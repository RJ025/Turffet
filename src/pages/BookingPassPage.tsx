import { useMemo, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { QRCodeSVG } from 'qrcode.react'
import {
  ArrowLeft,
  Calendar,
  Clock,
  Users,
  MapPin,
  Navigation,
  Phone,
  MessageCircle,
  CheckCircle2,
  XCircle,
  Copy,
  Star,
  UserPlus,
  Wifi,
} from 'lucide-react'
import { useAppSettings, useBooking, useCancelBooking, useSports } from '@/lib/api'
import {
  directionsUrl,
  formatINR,
  formatLongDay,
  formatRange,
  whatsappUrl,
} from '@/lib/format'
import { BottomSheet } from '@/components/BottomSheet'
import { ReviewSheet } from '@/components/ReviewSheet'
import { useToast } from '@/components/Toast'
import { errorMessage } from '@/lib/errors'
import type { Sport } from '@/lib/types'

export function BookingPassPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { toast } = useToast()

  const { data: booking, isLoading } = useBooking(id)
  const { data: sports = [] } = useSports()
  const { data: settings } = useAppSettings()
  const cancelMutation = useCancelBooking()

  const [cancelOpen, setCancelOpen] = useState(false)
  const [cancelReason, setCancelReason] = useState('')
  const [reviewOpen, setReviewOpen] = useState(false)

  const sportsMap = useMemo(() => {
    const m = new Map<string, Sport>()
    for (const s of sports) m.set(s.id, s)
    return m
  }, [sports])

  if (isLoading) {
    return (
      <div className="p-4 space-y-4">
        <div className="card h-96 animate-pulse bg-surface-2" />
      </div>
    )
  }

  if (!booking) {
    return (
      <div className="p-6 text-center space-y-3">
        <h2 className="text-lg font-bold">Booking pass not found</h2>
        <Link to="/bookings" className="btn-primary">
          Back to Bookings
        </Link>
      </div>
    )
  }

  const sp = sportsMap.get(booking.sport_id)
  const windowMins = settings?.cancellation_window_minutes ?? 120
  const minsUntilStart = Math.round((new Date(booking.starts_at).getTime() - Date.now()) / 60000)
  const canCancel = booking.status === 'confirmed' && minsUntilStart >= windowMins
  const isPast = new Date(booking.ends_at).getTime() < Date.now()
  const openGame = Array.isArray(booking.open_games) ? booking.open_games[0] : booking.open_games

  const handleCopyCode = async () => {
    await navigator.clipboard?.writeText(booking.code)
    toast(`Booking code ${booking.code} copied`, 'info')
  }

  const handleCancel = async () => {
    try {
      await cancelMutation.mutateAsync({ bookingId: booking.id, reason: cancelReason })
      toast('Booking cancelled.', 'info')
      setCancelOpen(false)
    } catch (err) {
      toast(errorMessage(err), 'error')
    }
  }

  return (
    <div className="p-4 space-y-4 safe-top">
      <div className="flex items-center justify-between">
        <button
          type="button"
          onClick={() => navigate('/bookings')}
          className="btn-secondary h-9 px-3 text-xs"
        >
          <ArrowLeft className="w-3.5 h-3.5" />
          <span>My Bookings</span>
        </button>
        <span className="inline-flex items-center gap-1.5 rounded-full bg-surface-2 border border-line px-3 py-1 text-[11px] text-muted">
          <Wifi className="w-3 h-3 text-neon" />
          Offline Pass Ready
        </span>
      </div>

      {/* Ticket card */}
      <div className="card overflow-hidden">
        {/* Status header */}
        <div
          className={`px-5 py-3 flex items-center justify-between text-xs font-bold uppercase tracking-wider ${
            booking.status === 'cancelled'
              ? 'bg-danger/15 text-danger border-b border-danger/30'
              : 'bg-neon text-ink'
          }`}
        >
          <span className="inline-flex items-center gap-1.5">
            {booking.status === 'cancelled' ? (
              <XCircle className="w-4 h-4" />
            ) : (
              <CheckCircle2 className="w-4 h-4" />
            )}
            Booking {booking.status}
          </span>
          <span>Pay at venue · {formatINR(booking.total_price)}</span>
        </div>

        {/* QR Pass section */}
        <div className="p-6 flex flex-col items-center text-center border-b border-dashed border-line space-y-3 bg-linear-to-b from-surface-2/60 to-surface">
          <div
            className={`p-4 rounded-2xl bg-white shadow-xl transition ${
              booking.status === 'cancelled' ? 'opacity-30 grayscale' : 'animate-pop'
            }`}
          >
            <QRCodeSVG value={booking.qr_token} size={196} level="M" />
          </div>

          <div className="space-y-1">
            <div className="text-[11px] uppercase tracking-widest text-muted">Booking Code</div>
            <button
              type="button"
              onClick={handleCopyCode}
              className="inline-flex items-center gap-2 rounded-xl bg-surface-2 border border-line px-4 py-1.5 font-mono text-lg font-bold tracking-widest text-neon hover:border-neon/50"
            >
              <span>{booking.code}</span>
              <Copy className="w-3.5 h-3.5 text-muted" />
            </button>
          </div>
          <p className="text-xs text-muted max-w-xs">
            Show this QR code to the turf manager when your group arrives at the venue.
          </p>
        </div>

        {/* Details */}
        <div className="p-5 space-y-4">
          <div>
            <div className="inline-flex items-center gap-1.5 rounded-md bg-surface-2 px-2.5 py-0.5 text-xs font-semibold text-neon mb-1">
              <span>{sp?.emoji ?? '🏟️'}</span>
              <span>{sp?.name ?? booking.sport_id}</span>
            </div>
            <h1 className="text-lg font-bold text-text">{booking.turfs?.name}</h1>
            <p className="text-xs text-muted flex items-center gap-1 mt-0.5">
              <MapPin className="w-3.5 h-3.5 text-neon shrink-0" />
              <span>{booking.turfs?.address}</span>
            </p>
          </div>

          <div className="grid grid-cols-2 gap-3 rounded-2xl bg-surface-2 border border-line p-3.5 text-xs">
            <div className="space-y-0.5">
              <div className="text-muted flex items-center gap-1">
                <Calendar className="w-3.5 h-3.5 text-neon" /> Date
              </div>
              <div className="font-semibold text-text">{formatLongDay(booking.starts_at)}</div>
            </div>
            <div className="space-y-0.5">
              <div className="text-muted flex items-center gap-1">
                <Clock className="w-3.5 h-3.5 text-neon" /> Time
              </div>
              <div className="font-semibold text-text">
                {formatRange(booking.starts_at, booking.ends_at)}
              </div>
            </div>
            <div className="space-y-0.5">
              <div className="text-muted">Pitch / Court</div>
              <div className="font-semibold text-text">
                {booking.courts?.name}{' '}
                {booking.courts?.size_label ? `(${booking.courts.size_label})` : ''}
              </div>
            </div>
            <div className="space-y-0.5">
              <div className="text-muted flex items-center gap-1">
                <Users className="w-3.5 h-3.5 text-neon" /> Players
              </div>
              <div className="font-semibold text-text">{booking.players_count} players coming</div>
            </div>
          </div>

          {openGame && (
            <Link
              to={`/games/${openGame.id}`}
              className="flex items-center justify-between rounded-xl border border-neon/40 bg-neon/10 px-4 py-3 text-xs"
            >
              <span className="flex items-center gap-2 font-semibold text-neon">
                <UserPlus className="w-4 h-4" />
                Looking for {openGame.spots_total} players · Manage requests
              </span>
              <span className="text-neon font-bold">Open →</span>
            </Link>
          )}

          {/* Venue actions */}
          {booking.turfs && (
            <div className="flex items-center gap-2">
              <a
                href={directionsUrl(booking.turfs.lat, booking.turfs.lng)}
                target="_blank"
                rel="noreferrer"
                className="btn-secondary h-10 text-xs flex-1"
              >
                <Navigation className="w-3.5 h-3.5 text-neon" />
                <span>Directions</span>
              </a>
              {booking.turfs.phone && (
                <a href={`tel:${booking.turfs.phone}`} className="btn-secondary h-10 text-xs flex-1">
                  <Phone className="w-3.5 h-3.5 text-neon" />
                  <span>Call</span>
                </a>
              )}
              {booking.turfs.whatsapp && (
                <a
                  href={whatsappUrl(
                    booking.turfs.whatsapp,
                    `Hi ${booking.turfs.name}, my Turffet booking code is ${booking.code}`,
                  )}
                  target="_blank"
                  rel="noreferrer"
                  className="btn-secondary h-10 text-xs flex-1"
                >
                  <MessageCircle className="w-3.5 h-3.5 text-neon" />
                  <span>WhatsApp</span>
                </a>
              )}
            </div>
          )}

          {/* Review or Cancel */}
          {isPast && booking.status !== 'cancelled' && (
            <button
              type="button"
              onClick={() => setReviewOpen(true)}
              className="btn-primary w-full"
            >
              <Star className="w-4 h-4" />
              <span>Rate & review your experience</span>
            </button>
          )}

          {booking.status === 'confirmed' && !isPast && (
            <div className="pt-2 border-t border-line space-y-2">
              {canCancel ? (
                <button
                  type="button"
                  onClick={() => setCancelOpen(true)}
                  className="btn-danger w-full h-10 text-xs"
                >
                  Cancel booking (free until {Math.round(windowMins / 60)}h before slot)
                </button>
              ) : (
                <p className="text-center text-xs text-muted">
                  Free cancellation closed ({Math.round(windowMins / 60)}h before kick-off). Need help? Call the turf directly.
                </p>
              )}
            </div>
          )}
        </div>
      </div>

      <BottomSheet open={cancelOpen} onClose={() => setCancelOpen(false)} title="Cancel this booking?">
        <p className="text-xs text-muted">
          Your slot at <strong className="text-text">{booking.turfs?.name}</strong> will be released immediately so other players can book it.
        </p>
        <input
          type="text"
          value={cancelReason}
          onChange={(e) => setCancelReason(e.target.value)}
          placeholder="Reason for cancelling (optional)"
          className="input h-10 text-sm"
        />
        <div className="flex gap-2">
          <button type="button" onClick={() => setCancelOpen(false)} className="btn-secondary flex-1">
            Keep slot
          </button>
          <button
            type="button"
            disabled={cancelMutation.isPending}
            onClick={handleCancel}
            className="btn-danger flex-1"
          >
            {cancelMutation.isPending ? 'Cancelling…' : 'Yes, cancel'}
          </button>
        </div>
      </BottomSheet>

      <ReviewSheet
        open={reviewOpen}
        onClose={() => setReviewOpen(false)}
        bookingId={booking.id}
        turfName={booking.turfs?.name ?? 'Turf'}
      />
    </div>
  )
}
