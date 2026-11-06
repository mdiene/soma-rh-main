import { useSyncExternalStore } from 'react'
import { queryErrors } from '../lib/queryErrors'

/** Bandeau des erreurs de lecture : évite qu'un bloc vide soit pris pour « aucune donnée ». */
export default function QueryErrorBanner() {
  const messages = useSyncExternalStore(queryErrors.subscribe, queryErrors.snapshot)
  if (messages.length === 0) return null
  return (
    <div role="alert" className="no-print mb-4 flex items-start justify-between gap-3 rounded border border-signal/30 bg-signal-light px-3 py-2 text-sm text-signal">
      <div>
        <p className="font-medium">Certaines données n'ont pas pu être chargées ; les blocs vides ne signifient pas « aucune donnée ».</p>
        <ul className="list-disc pl-5">{messages.map((m) => <li key={m}>{m}</li>)}</ul>
      </div>
      <button type="button" onClick={queryErrors.clear} className="shrink-0 underline">Fermer</button>
    </div>
  )
}
