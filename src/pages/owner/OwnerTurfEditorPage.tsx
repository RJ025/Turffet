import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { APIProvider, Map as GoogleMap, AdvancedMarker } from '@vis.gl/react-google-maps'
import {
  ArrowLeft,
  Building2,
  MapPin,
  Image as ImageIcon,
  Upload,
  Plus,
  Trash2,
  Clock,
  Users,
  Zap,
  ShieldCheck,
  Check,
  Sparkles,
  Copy,
  LocateFixed,
} from 'lucide-react'
import { useAuth } from '@/lib/auth'
import { useAmenities, useSports } from '@/lib/api'
import { uploadTurfPhoto, useOwnerSaveTurf, useOwnerTurfDetail } from '@/lib/ownerApi'
import { AREAS } from '@/lib/areas'
import { formatINR } from '@/lib/format'
import { AmenityIcon } from '@/components/AmenityIcon'
import { useToast } from '@/components/Toast'
import { errorMessage } from '@/lib/errors'
import type { OwnerTurfPayload } from '@/lib/types'

const API_KEY = (import.meta.env.VITE_GOOGLE_MAPS_API_KEY as string) || ''
const MAP_ID = (import.meta.env.VITE_GOOGLE_MAP_ID as string) || 'DEMO_MAP_ID'

const PRESET_PHOTOS = [
  { label: 'Football Floodlit Night', url: '/images/turfs/football-night.jpg' },
  { label: 'Football Day Pitch', url: '/images/turfs/football-day.jpg' },
  { label: 'Box Cricket Arena', url: '/images/turfs/box-cricket.jpg' },
  { label: 'Cricket Day Net', url: '/images/turfs/cricket-day.jpg' },
  { label: 'Badminton Indoor Court', url: '/images/turfs/badminton.jpg' },
  { label: 'Pickleball Hard Court', url: '/images/turfs/pickleball.jpg' },
  { label: 'Tennis Court', url: '/images/turfs/tennis.jpg' },
  { label: 'Basketball Court', url: '/images/turfs/basketball.jpg' },
  { label: 'Multi-sport Rooftop', url: '/images/turfs/multisport-rooftop.jpg' },
  { label: 'Turf Close-up', url: '/images/turfs/football-closeup.jpg' },
]

const DAYS = [
  { dow: 0, short: 'Sun', full: 'Sunday' },
  { dow: 1, short: 'Mon', full: 'Monday' },
  { dow: 2, short: 'Tue', full: 'Tuesday' },
  { dow: 3, short: 'Wed', full: 'Wednesday' },
  { dow: 4, short: 'Thu', full: 'Thursday' },
  { dow: 5, short: 'Fri', full: 'Friday' },
  { dow: 6, short: 'Sat', full: 'Saturday' },
]

const TIME_OPTIONS = Array.from({ length: 19 }, (_, idx) => {
  const hour = idx + 5 // 05:00 to 23:00
  const val = `${String(hour).padStart(2, '0')}:00`
  const h12 = hour % 12 || 12
  const ampm = hour < 12 ? 'AM' : 'PM'
  return { value: val, label: `${h12}:00 ${ampm}` }
})

const DEFAULT_SPORT_MAX_PLAYERS: Record<string, number> = {
  football: 12,
  cricket: 16,
  badminton: 4,
  pickleball: 4,
  tennis: 4,
  basketball: 10,
  volleyball: 12,
}

const PRESET_RULES = [
  'Non-marking shoes or turf studs only (metal studs strictly not allowed)',
  'Arrive 10 minutes before your slot and show your Turffet QR pass at reception',
  'Free cancellation up to 2 hours before slot start time',
  'Please respect the slot end time so the next group can start on schedule',
]

interface DayHoursState {
  day_of_week: number
  enabled: boolean
  open_time: string
  close_time: string
}

interface CourtDraft {
  id?: string | null
  key: string
  name: string
  size_label: string
  surface: string
  base_price: number
  max_players: number
  sports: { sport_id: string; max_players: number }[]
}

interface PricingRuleDraft {
  key: string
  court_key: string // '' = all courts
  days_of_week: number[]
  start_time: string
  end_time: string
  mode: 'discount' | 'fixed'
  discount_pct: number
  price: number
  label: string
  is_offpeak: boolean
}

export function OwnerTurfEditorPage() {
  const { id: editTurfId } = useParams<{ id: string }>()
  const isEditing = Boolean(editTurfId)
  const navigate = useNavigate()
  const { user, profile } = useAuth()
  const { data: sports = [] } = useSports()
  const { data: amenitiesList = [] } = useAmenities()
  const { data: existingTurf, isLoading: loadingExisting } = useOwnerTurfDetail(editTurfId)
  const saveTurf = useOwnerSaveTurf()
  const { toast } = useToast()

  // Basic info state
  const [name, setName] = useState('')
  const [area, setArea] = useState('Hauz Khas')
  const [address, setAddress] = useState('')
  const [description, setDescription] = useState('')
  const [phone, setPhone] = useState(profile?.business_phone || user?.phone || '')
  const [whatsapp, setWhatsapp] = useState(profile?.business_phone || user?.phone || '')
  const [slotMinutes, setSlotMinutes] = useState<number>(60)
  const [lat, setLat] = useState<number>(28.5494)
  const [lng, setLng] = useState<number>(77.2001)
  const [isActive, setIsActive] = useState<boolean>(true)

  // Photos state
  const [photos, setPhotos] = useState<string[]>([
    '/images/turfs/football-night.jpg',
    '/images/turfs/box-cricket.jpg',
  ])
  const [photoUrlInput, setPhotoUrlInput] = useState('')
  const [uploadingPhoto, setUploadingPhoto] = useState(false)

  // Operating hours state (0 = Sun ... 6 = Sat)
  const [hours, setHours] = useState<DayHoursState[]>(() =>
    DAYS.map((d) => ({
      day_of_week: d.dow,
      enabled: true,
      open_time: '06:00',
      close_time: '23:00',
    })),
  )

  // Courts & sports + max players per sport
  const [courts, setCourts] = useState<CourtDraft[]>([
    {
      key: 'court-1',
      name: 'Pitch 1 — Floodlit',
      size_label: '6-a-side (100×60 ft)',
      surface: 'FIFA 50mm Artificial Grass',
      base_price: 1500,
      max_players: 16,
      sports: [
        { sport_id: 'football', max_players: 12 },
        { sport_id: 'cricket', max_players: 16 },
      ],
    },
  ])

  // Happy Hour / Pricing rules state
  const [pricingRules, setPricingRules] = useState<PricingRuleDraft[]>([
    {
      key: 'rule-1',
      court_key: '',
      days_of_week: [1, 2, 3, 4, 5],
      start_time: '06:00',
      end_time: '16:00',
      mode: 'discount',
      discount_pct: 30,
      price: 1050,
      label: 'Happy Hour',
      is_offpeak: true,
    },
  ])

  // Amenities & Rules
  const [selectedAmenities, setSelectedAmenities] = useState<string[]>([
    'floodlights',
    'parking',
    'drinking_water',
    'washroom',
    'changing_room',
    'equipment_rental',
    'seating',
    'first_aid',
  ])
  const [rules, setRules] = useState<string[]>([
    'Non-marking shoes or turf studs only (metal studs strictly not allowed)',
    'Arrive 10 minutes before your slot and show your Turffet QR pass at reception',
  ])
  const [newRuleText, setNewRuleText] = useState('')
  const [formError, setFormError] = useState<string | null>(null)
  const [hydratedId, setHydratedId] = useState<string | null>(null)

  // Hydrate state when editing an existing turf
  useEffect(() => {
    if (!existingTurf || hydratedId === existingTurf.id) return
    setHydratedId(existingTurf.id)
    setName(existingTurf.name)
    setArea(existingTurf.area)
    setAddress(existingTurf.address)
    setDescription(existingTurf.description ?? '')
    setPhone(existingTurf.phone ?? '')
    setWhatsapp(existingTurf.whatsapp ?? '')
    setSlotMinutes(existingTurf.slot_minutes || 60)
    setLat(existingTurf.lat)
    setLng(existingTurf.lng)
    setIsActive(existingTurf.is_active ?? true)

    const loadedPhotos = existingTurf.turf_photos.length
      ? existingTurf.turf_photos.map((p) => p.url)
      : existingTurf.cover_image
        ? [existingTurf.cover_image]
        : []
    if (loadedPhotos.length) setPhotos(loadedPhotos)

    const ohMap = new Map(existingTurf.operating_hours.map((oh) => [oh.day_of_week, oh]))
    setHours(
      DAYS.map((d) => {
        const found = ohMap.get(d.dow)
        return {
          day_of_week: d.dow,
          enabled: Boolean(found),
          open_time: found ? found.open_time.slice(0, 5) : '06:00',
          close_time: found ? found.close_time.slice(0, 5) : '23:00',
        }
      }),
    )

    if (existingTurf.courts.length) {
      setCourts(
        existingTurf.courts.map((c, idx) => ({
          id: c.id,
          key: c.id || `court-${idx + 1}`,
          name: c.name,
          size_label: c.size_label ?? '',
          surface: c.surface ?? '',
          base_price: c.base_price,
          max_players: c.max_players,
          sports: c.court_sports.map((cs) => ({
            sport_id: cs.sport_id,
            max_players: cs.max_players ?? c.max_players,
          })),
        })),
      )
    }

    const loadedRules: PricingRuleDraft[] = existingTurf.pricing_rules.map((r, idx) => ({
      key: r.id || `rule-${idx + 1}`,
      court_key: r.court_id ?? '',
      days_of_week: r.days_of_week,
      start_time: r.start_time.slice(0, 5),
      end_time: r.end_time.slice(0, 5),
      mode: r.discount_pct != null ? 'discount' : 'fixed',
      discount_pct: r.discount_pct ?? 25,
      price: r.price ?? 1000,
      label: r.label ?? (r.is_offpeak ? 'Happy Hour' : 'Peak'),
      is_offpeak: r.is_offpeak,
    }))
    setPricingRules(loadedRules)

    setSelectedAmenities(existingTurf.turf_amenities.map((a) => a.amenity_id))
    setRules(existingTurf.rules ?? [])
  }, [existingTurf, hydratedId])

  const handleSelectAreaPreset = (areaLabel: string) => {
    setArea(areaLabel)
    const found = AREAS.find((a) => a.label === areaLabel)
    if (found) {
      setLat(found.lat)
      setLng(found.lng)
    }
  }

  const handleUseCurrentGps = () => {
    if (!('geolocation' in navigator)) {
      toast('GPS not available in this browser', 'error')
      return
    }
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setLat(Number(pos.coords.latitude.toFixed(6)))
        setLng(Number(pos.coords.longitude.toFixed(6)))
        toast('Pinned to your current GPS coordinates!', 'success')
      },
      () => {
        toast('Could not access GPS. Tap on the map or pick an area instead.', 'info')
      },
    )
  }

  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files ?? [])
    if (!files.length || !user) return
    setUploadingPhoto(true)
    try {
      const uploadedUrls: string[] = []
      for (const file of files) {
        const url = await uploadTurfPhoto(user.id, file)
        uploadedUrls.push(url)
      }
      setPhotos((prev) => [...prev, ...uploadedUrls])
      toast(`Uploaded ${uploadedUrls.length} photo${uploadedUrls.length > 1 ? 's' : ''}!`, 'success')
    } catch (err) {
      toast(errorMessage(err), 'error')
    } finally {
      setUploadingPhoto(false)
      e.target.value = ''
    }
  }

  const handleAddPhotoUrl = () => {
    const url = photoUrlInput.trim()
    if (!url) return
    if (!photos.includes(url)) {
      setPhotos((prev) => [...prev, url])
    }
    setPhotoUrlInput('')
  }

  const handleSetCoverPhoto = (idx: number) => {
    setPhotos((prev) => {
      const target = prev[idx]
      if (!target) return prev
      const rest = prev.filter((_, i) => i !== idx)
      return [target, ...rest]
    })
  }

  const handleCopyMondayToAll = () => {
    const mon = hours.find((h) => h.day_of_week === 1) ?? hours[0]!
    setHours((prev) =>
      prev.map((h) => ({
        ...h,
        enabled: mon.enabled,
        open_time: mon.open_time,
        close_time: mon.close_time,
      })),
    )
    toast('Copied Monday timings to all 7 days', 'info')
  }

  // Court helpers
  const addCourt = () => {
    const idx = courts.length + 1
    setCourts((prev) => [
      ...prev,
      {
        key: `court-${Date.now()}-${idx}`,
        name: `Court ${idx}`,
        size_label: '5-a-side (90×50 ft)',
        surface: 'FIFA Artificial Grass',
        base_price: 1200,
        max_players: 12,
        sports: [{ sport_id: 'football', max_players: 10 }],
      },
    ])
  }

  const updateCourt = (key: string, patch: Partial<CourtDraft>) => {
    setCourts((prev) => prev.map((c) => (c.key === key ? { ...c, ...patch } : c)))
  }

  const toggleCourtSport = (courtKey: string, sportId: string) => {
    setCourts((prev) =>
      prev.map((c) => {
        if (c.key !== courtKey) return c
        const exists = c.sports.some((s) => s.sport_id === sportId)
        let nextSports: { sport_id: string; max_players: number }[]
        if (exists) {
          if (c.sports.length <= 1) {
            toast('Each court must support at least 1 sport', 'info')
            return c
          }
          nextSports = c.sports.filter((s) => s.sport_id !== sportId)
        } else {
          const defaultMax = DEFAULT_SPORT_MAX_PLAYERS[sportId] ?? 10
          nextSports = [...c.sports, { sport_id: sportId, max_players: defaultMax }]
        }
        const highestSportPlayers = Math.max(...nextSports.map((s) => s.max_players), 2)
        return {
          ...c,
          sports: nextSports,
          max_players: Math.max(c.max_players, highestSportPlayers),
        }
      }),
    )
  }

  const updateCourtSportMaxPlayers = (courtKey: string, sportId: string, maxPlayers: number) => {
    const clamped = Math.max(2, Math.min(40, maxPlayers || 2))
    setCourts((prev) =>
      prev.map((c) => {
        if (c.key !== courtKey) return c
        const nextSports = c.sports.map((s) =>
          s.sport_id === sportId ? { ...s, max_players: clamped } : s,
        )
        const highestSportPlayers = Math.max(...nextSports.map((s) => s.max_players), 2)
        return {
          ...c,
          sports: nextSports,
          max_players: Math.max(c.max_players, highestSportPlayers),
        }
      }),
    )
  }

  // Pricing rule helpers
  const addPricingRuleTemplate = (template: 'happy_hour_pct' | 'morning_bird' | 'afternoon_fixed' | 'weekend_peak') => {
    const basePrice = courts[0]?.base_price ?? 1400
    const key = `rule-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`
    if (template === 'happy_hour_pct') {
      setPricingRules((prev) => [
        ...prev,
        {
          key,
          court_key: '',
          days_of_week: [1, 2, 3, 4, 5],
          start_time: '06:00',
          end_time: '16:00',
          mode: 'discount',
          discount_pct: 30,
          price: Math.round(basePrice * 0.7),
          label: 'Happy Hour',
          is_offpeak: true,
        },
      ])
    } else if (template === 'morning_bird') {
      setPricingRules((prev) => [
        ...prev,
        {
          key,
          court_key: '',
          days_of_week: [0, 1, 2, 3, 4, 5, 6],
          start_time: '06:00',
          end_time: '10:00',
          mode: 'discount',
          discount_pct: 35,
          price: Math.round(basePrice * 0.65),
          label: 'Early Bird Deal',
          is_offpeak: true,
        },
      ])
    } else if (template === 'afternoon_fixed') {
      setPricingRules((prev) => [
        ...prev,
        {
          key,
          court_key: '',
          days_of_week: [1, 2, 3, 4, 5],
          start_time: '11:00',
          end_time: '16:00',
          mode: 'fixed',
          discount_pct: 25,
          price: Math.max(400, basePrice - 500),
          label: 'Midday Saver',
          is_offpeak: true,
        },
      ])
    } else {
      setPricingRules((prev) => [
        ...prev,
        {
          key,
          court_key: '',
          days_of_week: [0, 5, 6],
          start_time: '18:00',
          end_time: '23:00',
          mode: 'fixed',
          discount_pct: 0,
          price: basePrice + 300,
          label: 'Weekend Prime',
          is_offpeak: false,
        },
      ])
    }
  }

  const updatePricingRule = (key: string, patch: Partial<PricingRuleDraft>) => {
    setPricingRules((prev) => prev.map((r) => (r.key === key ? { ...r, ...patch } : r)))
  }

  const toggleRuleDay = (key: string, dow: number) => {
    setPricingRules((prev) =>
      prev.map((r) => {
        if (r.key !== key) return r
        const exists = r.days_of_week.includes(dow)
        const nextDays = exists
          ? r.days_of_week.filter((d) => d !== dow)
          : [...r.days_of_week, dow].sort()
        return { ...r, days_of_week: nextDays.length ? nextDays : [dow] }
      }),
    )
  }

  const handleSave = async (publishActive: boolean) => {
    setFormError(null)
    if (!name.trim()) {
      const msg = 'Please enter your Turf / Venue Name in Section 1.'
      setFormError(msg)
      toast(msg, 'error')
      window.scrollTo({ top: 0, behavior: 'smooth' })
      return
    }
    if (!area.trim() || !address.trim()) {
      const msg = 'Please enter the Full Street Address & Landmark in Section 1.'
      setFormError(msg)
      toast(msg, 'error')
      window.scrollTo({ top: 0, behavior: 'smooth' })
      return
    }
    const openDays = hours.filter((h) => h.enabled)
    if (!openDays.length) {
      const msg = 'Please enable at least one open day in Section 3 (Operating Timings).'
      setFormError(msg)
      toast(msg, 'error')
      return
    }
    for (const h of openDays) {
      if (h.close_time <= h.open_time) {
        const dayName = DAYS.find((d) => d.dow === h.day_of_week)?.full ?? 'Day'
        const msg = `${dayName}: Closing time must be after opening time.`
        setFormError(msg)
        toast(msg, 'error')
        return
      }
    }
    if (!courts.length) {
      const msg = 'Please add at least one court or pitch in Section 4.'
      setFormError(msg)
      toast(msg, 'error')
      return
    }

    const payload: OwnerTurfPayload = {
      id: editTurfId ?? null,
      name: name.trim(),
      description: description.trim() || null,
      area: area.trim(),
      city: 'Delhi NCR',
      address: address.trim(),
      lat,
      lng,
      phone: phone.trim() || null,
      whatsapp: whatsapp.trim() || phone.trim() || null,
      cover_image: photos[0] ?? null,
      slot_minutes: slotMinutes,
      is_active: publishActive,
      rules,
      photos,
      amenities: selectedAmenities,
      operating_hours: openDays.map((h) => ({
        day_of_week: h.day_of_week,
        open_time: h.open_time,
        close_time: h.close_time,
      })),
      courts: courts.map((c) => ({
        id: c.id ?? null,
        key: c.key,
        name: c.name.trim() || 'Court 1',
        size_label: c.size_label.trim(),
        surface: c.surface.trim(),
        base_price: Math.max(100, Number(c.base_price) || 1000),
        max_players: Math.max(
          2,
          Number(c.max_players) || 10,
          ...c.sports.map((s) => Number(s.max_players) || 2),
        ),
        sports: c.sports.map((s) => ({
          sport_id: s.sport_id,
          max_players: Math.max(2, Number(s.max_players) || 10),
        })),
      })),
      pricing_rules: pricingRules.map((r) => ({
        court_key: r.court_key || null,
        days_of_week: r.days_of_week,
        start_time: r.start_time,
        end_time: r.end_time,
        price: r.mode === 'fixed' ? Math.max(100, Number(r.price) || 800) : null,
        discount_pct:
          r.mode === 'discount' ? Math.max(1, Math.min(90, Number(r.discount_pct) || 20)) : null,
        label: r.label.trim() || (r.is_offpeak ? 'Happy Hour' : 'Peak'),
        is_offpeak: r.is_offpeak,
      })),
    }

    try {
      const saved = await saveTurf.mutateAsync(payload)
      toast(
        publishActive
          ? `"${saved.name}" is now LIVE on Turffet!`
          : `Saved "${saved.name}" as draft`,
        'success',
      )
      navigate('/owner')
    } catch (err) {
      const msg = errorMessage(err)
      setFormError(msg)
      toast(msg, 'error')
    }
  }

  if (isEditing && loadingExisting) {
    return (
      <div className="p-4 space-y-4">
        <div className="card h-40 animate-pulse bg-surface-2" />
        <div className="card h-64 animate-pulse bg-surface-2" />
      </div>
    )
  }

  return (
    <div className="p-4 space-y-6 pb-20">
      {/* Header */}
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={() => navigate('/owner')}
            className="w-9 h-9 rounded-xl bg-surface-2 border border-line flex items-center justify-center text-text hover:border-neon/50"
          >
            <ArrowLeft className="w-4 h-4" />
          </button>
          <div>
            <h1 className="text-lg sm:text-xl font-extrabold text-text">
              {isEditing ? `Edit Turf · ${name || 'Venue'}` : 'List Your Turf on Turffet'}
            </h1>
            <p className="text-xs text-muted">
              Set photos, timings, courts, sports & player limits, Happy Hour deals, and amenities
            </p>
          </div>
        </div>
      </div>

      {/* SECTION 1: Basic Info & Map Location */}
      <section className="card p-4 sm:p-5 space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-2.5 border-b border-line pb-3">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-xl bg-neon/15 text-neon flex items-center justify-center">
              <Building2 className="w-4 h-4" />
            </div>
            <div>
              <h2 className="text-sm font-bold text-text">1. Venue Details & Map Location</h2>
              <p className="text-[11px] text-muted">
                Players use this to discover your turf by distance, area, and search
              </p>
            </div>
          </div>

          {!isEditing && (
            <button
              type="button"
              onClick={() => {
                setName('Apex Floodlit Arena — Hauz Khas')
                setArea('Hauz Khas')
                setAddress('Plot 14, Near Hauz Khas Metro Gate 1, South Delhi 110016')
                setDescription(
                  'Premier FIFA-grade 50mm floodlit rooftop turf & box cricket arena with ample parking, player dugouts, and chilled drinking water.',
                )
                setPhone(phone || '+91 98111 22334')
                setWhatsapp(whatsapp || '+91 98111 22334')
                setLat(28.5494)
                setLng(77.2001)
                setFormError(null)
                toast('Filled sample venue details!', 'info')
              }}
              className="btn-secondary h-8 px-3 text-xs border-neon/40 text-neon"
            >
              <Sparkles className="w-3.5 h-3.5" />
              <span>Quick-Fill Sample Details</span>
            </button>
          )}
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3.5">
          <div className="sm:col-span-2 space-y-1.5">
            <label className="label">Turf / Venue Name *</label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. Apex Floodlit Arena — Hauz Khas"
              className="input h-11 text-sm"
            />
          </div>

          <div className="space-y-1.5">
            <label className="label">Delhi NCR Hub / Area *</label>
            <select
              value={AREAS.some((a) => a.label === area) ? area : '__custom__'}
              onChange={(e) => {
                if (e.target.value !== '__custom__') {
                  handleSelectAreaPreset(e.target.value)
                }
              }}
              className="input h-11 text-sm bg-surface-2"
            >
              {AREAS.map((a) => (
                <option key={a.id} value={a.label}>
                  {a.label} ({a.region})
                </option>
              ))}
              <option value="__custom__">Custom Area in Delhi NCR…</option>
            </select>
          </div>

          <div className="space-y-1.5">
            <label className="label">Area Label Shown on Card *</label>
            <input
              type="text"
              value={area}
              onChange={(e) => setArea(e.target.value)}
              placeholder="e.g. Hauz Khas / Sector 62 Noida"
              className="input h-11 text-sm"
            />
          </div>

          <div className="sm:col-span-2 space-y-1.5">
            <label className="label">Full Street Address & Landmark *</label>
            <input
              type="text"
              value={address}
              onChange={(e) => setAddress(e.target.value)}
              placeholder="e.g. Rooftop, Plot 14, Near Hauz Khas Metro Gate 1, South Delhi"
              className="input h-11 text-sm"
            />
          </div>

          <div className="sm:col-span-2 space-y-1.5">
            <label className="label">About Your Turf (Description)</label>
            <textarea
              rows={2}
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Highlight turf quality, floodlights, roof height, parking, and vibe…"
              className="input py-2.5 text-sm min-h-[72px]"
            />
          </div>

          <div className="space-y-1.5">
            <label className="label">Venue Contact Phone</label>
            <input
              type="tel"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              placeholder="+91 98111 22334"
              className="input h-10 text-sm"
            />
          </div>

          <div className="space-y-1.5">
            <label className="label">WhatsApp Number (for player queries)</label>
            <input
              type="tel"
              value={whatsapp}
              onChange={(e) => setWhatsapp(e.target.value)}
              placeholder="+91 98111 22334"
              className="input h-10 text-sm"
            />
          </div>

          <div className="space-y-1.5">
            <label className="label">Slot Duration</label>
            <div className="grid grid-cols-4 gap-2">
              {[30, 60, 90, 120].map((mins) => (
                <button
                  key={mins}
                  type="button"
                  onClick={() => setSlotMinutes(mins)}
                  className={
                    slotMinutes === mins
                      ? 'chip-active justify-center h-10 text-xs font-bold'
                      : 'chip justify-center h-10 text-xs'
                  }
                >
                  {mins} min
                </button>
              ))}
            </div>
          </div>
        </div>

        {/* Interactive Map Pin Picker */}
        <div className="space-y-2 pt-2">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <label className="label flex items-center gap-1.5">
              <MapPin className="w-3.5 h-3.5 text-neon" />
              <span>Pin Exact Turf Location on Map (Tap map to move pin)</span>
            </label>
            <button
              type="button"
              onClick={handleUseCurrentGps}
              className="btn-secondary h-8 px-2.5 text-xs"
            >
              <LocateFixed className="w-3.5 h-3.5 text-neon" />
              <span>Use My GPS</span>
            </button>
          </div>

          {API_KEY ? (
            <div className="h-56 w-full rounded-2xl overflow-hidden border border-line bg-surface-2">
              <APIProvider apiKey={API_KEY}>
                <GoogleMap
                  mapId={MAP_ID}
                  center={{ lat, lng }}
                  defaultZoom={14}
                  gestureHandling="greedy"
                  disableDefaultUI={true}
                  colorScheme="DARK"
                  onClick={(ev) => {
                    if (ev.detail.latLng) {
                      setLat(Number(ev.detail.latLng.lat.toFixed(6)))
                      setLng(Number(ev.detail.latLng.lng.toFixed(6)))
                    }
                  }}
                  className="w-full h-full"
                >
                  <AdvancedMarker position={{ lat, lng }}>
                    <div className="rounded-full bg-neon text-ink px-3 py-1 text-xs font-extrabold shadow-lg border-2 border-white">
                      🏟️ {name || 'Your Turf'}
                    </div>
                  </AdvancedMarker>
                </GoogleMap>
              </APIProvider>
            </div>
          ) : null}

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1">
              <span className="text-[11px] text-muted">Latitude</span>
              <input
                type="number"
                step="0.0001"
                value={lat}
                onChange={(e) => setLat(Number(e.target.value) || 28.6139)}
                className="input h-9 text-xs font-mono"
              />
            </div>
            <div className="space-y-1">
              <span className="text-[11px] text-muted">Longitude</span>
              <input
                type="number"
                step="0.0001"
                value={lng}
                onChange={(e) => setLng(Number(e.target.value) || 77.209)}
                className="input h-9 text-xs font-mono"
              />
            </div>
          </div>
        </div>
      </section>

      {/* SECTION 2: Photos */}
      <section className="card p-4 sm:p-5 space-y-4">
        <div className="flex items-center justify-between gap-2 border-b border-line pb-3">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-xl bg-neon/15 text-neon flex items-center justify-center">
              <ImageIcon className="w-4 h-4" />
            </div>
            <div>
              <h2 className="text-sm font-bold text-text">2. Turf Photos ({photos.length})</h2>
              <p className="text-[11px] text-muted">
                Upload photos from your phone/computer, paste a URL, or pick from preset sport photos
              </p>
            </div>
          </div>

          <label className="btn-primary h-9 px-3.5 text-xs cursor-pointer shrink-0">
            <Upload className="w-3.5 h-3.5" />
            <span>{uploadingPhoto ? 'Uploading…' : 'Upload Photos'}</span>
            <input
              type="file"
              accept="image/*"
              multiple
              onChange={handleFileUpload}
              disabled={uploadingPhoto}
              className="hidden"
            />
          </label>
        </div>

        {/* Selected Photos Gallery */}
        {photos.length > 0 ? (
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-2.5">
            {photos.map((url, idx) => (
              <div
                key={`${url}-${idx}`}
                className="relative group aspect-16/10 rounded-xl overflow-hidden border border-line bg-surface-2"
              >
                <img src={url} alt={`Turf ${idx + 1}`} className="w-full h-full object-cover" />
                {idx === 0 ? (
                  <span className="absolute top-2 left-2 rounded-md bg-neon text-ink px-2 py-0.5 text-[10px] font-extrabold uppercase">
                    Cover Photo
                  </span>
                ) : (
                  <button
                    type="button"
                    onClick={() => handleSetCoverPhoto(idx)}
                    className="absolute top-2 left-2 rounded-md bg-ink/80 backdrop-blur border border-white/15 px-2 py-0.5 text-[10px] font-semibold text-text hover:text-neon"
                  >
                    Make Cover
                  </button>
                )}
                <button
                  type="button"
                  onClick={() => setPhotos((prev) => prev.filter((_, i) => i !== idx))}
                  className="absolute top-2 right-2 w-6 h-6 rounded-full bg-ink/80 text-danger flex items-center justify-center hover:bg-danger hover:text-white transition"
                  title="Remove photo"
                >
                  <Trash2 className="w-3 h-3" />
                </button>
              </div>
            ))}
          </div>
        ) : (
          <div className="rounded-xl border border-dashed border-line p-4 text-center text-xs text-muted">
            No photos selected yet. Upload a photo or click any preset below.
          </div>
        )}

        {/* Paste image URL */}
        <div className="flex gap-2">
          <input
            type="url"
            value={photoUrlInput}
            onChange={(e) => setPhotoUrlInput(e.target.value)}
            placeholder="Or paste an image URL (https://...)"
            className="input h-9 text-xs flex-1"
          />
          <button type="button" onClick={handleAddPhotoUrl} className="btn-secondary h-9 px-3 text-xs">
            Add URL
          </button>
        </div>

        {/* Preset Sport Photos */}
        <div className="space-y-1.5">
          <div className="text-[11px] font-semibold text-muted">
            Quick-add high-resolution turf photos (tap to toggle):
          </div>
          <div className="flex items-center gap-2 overflow-x-auto no-scrollbar pb-1">
            {PRESET_PHOTOS.map((preset) => {
              const selected = photos.includes(preset.url)
              return (
                <button
                  key={preset.url}
                  type="button"
                  onClick={() =>
                    setPhotos((prev) =>
                      prev.includes(preset.url)
                        ? prev.filter((u) => u !== preset.url)
                        : [...prev, preset.url],
                    )
                  }
                  className={`relative shrink-0 w-28 aspect-16/10 rounded-xl overflow-hidden border transition ${
                    selected ? 'border-neon ring-2 ring-neon/40' : 'border-line opacity-75 hover:opacity-100'
                  }`}
                >
                  <img src={preset.url} alt={preset.label} className="w-full h-full object-cover" />
                  <div className="absolute inset-x-0 bottom-0 bg-ink/80 px-1.5 py-0.5 text-[9px] font-medium text-text truncate">
                    {preset.label}
                  </div>
                  {selected && (
                    <div className="absolute top-1 right-1 w-4 h-4 rounded-full bg-neon text-ink flex items-center justify-center">
                      <Check className="w-2.5 h-2.5 stroke-[3]" />
                    </div>
                  )}
                </button>
              )
            })}
          </div>
        </div>
      </section>

      {/* SECTION 3: Operating Hours (Timings) */}
      <section className="card p-4 sm:p-5 space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-line pb-3">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-xl bg-neon/15 text-neon flex items-center justify-center">
              <Clock className="w-4 h-4" />
            </div>
            <div>
              <h2 className="text-sm font-bold text-text">3. Operating Timings (Opening & Closing Hours)</h2>
              <p className="text-[11px] text-muted">
                Choose which days your turf is open and the exact hours slots can be booked
              </p>
            </div>
          </div>

          <button
            type="button"
            onClick={handleCopyMondayToAll}
            className="btn-secondary h-8 px-3 text-xs"
          >
            <Copy className="w-3.5 h-3.5 text-neon" />
            <span>Copy Monday to All Days</span>
          </button>
        </div>

        <div className="space-y-2">
          {hours.map((h) => {
            const dayMeta = DAYS.find((d) => d.dow === h.day_of_week)!
            return (
              <div
                key={h.day_of_week}
                className={`rounded-xl border px-3 py-2.5 flex flex-wrap items-center justify-between gap-2 ${
                  h.enabled ? 'border-line bg-surface-2' : 'border-line/50 bg-surface/40 opacity-60'
                }`}
              >
                <label className="flex items-center gap-2.5 cursor-pointer min-w-[120px]">
                  <input
                    type="checkbox"
                    checked={h.enabled}
                    onChange={(e) =>
                      setHours((prev) =>
                        prev.map((item) =>
                          item.day_of_week === h.day_of_week
                            ? { ...item, enabled: e.target.checked }
                            : item,
                        ),
                      )
                    }
                    className="w-4 h-4 accent-neon rounded"
                  />
                  <span className="text-xs font-bold text-text">{dayMeta.full}</span>
                </label>

                {h.enabled ? (
                  <div className="flex items-center gap-2 text-xs">
                    <span className="text-muted">Open</span>
                    <select
                      value={h.open_time}
                      onChange={(e) =>
                        setHours((prev) =>
                          prev.map((item) =>
                            item.day_of_week === h.day_of_week
                              ? { ...item, open_time: e.target.value }
                              : item,
                          ),
                        )
                      }
                      className="input h-8 px-2 text-xs bg-surface w-28"
                    >
                      {TIME_OPTIONS.map((t) => (
                        <option key={t.value} value={t.value}>
                          {t.label}
                        </option>
                      ))}
                    </select>
                    <span className="text-muted">to</span>
                    <select
                      value={h.close_time}
                      onChange={(e) =>
                        setHours((prev) =>
                          prev.map((item) =>
                            item.day_of_week === h.day_of_week
                              ? { ...item, close_time: e.target.value }
                              : item,
                          ),
                        )
                      }
                      className="input h-8 px-2 text-xs bg-surface w-28"
                    >
                      {TIME_OPTIONS.map((t) => (
                        <option key={t.value} value={t.value}>
                          {t.label}
                        </option>
                      ))}
                    </select>
                  </div>
                ) : (
                  <span className="text-xs text-muted font-medium">Closed</span>
                )}
              </div>
            )
          })}
        </div>
      </section>

      {/* SECTION 4: Courts, Sports & Max Players per Sport */}
      <section className="card p-4 sm:p-5 space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-line pb-3">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-xl bg-neon/15 text-neon flex items-center justify-center">
              <Users className="w-4 h-4" />
            </div>
            <div>
              <h2 className="text-sm font-bold text-text">
                4. Courts / Pitches, Sports & Max Players per Sport ({courts.length})
              </h2>
              <p className="text-[11px] text-muted">
                Add each pitch/court, its regular slot price, which sports can be played, and max people allowed in each sport
              </p>
            </div>
          </div>

          <button type="button" onClick={addCourt} className="btn-primary h-9 px-3.5 text-xs">
            <Plus className="w-3.5 h-3.5" />
            <span>Add Court / Pitch</span>
          </button>
        </div>

        <div className="space-y-4">
          {courts.map((court, idx) => (
            <div
              key={court.key}
              className="rounded-2xl border border-line bg-surface-2 p-4 space-y-4"
            >
              <div className="flex items-center justify-between gap-2">
                <div className="flex items-center gap-2">
                  <span className="rounded-lg bg-neon text-ink px-2 py-0.5 text-xs font-extrabold">
                    Court #{idx + 1}
                  </span>
                  <span className="text-sm font-bold text-text">{court.name}</span>
                </div>
                {courts.length > 1 && (
                  <button
                    type="button"
                    onClick={() => setCourts((prev) => prev.filter((c) => c.key !== court.key))}
                    className="text-xs text-danger hover:underline inline-flex items-center gap-1"
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                    <span>Remove Court</span>
                  </button>
                )}
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                <div className="space-y-1">
                  <label className="label">Court / Pitch Name *</label>
                  <input
                    type="text"
                    value={court.name}
                    onChange={(e) => updateCourt(court.key, { name: e.target.value })}
                    placeholder="e.g. Pitch 1 — 6v6 Arena"
                    className="input h-10 text-xs"
                  />
                </div>

                <div className="space-y-1">
                  <label className="label">Size / Format Label</label>
                  <input
                    type="text"
                    value={court.size_label}
                    onChange={(e) => updateCourt(court.key, { size_label: e.target.value })}
                    placeholder="e.g. 6-a-side (100×60 ft)"
                    className="input h-10 text-xs"
                  />
                </div>

                <div className="space-y-1">
                  <label className="label">Surface Type</label>
                  <input
                    type="text"
                    value={court.surface}
                    onChange={(e) => updateCourt(court.key, { surface: e.target.value })}
                    placeholder="e.g. FIFA 50mm Artificial Grass"
                    className="input h-10 text-xs"
                  />
                </div>

                <div className="space-y-1">
                  <label className="label">Regular Price per Slot (₹) *</label>
                  <input
                    type="number"
                    min={100}
                    step={50}
                    value={court.base_price}
                    onChange={(e) => updateCourt(court.key, { base_price: Number(e.target.value) || 0 })}
                    className="input h-10 text-xs font-bold text-neon"
                  />
                </div>

                <div className="space-y-1 sm:col-span-2">
                  <label className="label">
                    Overall Max People Allowed on This Court at One Time
                  </label>
                  <div className="flex items-center gap-2">
                    <input
                      type="number"
                      min={2}
                      max={50}
                      value={court.max_players}
                      onChange={(e) =>
                        updateCourt(court.key, { max_players: Number(e.target.value) || 2 })
                      }
                      className="input h-10 text-xs w-28 font-bold"
                    />
                    <span className="text-xs text-muted">
                      players max on {court.name}
                    </span>
                  </div>
                </div>
              </div>

              {/* Sports selectable on this court + per-sport max players */}
              <div className="space-y-2.5 pt-2 border-t border-line">
                <div className="label">
                  Sports playable on {court.name} & max players for each sport:
                </div>
                <div className="flex flex-wrap gap-2">
                  {sports.map((sp) => {
                    const selected = court.sports.some((s) => s.sport_id === sp.id)
                    return (
                      <button
                        key={sp.id}
                        type="button"
                        onClick={() => toggleCourtSport(court.key, sp.id)}
                        className={selected ? 'chip-active h-8 text-xs' : 'chip h-8 text-xs'}
                      >
                        <span>{sp.emoji}</span>
                        <span>{sp.name}</span>
                      </button>
                    )
                  })}
                </div>

                {/* Per-sport player capacity rows */}
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 pt-1">
                  {court.sports.map((cs) => {
                    const sp = sports.find((s) => s.id === cs.sport_id)
                    return (
                      <div
                        key={cs.sport_id}
                        className="rounded-xl bg-surface border border-line px-3 py-2 flex items-center justify-between gap-2"
                      >
                        <div className="flex items-center gap-2 text-xs font-semibold text-text">
                          <span>{sp?.emoji ?? '🏟️'}</span>
                          <span>{sp?.name ?? cs.sport_id}</span>
                        </div>
                        <div className="flex items-center gap-1.5">
                          <span className="text-[11px] text-muted">Max players:</span>
                          <input
                            type="number"
                            min={2}
                            max={40}
                            value={cs.max_players}
                            onChange={(e) =>
                              updateCourtSportMaxPlayers(
                                court.key,
                                cs.sport_id,
                                Number(e.target.value),
                              )
                            }
                            className="input h-7 w-16 px-2 text-xs text-center font-bold text-neon"
                          />
                        </div>
                      </div>
                    )
                  })}
                </div>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* SECTION 5: Happy Hour Deals & Peak Pricing */}
      <section className="card p-4 sm:p-5 space-y-4">
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-line pb-3">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-xl bg-neon/15 text-neon flex items-center justify-center">
              <Zap className="w-4 h-4" />
            </div>
            <div>
              <h2 className="text-sm font-bold text-text">
                5. Happy Hour Deals, Off-Peak Discounts & Peak Pricing ({pricingRules.length})
              </h2>
              <p className="text-[11px] text-muted">
                Fill empty daytime hours with Happy Hour % discounts or fixed ₹ deal prices
              </p>
            </div>
          </div>
        </div>

        {/* 1-click Deal Templates */}
        <div className="space-y-1.5">
          <div className="text-[11px] font-semibold text-muted flex items-center gap-1">
            <Sparkles className="w-3.5 h-3.5 text-neon" />
            <span>Quick-add popular deal templates:</span>
          </div>
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              onClick={() => addPricingRuleTemplate('happy_hour_pct')}
              className="btn-secondary h-8 px-3 text-xs border-neon/40 text-neon"
            >
              + Weekday Happy Hour (30% OFF · 6 AM–4 PM)
            </button>
            <button
              type="button"
              onClick={() => addPricingRuleTemplate('morning_bird')}
              className="btn-secondary h-8 px-3 text-xs"
            >
              + Early Bird (35% OFF · 6 AM–10 AM)
            </button>
            <button
              type="button"
              onClick={() => addPricingRuleTemplate('afternoon_fixed')}
              className="btn-secondary h-8 px-3 text-xs"
            >
              + Midday Fixed Deal (11 AM–4 PM)
            </button>
            <button
              type="button"
              onClick={() => addPricingRuleTemplate('weekend_peak')}
              className="btn-secondary h-8 px-3 text-xs"
            >
              + Weekend Prime Rate (6 PM–11 PM)
            </button>
          </div>
        </div>

        {pricingRules.length === 0 ? (
          <div className="rounded-xl border border-dashed border-line p-4 text-center text-xs text-muted">
            No custom pricing rules added. All slots will use each court’s regular base price.
          </div>
        ) : (
          <div className="space-y-3">
            {pricingRules.map((rule) => {
              const sampleBase =
                courts.find((c) => c.key === rule.court_key)?.base_price ??
                courts[0]?.base_price ??
                1400
              const previewPrice =
                rule.mode === 'discount'
                  ? Math.round((sampleBase * (100 - rule.discount_pct)) / 100)
                  : rule.price

              return (
                <div
                  key={rule.key}
                  className={`rounded-2xl border p-4 space-y-3 ${
                    rule.is_offpeak
                      ? 'border-neon/35 bg-neon/5'
                      : 'border-line bg-surface-2'
                  }`}
                >
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div className="flex items-center gap-2">
                      <button
                        type="button"
                        onClick={() => updatePricingRule(rule.key, { is_offpeak: true })}
                        className={
                          rule.is_offpeak
                            ? 'chip-active h-7 text-xs'
                            : 'chip h-7 text-xs'
                        }
                      >
                        <Zap className="w-3 h-3" />
                        <span>Happy Hour / Deal</span>
                      </button>
                      <button
                        type="button"
                        onClick={() =>
                          updatePricingRule(rule.key, {
                            is_offpeak: false,
                            mode: 'fixed',
                            label: rule.label === 'Happy Hour' ? 'Peak Rate' : rule.label,
                          })
                        }
                        className={
                          !rule.is_offpeak
                            ? 'chip-active h-7 text-xs'
                            : 'chip h-7 text-xs'
                        }
                      >
                        <span>Peak / Standard Override</span>
                      </button>
                    </div>

                    <button
                      type="button"
                      onClick={() =>
                        setPricingRules((prev) => prev.filter((r) => r.key !== rule.key))
                      }
                      className="text-xs text-danger hover:underline inline-flex items-center gap-1"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                      <span>Remove</span>
                    </button>
                  </div>

                  <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                    <div className="space-y-1">
                      <label className="label">Deal / Rule Label</label>
                      <input
                        type="text"
                        value={rule.label}
                        onChange={(e) => updatePricingRule(rule.key, { label: e.target.value })}
                        placeholder="e.g. Happy Hour, Student Deal"
                        className="input h-9 text-xs"
                      />
                    </div>

                    <div className="space-y-1">
                      <label className="label">Applies to Court</label>
                      <select
                        value={rule.court_key}
                        onChange={(e) =>
                          updatePricingRule(rule.key, { court_key: e.target.value })
                        }
                        className="input h-9 text-xs bg-surface"
                      >
                        <option value="">All Courts on this Turf</option>
                        {courts.map((c) => (
                          <option key={c.key} value={c.key}>
                            {c.name}
                          </option>
                        ))}
                      </select>
                    </div>

                    <div className="space-y-1">
                      <label className="label">Time Window</label>
                      <div className="flex items-center gap-1.5">
                        <select
                          value={rule.start_time}
                          onChange={(e) =>
                            updatePricingRule(rule.key, { start_time: e.target.value })
                          }
                          className="input h-9 px-2 text-xs bg-surface flex-1"
                        >
                          {TIME_OPTIONS.map((t) => (
                            <option key={t.value} value={t.value}>
                              {t.label}
                            </option>
                          ))}
                        </select>
                        <span className="text-xs text-muted">to</span>
                        <select
                          value={rule.end_time}
                          onChange={(e) =>
                            updatePricingRule(rule.key, { end_time: e.target.value })
                          }
                          className="input h-9 px-2 text-xs bg-surface flex-1"
                        >
                          {TIME_OPTIONS.map((t) => (
                            <option key={t.value} value={t.value}>
                              {t.label}
                            </option>
                          ))}
                        </select>
                      </div>
                    </div>
                  </div>

                  {/* Days of week */}
                  <div className="space-y-1.5">
                    <div className="flex items-center justify-between">
                      <span className="label">Active Days</span>
                      <div className="flex gap-2 text-[11px]">
                        <button
                          type="button"
                          onClick={() =>
                            updatePricingRule(rule.key, { days_of_week: [1, 2, 3, 4, 5] })
                          }
                          className="text-neon hover:underline"
                        >
                          Weekdays
                        </button>
                        <button
                          type="button"
                          onClick={() => updatePricingRule(rule.key, { days_of_week: [0, 6] })}
                          className="text-neon hover:underline"
                        >
                          Weekends
                        </button>
                        <button
                          type="button"
                          onClick={() =>
                            updatePricingRule(rule.key, { days_of_week: [0, 1, 2, 3, 4, 5, 6] })
                          }
                          className="text-neon hover:underline"
                        >
                          All Days
                        </button>
                      </div>
                    </div>
                    <div className="flex flex-wrap gap-1.5">
                      {DAYS.map((d) => {
                        const active = rule.days_of_week.includes(d.dow)
                        return (
                          <button
                            key={d.dow}
                            type="button"
                            onClick={() => toggleRuleDay(rule.key, d.dow)}
                            className={`w-10 h-8 rounded-lg text-xs font-bold border transition ${
                              active
                                ? 'border-neon bg-neon text-ink'
                                : 'border-line bg-surface text-muted'
                            }`}
                          >
                            {d.short}
                          </button>
                        )
                      })}
                    </div>
                  </div>

                  {/* Pricing Mode: % Discount vs Fixed Price */}
                  <div className="flex flex-wrap items-center justify-between gap-3 pt-2 border-t border-line/60">
                    <div className="flex items-center gap-2">
                      <button
                        type="button"
                        onClick={() => updatePricingRule(rule.key, { mode: 'discount' })}
                        className={
                          rule.mode === 'discount'
                            ? 'chip-active h-8 text-xs'
                            : 'chip h-8 text-xs'
                        }
                      >
                        % Discount
                      </button>
                      <button
                        type="button"
                        onClick={() => updatePricingRule(rule.key, { mode: 'fixed' })}
                        className={
                          rule.mode === 'fixed'
                            ? 'chip-active h-8 text-xs'
                            : 'chip h-8 text-xs'
                        }
                      >
                        Fixed ₹ Price
                      </button>
                    </div>

                    {rule.mode === 'discount' ? (
                      <div className="flex items-center gap-2">
                        <input
                          type="number"
                          min={5}
                          max={85}
                          step={5}
                          value={rule.discount_pct}
                          onChange={(e) =>
                            updatePricingRule(rule.key, {
                              discount_pct: Number(e.target.value) || 10,
                            })
                          }
                          className="input h-9 w-20 text-xs font-bold text-neon text-center"
                        />
                        <span className="text-xs font-bold text-neon">% OFF</span>
                        <span className="text-xs text-muted">
                          (Players pay <strong className="text-text">{formatINR(previewPrice)}</strong>/slot)
                        </span>
                      </div>
                    ) : (
                      <div className="flex items-center gap-2">
                        <span className="text-xs text-muted">Slot Price (₹):</span>
                        <input
                          type="number"
                          min={100}
                          step={50}
                          value={rule.price}
                          onChange={(e) =>
                            updatePricingRule(rule.key, {
                              price: Number(e.target.value) || 500,
                            })
                          }
                          className="input h-9 w-24 text-xs font-bold text-neon text-center"
                        />
                      </div>
                    )}
                  </div>
                </div>
              )
            })}
          </div>
        )}
      </section>

      {/* SECTION 6: Amenities & Venue Rules */}
      <section className="card p-4 sm:p-5 space-y-4">
        <div className="flex items-center gap-2.5 border-b border-line pb-3">
          <div className="w-8 h-8 rounded-xl bg-neon/15 text-neon flex items-center justify-center">
            <ShieldCheck className="w-4 h-4" />
          </div>
          <div>
            <h2 className="text-sm font-bold text-text">6. Amenities & Venue Rules</h2>
            <p className="text-[11px] text-muted">
              Select all facilities available at your turf and any rules players should know
            </p>
          </div>
        </div>

        <div className="space-y-2">
          <div className="label">Available Amenities ({selectedAmenities.length} selected)</div>
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
            {amenitiesList.map((a) => {
              const active = selectedAmenities.includes(a.id)
              return (
                <button
                  key={a.id}
                  type="button"
                  onClick={() =>
                    setSelectedAmenities((prev) =>
                      prev.includes(a.id) ? prev.filter((id) => id !== a.id) : [...prev, a.id],
                    )
                  }
                  className={`rounded-xl border px-3 py-2.5 flex items-center gap-2.5 text-xs font-medium text-left transition ${
                    active
                      ? 'border-neon bg-neon/10 text-text'
                      : 'border-line bg-surface-2 text-muted hover:text-text'
                  }`}
                >
                  <AmenityIcon
                    icon={a.icon}
                    className={`w-4 h-4 shrink-0 ${active ? 'text-neon' : 'text-muted'}`}
                  />
                  <span className="truncate">{a.name}</span>
                </button>
              )
            })}
          </div>
        </div>

        {/* Venue Rules */}
        <div className="space-y-2.5 pt-2 border-t border-line">
          <div className="label">Turf Rules for Players</div>
          <div className="space-y-1.5">
            {rules.map((r, idx) => (
              <div
                key={idx}
                className="rounded-xl bg-surface-2 border border-line px-3 py-2 flex items-center justify-between gap-2 text-xs"
              >
                <span className="text-text">{r}</span>
                <button
                  type="button"
                  onClick={() => setRules((prev) => prev.filter((_, i) => i !== idx))}
                  className="text-muted hover:text-danger shrink-0"
                >
                  <Trash2 className="w-3.5 h-3.5" />
                </button>
              </div>
            ))}
          </div>

          <div className="flex gap-2">
            <input
              type="text"
              value={newRuleText}
              onChange={(e) => setNewRuleText(e.target.value)}
              placeholder="Add a rule (e.g. Metal studs not allowed, bring valid ID)…"
              className="input h-9 text-xs flex-1"
            />
            <button
              type="button"
              onClick={() => {
                if (!newRuleText.trim()) return
                setRules((prev) => [...prev, newRuleText.trim()])
                setNewRuleText('')
              }}
              className="btn-secondary h-9 px-3 text-xs"
            >
              Add Rule
            </button>
          </div>

          <div className="flex flex-wrap gap-1.5">
            {PRESET_RULES.filter((pr) => !rules.includes(pr)).map((pr) => (
              <button
                key={pr}
                type="button"
                onClick={() => setRules((prev) => [...prev, pr])}
                className="rounded-lg bg-surface-2 border border-line px-2.5 py-1 text-[11px] text-muted hover:text-neon hover:border-neon/40 transition text-left"
              >
                + {pr}
              </button>
            ))}
          </div>
        </div>
      </section>

      {/* Publish & Save Action Bar */}
      {formError && (
        <div className="rounded-2xl bg-danger/15 border border-danger/40 px-4 py-3 text-xs font-semibold text-danger">
          ⚠️ {formError}
        </div>
      )}

      <div className="card p-4 border-neon/40 bg-surface flex flex-col sm:flex-row items-stretch sm:items-center justify-between gap-3">
        <label className="flex items-center gap-2.5 cursor-pointer">
          <input
            type="checkbox"
            checked={isActive}
            onChange={(e) => setIsActive(e.target.checked)}
            className="w-4 h-4 accent-neon rounded"
          />
          <div>
            <div className="text-xs font-bold text-text">Make turf LIVE on Player App immediately</div>
            <div className="text-[11px] text-muted">
              Players in Delhi NCR will be able to find and book slots right away
            </div>
          </div>
        </label>

        <div className="flex items-center gap-2.5">
          <button
            type="button"
            disabled={saveTurf.isPending}
            onClick={() => handleSave(false)}
            className="btn-secondary h-11 px-4 text-xs"
          >
            Save as Hidden Draft
          </button>
          <button
            type="button"
            disabled={saveTurf.isPending}
            onClick={() => handleSave(isActive)}
            className="btn-primary h-11 px-6 text-sm shadow-glow flex-1 sm:flex-initial"
          >
            <Check className="w-4 h-4" />
            <span>
              {saveTurf.isPending
                ? 'Saving Turf…'
                : isEditing
                  ? 'Save Turf Changes'
                  : 'Publish Turf Live'}
            </span>
          </button>
        </div>
      </div>
    </div>
  )
}
