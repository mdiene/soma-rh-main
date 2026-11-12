import { UserGuideTab } from '../components/UserGuideTab'
import { PageHeader } from '../components/ui'

/** Aide : le guide utilisateur, accessible à tous les rôles (les Paramètres, eux, sont réservés à rh et paie). */
export default function HelpPage() {
  return (
    <>
      <PageHeader title="Aide et guide utilisateur" description="Le guide de SOMA-RH, par rôle : démarrer, embaucher, gérer les congés, calculer la paie, consulter les états." />
      <UserGuideTab />
    </>
  )
}
