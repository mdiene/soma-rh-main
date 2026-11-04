drop function if exists public.org_apply_reorg(jsonb, date, text);
-- team_loans_summary() : recréer depuis db/migrations/20261104190000_equipe_presence_prets.sql si les prêts doivent redevenir visibles.
notify pgrst, 'reload schema';
