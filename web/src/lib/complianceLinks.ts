/** Lien « Corriger » d'un constat : l'écran où l'on modifie l'élément en cause. */
export type FindingRef = { entity: string; entity_id: string; employee_id: string | null; fix_target: string; message: string }

export function fixLink(f: FindingRef): { to: string; label: string } {
  switch (f.entity) {
    case 'employee':
      return { to: `/salaries/${f.employee_id ?? f.entity_id}`, label: 'Ouvrir la fiche du salarié' }
    case 'salary_slip':
      return { to: `/bulletins/${f.entity_id}`, label: 'Ouvrir le bulletin' }
    case 'cotisation':
      return { to: '/etats?onglet=cotisations', label: 'Ouvrir l’état des cotisations' }
    case 'planning': {
      // le message cite « semaine du JJ/MM/AAAA » : on ouvre cette semaine
      const m = /semaine du (\d{2})\/(\d{2})\/(\d{4})/.exec(f.message)
      return { to: m ? `/planning?semaine=${m[3]}-${m[2]}-${m[1]}` : '/planning', label: 'Ouvrir le planning' }
    }
    case 'parameter':
      return { to: '/centre-conformite', label: 'Ouvrir les constantes' }
    case 'company':
      return f.fix_target === 'parameter'
        ? { to: '/modules', label: 'Ouvrir les paramètres du module' }
        : { to: '/parametres?onglet=societe', label: 'Ouvrir la fiche société' }
    default:
      return { to: '/centre-conformite', label: 'Ouvrir le centre' }
  }
}
