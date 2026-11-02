import { useMemo } from 'react'
import { Link } from 'react-router-dom'
import { Heart } from 'lucide-react'
import { useFavourites, useNearbyTurfs, useSports, useToggleFavourite } from '@/lib/api'
import { useUserLocation } from '@/lib/location'
import { TurfCard } from '@/components/TurfCard'
import type { Sport } from '@/lib/types'

export function FavouritesPage() {
  const { location } = useUserLocation()
  const { data: favIds = [], isLoading: favsLoading } = useFavourites()
  const { data: allTurfs = [], isLoading: turfsLoading } = useNearbyTurfs({
    lat: location.lat,
    lng: location.lng,
    radiusKm: 120,
  })
  const { data: sports = [] } = useSports()
  const toggleFav = useToggleFavourite()

  const sportsMap = useMemo(() => {
    const m = new Map<string, Sport>()
    for (const s of sports) m.set(s.id, s)
    return m
  }, [sports])

  const favSet = useMemo(() => new Set(favIds), [favIds])
  const savedTurfs = useMemo(() => allTurfs.filter((t) => favSet.has(t.id)), [allTurfs, favSet])

  return (
    <div className="p-4 space-y-4 safe-top">
      <div>
        <h1 className="text-xl font-bold">Saved Turfs</h1>
        <p className="text-xs text-muted">Quick access to your regular pitches across Delhi NCR</p>
      </div>

      {favsLoading || turfsLoading ? (
        <div className="space-y-4">
          {[1, 2].map((n) => (
            <div key={n} className="card h-60 animate-pulse bg-surface-2" />
          ))}
        </div>
      ) : savedTurfs.length === 0 ? (
        <div className="card p-8 text-center space-y-3">
          <Heart className="w-8 h-8 text-neon mx-auto" />
          <h3 className="text-base font-bold">No saved turfs yet</h3>
          <p className="text-xs text-muted max-w-xs mx-auto">
            Tap the heart icon on any turf listing to save it here for 1-tap booking.
          </p>
          <Link to="/" className="btn-primary text-xs h-9">
            Explore turfs
          </Link>
        </div>
      ) : (
        <div className="space-y-4">
          {savedTurfs.map((turf) => (
            <TurfCard
              key={turf.id}
              turf={turf}
              sportsMap={sportsMap}
              isFavourite={true}
              onToggleFavourite={() => toggleFav.mutate({ turfId: turf.id, isFav: true })}
            />
          ))}
        </div>
      )}
    </div>
  )
}
