import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Plus, Trash2 } from 'lucide-react'
import { useState } from 'react'
import { dataApi, unwrap } from '../lib/api'
import { useAuth } from '../lib/auth'
import { useCompany } from '../lib/queries'
import { Button, ErrorNote, Section, SelectField, Spinner, TextField } from './ui'

/**
 * RPR-10 : gestion des départements (directions, secteurs, sections, services) proposés sur la fiche salarié.
 * Création, suppression des départements sans salarié ; les droits sont ceux de la base (rôle rh).
 */
type Dept = { id: string; name: string; kind: string; parent_id: string | null }
const KINDS = [
  { value: 'direction', label: 'Direction' },
  { value: 'secteur', label: 'Secteur' },
  { value: 'section', label: 'Section' },
  { value: 'service', label: 'Service' },
]
const kindLabel = (k: string) => KINDS.find((x) => x.value === k)?.label ?? k

/** Messages de la base traduits pour l'utilisateur. */
function explain(error: unknown): Error | null {
  if (!error) return null
  const m = error instanceof Error ? error.message : String(error)
  if (/departments_company_id_name_key|duplicate key/.test(m)) return new Error('Un département porte déjà ce nom.')
  if (/employees_department_id_fkey|violates foreign key/.test(m)) return new Error('Des salariés sont rattachés à ce département : changez leur département avant de le supprimer.')
  return new Error(m)
}

export function DepartmentsManager() {
  const { can } = useAuth()
  const qc = useQueryClient()
  const company = useCompany()
  const q = useQuery({
    queryKey: ['departments_all'],
    queryFn: async () => unwrap(await dataApi.from('departments').select('id, name, kind, parent_id').order('name')) as Dept[],
  })
  const [name, setName] = useState('')
  const [kind, setKind] = useState('direction')
  const [parent, setParent] = useState('')
  const refresh = () => { qc.invalidateQueries({ queryKey: ['departments_all'] }); qc.invalidateQueries({ queryKey: ['departments'] }) }
  const add = useMutation({
    mutationFn: async () => unwrap(await dataApi.from('departments').insert({ company_id: company.data!.id, name: name.trim(), kind, parent_id: parent || null }).select('id')),
    onSuccess: () => { setName(''); setParent(''); refresh() },
  })
  const remove = useMutation({
    mutationFn: async (id: string) => unwrap(await dataApi.from('departments').delete().eq('id', id).select('id')),
    onSuccess: refresh,
  })
  const parentName = (id: string | null) => q.data?.find((d) => d.id === id)?.name ?? '—'
  const editable = can('rh')

  return (
    <Section title="Départements" className="mt-6">
      <p className="mb-3 max-w-prose text-xs text-ink-muted">Directions, secteurs, sections et services de la société. Le département se choisit sur la fiche du salarié ; il sert aux filtres (présences, effectifs) et à l'organigramme. Un département ne peut être supprimé que s'il ne compte aucun salarié.</p>
      {q.isLoading ? <Spinner /> : (q.data ?? []).length === 0 ? (
        <p className="mb-3 text-sm text-ink-soft">Aucun département pour l'instant.</p>
      ) : (
        <table className="mb-4 w-full text-sm">
          <thead><tr className="border-b border-line text-left text-xs text-ink-muted"><th className="py-1.5 pr-3">Nom</th><th className="pr-3">Niveau</th><th className="pr-3">Dépend de</th><th /></tr></thead>
          <tbody>
            {q.data!.map((d) => (
              <tr key={d.id} className="border-b border-line/60">
                <td className="py-1.5 pr-3 font-medium">{d.name}</td>
                <td className="pr-3">{kindLabel(d.kind)}</td>
                <td className="pr-3 text-ink-soft">{parentName(d.parent_id)}</td>
                <td className="text-right">
                  {editable && <Button size="sm" variant="ghost" aria-label={`Supprimer ${d.name}`} icon={<Trash2 className="h-3.5 w-3.5" />} loading={remove.isPending && remove.variables === d.id} onClick={() => remove.mutate(d.id)} />}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {editable && (
        <form className="flex flex-wrap items-end gap-3" onSubmit={(e) => { e.preventDefault(); if (name.trim()) add.mutate() }}>
          <TextField label="Nom du département" value={name} onChange={(e) => setName(e.target.value)} className="w-64" />
          <SelectField label="Niveau" value={kind} onChange={(e) => setKind(e.target.value)}>
            {KINDS.map((k) => <option key={k.value} value={k.value}>{k.label}</option>)}
          </SelectField>
          <SelectField label="Dépend de" value={parent} onChange={(e) => setParent(e.target.value)}>
            <option value="">— aucun —</option>
            {(q.data ?? []).map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
          </SelectField>
          <Button type="submit" variant="primary" icon={<Plus className="h-4 w-4" />} loading={add.isPending} disabled={!name.trim() || !company.data}>Ajouter</Button>
        </form>
      )}
      <div className="mt-3"><ErrorNote error={q.error || explain(add.error) || explain(remove.error)} /></div>
    </Section>
  )
}
