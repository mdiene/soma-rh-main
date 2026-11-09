-- =============================================================================
-- Documents salariés sans passerelle : deux fonctions RPC (dépôt, suppression) qui reprennent les règles de api/server.mjs,
-- et, si le schéma `storage` existe (Supabase), un bucket privé « employee-documents » avec ses politiques.
-- Chemin d'un objet : <employee_id>/<fichier>. Sur la base locale (sans schéma storage) seules les fonctions sont créées.
-- Retour : db/rollback/20261212090000_documents_supabase_storage_down.sql
-- =============================================================================
create or replace function public.register_employee_document(
  p_employee_id uuid, p_requirement_code text, p_slot integer, p_storage_path text,
  p_file_name text, p_mime_type text, p_size_bytes bigint, p_checksum text default null)
returns public.employee_documents
language plpgsql security definer set search_path = ''
as $$
declare
  v_req public.document_requirements;
  v_cur public.employee_documents;
  v_doc public.employee_documents;
  v_version integer;
  v_slot integer := greatest(coalesce(p_slot, 1), 1);
begin
  if (select auth.uid()) is null then raise exception 'Authentification requise'; end if;
  if not (public.has_role(array['rh']) or p_employee_id = (select public.my_employee_id())) then
    raise exception 'Accès interdit à ce dossier';
  end if;
  select * into v_req from public.document_requirements where code = p_requirement_code and active;
  if not found then raise exception 'Type de document inconnu'; end if;
  if not (p_mime_type = any(v_req.allowed_mime_types)) then raise exception 'Format non autorisé pour ce document'; end if;
  if p_size_bytes <= 0 or p_size_bytes > least(v_req.max_size_bytes, 10 * 1024 * 1024) then
    raise exception 'Taille de fichier invalide (10 Mo maximum)';
  end if;
  if p_storage_path not like p_employee_id::text || '/%' then raise exception 'Chemin de stockage invalide'; end if;

  select * into v_cur from public.employee_documents
   where employee_id = p_employee_id and requirement_code = p_requirement_code and document_slot = v_slot and archived_at is null
   for update;
  if found then
    v_version := v_cur.current_version + 1;
    update public.employee_documents
       set file_name = p_file_name, storage_path = p_storage_path, mime_type = p_mime_type, size_bytes = p_size_bytes,
           checksum = p_checksum, thumbnail_path = null, status = 'en_attente', rejection_reason = null,
           validated_by = null, validated_at = null, current_version = v_version, submitted_at = now(),
           archived_at = null, archived_by = null
     where id = v_cur.id returning * into v_doc;
  else
    v_version := 1;
    insert into public.employee_documents
      (employee_id, document_type, requirement_code, document_slot, title, file_name, storage_path, mime_type, size_bytes,
       checksum, created_by, status, current_version, submitted_at)
    values (p_employee_id, p_requirement_code, p_requirement_code,
            case when p_requirement_code in ('situation_matrimoniale', 'actes_enfants') then v_slot else 1 end,
            v_req.title, p_file_name, p_storage_path, p_mime_type, p_size_bytes, p_checksum, (select auth.uid()),
            'en_attente', 1, now())
    returning * into v_doc;
  end if;
  insert into public.document_versions (document_id, version_number, storage_path, file_name, mime_type, size_bytes, checksum, uploaded_by)
  values (v_doc.id, v_version, p_storage_path, p_file_name, p_mime_type, p_size_bytes, p_checksum, (select auth.uid()));
  return v_doc;
end;
$$;

-- Supprime le document (RH/admin) et renvoie les chemins des fichiers à retirer du stockage.
create or replace function public.delete_employee_document(p_document_id uuid)
returns text[]
language plpgsql security definer set search_path = ''
as $$
declare v_paths text[];
begin
  if not public.has_role(array['rh']) then raise exception 'Document introuvable ou non autorisé'; end if;
  select array_agg(distinct p) into v_paths from (
    select storage_path p from public.employee_documents where id = p_document_id
    union select storage_path from public.document_versions where document_id = p_document_id) s;
  if v_paths is null then raise exception 'Document introuvable ou non autorisé'; end if;
  delete from public.employee_documents where id = p_document_id;
  return v_paths;
end;
$$;

revoke all on function public.register_employee_document(uuid, text, integer, text, text, text, bigint, text) from public, anon;
revoke all on function public.delete_employee_document(uuid) from public, anon;
grant execute on function public.register_employee_document(uuid, text, integer, text, text, text, bigint, text) to authenticated;
grant execute on function public.delete_employee_document(uuid) to authenticated;

-- Stockage Supabase uniquement
do $$
begin
  if to_regclass('storage.objects') is null then return; end if;
  insert into storage.buckets (id, name, public) values ('employee-documents', 'employee-documents', false) on conflict (id) do nothing;
  drop policy if exists employee_documents_read on storage.objects;
  drop policy if exists employee_documents_write on storage.objects;
  drop policy if exists employee_documents_remove on storage.objects;
  create policy employee_documents_read on storage.objects for select to authenticated
    using (bucket_id = 'employee-documents'
           and (public.has_role(array['rh']) or (storage.foldername(name))[1] = (select public.my_employee_id())::text));
  create policy employee_documents_write on storage.objects for insert to authenticated
    with check (bucket_id = 'employee-documents'
           and (public.has_role(array['rh']) or (storage.foldername(name))[1] = (select public.my_employee_id())::text));
  create policy employee_documents_remove on storage.objects for delete to authenticated
    using (bucket_id = 'employee-documents' and public.has_role(array['rh']));
end $$;

notify pgrst, 'reload schema';
