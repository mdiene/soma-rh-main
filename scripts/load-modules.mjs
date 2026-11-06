// Charge les manifestes de docs/modules/manifests/*.json dans la base locale (M0).
// Valide chaque fichier contre docs/modules/manifest.schema.json (ajv de web/node_modules), calcule le hash
// sha256 du contenu, puis appelle public.load_module_manifest en tant que RH (via psql dans le conteneur).
// Usage : node scripts/load-modules.mjs [--check]   (--check : valide seulement, n'écrit rien)
import { readFileSync, readdirSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { createRequire } from 'node:module'
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const Ajv = createRequire(join(root, 'web', 'package.json'))('ajv')
const validate = new Ajv({ allErrors: true }).compile(JSON.parse(readFileSync(join(root, 'docs/modules/manifest.schema.json'), 'utf8')))
const dir = join(root, 'docs/modules/manifests')
const checkOnly = process.argv.includes('--check')
let failed = false

for (const f of readdirSync(dir).filter((x) => x.endsWith('.json'))) {
  const raw = readFileSync(join(dir, f))
  const text = raw.toString('utf8')
  const manifest = JSON.parse(text)
  if (!validate(manifest)) {
    failed = true
    console.error(`ECHEC ${f}`)
    for (const e of validate.errors) console.error(`  ${e.dataPath || '/'} ${e.message}`)
    continue
  }
  if (checkOnly) { console.log(`OK ${f} (valide)`); continue }
  if (text.includes('$m0$')) { failed = true; console.error(`ECHEC ${f} : contient la balise $m0$`); continue }
  const hash = createHash('sha256').update(raw).digest('hex')
  // La RH est simulée par le JWT d'un utilisateur ayant le rôle rh ; dollar-quoting pour le JSON.
  const sql =
    `begin; select set_config('request.jwt.claim.sub', (select user_id::text from public.user_roles where role='rh' order by user_id limit 1), true);` +
    `set local role authenticated;` +
    `select public.load_module_manifest($m0$${JSON.stringify(manifest)}$m0$::jsonb, '${hash}'); commit;`
  const out = execFileSync('docker', ['exec', '-i', 'soma-rh-local-postgres-1', 'psql', '-U', 'soma', '-d', 'soma_rh', '-At', '-v', 'ON_ERROR_STOP=1'], { input: sql, encoding: 'utf8' })
  console.log(`OK ${f}: ${out.split('\n').find((l) => l.startsWith('{')) ?? out.trim()}`)
}
process.exit(failed ? 1 : 0)
