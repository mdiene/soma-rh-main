import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
// Proxy de développement : permet d'appeler l'API depuis la même origine que le site (VITE_API_URL=http://localhost:5173),
// utile quand un navigateur restreint (ex. celui de Claude Desktop) bloque les appels vers un autre port.
const api = 'http://localhost:8000'
export default defineConfig({
  plugins: [react()],
  // fs.allow : l'onglet « Documentation utilisateur » lit docs/ (hors de web/) ; sans cela le serveur de développement répond 403 aux images du guide.
  server: { fs: { allow: ['..'] }, proxy: { '/auth/v1': api, '/rest/v1': api, '/api/v1': api } },
})
