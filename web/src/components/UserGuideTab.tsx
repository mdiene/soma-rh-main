import clsx from 'clsx'
import { useEffect, useMemo, useState } from 'react'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import docsConfig from '../../../docs/docs.json'
import { Spinner } from './ui'

// Le guide est lu depuis docs/guide-utilisateur (même source que le site Mintlify) : une seule rédaction.
// L'ordre et la liste des pages viennent du groupe « Guide utilisateur » de docs/docs.json.
// Écrire les pages en Markdown simple (pas de composants JSX Mintlify) pour qu'elles s'affichent ici comme en ligne.
const SOURCES = import.meta.glob('../../../docs/guide-utilisateur/*.{md,mdx}', { query: '?raw', import: 'default' }) as Record<string, () => Promise<string>>
const IMAGES = import.meta.glob('../../../docs/guide-utilisateur/**/*.{png,jpg,jpeg,webp,gif,svg}', { eager: true, query: '?url', import: 'default' }) as Record<string, string>

type Group = { group?: string; pages?: (string | Group)[] }
const flatten = (pages: (string | Group)[] = []): string[] => pages.flatMap((p) => (typeof p === 'string' ? [p] : flatten(p.pages)))
const SLUGS = flatten(((docsConfig.navigation.groups as Group[]).find((g) => g.group === 'Guide utilisateur'))?.pages)
  .map((p) => p.replace(/^guide-utilisateur\//, ''))

const sourceOf = (slug: string) => SOURCES[`../../../docs/guide-utilisateur/${slug}.mdx`] ?? SOURCES[`../../../docs/guide-utilisateur/${slug}.md`]
const imageOf = (src: string) => IMAGES[`../../../docs${src}`] ?? src

/** Sépare l'en-tête YAML (title, description) du corps. */
function parse(raw: string) {
  const m = raw.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/)
  const field = (k: string) => m?.[1].match(new RegExp(`^${k}:\\s*"?(.*?)"?\\s*$`, 'm'))?.[1]
  return { title: field('title'), description: field('description'), body: m ? raw.slice(m[0].length) : raw }
}

export function UserGuideTab() {
  const available = useMemo(() => SLUGS.filter((s) => sourceOf(s)), [])
  const [slug, setSlug] = useState(available[0])
  const [pages, setPages] = useState<Record<string, ReturnType<typeof parse>>>({})
  const [failed, setFailed] = useState(false)

  // Charge tous les titres pour le sommaire (fichiers courts), puis affiche la page choisie.
  useEffect(() => {
    let alive = true
    Promise.all(available.map(async (s) => [s, parse(await sourceOf(s)())] as const))
      .then((all) => { if (alive) setPages(Object.fromEntries(all)) })
      .catch(() => { if (alive) setFailed(true) })
    return () => { alive = false }
  }, [available])

  if (available.length === 0) return <p className="text-sm text-ink-soft">Aucune page de guide n'est disponible dans cette version.</p>
  if (failed) return <p role="alert" className="text-sm text-signal">Le guide n'a pas pu être chargé.</p>
  if (!Object.keys(pages).length) return <Spinner />
  const page = pages[slug]

  return (
    <div className="grid gap-4 lg:grid-cols-[16rem_minmax(0,1fr)]">
      <nav aria-label="Pages du guide" className="flex flex-row flex-wrap gap-1 lg:flex-col">
        {available.map((s) => (
          <button key={s} type="button" aria-current={slug === s} onClick={() => setSlug(s)}
            className={clsx('rounded px-3 py-2 text-left text-sm', slug === s ? 'bg-river text-white' : 'text-ink-soft hover:bg-white hover:text-ink')}>
            {pages[s]?.title ?? s}
          </button>
        ))}
      </nav>
      <article className="max-w-3xl text-sm leading-relaxed">
        <h2 className="mb-1 text-lg font-semibold">{page?.title}</h2>
        {page?.description && <p className="mb-4 text-ink-soft">{page.description}</p>}
        <ReactMarkdown remarkPlugins={[remarkGfm]}
          components={{
            h2: (p) => <h3 className="mb-2 mt-6 text-base font-semibold">{p.children}</h3>,
            h3: (p) => <h4 className="mb-1 mt-4 font-semibold">{p.children}</h4>,
            p: (p) => <p className="my-2">{p.children}</p>,
            ul: (p) => <ul className="my-2 list-disc space-y-1 pl-5">{p.children}</ul>,
            ol: (p) => <ol className="my-2 list-decimal space-y-2 pl-5">{p.children}</ol>,
            table: (p) => <div className="my-3 overflow-x-auto"><table className="w-full text-sm">{p.children}</table></div>,
            th: (p) => <th className="table-head px-2 py-1.5 text-left">{p.children}</th>,
            td: (p) => <td className="border-b border-line/70 px-2 py-1.5">{p.children}</td>,
            code: (p) => <code className="rounded bg-paper px-1 py-0.5 text-xs">{p.children}</code>,
            img: ({ src, alt }) => <img src={imageOf(src ?? '')} alt={alt ?? ''} loading="lazy" className="my-3 max-w-full rounded border border-line" />,
            a: ({ href = '', children }) => {
              const internal = href.match(/^\/guide-utilisateur\/([^#]+)/)?.[1]
              return internal && available.includes(internal)
                ? <button type="button" className="font-medium text-river underline" onClick={() => setSlug(internal)}>{children}</button>
                : <a href={href} className="font-medium text-river underline" target="_blank" rel="noreferrer">{children}</a>
            },
          }}>
          {page?.body ?? ''}
        </ReactMarkdown>
      </article>
    </div>
  )
}
