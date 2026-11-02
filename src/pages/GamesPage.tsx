import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { Users, Calendar, Clock, MapPin, Sparkles, Plus } from 'lucide-react'
import { useGames, useSports } from '@/lib/api'
import { useUserLocation } from '@/lib/location'
import { formatDay, formatINR, formatRange, SKILL_LABEL } from '@/lib/format'
import type { Sport } from '@/lib/types'

export function GamesPage() {
  const { location } = useUserLocation()
  const { data: sports = [] } = useSports()
  const [mine, setMine] = useState(false)
  const [sport, setSport] = useState<string | null>(null)

  const { data: games = [], isLoading } = useGames({
    lat: location.lat,
    lng: location.lng,
    sport,
    mine,
  })

  const sportsMap = useMemo(() => {
    const m = new Map<string, Sport>()
    for (const s of sports) m.set(s.id, s)
    return m
  }, [sports])

  return (
    <div className="p-4 space-y-4 safe-top">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-bold">Find Players</h1>
          <p className="text-xs text-muted">Join open games near you or host one when booking a turf</p>
        </div>
        <Link to="/" className="btn-primary h-9 px-3 text-xs shrink-0">
          <Plus className="w-3.5 h-3.5" />
          <span>Host game</span>
        </Link>
      </div>

      {/* Tabs */}
      <div className="grid grid-cols-2 rounded-xl bg-surface p-1 border border-line">
        <button
          type="button"
          onClick={() => setMine(false)}
          className={`h-9 rounded-lg text-xs font-semibold transition ${
            !mine ? 'bg-neon text-ink' : 'text-muted hover:text-text'
          }`}
        >
          Open games near you
        </button>
        <button
          type="button"
          onClick={() => setMine(true)}
          className={`h-9 rounded-lg text-xs font-semibold transition ${
            mine ? 'bg-neon text-ink' : 'text-muted hover:text-text'
          }`}
        >
          My games & requests
        </button>
      </div>

      {/* Sport filter */}
      <div className="flex items-center gap-2 overflow-x-auto no-scrollbar -mx-4 px-4">
        <button
          type="button"
          onClick={() => setSport(null)}
          className={sport === null ? 'chip-active h-8 text-xs' : 'chip h-8 text-xs'}
        >
          All sports
        </button>
        {sports.map((s) => (
          <button
            key={s.id}
            type="button"
            onClick={() => setSport((cur) => (cur === s.id ? null : s.id))}
            className={sport === s.id ? 'chip-active h-8 text-xs' : 'chip h-8 text-xs'}
          >
            <span>{s.emoji}</span>
            <span>{s.name}</span>
          </button>
        ))}
      </div>

      {isLoading ? (
        <div className="space-y-3">
          {[1, 2].map((n) => (
            <div key={n} className="card h-36 animate-pulse bg-surface-2" />
          ))}
        </div>
      ) : games.length === 0 ? (
        <div className="card p-8 text-center space-y-3">
          <Users className="w-8 h-8 text-neon mx-auto" />
          <h3 className="text-base font-bold">
            {mine ? 'You haven’t joined or hosted any games yet' : 'No open games right now'}
          </h3>
          <p className="text-xs text-muted max-w-xs mx-auto">
            Book a slot at any turf and switch on “Looking for more players” to invite nearby players.
          </p>
          <Link to="/" className="btn-primary text-xs h-9">
            Find a turf to book
          </Link>
        </div>
      ) : (
        <div className="space-y-3">
          {games.map((g) => {
            const sp = sportsMap.get(g.sport_id)
            const spotsLeft = Math.max(0, g.spots_total - g.spots_filled)
            const perHead = Math.round(g.total_price / (g.players_count + g.spots_total))

            return (
              <Link
                key={g.id}
                to={`/games/${g.id}`}
                className="card p-4 block space-y-3 hover:border-neon/40 transition"
              >
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <div className="flex flex-wrap items-center gap-1.5">
                      <span className="inline-flex items-center gap-1 rounded-md bg-surface-2 px-2 py-0.5 text-xs font-semibold text-text">
                        {sp?.emoji ?? '🏟️'} {sp?.name ?? g.sport_id}
                      </span>
                      {g.skill_level && (
                        <span className="inline-flex items-center gap-1 rounded-md bg-neon/10 text-neon px-2 py-0.5 text-[11px] font-semibold">
                          <Sparkles className="w-3 h-3" />
                          {SKILL_LABEL[g.skill_level]}
                        </span>
                      )}
                      {g.is_host && (
                        <span className="rounded-md bg-info/15 text-info px-2 py-0.5 text-[10px] font-bold uppercase">
                          Host
                        </span>
                      )}
                      {g.my_status && (
                        <span className="rounded-md bg-neon/15 text-neon px-2 py-0.5 text-[10px] font-bold uppercase">
                          {g.my_status}
                        </span>
                      )}
                    </div>
                    <h3 className="text-base font-bold text-text truncate mt-1.5">{g.turf_name}</h3>
                    <p className="text-xs text-muted flex items-center gap-1 truncate">
                      <MapPin className="w-3 h-3 text-neon shrink-0" />
                      <span>
                        {g.turf_area}
                        {g.distance_km != null ? ` · ${g.distance_km} km` : ''}
                      </span>
                    </p>
                  </div>

                  <div className="text-right shrink-0">
                    <span className="inline-flex items-center gap-1 rounded-full bg-neon text-ink px-2.5 py-0.5 text-xs font-extrabold">
                      {spotsLeft} {spotsLeft === 1 ? 'spot' : 'spots'} left
                    </span>
                    <div className="text-xs text-muted mt-1">~{formatINR(perHead)}/player</div>
                  </div>
                </div>

                {g.note && <p className="text-xs text-muted line-clamp-2">“{g.note}”</p>}

                <div className="flex items-center justify-between pt-2 border-t border-line text-xs text-text">
                  <div className="flex items-center gap-3">
                    <span className="inline-flex items-center gap-1">
                      <Calendar className="w-3.5 h-3.5 text-neon" />
                      {formatDay(g.starts_at)}
                    </span>
                    <span className="inline-flex items-center gap-1">
                      <Clock className="w-3.5 h-3.5 text-neon" />
                      {formatRange(g.starts_at, g.ends_at)}
                    </span>
                  </div>
                  <span className="text-muted">Hosted by {g.host_name}</span>
                </div>
              </Link>
            )
          })}
        </div>
      )}
    </div>
  )
}
