-- M6 : planning métier. Modèles de postes lus dans les manifestes (planning_rules.shift_templates) des modules actifs,
-- planning par salarié et par jour, report dans les présences et la paie (heures de nuit), contrôle de conformité hebdomadaire.
-- compute_salary_slip n'est pas modifiée : le report passe par attendance (working_hours) et module_payroll_input (INP_NIGHT_HOURS).
-- Retour : db/rollback/20261202090000_m6_planning_metier_down.sql

create table public.module_shift (
  id          uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  work_date   date not null,
  module_id   text not null references public.module_manifest(module_id) on delete cascade,
  shift_code  text not null,
  hours       numeric not null check (hours >= 0 and hours <= 24),
  night_hours numeric not null default 0 check (night_hours >= 0 and night_hours <= hours),
  created_by  uuid default auth.uid() references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  unique (employee_id, work_date)
);
create index module_shift_module_idx on public.module_shift(module_id);
create index module_shift_date_idx on public.module_shift(work_date);
create index module_shift_created_by_idx on public.module_shift(created_by);

alter table public.module_shift enable row level security;
create policy module_shift_read on public.module_shift for select to authenticated
  using (employee_id = (select public.my_employee_id()) or (select public.has_role(array['rh','paie'])));
create policy module_shift_write on public.module_shift for all to authenticated
  using ((select public.has_role(array['rh','paie']))) with check ((select public.has_role(array['rh','paie'])));
create trigger module_shift_audit after insert or update or delete on public.module_shift
  for each row execute function public.business_audit();

-- Heures de nuit (22 h – 5 h, Code du travail 2026, art. 245) d'un poste défini par son début et sa fin ; fin <= début = lendemain.
create or replace function public.shift_night_hours(p_start time, p_end time) returns numeric
language sql immutable set search_path = '' as $$
  with s as (select extract(epoch from p_start) / 3600.0 as a,
                    extract(epoch from p_end) / 3600.0 + case when p_end <= p_start then 24 else 0 end as b)
  select coalesce(sum(greatest(0, least(s.b, w.hi) - greatest(s.a, w.lo))), 0)
  from s, (values (-2.0, 5.0), (22.0, 29.0), (46.0, 53.0)) as w(lo, hi)
$$;

-- Modèles de postes des modules actifs
create or replace function public.shift_templates()
returns table(module_id text, code text, label text, start_time time, end_time time, hours numeric, night_hours numeric)
language sql stable security definer set search_path = '' as $$
  select m.module_id, t->>'code', coalesce(t->>'label', t->>'code'),
         nullif(t->>'start', '')::time, nullif(t->>'end', '')::time,
         (t->>'duration_hours')::numeric,
         case when t ? 'start' and t ? 'end' then public.shift_night_hours((t->>'start')::time, (t->>'end')::time)
              else coalesce((t->>'night_hours')::numeric, 0) end
  from public.module_manifest m
  join public.module_activation a on a.module_id = m.module_id and a.enabled
  cross join lateral jsonb_array_elements(coalesce(m.manifest #> '{planning_rules,shift_templates}', '[]'::jsonb)) t
  where public.has_role(array['rh','paie']) and t ? 'code' and t ? 'duration_hours'
$$;

-- Planifier : [{employee_id, work_date, code}] ; code vide ou null = suppression du poste du jour.
create or replace function public.plan_shifts(p_rows jsonb) returns integer
language plpgsql security definer set search_path = '' as $$
declare r jsonb; t record; n int := 0; v_emp uuid; v_date date; v_code text;
begin
  if not public.has_role(array['rh','paie']) then raise exception 'Droits insuffisants : rôle « rh » ou « paie » requis'; end if;
  for r in select x from jsonb_array_elements(p_rows) x loop
    v_emp := (r->>'employee_id')::uuid; v_date := (r->>'work_date')::date; v_code := nullif(btrim(r->>'code'), '');
    if v_code is null then
      delete from public.module_shift where employee_id = v_emp and work_date = v_date;
    else
      select * into t from public.shift_templates() st where st.code = v_code;
      if t.code is null then raise exception 'Modèle de poste inconnu ou module éteint : %', v_code using errcode = 'check_violation'; end if;
      insert into public.module_shift(employee_id, work_date, module_id, shift_code, hours, night_hours)
        values (v_emp, v_date, t.module_id, t.code, t.hours, t.night_hours)
      on conflict (employee_id, work_date) do update
        set module_id = excluded.module_id, shift_code = excluded.shift_code, hours = excluded.hours, night_hours = excluded.night_hours;
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;

-- Reporter le planning d'un mois : présences manquantes créées (jamais d'écrasement d'une présence saisie) et heures de nuit en saisie de période.
create or replace function public.apply_planning(p_period date) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_start date := date_trunc('month', p_period)::date; v_end date := (date_trunc('month', p_period) + interval '1 month')::date;
        v_att int; v_night int;
begin
  if not public.has_role(array['rh','paie']) then raise exception 'Droits insuffisants : rôle « rh » ou « paie » requis'; end if;
  insert into public.attendance(employee_id, attendance_date, status, working_hours)
    select s.employee_id, s.work_date, 'Présent', s.hours from public.module_shift s
    where s.work_date >= v_start and s.work_date < v_end and s.hours > 0
  on conflict (employee_id, attendance_date) do nothing;
  get diagnostics v_att = row_count;

  insert into public.module_payroll_input(employee_id, period, module_id, input_key, value)
    select s.employee_id, v_start, s.module_id, 'INP_NIGHT_HOURS', sum(s.night_hours)
    from public.module_shift s
    where s.work_date >= v_start and s.work_date < v_end
    group by s.employee_id, s.module_id having sum(s.night_hours) > 0
  on conflict (employee_id, period, module_id, input_key) do update set value = excluded.value;
  get diagnostics v_night = row_count;
  return jsonb_build_object('attendance_created', v_att, 'night_inputs', v_night);
end $$;

-- Conformité du planning par semaine ISO : durée hebdomadaire (seuil d'équivalence de la catégorie, sinon 40 h) et repos hebdomadaire.
create or replace function public.planning_compliance(p_from date, p_to date)
returns table(code text, severity text, employee_id uuid, employee_name text, week_start date, message text)
language sql stable security definer set search_path = '' as $$
  with w as (
    select s.employee_id, date_trunc('week', s.work_date)::date as wk, sum(s.hours) as hrs, count(*) as days
    from public.module_shift s where s.work_date between p_from and p_to group by 1, 2
  ), thr as (
    select (select (v.value #>> '{}')::numeric from public.module_parameter_value v
             where v.module_id = 'soma-mod-securite-gardiennage-sn' and v.param_key = 'weekly_legal_hours' limit 1) as legal,
           (select v.value from public.module_parameter_value v
             where v.module_id = 'soma-mod-securite-gardiennage-sn' and v.param_key = 'equivalence_thresholds' limit 1) as eq
  ), lim as (
    select w.*, e.last_name || ' ' || e.first_name as nm,
           coalesce((((select t.eq from thr t) -> (select d.data->>'sec_categorie_poste' from public.employee_module_data d
                      where d.employee_id = w.employee_id and d.module_id = 'soma-mod-securite-gardiennage-sn' limit 1)) #>> '{}')::numeric,
                    (select t.legal from thr t), 40) as max_h
    from w join public.employees e on e.id = w.employee_id
  )
  select 'duree_hebdo_depassee'::text, 'alerte'::text, l.employee_id, l.nm, l.wk,
         'Semaine du ' || to_char(l.wk, 'DD/MM/YYYY') || ' : ' || l.hrs || ' h planifiées pour un seuil de ' || l.max_h || ' h (heures supplémentaires à prévoir)'
  from lim l where public.has_role(array['rh','paie']) and l.hrs > l.max_h
  union all
  select 'repos_hebdo_manquant', 'erreur', l.employee_id, l.nm, l.wk,
         'Semaine du ' || to_char(l.wk, 'DD/MM/YYYY') || ' : aucun jour de repos planifié (repos hebdomadaire de 24 h, Code du travail 2026, art. 246)'
  from lim l where public.has_role(array['rh','paie']) and l.days >= 7
$$;

revoke execute on function public.shift_templates(), public.plan_shifts(jsonb), public.apply_planning(date),
  public.planning_compliance(date, date), public.shift_night_hours(time, time) from public, anon;
grant execute on function public.shift_templates(), public.plan_shifts(jsonb), public.apply_planning(date),
  public.planning_compliance(date, date), public.shift_night_hours(time, time) to authenticated;
