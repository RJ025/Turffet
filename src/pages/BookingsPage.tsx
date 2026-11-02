import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { QrCode, Calendar, Clock, Users, Star, Ticket, MapPin } from 'lucide-react'
import { useMyBookings, useSports } from '@/lib/api'
import { formatDay, formatINR, formatRange } from '@/lib/format'
import { ReviewSheet } from '@/components/ReviewSheet'
import type { BookingWithRelations, Sport } from '@/lib/types'

type Tab = 'upcoming' | 'past' | 'cancelled'

export function BookingsPage() {
  const { data: bookings = [], isLoading } = useMyBookings()
  const { data: sports = [] } = useSports()
  const [tab, setTab] = useState<Tab>('upcoming')
  const [reviewTarget, setReviewTarget] = useState<BookingWithRelations | null>(null)

  const sportsMap = useMemo(() => {
    const m = new Map<string, Sport>()
    for (const s of sports) m.set(s.id, s)
    return m
  }, [sports])

  const now = Date.now()
  const filtered = useMemo(() => {
    return bookings.filter((b) => {
      const endMs = new Date(b.ends_at).getTime()
      if (tab === 'cancelled') return b.status === 'cancelled'
      if (tab === 'upcoming') return (b.status === 'confirmed' || b.status === 'checked_in') && endMs >= now
      return b.status !== 'cancelled' && endMs < now
    })
  }, [bookings, tab, now])

  return (
    <div className="p-4 space-y-4 safe-top">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-bold">My Bookings</h1>
          <p className="text-xs text-muted">Your QR booking passes are saved for offline access</p>
        </div>
      </div>

      {/* Tabs */}
      <div className="grid grid-cols-3 rounded-xl bg-surface p-1 border border-line">
        {(['upcoming', 'past', 'cancelled'] as Tab[]).map((t) => (
          <button
            key={t}
            type="button"
            onClick={() => setTab(t)}
            className={`h-9 rounded-lg text-xs font-semibold capitalize transition ${
              tab === t ? 'bg-neon text-ink' : 'text-muted hover:text-text'
            }`}
          >
            {t}
          </button>
        ))}
      </div>

      {isLoading ? (
        <div className="space-y-3">
          {[1, 2].map((n) => (
            <div key={n} className="card h-36 animate-pulse bg-surface-2" />
          ))}
        </div>
      ) : filtered.length === 0 ? (
        <div className="card p-8 text-center space-y-3">
          <Ticket className="w-8 h-8 text-neon mx-auto" />
          <h3 className="text-base font-bold">No {tab} bookings</h3>
          <p className="text-xs text-muted max-w-xs mx-auto">
            {tab === 'upcoming'
              ? 'Book a turf slot near you and your QR pass will show up right here.'
              : 'Your booking history will appear here.'}
          </p>
          {tab === 'upcoming' && (
            <Link to="/" className="btn-primary text-xs h-9">
              Explore turfs
            </Link>
          )}
        </div>
      ) : (
        <div className="space-y-3">
          {filtered.map((b) => {
            const sp = sportsMap.get(b.sport_id)
            const reviewList = Array.isArray(b.reviews) ? b.reviews : b.reviews ? [b.reviews] : []
            const existingReview = reviewList[0]
            const canReview = b.status !== 'cancelled' && new Date(b.ends_at).getTime() < now

            return (
              <div key={b.id} className="card p-4 space-y-3">
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="inline-flex items-center gap-1 rounded-md bg-surface-2 px-2 py-0.5 text-xs font-medium text-text">
                        {sp?.emoji ?? '🏟️'} {sp?.name ?? b.sport_id}
                      </span>
                      <span className="font-mono text-xs font-bold text-neon">#{b.code}</span>
                    </div>
                    <h3 className="text-base font-bold text-text truncate mt-1">
                      {b.turfs?.name ?? 'Turf Booking'}
                    </h3>
                    <p className="text-xs text-muted flex items-center gap-1 truncate">
                      <MapPin className="w-3 h-3 text-neon shrink-0" />
                      <span>
                        {b.courts?.name} · {b.turfs?.area}
                      </span>
                    </p>
                  </div>
                  <div className="text-right shrink-0">
                    <div className="text-sm font-bold text-neon">{formatINR(b.total_price)}</div>
                    <div className="text-[10px] text-muted uppercase">{b.status}</div>
                  </div>
                </div>

                <div className="flex flex-wrap items-center gap-4 text-xs text-text pt-2 border-t border-line">
                  <span className="inline-flex items-center gap-1.5">
                    <Calendar className="w-3.5 h-3.5 text-neon" />
                    {formatDay(b.starts_at)}
                  </span>
                  <span className="inline-flex items-center gap-1.5">
                    <Clock className="w-3.5 h-3.5 text-neon" />
                    {formatRange(b.starts_at, b.ends_at)}
                  </span>
                  <span className="inline-flex items-center gap-1.5">
                    <Users className="w-3.5 h-3.5 text-neon" />
                    {b.players_count} players
                  </span>
                </div>

                <div className="flex items-center gap-2 pt-1">
                  <Link to={`/bookings/${b.id}`} className="btn-primary h-9 text-xs flex-1">
                    <QrCode className="w-3.5 h-3.5" />
                    <span>View QR Pass</span>
                  </Link>
                  {canReview && (
                    <button
                      type="button"
                      onClick={() => setReviewTarget(b)}
                      className="btn-secondary h-9 text-xs px-3"
                    >
                      <Star className="w-3.5 h-3.5 text-neon" />
                      <span>{existingReview ? `Rated ${existingReview.rating}★` : 'Rate turf'}</span>
                    </button>
                  )}
                </div>
              </div>
            )
          })}
        </div>
      )}

      {reviewTarget && (
        <ReviewSheet
          open={Boolean(reviewTarget)}
          onClose={() => setReviewTarget(null)}
          bookingId={reviewTarget.id}
          turfName={reviewTarget.turfs?.name ?? 'Turf'}
        />
      )}
    </div>
  )
}
