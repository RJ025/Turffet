import { Zap } from 'lucide-react'
import { BottomSheet } from './BottomSheet'
import { AmenityIcon } from './AmenityIcon'
import { useAmenities } from '@/lib/api'
import { formatINR } from '@/lib/format'

export interface FilterState {
  maxPrice: number | null
  offpeakOnly: boolean
  amenities: string[]
  radiusKm: number
}

const PRICE_STEPS = [null, 800, 1200, 1600, 2200] as const
const RADIUS_STEPS = [10, 25, 40, 60] as const

interface Props {
  open: boolean
  onClose: () => void
  value: FilterState
  onChange: (next: FilterState) => void
  onReset: () => void
}

export function FilterSheet({ open, onClose, value, onChange, onReset }: Props) {
  const { data: amenities = [] } = useAmenities()

  const toggleAmenity = (id: string) => {
    const exists = value.amenities.includes(id)
    onChange({
      ...value,
      amenities: exists ? value.amenities.filter((a) => a !== id) : [...value.amenities, id],
    })
  }

  return (
    <BottomSheet open={open} onClose={onClose} title="Filters">
      {/* Off-peak happy hour toggle */}
      <button
        type="button"
        onClick={() => onChange({ ...value, offpeakOnly: !value.offpeakOnly })}
        className={`w-full flex items-center justify-between gap-3 rounded-xl border p-3.5 text-left transition ${
          value.offpeakOnly ? 'border-neon bg-neon/10' : 'border-line bg-surface-2'
        }`}
      >
        <div className="flex items-center gap-3">
          <div className="w-9 h-9 rounded-xl bg-neon/15 text-neon flex items-center justify-center shrink-0">
            <Zap className="w-4 h-4" />
          </div>
          <div>
            <div className="text-sm font-semibold text-text">Happy Hour / Off-peak deals only</div>
            <div className="text-xs text-muted">Up to 40% off during quieter morning & afternoon hours</div>
          </div>
        </div>
        <div
          className={`w-5 h-5 rounded-md border flex items-center justify-center ${
            value.offpeakOnly ? 'bg-neon border-neon text-ink font-bold' : 'border-line'
          }`}
        >
          {value.offpeakOnly ? '✓' : ''}
        </div>
      </button>

      {/* Max price */}
      <div className="space-y-2">
        <div className="label">Max price per slot</div>
        <div className="flex flex-wrap gap-2">
          {PRICE_STEPS.map((p) => {
            const active = value.maxPrice === p
            return (
              <button
                key={String(p)}
                type="button"
                onClick={() => onChange({ ...value, maxPrice: p })}
                className={active ? 'chip-active' : 'chip'}
              >
                {p == null ? 'Any price' : `Under ${formatINR(p)}`}
              </button>
            )
          })}
        </div>
      </div>

      {/* Distance radius */}
      <div className="space-y-2">
        <div className="label">Search radius</div>
        <div className="flex flex-wrap gap-2">
          {RADIUS_STEPS.map((km) => {
            const active = value.radiusKm === km
            return (
              <button
                key={km}
                type="button"
                onClick={() => onChange({ ...value, radiusKm: km })}
                className={active ? 'chip-active' : 'chip'}
              >
                {km === 60 ? 'All NCR (60 km)' : `Within ${km} km`}
              </button>
            )
          })}
        </div>
      </div>

      {/* Amenities */}
      <div className="space-y-2">
        <div className="label">Must-have amenities</div>
        <div className="grid grid-cols-2 gap-2">
          {amenities.map((a) => {
            const active = value.amenities.includes(a.id)
            return (
              <button
                key={a.id}
                type="button"
                onClick={() => toggleAmenity(a.id)}
                className={`flex items-center gap-2 rounded-xl border px-3 py-2.5 text-left text-xs font-medium transition ${
                  active
                    ? 'border-neon bg-neon/10 text-neon'
                    : 'border-line bg-surface-2 text-text hover:bg-surface-3'
                }`}
              >
                <AmenityIcon icon={a.icon} className="w-4 h-4 shrink-0" />
                <span className="truncate">{a.name}</span>
              </button>
            )
          })}
        </div>
      </div>

      <div className="flex items-center gap-3 pt-2">
        <button type="button" onClick={onReset} className="btn-secondary flex-1">
          Reset
        </button>
        <button type="button" onClick={onClose} className="btn-primary flex-1">
          Apply filters
        </button>
      </div>
    </BottomSheet>
  )
}
