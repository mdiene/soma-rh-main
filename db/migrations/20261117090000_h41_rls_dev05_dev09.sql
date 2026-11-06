-- =============================================================================
-- H41 : RLS manquante sur les tables des migrations Dev05 et Dev09 (données personnelles)
--   notifications_log, job_postulations, candidatures, trainings, evaluations
-- Règles : RH = gestion complète ; salarié = lecture de ses propres formations et candidatures
--          (my_employee_id()) et de ses propres notifications ; évaluations réservées à la RH ;
--          paie = lecture des notifications et écriture (envoi) sur notifications_log.
-- Index manquants sur les clés étrangères created_by.
-- Retour : db/rollback/20261117090000_h41_rls_dev05_dev09_down.sql
-- =============================================================================
create index if not exists job_postulations_created_by_idx on public.job_postulations(created_by);
create index if not exists candidatures_created_by_idx     on public.candidatures(created_by);
create index if not exists trainings_created_by_idx        on public.trainings(created_by);

alter table public.notifications_log enable row level security;
alter table public.job_postulations  enable row level security;
alter table public.candidatures      enable row level security;
alter table public.trainings         enable row level security;
alter table public.evaluations       enable row level security;

-- notifications_log
create policy notifications_log_read on public.notifications_log for select to authenticated
  using (user_id = (select auth.uid()) or (select public.has_role(array['rh','paie'])));
create policy notifications_log_ins  on public.notifications_log for insert to authenticated
  with check ((select public.has_role(array['rh','paie'])));
create policy notifications_log_upd  on public.notifications_log for update to authenticated
  using ((select public.has_role(array['rh','paie']))) with check ((select public.has_role(array['rh','paie'])));
create policy notifications_log_del  on public.notifications_log for delete to authenticated
  using ((select public.has_role(array['rh'])));

-- job_postulations (offres internes) : RH seulement
create policy job_postulations_rh on public.job_postulations for all to authenticated
  using ((select public.has_role(array['rh']))) with check ((select public.has_role(array['rh'])));

-- candidatures : RH complet, salarié en lecture de ses lignes
create policy candidatures_read on public.candidatures for select to authenticated
  using (employee_id = (select public.my_employee_id()) or (select public.has_role(array['rh'])));
create policy candidatures_ins  on public.candidatures for insert to authenticated with check ((select public.has_role(array['rh'])));
create policy candidatures_upd  on public.candidatures for update to authenticated
  using ((select public.has_role(array['rh']))) with check ((select public.has_role(array['rh'])));
create policy candidatures_del  on public.candidatures for delete to authenticated using ((select public.has_role(array['rh'])));

-- trainings : RH complet, salarié en lecture de ses lignes
create policy trainings_read on public.trainings for select to authenticated
  using (employee_id = (select public.my_employee_id()) or (select public.has_role(array['rh'])));
create policy trainings_ins  on public.trainings for insert to authenticated with check ((select public.has_role(array['rh'])));
create policy trainings_upd  on public.trainings for update to authenticated
  using ((select public.has_role(array['rh']))) with check ((select public.has_role(array['rh'])));
create policy trainings_del  on public.trainings for delete to authenticated using ((select public.has_role(array['rh'])));

-- evaluations : RH seulement
create policy evaluations_rh on public.evaluations for all to authenticated
  using ((select public.has_role(array['rh']))) with check ((select public.has_role(array['rh'])));

revoke all on public.notifications_log, public.job_postulations, public.candidatures, public.trainings, public.evaluations from anon;
notify pgrst, 'reload schema';
