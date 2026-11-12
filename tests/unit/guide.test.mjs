import { test } from 'node:test'
import assert from 'node:assert/strict'
import { existsSync, readFileSync, readdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

// Contrôle du guide utilisateur : navigation, fichiers, images, liens internes, absence de JSX et de secrets.
const DOCS = fileURLToPath(new URL('../../docs/', import.meta.url))
const GUIDE = `${DOCS}guide-utilisateur/`
const nav = JSON.parse(readFileSync(`${DOCS}docs.json`, 'utf8'))
const pages = nav.navigation.groups.find((g) => g.group === 'Guide utilisateur').pages
const fichier = (p) => [`${DOCS}${p}.mdx`, `${DOCS}${p}.md`].find(existsSync)
const lire = (p) => readFileSync(fichier(p), 'utf8')
const sansCode = (t) => t.replace(/```[\s\S]*?```/g, '').replace(/`[^`\n]*`/g, '')

test('chaque page de la navigation existe', () => {
  for (const p of pages) assert.ok(fichier(p), `page absente : ${p}`)
})

test('aucune page du dossier hors navigation (hors index CSV et captures)', () => {
  const presentes = readdirSync(GUIDE).filter((f) => /\.mdx?$/.test(f)).map((f) => `guide-utilisateur/${f.replace(/\.mdx?$/, '')}`)
  const hors = presentes.filter((p) => !pages.includes(p))
  assert.deepEqual(hors, [], `pages hors navigation : ${hors.join(', ')}`)
})

test('chaque image référencée existe', () => {
  for (const p of pages) {
    for (const [, chemin] of lire(p).matchAll(/!\[[^\]]*\]\((\/[^)\s]+)\)/g)) {
      assert.ok(existsSync(`${DOCS}${chemin.slice(1)}`), `${p} : image absente ${chemin}`)
    }
  }
})

test('chaque image a un texte alternatif', () => {
  for (const p of pages) assert.ok(!/!\[\]\(/.test(lire(p)), `${p} : image sans texte alternatif`)
})

test('chaque lien interne pointe vers une page existante', () => {
  for (const p of pages) {
    for (const [, cible] of sansCode(lire(p)).matchAll(/(?<!!)\[[^\]]+\]\((\/[^)\s#]+)\)/g)) {
      assert.ok(fichier(cible.slice(1)), `${p} : lien cassé ${cible}`)
    }
  }
})

test('aucun composant JSX dans les pages', () => {
  for (const p of pages) {
    const m = sansCode(lire(p)).match(/<\/?[A-Z][A-Za-z]*[\s>/]/)
    assert.equal(m, null, `${p} : composant JSX ${m?.[0]}`)
  }
})

test('aucun mot de passe ni jeton dans les pages et le suivi', () => {
  const motifs = [/eyJ[A-Za-z0-9_-]{15,}/, /sb_(publishable|secret)_[A-Za-z0-9_-]+/, /Qa![A-Za-z0-9]{8,}/, /(mot de passe|password)\s*[:=]\s*\S{6,}/i, /Bearer\s+[A-Za-z0-9._-]{20,}/]
  const cibles = [...pages.map((p) => fichier(p)), `${DOCS}recette/SUIVI_GUIDE.md`]
  for (const f of cibles) {
    const t = readFileSync(f, 'utf8')
    for (const re of motifs) assert.equal(re.test(t), false, `${f} : motif sensible ${re}`)
  }
})
