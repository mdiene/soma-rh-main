import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { dataApi, unwrap } from '../lib/api'
import { useAuth } from '../lib/auth'
import { date } from '../lib/format'
import { Badge, Button, Empty, ErrorNote, PageHeader, Section, Spinner } from '../components/ui'

type Row = {
  module_id: string; name: string; version: string; status: string
  manifest: { parameters?: Record<string, unknown> }
  activation: { enabled: boolean; enabled_at: string | null }[]
  params: { param_key: string }[]
}

/** Modules métiers (gardiennage, intérim…) : activer ou désactiver sans toucher au cœur de l'application. */
export default function ModulesPage() {
  const { can } = useAuth()
  const qc = useQueryClient()
  const list = useQuery({
    queryKey: ['module_manifest'],
    queryFn: async () => unwrap(await dataApi.from('module_manifest')
      .select('module_id, name, version, status, manifest, activation:module_activation(enabled, enabled_at), params:module_parameter_value(param_key)')
      .order('name')) as unknown as Row[],
  })
  const toggle = useMutation({
    mutationFn: async ({ module_id, enabled }: { module_id: string; enabled: boolean }) =>
      unwrap(await dataApi.from('module_activation').upsert({ module_id, enabled }, { onConflict: 'module_id' }).select('id')),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['module_manifest'] }),
  })

  return (
    <>
      <PageHeader
        title="Modules métiers"
        description="Activez un module sectoriel pour faire apparaître ses règles et ses écrans. Un module désactivé ne change rien au calcul de la paie."
      />
      <ErrorNote error={list.error ?? toggle.error} />
      {list.isLoading ? <Spinner /> : !list.data?.length ? <Empty title="Aucun module chargé" /> : (
        <div className="grid gap-4 lg:grid-cols-2">
          {list.data.map((m) => {
            const enabled = m.activation[0]?.enabled ?? false
            const expected = Object.keys(m.manifest.parameters ?? {}).length
            const filled = new Set(m.params.map((p) => p.param_key)).size
            return (
              <Section key={m.module_id} title={m.name} actions={<Badge value={enabled ? 'Actif' : 'Inactif'} />}>
                <p className="text-sm text-ink-soft">
                  Version {m.version} · manifeste « {m.status === 'draft' ? 'brouillon' : m.status} »
                  {enabled && m.activation[0]?.enabled_at && ` · activé le ${date(m.activation[0].enabled_at.slice(0, 10))}`}
                </p>
                <p className={filled < expected ? 'mt-1 text-sm text-signal' : 'mt-1 text-sm text-ink-soft'}>
                  {filled} paramètre(s) renseigné(s) sur {expected}
                  {filled < expected && ' : les manquants déclenchent une alerte au calcul.'}
                </p>
                {can('rh') && (
                  <Button className="mt-3" variant={enabled ? 'ghost' : 'primary'} loading={toggle.isPending}
                    onClick={() => toggle.mutate({ module_id: m.module_id, enabled: !enabled })}>
                    {enabled ? 'Désactiver' : 'Activer'}
                  </Button>
                )}
              </Section>
            )
          })}
        </div>
      )}
    </>
  )
}
