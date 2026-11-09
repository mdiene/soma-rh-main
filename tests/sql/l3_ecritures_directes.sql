-- L3 : les écritures directes sur les constantes et barèmes sont réservées à l'administrateur ; le rh et la paie lisent et passent par des demandes.
-- Tout est annulé. Usage : psql -v ON_ERROR_STOP=1 -f tests/sql/l3_ecritures_directes.sql  (attendu : "OK l3_ecritures_directes")
begin;
create temp table t_ctx as
select
  (select user_id from public.user_roles where role = 'admin' order by user_id limit 1) as user_admin,
  (select user_id from public.user_roles where role = 'rh' and user_id not in (select user_id from public.user_roles where role = 'admin') order by user_id limit 1) as user_rh,
  (select user_id from public.user_roles where role = 'paie' and user_id not in (select user_id from public.user_roles where role = 'admin') order by user_id limit 1) as user_paie;
grant select on t_ctx to authenticated;
create or replace function pg_temp.as_user(p_user uuid) returns void language plpgsql as $$
begin
  execute 'reset role'; execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', p_user::text, true);
end $$;
do $$
declare
  c record; t text; n int; v_floor date; u uuid; v_cnt_before int;
  v_tables text[] := array['payroll_settings', 'tax_slabs', 'tax_slab_brackets', 'ir_family_reductions', 'trimf_brackets',
                           'overtime_rates', 'notice_scales', 'garnishment_scale', 'severance_scales'];
begin
  select * into c from t_ctx;
  if c.user_admin is null or c.user_rh is null or c.user_paie is null then raise exception 'FAIL : comptes admin / rh / paie introuvables'; end if;
  v_floor := coalesce(public.parameters_min_effective_date(), date_trunc('month', current_date)::date);

  -- 1. lecture conservée pour rh et paie
  foreach u in array array[c.user_rh, c.user_paie] loop
    perform pg_temp.as_user(u);
    foreach t in array v_tables loop
      execute format('select count(*) from public.%I', t) into n;
      if n = 0 then raise exception 'FAIL : % illisible ou vide pour un rôle de gestion', t; end if;
    end loop;
  end loop;

  -- 2. écriture directe refusée au rh et à la paie : aucune ligne modifiée ni créée (la RLS filtre sans lever d'erreur sur update / delete)
  foreach u in array array[c.user_rh, c.user_paie] loop
    perform pg_temp.as_user(u);
    foreach t in array v_tables loop
      begin
        execute format('insert into public.%I select * from public.%I limit 1', t, t);
        raise exception 'FAIL : insertion directe acceptée dans % pour un rôle non administrateur', t;
      exception when others then
        if sqlerrm like 'FAIL%' then raise; end if;   -- toute autre erreur (RLS, doublon) est un refus
      end;
    end loop;
    execute 'update public.payroll_settings set css_ceiling = css_ceiling + 1';
    get diagnostics n = row_count;
    if n <> 0 then raise exception 'FAIL : modification directe de payroll_settings acceptée (% lignes)', n; end if;
    execute 'delete from public.overtime_rates';
    get diagnostics n = row_count;
    if n <> 0 then raise exception 'FAIL : suppression directe de overtime_rates acceptée (% lignes)', n; end if;
  end loop;

  -- 3. la demande reste ouverte à rh et à la paie, l'administrateur écrit toujours
  perform pg_temp.as_user(c.user_paie);
  perform public.request_parameter_change('css_ceiling', 72000, v_floor);
  perform pg_temp.as_user(c.user_admin);
  select count(*) into v_cnt_before from public.payroll_settings;
  execute format('insert into public.payroll_settings select (jsonb_populate_record(s, jsonb_build_object(''id'', gen_random_uuid(), ''effective_from'', %L))).* from public.payroll_settings_at(%L) s',
                 (v_floor + interval '2 months')::date, v_floor);
  if (select count(*) from public.payroll_settings) <> v_cnt_before + 1 then raise exception 'FAIL : l''administrateur n''écrit plus directement'; end if;
  raise notice 'OK l3_ecritures_directes';
end $$;
rollback;
