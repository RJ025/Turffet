import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Users, UserPlus, Sparkles, ShieldAlert, Calendar, Clock, Minus, Plus } from 'lucide-react'
import { BottomSheet } from './BottomSheet'
import { useCreateBooking } from '@/lib/api'
import { useAuth } from '@/lib/auth'
import { useToast } from './Toast'
import { errorMessage } from '@/lib/errors'
import { formatDay, formatINR, formatRange, SKILL_LABEL } from '@/lib/format'
import type { Court, SkillLevel, Slot, Sport, TurfDetail } from '@/lib/types'

interface Props {
  open: boolean
  onClose: () => void
  turf: TurfDetail
  court: Court
  slots: Slot[]
  sportsMap: Map<string, Sport>
  cancellationWindowMinutes: number
}

export function BookingSheet({
  open,
  onClose,
  turf,
  court,
  slots,
  sportsMap,
  cancellationWindowMinutes,
}: Props) {
  const navigate = useNavigate()
  const { user, profile } = useAuth()
  const { toast } = useToast()
  const createBooking = useCreateBooking()

  const supportedSports = court.court_sports.map((cs) => cs.sport_id)
  const [sportId, setSportId] = useState<string>(supportedSports[0] ?? 'football')
  const activeSportConfig = court.court_sports.find((cs) => cs.sport_id === sportId)
  const maxPlayersForSport = activeSportConfig?.max_players ?? court.max_players
  const [players, setPlayers] = useState<number>(() => Math.min(8, maxPlayersForSport))
  const [openToJoin, setOpenToJoin] = useState(false)
  const [lookingFor, setLookingFor] = useState(2)
  const [skill, setSkill] = useState<SkillLevel>(profile?.skill_level ?? 'intermediate')
  const [note, setNote] = useState('')

  if (!slots.length) return null
  const firstSlot = slots[0]!
  const lastSlot = slots[slots.length - 1]!
  const totalPrice = slots.reduce((sum, s) => sum + s.price, 0)
  const regularTotal = court.base_price * slots.length
  const savings = Math.max(0, regularTotal - totalPrice)
  const clampedPlayers = Math.min(players, maxPlayersForSport)
  const maxLookingFor = Math.max(1, maxPlayersForSport - clampedPlayers)

  const handleConfirm = async () => {
    if (!user) {
      toast('Sign in to confirm your booking', 'info')
      navigate(`/auth?next=${encodeURIComponent(`/turf/${turf.slug}`)}`)
      return
    }
    try {
      const booking = await createBooking.mutateAsync({
        courtId: court.id,
        sportId: supportedSports.includes(sportId) ? sportId : (supportedSports[0] ?? 'football'),
        startsAt: firstSlot.starts_at,
        slots: slots.length,
        players: clampedPlayers,
        lookingFor: openToJoin ? Math.min(lookingFor, maxLookingFor) : 0,
        skill: openToJoin ? skill : null,
        note: note.trim() || null,
        turf,
        totalPrice,
      })
      toast('Booking confirmed! Here is your QR pass.', 'success')
      onClose()
      navigate(`/bookings/${booking.id}`)
    } catch (err) {
      toast(errorMessage(err), 'error')
    }
  }

  return (
    <BottomSheet open={open} onClose={onClose} title="Confirm your booking">
      {/* Summary banner */}
      <div className="rounded-2xl bg-surface-2 border border-line p-3.5 space-y-2">
        <div className="flex items-center justify-between">
          <div>
            <div className="text-sm font-bold text-text">{turf.name}</div>
            <div className="text-xs text-muted">
              {court.name} {court.size_label ? `· ${court.size_label}` : ''}
            </div>
          </div>
          <div className="text-right">
            <div className="text-base font-bold text-neon">{formatINR(totalPrice)}</div>
            <div className="text-[11px] text-muted">Pay at venue</div>
          </div>
        </div>
        <div className="flex items-center gap-4 pt-2 border-t border-line text-xs text-text">
          <span className="inline-flex items-center gap-1.5">
            <Calendar className="w-3.5 h-3.5 text-neon" />
            {formatDay(firstSlot.starts_at)}
          </span>
          <span className="inline-flex items-center gap-1.5">
            <Clock className="w-3.5 h-3.5 text-neon" />
            {formatRange(firstSlot.starts_at, lastSlot.ends_at)} ({slots.length}h)
          </span>
        </div>
        {savings > 0 && (
          <div className="inline-flex items-center gap-1.5 rounded-lg bg-neon/10 text-neon px-2.5 py-1 text-xs font-semibold">
            <Sparkles className="w-3.5 h-3.5" />
            You save {formatINR(savings)} with Happy Hour pricing!
          </div>
        )}
      </div>

      {/* Sport selector (when court supports multiple sports) */}
      {supportedSports.length > 1 && (
        <div className="space-y-2">
          <div className="label">Which sport are you playing?</div>
          <div className="flex flex-wrap gap-2">
            {supportedSports.map((sid) => {
              const sp = sportsMap.get(sid)
              const active = sportId === sid
              return (
                <button
                  key={sid}
                  type="button"
                  onClick={() => setSportId(sid)}
                  className={active ? 'chip-active' : 'chip'}
                >
                  <span>{sp?.emoji ?? '🏟️'}</span>
                  <span>{sp?.name ?? sid}</span>
                </button>
              )
            })}
          </div>
        </div>
      )}

      {/* Number of players coming */}
      <div className="rounded-2xl bg-surface-2 border border-line p-3.5 flex items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-xl bg-surface-3 text-neon flex items-center justify-center shrink-0">
            <Users className="w-4 h-4" />
          </div>
          <div>
            <div className="text-sm font-semibold text-text">Players coming</div>
            <div className="text-xs text-muted">
              Shared with the turf owner (max {maxPlayersForSport} for {sportsMap.get(sportId)?.name ?? sportId})
            </div>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={() => setPlayers((p) => Math.max(1, Math.min(p, maxPlayersForSport) - 1))}
            className="w-8 h-8 rounded-lg bg-surface-3 border border-line flex items-center justify-center text-text active:scale-95"
          >
            <Minus className="w-3.5 h-3.5" />
          </button>
          <span className="w-7 text-center text-sm font-bold">{clampedPlayers}</span>
          <button
            type="button"
            onClick={() => setPlayers((p) => Math.min(maxPlayersForSport, p + 1))}
            className="w-8 h-8 rounded-lg bg-surface-3 border border-line flex items-center justify-center text-text active:scale-95"
          >
            <Plus className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>

      {/* Find Players toggle: looking for X more players */}
      {clampedPlayers < maxPlayersForSport && (
        <div className="rounded-2xl border border-line bg-surface-2 p-3.5 space-y-3">
          <button
            type="button"
            onClick={() => setOpenToJoin((v) => !v)}
            className="w-full flex items-center justify-between gap-3 text-left"
          >
            <div className="flex items-center gap-3">
              <div className="w-9 h-9 rounded-xl bg-neon/15 text-neon flex items-center justify-center shrink-0">
                <UserPlus className="w-4 h-4" />
              </div>
              <div>
                <div className="text-sm font-semibold text-text">Looking for more players?</div>
                <div className="text-xs text-muted">Post this game to Find Players so nearby players can join</div>
              </div>
            </div>
            <div
              className={`w-10 h-6 rounded-full p-0.5 transition ${
                openToJoin ? 'bg-neon' : 'bg-surface-3 border border-line'
              }`}
            >
              <div
                className={`w-5 h-5 rounded-full transition transform ${
                  openToJoin ? 'translate-x-4 bg-ink' : 'translate-x-0 bg-muted'
                }`}
              />
            </div>
          </button>

          {openToJoin && (
            <div className="pt-3 border-t border-line space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-xs font-medium text-text">How many extra players do you need?</span>
                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() => setLookingFor((n) => Math.max(1, n - 1))}
                    className="w-7 h-7 rounded-lg bg-surface-3 border border-line flex items-center justify-center text-xs"
                  >
                    -
                  </button>
                  <span className="w-6 text-center text-sm font-bold text-neon">
                    {Math.min(lookingFor, maxLookingFor)}
                  </span>
                  <button
                    type="button"
                    onClick={() => setLookingFor((n) => Math.min(maxLookingFor, n + 1))}
                    className="w-7 h-7 rounded-lg bg-surface-3 border border-line flex items-center justify-center text-xs"
                  >
                    +
                  </button>
                </div>
              </div>

              <div className="space-y-1.5">
                <div className="text-xs text-muted">Preferred skill level</div>
                <div className="flex gap-2">
                  {(['beginner', 'intermediate', 'advanced'] as SkillLevel[]).map((lv) => (
                    <button
                      key={lv}
                      type="button"
                      onClick={() => setSkill(lv)}
                      className={skill === lv ? 'chip-active text-xs h-8' : 'chip text-xs h-8'}
                    >
                      {SKILL_LABEL[lv]}
                    </button>
                  ))}
                </div>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Optional note */}
      <div className="space-y-1.5">
        <label className="label" htmlFor="booking-note">
          Note for turf / players (optional)
        </label>
        <input
          id="booking-note"
          type="text"
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="e.g. Need bibs & match ball, friendly 5v5"
          maxLength={140}
          className="input h-10 text-sm"
        />
      </div>

      {/* Cancellation policy */}
      <div className="flex items-start gap-2.5 rounded-xl bg-surface-2/60 border border-line px-3 py-2.5 text-xs text-muted">
        <ShieldAlert className="w-4 h-4 text-neon shrink-0 mt-0.5" />
        <span>
          Free cancellation up to <strong className="text-text">{Math.round(cancellationWindowMinutes / 60)} hours</strong>{' '}
          before kick-off. You’ll receive an instant QR pass to show at the venue.
        </span>
      </div>

      <button
        type="button"
        disabled={createBooking.isPending}
        onClick={handleConfirm}
        className="btn-primary w-full h-12 text-base shadow-glow"
      >
        {createBooking.isPending ? 'Locking your slot…' : `Confirm booking · ${formatINR(totalPrice)}`}
      </button>
    </BottomSheet>
  )
}
