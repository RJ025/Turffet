import type {
  Amenity,
  AppSettings,
  BookingWithRelations,
  GameDetail,
  GameListItem,
  Review,
  Slot,
  Sport,
  TurfDetail,
  TurfListItem,
} from './types'

export const FALLBACK_SPORTS: Sport[] = [
  { id: 'football', name: 'Football', emoji: '⚽', sort_order: 1 },
  { id: 'cricket', name: 'Box Cricket', emoji: '🏏', sort_order: 2 },
  { id: 'badminton', name: 'Badminton', emoji: '🏸', sort_order: 3 },
  { id: 'pickleball', name: 'Pickleball', emoji: '🏓', sort_order: 4 },
  { id: 'tennis', name: 'Tennis', emoji: '🎾', sort_order: 5 },
  { id: 'basketball', name: 'Basketball', emoji: '🏀', sort_order: 6 },
  { id: 'volleyball', name: 'Volleyball', emoji: '🏐', sort_order: 7 },
]

export const FALLBACK_AMENITIES: Amenity[] = [
  { id: 'parking', name: 'Parking', icon: 'car', sort_order: 1 },
  { id: 'floodlights', name: 'Floodlights', icon: 'lightbulb', sort_order: 2 },
  { id: 'washroom', name: 'Washroom', icon: 'bath', sort_order: 3 },
  { id: 'changing_room', name: 'Changing room', icon: 'shirt', sort_order: 4 },
  { id: 'drinking_water', name: 'Drinking water', icon: 'glass-water', sort_order: 5 },
  { id: 'shower', name: 'Shower', icon: 'shower-head', sort_order: 6 },
  { id: 'cafe', name: 'Café / snacks', icon: 'coffee', sort_order: 7 },
  { id: 'equipment_rental', name: 'Equipment rental', icon: 'package', sort_order: 8 },
  { id: 'seating', name: 'Seating area', icon: 'armchair', sort_order: 9 },
  { id: 'first_aid', name: 'First aid', icon: 'cross', sort_order: 10 },
  { id: 'cctv', name: 'CCTV', icon: 'cctv', sort_order: 11 },
  { id: 'air_conditioned', name: 'Air conditioned', icon: 'snowflake', sort_order: 12 },
  { id: 'wifi', name: 'Wi-Fi', icon: 'wifi', sort_order: 13 },
]

export const FALLBACK_SETTINGS: AppSettings = {
  cancellation_window_minutes: 120,
  max_slots_per_booking: 3,
  max_bookings_per_day: 2,
  booking_horizon_days: 14,
  strikes_enabled: false,
  strike_limit: 3,
}

interface SeedCourt {
  id: string
  name: string
  size: string
  surface: string
  price: number
  max: number
  sports: string[]
}

interface SeedRule {
  days: number[]
  start: string
  end: string
  pct: number
  label: string
}

interface SeedTurf {
  id: string
  slug: string
  name: string
  area: string
  address: string
  lat: number
  lng: number
  phone: string
  desc: string
  photos: string[]
  amenities: string[]
  open: string
  close: string
  rating_avg: number
  rating_count: number
  rules: string[]
  pricing: SeedRule[]
  courts: SeedCourt[]
}

const STD_RULES = [
  'Turf/non-marking shoes only, no metal studs',
  'Please arrive 10 minutes before your slot',
  'No smoking, alcohol or food on the playing area',
  'Show your Turffet QR at the reception',
]

const COURT_RULES = [
  'Non-marking shoes are mandatory',
  'Max 4 players per court',
  'Please arrive 10 minutes before your slot',
  'Show your Turffet QR at the reception',
]

const FOOTBALL_PRICING: SeedRule[] = [
  { days: [1, 2, 3, 4, 5], start: '06:00:00', end: '09:00:00', pct: 35, label: 'Happy Hour' },
  { days: [1, 2, 3, 4, 5], start: '12:00:00', end: '16:00:00', pct: 30, label: 'Afternoon Deal' },
  { days: [0, 6], start: '18:00:00', end: '23:00:00', pct: -15, label: 'Weekend Prime' },
]

const CRICKET_PRICING: SeedRule[] = [
  { days: [1, 2, 3, 4, 5], start: '07:00:00', end: '10:00:00', pct: 30, label: 'Early Bird' },
  { days: [1, 2, 3, 4, 5], start: '13:00:00', end: '17:00:00', pct: 35, label: 'Afternoon Deal' },
  { days: [0, 6], start: '17:00:00', end: '23:00:00', pct: -10, label: 'Weekend Prime' },
]

const RACQUET_PRICING: SeedRule[] = [
  { days: [1, 2, 3, 4, 5], start: '10:00:00', end: '16:00:00', pct: 40, label: 'Midday Deal' },
  { days: [0, 1, 2, 3, 4, 5, 6], start: '21:00:00', end: '23:00:00', pct: 20, label: 'Late Night' },
]

const MIXED_PRICING: SeedRule[] = [
  { days: [1, 2, 3, 4, 5], start: '06:00:00', end: '09:00:00', pct: 30, label: 'Happy Hour' },
  { days: [1, 2, 3, 4, 5], start: '11:00:00', end: '16:00:00', pct: 35, label: 'Afternoon Deal' },
]

const SEED_TURFS: SeedTurf[] = [
  {
    id: '11111111-1111-4111-8111-000000000101',
    slug: 'spada-arena-sushant-lok-gurugram',
    name: 'SPADA Arena | Sushant Lok',
    area: 'Sushant Lok Phase 1, Sector 43, Gurugram',
    address: 'Excelsior American School, Block C2, Sushant Lok Phase I, Sector 43, Golf Course Road, Gurugram, Haryana 122002',
    lat: 28.4575,
    lng: 77.0825,
    phone: '+919167405982',
    desc: 'Flagship FIFA-quality artificial turf facility on Golf Course Road with pro-grade LED floodlights, 5v5 and 7v7 football setups, and box cricket.',
    photos: ['/images/turfs/football-night.jpg', '/images/turfs/football-closeup.jpg', '/images/turfs/football-day.jpg'],
    amenities: ['parking', 'floodlights', 'washroom', 'changing_room', 'drinking_water', 'cafe', 'equipment_rental', 'cctv'],
    open: '06:00:00',
    close: '24:00:00',
    rating_avg: 4.8,
    rating_count: 42,
    rules: STD_RULES,
    pricing: FOOTBALL_PRICING,
    courts: [
      { id: 'c-101-a', name: 'Turf A (5v5)', size: '5-a-side', surface: 'FIFA Artificial Grass', price: 1500, max: 12, sports: ['football', 'cricket'] },
      { id: 'c-101-b', name: 'Turf B (7v7)', size: '7-a-side', surface: 'FIFA Artificial Grass', price: 2400, max: 16, sports: ['football', 'cricket'] },
    ],
  },
  {
    id: '11111111-1111-4111-8111-000000000102',
    slug: 'gallant-play-arena-south-city-1',
    name: 'Gallant Play Arena | South City 1',
    area: 'Sector 41, South City 1, Gurugram',
    address: 'K.R. Mangalam World School, E-Block, South City I, Sector 41 (Near Huda City Centre), Gurugram, Haryana 122001',
    lat: 28.4562,
    lng: 77.0628,
    phone: '+919958677005',
    desc: 'Gallant Sports multi-sport arena featuring shock-pad artificial football turf, box cricket enclosure, synthetic basketball court and tennis.',
    photos: ['/images/turfs/multisport-rooftop.jpg', '/images/turfs/football-day.jpg', '/images/turfs/basketball.jpg'],
    amenities: ['parking', 'floodlights', 'washroom', 'changing_room', 'drinking_water', 'first_aid', 'seating', 'cctv'],
    open: '06:00:00',
    close: '23:00:00',
    rating_avg: 4.7,
    rating_count: 35,
    rules: STD_RULES,
    pricing: MIXED_PRICING,
    courts: [
      { id: 'c-102-a', name: 'Main Football & Cricket Turf', size: '6-a-side', surface: 'FIFA shock-pad grass', price: 1600, max: 14, sports: ['football', 'cricket'] },
      { id: 'c-102-b', name: 'Basketball Court', size: '5 vs 5', surface: 'Synthetic acrylic', price: 1000, max: 12, sports: ['basketball'] },
    ],
  },
  {
    id: '11111111-1111-4111-8111-000000000103',
    slug: 'sportslane-arena-sector-58-gurugram',
    name: 'SportsLane Arena | Sector 58',
    area: 'Sector 58, Golf Course Ext. Road, Gurugram',
    address: 'Behind Ireo Grand Arch, Ghatta Kanarpur, Sector 58 (Near Sector 55-56 Metro), Gurugram, Haryana 122011',
    lat: 28.4148,
    lng: 77.1115,
    phone: '+919818070700',
    desc: 'Dedicated racquet sports facility featuring indoor air-conditioned BWF-approved wooden badminton courts and outdoor cool-top pickleball & tennis courts.',
    photos: ['/images/turfs/badminton.jpg', '/images/turfs/pickleball.jpg', '/images/turfs/tennis.jpg'],
    amenities: ['parking', 'floodlights', 'washroom', 'changing_room', 'drinking_water', 'air_conditioned', 'equipment_rental', 'cafe'],
    open: '06:00:00',
    close: '23:00:00',
    rating_avg: 4.8,
    rating_count: 54,
    rules: COURT_RULES,
    pricing: RACQUET_PRICING,
    courts: [
      { id: 'c-103-1', name: 'Badminton Court 1', size: 'Doubles', surface: 'BWF Wooden + Mat', price: 550, max: 4, sports: ['badminton'] },
      { id: 'c-103-2', name: 'Pickleball Court 1', size: 'Doubles', surface: 'Cool-top Acrylic', price: 750, max: 4, sports: ['pickleball'] },
    ],
  },
  {
    id: '11111111-1111-4111-8111-000000000104',
    slug: 'siri-fort-sports-complex-hauz-khas',
    name: 'Siri Fort Sports Complex (DDA)',
    area: 'Siri Fort / Hauz Khas, South Delhi',
    address: 'August Kranti Marg, near Asian Games Village, Siri Fort, New Delhi, Delhi 110049',
    lat: 28.5535,
    lng: 77.2165,
    phone: '+911126496657',
    desc: 'Premier DDA multi-sport complex in South Delhi with floodlit synthetic tennis courts, indoor badminton halls, basketball courts and mini-football turf.',
    photos: ['/images/turfs/tennis.jpg', '/images/turfs/badminton.jpg', '/images/turfs/football-day.jpg'],
    amenities: ['parking', 'floodlights', 'washroom', 'changing_room', 'drinking_water', 'shower', 'cafe', 'first_aid', 'seating'],
    open: '06:00:00',
    close: '22:00:00',
    rating_avg: 4.8,
    rating_count: 68,
    rules: STD_RULES,
    pricing: MIXED_PRICING,
    courts: [
      { id: 'c-104-a', name: 'Mini Football Turf', size: '5-a-side', surface: 'Synthetic turf', price: 1400, max: 12, sports: ['football'] },
      { id: 'c-104-b', name: 'Synthetic Tennis Court', size: 'Doubles', surface: 'Acrylic hard court', price: 700, max: 4, sports: ['tennis'] },
    ],
  },
  {
    id: '11111111-1111-4111-8111-000000000106',
    slug: 'claygrounds-deep-vk-vasant-kunj',
    name: 'ClayGrounds | Vasant Kunj (Deep VK)',
    area: 'Sector D, Vasant Kunj, South Delhi',
    address: 'Deep Public School, Pocket 2, Sector D, Vasant Kunj, New Delhi, Delhi 110070',
    lat: 28.5246,
    lng: 77.1558,
    phone: '+917827860783',
    desc: 'South Delhi’s go-to 5v5 and 7v7 turf arena in Vasant Kunj with fresh artificial grass and bright night floodlights.',
    photos: ['/images/turfs/football-closeup.jpg', '/images/turfs/football-night.jpg'],
    amenities: ['parking', 'floodlights', 'washroom', 'drinking_water', 'equipment_rental', 'seating'],
    open: '06:00:00',
    close: '24:00:00',
    rating_avg: 4.7,
    rating_count: 37,
    rules: STD_RULES,
    pricing: FOOTBALL_PRICING,
    courts: [
      { id: 'c-106-a', name: 'Turf 1 (5v5)', size: '5-a-side', surface: 'Artificial grass', price: 1500, max: 12, sports: ['football', 'cricket'] },
    ],
  },
  {
    id: '11111111-1111-4111-8111-000000000115',
    slug: 'arena-44-the-box-zone-noida-sector-44',
    name: 'Arena 44 (The Box Zone) | Sector 44',
    area: 'Sector 44 (Near Sector 18), Noida',
    address: 'Mahamaya Northern United Sports Arena, Block B, Sector 44 (5 mins from Botanical Garden Metro), Noida, Uttar Pradesh 201301',
    lat: 28.5562,
    lng: 77.3398,
    phone: '+919310096119',
    desc: 'Premium Noida multi-sport complex offering dedicated Pickleball courts, Box Cricket, Football and Badminton.',
    photos: ['/images/turfs/pickleball.jpg', '/images/turfs/football-night.jpg', '/images/turfs/box-cricket.jpg'],
    amenities: ['parking', 'floodlights', 'washroom', 'changing_room', 'drinking_water', 'cafe', 'equipment_rental', 'cctv'],
    open: '06:00:00',
    close: '24:00:00',
    rating_avg: 4.8,
    rating_count: 51,
    rules: STD_RULES,
    pricing: MIXED_PRICING,
    courts: [
      { id: 'c-115-1', name: 'Main Turf (Football & Cricket)', size: '6-a-side', surface: 'Artificial grass', price: 1400, max: 14, sports: ['football', 'cricket'] },
      { id: 'c-115-2', name: 'Pickleball Court 1', size: 'Doubles', surface: 'Acrylic hard court', price: 700, max: 4, sports: ['pickleball'] },
    ],
  },
  {
    id: '11111111-1111-4111-8111-000000000116',
    slug: 'playall-sports-arena-sector-62-gurugram',
    name: 'PlayAll Sports Arena | Sector 62',
    area: 'Sector 62, Golf Course Ext., Gurugram',
    address: 'CRPF Road, near HBR Chowk, Ullahawas, Sector 62, Gurugram, Haryana 122102',
    lat: 28.4089,
    lng: 77.0912,
    phone: '+919310096119',
    desc: 'One of Gurugram’s busiest box cricket and 6-a-side football venues with high-roof netting, uniform bounce, and late-night floodlit slots.',
    photos: ['/images/turfs/box-cricket.jpg', '/images/turfs/cricket-day.jpg'],
    amenities: ['parking', 'floodlights', 'washroom', 'drinking_water', 'equipment_rental'],
    open: '06:00:00',
    close: '24:00:00',
    rating_avg: 4.6,
    rating_count: 27,
    rules: STD_RULES,
    pricing: CRICKET_PRICING,
    courts: [
      { id: 'c-116-a', name: 'Box Arena 1', size: '8 vs 8', surface: 'Artificial turf', price: 1400, max: 16, sports: ['cricket', 'football'] },
    ],
  },
]

function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371
  const dLat = ((lat2 - lat1) * Math.PI) / 180
  const dLng = ((lng2 - lng1) * Math.PI) / 180
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLng / 2) ** 2
  return Math.round(R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)) * 10) / 10
}

function discountedPrice(base: number, pct: number): number {
  return Math.round(((base * (100 - pct)) / 100) / 10) * 10
}

export function fallbackNearbyTurfs(params: {
  lat?: number | null
  lng?: number | null
  radiusKm?: number
  sport?: string | null
  maxPrice?: number | null
  search?: string | null
  amenities?: string[]
  offpeakOnly?: boolean
}): TurfListItem[] {
  const q = params.search?.trim().toLowerCase() ?? ''
  const out: TurfListItem[] = []
  for (const t of SEED_TURFS) {
    const sports = Array.from(new Set(t.courts.flatMap((c) => c.sports))).sort()
    const minPrice = Math.min(...t.courts.map((c) => c.price))
    const offpeakRules = t.pricing.filter((p) => p.pct > 0)
    const offpeakPrice =
      offpeakRules.length > 0
        ? Math.min(...t.courts.flatMap((c) => offpeakRules.map((r) => discountedPrice(c.price, r.pct))))
        : null
    const dist =
      params.lat != null && params.lng != null ? haversineKm(params.lat, params.lng, t.lat, t.lng) : null

    if (dist != null && params.radiusKm && dist > params.radiusKm) continue
    if (params.sport && !sports.includes(params.sport)) continue
    if (params.maxPrice != null && minPrice > params.maxPrice && (offpeakPrice == null || offpeakPrice > params.maxPrice)) continue
    if (q && !t.name.toLowerCase().includes(q) && !t.area.toLowerCase().includes(q)) continue
    if (params.amenities?.length && !params.amenities.every((a) => t.amenities.includes(a))) continue
    if (params.offpeakOnly && offpeakPrice == null) continue

    out.push({
      id: t.id,
      slug: t.slug,
      name: t.name,
      area: t.area,
      address: t.address,
      lat: t.lat,
      lng: t.lng,
      cover_image: t.photos[0] ?? null,
      rating_avg: t.rating_avg,
      rating_count: t.rating_count,
      distance_km: dist,
      min_price: minPrice,
      offpeak_price: offpeakPrice,
      sports,
      amenities: t.amenities,
      opens_at: t.open,
      closes_at: t.close,
    })
  }
  return out.sort((a, b) => (a.distance_km ?? 999) - (b.distance_km ?? 999) || b.rating_avg - a.rating_avg)
}

export function fallbackTurfDetail(slugOrId: string): TurfDetail | null {
  const t = SEED_TURFS.find((x) => x.slug === slugOrId || x.id === slugOrId)
  if (!t) return null
  return {
    id: t.id,
    slug: t.slug,
    name: t.name,
    description: t.desc,
    area: t.area,
    city: 'Delhi NCR',
    address: t.address,
    lat: t.lat,
    lng: t.lng,
    phone: t.phone,
    whatsapp: t.phone,
    cover_image: t.photos[0] ?? null,
    rules: t.rules,
    slot_minutes: 60,
    rating_avg: t.rating_avg,
    rating_count: t.rating_count,
    turf_photos: t.photos.map((url, idx) => ({ id: `${t.id}-p-${idx}`, url, sort_order: idx })),
    turf_amenities: t.amenities.map((amenity_id) => ({ amenity_id })),
    operating_hours: [0, 1, 2, 3, 4, 5, 6].map((dow) => ({
      day_of_week: dow,
      open_time: t.open,
      close_time: t.close,
    })),
    courts: t.courts.map((c, idx) => ({
      id: c.id,
      turf_id: t.id,
      name: c.name,
      size_label: c.size,
      surface: c.surface,
      base_price: c.price,
      max_players: c.max,
      sort_order: idx,
      court_sports: c.sports.map((sport_id) => ({ sport_id })),
    })),
    pricing_rules: t.courts.flatMap((c) =>
      t.pricing.map((r, rIdx) => ({
        id: `${c.id}-r-${rIdx}`,
        court_id: c.id,
        days_of_week: r.days,
        start_time: r.start,
        end_time: r.end,
        price: discountedPrice(c.price, r.pct),
        label: r.label,
        is_offpeak: r.pct > 0,
      })),
    ),
  }
}

export function fallbackTurfSlots(turfId: string, dateStr: string, bookedPasses: BookingWithRelations[]): Slot[] {
  const t = SEED_TURFS.find((x) => x.id === turfId)
  if (!t) return []
  const openH = parseInt(t.open.split(':')[0]!, 10)
  const closeH = parseInt(t.close.split(':')[0]!, 10)
  const dow = new Date(`${dateStr}T12:00:00+05:30`).getUTCDay()
  const now = Date.now()
  const out: Slot[] = []

  for (const c of t.courts) {
    for (let h = openH; h < closeH; h++) {
      const hh = String(h).padStart(2, '0')
      const nextHh = String(h + 1).padStart(2, '0')
      const startsAt = new Date(`${dateStr}T${hh}:00:00+05:30`).toISOString()
      const endsAt =
        h + 1 === 24
          ? new Date(new Date(`${dateStr}T00:00:00+05:30`).getTime() + 86400000).toISOString()
          : new Date(`${dateStr}T${nextHh}:00:00+05:30`).toISOString()
      const timeStr = `${hh}:00:00`
      const rule = t.pricing.find((r) => r.days.includes(dow) && timeStr >= r.start && timeStr < r.end)
      const price = rule ? discountedPrice(c.price, rule.pct) : c.price

      const overlapping = bookedPasses.find(
        (b) =>
          b.court_id === c.id &&
          (b.status === 'confirmed' || b.status === 'checked_in') &&
          new Date(b.starts_at).getTime() < new Date(endsAt).getTime() &&
          new Date(b.ends_at).getTime() > new Date(startsAt).getTime(),
      )

      out.push({
        court_id: c.id,
        starts_at: startsAt,
        ends_at: endsAt,
        price,
        label: rule?.label ?? null,
        is_offpeak: rule ? rule.pct > 0 : false,
        is_available: new Date(startsAt).getTime() > now && !overlapping,
        is_mine: Boolean(overlapping),
      })
    }
  }
  return out
}

export const FALLBACK_REVIEWS: Record<string, Review[]> = {
  '11111111-1111-4111-8111-000000000101': [
    {
      id: 'rev-1',
      rating: 5,
      comment: 'Best 5-a-side turf in Gurugram. Floodlights are bright and grass cushion is top notch.',
      created_at: new Date(Date.now() - 86400000 * 3).toISOString(),
      reviewer_name: 'Aarav',
      sport_id: 'football',
    },
  ],
}

export function getFallbackGames(lat?: number | null, lng?: number | null, sport?: string | null): GameListItem[] {
  const tomorrow7pm = new Date()
  tomorrow7pm.setDate(tomorrow7pm.getDate() + 1)
  tomorrow7pm.setHours(19, 0, 0, 0)
  const tomorrow8pm = new Date(tomorrow7pm.getTime() + 3600000)

  const sample: GameListItem[] = [
    {
      id: 'sample-game-1',
      booking_id: 'sample-booking-1',
      turf_id: '11111111-1111-4111-8111-000000000101',
      turf_name: 'SPADA Arena | Sushant Lok',
      turf_area: 'Sushant Lok Phase 1, Sector 43, Gurugram',
      turf_cover: '/images/turfs/football-night.jpg',
      sport_id: 'football',
      starts_at: tomorrow7pm.toISOString(),
      ends_at: tomorrow8pm.toISOString(),
      spots_total: 3,
      spots_filled: 1,
      players_count: 7,
      total_price: 1500,
      skill_level: 'intermediate',
      note: 'Friendly 5v5 game after work at SPADA Sushant Lok. Turf shoes required!',
      status: 'open',
      host_name: 'Kabir',
      is_host: false,
      my_status: null,
      distance_km: lat != null && lng != null ? haversineKm(lat, lng, 28.4575, 77.0825) : null,
    },
  ]
  return sport ? sample.filter((g) => g.sport_id === sport) : sample
}

export function getFallbackGameDetail(gameId: string): GameDetail | null {
  const g = getFallbackGames().find((x) => x.id === gameId)
  if (!g) return null
  const turf = fallbackTurfDetail(g.turf_id)
  if (!turf) return null
  return {
    id: g.id,
    status: g.status,
    sport_id: g.sport_id,
    starts_at: g.starts_at,
    ends_at: g.ends_at,
    spots_total: g.spots_total,
    skill_level: g.skill_level,
    note: g.note,
    is_host: false,
    my_request: null,
    host: { name: g.host_name, skill_level: g.skill_level, phone: null },
    booking: {
      players_count: g.players_count,
      total_price: g.total_price,
      court_name: turf.courts[0]?.name ?? 'Turf A',
      size_label: turf.courts[0]?.size_label ?? '5-a-side',
    },
    turf: {
      id: turf.id,
      slug: turf.slug,
      name: turf.name,
      area: turf.area,
      address: turf.address,
      lat: turf.lat,
      lng: turf.lng,
      cover_image: turf.cover_image,
    },
    players: g.spots_filled > 0 ? [{ name: 'Siddharth', skill_level: 'intermediate' }] : [],
    requests: null,
  }
}
