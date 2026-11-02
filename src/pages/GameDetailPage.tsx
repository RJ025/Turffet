import { useMemo, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import {
  ArrowLeft,
  Calendar,
  Clock,
  MapPin,
  Navigation,
  Users,
  Sparkles,
  Check,
  X,
  MessageCircle,
} from 'lucide-react'
import {
  useGameDetail,
  useRequestJoin,
  useRespondJoin,
  useSetGameOpen,
  useSports,
  useWithdrawJoin,
} from '@/lib/api'
import { useAuth } from '@/lib/auth'
import {
  directionsUrl,
  formatINR,
  formatLongDay,
  formatRange,
  initials,
  SKILL_LABEL,
  whatsappUrl,
} from '@/lib/format'
import { useToast } from '@/components/Toast'
import { errorMessage } from '@/lib/errors'
import type { Sport } from '@/lib/types'

export function GameDetailPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { user } = useAuth()
  const { toast } = useToast()

  const { data: game, isLoading } = useGameDetail(id)
  const { data: sports = [] } = useSports()
  const requestJoin = useRequestJoin()
  const respondJoin = useRespondJoin()
  const withdrawJoin = useWithdrawJoin()
  const setGameOpen = useSetGameOpen()

  const [message, setMessage] = useState('')

  const sportsMap = useMemo(() => {
    const m = new Map<string, Sport>()
    for (const s of sports) m.set(s.id, s)
    return m
  }, [sports])

  if (isLoading) {
    return (
      <div className="p-4 space-y-4">
        <div className="card h-64 animate-pulse bg-surface-2" />
      </div>
    )
  }

  if (!game) {
    return (
      <div className="p-6 text-center space-y-3">
        <h2 className="text-lg font-bold">Game not found</h2>
        <Link to="/games" className="btn-primary">
          Back to Find Players
        </Link>
      </div>
    )
  }

  const sp = sportsMap.get(game.sport_id)
  const spotsLeft = Math.max(0, game.spots_total - game.players.length)
  const perHead = Math.round(game.booking.total_price / (game.booking.players_count + game.spots_total))
  const isSample = game.id.startsWith('sample-game-')

  const handleJoin = async () => {
    if (!user) {
      toast('Sign in to request a spot in this game', 'info')
      navigate(`/auth?next=${encodeURIComponent(`/games/${game.id}`)}`)
      return
    }
    if (isSample) {
      toast('Join request sent to the host!', 'success')
      return
    }
    try {
      await requestJoin.mutateAsync({ gameId: game.id, message })
      toast('Join request sent to the host!', 'success')
      setMessage('')
    } catch (err) {
      toast(errorMessage(err), 'error')
    }
  }

  const handleWithdraw = async () => {
    try {
      await withdrawJoin.mutateAsync({ gameId: game.id })
      toast('Request withdrawn', 'info')
    } catch (err) {
      toast(errorMessage(err), 'error')
    }
  }

  return (
    <div className="p-4 space-y-4 safe-top">
      <div className="flex items-center justify-between">
        <button
          type="button"
          onClick={() => navigate('/games')}
          className="btn-secondary h-9 px-3 text-xs"
        >
          <ArrowLeft className="w-3.5 h-3.5" />
          <span>Find Players</span>
        </button>
        <span className="inline-flex items-center gap-1 rounded-full bg-neon/15 text-neon px-3 py-1 text-xs font-bold">
          {spotsLeft} of {game.spots_total} spots open
        </span>
      </div>

      {/* Main game card */}
      <div className="card p-5 space-y-4">
        <div className="flex items-start justify-between gap-3">
          <div>
            <div className="flex items-center gap-2">
              <span className="inline-flex items-center gap-1 rounded-md bg-surface-2 px-2.5 py-0.5 text-xs font-semibold text-neon">
                {sp?.emoji ?? '🏟️'} {sp?.name ?? game.sport_id}
              </span>
              {game.skill_level && (
                <span className="inline-flex items-center gap-1 rounded-md bg-surface-2 px-2.5 py-0.5 text-xs text-text">
                  <Sparkles className="w-3 h-3 text-neon" />
                  {SKILL_LABEL[game.skill_level]}
                </span>
              )}
            </div>
            <Link
              to={`/turf/${game.turf.slug}`}
              className="text-lg font-bold text-text hover:text-neon transition block mt-1.5"
            >
              {game.turf.name}
            </Link>
            <p className="text-xs text-muted flex items-center gap-1 mt-0.5">
              <MapPin className="w-3.5 h-3.5 text-neon shrink-0" />
              <span>{game.turf.address}</span>
            </p>
          </div>
          <a
            href={directionsUrl(game.turf.lat, game.turf.lng)}
            target="_blank"
            rel="noreferrer"
            className="btn-secondary h-9 px-3 text-xs shrink-0"
          >
            <Navigation className="w-3.5 h-3.5 text-neon" />
            <span>Map</span>
          </a>
        </div>

        <div className="grid grid-cols-2 gap-3 rounded-2xl bg-surface-2 border border-line p-3.5 text-xs">
          <div>
            <div className="text-muted flex items-center gap-1">
              <Calendar className="w-3.5 h-3.5 text-neon" /> Date
            </div>
            <div className="font-semibold text-text mt-0.5">{formatLongDay(game.starts_at)}</div>
          </div>
          <div>
            <div className="text-muted flex items-center gap-1">
              <Clock className="w-3.5 h-3.5 text-neon" /> Time
            </div>
            <div className="font-semibold text-text mt-0.5">
              {formatRange(game.starts_at, game.ends_at)}
            </div>
          </div>
          <div>
            <div className="text-muted">Court / Pitch</div>
            <div className="font-semibold text-text mt-0.5">
              {game.booking.court_name}{' '}
              {game.booking.size_label ? `(${game.booking.size_label})` : ''}
            </div>
          </div>
          <div>
            <div className="text-muted">Est. share at venue</div>
            <div className="font-semibold text-neon mt-0.5">~{formatINR(perHead)} / player</div>
          </div>
        </div>

        {game.note && (
          <div className="rounded-xl bg-surface-2/60 border border-line p-3 text-xs text-text">
            <span className="text-muted font-semibold block mb-0.5">Host’s note:</span>
            {game.note}
          </div>
        )}

        {/* Roster */}
        <div className="space-y-2">
          <div className="label flex items-center gap-1.5">
            <Users className="w-3.5 h-3.5 text-neon" />
            <span>
              Squad ({game.booking.players_count} in host’s group + {game.players.length} joined)
            </span>
          </div>
          <div className="flex flex-wrap gap-2">
            <div className="inline-flex items-center gap-2 rounded-xl bg-surface-2 border border-neon/40 px-3 py-1.5 text-xs">
              <span className="w-6 h-6 rounded-full bg-neon text-ink font-bold flex items-center justify-center text-[11px]">
                {initials(game.host.name)}
              </span>
              <span className="font-semibold">{game.host.name} (Host)</span>
            </div>
            {game.players.map((p, idx) => (
              <div
                key={idx}
                className="inline-flex items-center gap-2 rounded-xl bg-surface-2 border border-line px-3 py-1.5 text-xs"
              >
                <span className="w-6 h-6 rounded-full bg-surface-3 text-text font-bold flex items-center justify-center text-[11px]">
                  {initials(p.name)}
                </span>
                <span>{p.name}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Visitor actions */}
        {!game.is_host && (
          <div className="pt-2 border-t border-line space-y-3">
            {game.my_request?.status === 'accepted' ? (
              <div className="space-y-2">
                <div className="rounded-xl bg-neon/15 border border-neon/40 p-3 text-xs text-neon font-semibold">
                  You’re in! Meet the squad at {game.turf.name} 10 minutes before kick-off.
                </div>
                <div className="flex gap-2">
                  {game.host.phone && (
                    <a
                      href={whatsappUrl(game.host.phone, `Hi ${game.host.name}, I joined your game on Turffet!`)}
                      target="_blank"
                      rel="noreferrer"
                      className="btn-secondary text-xs flex-1"
                    >
                      <MessageCircle className="w-3.5 h-3.5 text-neon" />
                      <span>WhatsApp Host</span>
                    </a>
                  )}
                  <button type="button" onClick={handleWithdraw} className="btn-danger text-xs flex-1">
                    Leave game
                  </button>
                </div>
              </div>
            ) : game.my_request?.status === 'pending' ? (
              <div className="flex items-center justify-between rounded-xl bg-surface-2 border border-line p-3 text-xs">
                <span className="text-muted">Your join request is waiting for the host’s approval.</span>
                <button type="button" onClick={handleWithdraw} className="text-danger font-semibold">
                  Withdraw
                </button>
              </div>
            ) : game.status === 'open' && spotsLeft > 0 ? (
              <div className="space-y-2.5">
                <input
                  type="text"
                  value={message}
                  onChange={(e) => setMessage(e.target.value)}
                  placeholder="Say hi & mention your position / skill level (optional)…"
                  maxLength={140}
                  className="input h-10 text-sm"
                />
                <button
                  type="button"
                  disabled={requestJoin.isPending}
                  onClick={handleJoin}
                  className="btn-primary w-full shadow-glow"
                >
                  {requestJoin.isPending ? 'Sending request…' : 'Request to join game'}
                </button>
              </div>
            ) : (
              <div className="text-center text-xs text-muted py-1">This game is full.</div>
            )}
          </div>
        )}
      </div>

      {/* Host controls */}
      {game.is_host && (
        <div className="card p-5 space-y-4">
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-bold uppercase tracking-wider text-muted">
              Join Requests ({game.requests?.length ?? 0})
            </h2>
            <button
              type="button"
              onClick={() =>
                setGameOpen.mutate({ gameId: game.id, open: game.status === 'closed' })
              }
              className="btn-secondary h-8 px-3 text-xs"
            >
              {game.status === 'closed' ? 'Reopen game' : 'Close requests'}
            </button>
          </div>

          {!game.requests?.length ? (
            <p className="text-xs text-muted">
              No requests yet. Nearby players will see your game in Find Players.
            </p>
          ) : (
            <div className="space-y-2.5">
              {game.requests.map((r) => (
                <div
                  key={r.id}
                  className="rounded-xl bg-surface-2 border border-line p-3 flex items-center justify-between gap-3"
                >
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-bold text-text">{r.name}</span>
                      {r.skill_level && (
                        <span className="text-[11px] text-neon font-medium">
                          {SKILL_LABEL[r.skill_level]}
                        </span>
                      )}
                    </div>
                    {r.message && <p className="text-xs text-muted mt-0.5">“{r.message}”</p>}
                  </div>
                  <div className="flex items-center gap-1.5 shrink-0">
                    {r.status === 'pending' ? (
                      <>
                        <button
                          type="button"
                          onClick={() =>
                            respondJoin.mutate({ requestId: r.id, accept: false, gameId: game.id })
                          }
                          className="w-8 h-8 rounded-lg bg-danger/15 text-danger flex items-center justify-center"
                          title="Decline"
                        >
                          <X className="w-4 h-4" />
                        </button>
                        <button
                          type="button"
                          onClick={() =>
                            respondJoin.mutate({ requestId: r.id, accept: true, gameId: game.id })
                          }
                          className="w-8 h-8 rounded-lg bg-neon text-ink flex items-center justify-center"
                          title="Accept"
                        >
                          <Check className="w-4 h-4" />
                        </button>
                      </>
                    ) : (
                      <span className="text-xs font-semibold uppercase text-muted">{r.status}</span>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  )
}
