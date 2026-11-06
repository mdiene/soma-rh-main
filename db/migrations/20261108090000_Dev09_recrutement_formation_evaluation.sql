-- =============================================================================
-- D-017 (QA, S5) : recrutement, formation, évaluation
-- Lot 9 : Recrutement, formation, évaluation (si validé)
-- =============================================================================
-- Objectifs :
--   1. Tables pour le module recrutement : offres, candidatures, candidats
--   2. Tables pour le module formation : formations, suivi, compétences
--   3. Tables pour le module évaluation : entretiens, notes, objectifs
--   4. Interface Mintlify pour chaque module
-- Retour : db/rollback/20261108090000_Dev09_recrutement_formation_évaluation_down.sql
-- =============================================================================
-- Note : ce lot n'est activé que si le propriétaire valide son inclusion.
-- =============================================================================
-- === Module : Recrutement ===
create table if not exists public.job_postulations (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  job_title text not null,
  department text,
  status text not null default 'en_attente' check (status in ('en_attente', 'approuvée', 'refusée')),
  source text,
  source_id uuid,
  created_at timestamp with time zone not null default now(),
  created_by uuid references auth.users(id) on delete set null
);

create index if not exists job_postulations_employee_idx on public.job_postulations(employee_id);

create table if not exists public.candidatures (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  job_postulation_id uuid not null references public.job_postulations(id) on delete cascade,
  status text not null default 'en_attente' check (status in ('en_attente', 'approuvée', 'refusée')),
  motivation text,
  created_at timestamp with time zone not null default now(),
  created_by uuid references auth.users(id) on delete set null
);

create index if not exists candidatures_employee_idx on public.candidatures(employee_id);
create index if not exists candidatures_job_postulation_idx on public.candidatures(job_postulation_id);

-- === Module : Formation ===
create table if not exists public.trainings (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  title text not null,
  description text,
  start_date date not null,
  end_date date,
  status text not null default 'en_cours' check (status in ('en_cours', 'terminé', 'abandonné')),
  notes text,
  created_at timestamp with time zone not null default now(),
  created_by uuid references auth.users(id) on delete set null
);

create index if not exists trainings_employee_idx on public.trainings(employee_id);

-- === Module : Évaluation ===
create table if not exists public.evaluations (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.employees(id) on delete cascade,
  evaluator text,
  period text,
  global_note numeric check (global_note between 0 and 20),
  commentaires text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone default now()
);

create index if not exists evaluations_employee_idx on public.evaluations(employee_id);

-- Retour : db/rollback/20261108090000_Dev09_recrutement_formation_evaluation_down.sql
