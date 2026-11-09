-- Retour : supprime les modèles de documents (les attestations reviennent au texte de secours du code).
drop table if exists public.document_templates;
drop function if exists public.document_templates_stamp();
notify pgrst, 'reload schema';
