import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import { AREAS, DEFAULT_AREA, type Area } from './areas'

export interface UserLocation {
  lat: number
  lng: number
  label: string
  source: 'gps' | 'area'
}

type Status = 'idle' | 'locating' | 'denied' | 'ready'

interface LocationCtx {
  location: UserLocation
  status: Status
  requestGps: () => void
  setArea: (area: Area) => void
}

const STORAGE_KEY = 'turffet.location'
const Ctx = createContext<LocationCtx | null>(null)

function nearestAreaLabel(lat: number, lng: number) {
  let best = AREAS[0]!
  let bestD = Infinity
  for (const a of AREAS) {
    const d = (a.lat - lat) ** 2 + (a.lng - lng) ** 2
    if (d < bestD) {
      bestD = d
      best = a
    }
  }
  return `Near ${best.label}`
}

export function LocationProvider({ children }: { children: ReactNode }) {
  const [location, setLocation] = useState<UserLocation>(() => {
    try {
      const raw = localStorage.getItem(STORAGE_KEY)
      if (raw) return JSON.parse(raw) as UserLocation
    } catch {
      /* ignore */
    }
    return { lat: DEFAULT_AREA.lat, lng: DEFAULT_AREA.lng, label: DEFAULT_AREA.label, source: 'area' }
  })
  const [status, setStatus] = useState<Status>('idle')

  const persist = (l: UserLocation) => {
    setLocation(l)
    localStorage.setItem(STORAGE_KEY, JSON.stringify(l))
  }

  const requestGps = useCallback(() => {
    if (!('geolocation' in navigator)) {
      setStatus('denied')
      return
    }
    setStatus('locating')
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        const { latitude, longitude } = pos.coords
        persist({ lat: latitude, lng: longitude, label: nearestAreaLabel(latitude, longitude), source: 'gps' })
        setStatus('ready')
      },
      () => setStatus('denied'),
      { enableHighAccuracy: false, timeout: 10000, maximumAge: 5 * 60 * 1000 },
    )
  }, [])

  const setArea = useCallback((area: Area) => {
    persist({ lat: area.lat, lng: area.lng, label: area.label, source: 'area' })
    setStatus('ready')
  }, [])

  // First visit: if GPS permission was already granted, refresh silently.
  useEffect(() => {
    const first = !localStorage.getItem(STORAGE_KEY)
    navigator.permissions
      ?.query({ name: 'geolocation' as PermissionName })
      .then((p) => {
        if (p.state === 'granted' || (first && p.state === 'prompt')) requestGps()
      })
      .catch(() => {
        if (first) requestGps()
      })
  }, [requestGps])

  const value = useMemo(() => ({ location, status, requestGps, setArea }), [location, status, requestGps, setArea])
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useUserLocation() {
  const ctx = useContext(Ctx)
  if (!ctx) throw new Error('useUserLocation must be used inside LocationProvider')
  return ctx
}
