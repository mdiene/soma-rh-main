import { useEffect } from 'react'
import { useLocation } from 'react-router-dom'

/**
 * Lien « Corriger » du centre de conformité : `?surligne=<clé>` met en évidence l'élément
 * marqué `data-fix="<clé>"` (champ, section…) et le fait défiler à l'écran.
 * La page charge ses données après l'affichage : on attend l'élément (10 s au plus).
 */
export function useHighlight() {
  const { pathname, search } = useLocation()
  useEffect(() => {
    const key = new URLSearchParams(search).get('surligne')
    if (!key) return
    let done = false
    let targets: Element[] = []
    const find = () => {
      const els = [...document.querySelectorAll('[data-fix]')].filter((e) => e.getAttribute('data-fix') === key)   // plusieurs lignes possibles (retenues)
      if (!els.length || done) return
      done = true
      targets = els.map((el) => el.closest('label') ?? el)
      targets[0].scrollIntoView({ block: 'center', behavior: 'smooth' })
      targets.forEach((t) => t.classList.add('fix-highlight'))
      const el = els[0]
      if (el instanceof HTMLInputElement || el instanceof HTMLSelectElement) el.focus({ preventScroll: true })
      obs.disconnect()
    }
    const obs = new MutationObserver(find)
    obs.observe(document.body, { childList: true, subtree: true })
    find()
    const stop = setTimeout(() => obs.disconnect(), 10_000)
    const off = () => targets.forEach((t) => t.classList.remove('fix-highlight'))
    const clear = setTimeout(off, 12_000)
    return () => { obs.disconnect(); clearTimeout(stop); clearTimeout(clear); off() }
  }, [pathname, search])
}
