import { Navigation, MapPin, Check } from 'lucide-react'
import { BottomSheet } from './BottomSheet'
import { AREAS, type Area } from '@/lib/areas'
import { useUserLocation } from '@/lib/location'

const REGIONS: Area['region'][] = ['Delhi', 'Gurugram', 'Noida', 'Ghaziabad', 'Faridabad']

export function AreaPickerSheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { location, status, requestGps, setArea } = useUserLocation()

  return (
    <BottomSheet open={open} onClose={onClose} title="Choose your location">
      <button
        type="button"
        onClick={() => {
          requestGps()
          onClose()
        }}
        className="w-full flex items-center gap-3 rounded-xl border border-neon/40 bg-neon/10 px-4 py-3 text-left transition hover:bg-neon/15"
      >
        <div className="w-9 h-9 rounded-full bg-neon text-ink flex items-center justify-center shrink-0">
          <Navigation className="w-4 h-4" />
        </div>
        <div className="flex-1">
          <div className="text-sm font-semibold text-neon">
            {status === 'locating' ? 'Finding your location…' : 'Use current GPS location'}
          </div>
          <div className="text-xs text-muted">Sort turfs by exact distance from you</div>
        </div>
      </button>

      {REGIONS.map((region) => (
        <div key={region} className="space-y-2">
          <div className="label">{region}</div>
          <div className="grid grid-cols-2 gap-2">
            {AREAS.filter((a) => a.region === region).map((area) => {
              const active = location.label === area.label
              return (
                <button
                  key={area.id}
                  type="button"
                  onClick={() => {
                    setArea(area)
                    onClose()
                  }}
                  className={`flex items-center justify-between gap-2 rounded-xl border px-3 py-2.5 text-left text-sm transition ${
                    active
                      ? 'border-neon bg-neon/10 text-neon font-semibold'
                      : 'border-line bg-surface-2 text-text hover:bg-surface-3'
                  }`}
                >
                  <span className="flex items-center gap-2 truncate">
                    <MapPin className="w-3.5 h-3.5 shrink-0 text-muted" />
                    <span className="truncate">{area.label}</span>
                  </span>
                  {active && <Check className="w-4 h-4 shrink-0" />}
                </button>
              )
            })}
          </div>
        </div>
      ))}
    </BottomSheet>
  )
}
