import { useEffect, useMemo, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import {
  ArrowLeft,
  Heart,
  Share2,
  Star,
  MapPin,
  Navigation,
  Phone,
  MessageCircle,
  Zap,
  Clock,
  ShieldCheck,
  Users,
} from 'lucide-react'
import {
  useAmenities,
  useAppSettings,
  useFavourites,
  useSports,
  useToggleFavourite,
  useTurfDetail,
  useTurfReviews,
  useTurfSlots,
} from '@/lib/api'
import {
  directionsUrl,
  formatClock,
  formatDay,
  formatINR,
  formatRange,
  formatTime,
  istDateKey,
  nextDays,
  whatsappUrl,
} from '@/lib/format'
import { AmenityIcon } from '@/components/AmenityIcon'
import { BookingSheet } from '@/components/BookingSheet'
import { useToast } from '@/components/Toast'
import type { Amenity, Slot, Sport } from '@/lib/types'

export function TurfDetailPage() {
  const { slug } = useParams<{ slug: string }>()
  const navigate = useNavigate()
  const { toast } = useToast()

  const { data: turf, isLoading } = useTurfDetail(slug)
  const { data: sports = [] } = useSports()
  const { data: amenities = [] } = useAmenities()
  const { data: settings } = useAppSettings()
  const { data: favIds = [] } = useFavourites()
  const toggleFav = useToggleFavourite()

  const days = useMemo(() => nextDays(settings?.booking_horizon_days ?? 14), [settings?.booking_horizon_days])
  const [dateKey, setDateKey] = useState<string>(() => istDateKey())
  const [courtId, setCourtId] = useState<string>('')
  const [selectedStarts, setSelectedStarts] = useState<string[]>([])
  const [photoIdx, setPhotoIdx] = useState(0)
  const [bookingOpen, setBookingOpen] = useState(false)

  useEffect(() => {
    if (turf?.courts.length && !courtId) {
      setCourtId(turf.courts[0]!.id)
    }
  }, [turf, courtId])

  // Clear slot selection when court or date changes
  useEffect(() => {
    setSelectedStarts([])
  }, [courtId, dateKey])

  const { data: allSlots = [], isLoading: slotsLoading } = useTurfSlots(turf?.id, dateKey)
  const { data: reviews = [] } = useTurfReviews(turf?.id)

  const sportsMap = useMemo(() => {
    const m = new Map<string, Sport>()
    for (const s of sports) m.set(s.id, s)
    return m
  }, [sports])

  const amenitiesMap = useMemo(() => {
    const m = new Map<string, Amenity>()
    for (const a of amenities) m.set(a.id, a)
    return m
  }, [amenities])

  const activeCourt = useMemo(
    () => turf?.courts.find((c) => c.id === courtId) ?? turf?.courts[0] ?? null,
    [turf, courtId],
  )

  const courtSlots = useMemo(
    () => allSlots.filter((s) => s.court_id === activeCourt?.id),
    [allSlots, activeCourt],
  )

  const selectedSlots = useMemo(() => {
    const set = new Set(selectedStarts)
    return courtSlots.filter((s) => set.has(s.starts_at))
  }, [courtSlots, selectedStarts])

  const maxSlots = settings?.max_slots_per_booking ?? 3

  const handleSlotTap = (slot: Slot) => {
    if (!slot.is_available) return
    const idx = courtSlots.findIndex((s) => s.starts_at === slot.starts_at)
    if (idx < 0) return

    if (selectedStarts.includes(slot.starts_at)) {
      // If tapping an end of the current selection, trim it; otherwise reset
      if (selectedStarts.length === 1) {
        setSelectedStarts([])
      } else if (slot.starts_at === selectedStarts[0]) {
        setSelectedStarts(selectedStarts.slice(1))
      } else if (slot.starts_at === selectedStarts[selectedStarts.length - 1]) {
        setSelectedStarts(selectedStarts.slice(0, -1))
      } else {
        setSelectedStarts([slot.starts_at])
      }
      return
    }

    if (selectedStarts.length === 0) {
      setSelectedStarts([slot.starts_at])
      return
    }

    // Check if adjacent to current contiguous block
    const firstIdx = courtSlots.findIndex((s) => s.starts_at === selectedStarts[0])
    const lastIdx = courtSlots.findIndex((s) => s.starts_at === selectedStarts[selectedStarts.length - 1])

    if (idx === lastIdx + 1 && selectedStarts.length < maxSlots) {
      setSelectedStarts([...selectedStarts, slot.starts_at])
    } else if (idx === firstIdx - 1 && selectedStarts.length < maxSlots) {
      setSelectedStarts([slot.starts_at, ...selectedStarts])
    } else {
      setSelectedStarts([slot.starts_at])
    }
  }

  if (isLoading) {
    return (
      <div className="p-4 space-y-4">
        <div className="card h-60 animate-pulse bg-surface-2" />
        <div className="card h-36 animate-pulse bg-surface-2" />
        <div className="card h-64 animate-pulse bg-surface-2" />
      </div>
    )
  }

  if (!turf || !activeCourt) {
    return (
      <div className="p-6 text-center space-y-3">
        <h2 className="text-lg font-bold">Turf not found</h2>
        <Link to="/" className="btn-primary">
          Back to Explore
        </Link>
      </div>
    )
  }

  const photos = turf.turf_photos.length
    ? turf.turf_photos.map((p) => p.url)
    : turf.cover_image
      ? [turf.cover_image]
      : []
  const isFav = favIds.includes(turf.id)
  const offpeakRules = turf.pricing_rules.filter((r) => r.is_offpeak && (!r.court_id || r.court_id === activeCourt.id))
  const totalPrice = selectedSlots.reduce((sum, s) => sum + s.price, 0)
  const todayHours = turf.operating_hours[0]

  const handleShare = async () => {
    const url = window.location.href
    if (navigator.share) {
      try {
        await navigator.share({ title: turf.name, text: `Book ${turf.name} on Turffet`, url })
        return
      } catch {
        /* user cancelled */
      }
    }
    await navigator.clipboard?.writeText(url)
    toast('Link copied to clipboard', 'info')
  }

  return (
    <div className="pb-24 space-y-5">
      {/* Hero gallery */}
      <div className="relative aspect-16/10 bg-surface-2 overflow-hidden">
        {photos[photoIdx] && (
          <img src={photos[photoIdx]} alt={turf.name} className="w-full h-full object-cover" />
        )}
        <div className="absolute inset-0 bg-linear-to-t from-ink via-transparent to-ink/50" />

        {/* Top bar */}
        <div className="absolute top-3 inset-x-4 flex items-center justify-between safe-top">
          <button
            type="button"
            onClick={() => navigate(-1)}
            aria-label="Back"
            className="w-10 h-10 rounded-full bg-ink/75 backdrop-blur border border-white/10 flex items-center justify-center text-text"
          >
            <ArrowLeft className="w-4 h-4" />
          </button>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleShare}
              aria-label="Share"
              className="w-10 h-10 rounded-full bg-ink/75 backdrop-blur border border-white/10 flex items-center justify-center text-text"
            >
              <Share2 className="w-4 h-4" />
            </button>
            <button
              type="button"
              onClick={() => toggleFav.mutate({ turfId: turf.id, isFav })}
              aria-label="Save turf"
              className="w-10 h-10 rounded-full bg-ink/75 backdrop-blur border border-white/10 flex items-center justify-center"
            >
              <Heart className={`w-4 h-4 ${isFav ? 'fill-danger text-danger' : 'text-text'}`} />
            </button>
          </div>
        </div>

        {/* Photo thumbnails */}
        {photos.length > 1 && (
          <div className="absolute bottom-3 right-4 flex items-center gap-1.5">
            {photos.map((_, idx) => (
              <button
                key={idx}
                type="button"
                onClick={() => setPhotoIdx(idx)}
                className={`h-1.5 rounded-full transition-all ${
                  idx === photoIdx ? 'w-6 bg-neon' : 'w-2 bg-white/50'
                }`}
              />
            ))}
          </div>
        )}
      </div>

      <div className="px-4 space-y-5">
        {/* Title + Rating + Quick actions */}
        <div className="space-y-3">
          <div className="flex items-start justify-between gap-3">
            <div>
              <h1 className="text-xl font-bold text-text">{turf.name}</h1>
              <p className="text-xs text-muted flex items-center gap-1 mt-1">
                <MapPin className="w-3.5 h-3.5 text-neon shrink-0" />
                <span>{turf.address}</span>
              </p>
            </div>
            {turf.rating_count > 0 && (
              <div className="rounded-xl bg-surface border border-line px-3 py-1.5 text-right shrink-0">
                <div className="flex items-center gap-1 text-sm font-bold text-neon">
                  <Star className="w-4 h-4 fill-neon text-neon" />
                  {Number(turf.rating_avg).toFixed(1)}
                </div>
                <div className="text-[10px] text-muted">{turf.rating_count} reviews</div>
              </div>
            )}
          </div>

          {turf.description && <p className="text-sm text-muted leading-relaxed">{turf.description}</p>}

          <div className="flex items-center gap-2 pt-1">
            <a
              href={directionsUrl(turf.lat, turf.lng)}
              target="_blank"
              rel="noreferrer"
              className="btn-secondary h-9 px-3 text-xs flex-1"
            >
              <Navigation className="w-3.5 h-3.5 text-neon" />
              <span>Directions</span>
            </a>
            {turf.phone && (
              <a href={`tel:${turf.phone}`} className="btn-secondary h-9 px-3 text-xs flex-1">
                <Phone className="w-3.5 h-3.5 text-neon" />
                <span>Call turf</span>
              </a>
            )}
            {turf.whatsapp && (
              <a
                href={whatsappUrl(turf.whatsapp, `Hi ${turf.name}, checking availability via Turffet`)}
                target="_blank"
                rel="noreferrer"
                className="btn-secondary h-9 px-3 text-xs flex-1"
              >
                <MessageCircle className="w-3.5 h-3.5 text-neon" />
                <span>WhatsApp</span>
              </a>
            )}
          </div>
        </div>

        {/* Off-peak / Happy Hour callout */}
        {offpeakRules.length > 0 && (
          <div className="rounded-2xl border border-neon/35 bg-neon/10 p-3.5 flex items-start gap-3">
            <div className="w-9 h-9 rounded-xl bg-neon text-ink flex items-center justify-center shrink-0">
              <Zap className="w-4 h-4 fill-current" />
            </div>
            <div className="space-y-1 text-xs">
              <div className="font-bold text-neon text-sm">Off-Peak / Happy Hour Pricing</div>
              {offpeakRules.slice(0, 3).map((r) => {
                const effectivePrice =
                  r.price != null
                    ? r.price
                    : r.discount_pct != null
                      ? Math.round((activeCourt.base_price * (100 - r.discount_pct)) / 100)
                      : activeCourt.base_price
                return (
                  <div key={r.id} className="text-text">
                    <span className="font-semibold">{r.label ?? 'Happy Hour'}:</span>{' '}
                    {formatClock(r.start_time)} – {formatClock(r.end_time)} at{' '}
                    <span className="font-bold text-neon">{formatINR(effectivePrice)}/hr</span>
                    {r.discount_pct != null && r.discount_pct > 0 && (
                      <span className="ml-1.5 rounded bg-neon/20 text-neon px-1.5 py-0.5 text-[10px] font-bold">
                        {r.discount_pct}% OFF
                      </span>
                    )}
                  </div>
                )
              })}
            </div>
          </div>
        )}

        {/* Step 1: Select court / pitch */}
        <section className="space-y-2.5">
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-bold uppercase tracking-wider text-muted">1. Choose Pitch / Court</h2>
            {todayHours && (
              <span className="text-xs text-muted inline-flex items-center gap-1">
                <Clock className="w-3 h-3" />
                {formatClock(todayHours.open_time)} – {formatClock(todayHours.close_time)}
              </span>
            )}
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
            {turf.courts.map((c) => {
              const active = c.id === activeCourt.id
              return (
                <button
                  key={c.id}
                  type="button"
                  onClick={() => setCourtId(c.id)}
                  className={`rounded-2xl border p-3.5 text-left transition ${
                    active
                      ? 'border-neon bg-neon/10 shadow-glow'
                      : 'border-line bg-surface hover:bg-surface-2'
                  }`}
                >
                  <div className="flex items-center justify-between gap-2">
                    <span className="text-sm font-bold text-text">{c.name}</span>
                    <span className="text-sm font-bold text-neon">{formatINR(c.base_price)}/hr</span>
                  </div>
                  <div className="flex items-center justify-between text-xs text-muted mt-1">
                    <span>
                      {c.size_label} {c.surface ? `· ${c.surface}` : ''}
                    </span>
                    <span className="inline-flex items-center gap-1">
                      <Users className="w-3 h-3" /> Max {c.max_players}
                    </span>
                  </div>
                  <div className="flex flex-wrap gap-1 mt-2">
                    {c.court_sports.map(({ sport_id, max_players }) => {
                      const sp = sportsMap.get(sport_id)
                      return (
                        <span
                          key={sport_id}
                          className="inline-flex items-center gap-1 rounded-md bg-surface-2 px-2 py-0.5 text-[11px] text-text"
                        >
                          {sp?.emoji} {sp?.name ?? sport_id}
                          {max_players ? <span className="text-muted">({max_players}p)</span> : null}
                        </span>
                      )
                    })}
                  </div>
                </button>
              )
            })}
          </div>
        </section>

        {/* Step 2: Date selector */}
        <section className="space-y-2.5">
          <h2 className="text-sm font-bold uppercase tracking-wider text-muted">2. Select Date</h2>
          <div className="flex items-center gap-2 overflow-x-auto no-scrollbar -mx-4 px-4">
            {days.map((d) => {
              const active = d.key === dateKey
              return (
                <button
                  key={d.key}
                  type="button"
                  onClick={() => setDateKey(d.key)}
                  className={`shrink-0 w-16 rounded-2xl border py-2.5 flex flex-col items-center transition ${
                    active
                      ? 'border-neon bg-neon text-ink font-bold'
                      : 'border-line bg-surface text-text hover:bg-surface-2'
                  }`}
                >
                  <span className={`text-[10px] uppercase ${active ? 'text-ink/80' : 'text-muted'}`}>
                    {d.weekday}
                  </span>
                  <span className="text-base font-bold leading-tight">{d.day}</span>
                  <span className={`text-[10px] ${active ? 'text-ink/80' : 'text-muted'}`}>{d.month}</span>
                </button>
              )
            })}
          </div>
        </section>

        {/* Step 3: Live slot grid */}
        <section className="space-y-2.5">
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-bold uppercase tracking-wider text-muted">
              3. Pick Time Slots (up to {maxSlots} hrs)
            </h2>
            <span className="inline-flex items-center gap-1.5 text-xs text-neon">
              <span className="w-2 h-2 rounded-full bg-neon animate-pulse" />
              Live availability
            </span>
          </div>

          {slotsLoading ? (
            <div className="grid grid-cols-3 sm:grid-cols-4 gap-2">
              {Array.from({ length: 12 }).map((_, i) => (
                <div key={i} className="h-16 rounded-xl bg-surface-2 animate-pulse" />
              ))}
            </div>
          ) : (
            <div className="grid grid-cols-3 sm:grid-cols-4 gap-2">
              {courtSlots.map((slot) => {
                const isSelected = selectedStarts.includes(slot.starts_at)
                return (
                  <button
                    key={slot.starts_at}
                    type="button"
                    disabled={!slot.is_available}
                    onClick={() => handleSlotTap(slot)}
                    className={`relative rounded-xl border p-2.5 text-left transition ${
                      isSelected
                        ? 'border-neon bg-neon text-ink font-bold shadow-glow'
                        : !slot.is_available
                          ? 'border-line/50 bg-surface-2/40 text-muted/40 line-through cursor-not-allowed'
                          : slot.is_offpeak
                            ? 'border-neon/40 bg-neon/5 text-text hover:border-neon'
                            : 'border-line bg-surface text-text hover:bg-surface-2'
                    }`}
                  >
                    {slot.is_offpeak && slot.is_available && !isSelected && (
                      <span className="absolute -top-1.5 right-2 rounded bg-neon text-ink px-1.5 py-0.2 text-[9px] font-extrabold uppercase">
                        Deal
                      </span>
                    )}
                    <div className="text-xs font-semibold">{formatTime(slot.starts_at)}</div>
                    <div
                      className={`text-xs mt-1 ${
                        isSelected
                          ? 'text-ink font-bold'
                          : !slot.is_available
                            ? 'text-muted/40'
                            : slot.is_offpeak
                              ? 'text-neon font-bold'
                              : 'text-muted'
                      }`}
                    >
                      {slot.is_mine ? 'Your slot' : !slot.is_available ? 'Booked' : formatINR(slot.price)}
                    </div>
                  </button>
                )
              })}
            </div>
          )}
        </section>

        {/* Amenities */}
        <section className="space-y-2.5">
          <h2 className="text-sm font-bold uppercase tracking-wider text-muted">Amenities</h2>
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
            {turf.turf_amenities.map(({ amenity_id }) => {
              const a = amenitiesMap.get(amenity_id)
              return (
                <div
                  key={amenity_id}
                  className="flex items-center gap-2.5 rounded-xl bg-surface border border-line px-3 py-2.5 text-xs font-medium text-text"
                >
                  <AmenityIcon icon={a?.icon ?? 'check'} className="w-4 h-4 text-neon shrink-0" />
                  <span>{a?.name ?? amenity_id}</span>
                </div>
              )
            })}
          </div>
        </section>

        {/* Rules */}
        {turf.rules.length > 0 && (
          <section className="space-y-2.5">
            <h2 className="text-sm font-bold uppercase tracking-wider text-muted">Turf Rules</h2>
            <div className="card p-4 space-y-2">
              {turf.rules.map((rule, idx) => (
                <div key={idx} className="flex items-start gap-2.5 text-xs text-muted">
                  <ShieldCheck className="w-4 h-4 text-neon shrink-0 mt-0.5" />
                  <span>{rule}</span>
                </div>
              ))}
            </div>
          </section>
        )}

        {/* Reviews */}
        <section className="space-y-2.5">
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-bold uppercase tracking-wider text-muted">
              Player Reviews ({reviews.length})
            </h2>
          </div>
          {reviews.length === 0 ? (
            <div className="card p-4 text-xs text-muted">
              No written reviews yet. Book a slot and be the first to review!
            </div>
          ) : (
            <div className="space-y-2.5">
              {reviews.map((rev) => (
                <div key={rev.id} className="card p-3.5 space-y-1.5">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-bold text-text">{rev.reviewer_name}</span>
                    <span className="inline-flex items-center gap-1 text-xs font-bold text-neon">
                      <Star className="w-3.5 h-3.5 fill-neon text-neon" />
                      {rev.rating}.0
                    </span>
                  </div>
                  {rev.comment && <p className="text-xs text-muted leading-relaxed">{rev.comment}</p>}
                  <div className="text-[10px] text-muted">{formatDay(rev.created_at)}</div>
                </div>
              ))}
            </div>
          )}
        </section>
      </div>

      {/* Sticky bottom booking bar */}
      {selectedSlots.length > 0 && (
        <div className="fixed bottom-16 inset-x-0 z-30 px-4 pb-2 pointer-events-none">
          <div className="max-w-2xl mx-auto pointer-events-auto rounded-2xl bg-surface/95 backdrop-blur border border-neon/50 p-3.5 shadow-2xl flex items-center justify-between gap-3 animate-fade-up">
            <div>
              <div className="text-xs text-muted">
                {activeCourt.name} · {formatRange(selectedSlots[0]!.starts_at, selectedSlots[selectedSlots.length - 1]!.ends_at)}
              </div>
              <div className="text-base font-bold text-neon">
                {formatINR(totalPrice)}{' '}
                <span className="text-xs font-normal text-muted">
                  ({selectedSlots.length} {selectedSlots.length === 1 ? 'slot' : 'slots'})
                </span>
              </div>
            </div>
            <button
              type="button"
              onClick={() => setBookingOpen(true)}
              className="btn-primary h-11 px-5 shadow-glow"
            >
              Continue →
            </button>
          </div>
        </div>
      )}

      <BookingSheet
        open={bookingOpen}
        onClose={() => setBookingOpen(false)}
        turf={turf}
        court={activeCourt}
        slots={selectedSlots}
        sportsMap={sportsMap}
        cancellationWindowMinutes={settings?.cancellation_window_minutes ?? 120}
      />
    </div>
  )
}
