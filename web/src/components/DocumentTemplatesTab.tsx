import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { RotateCcw, Save } from 'lucide-react'
import { useEffect, useState } from 'react'
import { dataApi, unwrap } from '../lib/api'
import { useAuth } from '../lib/auth'
import { date } from '../lib/format'
import { DEFAULT_TEMPLATES, TEMPLATE_FIELDS, renderTemplate, unknownFields } from '../lib/documentTemplates'
import { Button, ErrorNote, Section, SelectField, Spinner } from './ui'

const SAMPLE: Record<string, string> = {
  societe: 'Société Exemple', civilite: 'Madame', prenom: 'Awa', nom: 'DIOP', matricule: 'M0001',
  naissance: ', née le 01/01/1990 à Dakar', etat: 'est', employe: 'employée', fonction: ' en qualité de Comptable',
  date_embauche: '15/03/2020', fin: '', e: 'e', effectif: 'L’intéressée fait toujours partie de notre effectif à la date de la présente.',
  salaire: 'À la date du bulletin de octobre 2026, sa rémunération mensuelle s’établit à 450 000 F CFA brut, soit 380 000 F CFA net à payer.',
  date_du_jour: '09/11/2026', lieu: 'Dakar',
}

/** Paramètres > Modèles de documents : texte des attestations, champs {{…}}, aperçu. Modification réservée à la RH. */
export function DocumentTemplatesTab() {
  const { can } = useAuth()
  const qc = useQueryClient()
  const [code, setCode] = useState<'attestation_travail' | 'attestation_salaire'>('attestation_travail')
  const [body, setBody] = useState('')
  const list = useQuery({
    queryKey: ['document_templates'],
    queryFn: async () => unwrap(await dataApi.from('document_templates').select('code, title, body, version, updated_at').order('code')),
  })
  const current = list.data?.find((t) => t.code === code)
  useEffect(() => { setBody(current?.body ?? DEFAULT_TEMPLATES[code]) }, [current?.body, code])

  const unknown = unknownFields(body)
  const dirty = body !== (current?.body ?? DEFAULT_TEMPLATES[code])
  const save = useMutation({
    mutationFn: async () => unwrap(await dataApi.from('document_templates')
      .upsert({ code, title: code === 'attestation_travail' ? 'Attestation de travail' : 'Attestation de salaire', body }, { onConflict: 'code' }).select()),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['document_templates'] }); qc.invalidateQueries({ queryKey: ['document_template'] }) },
  })
  const editable = can('rh')

  return (
    <Section title="Modèles de documents"
      actions={editable && (
        <div className="flex gap-2">
          <Button size="sm" variant="ghost" icon={<RotateCcw className="h-3.5 w-3.5" />} onClick={() => setBody(DEFAULT_TEMPLATES[code])}>Texte d'origine</Button>
          <Button size="sm" variant="primary" icon={<Save className="h-3.5 w-3.5" />} loading={save.isPending} disabled={!dirty || unknown.length > 0}
            onClick={() => save.mutate()}>Enregistrer</Button>
        </div>
      )}>
      {list.isLoading ? <Spinner /> : (
        <div className="grid gap-4 lg:grid-cols-2">
          <div>
            <SelectField label="Document" value={code} onChange={(e) => setCode(e.target.value as typeof code)}>
              <option value="attestation_travail">Attestation de travail</option>
              <option value="attestation_salaire">Attestation de salaire</option>
            </SelectField>
            <label className="mt-3 block">
              <span className="label">Texte (une ligne vide sépare les paragraphes)</span>
              <textarea className="field min-h-64 font-mono text-xs" value={body} disabled={!editable} onChange={(e) => setBody(e.target.value)} />
            </label>
            {unknown.length > 0 && (
              <p role="alert" className="mt-2 text-xs text-signal">Champ inconnu : {unknown.map((k) => `{{${k}}}`).join(', ')}. Corrigez avant d'enregistrer.</p>
            )}
            {current && <p className="mt-2 text-xs text-ink-muted">Version {current.version}, modifiée le {date(current.updated_at.slice(0, 10))}.</p>}
            {!editable && <p className="mt-2 text-xs text-ink-muted">Lecture seule : la modification est réservée au rôle RH.</p>}
            <ErrorNote error={list.error || save.error} />
            <details className="mt-3 text-xs text-ink-soft">
              <summary className="cursor-pointer">Champs disponibles</summary>
              <ul className="mt-2 space-y-1">
                {TEMPLATE_FIELDS.map((f) => <li key={f.key}><code>{`{{${f.key}}}`}</code> : {f.label}</li>)}
              </ul>
            </details>
          </div>
          <div>
            <p className="label">Aperçu avec des données fictives</p>
            <div className="rounded border border-line bg-white p-4 text-[13px] leading-relaxed">
              {renderTemplate(body, SAMPLE).map((p, i) => <p key={i} className="mb-3">{p}</p>)}
            </div>
          </div>
        </div>
      )}
    </Section>
  )
}
