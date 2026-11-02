import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from 'react'
import { CheckCircle2, AlertCircle, Info } from 'lucide-react'

type ToastTone = 'success' | 'error' | 'info'

interface ToastItem {
  id: number
  message: string
  tone: ToastTone
}

interface ToastCtx {
  toast: (message: string, tone?: ToastTone) => void
}

const Ctx = createContext<ToastCtx | null>(null)

export function ToastProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<ToastItem[]>([])

  const toast = useCallback((message: string, tone: ToastTone = 'info') => {
    const id = Date.now() + Math.random()
    setItems((prev) => [...prev, { id, message, tone }])
    setTimeout(() => {
      setItems((prev) => prev.filter((t) => t.id !== id))
    }, 3400)
  }, [])

  const value = useMemo(() => ({ toast }), [toast])

  return (
    <Ctx.Provider value={value}>
      {children}
      <div className="fixed top-3 inset-x-0 z-50 flex flex-col items-center gap-2 px-4 pointer-events-none safe-top">
        {items.map((item) => (
          <div
            key={item.id}
            className="pointer-events-auto flex items-center gap-2.5 max-w-md w-full rounded-xl bg-surface-2/95 backdrop-blur border border-line px-4 py-3 text-sm shadow-xl animate-fade-up"
          >
            {item.tone === 'success' && <CheckCircle2 className="w-4 h-4 text-neon shrink-0" />}
            {item.tone === 'error' && <AlertCircle className="w-4 h-4 text-danger shrink-0" />}
            {item.tone === 'info' && <Info className="w-4 h-4 text-info shrink-0" />}
            <span className="text-text font-medium">{item.message}</span>
          </div>
        ))}
      </div>
    </Ctx.Provider>
  )
}

export function useToast() {
  const ctx = useContext(Ctx)
  if (!ctx) throw new Error('useToast must be used inside ToastProvider')
  return ctx
}
