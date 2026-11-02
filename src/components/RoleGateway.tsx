import { createContext, useContext, useState, type ReactNode } from 'react'
import { useLocation, useNavigate } from 'react-router-dom'
import { Building2, Users, Sparkles, QrCode, CalendarClock, Trophy, ArrowRight } from 'lucide-react'

export type AppRole = 'player' | 'owner'

const ROLE_STORAGE_KEY = 'turffet.role.session.v1'

interface RoleGateContextValue {
  role: AppRole | null
  chooseRole: (role: AppRole, targetPath?: string) => void
  openRoleChooser: () => void
}

const RoleGateContext = createContext<RoleGateContextValue | null>(null)

export function RoleGateProvider({ children }: { children: ReactNode }) {
  const navigate = useNavigate()
  const location = useLocation()

  const [role, setRole] = useState<AppRole | null>(() => {
    try {
      const saved = sessionStorage.getItem(ROLE_STORAGE_KEY)
      if (saved === 'player' || saved === 'owner') return saved
    } catch {
      /* ignore */
    }
    if (typeof window !== 'undefined' && window.location.pathname.startsWith('/owner')) {
      return 'owner'
    }
    return null
  })

  const [chooserOpen, setChooserOpen] = useState<boolean>(() => {
    if (typeof window !== 'undefined' && window.location.pathname.startsWith('/owner')) {
      return false
    }
    try {
      const saved = sessionStorage.getItem(ROLE_STORAGE_KEY)
      return !(saved === 'player' || saved === 'owner')
    } catch {
      return true
    }
  })

  const chooseRole = (nextRole: AppRole, targetPath?: string) => {
    setRole(nextRole)
    setChooserOpen(false)
    try {
      sessionStorage.setItem(ROLE_STORAGE_KEY, nextRole)
    } catch {
      /* ignore */
    }
    if (targetPath) {
      navigate(targetPath)
      return
    }
    if (nextRole === 'owner') {
      if (!location.pathname.startsWith('/owner')) {
        navigate('/owner')
      }
    } else {
      if (location.pathname.startsWith('/owner')) {
        navigate('/')
      }
    }
  }

  const openRoleChooser = () => setChooserOpen(true)

  return (
    <RoleGateContext.Provider value={{ role, chooseRole, openRoleChooser }}>
      {children}
      {chooserOpen && (
        <div className="fixed inset-0 z-50 bg-ink/95 backdrop-blur-xl overflow-y-auto flex items-center justify-center p-4">
          <div className="w-full max-w-xl my-auto space-y-6 py-6 animate-fade-up">
            {/* Brand Header */}
            <div className="text-center space-y-2">
              <div className="inline-flex items-center gap-2 rounded-full bg-neon/15 border border-neon/30 px-3.5 py-1 text-xs font-bold text-neon">
                <Sparkles className="w-3.5 h-3.5" />
                <span>TURFFET · DELHI NCR</span>
              </div>
              <h1 className="text-2xl sm:text-3xl font-extrabold text-text tracking-tight">
                Welcome to <span className="text-neon">Turffet</span>
              </h1>
              <p className="text-xs sm:text-sm text-muted max-w-md mx-auto">
                Are you here to book a turf & play, or are you a turf owner looking to list and manage your venue?
              </p>
            </div>

            {/* Two Role Cards */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              {/* Option 1: Player */}
              <button
                type="button"
                onClick={() => chooseRole('player', '/')}
                className="group relative rounded-3xl border border-line bg-surface hover:border-neon hover:bg-surface-2 p-5 text-left transition-all flex flex-col justify-between gap-5 shadow-lg hover:shadow-glow"
              >
                <div className="space-y-3">
                  <div className="flex items-center justify-between">
                    <div className="w-12 h-12 rounded-2xl bg-neon/15 border border-neon/30 text-neon flex items-center justify-center">
                      <Trophy className="w-6 h-6" />
                    </div>
                    <span className="rounded-full bg-surface-2 border border-line px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wider text-muted group-hover:border-neon/40 group-hover:text-neon">
                      Book & Play
                    </span>
                  </div>

                  <div>
                    <h2 className="text-lg font-extrabold text-text group-hover:text-neon transition">
                      I’m a Player
                    </h2>
                    <p className="text-xs text-muted mt-1 leading-relaxed">
                      Discover nearby turfs, book live slots, unlock Happy Hour deals, and find teammates.
                    </p>
                  </div>

                  <ul className="space-y-1.5 text-xs text-text/90 pt-1">
                    <li className="flex items-center gap-2">
                      <CalendarClock className="w-3.5 h-3.5 text-neon shrink-0" />
                      <span>Live slot availability & Happy Hour deals</span>
                    </li>
                    <li className="flex items-center gap-2">
                      <Users className="w-3.5 h-3.5 text-neon shrink-0" />
                      <span>Bring your squad or “Find Players” to join</span>
                    </li>
                    <li className="flex items-center gap-2">
                      <QrCode className="w-3.5 h-3.5 text-neon shrink-0" />
                      <span>Instant QR booking pass for venue check-in</span>
                    </li>
                  </ul>
                </div>

                <div className="w-full rounded-xl bg-neon text-ink font-bold text-xs h-10 px-4 flex items-center justify-between group-hover:brightness-105 transition">
                  <span>Enter Player App</span>
                  <ArrowRight className="w-4 h-4" />
                </div>
              </button>

              {/* Option 2: Turf Owner */}
              <button
                type="button"
                onClick={() => chooseRole('owner', '/owner')}
                className="group relative rounded-3xl border border-line bg-surface hover:border-neon hover:bg-surface-2 p-5 text-left transition-all flex flex-col justify-between gap-5 shadow-lg hover:shadow-glow"
              >
                <div className="space-y-3">
                  <div className="flex items-center justify-between">
                    <div className="w-12 h-12 rounded-2xl bg-neon/15 border border-neon/30 text-neon flex items-center justify-center">
                      <Building2 className="w-6 h-6" />
                    </div>
                    <span className="rounded-full bg-neon/15 border border-neon/30 px-2.5 py-0.5 text-[10px] font-bold uppercase tracking-wider text-neon">
                      Partner Portal
                    </span>
                  </div>

                  <div>
                    <h2 className="text-lg font-extrabold text-text group-hover:text-neon transition">
                      I’m a Turf Owner
                    </h2>
                    <p className="text-xs text-muted mt-1 leading-relaxed">
                      List your turf on Turffet, fill empty off-peak hours, and manage bookings & QR check-ins.
                    </p>
                  </div>

                  <ul className="space-y-1.5 text-xs text-text/90 pt-1">
                    <li className="flex items-center gap-2">
                      <Building2 className="w-3.5 h-3.5 text-neon shrink-0" />
                      <span>Add photos, timings, amenities & courts</span>
                    </li>
                    <li className="flex items-center gap-2">
                      <Users className="w-3.5 h-3.5 text-neon shrink-0" />
                      <span>Set sports & max players per sport</span>
                    </li>
                    <li className="flex items-center gap-2">
                      <QrCode className="w-3.5 h-3.5 text-neon shrink-0" />
                      <span>Happy Hour deals & QR scanner check-in</span>
                    </li>
                  </ul>
                </div>

                <div className="w-full rounded-xl bg-surface-3 border border-neon/50 text-neon group-hover:bg-neon group-hover:text-ink font-bold text-xs h-10 px-4 flex items-center justify-between transition">
                  <span>List & Manage Your Turf</span>
                  <ArrowRight className="w-4 h-4" />
                </div>
              </button>
            </div>

            <p className="text-center text-[11px] text-muted">
              You can switch between <strong className="text-text">Player</strong> and{' '}
              <strong className="text-text">Turf Owner</strong> anytime from the top bar.
            </p>
          </div>
        </div>
      )}
    </RoleGateContext.Provider>
  )
}

export function useRoleGate() {
  const ctx = useContext(RoleGateContext)
  if (!ctx) {
    throw new Error('useRoleGate must be used within RoleGateProvider')
  }
  return ctx
}
