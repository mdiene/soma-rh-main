import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { dataApi, unwrap } from '../lib/api'
import { useAuth } from '../lib/auth'
import { employeeFields, missingRequired, requiredNow, type ModuleField } from '../lib/moduleFields'
import { Button, ErrorNote, Section, SelectField, TextField } from './ui'

type Mod = { module_id: string; name: string; manifest: { custom_fields?: unknown; parameters?: Record<string, unknown> } }
type Data = Record<string, unknown>

/** Formulaire généré depuis les `custom_fields` d'un manifeste. */
export function ModuleForm({ fields, data, onChange, disabled }: {
  fields: ModuleField[]; data: Data; onChange: (key: string, v: unknown) => void; disabled?: boolean
}) {
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      {fields.map((f) => {
        const value = data[f.key] ?? f.def
        const hint = [f.legalRef, f.note].filter(Boolean).join(' · ') || undefined
        const label = f.label + (requiredNow(f, data) ? ' *' : '')
        if (f.type === 'boolean') {
          return (
            <label key={f.key} className="flex items-center gap-2 text-sm sm:pt-6">
              <input data-fix={f.key} type="checkbox" checked={value === true} disabled={disabled} onChange={(e) => onChange(f.key, e.target.checked)} />
              <span>{label}</span>
            </label>
          )
        }
        if (f.type === 'enum' && f.options?.length) {
          return (
            <SelectField key={f.key} data-fix={f.key} label={label} hint={hint} value={String(value ?? '')} disabled={disabled} onChange={(e) => onChange(f.key, e.target.value || null)}>
              <option value="">—</option>
              {f.options.map((o) => <option key={o}>{o}</option>)}
            </SelectField>
          )
        }
        return (
          <TextField key={f.key} data-fix={f.key} label={label} disabled={disabled}
            hint={f.type === 'enum' ? `${hint ? hint + ' · ' : ''}Liste non renseignée : saisie libre.` : hint}
            type={f.type === 'date' ? 'date' : f.type === 'number' ? 'number' : 'text'}
            value={String(value ?? '')}
            onChange={(e) => onChange(f.key, f.type === 'number' ? (e.target.value === '' ? null : Number(e.target.value)) : e.target.value || null)} />
        )
      })}
    </div>
  )
}

/** Onglet « Métier » de la fiche : une section par module actif qui déclare des champs salarié. */
export function ModuleSection({ employeeId }: { employeeId: string }) {
  const { can } = useAuth()
  const mods = useQuery({
    queryKey: ['module_manifest', 'active'],
    queryFn: async () => (unwrap(await dataApi.from('module_manifest')
      .select('module_id, name, manifest, activation:module_activation!inner(enabled)')
      .eq('activation.enabled', true)) as unknown as Mod[]),
  })
  const rows = (mods.data ?? []).map((m) => ({ m, fields: employeeFields(m.manifest.custom_fields, m.manifest.parameters) })).filter((x) => x.fields.length)
  if (mods.isLoading || rows.length === 0) return null
  return (
    <div className="mt-6 space-y-6">
      {rows.map(({ m, fields }) => <ModuleBlock key={m.module_id} m={m} fields={fields} employeeId={employeeId} editable={can('rh')} />)}
    </div>
  )
}

function ModuleBlock({ m, fields, employeeId, editable }: { m: Mod; fields: ModuleField[]; employeeId: string; editable: boolean }) {
  const qc = useQueryClient()
  const key = ['employee_module_data', employeeId, m.module_id]
  const row = useQuery({
    queryKey: key,
    queryFn: async () => unwrap(await dataApi.from('employee_module_data').select('id, data').eq('employee_id', employeeId).eq('module_id', m.module_id).maybeSingle()),
  })
  const [draft, setDraft] = useState<Data | null>(null)
  const data = draft ?? (row.data?.data as Data | undefined) ?? {}
  const defaults = Object.fromEntries(fields.filter((f) => f.def !== undefined).map((f) => [f.key, f.def]))
  const missing = missingRequired(fields, { ...defaults, ...data })
  const save = useMutation({
    mutationFn: async () => {
      const payload = Object.fromEntries(Object.entries(data).filter(([, v]) => v !== null && v !== undefined)) as never
      if (row.data) unwrap(await dataApi.from('employee_module_data').update({ data: payload }).eq('id', row.data.id).select('id'))
      else unwrap(await dataApi.from('employee_module_data').insert({ employee_id: employeeId, module_id: m.module_id, data: payload }).select('id'))
    },
    onSuccess: () => { setDraft(null); qc.invalidateQueries({ queryKey: key }) },
  })
  return (
    <div data-fix={`module_${m.module_id}`}><Section title={`Métier — ${m.name}`}>
      <ModuleForm fields={fields} data={{ ...defaults, ...data }} disabled={!editable} onChange={(k, v) => setDraft({ ...data, [k]: v })} />
      <ErrorNote error={row.error ?? save.error} />
      {missing.length > 0 && <p className="mt-3 text-sm text-signal">À renseigner : {missing.map((f) => f.label).join(', ')}.</p>}
      {editable && (
        <div className="mt-3 flex items-center gap-3">
          <Button variant="primary" loading={save.isPending} disabled={draft === null || missing.length > 0} onClick={() => save.mutate()}>Enregistrer</Button>
          {save.isSuccess && draft === null && <span className="text-xs text-river-dark">Enregistré.</span>}
        </div>
      )}
    </Section></div>
  )
}
