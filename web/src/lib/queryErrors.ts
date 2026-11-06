// Erreurs de lecture signalées par le QueryCache : affichées dans un bandeau (H43), même si la page ne lit pas `isError`.
let messages: string[] = []
const listeners = new Set<() => void>()
const emit = () => listeners.forEach((l) => l())

export const queryErrors = {
  add(error: unknown) {
    const m = error instanceof Error ? error.message : String(error)
    if (messages.includes(m)) return
    messages = [...messages, m].slice(-3)
    emit()
  },
  clear() { messages = []; emit() },
  subscribe(l: () => void) { listeners.add(l); return () => { listeners.delete(l) } },
  snapshot: () => messages,
}
