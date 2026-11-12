// Masquage des champs sensibles avant une capture (partagé par capture.ts et tests/unit/capture.mask.test.mjs).
export const SECRET_SELECTOR =
  'input[type=password], input[autocomplete=one-time-code], input[name*="token" i], input[id*="token" i], input[name*="secret" i], input[placeholder*="jeton" i]'
export const MASK = '••••••••'

/** Remplace la valeur de chaque champ sensible par une valeur fixe (la longueur réelle ne fuit pas). Retourne le nombre de champs masqués. */
export function maskSecrets(page) {
  return page.evaluate(([sel, mask]) => {
    const els = [...document.querySelectorAll(sel)]
    for (const el of els) {
      el.value = mask
      el.setAttribute('value', mask)
    }
    return els.length
  }, [SECRET_SELECTOR, MASK])
}
