-- M5 (gardiennage) : heures supplémentaires au-delà du seuil d'équivalence, depuis la grille de présences (working_hours).
-- Moteur de modules (M3) : opérateur JSONLogic « lookup » (valeur d'un paramètre objet par clé), variable presence_hours,
-- clés de règle facultatives requires_vars (règle ignorée si une variable manque) et skip_if_zero. compute_salary_slip n'est pas modifiée.
-- Retour : db/rollback/20261130090000_m5_equivalence_heures_sup_down.sql

create or replace function public.jl_eval(p_rule jsonb, p_vars jsonb) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare
  op text; args jsonb; n int; i int; ev jsonb[] := '{}'; acc numeric; t numeric; j jsonb;
begin
  if jsonb_typeof(p_rule) is distinct from 'object' then return p_rule; end if;
  select e.key, e.value into op, args from jsonb_each(p_rule) e limit 1;
  if op is null then return null; end if;
  if jsonb_typeof(args) <> 'array' then args := jsonb_build_array(args); end if;
  n := jsonb_array_length(args);

  if op = 'var' then                                   -- ["nom"] ou ["nom", défaut]
    j := nullif(p_vars -> (args ->> 0), 'null'::jsonb);
    return coalesce(j, args -> 1);
  end if;
  if op = 'lookup' then                               -- ["param", clé] : valeur de la clé dans un paramètre de type objet ; null si absente
    j := public.jl_eval(args -> 1, p_vars);
    return case when j is null then null else nullif((p_vars -> (args ->> 0)) -> (j #>> '{}'), 'null'::jsonb) end;
  end if;
  if op = 'if' then                                    -- évaluation paresseuse : cond, alors, [cond, alors]*, [sinon]
    i := 0;
    while i + 1 < n loop
      if public.jl_truthy(public.jl_eval(args -> i, p_vars)) then return public.jl_eval(args -> (i + 1), p_vars); end if;
      i := i + 2;
    end loop;
    return case when i < n then public.jl_eval(args -> i, p_vars) end;
  end if;
  if op = 'and' then
    for i in 0 .. n - 1 loop
      if not public.jl_truthy(public.jl_eval(args -> i, p_vars)) then return to_jsonb(false); end if;
    end loop;
    return to_jsonb(true);
  end if;
  if op = 'or' then
    for i in 0 .. n - 1 loop
      if public.jl_truthy(public.jl_eval(args -> i, p_vars)) then return to_jsonb(true); end if;
    end loop;
    return to_jsonb(false);
  end if;

  for i in 0 .. n - 1 loop ev := array_append(ev, public.jl_eval(args -> i, p_vars)); end loop;
  if op = '!' then return to_jsonb(not public.jl_truthy(ev[1])); end if;
  if op in ('==', '!=') then
    if ev[1] is null or ev[2] is null then return null; end if;
    return to_jsonb((ev[1] = ev[2]) = (op = '=='));
  end if;
  if op in ('+', '-', '*', '/', 'min', 'max', '<', '<=', '>', '>=') then
    if exists (select 1 from unnest(ev) x where x is null) then return null; end if;   -- valeur manquante : jamais 0
    acc := (ev[1] #>> '{}')::numeric;
    if op = '-' and n = 1 then return to_jsonb(-acc); end if;
    for i in 2 .. n loop
      t := (ev[i] #>> '{}')::numeric;
      if op in ('<', '<=', '>', '>=') then
        return to_jsonb(case op when '<' then acc < t when '<=' then acc <= t when '>' then acc > t else acc >= t end);
      end if;
      acc := case op when '+' then acc + t when '-' then acc - t when '*' then acc * t
                     when '/' then acc / nullif(t, 0) when 'min' then least(acc, t) else greatest(acc, t) end;
    end loop;
    return to_jsonb(acc);
  end if;
  raise exception 'opérateur JSONLogic inconnu : %', op;
end $$;

create or replace function public.module_payroll_adjustments(p_employee_id uuid, p_period date, p_hourly numeric) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  m record; r jsonb; v_par jsonb; v_inp jsonb; v_dat jsonb; v_vars jsonb; v_miss text[]; v_amt numeric; v_tax boolean;
  v_pres numeric; v_gross numeric := 0; v_nontax numeric := 0; v_lines jsonb := '[]'; v_finds jsonb := '[]';
begin
  for m in
    select mm.module_id, mm.name, mm.manifest from public.module_manifest mm
    where public.module_active_for(p_employee_id, mm.module_id, p_period) and mm.manifest ? 'payroll_rules'
    order by mm.module_id
  loop
    select coalesce(jsonb_object_agg(pv.param_key, pv.value), '{}') into v_par from public.module_parameter_value pv
     where pv.module_id = m.module_id and pv.value <> 'null'::jsonb
       and (pv.valid_from is null or pv.valid_from <= p_period) and (pv.valid_to is null or pv.valid_to > p_period);
    select coalesce(jsonb_object_agg(i.input_key, i.value), '{}') into v_inp from public.module_payroll_input i
     where i.employee_id = p_employee_id and i.module_id = m.module_id and i.period = p_period;
    select coalesce((select d.data from public.employee_module_data d where d.employee_id = p_employee_id and d.module_id = m.module_id
                      and (d.valid_from is null or d.valid_from <= p_period) and (d.valid_to is null or d.valid_to > p_period) limit 1), '{}')
      into v_dat;
    v_vars := v_dat || v_par || v_inp || jsonb_build_object('hourly_rate', p_hourly);
    -- heures de présence du mois saisies dans la grille de présences (absentes s'il n'y a aucune ligne de présence)
    select sum(coalesce(a.working_hours, 0)) into v_pres from public.attendance a
     where a.employee_id = p_employee_id and a.attendance_date >= p_period and a.attendance_date < (p_period + interval '1 month')::date;
    if v_pres is not null then v_vars := v_vars || jsonb_build_object('presence_hours', v_pres); end if;

    for r in select x from jsonb_array_elements(m.manifest -> 'payroll_rules') x loop
      -- pas de saisie pour cette règle sur la période : rien à calculer, rien à signaler
      if exists (select 1 from jsonb_array_elements_text(coalesce(r -> 'inputs', '[]')) k where not jsonb_exists(v_inp, k)) then continue; end if;
      if exists (select 1 from jsonb_array_elements_text(coalesce(r -> 'requires_vars', '[]')) k where not jsonb_exists(v_vars, k)) then continue; end if;
      select coalesce(array_agg(k), '{}') into v_miss from jsonb_array_elements_text(coalesce(r -> 'params', '[]')) k where not jsonb_exists(v_par, k);
      if cardinality(v_miss) > 0 then
        v_finds := v_finds || jsonb_build_object('module_id', m.module_id, 'rule_id', r ->> 'rule_id',
          'code', 'missing_parameter:' || v_miss[1], 'missing', to_jsonb(v_miss), 'severity', coalesce(r ->> 'severity', 'warning'));
        continue;
      end if;
      v_amt := public.jl_num(r -> 'logic', v_vars);
      if v_amt is null then
        v_finds := v_finds || jsonb_build_object('module_id', m.module_id, 'rule_id', r ->> 'rule_id',
          'code', 'missing_value', 'severity', coalesce(r ->> 'severity', 'warning'));
        continue;
      end if;
      if v_amt = 0 and coalesce((r ->> 'skip_if_zero')::boolean, false) then continue; end if;
      v_tax := coalesce((r ->> 'taxable')::boolean, true);
      if v_tax then v_gross := v_gross + v_amt; else v_nontax := v_nontax + v_amt; end if;
      v_lines := v_lines || jsonb_build_object('module_id', m.module_id, 'rule_id', r ->> 'rule_id', 'label', r ->> 'label',
        'amount', v_amt, 'taxable', v_tax, 'legal_ref', r ->> 'legal_ref', 'inputs', v_inp, 'params', v_par);
    end loop;
  end loop;
  return jsonb_build_object('gross', v_gross, 'non_taxable', v_nontax, 'lines', v_lines, 'findings', v_finds);
end $$;

revoke execute on function public.jl_eval(jsonb, jsonb), public.module_payroll_adjustments(uuid, date, numeric) from public, anon;
grant execute on function public.jl_eval(jsonb, jsonb), public.module_payroll_adjustments(uuid, date, numeric) to authenticated;
