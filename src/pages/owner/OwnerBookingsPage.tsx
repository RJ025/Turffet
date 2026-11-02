import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import {
  CalendarCheck2,
  CheckCircle2,
  XCircle,
  AlertTriangle,
  Plus,
  Users,
  Clock,
  Phone,
  QrCode,
} from 'lucide-react'
import {
  useOwnerBlockSlots,
  useOwnerBookings,
  useOwnerCancelBooking,
  useOwnerCheckIn,
  useOwnerDashboard,
  useOwnerMarkNoShow,
  useOwnerTurfDetail,
} from '@/lib/ownerApi'
import { useSports, useTurfSlots } from '@/lib/api'
import { formatDay, formatINR, formatRange, formatTime, istDateKey, nextDays } from '@/lib/format'
import { BottomSheet } from '@/components/BottomSheet'
import { useToast } from '@/components/Toast'
import { errorMessage } from '@/lib/errors'
import type { Sport } from '@/lib/types'

export function OwnerBookingsPage() {
  const { data: dashboard } = useOwnerDashboard()
  const { data: sports = [] } = useSports()
  const checkIn = useOwnerCheckIn()
  const markNoShow = useOwnerMarkNoShow()
  const cancelBooking = useOwnerCancelBooking()
  const blockSlots = useOwnerBlockSlots()
  const { toast } = useToast()

  const ownerTurfs = dashboard?.turfs ?? []
  const days = useMemo(() => nextDays(14), [])

  const [selectedDate, setSelectedDate] = useState<string>(() => istDateKey())
  const [selectedTurfId, setSelectedTurfId] = useState<string>('')
  const [showAllUpcoming, setShowAllUpcoming] = useState<boolean>(true)

  const { data: bookings = [], isLoading } = useOwnerBookings({
    from: showAllUpcoming ? istDateKey() : selectedDate,
    to: showAllUpcoming ? days[days.length - 1]?.key ?? selectedDate : selectedDate,
    turfId: selectedTurfId || null,
  })

  // Walk-in / Block Slot sheet state
  const [walkInOpen, setWalkInOpen] = useState(false)
  const [modalTurfId, setModalTurfId] = useState<string>('')
  const [modalCourtId, setModalCourtId] = useState<string>('')
  const [modalDate, setModalDate] = useState<string>(() => istDateKey())
  const [modalStartTime, setModalStartTime] = useState<string>('')
  const [modalSlotsCount, setModalSlotsCount] = useState<number>(1)
  const [modalSource, setModalSource] = useState<'walk_in' | 'blocked'>('walk_in')
  const [modalSportId, setModalSportId] = useState<string>('football')
  const [modalPlayers, setModalPlayers] = useState<number>(10)
  const [modalPrice, setModalPrice] = useState<string>('')
  const [modalNote, setModalNote] = useState<string>('')

  useEffect(() => {
    if (ownerTurfs.length && !modalTurfId) {
      setModalTurfId(ownerTurfs[0]!.id)
    }
  }, [ownerTurfs, modalTurfId])

  const { data: modalTurfDetail } = useOwnerTurfDetail(modalTurfId || undefined)
  const { data: modalSlots = [] } = useTurfSlots(modalTurfId || undefined, modalDate)

  useEffect(() => {
    if (modalTurfDetail?.courts.length) {
      const firstCourt = modalTurfDetail.courts[0]!
      setModalCourtId(firstCourt.id)
      const firstSport = firstCourt.court_sports[0]?.sport_id ?? 'football'
      setModalSportId(firstSport)
      setModalPlayers(Math.min(10, firstCourt.max_players))
    }
  }, [modalTurfDetail])

  const activeModalCourt = useMemo(
    () => modalTurfDetail?.courts.find((c) => c.id === modalCourtId) ?? modalTurfDetail?.courts[0] ?? null,
    [modalTurfDetail, modalCourtId],
  )

  const availableCourtSlots = useMemo(
    () => modalSlots.filter((s) => s.court_id === activeModalCourt?.id && s.is_available),
    [modalSlots, activeModalCourt],
  )

  useEffect(() => {
    if (availableCourtSlots.length && !availableCourtSlots.some((s) => s.starts_at === modalStartTime)) {
      setModalStartTime(availableCourtSlots[0]!.starts_at)
    }
  }, [availableCourtSlots, modalStartTime])

  const sportsMap = useMemo(() => {
    const m = new Map<string, Sport>()
    for (const s of sports) m.set(s.id, s)
    return m
  }, [sports])

  const handleCheckIn = async (bookingId: string) => {
    try {
      await checkIn.mutateAsync({ bookingId })
      toast('Booking marked Checked In!', 'success')
    } catch (err) {
      toast(errorMessage(err), 'error')
    }
  }

  const handleNoShow = async (bookingId: string) => {
    if (!window.confirm('Mark this booking as No-Show? This adds a strike to the player account.')) {
      return
    }
    try {
      await markNoShow.mutateAsync(bookingId)
      toast('Booking marked as No-Show', 'info')
    } catch (err) {
      toast(errorMessage(err), 'error')
    }
  }

  const handleCancel = async (bookingId: string) => {
    const reason = window.prompt('Reason for cancelling this booking (sent to player):', 'Slot maintenance')
    if (reason === null) return
    try {
      await cancelBooking.mutateAsync({ bookingId, reason })
      toast('Booking cancelled', 'info')
    } catch (err) {
      toast(errorMessage(err), 'error')
    }
  }

  const handleCreateWalkInOrBlock = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!activeModalCourt || !modalStartTime) {
      toast('Please select a court and available time slot', 'error')
      return
    }
    try {
      await blockSlots.mutateAsync({
        courtId: activeModalCourt.id,
        sportId: modalSportId,
        startsAt: modalStartTime,
        slots: modalSlotsCount,
        players: modalPlayers,
        source: modalSource,
        price: modalSource === 'blocked' ? 0 : modalPrice ? Number(modalPrice) : null,
        note: modalNote.trim() || (modalSource === 'walk_in' ? 'Walk-in booking' : 'Blocked by owner'),
      })
      toast(
        modalSource === 'walk_in' ? 'Walk-in booking added!' : 'Slot blocked on calendar!',
        'success',
      )
      setWalkInOpen(false)
      setModalNote('')
      setModalPrice('')
    } catch (err) {
      toast(errorMessage(err), 'error')
    }
  }

  return (
    <div className="p-4 space-y-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-extrabold text-text">Bookings & Slot Schedule</h1>
          <p className="text-xs text-muted">
            View player bookings, check in squads, or add walk-in bookings & maintenance blocks
          </p>
        </div>

        <div className="flex items-center gap-2">
          <Link to="/owner/scan" className="btn-secondary h-10 px-3 text-xs">
            <QrCode className="w-4 h-4 text-neon" />
            <span>Scan QR</span>
          </Link>
          <button
            type="button"
            onClick={() => setWalkInOpen(true)}
            disabled={ownerTurfs.length === 0}
            className="btn-primary h-10 px-4 text-xs shadow-glow"
          >
            <Plus className="w-4 h-4" />
            <span>Walk-In / Block Slot</span>
          </button>
        </div>
      </div>

      {/* Filters: Turf selector + Date toggle */}
      <div className="card p-3.5 space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={() => setShowAllUpcoming(true)}
              className={showAllUpcoming ? 'chip-active h-8 text-xs' : 'chip h-8 text-xs'}
            >
              Next 14 Days
            </button>
            <button
              type="button"
              onClick={() => setShowAllUpcoming(false)}
              className={!showAllUpcoming ? 'chip-active h-8 text-xs' : 'chip h-8 text-xs'}
            >
              Filter by Day
            </button>
          </div>

          <select
            value={selectedTurfId}
            onChange={(e) => setSelectedTurfId(e.target.value)}
            className="input h-9 px-3 text-xs bg-surface-2 w-full sm:w-64"
          >
            <option value="">All Your Turfs ({ownerTurfs.length})</option>
            {ownerTurfs.map((t) => (
              <option key={t.id} value={t.id}>
                {t.name} ({t.area})
              </option>
            ))}
          </select>
        </div>

        {!showAllUpcoming && (
          <div className="flex items-center gap-2 overflow-x-auto no-scrollbar pt-1">
            {days.map((d) => {
              const active = d.key === selectedDate
              return (
                <button
                  key={d.key}
                  type="button"
                  onClick={() => setSelectedDate(d.key)}
                  className={`shrink-0 w-14 rounded-xl border py-2 flex flex-col items-center text-xs transition ${
                    active
                      ? 'border-neon bg-neon text-ink font-bold'
                      : 'border-line bg-surface-2 text-text'
                  }`}
                >
                  <span className="text-[10px] uppercase opacity-75">{d.weekday}</span>
                  <span className="text-sm font-extrabold">{d.day}</span>
                </button>
              )
            })}
          </div>
        )}
      </div>

      {/* Bookings List */}
      {isLoading ? (
        <div className="space-y-3">
          {[1, 2, 3].map((i) => (
            <div key={i} className="card h-28 animate-pulse bg-surface-2" />
          ))}
        </div>
      ) : bookings.length === 0 ? (
        <div className="card p-8 text-center space-y-3">
          <CalendarCheck2 className="w-8 h-8 text-neon mx-auto" />
          <h3 className="text-base font-bold text-text">No bookings found for this filter</h3>
          <p className="text-xs text-muted max-w-xs mx-auto">
            When players book slots on your turf or when you add a walk-in booking, they’ll show up here.
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {bookings.map((b) => {
            const sp = sportsMap.get(b.sport_id)
            return (
              <div key={b.id} className="card p-4 space-y-3">
                <div className="flex flex-wrap items-start justify-between gap-2">
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
                      {b.source !== 'app' && (
                        <span className="rounded bg-surface-3 border border-line px-2 py-0.5 text-[10px] font-bold uppercase text-muted">
                          {b.source === 'walk_in' ? 'Walk-In' : 'Blocked Slot'}
                        </span>
                      )}
                    </div>

                    <div className="flex flex-wrap items-center gap-3 text-xs text-muted">
                      <span className="inline-flex items-center gap-1 font-semibold text-text">
                        <Clock className="w-3.5 h-3.5 text-neon" />
                        {formatDay(b.starts_at)} · {formatRange(b.starts_at, b.ends_at)}
                      </span>
                      <span className="inline-flex items-center gap-1">
                        <Users className="w-3.5 h-3.5 text-neon" />
                        {b.players_count} players
                      </span>
                      <span className="font-bold text-neon">{formatINR(b.total_price)}</span>
                    </div>
                  </div>

                  <span
                    className={`rounded-full px-2.5 py-0.5 text-[10px] font-extrabold uppercase ${
                      b.status === 'checked_in'
                        ? 'bg-neon text-ink'
                        : b.status === 'confirmed'
                          ? 'bg-neon/15 text-neon border border-neon/30'
                          : 'bg-danger/15 text-danger'
                    }`}
                  >
                    {b.status.replace('_', ' ')}
                  </span>
                </div>

                <div className="flex flex-wrap items-center justify-between gap-2 pt-2 border-t border-line text-xs">
                  <div className="flex flex-wrap items-center gap-3 text-muted">
                    <span>
                      Booked by: <strong className="text-text">{b.player_name}</strong>
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
                    {b.note && <span className="text-muted">· “{b.note}”</span>}
                  </div>

                  {b.status === 'confirmed' && (
                    <div className="flex items-center gap-2">
                      <button
                        type="button"
                        onClick={() => handleCheckIn(b.id)}
                        disabled={checkIn.isPending}
                        className="btn-primary h-8 px-3 text-xs"
                      >
                        <CheckCircle2 className="w-3.5 h-3.5" />
                        <span>Check In</span>
                      </button>
                      <button
                        type="button"
                        onClick={() => handleNoShow(b.id)}
                        disabled={markNoShow.isPending}
                        className="btn-secondary h-8 px-2.5 text-xs"
                        title="Mark No-Show"
                      >
                        <AlertTriangle className="w-3.5 h-3.5 text-warn" />
                        <span>No-Show</span>
                      </button>
                      <button
                        type="button"
                        onClick={() => handleCancel(b.id)}
                        disabled={cancelBooking.isPending}
                        className="btn-secondary h-8 px-2.5 text-xs text-danger"
                        title="Cancel Booking"
                      >
                        <XCircle className="w-3.5 h-3.5" />
                        <span>Cancel</span>
                      </button>
                    </div>
                  )}
                </div>
              </div>
            )
          })}
        </div>
      )}

      {/* Walk-In / Block Slot Bottom Sheet */}
      <BottomSheet
        open={walkInOpen}
        onClose={() => setWalkInOpen(false)}
        title="Add Walk-In Booking or Block Slot"
      >
        <form onSubmit={handleCreateWalkInOrBlock} className="space-y-3.5">
          <div className="grid grid-cols-2 gap-2">
            <button
              type="button"
              onClick={() => setModalSource('walk_in')}
              className={
                modalSource === 'walk_in'
                  ? 'chip-active justify-center h-10 text-xs font-bold'
                  : 'chip justify-center h-10 text-xs'
              }
            >
              Walk-In Customer
            </button>
            <button
              type="button"
              onClick={() => setModalSource('blocked')}
              className={
                modalSource === 'blocked'
                  ? 'chip-active justify-center h-10 text-xs font-bold'
                  : 'chip justify-center h-10 text-xs'
              }
            >
              Block for Maintenance
            </button>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div className="space-y-1">
              <label className="label">Select Turf</label>
              <select
                value={modalTurfId}
                onChange={(e) => setModalTurfId(e.target.value)}
                className="input h-10 text-xs bg-surface-2"
              >
                {ownerTurfs.map((t) => (
                  <option key={t.id} value={t.id}>
                    {t.name}
                  </option>
                ))}
              </select>
            </div>

            <div className="space-y-1">
              <label className="label">Select Court / Pitch</label>
              <select
                value={modalCourtId}
                onChange={(e) => setModalCourtId(e.target.value)}
                className="input h-10 text-xs bg-surface-2"
              >
                {(modalTurfDetail?.courts ?? []).map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name} ({formatINR(c.base_price)}/slot)
                  </option>
                ))}
              </select>
            </div>

            <div className="space-y-1">
              <label className="label">Date</label>
              <select
                value={modalDate}
                onChange={(e) => setModalDate(e.target.value)}
                className="input h-10 text-xs bg-surface-2"
              >
                {days.map((d) => (
                  <option key={d.key} value={d.key}>
                    {d.weekday}, {d.day} {d.month}
                  </option>
                ))}
              </select>
            </div>

            <div className="space-y-1">
              <label className="label">Available Start Slot</label>
              <select
                value={modalStartTime}
                onChange={(e) => setModalStartTime(e.target.value)}
                className="input h-10 text-xs bg-surface-2"
              >
                {availableCourtSlots.length === 0 ? (
                  <option value="">No free slots on this date</option>
                ) : (
                  availableCourtSlots.map((s) => (
                    <option key={s.starts_at} value={s.starts_at}>
                      {formatTime(s.starts_at)} ({formatINR(s.price)})
                    </option>
                  ))
                )}
              </select>
            </div>

            <div className="space-y-1">
              <label className="label">Consecutive Slots</label>
              <select
                value={modalSlotsCount}
                onChange={(e) => setModalSlotsCount(Number(e.target.value))}
                className="input h-10 text-xs bg-surface-2"
              >
                {[1, 2, 3, 4].map((n) => (
                  <option key={n} value={n}>
                    {n} {n === 1 ? 'slot' : 'slots'}
                  </option>
                ))}
              </select>
            </div>

            {modalSource === 'walk_in' && (
              <>
                <div className="space-y-1">
                  <label className="label">Sport</label>
                  <select
                    value={modalSportId}
                    onChange={(e) => setModalSportId(e.target.value)}
                    className="input h-10 text-xs bg-surface-2"
                  >
                    {(activeModalCourt?.court_sports ?? []).map((cs) => (
                      <option key={cs.sport_id} value={cs.sport_id}>
                        {sportsMap.get(cs.sport_id)?.name ?? cs.sport_id}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="space-y-1">
                  <label className="label">Number of Players</label>
                  <input
                    type="number"
                    min={1}
                    max={activeModalCourt?.max_players ?? 30}
                    value={modalPlayers}
                    onChange={(e) => setModalPlayers(Number(e.target.value) || 2)}
                    className="input h-10 text-xs"
                  />
                </div>

                <div className="space-y-1">
                  <label className="label">Custom Total Price (₹, optional)</label>
                  <input
                    type="number"
                    min={0}
                    step={50}
                    value={modalPrice}
                    onChange={(e) => setModalPrice(e.target.value)}
                    placeholder="Leave blank for automatic slot price"
                    className="input h-10 text-xs"
                  />
                </div>
              </>
            )}
          </div>

          <div className="space-y-1">
            <label className="label">
              {modalSource === 'walk_in'
                ? 'Customer Name & Phone / Note'
                : 'Maintenance / Block Reason'}
            </label>
            <input
              type="text"
              value={modalNote}
              onChange={(e) => setModalNote(e.target.value)}
              placeholder={
                modalSource === 'walk_in'
                  ? 'e.g. Rahul Sharma (+91 98111 00000) — Paid cash'
                  : 'e.g. Floodlight maintenance / Corporate tournament'
              }
              className="input h-10 text-xs"
            />
          </div>

          <button
            type="submit"
            disabled={blockSlots.isPending || availableCourtSlots.length === 0}
            className="btn-primary w-full h-11 text-sm shadow-glow"
          >
            {blockSlots.isPending
              ? 'Saving…'
              : modalSource === 'walk_in'
                ? 'Confirm Walk-In Booking'
                : 'Block Selected Slot'}
          </button>
        </form>
      </BottomSheet>
    </div>
  )
}
