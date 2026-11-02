import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import {
  MapPin,
  ChevronDown,
  Bell,
  Search,
  SlidersHorizontal,
  Map as MapIcon,
  List,
  Zap,
  X,
  Building2,
} from 'lucide-react'
import { useRoleGate } from '@/components/RoleGateway'
import {
  useFavourites,
  useNearbyTurfs,
  useNotifications,
  useSports,
  useToggleFavourite,
} from '@/lib/api'
import { useUserLocation } from '@/lib/location'
import { TurfCard } from '@/components/TurfCard'
import { TurfMap } from '@/components/TurfMap'
import { AreaPickerSheet } from '@/components/AreaPickerSheet'
import { FilterSheet, type FilterState } from '@/components/FilterSheet'
import type { Sport } from '@/lib/types'

const DEFAULT_FILTERS: FilterState = {
  maxPrice: null,
  offpeakOnly: false,
  amenities: [],
  radiusKm: 60,
}

export function ExplorePage() {
  const { location } = useUserLocation()
  const { chooseRole } = useRoleGate()
  const { data: sports = [] } = useSports()
  const { data: favIds = [] } = useFavourites()
  const toggleFav = useToggleFavourite()
  const { data: notifications = [] } = useNotifications()

  const [sport, setSport] = useState<string | null>(null)
  const [search, setSearch] = useState('')
  const [view, setView] = useState<'list' | 'map'>('list')
  const [areaOpen, setAreaOpen] = useState(false)
  const [filterOpen, setFilterOpen] = useState(false)
  const [filters, setFilters] = useState<FilterState>(DEFAULT_FILTERS)

  const sportsMap = useMemo(() => {
    const m = new Map<string, Sport>()
    for (const s of sports) m.set(s.id, s)
    return m
  }, [sports])

  const favSet = useMemo(() => new Set(favIds), [favIds])
  const unreadCount = useMemo(() => notifications.filter((n) => !n.read_at).length, [notifications])

  const activeFilterCount =
    (filters.maxPrice != null ? 1 : 0) +
    (filters.offpeakOnly ? 1 : 0) +
    filters.amenities.length +
    (filters.radiusKm !== 60 ? 1 : 0)

  const { data: turfs = [], isLoading } = useNearbyTurfs({
    lat: location.lat,
    lng: location.lng,
    radiusKm: filters.radiusKm,
    sport,
    maxPrice: filters.maxPrice,
    search,
    amenities: filters.amenities,
    offpeakOnly: filters.offpeakOnly,
  })

  return (
    <div className="space-y-4">
      {/* Sticky header */}
      <header className="sticky top-0 z-30 bg-ink/90 backdrop-blur-md border-b border-line px-4 pt-3 pb-3 space-y-3 safe-top">
        <div className="flex items-center justify-between gap-3">
          <button
            type="button"
            onClick={() => setAreaOpen(true)}
            className="flex items-center gap-2 text-left group min-w-0"
          >
            <div className="w-9 h-9 rounded-xl bg-neon/15 border border-neon/30 text-neon flex items-center justify-center shrink-0">
              <MapPin className="w-4 h-4" />
            </div>
            <div className="min-w-0">
              <div className="text-[11px] uppercase tracking-wider text-muted font-semibold flex items-center gap-1">
                <span>Delhi NCR</span>
                <ChevronDown className="w-3.5 h-3.5 text-neon" />
              </div>
              <div className="text-sm font-bold text-text truncate group-hover:text-neon transition">
                {location.label}
              </div>
            </div>
          </button>

          <div className="flex items-center gap-2 shrink-0">
            <button
              type="button"
              onClick={() => chooseRole('owner', '/owner')}
              className="h-9 px-3 rounded-xl bg-neon/10 border border-neon/40 text-neon hover:bg-neon hover:text-ink text-xs font-bold inline-flex items-center gap-1.5 transition"
              title="Switch to Turf Owner Portal"
            >
              <Building2 className="w-3.5 h-3.5" />
              <span>Turf Owner</span>
            </button>
            <button
              type="button"
              onClick={() => setView((v) => (v === 'list' ? 'map' : 'list'))}
              className="btn-secondary h-9 px-3 text-xs rounded-xl"
            >
              {view === 'list' ? (
                <>
                  <MapIcon className="w-3.5 h-3.5 text-neon" />
                  <span>Map</span>
                </>
              ) : (
                <>
                  <List className="w-3.5 h-3.5 text-neon" />
                  <span>List</span>
                </>
              )}
            </button>
            <Link
              to="/notifications"
              aria-label="Notifications"
              className="relative w-9 h-9 rounded-xl bg-surface-2 border border-line flex items-center justify-center text-text hover:border-neon/50"
            >
              <Bell className="w-4 h-4" />
              {unreadCount > 0 && (
                <span className="absolute -top-1 -right-1 min-w-4 h-4 rounded-full bg-neon text-ink text-[10px] font-bold flex items-center justify-center px-1">
                  {unreadCount}
                </span>
              )}
            </Link>
          </div>
        </div>

        {/* Search + Filter button */}
        <div className="flex items-center gap-2">
          <div className="relative flex-1">
            <Search className="w-4 h-4 text-muted absolute left-3.5 top-1/2 -translate-y-1/2 pointer-events-none" />
            <input
              type="search"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search turf name or area (e.g. Hauz Khas, Cyber City)…"
              className="input h-10 pl-10 pr-8 text-sm"
            />
            {search && (
              <button
                type="button"
                onClick={() => setSearch('')}
                className="absolute right-2.5 top-1/2 -translate-y-1/2 text-muted hover:text-text"
              >
                <X className="w-4 h-4" />
              </button>
            )}
          </div>
          <button
            type="button"
            onClick={() => setFilterOpen(true)}
            className={`relative h-10 px-3 rounded-xl border flex items-center gap-1.5 text-xs font-semibold transition ${
              activeFilterCount > 0
                ? 'border-neon bg-neon/10 text-neon'
                : 'border-line bg-surface-2 text-text hover:bg-surface-3'
            }`}
          >
            <SlidersHorizontal className="w-3.5 h-3.5" />
            <span>Filters</span>
            {activeFilterCount > 0 && (
              <span className="w-4 h-4 rounded-full bg-neon text-ink text-[10px] font-bold flex items-center justify-center">
                {activeFilterCount}
              </span>
            )}
          </button>
        </div>

        {/* Sport + Happy Hour chips */}
        <div className="flex items-center gap-2 overflow-x-auto no-scrollbar -mx-4 px-4">
          <button
            type="button"
            onClick={() => setSport(null)}
            className={sport === null ? 'chip-active h-8 text-xs' : 'chip h-8 text-xs'}
          >
            All sports
          </button>
          <button
            type="button"
            onClick={() => setFilters((f) => ({ ...f, offpeakOnly: !f.offpeakOnly }))}
            className={filters.offpeakOnly ? 'chip-active h-8 text-xs' : 'chip h-8 text-xs'}
          >
            <Zap className="w-3.5 h-3.5 text-neon" />
            <span>Happy Hour</span>
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
      </header>

      {/* Main content */}
      <div className="px-4 space-y-4">
        <div className="flex items-center justify-between text-xs text-muted">
          <span>
            {isLoading
              ? 'Finding turfs near you…'
              : `${turfs.length} ${turfs.length === 1 ? 'turf' : 'turfs'} available`}
          </span>
          {(sport || search || activeFilterCount > 0) && (
            <button
              type="button"
              onClick={() => {
                setSport(null)
                setSearch('')
                setFilters(DEFAULT_FILTERS)
              }}
              className="text-neon font-semibold hover:underline"
            >
              Reset all
            </button>
          )}
        </div>

        {view === 'map' ? (
          <TurfMap turfs={turfs} userLocation={location} sportsMap={sportsMap} />
        ) : isLoading ? (
          <div className="space-y-4">
            {[1, 2, 3].map((n) => (
              <div key={n} className="card h-64 animate-pulse bg-surface-2" />
            ))}
          </div>
        ) : turfs.length === 0 ? (
          sport || search || activeFilterCount > 0 ? (
            <div className="card p-8 text-center space-y-3">
              <div className="text-3xl">🏟️</div>
              <h3 className="text-base font-bold">No turfs match your filters</h3>
              <p className="text-xs text-muted max-w-xs mx-auto">
                Try expanding your search radius or clearing your sport and price filters.
              </p>
              <button
                type="button"
                onClick={() => {
                  setSport(null)
                  setSearch('')
                  setFilters(DEFAULT_FILTERS)
                }}
                className="btn-secondary text-xs h-9"
              >
                Clear filters
              </button>
            </div>
          ) : (
            <div className="card p-8 text-center space-y-4">
              <div className="w-14 h-14 rounded-2xl bg-neon/15 border border-neon/30 text-neon flex items-center justify-center mx-auto">
                <Building2 className="w-7 h-7" />
              </div>
              <div className="space-y-1.5 max-w-sm mx-auto">
                <h3 className="text-base font-bold text-text">No turfs registered yet</h3>
                <p className="text-xs text-muted leading-relaxed">
                  Only turfs registered and published by turf owners appear here. Are you a turf owner? Register your
                  venue on the Owner Portal to make it live for players!
                </p>
              </div>
              <button
                type="button"
                onClick={() => chooseRole('owner', '/owner/turfs/new')}
                className="btn-primary text-xs h-10 px-5 shadow-glow"
              >
                <Building2 className="w-3.5 h-3.5" />
                <span>Register a Turf on Owner Portal</span>
              </button>
            </div>
          )
        ) : (
          <div className="space-y-4">
            {turfs.map((turf) => (
              <TurfCard
                key={turf.id}
                turf={turf}
                sportsMap={sportsMap}
                isFavourite={favSet.has(turf.id)}
                onToggleFavourite={() =>
                  toggleFav.mutate({ turfId: turf.id, isFav: favSet.has(turf.id) })
                }
              />
            ))}
          </div>
        )}
      </div>

      <AreaPickerSheet open={areaOpen} onClose={() => setAreaOpen(false)} />
      <FilterSheet
        open={filterOpen}
        onClose={() => setFilterOpen(false)}
        value={filters}
        onChange={setFilters}
        onReset={() => setFilters(DEFAULT_FILTERS)}
      />
    </div>
  )
}
