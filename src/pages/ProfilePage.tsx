import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { Bell, LogOut, ShieldCheck, UserCheck, Sparkles, Edit3, Building2, ArrowRight } from 'lucide-react'
import { useAuth } from '@/lib/auth'
import { useRoleGate } from '@/components/RoleGateway'
import { useAppSettings, useSports } from '@/lib/api'
import {
  disablePushNotifications,
  enablePushNotifications,
  getCurrentPushSubscription,
  isPushSupported,
} from '@/lib/push'
import { initials, SKILL_LABEL } from '@/lib/format'
import { useToast } from '@/components/Toast'
import { errorMessage } from '@/lib/errors'

export function ProfilePage() {
  const { user, profile, signOut } = useAuth()
  const { chooseRole } = useRoleGate()
  const { data: sports = [] } = useSports()
  const { data: settings } = useAppSettings()
  const { toast } = useToast()

  const [pushEnabled, setPushEnabled] = useState(false)
  const [pushBusy, setPushBusy] = useState(false)

  useEffect(() => {
    getCurrentPushSubscription().then((sub) => setPushEnabled(Boolean(sub)))
  }, [])

  const handleTogglePush = async () => {
    if (!user) {
      toast('Sign in first to enable push reminders', 'info')
      return
    }
    setPushBusy(true)
    try {
      if (pushEnabled) {
        await disablePushNotifications()
        setPushEnabled(false)
        toast('Push reminders turned off', 'info')
      } else {
        await enablePushNotifications(user.id)
        setPushEnabled(true)
        toast('Web push reminders enabled!', 'success')
      }
    } catch (err) {
      toast(errorMessage(err), 'error')
    } finally {
      setPushBusy(false)
    }
  }

  if (!user) {
    return (
      <div className="p-4 pt-8 space-y-4 safe-top">
        <div className="card p-6 text-center space-y-3">
          <div className="w-14 h-14 rounded-full bg-neon/15 text-neon flex items-center justify-center mx-auto">
            <UserCheck className="w-6 h-6" />
          </div>
          <h1 className="text-lg font-bold">Sign in to Turffet</h1>
          <p className="text-xs text-muted max-w-xs mx-auto">
            Sync your bookings across devices, join open games, and receive 2-hour match reminders.
          </p>
          <Link to="/auth" className="btn-primary w-full max-w-xs mx-auto">
            Sign in with Phone / OTP
          </Link>
        </div>

        <button
          type="button"
          onClick={() => chooseRole('owner', '/owner')}
          className="card w-full p-4 border-neon/40 bg-neon/5 hover:bg-neon/10 transition flex items-center justify-between gap-3 text-left"
        >
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-neon text-ink flex items-center justify-center shrink-0">
              <Building2 className="w-5 h-5" />
            </div>
            <div>
              <div className="text-sm font-bold text-neon">Own a sports turf?</div>
              <div className="text-xs text-muted">
                Open the Turf Owner Portal to list your venue, set Happy Hour deals & scan QR passes
              </div>
            </div>
          </div>
          <ArrowRight className="w-4 h-4 text-neon shrink-0" />
        </button>
      </div>
    )
  }

  return (
    <div className="p-4 space-y-4 safe-top">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-bold">Profile</h1>
        <Link to="/onboarding" className="btn-secondary h-9 px-3 text-xs">
          <Edit3 className="w-3.5 h-3.5 text-neon" />
          <span>Edit</span>
        </Link>
      </div>

      {/* Player card */}
      <div className="card p-5 space-y-4">
        <div className="flex items-center gap-3.5">
          <div className="w-14 h-14 rounded-2xl bg-neon text-ink font-display text-xl font-bold flex items-center justify-center shrink-0">
            {initials(profile?.full_name || user.phone || user.email)}
          </div>
          <div className="min-w-0">
            <h2 className="text-lg font-bold text-text truncate">
              {profile?.full_name || 'Turffet Player'}
            </h2>
            <p className="text-xs text-muted truncate">{user.phone || user.email}</p>
            {profile?.skill_level && (
              <span className="inline-flex items-center gap-1 rounded-md bg-neon/15 text-neon px-2 py-0.5 text-[11px] font-semibold mt-1">
                <Sparkles className="w-3 h-3" />
                {SKILL_LABEL[profile.skill_level]}
              </span>
            )}
          </div>
        </div>

        {profile?.preferred_sports?.length ? (
          <div className="pt-3 border-t border-line space-y-1.5">
            <div className="label">Preferred sports</div>
            <div className="flex flex-wrap gap-1.5">
              {profile.preferred_sports.map((sid) => {
                const sp = sports.find((s) => s.id === sid)
                return (
                  <span
                    key={sid}
                    className="inline-flex items-center gap-1 rounded-full bg-surface-2 border border-line px-3 py-1 text-xs"
                  >
                    <span>{sp?.emoji ?? '🏟️'}</span>
                    <span>{sp?.name ?? sid}</span>
                  </span>
                )
              })}
            </div>
          </div>
        ) : null}
      </div>

      {/* Turf Owner Portal CTA */}
      <button
        type="button"
        onClick={() => chooseRole('owner', '/owner')}
        className="card w-full p-4 border-neon/40 bg-neon/5 hover:bg-neon/10 transition flex items-center justify-between gap-3 text-left"
      >
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-neon text-ink flex items-center justify-center shrink-0">
            <Building2 className="w-5 h-5" />
          </div>
          <div>
            <div className="text-sm font-bold text-neon">
              {profile?.is_owner ? 'Open Turf Owner Portal' : 'Own a turf? List your venue on Turffet'}
            </div>
            <div className="text-xs text-muted">
              Manage photos, courts, sports & player limits, Happy Hour deals, bookings & QR check-ins
            </div>
          </div>
        </div>
        <ArrowRight className="w-4 h-4 text-neon shrink-0" />
      </button>

      {/* Web Push reminders */}
      <div className="card p-4 flex items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-neon/15 text-neon flex items-center justify-center shrink-0">
            <Bell className="w-5 h-5" />
          </div>
          <div>
            <div className="text-sm font-semibold text-text">Web Push Match Reminders</div>
            <div className="text-xs text-muted">
              {isPushSupported()
                ? 'Get notified 2 hours before kick-off and when players request to join'
                : 'Install Turffet to your home screen to receive push notifications'}
            </div>
          </div>
        </div>
        {isPushSupported() && (
          <button
            type="button"
            disabled={pushBusy}
            onClick={handleTogglePush}
            className={pushEnabled ? 'btn-secondary h-9 px-3 text-xs' : 'btn-primary h-9 px-3 text-xs'}
          >
            {pushEnabled ? 'Enabled ✓' : 'Enable'}
          </button>
        )}
      </div>

      {/* Fair-play / No-show strikes status */}
      <div className="card p-4 space-y-2">
        <div className="flex items-center justify-between">
          <span className="text-sm font-semibold text-text flex items-center gap-2">
            <ShieldCheck className="w-4 h-4 text-neon" />
            Fair-Play & Attendance
          </span>
          <span className="text-xs font-bold text-neon">
            {profile?.strikes ?? 0} / {settings?.strike_limit ?? 3} strikes
          </span>
        </div>
        <p className="text-xs text-muted leading-relaxed">
          Free cancellation is available up to{' '}
          <strong className="text-text">
            {Math.round((settings?.cancellation_window_minutes ?? 120) / 60)} hours
          </strong>{' '}
          before your slot. No-show strike enforcement activates once venue QR check-in scanning is live in the owner portal.
        </p>
      </div>

      <button
        type="button"
        onClick={signOut}
        className="btn-danger w-full h-11 text-sm"
      >
        <LogOut className="w-4 h-4" />
        <span>Sign out</span>
      </button>
    </div>
  )
}
