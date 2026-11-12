import { ArrowLeft } from 'lucide-react'
import { Link, useLocation } from 'react-router-dom'

/** Bandeau « Retour au constat » : affiché sur la page ouverte par un lien « Corriger » du centre de conformité (`?retour=<constat>`). */
export function ReturnToCompliance() {
  const { search } = useLocation()
  const id = new URLSearchParams(search).get('retour')
  if (!id) return null
  return (
    <p className="no-print mb-4 flex flex-wrap items-center gap-3 rounded border border-phosphate bg-phosphate-light px-3 py-2 text-sm text-ink">
      <span>Correction demandée par le centre de conformité.</span>
      <Link to={`/centre-conformite?constat=${encodeURIComponent(id)}`} className="inline-flex items-center gap-1 font-medium text-river underline underline-offset-2">
        <ArrowLeft className="size-4" aria-hidden />Retour au constat
      </Link>
    </p>
  )
}
