-- =============================================================================
-- L6-04 : modèles de documents (attestations) modifiables par la RH.
-- Le corps est un texte brut : paragraphes séparés par une ligne vide, champs {{nom_du_champ}}
-- remplacés à l'impression (liste dans web/src/lib/documentTemplates.ts). Aucune donnée salarié n'est stockée ici.
-- Retour : db/rollback/20261205090000_document_templates_down.sql
-- =============================================================================
create table public.document_templates (
  code        text primary key check (code ~ '^[a-z0-9_]+$'),
  title       text not null check (length(btrim(title)) > 0),
  body        text not null check (length(btrim(body)) > 0 and length(body) <= 20000),
  version     integer not null default 1,
  updated_by  uuid default auth.uid() references auth.users(id) on delete set null,
  updated_at  timestamptz not null default now()
);
create index document_templates_updated_by_idx on public.document_templates(updated_by);

alter table public.document_templates enable row level security;
create policy document_templates_read on public.document_templates for select to authenticated
  using ((select public.has_role(array['rh','paie'])));
create policy document_templates_write on public.document_templates for all to authenticated
  using ((select public.has_role(array['rh']))) with check ((select public.has_role(array['rh'])));

-- version +1 et auteur à chaque modification du texte
create or replace function public.document_templates_stamp() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then new.version := old.version + 1; end if;
  new.updated_by := auth.uid();
  new.updated_at := now();
  return new;
end $$;
revoke execute on function public.document_templates_stamp() from public, anon, authenticated;
create trigger document_templates_stamp before insert or update on public.document_templates
  for each row execute function public.document_templates_stamp();
create trigger document_templates_audit after insert or update or delete on public.document_templates
  for each row execute function public.business_audit();

-- Modèles de départ : le texte qui était écrit en dur dans AttestationModal
insert into public.document_templates (code, title, body) values
('attestation_travail', 'Attestation de travail',
 E'Nous soussignés, {{societe}}, attestons que {{civilite}} {{prenom}} {{nom}}{{naissance}}, matricule {{matricule}}, {{etat}} {{employe}} au sein de notre société{{fonction}} depuis le {{date_embauche}}{{fin}}.\n\n{{effectif}}\n\nLa présente attestation est délivrée à l''intéressé{{e}}, sur sa demande, pour servir et valoir ce que de droit.'),
('attestation_salaire', 'Attestation de salaire',
 E'Nous soussignés, {{societe}}, attestons que {{civilite}} {{prenom}} {{nom}}{{naissance}}, matricule {{matricule}}, {{etat}} {{employe}} au sein de notre société{{fonction}} depuis le {{date_embauche}}{{fin}}.\n\n{{salaire}}\n\nLa présente attestation est délivrée à l''intéressé{{e}}, sur sa demande, pour servir et valoir ce que de droit.')
on conflict (code) do nothing;

notify pgrst, 'reload schema';
