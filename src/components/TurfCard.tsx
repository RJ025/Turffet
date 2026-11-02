import { Link } from 'react-router-dom'
import { Heart, MapPin, Star, Clock, Zap } from 'lucide-react'
import type { Sport, TurfListItem } from '@/lib/types'
import { formatClock, formatINR } from '@/lib/format'

interface Props {
  turf: TurfListItem
  sportsMap: Map<string, Sport>
  isFavourite: boolean
  onToggleFavourite: () => void
}

export function TurfCard({ turf, sportsMap, isFavourite, onToggleFavourite }: Props) {
  const hasOffpeak = turf.offpeak_price != null && (turf.min_price == null || turf.offpeak_price < turf.min_price)

  return (
    <div className="card overflow-hidden group transition hover:border-neon/40">
      <div className="relative aspect-16/9 bg-surface-2 overflow-hidden">
        <Link to={`/turf/${turf.slug}`} className="block w-full h-full">
          {turf.cover_image ? (
            <img
              src={turf.cover_image}
              alt={turf.name}
              loading="lazy"
              className="w-full h-full object-cover transition duration-500 group-hover:scale-105"
            />
          ) : (
            <div className="w-full h-full flex items-center justify-center text-muted text-sm">No photo</div>
          )}
          <div className="absolute inset-0 bg-linear-to-t from-ink/90 via-ink/25 to-transparent" />
        </Link>

        {/* Top badges */}
        <div className="absolute top-3 left-3 flex items-center gap-2">
          {hasOffpeak && (
            <span className="inline-flex items-center gap-1 rounded-full bg-neon text-ink px-2.5 py-1 text-xs font-bold shadow">
              <Zap className="w-3 h-3 fill-current" />
              Happy Hour {formatINR(turf.offpeak_price)}
            </span>
          )}
          {turf.distance_km != null && (
            <span className="inline-flex items-center gap-1 rounded-full bg-ink/80 backdrop-blur px-2.5 py-1 text-xs font-medium text-text border border-white/10">
              {turf.distance_km} km
            </span>
          )}
        </div>

        {/* Favourite button */}
        <button
          type="button"
          onClick={(e) => {
            e.preventDefault()
            e.stopPropagation()
            onToggleFavourite()
          }}
          aria-label={isFavourite ? 'Remove from saved' : 'Save turf'}
          className="absolute top-3 right-3 w-9 h-9 rounded-full bg-ink/75 backdrop-blur border border-white/10 flex items-center justify-center transition active:scale-90"
        >
          <Heart className={`w-4 h-4 ${isFavourite ? 'fill-danger text-danger' : 'text-text'}`} />
        </button>

        {/* Bottom overlay: sports + rating */}
        <div className="absolute bottom-2.5 inset-x-3 flex items-center justify-between gap-2 pointer-events-none">
          <div className="flex items-center gap-1.5 overflow-x-auto no-scrollbar">
            {turf.sports.map((sid) => {
              const sp = sportsMap.get(sid)
              return (
                <span
                  key={sid}
                  className="inline-flex items-center gap-1 rounded-full bg-ink/80 backdrop-blur px-2.5 py-0.5 text-xs font-medium text-text border border-white/10"
                >
                  <span>{sp?.emoji ?? '🏟️'}</span>
                  <span>{sp?.name ?? sid}</span>
                </span>
              )
            })}
          </div>
          {turf.rating_count > 0 && (
            <span className="inline-flex items-center gap-1 rounded-full bg-ink/85 backdrop-blur px-2.5 py-0.5 text-xs font-semibold text-text border border-white/10 shrink-0">
              <Star className="w-3.5 h-3.5 fill-neon text-neon" />
              {Number(turf.rating_avg).toFixed(1)}
              <span className="text-muted font-normal">({turf.rating_count})</span>
            </span>
          )}
        </div>
      </div>

      <Link to={`/turf/${turf.slug}`} className="block p-4 space-y-2.5">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <h3 className="text-base font-bold text-text truncate group-hover:text-neon transition">
              {turf.name}
            </h3>
            <p className="text-xs text-muted flex items-center gap-1 truncate mt-0.5">
              <MapPin className="w-3.5 h-3.5 shrink-0 text-neon" />
              <span className="truncate">{turf.area}</span>
            </p>
          </div>
          <div className="text-right shrink-0">
            <div className="text-[11px] text-muted">Starts at</div>
            <div className="text-base font-bold text-neon">
              {formatINR(hasOffpeak ? turf.offpeak_price : turf.min_price)}
              <span className="text-xs font-normal text-muted">/hr</span>
            </div>
          </div>
        </div>

        <div className="flex items-center justify-between pt-2 border-t border-line text-xs text-muted">
          <span className="inline-flex items-center gap-1.5">
            <Clock className="w-3.5 h-3.5" />
            {turf.opens_at && turf.closes_at
              ? `${formatClock(turf.opens_at)} – ${formatClock(turf.closes_at)}`
              : 'Open daily'}
          </span>
          <span className="text-neon font-semibold">Check live slots →</span>
        </div>
      </Link>
    </div>
  )
}
