import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { execSync } from 'node:child_process'

// Identification du build, affichée dans « À propos » et « Sauvegardes et versions » (aucun secret)
const commit = (() => { try { return execSync('git rev-parse --short HEAD', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim() } catch { return '' } })()

// https://vite.dev/config/
// Proxy de développement : permet d'appeler l'API depuis la même origine que le site (VITE_API_URL=http://localhost:5173),
// utile quand un navigateur restreint (ex. celui de Claude Desktop) bloque les appels vers un autre port.
// 127.0.0.1 et non « localhost » : sous Windows, Docker Desktop peut laisser le transfert de port en IPv6 (::1) sans réponse
const api = 'http://127.0.0.1:8000'
export default defineConfig({
  plugins: [react()],
  define: { __APP_COMMIT__: JSON.stringify(commit), __APP_BUILD_DATE__: JSON.stringify(new Date().toISOString().slice(0, 10)) },
  // fs.allow : l'onglet « Documentation utilisateur » lit docs/ (hors de web/) ; sans cela le serveur de développement répond 403 aux images du guide.
  server: { fs: { allow: ['..'] }, proxy: { '/auth/v1': api, '/rest/v1': api, '/api/v1': api } },
})
