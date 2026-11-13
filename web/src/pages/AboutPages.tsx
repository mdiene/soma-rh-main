import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { APP_NAME, APP_VERSION, BUILD, CONTACT, HISTORY, RELEASES, environment } from '../lib/appInfo'
import { PageHeader, Section } from '../components/ui'

/** Pages d'information du menu « À propos » : informations, tarification et services, conditions, confidentialité, sauvegardes et versions. */

const Draft = ({ children }: { children: ReactNode }) => (
  <p role="note" className="mb-5 rounded border border-phosphate bg-phosphate-light px-3 py-2 text-sm text-ink">{children}</p>
)
const Ul = ({ items }: { items: ReactNode[] }) => (
  <ul className="list-disc space-y-1 pl-5 text-sm text-ink-soft">{items.map((i, k) => <li key={k}>{i}</li>)}</ul>
)
const Body = ({ children }: { children: ReactNode }) => <div className="space-y-3 p-4 text-sm text-ink-soft">{children}</div>
const Stack = ({ children }: { children: ReactNode }) => <div className="max-w-4xl space-y-5">{children}</div>
const dateFr = (iso: string) => iso.split('-').reverse().join('/')
const unset = <span className="text-ink-muted">À renseigner par l’administrateur du déploiement</span>

/* ------------------------------------------------------------------------------------------ À propos */
export function AboutPage() {
  return (
    <>
      <PageHeader title={`À propos de ${APP_NAME}`} description="Application de gestion du personnel et de la paie : fiches salariés, congés et présences, paie, cotisations et conformité légale." />
      <Stack>
        <Section title="Version">
          <Body>
            <dl className="grid gap-x-6 gap-y-2 sm:grid-cols-[12rem_1fr]">
              <dt className="font-medium text-ink">Version</dt><dd>{APP_VERSION}</dd>
              <dt className="font-medium text-ink">Identifiant du build</dt><dd>{BUILD.commit || 'non disponible'}{BUILD.date ? ` · ${dateFr(BUILD.date)}` : ''}</dd>
              <dt className="font-medium text-ink">Environnement</dt><dd>{environment()}</dd>
            </dl>
            <p>Le détail des versions et la procédure de sauvegarde sont dans <Link className="text-river underline" to="/sauvegardes-versions">Sauvegardes et versions</Link>.</p>
          </Body>
        </Section>
        <Section title="Ce que couvre l’application">
          <Body>
            <Ul items={[
              'Gestion du personnel : fiches, contrats, catégories conventionnelles, pièces du dossier, organigramme.',
              'Congés, absences, présences et planning.',
              'Paie : variables du mois, calcul des bulletins, revue, approbation, validation et clôture avec séparation des tâches ; prêts et régularisations.',
              'Cotisations et états légaux : IPRES, caisse de sécurité sociale, IPM, impôts ; suivi des versements.',
              'Centre de conformité : constantes légales datées, constats, dérogations validées par l’administrateur.',
              'Espace salarié : bulletins, congés, demandes ; connexion possible par numéro de téléphone.',
            ]} />
          </Body>
        </Section>
        <Section title="Éditeur et support">
          <Body>
            <dl className="grid gap-x-6 gap-y-2 sm:grid-cols-[12rem_1fr]">
              <dt className="font-medium text-ink">Éditeur</dt><dd>{CONTACT.editor || unset}</dd>
              <dt className="font-medium text-ink">E-mail du support</dt><dd>{CONTACT.email ? <a className="text-river underline" href={`mailto:${CONTACT.email}`}>{CONTACT.email}</a> : unset}</dd>
              <dt className="font-medium text-ink">Téléphone du support</dt><dd>{CONTACT.phone || unset}</dd>
            </dl>
            <p className="text-xs">Ces coordonnées se définissent à l’installation (variables VITE_EDITOR_NAME, VITE_SUPPORT_EMAIL et VITE_SUPPORT_PHONE) : l’application n’en invente aucune.</p>
          </Body>
        </Section>
        <Section title="Composants open source">
          <Body>
            <p>L’application s’appuie notamment sur React, Vite, Tailwind CSS, TanStack Query et Table, Lucide, Framer Motion, PostgreSQL et PostgREST. Leurs licences respectives s’appliquent.</p>
          </Body>
        </Section>
      </Stack>
    </>
  )
}

/* ------------------------------------------------------------------------------------- Tarification */
export function PricingPage() {
  return (
    <>
      <PageHeader title="Tarification et services" description="Ce que la plateforme apporte à l’organisation qui l’utilise, et les conditions commerciales." />
      <Stack>
        <Draft>Aucun tarif n’est publié dans l’application. Les formules, prix et engagements ci-dessous sont à définir par l’éditeur ; seuls les services de la plateforme décrivent l’existant.</Draft>
        <Section title="Services de la plateforme">
          <Body>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <caption className="sr-only">Services de la plateforme et ce qu’ils couvrent</caption>
                <thead><tr className="table-head"><th scope="col" className="px-2 py-1.5 text-left">Service</th><th scope="col" className="px-2 py-1.5 text-left">Ce qu’il apporte</th></tr></thead>
                <tbody>
                  {[
                    ['Gestion du personnel', 'Fiches salariés, assistant de saisie, pièces du dossier, organigramme, historique des emplois.'],
                    ['Paie', 'Calcul des bulletins (IPRES, IPM, CSS, TRIMF, IR), prorata, heures supplémentaires, prêts, workflow à comptes distincts, clôture.'],
                    ['Congés et présences', 'Soldes, demandes à deux niveaux de validation, planning, présences intégrées à la paie.'],
                    ['Cotisations et états légaux', 'États IPRES et CSS, livre de paie, écritures comptables, suivi des versements par caisse.'],
                    ['Conformité légale', 'Constantes légales datées et sourcées, constats, dérogations validées, journal des modifications.'],
                    ['Espace salarié', 'Bulletins, congés, demandes ; connexion par e-mail ou par numéro de téléphone.'],
                    ['Sécurité et traçabilité', 'Accès par rôle, séparation des tâches, journal d’audit, verrouillage des connexions.'],
                    ['Sauvegardes et mises à jour', 'Procédures de sauvegarde et de restauration, journal des versions (voir « Sauvegardes et versions »).'],
                  ].map(([a, b]) => <tr key={a} className="border-b border-line/70 align-top"><th scope="row" className="px-2 py-2 text-left font-medium text-ink">{a}</th><td className="px-2 py-2">{b}</td></tr>)}
                </tbody>
              </table>
            </div>
          </Body>
        </Section>
        <Section title="Conditions commerciales (à définir par l’éditeur)">
          <Body>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <caption className="sr-only">Conditions commerciales à définir</caption>
                <thead><tr className="table-head"><th scope="col" className="px-2 py-1.5 text-left">Élément</th><th scope="col" className="px-2 py-1.5 text-left">Valeur</th></tr></thead>
                <tbody>
                  {['Formules et périmètres', 'Prix et périodicité de facturation', 'Nombre de salariés inclus et paliers', 'Niveau de support et délais de réponse', 'Engagement de disponibilité', 'Paramétrage initial, reprise de données, formation'].map((k) => (
                    <tr key={k} className="border-b border-line/70"><th scope="row" className="px-2 py-2 text-left font-medium text-ink">{k}</th><td className="px-2 py-2 text-ink-muted">À définir</td></tr>
                  ))}
                </tbody>
              </table>
            </div>
            <p>Pour un devis, contactez l’éditeur (voir <Link className="text-river underline" to="/a-propos">À propos</Link>).</p>
          </Body>
        </Section>
      </Stack>
    </>
  )
}

/* ------------------------------------------------------------------------ Conditions d'utilisation */
export function TermsPage() {
  return (
    <>
      <PageHeader title="Conditions d’utilisation" description="Règles d’usage de la plateforme par les utilisateurs de l’organisation." />
      <Stack>
        <Draft>Version de travail, non validée juridiquement : à faire relire et compléter par un conseil juridique avant diffusion (identité de l’éditeur, droit applicable, responsabilités, durée).</Draft>
        {[
          ['1. Objet', 'Les présentes conditions encadrent l’utilisation de la plateforme de gestion du personnel et de la paie par les personnes autorisées de l’organisation cliente.'],
          ['2. Accès et comptes', 'Chaque compte est personnel et attribué par l’administrateur de l’organisation avec un rôle (salarié, manager, rh, paie, administrateur). L’utilisateur garde ses identifiants confidentiels et signale toute utilisation suspecte. Les accès sont journalisés.'],
          ['3. Usage conforme', 'La plateforme est utilisée pour la gestion du personnel et de la paie de l’organisation. Il est interdit de contourner les contrôles d’accès, d’extraire des données hors du périmètre de son rôle ou d’utiliser les données à d’autres fins.'],
          ['4. Données saisies et paramètres légaux', 'L’organisation reste responsable de l’exactitude des données saisies et de la validation des paramètres légaux (taux, plafonds, barèmes) dans le Centre de conformité. Les calculs de paie appliquent ces paramètres ; les bulletins sont contrôlés et validés par les personnes habilitées avant remise.'],
          ['5. Séparation des tâches', 'La préparation, l’approbation, la validation et la clôture de la paie sont réparties entre des personnes distinctes. Toute dérogation exige un motif, enregistré dans le journal d’audit.'],
          ['6. Disponibilité et sauvegardes', 'L’éditeur met en œuvre des moyens raisonnables pour assurer la disponibilité et la sauvegarde des données (voir « Sauvegardes et versions »). Les engagements précis de disponibilité sont à définir au contrat.'],
          ['7. Propriété', 'Les données de l’organisation lui appartiennent. La plateforme, son code et sa documentation restent la propriété de l’éditeur ou de ses concédants.'],
          ['8. Évolution des conditions', 'Les conditions peuvent évoluer ; la version applicable est celle publiée dans l’application. Les utilisateurs sont informés des changements importants.'],
        ].map(([t, c]) => <Section key={t} title={t}><Body><p>{c}</p></Body></Section>)}
      </Stack>
    </>
  )
}

/* --------------------------------------------------------------------------------- Confidentialité */
export function PrivacyPage() {
  return (
    <>
      <PageHeader title="Politique de confidentialité" description="Quelles données personnelles sont traitées, pourquoi, par qui et comment elles sont protégées." />
      <Stack>
        <Draft>Version de travail, non validée juridiquement. Le cadre cité (loi sénégalaise n° 2008-12 sur les données à caractère personnel, Commission de protection des données personnelles) provient de la documentation du projet : à confirmer, ainsi que les durées de conservation, par un conseil juridique.</Draft>
        <Section title="Données traitées">
          <Body>
            <Ul items={[
              'Identité et état civil : nom, prénom, nom de jeune fille, date et lieu de naissance, nationalité, situation de famille, enfants à charge, filiation (père, mère).',
              'Pièce d’identité (numéro de CNI ou de passeport, dates), numéros d’affiliation (IPRES, caisse de sécurité sociale).',
              'Coordonnées : adresse, téléphones, e-mails, personne à prévenir.',
              'Contrat, emploi, catégorie, présences, congés, absences.',
              'Rémunération, bulletins, retenues, prêts, coordonnées bancaires.',
              'Données de connexion : compte, journal des connexions ; pour la connexion par téléphone, numéro et date de naissance (jamais conservés en clair dans les compteurs).',
            ]} />
          </Body>
        </Section>
        <Section title="Finalités"><Body><p>Gestion administrative du personnel, établissement et contrôle de la paie, déclarations sociales et fiscales, gestion des congés et du planning, sécurité des accès et traçabilité des opérations.</p></Body></Section>
        <Section title="Qui accède aux données">
          <Body>
            <Ul items={[
              'Chaque salarié voit ses propres informations.',
              'Les managers voient leur équipe (présences, congés).',
              'Les rôles rh et paie voient les données utiles à leur mission ; l’administrateur supervise.',
              'Les organismes sociaux et fiscaux reçoivent les déclarations obligatoires de l’organisation.',
              'Les prestataires techniques d’hébergement et de base de données (Supabase, Vercel) traitent les données pour le compte de l’organisation.',
            ]} />
          </Body>
        </Section>
        <Section title="Mesures de sécurité">
          <Body>
            <Ul items={[
              'Contrôle d’accès par rôle appliqué dans la base de données (et pas seulement à l’écran).',
              'Mots de passe stockés sous forme hachée ; verrouillage progressif après échecs de connexion.',
              'Journal d’audit des opérations sensibles ; séparation des tâches pour la paie.',
              'Documents du dossier salarié stockés avec contrôle d’accès et journal de consultation.',
              'Données personnelles absentes du code source et des fichiers suivis par Git.',
            ]} />
          </Body>
        </Section>
        <Section title="Conservation"><Body><p>Les durées de conservation sont à fixer par l’organisation selon ses obligations légales (paie, social, fiscal). Aucune durée n’est imposée par l’application.</p></Body></Section>
        <Section title="Vos droits"><Body><p>Toute personne concernée peut demander l’accès à ses données, leur rectification ou, selon la réglementation applicable, leur suppression ou la limitation de leur traitement. La demande s’adresse au service RH de l’organisation, via « Mon profil et mes demandes ».</p></Body></Section>
      </Stack>
    </>
  )
}

/* ----------------------------------------------------------------------- Sauvegardes et versions */
export function BackupVersionsPage() {
  return (
    <>
      <PageHeader title="Sauvegardes et versions" description="Version installée, historique des mises à jour, et procédures de sauvegarde et de restauration." />
      <Stack>
        <Section title="Version installée">
          <Body>
            <dl className="grid gap-x-6 gap-y-2 sm:grid-cols-[12rem_1fr]">
              <dt className="font-medium text-ink">Version</dt><dd>{APP_VERSION}</dd>
              <dt className="font-medium text-ink">Build</dt><dd>{BUILD.commit || 'non disponible'}{BUILD.date ? ` · ${dateFr(BUILD.date)}` : ''}</dd>
              <dt className="font-medium text-ink">Environnement</dt><dd>{environment()}</dd>
            </dl>
          </Body>
        </Section>
        <Section title="Journal des versions">
          <Body>
            {RELEASES.map((r) => (
              <article key={r.version} aria-label={`Version ${r.version}`}>
                <h3 className="font-semibold text-ink">Version {r.version} — {dateFr(r.date)} : {r.title}</h3>
                <Ul items={r.changes} />
              </article>
            ))}
            <h3 className="pt-2 font-semibold text-ink">Avant la numérotation</h3>
            {HISTORY.map((h) => (
              <article key={h.date} aria-label={h.title}>
                <p className="font-medium text-ink">{dateFr(h.date)} : {h.title}</p>
                <Ul items={h.changes} />
              </article>
            ))}
            <p className="text-xs">Le détail complet, commit par commit, est dans l’historique Git du projet et dans le journal des paliers de recette.</p>
          </Body>
        </Section>
        <Section title="Sauvegarde et restauration">
          <Body>
            <Ul items={[
              <><strong className="text-ink">Installation locale :</strong> sauvegarde de la base avec le script <code>scripts/local-backup.ps1</code> (fichier daté dans <code>backups/</code>), restauration avec <code>scripts/local-restore.ps1</code>. À faire avant toute mise à jour.</>,
              <><strong className="text-ink">Installation en ligne :</strong> les sauvegardes dépendent de l’offre du fournisseur de base de données ; leur fréquence et leur durée de rétention sont à vérifier dans la console du fournisseur et à consigner au contrat.</>,
              'Les retours arrière de chaque évolution de la base sont fournis avec les migrations (dossier db/rollback).',
            ]} />
          </Body>
        </Section>
        <Section title="Mises à jour et contrôle de version">
          <Body>
            <Ul items={[
              'Chaque évolution de la base passe par une migration datée, appliquée dans l’ordre et accompagnée de son retour arrière et de ses tests.',
              'Avant le déploiement : sauvegarde, tests (types, build, unitaires, base, interface), puis application des migrations et publication.',
              'Après le déploiement : vérification de la version affichée ci-dessus et contrôle de non-régression de la paie.',
            ]} />
          </Body>
        </Section>
      </Stack>
    </>
  )
}
