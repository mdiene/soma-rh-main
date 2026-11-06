-- Retour proposé : recrutement, formation, évaluation. Ordre inverse des clés étrangères (candidatures dépend de job_postulations).
drop table if exists public.evaluations;
drop table if exists public.trainings;
drop table if exists public.candidatures;
drop table if exists public.job_postulations;
notify pgrst, 'reload schema';
