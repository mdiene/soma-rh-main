import { useState } from 'react'
import { Button, ErrorNote, TextField } from './ui'
import {
  PASSWORD_PATTERN, PASSWORD_RULE, definirMotDePasse, demanderAcces, ouvrirActivation, seConnecterParTelephone,
} from '../lib/phoneAuth'

type Step = 'signin' | 'request' | 'activate' | 'password'

const TITLES: Record<Step, string> = {
  signin: 'Connexion par téléphone',
  request: 'Créer mon accès ou changer mon mot de passe',
  activate: 'Activer mon accès',
  password: 'Choisir mon mot de passe',
}

/** Connexion des salariés par numéro de téléphone : numéro, [date de naissance], mot de passe (autorisation par l'administrateur). */
export function PhoneLogin() {
  const [step, setStep] = useState<Step>('signin')
  const [phone, setPhone] = useState('')
  const [birth, setBirth] = useState('')
  const [password, setPassword] = useState('')
  const [show, setShow] = useState(false)
  const [token, setToken] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<unknown>(null)
  const [info, setInfo] = useState<string | null>(null)

  async function run(action: () => Promise<void>) {
    setBusy(true); setError(null); setInfo(null)
    try { await action() } catch (err) { setError(err) } finally { setBusy(false) }
  }
  const go = (s: Step) => { setStep(s); setError(null); setInfo(null); setPassword('') }

  const submit = (e: React.FormEvent) => {
    e.preventDefault()
    run(async () => {
      if (step === 'signin') return seConnecterParTelephone(phone, password)
      if (step === 'request') {
        await demanderAcces(phone)
        setInfo("Votre demande a été enregistrée. L'administrateur doit l'autoriser. Revenez saisir votre numéro plus tard.")
        return
      }
      if (step === 'activate') {
        const r = await ouvrirActivation(phone, birth)
        if (r.status === 'ready') { setToken(r.token); go('password') } else setInfo(r.message ?? "Votre accès n'est pas encore autorisé. Revenez plus tard.")
        return
      }
      if (!PASSWORD_PATTERN.test(password)) throw new Error(`Mot de passe invalide : ${PASSWORD_RULE}`)
      await definirMotDePasse(token, password)
      await seConnecterParTelephone(phone, password)
    })
  }

  return (
    <form onSubmit={submit} className="space-y-4" aria-label={TITLES[step]}>
      <p className="text-sm text-ink-soft">
        {step === 'signin' && 'Utilisez le numéro de téléphone enregistré sur votre fiche.'}
        {step === 'request' && "Saisissez votre numéro : l'administrateur recevra votre demande et la validera après vous avoir contacté."}
        {step === 'activate' && 'Votre demande est autorisée ? Saisissez de nouveau votre numéro et votre date de naissance.'}
        {step === 'password' && `Choisissez votre mot de passe : ${PASSWORD_RULE}`}
      </p>

      {step !== 'password' && (
        <TextField label="Numéro de téléphone" type="tel" inputMode="tel" autoComplete="tel" placeholder="77 123 45 67" required
          value={phone} onChange={(e) => setPhone(e.target.value)} />
      )}
      {step === 'activate' && (
        <TextField label="Date de naissance" type="date" required value={birth} onChange={(e) => setBirth(e.target.value)}
          hint="Elle sert à vérifier que vous êtes bien le titulaire de la fiche." />
      )}
      {(step === 'signin' || step === 'password') && (
        <div>
          <TextField label={step === 'signin' ? 'Mot de passe' : 'Nouveau mot de passe'} type={show ? 'text' : 'password'}
            autoComplete={step === 'signin' ? 'current-password' : 'new-password'} required
            {...(step === 'password' ? { minLength: 5, maxLength: 8, pattern: '[A-Za-z0-9]{5,8}', title: PASSWORD_RULE } : {})}
            value={password} onChange={(e) => setPassword(e.target.value)} hint={step === 'password' ? PASSWORD_RULE : undefined} />
          <label className="mt-2 flex items-center gap-2 text-sm text-ink-soft">
            <input type="checkbox" checked={show} onChange={(e) => setShow(e.target.checked)} /> Afficher le mot de passe
          </label>
        </div>
      )}

      <div aria-live="polite">
        <ErrorNote error={error} />
        {info && <p className="rounded border border-river/30 bg-river-light px-3 py-2 text-sm text-river-dark">{info}</p>}
      </div>

      <Button type="submit" variant="primary" loading={busy} className="w-full">
        {step === 'signin' ? 'Se connecter' : step === 'request' ? 'Envoyer ma demande' : step === 'activate' ? 'Continuer' : 'Enregistrer et me connecter'}
      </Button>

      <div className="flex flex-col gap-1 text-sm">
        {step === 'signin' && (<>
          <button type="button" className="text-left text-river hover:underline" onClick={() => go('request')}>Créer mon accès</button>
          <button type="button" className="text-left text-river hover:underline" onClick={() => go('request')}>Mot de passe oublié</button>
        </>)}
        {step === 'request' && <button type="button" className="text-left text-river hover:underline" onClick={() => go('activate')}>Ma demande est autorisée : continuer</button>}
        {step !== 'signin' && <button type="button" className="text-left text-river hover:underline" onClick={() => go('signin')}>Retour à la connexion</button>}
      </div>
    </form>
  )
}
