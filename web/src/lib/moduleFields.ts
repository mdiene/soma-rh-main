/** Normalise les `custom_fields` des manifestes (deux écritures coexistent : gardiennage = liste `field_key/data_type`,
 *  intérim = objet `worker_profile` avec `field_id/type`) en une description unique pour ModuleForm. */
export type FieldType = 'string' | 'number' | 'boolean' | 'date' | 'enum'
export type ModuleField = {
  key: string; label: string; type: FieldType
  required: boolean; requiredIf?: string
  options?: string[]          // enum : valeurs fixes ou tirées d'un paramètre ; absent = saisie libre
  def?: unknown; legalRef?: string; note?: string
}

type Raw = Record<string, unknown>
const TYPES: Record<string, FieldType> = { string: 'string', number: 'number', boolean: 'boolean', date: 'date' }

/** Seuls les champs du salarié : la liste à plat, ou `worker_profile` (les profils d'agence ne sont pas des champs salarié). */
export function employeeFields(customFields: unknown, parameters: Raw = {}): ModuleField[] {
  const raw: Raw[] = Array.isArray(customFields)
    ? (customFields as Raw[]).filter((f) => !f.target_entity || f.target_entity === 'Employee' || f.target_entity === 'Contract')
    : Array.isArray((customFields as Raw | null)?.worker_profile) ? ((customFields as Raw).worker_profile as Raw[]) : []
  return raw.flatMap((f) => {
    const key = (f.field_key ?? f.field_id) as string | undefined
    if (!key) return []
    const fixed = f.enum as string[] | undefined
    const src = typeof f.enum_source === 'string' ? f.enum_source.replace(/^parameters\./, '') : undefined
    const fromParam = src ? (parameters[src] as Raw | undefined)?.value : undefined
    const options = fixed ?? (fromParam && typeof fromParam === 'object' ? Object.keys(fromParam) : undefined)
    const t = String(f.data_type ?? f.type ?? 'string').toLowerCase()
    const validation = f.validation as Raw | undefined
    return [{
      key, label: String(f.label ?? key),
      type: fixed || src ? 'enum' : TYPES[t] ?? 'string',
      required: f.required === true, requiredIf: f.required_if as string | undefined,
      options, def: f.default_value ?? f.default,
      legalRef: f.legal_ref as string | undefined, note: validation?.note as string | undefined,
    }]
  })
}

/** Évalue `champ == true|false|'x'` (seule forme utilisée par les manifestes). */
export function requiredNow(f: ModuleField, data: Record<string, unknown>): boolean {
  if (f.required) return true
  const m = f.requiredIf?.match(/^\s*(\w+)\s*==\s*(true|false|'[^']*')\s*$/)
  if (!m) return false
  const want = m[2] === 'true' ? true : m[2] === 'false' ? false : m[2].slice(1, -1)
  return (data[m[1]] ?? false) === want
}

export const missingRequired = (fields: ModuleField[], data: Record<string, unknown>) =>
  fields.filter((f) => requiredNow(f, data) && (data[f.key] === undefined || data[f.key] === null || data[f.key] === ''))
