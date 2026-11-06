-- decide_leave refuse un utilisateur sans rôle sur l'étape (salarié simple, paie seule). Tout est annulé.
-- Attendu : "OK decide_leave_droits"
begin;
create temp table t_ctx as
select (select l.id from public.leave_applications l where l.status = 'Ouverte'
          and exists (select 1 from public.leave_approval_steps s where s.leave_id = l.id and s.status = 'En attente') order by l.id limit 1) as leave_id,
       (select e.user_id from public.employees e where e.user_id is not null
          and not exists (select 1 from public.user_roles r where r.user_id = e.user_id and r.role in ('rh','admin','manager')) order by e.id limit 1) as u_sal,
       (select user_id from public.user_roles where role = 'paie' and user_id not in (select user_id from public.user_roles where role in ('rh','admin','manager')) order by user_id limit 1) as u_paie;
grant select on t_ctx to authenticated;
do $$
declare c record; r text; u uuid;
begin
  select * into c from t_ctx;
  if c.leave_id is null or c.u_sal is null or c.u_paie is null then raise exception 'données de test manquantes : %', c; end if;
  foreach u in array array[c.u_sal, c.u_paie] loop
    execute 'reset role'; execute 'set local role authenticated';
    perform set_config('request.jwt.claim.sub', u::text, true);
    begin
      perform public.decide_leave(c.leave_id, 'Approuvée', 'test');
      raise exception 'décision acceptée pour %', u;
    exception when others then
      if sqlerrm not like '%revient%' and sqlerrm not like '%propre demande%' then raise exception 'autre erreur pour % : %', u, sqlerrm; end if;
    end;
  end loop;
  raise notice 'OK decide_leave_droits';
end $$;
rollback;
