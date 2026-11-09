import { createClient, type Session, type SupabaseClient } from '@supabase/supabase-js'
import type { Database } from './database.types'

// Seul fichier qui connaît la bibliothèque cliente (PostgREST + authentification locale).
export type ApiClient = SupabaseClient
export type ApiSession = Session

const url = import.meta.env.VITE_API_URL as string
const key = import.meta.env.VITE_API_PUBLIC_KEY as string

if (!url || !key) {
  throw new Error('Configuration manquante : renseignez VITE_API_URL et VITE_API_PUBLIC_KEY dans web/.env.local')
}

export const dataApi = createClient<Database>(url, key, {
  auth: { persistSession: true, autoRefreshToken: true },
})

// Documents : « gateway » (défaut, version locale : fichiers servis par la passerelle /api/v1) ou
// « supabase » (version en ligne : Supabase Storage, bucket privé « employee-documents »).
export const documentsOnStorage = import.meta.env.VITE_DOCUMENTS_MODE === 'supabase'
const BUCKET = 'employee-documents'

async function sha256Hex(file: File) {
  const digest = await crypto.subtle.digest('SHA-256', await file.arrayBuffer())
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, '0')).join('')
}

async function storageDocument(documentId: string) {
  const row = unwrap(await dataApi.from('employee_documents').select('storage_path, file_name, mime_type').eq('id', documentId).maybeSingle())
  return row
}

async function uploadToStorage(employeeId: string, requirementCode: string, file: File, documentSlot: number) {
  const path = `${employeeId}/${requirementCode}-${crypto.randomUUID()}-${file.name.normalize('NFKC').replace(/[^a-zA-Z0-9._-]/g, '_').slice(0, 120)}`
  const up = await dataApi.storage.from(BUCKET).upload(path, file, { contentType: file.type, upsert: false })
  if (up.error) throw new Error(up.error.message)
  const { data, error } = await dataApi.rpc('register_employee_document', {
    p_employee_id: employeeId, p_requirement_code: requirementCode, p_slot: documentSlot, p_storage_path: path,
    p_file_name: file.name, p_mime_type: file.type, p_size_bytes: file.size, p_checksum: await sha256Hex(file),
  })
  if (error) {
    await dataApi.storage.from(BUCKET).remove([path])
    throw new Error(error.message)
  }
  return data
}

export async function uploadEmployeeDocument(employeeId: string, requirementCode: string, file: File, documentSlot = 1) {
  if (documentsOnStorage) return uploadToStorage(employeeId, requirementCode, file, documentSlot)
  const { data } = await dataApi.auth.getSession()
  const token = data.session?.access_token
  if (!token) throw new Error('Session expirée, reconnectez-vous.')
  const fileName = btoa(unescape(encodeURIComponent(file.name)))
  const response = await fetch(`${url}/api/v1/documents/upload`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${token}`,
      'x-employee-id': employeeId,
      'x-requirement-code': requirementCode,
      'x-document-slot': String(documentSlot),
      'x-file-name': fileName,
      'x-file-mime': file.type,
      'content-type': 'application/octet-stream',
    },
    body: file,
  })
  const result = await response.json() as { message?: string; document?: unknown }
  if (!response.ok) throw new Error(result.message ?? 'Le dépôt du document a échoué.')
  return result.document
}

export async function openEmployeeDocument(documentId: string) {
  const blobUrl = await getEmployeeDocumentBlobUrl(documentId)
  window.open(blobUrl, '_blank', 'noopener,noreferrer')
  window.setTimeout(() => URL.revokeObjectURL(blobUrl), 60_000)
}

export function getEmployeeDocumentUrl(documentId: string) {
  return `${url}/api/v1/documents/${documentId}`
}

export function getEmployeeDocumentThumbnailUrl(documentId: string) {
  return `${url}/api/v1/documents/${documentId}/thumbnail`
}

export async function getEmployeeDocumentBlobUrl(documentId: string) {
  if (documentsOnStorage) {
    const doc = await storageDocument(documentId)
    if (!doc) throw new Error('Le document est indisponible.')
    const { data, error } = await dataApi.storage.from(BUCKET).download(doc.storage_path)
    if (error) throw new Error(error.message)
    await dataApi.rpc('log_employee_document_access', { p_document_id: documentId })
    return URL.createObjectURL(data)
  }
  return getPrivateBlobUrl(getEmployeeDocumentUrl(documentId), 'Le document est indisponible.')
}

export async function getEmployeeDocumentThumbnailBlobUrl(documentId: string) {
  if (documentsOnStorage) {
    // Miniature simplifiée en ligne : l'image elle-même pour JPEG/PNG, sinon l'écran affiche le type de fichier.
    const doc = await storageDocument(documentId)
    if (!doc || !doc.mime_type.startsWith('image/')) throw new Error('Pas de miniature')
    const { data, error } = await dataApi.storage.from(BUCKET).download(doc.storage_path)
    if (error) throw new Error(error.message)
    return URL.createObjectURL(data)
  }
  return getPrivateBlobUrl(getEmployeeDocumentThumbnailUrl(documentId), 'La miniature est indisponible.')
}

export async function openEmployeeDocumentsBundle(employeeId: string) {
  if (documentsOnStorage) throw new Error("Le dossier PDF n'est pas disponible en ligne.")
  const popup = window.open('', '_blank')
  if (!popup) throw new Error('Autorisez les fenêtres contextuelles pour ouvrir le dossier PDF.')
  popup.opener = null
  try {
    const { data } = await dataApi.auth.getSession()
    const token = data.session?.access_token
    if (!token) throw new Error('Session expirée, reconnectez-vous.')
    const response = await fetch(`${url}/api/v1/employees/${employeeId}/documents/bundle`, { headers: { authorization: `Bearer ${token}` } })
    if (!response.ok) {
      const result = await response.json() as { message?: string }
      throw new Error(result.message ?? 'Le dossier PDF est indisponible.')
    }
    const blobUrl = URL.createObjectURL(await response.blob())
    popup.location.href = blobUrl
    window.setTimeout(() => URL.revokeObjectURL(blobUrl), 60_000)
  } catch (error) {
    popup.close()
    throw error
  }
}

async function getPrivateBlobUrl(resourceUrl: string, fallbackMessage: string) {
  const { data } = await dataApi.auth.getSession()
  const token = data.session?.access_token
  if (!token) throw new Error('Session expirée, reconnectez-vous.')
  const response = await fetch(resourceUrl, { headers: { authorization: `Bearer ${token}` } })
  if (!response.ok) {
    const result = await response.json() as { message?: string }
    throw new Error(result.message ?? fallbackMessage)
  }
  return URL.createObjectURL(await response.blob())
}

export async function reviewEmployeeDocument(documentId: string, status: 'valide' | 'refuse', reason?: string) {
  const { data, error } = await dataApi.rpc('review_employee_document', {
    p_document_id: documentId,
    p_status: status,
    p_reason: reason ?? undefined,
  })
  if (error) throw new Error(error.message)
  return data
}

export async function archiveEmployeeDocument(documentId: string) {
  const { data, error } = await dataApi.rpc('archive_employee_document', { p_document_id: documentId })
  if (error) throw new Error(error.message)
  return data
}

export async function deleteEmployeeDocument(documentId: string) {
  if (documentsOnStorage) {
    const { data, error } = await dataApi.rpc('delete_employee_document', { p_document_id: documentId })
    if (error) throw new Error(error.message)
    await dataApi.storage.from(BUCKET).remove(data as string[])
    return { deleted: true }
  }
  const { data } = await dataApi.auth.getSession()
  const token = data.session?.access_token
  if (!token) throw new Error('Session expirée, reconnectez-vous.')
  const response = await fetch(getEmployeeDocumentUrl(documentId), {
    method: 'DELETE',
    headers: { authorization: `Bearer ${token}` },
  })
  const result = await response.json() as { message?: string }
  if (!response.ok) throw new Error(result.message ?? 'La suppression du document a échoué.')
  return result
}

export type Tables<T extends keyof Database['public']['Tables']> = Database['public']['Tables'][T]['Row']
export type Views<T extends keyof Database['public']['Views']> = Database['public']['Views'][T]['Row']

/** Copie d'un objet sans certaines clés (ex. colonnes gérées par la base). */
export function omit<T extends object, K extends keyof T>(obj: T, ...keys: K[]): Omit<T, K> {
  const copy = { ...obj }
  for (const k of keys) delete copy[k]
  return copy
}

/** Lève une erreur lisible si la requête échoue. */
export function unwrap<R extends { data: unknown; error: { message: string } | null }>(res: R): NonNullable<R['data']> {
  if (res.error) throw new Error(res.error.message)
  return res.data as NonNullable<R['data']>
}

/** Refus d'une transition de paie : `code` vaut 'SD403' quand la séparation des tâches s'applique. */
export class PayrollRefusal extends Error {
  code?: string
  constructor(message: string, code?: string) { super(message); this.code = code }
}

/** Fait avancer une paie par la RPC qui journalise aussi les refus (L1-02). */
export async function transitionPayroll(id: string, status: string, reason?: string | null) {
  const res = unwrap(await dataApi.rpc('try_transition_payroll_entry', {
    p_payroll_entry_id: id, p_target_status: status, p_reason: reason?.trim() || undefined,
  })) as unknown as { ok: boolean; message?: string; code?: string }
  if (!res.ok) throw new PayrollRefusal(res.message ?? 'Transition refusée', res.code)
  return res
}

/** Statuts d'une paie que l'administrateur peut faire reculer (pour la corriger ou la supprimer). */
export const REVERTIBLE = ['En revue', 'Approuvée', 'Validée', 'Payée', 'Clôturée']

/** États d'un traitement dont les bulletins sont validés (un mois payé ou clôturé reste un mois validé). */
export const VALIDATED_STATUSES = ['Validée', 'Payée', 'Clôturée']
export const isPayrollValidated = (status: string) => VALIDATED_STATUSES.includes(status)
