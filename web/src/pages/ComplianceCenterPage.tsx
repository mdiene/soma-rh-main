import { useQuery } from '@tanstack/react-query'
import clsx from 'clsx'
import { useEffect, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { ApprovalsTab } from '../components/compliance/ApprovalsTab'
import { FindingsTab } from '../components/compliance/FindingsTab'
import { WaiversTab } from '../components/compliance/WaiversTab'
import { ConstantsTab } from '../components/compliance/ConstantsTab'
import { PageHeader } from '../components/ui'
import { dataApi, unwrap } from '../lib/api'

const TABS = [
  { id: 'coherence', label: 'Cohérence' },
  { id: 'derogations', label: 'Dérogations' },
  { id: 'constantes', label: 'Constantes et barèmes' },
  { id: 'validation', label: 'À valider' },
] as const
type TabId = (typeof TABS)[number]['id']

/** Centre de contrôle de conformité : constantes légales, barèmes, demandes à valider et cohérence avec le Code du Travail. */
export default function ComplianceCenterPage() {
  const [params, setParams] = useSearchParams()
  const tab: TabId = TABS.some((t) => t.id === params.get('onglet')) ? (params.get('onglet') as TabId) : 'coherence'
  const [notice, setNotice] = useState('')
  const timer = useRef<number>(undefined)
  useEffect(() => () => window.clearTimeout(timer.current), [])
  const say = (m: string) => { setNotice(m); window.clearTimeout(timer.current); timer.current = window.setTimeout(() => setNotice(''), 8000) }

  const pending = useQuery({
    queryKey: ['approval_pending'], refetchInterval: 120_000,
    queryFn: async () => unwrap(await dataApi.rpc('approval_pending_count')) as number,
  }).data

  const select = (id: TabId) => setParams(id === 'coherence' ? {} : { onglet: id }, { replace: true })
  return (
    <>
      <PageHeader title="Centre de conformité" description="Scan de cohérence, dérogations, constantes légales et barèmes avec le texte de loi qui les fonde, modifications versionnées et validées par l’administrateur. Les paies déjà calculées ne changent jamais." />
      <div className="no-print mb-5 flex flex-wrap gap-1 border-b border-line" role="tablist" aria-label="Sections du centre de conformité">
        {TABS.map((t) => (
          <button key={t.id} role="tab" id={`tab-${t.id}`} aria-selected={tab === t.id} aria-controls={`panel-${t.id}`} onClick={() => select(t.id)}
            className={clsx('-mb-px border-b-2 px-3 py-2 text-sm', tab === t.id ? 'border-river font-medium text-ink' : 'border-transparent text-ink-soft hover:text-ink')}>
            {t.label}{t.id === 'validation' && pending ? ` (${pending})` : ''}
          </button>
        ))}
      </div>
      <p role="status" aria-live="polite" className={notice ? 'mb-4 rounded border border-river/30 bg-river-light px-3 py-2 text-sm text-ink' : 'sr-only'}>{notice}</p>
      <div role="tabpanel" id={`panel-${tab}`} aria-labelledby={`tab-${tab}`}>
        {tab === 'coherence' && <FindingsTab onNotice={say} />}
        {tab === 'derogations' && <WaiversTab onNotice={say} />}
        {tab === 'constantes' && <ConstantsTab onNotice={say} />}
        {tab === 'validation' && <ApprovalsTab onNotice={say} />}
      </div>
    </>
  )
}
