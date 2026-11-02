import { useMemo } from 'react'
import { Link } from 'react-router-dom'
import {
  PlusCircle,
  QrCode,
  CalendarCheck2,
  Edit3,
  ExternalLink,
  Eye,
  EyeOff,
  Trash2,
  MapPin,
  Star,
  Zap,
  Users,
  IndianRupee,
  TrendingUp,
  CheckCircle2,
  Phone,
  Clock,
} from 'lucide-react'
import {
  useOwnerCheckIn,
  useOwnerDashboard,
  useOwnerDeleteTurf,
  useOwnerSetTurfActive,
} from '@/lib/ownerApi'
import { useSports } from '@/lib/api'
import { formatDay, formatINR, formatRange } from '@/lib/format'
import { useToast } from '@/components/Toast'
import { errorMessage } from '@/lib/errors'
import type { Sport } from '@/lib/types'

export function OwnerDashboardPage() {
  const { data: dashboard, isLoading } = useOwnerDashboard()
  const { data: sports = [] } = useSports()
  const setTurfActive = useOwnerSetTurfActive()
  const deleteTurf = useOwnerDeleteTurf()
  const checkIn = useOwnerCheckIn()
  const { toast } = useToast()

  const sportsMap = useMemo(() => {
    const m = new Map<string, Sport>()
    for (const s of sports) m.set(s.id, s)
    return m
  }, [sports])

  const handleToggleActive = async (turfId: string, currentActive: boolean) => {
    try {
      await setTurfActive.mutateAsync({ turfId, active: !currentActive })
      toast(!currentActive ? 'Turf is now LIVE on the player app!' : 'Turf hidden from players', 'success')
    } catch (err) {
      toast(errorMessage(err), 'error')
    }
  }

  const handleDeleteTurf = async (turfId: string, name: string) => {
    if (!window.confirm(`Delete "${name}" permanently? This will remove all courts and slots for this turf.`)) {
      return
    }
    try {
      await deleteTurf.mutateAsync(turfId)
      toast(`Deleted ${name}`, 'info')
    } catch (err) {
      toast(errorMessage(err), 'error')
    }
  }

  const handleQuickCheckIn = async (bookingId: string) => {
    try {
      await checkIn.mutateAsync({ bookingId })
      toast('Player checked in!', 'success')
    } catch (err) {
      toast(errorMessage(err), 'error')
    }
  }

  if (isLoading) {
    return (
      <div className="p-4 space-y-4">
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          {[1, 2, 3, 4].map((i) => (
            <div key={i} className="card h-24 animate-pulse bg-surface-2" />
          ))}
        </div>
        <div className="card h-56 animate-pulse bg-surface-2" />
      </div>
    )
  }

  const turfs = dashboard?.turfs ?? []
  const upcoming = dashboard?.upcoming_bookings ?? []

  return (
    <div className="p-4 space-y-6">
      {/* Quick Action Bar */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-extrabold text-text">Owner Dashboard</h1>
          <p className="text-xs text-muted">
            Manage your turfs, timings, sports, Happy Hour deals & player check-ins
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Link to="/owner/scan" className="btn-secondary h-10 px-3.5 text-xs">
            <QrCode className="w-4 h-4 text-neon" />
            <span>Scan QR</span>
          </Link>
          <Link to="/owner/turfs/new" className="btn-primary h-10 px-4 text-xs shadow-glow">
            <PlusCircle className="w-4 h-4" />
            <span>List New Turf</span>
          </Link>
        </div>
      </div>

      {/* KPI Metrics Grid */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div className="card p-3.5 space-y-1">
          <div className="flex items-center justify-between text-xs text-muted">
            <span>Today’s Bookings</span>
            <CalendarCheck2 className="w-4 h-4 text-neon" />
          </div>
          <div className="text-2xl font-extrabold text-text">{dashboard?.today_bookings ?? 0}</div>
          <div className="text-[11px] text-neon font-medium">
            {dashboard?.today_checked_in ?? 0} checked in
          </div>
        </div>

        <div className="card p-3.5 space-y-1">
          <div className="flex items-center justify-between text-xs text-muted">
            <span>Today’s Revenue</span>
            <IndianRupee className="w-4 h-4 text-neon" />
          </div>
          <div className="text-2xl font-extrabold text-neon">
            {formatINR(dashboard?.today_revenue ?? 0)}
          </div>
          <div className="text-[11px] text-muted">
            7-day: {formatINR(dashboard?.week_revenue ?? 0)}
          </div>
        </div>

        <div className="card p-3.5 space-y-1">
          <div className="flex items-center justify-between text-xs text-muted">
            <span>Slot Occupancy</span>
            <TrendingUp className="w-4 h-4 text-neon" />
          </div>
          <div className="text-2xl font-extrabold text-text">
            {dashboard?.today_occupancy_pct ?? 0}%
          </div>
          <div className="text-[11px] text-muted">Across open hours today</div>
        </div>

        <div className="card p-3.5 space-y-1">
          <div className="flex items-center justify-between text-xs text-muted">
            <span>Your Turfs</span>
            <Zap className="w-4 h-4 text-neon" />
          </div>
          <div className="text-2xl font-extrabold text-text">{turfs.length}</div>
          <div className="text-[11px] text-muted">
            {turfs.filter((t) => t.is_active).length} live on player app
          </div>
        </div>
      </div>

      {/* My Turfs Section */}
      <section className="space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-bold uppercase tracking-wider text-muted">
            Your Listed Turfs ({turfs.length})
          </h2>
          <Link to="/owner/turfs/new" className="text-xs font-bold text-neon hover:underline">
            + Add another turf
          </Link>
        </div>

        {turfs.length === 0 ? (
          <div className="card p-6 sm:p-8 text-center space-y-4 border-dashed border-neon/40 bg-neon/5">
            <div className="w-14 h-14 rounded-2xl bg-neon/15 border border-neon/30 text-neon flex items-center justify-center mx-auto">
              <PlusCircle className="w-7 h-7" />
            </div>
            <div className="space-y-1 max-w-md mx-auto">
              <h3 className="text-lg font-extrabold text-text">List your first turf on Turffet</h3>
              <p className="text-xs text-muted leading-relaxed">
                Add your turf photos, opening & closing timings, amenities, courts, sports & max players per sport, and
                Happy Hour deals. As soon as you publish, players in Delhi NCR can discover and book your turf!
              </p>
            </div>
            <Link to="/owner/turfs/new" className="btn-primary h-11 px-6 text-sm shadow-glow inline-flex">
              <PlusCircle className="w-4 h-4" />
              <span>List Your Turf Now</span>
            </Link>
          </div>
        ) : (
          <div className="space-y-3">
            {turfs.map((turf) => (
              <div
                key={turf.id}
                className="card overflow-hidden flex flex-col sm:flex-row items-stretch justify-between"
              >
                <div className="relative sm:w-44 aspect-16/9 sm:aspect-auto bg-surface-2 shrink-0">
                  {turf.cover_image ? (
                    <img
                      src={turf.cover_image}
                      alt={turf.name}
                      className="w-full h-full object-cover"
                    />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center text-2xl">🏟️</div>
                  )}
                  <span
                    className={`absolute top-2.5 left-2.5 rounded-full px-2.5 py-0.5 text-[10px] font-extrabold uppercase tracking-wider ${
                      turf.is_active
                        ? 'bg-neon text-ink'
                        : 'bg-surface/90 text-muted border border-line'
                    }`}
                  >
                    {turf.is_active ? 'Live' : 'Hidden'}
                  </span>
                </div>

                <div className="p-4 flex-1 flex flex-col justify-between gap-3">
                  <div className="space-y-1.5">
                    <div className="flex items-start justify-between gap-2">
                      <div>
                        <h3 className="text-base font-bold text-text">{turf.name}</h3>
                        <p className="text-xs text-muted flex items-center gap-1 mt-0.5">
                          <MapPin className="w-3.5 h-3.5 text-neon shrink-0" />
                          <span>{turf.area} · {turf.address}</span>
                        </p>
                      </div>
                      {turf.min_price != null && (
                        <div className="text-right shrink-0">
                          <div className="text-sm font-extrabold text-neon">
                            From {formatINR(turf.min_price)}/hr
                          </div>
                          <div className="text-[10px] text-muted">
                            {turf.courts_count} {turf.courts_count === 1 ? 'court' : 'courts'}
                          </div>
                        </div>
                      )}
                    </div>

                    {/* Sports & Deal badges */}
                    <div className="flex flex-wrap items-center gap-1.5 pt-1">
                      {(turf.sports ?? []).map((sid) => {
                        const sp = sportsMap.get(sid)
                        return (
                          <span
                            key={sid}
                            className="inline-flex items-center gap-1 rounded-md bg-surface-2 border border-line px-2 py-0.5 text-[11px] text-text"
                          >
                            <span>{sp?.emoji ?? '🏟️'}</span>
                            <span>{sp?.name ?? sid}</span>
                          </span>
                        )
                      })}
                      {turf.deals_count > 0 && (
                        <span className="inline-flex items-center gap-1 rounded-md bg-neon/15 border border-neon/30 px-2 py-0.5 text-[11px] font-semibold text-neon">
                          <Zap className="w-3 h-3" />
                          <span>
                            {turf.deals_count} {turf.deals_count === 1 ? 'Happy Hour deal' : 'Deals'}
                          </span>
                        </span>
                      )}
                      {turf.rating_count > 0 && (
                        <span className="inline-flex items-center gap-1 rounded-md bg-surface-2 px-2 py-0.5 text-[11px] text-neon font-semibold">
                          <Star className="w-3 h-3 fill-neon text-neon" />
                          {Number(turf.rating_avg).toFixed(1)} ({turf.rating_count})
                        </span>
                      )}
                    </div>
                  </div>

                  {/* Actions */}
                  <div className="flex flex-wrap items-center justify-between gap-2 pt-2 border-t border-line">
                    <span className="text-xs text-muted">
                      Today: <strong className="text-text">{turf.today_bookings}</strong> bookings
                    </span>
                    <div className="flex flex-wrap items-center gap-2">
                      <Link
                        to={`/owner/turfs/${turf.id}/edit`}
                        className="btn-secondary h-8 px-3 text-xs"
                      >
                        <Edit3 className="w-3.5 h-3.5 text-neon" />
                        <span>Edit Turf</span>
                      </Link>
                      <Link
                        to={`/turf/${turf.slug}`}
                        className="btn-secondary h-8 px-3 text-xs"
                        title="Preview on Player App"
                      >
                        <ExternalLink className="w-3.5 h-3.5 text-neon" />
                        <span>Player View</span>
                      </Link>
                      <button
                        type="button"
                        onClick={() => handleToggleActive(turf.id, turf.is_active)}
                        disabled={setTurfActive.isPending}
                        className="btn-secondary h-8 px-3 text-xs"
                      >
                        {turf.is_active ? (
                          <>
                            <EyeOff className="w-3.5 h-3.5 text-muted" />
                            <span>Hide</span>
                          </>
                        ) : (
                          <>
                            <Eye className="w-3.5 h-3.5 text-neon" />
                            <span>Publish</span>
                          </>
                        )}
                      </button>
                      <button
                        type="button"
                        onClick={() => handleDeleteTurf(turf.id, turf.name)}
                        disabled={deleteTurf.isPending}
                        className="h-8 w-8 rounded-xl bg-danger/10 border border-danger/30 text-danger flex items-center justify-center hover:bg-danger/20 transition"
                        title="Delete turf"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* Upcoming Bookings Section */}
      <section className="space-y-3">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-bold uppercase tracking-wider text-muted">
            Upcoming & Active Bookings ({upcoming.length})
          </h2>
          <Link to="/owner/bookings" className="text-xs font-bold text-neon hover:underline">
            View all & block slots →
          </Link>
        </div>

        {upcoming.length === 0 ? (
          <div className="card p-5 text-center space-y-2">
            <p className="text-xs text-muted">
              No upcoming bookings right now. New player bookings and walk-ins will appear here live.
            </p>
            <div className="flex justify-center gap-2 pt-1">
              <Link to="/owner/bookings" className="btn-secondary h-8 px-3 text-xs">
                Add Walk-in / Block Slot
              </Link>
            </div>
          </div>
        ) : (
          <div className="space-y-2.5">
            {upcoming.map((b) => {
              const sp = sportsMap.get(b.sport_id)
              return (
                <div
                  key={b.id}
                  className="card p-3.5 flex flex-col sm:flex-row sm:items-center justify-between gap-3"
                >
                  <div className="space-y-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="rounded-md bg-neon/15 border border-neon/35 px-2 py-0.5 font-mono text-xs font-bold text-neon">
                        #{b.code}
                      </span>
                      <span className="text-sm font-bold text-text">{b.turf_name}</span>
                      <span className="text-xs text-muted">· {b.court_name}</span>
                      <span className="inline-flex items-center gap-1 rounded-md bg-surface-2 px-2 py-0.5 text-[11px]">
                        {sp?.emoji ?? '🏟️'} {sp?.name ?? b.sport_id}
                      </span>
                    </div>

                    <div className="flex flex-wrap items-center gap-3 text-xs text-muted">
                      <span className="inline-flex items-center gap-1 text-text font-medium">
                        <Clock className="w-3.5 h-3.5 text-neon" />
                        {formatDay(b.starts_at)} · {formatRange(b.starts_at, b.ends_at)}
                      </span>
                      <span className="inline-flex items-center gap-1">
                        <Users className="w-3.5 h-3.5 text-neon" />
                        {b.players_count} players
                      </span>
                      <span className="font-bold text-neon">{formatINR(b.total_price)}</span>
                    </div>

                    <div className="flex flex-wrap items-center gap-3 text-xs text-muted pt-0.5">
                      <span>
                        Player: <strong className="text-text">{b.player_name}</strong>
                      </span>
                      {b.player_phone && (
                        <a
                          href={`tel:${b.player_phone}`}
                          className="inline-flex items-center gap-1 text-neon hover:underline"
                        >
                          <Phone className="w-3 h-3" />
                          {b.player_phone}
                        </a>
                      )}
                      {b.source !== 'app' && (
                        <span className="uppercase text-[10px] font-bold px-2 py-0.5 rounded bg-surface-2 text-muted">
                          {b.source === 'walk_in' ? 'Walk-In' : 'Blocked'}
                        </span>
                      )}
                    </div>
                  </div>

                  <div className="flex items-center gap-2 shrink-0">
                    {b.status === 'checked_in' ? (
                      <span className="inline-flex items-center gap-1.5 rounded-xl bg-neon/15 border border-neon/40 px-3 py-1.5 text-xs font-bold text-neon">
                        <CheckCircle2 className="w-4 h-4" />
                        Checked In
                      </span>
                    ) : (
                      <button
                        type="button"
                        onClick={() => handleQuickCheckIn(b.id)}
                        disabled={checkIn.isPending}
                        className="btn-primary h-9 px-3.5 text-xs"
                      >
                        <CheckCircle2 className="w-3.5 h-3.5" />
                        <span>Check In</span>
                      </button>
                    )}
                  </div>
                </div>
              )
            })}
          </div>
        )}
      </section>
    </div>
  )
}
