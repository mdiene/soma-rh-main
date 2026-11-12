import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useState } from 'react'
import { dataApi, unwrap } from '../../lib/api'
import { EMPLOYEE_FIELDS } from '../../lib/complianceLinks'
import { selectable, useContractTypes } from '../../lib/queries'
import { Button, ErrorNote, Modal, SelectField, Spinner, TextField } from '../ui'
import { useRefreshCompliance } from './shared'

/** Corrige les champs d'un salarié sans quitter le centre de conformité, puis relance le scan. */
export function FixFieldsModal({ employeeId, keys, onClose }: { employeeId: string | null; keys: string[]; onClose: () => void }) {
  const qc = useQueryClient()
  const refresh = useRefreshCompliance()
  const contractTypes = useContractTypes()
  const [edit, setEdit] = useState<Record<string, string>>({})
  const cols = keys.join(',')
  const emp = useQuery({
    queryKey: ['employee-fix', employeeId, cols],
    enabled: !!employeeId,
    queryFn: async () => unwrap(await dataApi.from('employees').select(`id, ${cols}`).eq('id', employeeId!).single()) as unknown as Record<string, string | null>,
  })
  const save = useMutation({
    mutationFn: async () => {
      const patch = Object.fromEntries(Object.entries(edit).map(([k, v]) => [k, v.trim() === '' ? null : v.trim()]))
      unwrap(await dataApi.from('employees').update(patch).eq('id', employeeId!).select('id').single())
      unwrap(await dataApi.rpc('run_compliance_scan'))   // le constat disparaît s'il est résolu
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['employee', employeeId] }); void qc.invalidateQueries({ queryKey: ['employees'] })
      refresh(); setEdit({}); onClose()
    },
  })
  const value = (k: string) => edit[k] ?? emp.data?.[k] ?? ''
  const close = () => { setEdit({}); save.reset(); onClose() }

  return (
    <Modal open={employeeId !== null} title="Corriger la fiche du salarié" onClose={close}
      footer={<>
        <Button onClick={close}>Annuler</Button>
        <Button variant="primary" loading={save.isPending} disabled={Object.keys(edit).length === 0} onClick={() => save.mutate()}>Enregistrer et relancer le scan</Button>
      </>}>
      {emp.isLoading ? <Spinner /> : emp.isError ? <ErrorNote error={emp.error} /> : (
        <div className="grid gap-3 sm:grid-cols-2">
          {keys.map((k) => {
            const f = EMPLOYEE_FIELDS[k]
            const set = (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => setEdit((x) => ({ ...x, [k]: e.target.value }))
            return f.type === 'contract'
              ? <SelectField key={k} label={f.label} value={value(k)} onChange={set}>
                  <option value="">—</option>
                  {selectable(contractTypes.data, (c) => c.code === value(k)).map((c) => <option key={c.code} value={c.code}>{c.code} — {c.label}{c.is_active ? '' : ' (désactivé)'}</option>)}
                </SelectField>
              : <TextField key={k} label={f.label} type={f.type} maxLength={f.type === 'date' ? undefined : 100} value={value(k)} onChange={set} />
          })}
        </div>
      )}
      {save.isError && <ErrorNote error={save.error} />}
    </Modal>
  )
}
