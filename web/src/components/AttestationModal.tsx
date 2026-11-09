import { useQuery } from '@tanstack/react-query'
import { Printer } from 'lucide-react'
import { dataApi, unwrap } from '../lib/api'
import { useCompany, useDesignations } from '../lib/queries'
import { date, fcfa, monthLabel } from '../lib/format'
import { Button, Modal, Spinner } from './ui'
import { PrintPortal, printPortal } from './PrintPortal'
import { DEFAULT_TEMPLATES, renderTemplate } from '../lib/documentTemplates'

export type AttestationKind = 'attestation_travail' | 'attestation_salaire'

/** Attestation de travail / de salaire, prévisualisée à l'écran et imprimable (A4, à signer). */
export function AttestationModal({ employeeId, kind, onClose }: { employeeId: string | null; kind: AttestationKind; onClose: () => void }) {
  return (
    <Modal open={!!employeeId} onClose={onClose} wide title={kind === 'attestation_travail' ? 'Attestation de travail' : 'Attestation de salaire'}
      footer={<><Button variant="ghost" onClick={onClose}>Fermer</Button><Button variant="primary" icon={<Printer className="h-4 w-4" />} onClick={printPortal}>Imprimer</Button></>}>
      {employeeId && (
        <>
          <div className="max-h-[65vh] overflow-auto rounded border border-line bg-white"><AttestationDocument employeeId={employeeId} kind={kind} /></div>
          <PrintPortal><AttestationDocument employeeId={employeeId} kind={kind} /></PrintPortal>
        </>
      )}
    </Modal>
  )
}

function AttestationDocument({ employeeId, kind }: { employeeId: string; kind: AttestationKind }) {
  const company = useCompany()
  const designations = useDesignations()
  const emp = useQuery({
    queryKey: ['attestation-emp', employeeId],
    queryFn: async () => unwrap(await dataApi.from('employees').select('*').eq('id', employeeId).single()),
  })
  const slip = useQuery({
    queryKey: ['attestation-slip', employeeId],
    enabled: kind === 'attestation_salaire',
    queryFn: async () => unwrap(await dataApi.from('salary_slips').select('period_start, gross_pay, net_pay').eq('employee_id', employeeId).eq('status', 'Validé').order('period_start', { ascending: false }).limit(1)),
  })
  const tpl = useQuery({
    queryKey: ['document_template', kind],
    queryFn: async () => unwrap(await dataApi.from('document_templates').select('body').eq('code', kind).maybeSingle()),
  })
  if (emp.isLoading || company.isLoading || tpl.isLoading) return <div className="p-6"><Spinner /></div>
  const e = emp.data
  const c = company.data
  if (!e) return <p className="p-6 text-sm">Salarié introuvable.</p>

  const civ = e.gender === 'F' ? 'Madame' : 'Monsieur'
  const pron = e.gender === 'F' ? 'employée' : 'employé'
  const designation = designations.data?.find((d) => d.id === e.designation_id)?.name
  const left = e.status === 'Left' && e.relieving_date
  const last = slip.data?.[0]
  const today = date(new Date().toISOString().slice(0, 10))
  const place = 'Dakar'
  const f = e.gender === 'F' ? 'e' : ''
  const paragraphs = renderTemplate(tpl.data?.body ?? DEFAULT_TEMPLATES[kind], {
    societe: c?.name ?? '', civilite: civ, prenom: e.first_name, nom: e.last_name.toUpperCase(), matricule: e.employee_number,
    naissance: e.date_of_birth ? `, né${f} le ${date(e.date_of_birth)}${e.place_of_birth ? ` à ${e.place_of_birth}` : ''}` : '',
    etat: left ? 'a été' : 'est', employe: pron, fonction: designation ? ` en qualité de ${designation}` : '',
    date_embauche: date(e.date_of_joining), fin: left ? ` jusqu’au ${date(e.relieving_date!)}` : '', e: f,
    effectif: kind === 'attestation_travail' && !left ? `L’intéressé${f} fait toujours partie de notre effectif à la date de la présente.` : '',
    salaire: kind !== 'attestation_salaire' ? '' : last
      ? `À la date du bulletin de ${monthLabel(last.period_start)}, sa rémunération mensuelle s’établit à ${fcfa(last.gross_pay)} F CFA brut, soit ${fcfa(last.net_pay)} F CFA net à payer.`
      : 'Aucun bulletin validé : renseignez le montant à la main avant impression.',
    date_du_jour: today, lieu: place,
  })

  return (
    <div className="sheet mx-auto min-h-[250mm] max-w-[190mm] p-8 text-[13px] leading-relaxed" style={{ fontFamily: 'Archivo, sans-serif' }}>
      <header className="mb-10 border-b-2 border-ink pb-2">
        <p className="text-lg font-bold">{c?.name ?? ''}</p>
        <p>{c?.address ?? ''}</p>
        <p>{c?.ninea ? `NINEA ${c.ninea}` : ''}{c?.rccm ? ` · RCCM ${c.rccm}` : ''}</p>
      </header>

      <h1 className="mb-10 text-center text-xl font-bold uppercase tracking-wide underline">
        {kind === 'attestation_travail' ? 'Attestation de travail' : 'Attestation de salaire'}
      </h1>

      {paragraphs.map((p, i) => <p key={i} className="mb-4">{p}</p>)}

      <p className="mb-16 mt-12 text-right">Fait à {place}, le {today}</p>

      <div className="ml-auto w-72 text-center">
        <p className="font-bold">La Direction</p>
        <div className="mt-20 border-t border-ink pt-1 text-xs text-ink-soft">Signature et cachet</div>
      </div>
    </div>
  )
}
