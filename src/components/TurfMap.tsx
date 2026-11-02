import { useState } from 'react'
import { Link } from 'react-router-dom'
import { APIProvider, Map as GoogleMap, AdvancedMarker } from '@vis.gl/react-google-maps'
import { MapPin, Star, Navigation, Zap, X } from 'lucide-react'
import type { Sport, TurfListItem } from '@/lib/types'
import { formatINR, directionsUrl } from '@/lib/format'
import type { UserLocation } from '@/lib/location'

const API_KEY = (import.meta.env.VITE_GOOGLE_MAPS_API_KEY as string) || ''
const MAP_ID = (import.meta.env.VITE_GOOGLE_MAP_ID as string) || 'DEMO_MAP_ID'

interface Props {
  turfs: TurfListItem[]
  userLocation: UserLocation
  sportsMap: Map<string, Sport>
}

export function TurfMap({ turfs, userLocation, sportsMap }: Props) {
  const [selected, setSelected] = useState<TurfListItem | null>(turfs[0] ?? null)

  if (!API_KEY) {
    return (
      <div className="card p-6 text-center space-y-2">
        <MapPin className="w-8 h-8 text-neon mx-auto" />
        <p className="text-sm font-semibold">Google Maps API key missing</p>
        <p className="text-xs text-muted">Set VITE_GOOGLE_MAPS_API_KEY in .env to enable the map view.</p>
      </div>
    )
  }

  return (
    <div className="relative w-full h-[calc(100dvh-13.5rem)] min-h-[420px] rounded-2xl overflow-hidden border border-line bg-surface-2">
      <APIProvider apiKey={API_KEY}>
        <GoogleMap
          mapId={MAP_ID}
          defaultCenter={{ lat: userLocation.lat, lng: userLocation.lng }}
          defaultZoom={12}
          gestureHandling="greedy"
          disableDefaultUI={true}
          colorScheme="DARK"
          className="w-full h-full"
        >
          {/* User location dot */}
          <AdvancedMarker position={{ lat: userLocation.lat, lng: userLocation.lng }} title={userLocation.label}>
            <div className="relative flex items-center justify-center">
              <div className="w-7 h-7 rounded-full bg-info/30 animate-ping absolute" />
              <div className="w-3.5 h-3.5 rounded-full bg-info border-2 border-white shadow" />
            </div>
          </AdvancedMarker>

          {/* Turf price markers */}
          {turfs.map((t) => {
            const isSelected = selected?.id === t.id
            const price = t.offpeak_price != null && (t.min_price == null || t.offpeak_price < t.min_price)
              ? t.offpeak_price
              : t.min_price
            return (
              <AdvancedMarker
                key={t.id}
                position={{ lat: t.lat, lng: t.lng }}
                onClick={() => setSelected(t)}
                zIndex={isSelected ? 20 : 1}
              >
                <button
                  type="button"
                  onClick={() => setSelected(t)}
                  className={`flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-bold shadow-lg transition transform ${
                    isSelected
                      ? 'bg-neon text-ink scale-110 ring-2 ring-white'
                      : 'bg-ink text-text border border-neon/60 hover:scale-105'
                  }`}
                >
                  <span>{ sportsMap.get(t.sports[0] ?? '')?.emoji ?? '🏟️' }</span>
                  <span>{formatINR(price)}</span>
                </button>
              </AdvancedMarker>
            )
          })}
        </GoogleMap>
      </APIProvider>

      {/* Bottom turf preview card */}
      {selected && (
        <div className="absolute bottom-3 inset-x-3 z-10 card p-3.5 bg-surface/95 backdrop-blur shadow-2xl animate-fade-up">
          <button
            type="button"
            onClick={() => setSelected(null)}
            aria-label="Close preview"
            className="absolute top-2.5 right-2.5 w-7 h-7 rounded-full bg-surface-2 flex items-center justify-center text-muted hover:text-text"
          >
            <X className="w-3.5 h-3.5" />
          </button>
          <div className="flex gap-3">
            {selected.cover_image && (
              <img
                src={selected.cover_image}
                alt={selected.name}
                className="w-24 h-20 rounded-xl object-cover shrink-0 bg-surface-2"
              />
            )}
            <div className="flex-1 min-w-0 pr-5">
              <div className="flex items-center gap-1.5">
                {selected.offpeak_price != null && (
                  <span className="inline-flex items-center gap-0.5 rounded bg-neon/15 text-neon px-1.5 py-0.5 text-[10px] font-bold">
                    <Zap className="w-2.5 h-2.5" /> Deal
                  </span>
                )}
                {selected.rating_count > 0 && (
                  <span className="inline-flex items-center gap-0.5 text-xs font-semibold text-text">
                    <Star className="w-3 h-3 fill-neon text-neon" />
                    {Number(selected.rating_avg).toFixed(1)}
                  </span>
                )}
                {selected.distance_km != null && (
                  <span className="text-xs text-muted">· {selected.distance_km} km</span>
                )}
              </div>
              <h4 className="text-sm font-bold text-text truncate mt-0.5">{selected.name}</h4>
              <p className="text-xs text-muted truncate">{selected.area}</p>
              <div className="flex items-center justify-between mt-2">
                <div className="text-sm font-bold text-neon">
                  {formatINR(selected.offpeak_price ?? selected.min_price)}
                  <span className="text-xs font-normal text-muted">/hr</span>
                </div>
                <div className="flex items-center gap-2">
                  <a
                    href={directionsUrl(selected.lat, selected.lng)}
                    target="_blank"
                    rel="noreferrer"
                    className="w-8 h-8 rounded-lg bg-surface-2 border border-line flex items-center justify-center text-text"
                    title="Directions"
                  >
                    <Navigation className="w-3.5 h-3.5" />
                  </a>
                  <Link to={`/turf/${selected.slug}`} className="btn-primary h-8 px-3 text-xs rounded-lg">
                    View slots
                  </Link>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
