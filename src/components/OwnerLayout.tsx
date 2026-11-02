import { useState } from 'react'
import { Link, NavLink, Outlet } from 'react-router-dom'
import {
  LayoutDashboard,
  PlusCircle,
  QrCode,
  CalendarCheck2,
  Building2,
  Trophy,
  Sparkles,
  Phone,
  Check,
} from 'lucide-react'
import { useAuth } from '@/lib/auth'
import { useRegisterOwner } from '@/lib/ownerApi'
import { useRoleGate } from './RoleGateway'
import { useToast } from './Toast'
import { errorMessage } from '@/lib/errors'

const OWNER_TABS = [
  { to: '/owner', label: 'Dashboard', icon: LayoutDashboard, end: true },
  { to: '/owner/turfs/new', label: 'List Turf', icon: PlusCircle, end: false },
  { to: '/owner/scan', label: 'Scan QR', icon: QrCode, end: false },
  { to: '/owner/bookings', label: 'Bookings', icon: CalendarCheck2, end: false },
]

export function OwnerLayout() {
  const { user, profile, loading } = useAuth()
  const { chooseRole } = useRoleGate()
  const { toast } = useToast()
  const registerOwner = useRegisterOwner()

  const [fullName, setFullName] = useState(profile?.full_name || '')
  const [businessName, setBusinessName] = useState(profile?.business_name || '')
  const [businessPhone, setBusinessPhone] = useState(profile?.business_phone || user?.phone || '')
  const [showProfileForm, setShowProfileForm] = useState(false)

  const handleSaveOwnerProfile = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!businessName.trim()) {
      toast('Please enter your business or turf brand name', 'error')
      return
    }
    try {
      await registerOwner.mutateAsync({
        fullName: fullName.trim() || businessName.trim(),
        businessName: businessName.trim(),
        businessPhone: businessPhone.trim() || null,
      })
      toast('Owner profile saved!', 'success')
      setShowProfileForm(false)
    } catch (err) {
      toast(errorMessage(err), 'error')
    }
  }

  return (
    <div className="min-h-dvh flex flex-col bg-ink text-text">
      {/* Top Partner Header */}
      <header className="sticky top-0 z-30 bg-ink/90 backdrop-blur-md border-b border-line px-4 py-3 safe-top">
        <div className="max-w-3xl mx-auto flex items-center justify-between gap-3">
          <Link to="/owner" className="flex items-center gap-2.5 min-w-0">
            <div className="w-9 h-9 rounded-xl bg-neon text-ink flex items-center justify-center shrink-0 shadow-glow">
              <Building2 className="w-5 h-5" />
            </div>
            <div className="min-w-0">
              <div className="flex items-center gap-1.5">
                <span className="text-sm font-extrabold tracking-tight text-text">Turffet</span>
                <span className="rounded-md bg-neon/15 border border-neon/35 px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wider text-neon">
                  Owner Portal
                </span>
              </div>
              <div className="text-[11px] text-muted truncate">
                {profile?.business_name || profile?.full_name || 'List & manage your sports venues'}
              </div>
            </div>
          </Link>

          <div className="flex items-center gap-2 shrink-0">
            {user && (
              <button
                type="button"
                onClick={() => {
                  setFullName(profile?.full_name || '')
                  setBusinessName(profile?.business_name || '')
                  setBusinessPhone(profile?.business_phone || user.phone || '')
                  setShowProfileForm((v) => !v)
                }}
                className="btn-secondary h-9 px-3 text-xs rounded-xl hidden sm:inline-flex"
              >
                <span>{profile?.business_name ? 'Edit Brand' : 'Set Brand Name'}</span>
              </button>
            )}
            <button
              type="button"
              onClick={() => chooseRole('player', '/')}
              className="h-9 px-3 rounded-xl bg-surface-2 border border-line hover:border-neon/50 text-text text-xs font-semibold inline-flex items-center gap-1.5 transition"
              title="Switch to Player Booking App"
            >
              <Trophy className="w-3.5 h-3.5 text-neon" />
              <span>Player App</span>
            </button>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="flex-1 w-full max-w-3xl mx-auto pb-28">
        {loading ? (
          <div className="p-4 space-y-4">
            <div className="card h-36 animate-pulse bg-surface-2" />
            <div className="card h-56 animate-pulse bg-surface-2" />
          </div>
        ) : !user ? (
          <div className="p-4 pt-6 space-y-5">
            <div className="card p-6 space-y-4 border-neon/35 bg-linear-to-b from-surface to-ink">
              <div className="inline-flex items-center gap-1.5 rounded-full bg-neon/15 border border-neon/30 px-3 py-1 text-xs font-bold text-neon">
                <Sparkles className="w-3.5 h-3.5" />
                <span>Turffet Partner Portal</span>
              </div>
              <h1 className="text-xl sm:text-2xl font-extrabold text-text">
                List your turf & fill every empty slot
              </h1>
              <p className="text-xs sm:text-sm text-muted leading-relaxed">
                Sign in with your phone number to list your turf with photos, operating hours, courts, sports & player
                limits per sport, Happy Hour off-peak deals, and instant QR check-in scanning.
              </p>

              <div className="grid grid-cols-1 sm:grid-cols-3 gap-2.5 pt-1 text-xs">
                <div className="rounded-xl bg-surface-2 border border-line p-3 space-y-1">
                  <div className="font-bold text-neon">1. List Courts & Sports</div>
                  <div className="text-muted">Set photos, timings, amenities & max players for each sport</div>
                </div>
                <div className="rounded-xl bg-surface-2 border border-line p-3 space-y-1">
                  <div className="font-bold text-neon">2. Happy Hour Deals</div>
                  <div className="text-muted">Create % discounts or off-peak deals to fill daytime hours</div>
                </div>
                <div className="rounded-xl bg-surface-2 border border-line p-3 space-y-1">
                  <div className="font-bold text-neon">3. Scan QR at Venue</div>
                  <div className="text-muted">Verify player QR passes & group sizes on arrival</div>
                </div>
              </div>

              <div className="pt-2 flex flex-col sm:flex-row gap-2.5">
                <Link
                  to="/auth?next=%2Fowner"
                  className="btn-primary h-11 px-5 text-sm shadow-glow flex-1"
                >
                  <Phone className="w-4 h-4" />
                  <span>Sign in as Turf Owner (Phone OTP)</span>
                </Link>
                <button
                  type="button"
                  onClick={() => chooseRole('player', '/')}
                  className="btn-secondary h-11 px-4 text-xs"
                >
                  Browse as Player instead
                </button>
              </div>
            </div>
          </div>
        ) : (
          <>
            {/* Optional quick business profile banner if owner hasn't named their business yet */}
            {(showProfileForm || (!profile?.is_owner && !profile?.business_name)) && (
              <div className="px-4 pt-4">
                <form
                  onSubmit={handleSaveOwnerProfile}
                  className="rounded-2xl border border-neon/35 bg-surface p-4 space-y-3"
                >
                  <div className="flex items-center justify-between gap-2">
                    <div>
                      <div className="text-xs font-bold uppercase tracking-wider text-neon">
                        Owner / Business Details
                      </div>
                      <div className="text-xs text-muted">
                        Displayed on your turf listings and booking confirmations
                      </div>
                    </div>
                    {showProfileForm && (
                      <button
                        type="button"
                        onClick={() => setShowProfileForm(false)}
                        className="text-xs text-muted hover:text-text"
                      >
                        Close
                      </button>
                    )}
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-3 gap-2.5">
                    <input
                      type="text"
                      value={fullName}
                      onChange={(e) => setFullName(e.target.value)}
                      placeholder="Your name (e.g. Rohan Verma)"
                      className="input h-10 text-xs"
                    />
                    <input
                      type="text"
                      value={businessName}
                      onChange={(e) => setBusinessName(e.target.value)}
                      placeholder="Turf / Business name (e.g. Apex Arenas)"
                      className="input h-10 text-xs"
                      required
                    />
                    <div className="flex gap-2">
                      <input
                        type="tel"
                        value={businessPhone}
                        onChange={(e) => setBusinessPhone(e.target.value)}
                        placeholder="Venue contact phone"
                        className="input h-10 text-xs flex-1"
                      />
                      <button
                        type="submit"
                        disabled={registerOwner.isPending}
                        className="btn-primary h-10 px-3.5 text-xs shrink-0"
                      >
                        <Check className="w-3.5 h-3.5" />
                        <span>{registerOwner.isPending ? 'Saving…' : 'Save'}</span>
                      </button>
                    </div>
                  </div>
                </form>
              </div>
            )}

            <Outlet />
          </>
        )}
      </main>

      {/* Bottom Tab Bar for Owner Portal */}
      <nav className="fixed bottom-0 inset-x-0 z-40 bg-surface/95 backdrop-blur-md border-t border-line safe-bottom">
        <div className="max-w-3xl mx-auto grid grid-cols-4 h-16">
          {OWNER_TABS.map(({ to, label, icon: Icon, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              className={({ isActive }) =>
                `flex flex-col items-center justify-center gap-1 text-[11px] font-medium transition ${
                  isActive ? 'text-neon' : 'text-muted hover:text-text'
                }`
              }
            >
              {({ isActive }) => (
                <>
                  <div
                    className={`px-3 py-1 rounded-full transition ${
                      isActive ? 'bg-neon/15 text-neon' : ''
                    }`}
                  >
                    <Icon className="w-4 h-4" />
                  </div>
                  <span>{label}</span>
                </>
              )}
            </NavLink>
          ))}
        </div>
      </nav>
    </div>
  )
}
