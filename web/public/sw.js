// Hors-ligne partiel : seuls les fichiers statiques de l'application (/assets, icône) et la page d'accueil sont mis en cache.
// Aucune réponse de l'API, de l'authentification ni des données salariés n'est jamais stockée (autre origine ou chemin non listé).
const CACHE = 'soma-rh-shell-v1'

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(['/', '/favicon.svg'])).then(() => self.skipWaiting()))
})

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim()),
  )
})

self.addEventListener('fetch', (e) => {
  const req = e.request
  const url = new URL(req.url)
  if (req.method !== 'GET' || url.origin !== self.location.origin) return
  if (req.mode === 'navigate') {
    // Réseau d'abord ; la page d'accueil en cache sert de secours hors connexion.
    e.respondWith(fetch(req).catch(() => caches.match('/')))
  } else if (url.pathname.startsWith('/assets/') || url.pathname === '/favicon.svg') {
    // Fichiers à empreinte : cache d'abord.
    e.respondWith(
      caches.match(req).then((hit) => hit || fetch(req).then((res) => {
        if (res.ok) { const copy = res.clone(); caches.open(CACHE).then((c) => c.put(req, copy)) }
        return res
      })),
    )
  }
})
