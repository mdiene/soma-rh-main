import { useState } from 'react'
import clsx from 'clsx'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { dataApi, unwrap } from '../lib/api'
import { useAuth } from '../lib/auth'
import { date } from '../lib/format'
import { Badge, Button, Empty, ErrorNote, Modal, PageHeader, Section, Spinner, TextField } from '../components/ui'

type LegalStatus = 'verified' | 'secondary' | 'to_provide'
type ManifestParam = { value?: unknown; unit?: string; source?: string; legal_status?: LegalStatus; note?: string; minimum?: number; legal_ref?: string }
type ParamRow = { id: string; param_key: string; value: unknown }
type Row = {
  module_id: string; name: string; version: string; status: string
  manifest: { parameters?: Record<string, ManifestParam> }
  activation: { enabled: boolean; enabled_at: string | null } | null  // relation 1-1 (module_id unique)
  params: ParamRow[]
}

// ✔ texte lu · ◐ source secondaire · ✖ à fournir (libellés juridiques à faire valider par le comptable)
const STATUS: Record<LegalStatus, { mark: string; label: string; cls: string }> = {
  verified: { mark: '✔', label: 'Texte lu', cls: 'text-river-dark' },
  secondary: { mark: '◐', label: 'Source secondaire', cls: 'text-ink-soft' },
  to_provide: { mark: '✖', label: 'À fournir', cls: 'text-signal' },
}
const statusOf = (p: ManifestParam): LegalStatus => p.legal_status ?? 'to_provide'

const show = (v: unknown) => (v === null || v === undefined ? '' : typeof v === 'object' ? JSON.stringify(v) : String(v))
const parse = (s: string): unknown => (s.trim() !== '' && !Number.isNaN(Number(s.replace(',', '.'))) ? Number(s.replace(',', '.')) : s.trim())

/** Jauge de statut légal : un segment par paramètre, plein si une valeur est saisie. */
function Gauge({ m }: { m: Row }) {
  const defs = Object.entries(m.manifest.parameters ?? {})
  const filled = new Set(m.params.map((p) => p.param_key))
  if (!defs.length) return null
  return (
    <div className="mt-3" aria-label="Paramètres renseignés par statut légal">
      <div className="flex gap-0.5">
        {defs.map(([k, p]) => (
          <span key={k} title={`${k} : ${STATUS[statusOf(p)].label}${filled.has(k) ? '' : ' (manquant)'}`}
            className={clsx('h-2 flex-1 rounded-sm', filled.has(k) ? 'bg-river' : 'border border-signal/50 bg-signal-light')} />
        ))}
      </div>
      <p className="mt-1 text-xs text-ink-muted tabular-nums">
        {(['verified', 'secondary', 'to_provide'] as const).map((s) => {
          const n = defs.filter(([, p]) => statusOf(p) === s).length
          return n ? <span key={s} className="mr-3">{STATUS[s].mark} {n} {STATUS[s].label.toLowerCase()}</span> : null
        })}
      </p>
    </div>
  )
}

/** Saisie tracée des paramètres : l'écriture passe par module_parameter_value (RLS rh, journal d'audit). */
function ParamsModal({ m, onClose }: { m: Row; onClose: () => void }) {
  const qc = useQueryClient()
  const defs = Object.entries(m.manifest.parameters ?? {})
  const existing = new Map(m.params.map((p) => [p.param_key, p]))
  const [draft, setDraft] = useState<Record<string, string>>(
    () => Object.fromEntries(defs.map(([k]) => [k, show(existing.get(k)?.value)])),
  )
  const save = useMutation({
    mutationFn: async () => {
      for (const [k, p] of defs) {
        const cur = existing.get(k)
        const next = draft[k] ?? ''
        if (show(cur?.value) === next) continue
        if (next.trim() === '') {
          if (cur) unwrap(await dataApi.from('module_parameter_value').delete().eq('id', cur.id).select('id'))
        } else if (cur) {
          unwrap(await dataApi.from('module_parameter_value').update({ value: parse(next) as never }).eq('id', cur.id).select('id'))
        } else {
          unwrap(await dataApi.from('module_parameter_value').insert({
            module_id: m.module_id, param_key: k, value: parse(next) as never,
            legal_status: statusOf(p), source: p.source ?? 'Saisie client',
          }).select('id'))
        }
      }
    },
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['module_manifest'] }); onClose() },
  })
  return (
    <Modal open wide title={`Paramètres — ${m.name}`} onClose={onClose}
      footer={<><Button variant="ghost" onClick={onClose}>Annuler</Button><Button variant="primary" loading={save.isPending} onClick={() => save.mutate()}>Enregistrer</Button></>}>
      <ErrorNote error={save.error} />
      <p className="mb-3 text-sm text-ink-soft">Une valeur laissée vide reste « manquante » : le calcul émet une alerte et n'invente aucun montant. Chaque modification est tracée au journal.</p>
      <div className="space-y-4">
        {defs.map(([k, p]) => (
          <div key={k}>
            <TextField label={`${k}${p.unit ? ` (${p.unit})` : ''}`} value={draft[k] ?? ''}
              onChange={(e) => setDraft((d) => ({ ...d, [k]: e.target.value }))} inputMode="decimal"
              hint={[p.note, p.source && `Source : ${p.source}`].filter(Boolean).join(' · ') || undefined} />
            <span className={clsx('text-xs', STATUS[statusOf(p)].cls)}>{STATUS[statusOf(p)].mark} {STATUS[statusOf(p)].label}</span>
            {p.minimum !== undefined && draft[k]?.trim() && Number(parse(draft[k])) < p.minimum && (
              <p role="alert" className="mt-1 text-xs text-signal">
                Valeur inférieure au minimum légal : le taux légal est de {p.minimum * 100} %{p.legal_ref ? ` (${p.legal_ref})` : ''}.
              </p>
            )}
          </div>
        ))}
      </div>
    </Modal>
  )
}

const STEPS = ['Présentation', 'Paramètres', 'Simulation à blanc', 'Confirmation']

/** Assistant d'activation en 4 étapes. */
function ActivationWizard({ m, onClose, onParams }: { m: Row; onClose: () => void; onParams: () => void }) {
  const qc = useQueryClient()
  const [step, setStep] = useState(0)
  const filled = new Set(m.params.map((p) => p.param_key))
  const missing = Object.keys(m.manifest.parameters ?? {}).filter((k) => !filled.has(k))
  const activate = useMutation({
    mutationFn: async () => unwrap(await dataApi.from('module_activation').upsert({ module_id: m.module_id, enabled: true }, { onConflict: 'module_id' }).select('id')),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['module_manifest'] }); onClose() },
  })
  return (
    <Modal open title={`Activer — ${m.name}`} onClose={onClose}
      footer={<>
        {step > 0 && <Button variant="ghost" onClick={() => setStep(step - 1)}>Précédent</Button>}
        {step < 3
          ? <Button variant="primary" onClick={() => setStep(step + 1)}>Suivant</Button>
          : <Button variant="primary" loading={activate.isPending} onClick={() => activate.mutate()}>Activer le module</Button>}
      </>}>
      <ol className="mb-4 flex gap-2 text-xs" aria-label="Progression">
        {STEPS.map((s, i) => (
          <li key={s} aria-current={i === step ? 'step' : undefined}
            className={clsx('flex-1 border-t-2 pt-1', i <= step ? 'border-river text-ink' : 'border-line text-ink-muted')}>{i + 1}. {s}</li>
        ))}
      </ol>
      <ErrorNote error={activate.error} />
      {step === 0 && (
        <p className="text-sm text-ink-soft">Version {m.version}, manifeste « {m.status === 'draft' ? 'brouillon' : m.status} ». L'activation fait apparaître les règles et écrans du module ; elle ne modifie aucun bulletin déjà calculé.</p>
      )}
      {step === 1 && (missing.length === 0
        ? <p className="text-sm text-ink-soft">Tous les paramètres sont renseignés.</p>
        : <>
          <p className="text-sm text-signal">{missing.length} paramètre(s) manquant(s) : l'activation reste possible, mais le calcul émettra une alerte « paramètre manquant » pour chacun.</p>
          <ul className="mt-2 list-disc pl-5 text-sm text-ink-soft">{missing.map((k) => <li key={k}>{k}</li>)}</ul>
          <Button className="mt-3" onClick={onParams}>Saisir les paramètres</Button>
        </>)}
      {step === 2 && (
        <p className="text-sm text-ink-soft">Impact sur la paie du mois courant : <strong className="tabular-nums text-ink">0 F</strong> de brut, <strong className="tabular-nums text-ink">0 F</strong> de net. Le moteur de paie des modules (lot M3) n'existe pas encore : aucune rubrique n'est calculée, l'écart est nul par construction.</p>
      )}
      {step === 3 && (
        <p className="text-sm text-ink-soft">Vous allez activer <strong className="text-ink">{m.name}</strong>. L'activation est datée et tracée (qui, quand, quelle version du manifeste). Vous pourrez la désactiver à tout moment.</p>
      )}
    </Modal>
  )
}

/** Modules métiers (gardiennage, intérim…) : activer ou désactiver sans toucher au cœur de l'application. */
export default function ModulesPage() {
  const { can } = useAuth()
  const qc = useQueryClient()
  const [paramsFor, setParamsFor] = useState<string | null>(null)
  const [wizardFor, setWizardFor] = useState<string | null>(null)
  const list = useQuery({
    queryKey: ['module_manifest'],
    queryFn: async () => unwrap(await dataApi.from('module_manifest')
      .select('module_id, name, version, status, manifest, activation:module_activation(enabled, enabled_at), params:module_parameter_value(id, param_key, value)')
      .order('name')) as unknown as Row[],
  })
  const disable = useMutation({
    mutationFn: async (module_id: string) =>
      unwrap(await dataApi.from('module_activation').upsert({ module_id, enabled: false }, { onConflict: 'module_id' }).select('id')),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['module_manifest'] }),
  })
  const byId = (id: string | null) => list.data?.find((m) => m.module_id === id)
  const paramsModule = byId(paramsFor)
  const wizardModule = byId(wizardFor)

  return (
    <>
      <PageHeader
        title="Modules métiers"
        description="Activez un module sectoriel pour faire apparaître ses règles et ses écrans. Un module désactivé ne change rien au calcul de la paie."
      />
      <ErrorNote error={list.error ?? disable.error} />
      {list.isLoading ? <Spinner /> : !list.data?.length ? <Empty title="Aucun module chargé">Chargez les manifestes avec <code>node scripts/load-modules.mjs</code>.</Empty> : (
        <div className="grid gap-4 lg:grid-cols-2">
          {list.data.map((m) => {
            const enabled = m.activation?.enabled ?? false
            const expected = Object.keys(m.manifest.parameters ?? {}).length
            const filled = new Set(m.params.map((p) => p.param_key)).size
            return (
              <Section key={m.module_id} title={m.name} actions={<Badge value={enabled ? 'Actif' : 'Inactif'} />}>
                <p className="text-sm text-ink-soft">
                  Version {m.version} · manifeste « {m.status === 'draft' ? 'brouillon' : m.status} »
                  {enabled && m.activation?.enabled_at && ` · activé le ${date(m.activation.enabled_at.slice(0, 10))}`}
                </p>
                <p className={filled < expected ? 'mt-1 text-sm text-signal' : 'mt-1 text-sm text-ink-soft'}>
                  {filled} paramètre(s) renseigné(s) sur {expected}
                  {filled < expected && ' : les manquants déclenchent une alerte au calcul.'}
                </p>
                <Gauge m={m} />
                {can('rh') && (
                  <div className="mt-3 flex gap-2">
                    <Button onClick={() => setParamsFor(m.module_id)}>Paramètres</Button>
                    {enabled
                      ? <Button variant="ghost" loading={disable.isPending} onClick={() => disable.mutate(m.module_id)}>Désactiver</Button>
                      : <Button variant="primary" onClick={() => setWizardFor(m.module_id)}>Activer…</Button>}
                  </div>
                )}
              </Section>
            )
          })}
        </div>
      )}
      {paramsModule && <ParamsModal m={paramsModule} onClose={() => setParamsFor(null)} />}
      {wizardModule && !paramsModule && (
        <ActivationWizard m={wizardModule} onClose={() => setWizardFor(null)} onParams={() => setParamsFor(wizardModule.module_id)} />
      )}
    </>
  )
}
