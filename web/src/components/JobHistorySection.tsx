import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Pencil, Plus, Trash2 } from 'lucide-react'
import { useState } from 'react'
import { dataApi, unwrap } from '../lib/api'
import { useDesignations } from '../lib/queries'
import { date } from '../lib/format'
import { Button, ErrorNote, Modal, Section, SelectField, Spinner, TextField } from './ui'

type Job = { id: string; designation_id: string | null; title: string; valid_from: string; valid_to: string | null; note: string | null }
const EMPTY = { id: '', designation_id: '', title: '', valid_from: '', valid_to: '', note: '' }

/** Emplois successifs du salarié (art. 140 : le certificat de travail en indique la nature et les dates). Modification : RH seule. */
export function JobHistorySection({ employeeId, editable }: { employeeId: string; editable: boolean }) {
  const qc = useQueryClient()
  const designations = useDesignations()
  const [form, setForm] = useState<typeof EMPTY | null>(null)
  const list = useQuery({
    queryKey: ['employee_job_history', employeeId],
    queryFn: async () => unwrap(await dataApi.from('employee_job_history')
      .select('id, designation_id, title, valid_from, valid_to, note').eq('employee_id', employeeId).order('valid_from', { ascending: false })) as Job[],
  })
  const refresh = () => { qc.invalidateQueries({ queryKey: ['employee_job_history', employeeId] }); qc.invalidateQueries({ queryKey: ['certificate_jobs', employeeId] }) }

  const save = useMutation({
    mutationFn: async (f: typeof EMPTY) => {
      const row = { employee_id: employeeId, designation_id: f.designation_id || null, title: f.title.trim(), valid_from: f.valid_from, valid_to: f.valid_to || null, note: f.note.trim() || null }
      try {
        return unwrap(f.id ? await dataApi.from('employee_job_history').update(row).eq('id', f.id).select() : await dataApi.from('employee_job_history').insert(row).select())
      } catch (e) {
        if (/exclusion|overlap/i.test(String((e as Error).message))) throw new Error('Cette période chevauche un autre emploi du même salarié')
        throw e
      }
    },
    onSuccess: () => { refresh(); setForm(null) },
  })
  const remove = useMutation({
    mutationFn: async (id: string) => unwrap(await dataApi.from('employee_job_history').delete().eq('id', id).select()),
    onSuccess: refresh,
  })

  const valid = !!form && form.title.trim().length > 0 && !!form.valid_from && (!form.valid_to || form.valid_to >= form.valid_from)

  return (
    <Section title="Historique des emplois" className="xl:col-span-2"
      actions={editable && <Button size="sm" icon={<Plus className="h-3.5 w-3.5" />} onClick={() => setForm({ ...EMPTY })}>Ajouter un emploi</Button>}>
      {list.isLoading ? <Spinner /> : (list.data ?? []).length === 0 ? (
        <p className="text-sm text-ink-muted">Aucun emploi enregistré. Renseignez l’emploi de la fiche : il est reporté ici automatiquement.</p>
      ) : (
        <table className="w-full text-sm">
          <thead><tr className="table-head"><th className="px-2 py-1.5">Emploi</th><th className="px-2 py-1.5">Du</th><th className="px-2 py-1.5">Au</th><th className="px-2 py-1.5">Note</th>{editable && <th className="px-2 py-1.5"><span className="sr-only">Actions</span></th>}</tr></thead>
          <tbody>
            {list.data!.map((j) => (
              <tr key={j.id} className="border-t border-line/70">
                <td className="px-2 py-1.5 font-medium">{j.title}</td>
                <td className="px-2 py-1.5 tabular-nums">{date(j.valid_from)}</td>
                <td className="px-2 py-1.5 tabular-nums">{j.valid_to ? date(j.valid_to) : 'en cours'}</td>
                <td className="px-2 py-1.5 text-ink-soft">{j.note}</td>
                {editable && (
                  <td className="px-2 py-1.5 text-right">
                    <button aria-label={`Modifier ${j.title}`} className="rounded p-1 text-ink-soft hover:text-river"
                      onClick={() => setForm({ id: j.id, designation_id: j.designation_id ?? '', title: j.title, valid_from: j.valid_from, valid_to: j.valid_to ?? '', note: j.note ?? '' })}><Pencil className="h-4 w-4" aria-hidden /></button>
                    <button aria-label={`Supprimer ${j.title}`} className="rounded p-1 text-ink-soft hover:text-signal"
                      onClick={() => { if (window.confirm(`Supprimer l’emploi « ${j.title} » de l’historique ?`)) remove.mutate(j.id) }}><Trash2 className="h-4 w-4" aria-hidden /></button>
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>
      )}
      <ErrorNote error={list.error || remove.error} />
      <Modal open={!!form} onClose={() => setForm(null)} title={form?.id ? 'Modifier un emploi' : 'Ajouter un emploi'}
        footer={<><Button variant="ghost" onClick={() => setForm(null)}>Annuler</Button><Button variant="primary" loading={save.isPending} disabled={!valid} onClick={() => form && save.mutate(form)}>Enregistrer</Button></>}>
        {form && (
          <div className="grid gap-3 sm:grid-cols-2">
            <SelectField label="Emploi du référentiel" className="sm:col-span-2" value={form.designation_id}
              onChange={(e) => {
                const d = (designations.data ?? []).find((x) => x.id === e.target.value)
                setForm({ ...form, designation_id: e.target.value, title: d?.name ?? form.title })
              }}>
              <option value="">Autre (saisie libre)…</option>
              {(designations.data ?? []).map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
            </SelectField>
            <TextField label="Intitulé (tel qu’il figurera au certificat)" className="sm:col-span-2" value={form.title} onChange={(e) => setForm({ ...form, title: e.target.value })} />
            <TextField label="Du" type="date" value={form.valid_from} onChange={(e) => setForm({ ...form, valid_from: e.target.value })} />
            <TextField label="Au (inclus, vide si en cours)" type="date" value={form.valid_to} onChange={(e) => setForm({ ...form, valid_to: e.target.value })} />
            <TextField label="Note" className="sm:col-span-2" value={form.note} onChange={(e) => setForm({ ...form, note: e.target.value })} />
          </div>
        )}
        <div className="mt-3"><ErrorNote error={save.error} /></div>
      </Modal>
    </Section>
  )
}
