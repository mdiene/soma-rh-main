import http from 'node:http'
import { createHash, randomBytes, randomUUID } from 'node:crypto'
import { mkdir, readFile, unlink, writeFile } from 'node:fs/promises'
import path from 'node:path'
import bcrypt from 'bcryptjs'
import { SignJWT, jwtVerify } from 'jose'
import pg from 'pg'
import { PDFDocument, StandardFonts, rgb } from 'pdf-lib'
import { createDocumentThumbnail } from './thumbnail.mjs'
import {
  NEUTRAL_OPEN_MESSAGE, NEUTRAL_REQUEST_MESSAGE, createLoginLimiter, createPersistentLimiter, emailToPhone, hashIp, hashToken,
  clientAddress, isPhoneEmail, parseBirthDate, passwordProblem, phoneToEmail,
} from './phone.mjs'

// Store for rate limiting and brute force tracking (in-memory for simplicity;
// in production use Redis or database with persistence)
const rateLimitStore = new Map() // ip -> { count, resetTime }

// La table public.refresh_tokens est créée par la migration 20261105120000_refresh_tokens.sql (D-017).

// Refresh token store (in-memory; in production use persisted store with rotation)
// Format: { [token]: { userId, createdAt, lastUsed, valid: true } }
const refreshTokenStore = new Map()

// Adresse du client : request.ip n'existe pas sur http.IncomingMessage, d'où un compteur commun à tous (D-017)
function clientIp(request) {
  return clientAddress(request.socket?.remoteAddress, request.headers['x-forwarded-for'], process.env.TRUST_PROXY === '1')
}

// Simple rate limiter middleware factory
function rateLimitMiddleware(max, windowMs) {
  return async (request, response, next) => {
    const ip = clientIp(request)
    const now = Date.now()
    const entry = rateLimitStore.get(ip)

    if (entry && now < entry.resetTime) {
      // Still within rate limit window and exceeded
      if (entry.count >= max) {
        const retryAfter = Math.ceil((entry.resetTime - now) / 1000)
        return json(response, 429, {
          message: 'Trop de requêtes, réessayez dans ' + retryAfter + ' secondes',
        })
      }
      entry.count++
    } else {
      // New window
      rateLimitStore.set(ip, { count: 1, resetTime: now + windowMs })
    }

    next()
  }
}

// Helper: hash a refresh token for secure storage
function hashRefreshToken(token) {
  return createHash('sha256').update(token).digest('hex')
}

// Helper: create a refresh token and return the plain token
async function issueRefreshToken(userId) {
  const token = randomUUID()
  const tokenHash = hashRefreshToken(token)
  const expiresAt = new Date(Date.now() + SECURITY.refreshTokenTtl)
  await pool.query(
    `INSERT INTO public.refresh_tokens (user_id, token_hash, expires_at)
     VALUES ($1, $2, $3)`,
    [userId, tokenHash, expiresAt],
  )
  refreshTokenStore.set(token, { userId, createdAt: new Date(), lastUsed: new Date(), valid: true })
  return token
}

// Rotate refresh token : invalide le précédent, en crée un nouveau
async function rotateRefreshToken(userId, email) {
  // Invalider tous les tokens anciens pour cet utilisateur
  await pool.query(
    `UPDATE public.refresh_tokens SET is_revoked = TRUE WHERE user_id = $1 AND is_revoked = FALSE`,
    [userId],
  )
  // Créer un nouveau token
  return await issueRefreshToken(userId)
}

// Révoke un token spécifique (par ex. lors du logout)
async function revokeRefreshToken(token) {
  const tokenHash = hashRefreshToken(token)
  await pool.query(
    `UPDATE public.refresh_tokens SET is_revoked = TRUE WHERE token_hash = $1 AND is_revoked = FALSE`,
    [tokenHash],
  )
  // Remove from in-memory store
  refreshTokenStore.delete(token)
}

const { Pool } = pg
const port = Number(process.env.PORT ?? 8000)
const postgrestUrl = process.env.POSTGREST_URL ?? 'http://postgrest:3000'
const jwtSecret = process.env.JWT_SECRET
// Security configuration (override via env in production)
const SECURITY = {
  // Inscription : false = fermée (admin uniquement), true = ouverte
  signupEnabled: process.env.SIGNUP_ENABLED === 'true', // fermée par défaut (D-016)
  // Rate limiting : max requêtes par intervalle par IP
  rateLimit: {
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: Number(process.env.RATE_LIMIT_MAX ?? 120), // RPR-03 : limite par adresse séparée du verrou par compte, 120 requêtes sensibles/15 min par défaut
  },
  // Refresh token : expiration en ms (24h par défaut)
  refreshTokenTtl: Number(process.env.REFRESH_TOKEN_TTL ?? 24 * 60 * 60 * 1000),
  // Anti-force brute : échecs avant verrouillage
  bruteForceMax: Number(process.env.BRUTE_FORCE_MAX ?? 5),
  // TOTP : configurable par rôle (admin/rh sensibles)
  totpEnabled: process.env.TOTP_ENABLED === 'true',
};
if (!jwtSecret) throw new Error('JWT_SECRET is required')

const pool = new Pool({ connectionString: process.env.DATABASE_URL })
const secret = new TextEncoder().encode(jwtSecret)
const documentRoot = process.env.DOCUMENT_ROOT ?? '/data/documents'
const maxDocumentBytes = 10 * 1024 * 1024

await mkdir(documentRoot, { recursive: true })

async function issueToken(user) {
  return new SignJWT({ role: 'authenticated', aud: 'authenticated', email: user.email })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(user.id)
    .setIssuedAt()
    .setExpirationTime('8h')
    .sign(secret)
}

async function body(request, maxBytes = 25 * 1024 * 1024) {
  if (request.parsedBody) return request.parsedBody // corps déjà lu par auth() (le flux ne se relit pas)
  const chunks = []
  let size = 0
  for await (const chunk of request) {
    size += chunk.length
    if (size > maxBytes) throw Object.assign(new Error('Corps trop volumineux'), { code: 'BODY_TOO_LARGE' })
    chunks.push(chunk)
  }
  if (!chunks.length) return {}
  const raw = Buffer.concat(chunks).toString('utf8')
  const contentType = request.headers['content-type'] ?? ''
  if (contentType.includes('application/x-www-form-urlencoded')) {
    return Object.fromEntries(new URLSearchParams(raw))
  }
  return JSON.parse(raw)
}

function json(response, status, value) {
  response.writeHead(status, { 'content-type': 'application/json' })
  response.end(JSON.stringify(value))
}

async function binaryBody(request, limit = maxDocumentBytes) {
  const chunks = []
  let total = 0
  for await (const chunk of request) {
    total += chunk.length
    if (total > limit) throw new Error('Fichier trop volumineux (10 Mo maximum)')
    chunks.push(chunk)
  }

  return Buffer.concat(chunks)
}

function safeFileName(value) {
  const normalized = value.normalize('NFKC').replace(/[^a-zA-Z0-9._-]/g, '_').slice(0, 120)
  return normalized || 'document'
}

function sendPdf(response, bytes, fileName) {
  response.writeHead(200, {
    'content-type': 'application/pdf',
    'content-disposition': `inline; filename="${safeFileName(fileName)}"`,
    'content-length': bytes.length,
    'cache-control': 'private, no-store',
  })
  response.end(Buffer.from(bytes))
}

async function documentRoute(request, response, url) {
  const token = request.headers.authorization?.replace(/^Bearer\s+/i, '')
  if (!token) return json(response, 401, { message: 'Authentification requise' }), true
  const { payload } = await jwtVerify(token, secret, { audience: 'authenticated', algorithms: ['HS256'] })
  const userId = String(payload.sub ?? '')
  if (!userId) return json(response, 401, { message: 'Session invalide' }), true

  const bundleMatch = url.pathname.match(/^\/api\/v1\/employees\/([0-9a-f-]{36})\/documents\/bundle$/i)
  if (request.method === 'GET' && bundleMatch) {
    const employeeId = bundleMatch[1]
    const access = await pool.query(
      `select e.first_name, e.last_name, e.employee_number,
              exists(select 1 from public.user_roles where user_id = $1 and role in ('admin','rh')) as can_manage,
              e.user_id = $1 as is_owner
         from public.employees e
        where e.id = $2`,
      [userId, employeeId],
    )
    const employee = access.rows[0]
    if (!employee) return json(response, 404, { message: 'Salarié introuvable' }), true
    if (!employee.can_manage && !employee.is_owner) return json(response, 403, { message: 'Accès interdit à ce dossier' }), true

    const documents = await pool.query(
      `select d.title, d.file_name, d.mime_type, d.storage_path, d.thumbnail_path, d.document_slot,
              coalesce(r.sort_order, 9999) as sort_order
         from public.employee_documents d
         left join public.document_requirements r on r.code = d.requirement_code
        where d.employee_id = $1 and d.archived_at is null
        order by coalesce(r.sort_order, 9999), d.document_slot, d.created_at`,
      [employeeId],
    )
    const bundle = await PDFDocument.create()
    const font = await bundle.embedFont(StandardFonts.Helvetica)
    const boldFont = await bundle.embedFont(StandardFonts.HelveticaBold)
    const cover = bundle.addPage()
    const { width, height } = cover.getSize()
    cover.drawText('Dossier administratif salarié', { x: 54, y: height - 90, size: 22, font: boldFont, color: rgb(0.08, 0.16, 0.2) })
    cover.drawText(`${employee.first_name} ${employee.last_name}`, { x: 54, y: height - 130, size: 16, font: boldFont })
    cover.drawText(`Matricule : ${employee.employee_number}`, { x: 54, y: height - 155, size: 11, font })
    cover.drawText(`Généré le : ${new Date().toLocaleDateString('fr-FR')}`, { x: 54, y: height - 175, size: 11, font, color: rgb(0.3, 0.35, 0.38) })
    cover.drawText(`${documents.rows.length} document(s) intégré(s)`, { x: 54, y: height - 220, size: 13, font: boldFont, color: rgb(0.08, 0.35, 0.45) })

    for (const document of documents.rows) {
      const source = await readFile(path.join(documentRoot, document.storage_path))
      if (document.mime_type === 'application/pdf') {
        const sourcePdf = await PDFDocument.load(source)
        const pages = await bundle.copyPages(sourcePdf, sourcePdf.getPageIndices())
        pages.forEach((page) => bundle.addPage(page))
        continue
      }
      const page = bundle.addPage()
      const image = document.mime_type === 'image/png' ? await bundle.embedPng(source) : document.mime_type === 'image/jpeg' ? await bundle.embedJpg(source) : await bundle.embedJpg(await readFile(path.join(documentRoot, document.thumbnail_path)))
      const scale = Math.min((width - 72) / image.width, (height - 150) / image.height, 1)
      const imageWidth = image.width * scale
      const imageHeight = image.height * scale
      page.drawText(document.title + (document.document_slot > 1 ? ` n°${document.document_slot}` : ''), { x: 36, y: height - 42, size: 12, font: boldFont })
      page.drawImage(image, { x: (width - imageWidth) / 2, y: (height - imageHeight - 55) / 2, width: imageWidth, height: imageHeight })
      page.drawText(document.file_name, { x: 36, y: 24, size: 8, font, color: rgb(0.35, 0.35, 0.35) })
    }
    return sendPdf(response, await bundle.save(), `dossier-${safeFileName(employee.employee_number)}.pdf`), true
  }

  if (request.method === 'POST' && url.pathname === '/api/v1/documents/upload') {
    const employeeId = String(request.headers['x-employee-id'] ?? '')
    const requirementCode = String(request.headers['x-requirement-code'] ?? '')
    const documentSlot = Math.max(1, Number(request.headers['x-document-slot'] ?? 1))
    const mimeType = String(request.headers['x-file-mime'] ?? request.headers['content-type'] ?? '')
    const encodedName = String(request.headers['x-file-name'] ?? '')
    const fileName = encodedName ? Buffer.from(encodedName, 'base64').toString('utf8') : 'document'
    if (!/^[0-9a-f-]{36}$/i.test(employeeId) || !/^[a-z0-9_]+$/.test(requirementCode)) {
      return json(response, 400, { message: 'Référence de document invalide' }), true
    }
    const allowedMime = ['application/pdf', 'image/jpeg', 'image/png', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document']
    if (!allowedMime.includes(mimeType)) return json(response, 415, { message: 'Format accepté : PDF, Word, JPEG ou PNG' }), true

    const access = await pool.query(
      `select exists(select 1 from public.user_roles where user_id = $1 and role in ('admin','rh')) as can_manage,
              exists(select 1 from public.employees where id = $2 and user_id = $1) as is_owner`,
      [userId, employeeId],
    )
    const actor = access.rows[0]
    if (!actor?.can_manage && !actor?.is_owner) return json(response, 403, { message: 'Accès interdit à ce dossier' }), true

    const requirement = await pool.query(
      'select code, title, allowed_mime_types, max_size_bytes from public.document_requirements where code = $1 and active',
      [requirementCode],
    )
    const definition = requirement.rows[0]
    if (!definition) return json(response, 422, { message: 'Type de document inconnu' }), true
    if (!definition.allowed_mime_types.includes(mimeType)) return json(response, 415, { message: 'Format non autorisé pour ce document' }), true

    const file = await binaryBody(request, Math.min(Number(definition.max_size_bytes), maxDocumentBytes))
    if (!file.length) return json(response, 400, { message: 'Le fichier est vide' }), true
    const checksum = createHash('sha256').update(file).digest('hex')
    const storagePath = path.join(employeeId, `${requirementCode}-${randomUUID()}-${safeFileName(fileName)}`)
    const thumbnailPath = path.join(employeeId, `thumbnail-${randomUUID()}.jpg`)
    const absolutePath = path.join(documentRoot, storagePath)
    const absoluteThumbnailPath = path.join(documentRoot, thumbnailPath)
    await mkdir(path.dirname(absolutePath), { recursive: true })
    await writeFile(absolutePath, file, { flag: 'wx' })
    await writeFile(absoluteThumbnailPath, await createDocumentThumbnail(file, fileName, mimeType), { flag: 'wx' })

    const client = await pool.connect()
    try {
      await client.query('begin')
        const current = await client.query(
          'select id, current_version from public.employee_documents where employee_id = $1 and requirement_code = $2 and document_slot = $3 and archived_at is null for update',
          [employeeId, requirementCode, documentSlot],
      )
      let document
      let version
      if (current.rows[0]) {
        version = Number(current.rows[0].current_version) + 1
        document = await client.query(
          `update public.employee_documents
           set file_name = $1, storage_path = $2, mime_type = $3, size_bytes = $4, checksum = $5,
               thumbnail_path = $6,
               status = 'en_attente', rejection_reason = null, validated_by = null, validated_at = null,
               current_version = $7, submitted_at = now(), archived_at = null, archived_by = null
           where id = $8 returning *`,
          [fileName, storagePath, mimeType, file.length, checksum, thumbnailPath, version, current.rows[0].id],
        )
      } else {
        version = 1
        document = await client.query(
          `insert into public.employee_documents
             (employee_id, document_type, requirement_code, document_slot, title, file_name, storage_path, thumbnail_path, mime_type, size_bytes, checksum, created_by, status, current_version, submitted_at)
           values ($1, $2, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 'en_attente', 1, now()) returning *`,
          [employeeId, requirementCode, requirementCode === 'situation_matrimoniale' || requirementCode === 'actes_enfants' ? documentSlot : 1, definition.title, fileName, storagePath, thumbnailPath, mimeType, file.length, checksum, userId],
        )
      }
      await client.query(
        `insert into public.document_versions
          (document_id, version_number, storage_path, file_name, mime_type, size_bytes, checksum, uploaded_by)
         values ($1, $2, $3, $4, $5, $6, $7, $8)`,
        [document.rows[0].id, version, storagePath, fileName, mimeType, file.length, checksum, userId],
      )
      await client.query('commit')
      return json(response, 201, { document: document.rows[0] }), true
    } catch (error) {
      await client.query('rollback')
      await unlink(absolutePath).catch(logUnlink)
      await unlink(absoluteThumbnailPath).catch(logUnlink)
      throw error
    } finally {
      client.release()
    }
  }

  if (request.method === 'GET' && url.pathname.startsWith('/api/v1/documents/')) {
    const isThumbnail = url.pathname.endsWith('/thumbnail')
    const documentId = url.pathname.split('/').slice(-1 - (isThumbnail ? 1 : 0))[0]
    if (!/^[0-9a-f-]{36}$/i.test(documentId ?? '')) return json(response, 400, { message: 'Document invalide' }), true
    const result = await pool.query(
      `select d.storage_path, d.thumbnail_path, d.file_name, d.mime_type
       from public.employee_documents d
       where d.id = $1 and (
         exists(select 1 from public.user_roles where user_id = $2 and role in ('admin','rh'))
         or exists(select 1 from public.employees e where e.id = d.employee_id and e.user_id = $2)
       )`,
      [documentId, userId],
    )
    if (!result.rows[0]) return json(response, 404, { message: 'Document introuvable ou non autorisé' }), true
    const item = result.rows[0]
    const file = await readFile(path.join(documentRoot, isThumbnail ? item.thumbnail_path : item.storage_path))
    await pool.query(
      'insert into public.employee_document_access_log(document_id, user_id) values ($1, $2)',
      [documentId, userId],
    )
    response.writeHead(200, { 'content-type': isThumbnail ? 'image/jpeg' : item.mime_type, 'content-disposition': `inline; filename="${safeFileName(item.file_name)}"`, 'cache-control': 'private, no-store' })
    response.end(file)
    return true
  }
  if (request.method === 'DELETE' && url.pathname.startsWith('/api/v1/documents/')) {
    const documentId = url.pathname.split('/').pop()
    if (!/^[0-9a-f-]{36}$/i.test(documentId ?? '')) return json(response, 400, { message: 'Document invalide' }), true
    const access = await pool.query(
      `select d.storage_path, d.thumbnail_path
       from public.employee_documents d
       where d.id = $1
         and exists(select 1 from public.user_roles where user_id = $2 and role in ('admin','rh'))`,
      [documentId, userId],
    )
    if (!access.rows[0]) return json(response, 404, { message: 'Document introuvable ou non autorisé' }), true
    await pool.query('delete from public.employee_documents where id = $1', [documentId])
    await unlink(path.join(documentRoot, access.rows[0].storage_path)).catch(logUnlink)
    if (access.rows[0].thumbnail_path) await unlink(path.join(documentRoot, access.rows[0].thumbnail_path)).catch(logUnlink)
    return json(response, 200, { deleted: true }), true
  }
  return false
}

function setCors(request, response) {
  const origin = request.headers.origin
  if (origin === 'http://localhost:5173' || origin === 'http://127.0.0.1:5173') {
    response.setHeader('access-control-allow-origin', origin)
    response.setHeader('access-control-allow-credentials', 'true')
  }
  response.setHeader('access-control-allow-headers', 'authorization, apikey, content-type, accept, accept-profile, content-profile, prefer, range, x-client-info, x-supabase-api-version, x-employee-id, x-requirement-code, x-document-slot, x-file-name, x-file-mime')
  response.setHeader('access-control-allow-methods', 'GET, POST, PATCH, PUT, DELETE, OPTIONS')
}

// Connexion par téléphone : verrouillage progressif par couple numéro + adresse (jamais par adresse seule, RPR-03)
// État en base (survit au redémarrage, partagé entre instances), repli en mémoire si la base est indisponible
const persistent = (prefix, maxFailures) => createPersistentLimiter({
  query: (sql, params) => pool.query(sql, params), memory: createLoginLimiter({ maxFailures }), prefix, maxFailures, salt: () => jwtSecret,
})
const phoneLoginLimiter = persistent('phone', 5)
const emailLoginLimiter = persistent('email', SECURITY.bruteForceMax)

// RPR-03 : chaque verrouillage de connexion est journalisé (compte masqué, adresse hachée) et remonte dans les alertes de l'administrateur
const maskEmail = (email) => {
  const [local = '', domain = ''] = String(email ?? '').toLowerCase().split('@')
  return `${local.slice(0, 2)}***@${domain.slice(0, 60)}`
}
async function logLoginLock(email, ipHash) {
  try {
    await pool.query(
      "insert into public.audit_events (action, resource_type, result, after_data) values ('verrouillage_connexion', 'auth', 'denied', jsonb_build_object('account', $1::text, 'ip_hash', $2::text))",
      [maskEmail(email), ipHash],
    )
  } catch (error) {
    console.error('Journal du verrouillage indisponible :', error.message) // ne jamais empêcher la réponse de connexion
  }
}
// Hachage bcrypt (coût 12) d'un mot de passe inconnu : sert à égaliser le temps de réponse quand le compte n'existe pas
// Suppression de fichier : l'absence du fichier est normale, toute autre erreur laisse une trace (pièce orpheline)
const logUnlink = (error) => { if (error?.code !== 'ENOENT') console.error('Suppression de fichier impossible :', error?.message) }
const DUMMY_HASH = bcrypt.hashSync(randomBytes(16).toString('hex'), 12)
// Le journal des connexions ne doit jamais empêcher la réponse (comme logLoginLock), mais l'échec est tracé
async function logPhoneLogin(phone, action) {
  try { await pool.query('select public.phone_access_log_login($1, $2)', [phone, action]) }
  catch (error) { console.error('Journal de connexion téléphone indisponible :', error.message) }
}
const phoneRoutes = ['/auth/v1/phone/request', '/auth/v1/phone/open', '/auth/v1/phone/set-password']
const ipSalt = () => jwtSecret
const phoneDb = (fn, params) => pool.query(`select public.${fn} as r`, params).then((x) => x.rows[0].r)

async function phoneAuth(request, response, pathname) {
  const input = await body(request)
  const ipHash = hashIp(clientIp(request), ipSalt())

  // 1. Demande d'accès : toujours la même réponse, que le numéro existe ou non
  if (pathname === '/auth/v1/phone/request') {
    await pool.query('select public.phone_access_request($1, $2)', [String(input.phone ?? '').slice(0, 40), ipHash])
    return json(response, 200, { status: 'received', message: NEUTRAL_REQUEST_MESSAGE })
  }

  // 2. Ouverture de l'activation : numéro (+ date de naissance) ; renvoie un jeton de 15 min à usage unique
  if (pathname === '/auth/v1/phone/open') {
    const token = randomBytes(24).toString('hex')
    const ok = await phoneDb('phone_access_open($1, $2::date, $3, $4)',
      [String(input.phone ?? '').slice(0, 40), parseBirthDate(input.second), ipHash, hashToken(token)])
    return ok
      ? json(response, 200, { status: 'ready', token })
      : json(response, 200, { status: 'pending', message: NEUTRAL_OPEN_MESSAGE })
  }

  // 3. Définition du mot de passe (création ou réinitialisation)
  const client = await pool.connect()
  try {
    await client.query('begin')
    const tokenHash = hashToken(input.token ?? '')
    const peek = (await client.query('select * from public.phone_access_peek($1)', [tokenHash])).rows[0]
    if (!peek) {
      await client.query('rollback')
      return json(response, 400, { message: "Le lien d'activation est invalide ou a expiré. Recommencez la saisie de votre numéro." })
    }
    const problem = passwordProblem(input.password, {
      phone: peek.phone_e164, firstName: peek.first_name, lastName: peek.last_name, employeeNumber: peek.employee_number,
      birthDate: peek.date_of_birth ? new Date(peek.date_of_birth).toISOString().slice(0, 10) : null,
    })
    if (problem) {
      await client.query('rollback') // le jeton reste utilisable : le salarié corrige et réessaie
      return json(response, 422, { message: problem })
    }
    const hash = await bcrypt.hash(input.password, 12)
    let userId = peek.user_id
    if (userId) {
      await client.query('update auth.users set encrypted_password = $2, updated_at = now() where id = $1', [userId, hash])
    } else {
      userId = randomUUID()
      await client.query(
        'insert into auth.users (id, email, encrypted_password, email_confirmed_at) values ($1, $2, $3, now())',
        [userId, phoneToEmail(peek.phone_e164), hash],
      )
    }
    await client.query('select public.phone_access_complete($1, $2)', [tokenHash, userId])
    await client.query('commit')
    return json(response, 200, { status: 'done' })
  } catch (error) {
    await client.query('rollback').catch(() => {})
    throw error
  } finally {
    client.release()
  }
}

async function auth(request, response, pathname) {
  // Corps lu une fois pour toutes : la connexion par téléphone n'obéit pas au verrou collectif par adresse
  // Routes non authentifiées : corps plafonné à 64 Ko, JSON invalide refusé (plus de « {} » silencieux)
  if (request.method === 'POST') {
    try { request.parsedBody = await body(request, 64 * 1024) } catch (error) {
      if (error?.code === 'BODY_TOO_LARGE') {
        response.setHeader('connection', 'close')
        response.once('finish', () => request.destroy()) // on coupe le flux seulement une fois le 413 envoyé
        return json(response, 413, { message: 'Requête trop volumineuse' })
      }
      return json(response, 400, { message: 'Corps de requête invalide' })
    }
    if (request.parsedBody === null || typeof request.parsedBody !== 'object') return json(response, 400, { message: 'Corps de requête invalide' })
  }
  const phoneLogin = pathname === '/auth/v1/token' && isPhoneEmail(request.parsedBody?.email)
  // Middleware : vérification rate limit et brute force
  // Limitation seulement sur les points qui reçoivent des identifiants : /auth/v1/user est appelé à chaque page
  const sensible = request.method === 'POST' && (pathname === '/auth/v1/token' || pathname === '/auth/v1/signup' || phoneRoutes.includes(pathname))
  if (sensible) {
    await rateLimitMiddleware(SECURITY.rateLimit.max, SECURITY.rateLimit.windowMs)(request, response, async () => {})
    if (response.writableEnded) return true // 429 déjà envoyé : on n'exécute pas la requête
  }

  if (request.method === 'POST' && phoneRoutes.includes(pathname)) return phoneAuth(request, response, pathname)

  if (request.method === 'POST' && pathname === '/auth/v1/signup') {
    // Inscription fermée par défaut : seule une invitation admin permet de créer un compte
    if (!SECURITY.signupEnabled) {
      return json(response, 403, { message: 'Inscription fermée : création de compte sur invitation admin uniquement' })
    }
    const input = await body(request)
    if (!input.email || !input.password || input.password.length < 8) {
      return json(response, 400, { error: 'email et mot de passe de 8 caractères minimum requis' })
    }
    const password = await bcrypt.hash(input.password, 12)
    const id = randomUUID()
    const result = await pool.query(
      `insert into auth.users (id, email, encrypted_password, email_confirmed_at)
       values ($1, lower($2), $3, now())
       returning id, email, created_at, updated_at`,
      [id, input.email, password],
    )
    const user = result.rows[0]
    // Créer le rôle par défaut selon l'environnement
    const defaultRole = process.env.DEFAULT_USER_ROLE ?? 'salarié'
    await pool.query(
      `INSERT INTO public.user_roles (user_id, role) VALUES ($1, $2)`,
      [id, defaultRole],
    )
    // Token d'accès court (8h) et refresh token révocable (24h)
    const accessToken = await issueToken(user)
    const refreshToken = await issueRefreshToken(user.id)
    return json(response, 200, {
      user, access_token: accessToken, refresh_token: refreshToken,
      token_type: 'bearer', expires_in: 28800,
    })
  }

  if (request.method === 'POST' && pathname === '/auth/v1/token') {
    const input = await body(request)
    if (typeof input.email !== 'string' || typeof input.password !== 'string') return json(response, 400, { error: 'invalid_credentials', error_description: 'Adresse ou mot de passe invalide' })
    // RPR-03 : verrouillage progressif par couple compte + adresse (un poste ne bloque jamais les autres comptes ni les autres postes)
    const lockKey = `${hashIp(clientIp(request), ipSalt())}|${String(input.email ?? '').toLowerCase()}`
    if (!phoneLogin) {
      const wait = await emailLoginLimiter.retryAfter(lockKey)
      if (wait) return json(response, 429, { message: `Trop d'échecs pour ce compte depuis ce poste, réessayez dans ${wait} secondes` })
    }
    const result = await pool.query('select id, email, encrypted_password, created_at, updated_at from auth.users where email = lower($1)', [input.email])
    const user = result.rows[0]
    if (phoneLogin) {
      // Compte téléphone : verrouillage progressif par couple numéro + adresse, compte actif obligatoire
      const key = `${clientIp(request)}|${String(input.email).toLowerCase()}`
      const wait = await phoneLoginLimiter.retryAfter(key)
      if (wait) return json(response, 429, { message: `Trop d'échecs, réessayez dans ${wait} secondes` })
      // bcrypt est toujours exécuté (hachage factice si le numéro n'a pas de compte) : le délai ne révèle pas les comptes existants
      const passwordOk = await bcrypt.compare(input.password, user?.encrypted_password ?? DUMMY_HASH)
      const valid = user && passwordOk
        && (await phoneDb('phone_access_account_status($1)', [user.id])) === 'active'
      const phone = emailToPhone(input.email)
      if (!valid) {
        const locked = await phoneLoginLimiter.fail(key)
        await logPhoneLogin(phone, locked ? 'verrouillage de connexion' : 'connexion échouée')
        return json(response, 400, { error: 'invalid_credentials', error_description: 'Numéro ou mot de passe invalide' })
      }
      await phoneLoginLimiter.success(key)
      await logPhoneLogin(phone, 'connexion réussie')
      const refresh = await rotateRefreshToken(user.id, input.email)
      return json(response, 200, {
        user: { id: user.id, email: user.email, created_at: user.created_at, updated_at: user.updated_at },
        access_token: await issueToken(user), refresh_token: refresh, token_type: 'bearer', expires_in: 28800,
      })
    }
    const emailPasswordOk = await bcrypt.compare(input.password, user?.encrypted_password ?? DUMMY_HASH)
    if (!user || !emailPasswordOk) {
      if (await emailLoginLimiter.fail(lockKey)) await logLoginLock(input.email, lockKey.split('|')[0])
      return json(response, 400, { error: 'invalid_credentials', error_description: 'Adresse ou mot de passe invalide' })
    }
    await emailLoginLimiter.success(lockKey)
    // Rotate refresh token : ancien invalide, nouveau créé
    const newRefreshToken = await rotateRefreshToken(user.id, input.email)
    return json(response, 200, {
      user: { id: user.id, email: user.email, created_at: user.created_at, updated_at: user.updated_at },
      access_token: await issueToken(user),
      refresh_token: newRefreshToken,
      token_type: 'bearer', expires_in: 28800,
    })
  }

  if (request.method === 'GET' && pathname === '/auth/v1/user') {
    const token = request.headers.authorization?.replace(/^Bearer\s+/i, '')
    if (!token) return json(response, 401, { message: 'Missing authorization' })
    const { payload: claims } = await jwtVerify(token, secret, { audience: 'authenticated', algorithms: ['HS256'] })
    const result = await pool.query('select id, email, created_at, updated_at from auth.users where id = $1', [claims.sub])
    return result.rows[0] ? json(response, 200, result.rows[0]) : json(response, 401, { message: 'User not found' })
  }

  if (request.method === 'POST' && pathname === '/auth/v1/logout') {
    // Révocation du refresh token en base
    const token = request.headers.authorization?.replace(/^Bearer\s+/i, '')
    if (token) {
      await revokeRefreshToken(token)
    }
    return json(response, 204, {})
  }

  return false
}

const server = http.createServer(async (request, response) => {
  try {
    setCors(request, response)
    if (request.method === 'OPTIONS') {
      response.writeHead(204)
      response.end()
      return
    }
    const url = new URL(request.url, `http://${request.headers.host}`)
    if (url.pathname.startsWith('/auth/v1/')) {
      const handled = await auth(request, response, url.pathname)
      if (handled !== false) return
    }
    if (url.pathname.startsWith('/api/v1/documents/') || url.pathname.startsWith('/api/v1/employees/')) {
      if (await documentRoute(request, response, url)) return
    }

    const postgrestPath = url.pathname.startsWith('/rest/v1/')
      ? url.pathname.slice('/rest/v1'.length)
      : url.pathname
    const target = new URL(postgrestPath + url.search, postgrestUrl)
    const headers = {}
    for (const name of ['authorization', 'accept', 'accept-profile', 'content-profile', 'content-type', 'prefer', 'range', 'apikey']) {
      if (request.headers[name]) headers[name] = request.headers[name]
    }
    const hasBody = !['GET', 'HEAD'].includes(request.method)
    const upstream = await fetch(target, {
      method: request.method,
      headers,
      body: hasBody ? request : undefined,
      duplex: hasBody ? 'half' : undefined,
    })
    const responseHeaders = Object.fromEntries(upstream.headers)
    delete responseHeaders['access-control-allow-origin']
    delete responseHeaders['access-control-allow-credentials']
    response.writeHead(upstream.status, responseHeaders)
    response.end(Buffer.from(await upstream.arrayBuffer()))
  } catch (error) {
    // Jeton expiré, falsifié ou mal formé (jose) : 401 et non 500 (D-015)
    if (/^ERR_(JWT|JWS|JOSE)/.test(String(error?.code))) return json(response, 401, { message: 'Session invalide ou expirée' })
    console.error(error)
    json(response, 500, { message: 'Erreur interne de la passerelle' })
  }
})

server.listen(port, '0.0.0.0', () => console.log(`SOMA-RH gateway listening on ${port}`))
