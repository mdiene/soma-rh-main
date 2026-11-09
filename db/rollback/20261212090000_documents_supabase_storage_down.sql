-- Retour : retire les fonctions de dépôt/suppression et, sur Supabase, les politiques du bucket (le bucket et ses fichiers sont conservés).
drop function if exists public.register_employee_document(uuid, text, integer, text, text, text, bigint, text);
drop function if exists public.delete_employee_document(uuid);
do $$
begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists employee_documents_read on storage.objects;
    drop policy if exists employee_documents_write on storage.objects;
    drop policy if exists employee_documents_remove on storage.objects;
  end if;
end $$;
notify pgrst, 'reload schema';
