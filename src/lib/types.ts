export type SkillLevel = 'beginner' | 'intermediate' | 'advanced'
export type BookingStatus = 'confirmed' | 'checked_in' | 'completed' | 'cancelled' | 'no_show'
export type GameStatus = 'open' | 'full' | 'closed'
export type JoinStatus = 'pending' | 'accepted' | 'declined' | 'withdrawn'

export interface Sport {
  id: string
  name: string
  emoji: string
  sort_order: number
}

export interface Amenity {
  id: string
  name: string
  icon: string
  sort_order: number
}

export interface AppSettings {
  cancellation_window_minutes: number
  max_slots_per_booking: number
  max_bookings_per_day: number
  booking_horizon_days: number
  strikes_enabled: boolean
  strike_limit: number
}

export interface TurfListItem {
  id: string
  slug: string
  name: string
  area: string
  address: string
  lat: number
  lng: number
  cover_image: string | null
  rating_avg: number
  rating_count: number
  distance_km: number | null
  min_price: number | null
  offpeak_price: number | null
  sports: string[]
  amenities: string[]
  opens_at: string | null
  closes_at: string | null
}

export interface Court {
  id: string
  turf_id: string
  name: string
  size_label: string | null
  surface: string | null
  base_price: number
  max_players: number
  sort_order: number
  court_sports: { sport_id: string; max_players?: number | null }[]
}

export interface PricingRule {
  id: string
  court_id: string | null
  days_of_week: number[]
  start_time: string
  end_time: string
  price: number | null
  discount_pct?: number | null
  label: string | null
  is_offpeak: boolean
}

export interface OperatingHours {
  day_of_week: number
  open_time: string
  close_time: string
}

export interface TurfDetail {
  id: string
  slug: string
  name: string
  description: string | null
  area: string
  city: string
  address: string
  lat: number
  lng: number
  phone: string | null
  whatsapp: string | null
  cover_image: string | null
  rules: string[]
  slot_minutes: number
  rating_avg: number
  rating_count: number
  turf_photos: { id: string; url: string; sort_order: number }[]
  turf_amenities: { amenity_id: string }[]
  operating_hours: OperatingHours[]
  courts: Court[]
  pricing_rules: PricingRule[]
}

export interface Slot {
  court_id: string
  starts_at: string
  ends_at: string
  price: number
  label: string | null
  is_offpeak: boolean
  is_available: boolean
  is_mine: boolean
}

export interface Booking {
  id: string
  code: string
  qr_token: string
  user_id: string
  turf_id: string
  court_id: string
  sport_id: string
  starts_at: string
  ends_at: string
  players_count: number
  total_price: number
  status: BookingStatus
  note: string | null
  cancelled_at: string | null
  checked_in_at: string | null
  created_at: string
}

export interface BookingWithRelations extends Booking {
  turfs: Pick<TurfDetail, 'id' | 'slug' | 'name' | 'area' | 'address' | 'lat' | 'lng' | 'cover_image' | 'phone' | 'whatsapp'>
  courts: Pick<Court, 'id' | 'name' | 'size_label'>
  open_games: { id: string; spots_total: number; status: GameStatus }[] | { id: string; spots_total: number; status: GameStatus } | null
  reviews: { id: string; rating: number; comment: string | null }[] | { id: string; rating: number; comment: string | null } | null
}

export interface GameListItem {
  id: string
  booking_id: string
  turf_id: string
  turf_name: string
  turf_area: string
  turf_cover: string | null
  sport_id: string
  starts_at: string
  ends_at: string
  spots_total: number
  spots_filled: number
  players_count: number
  total_price: number
  skill_level: SkillLevel | null
  note: string | null
  status: GameStatus
  host_name: string
  is_host: boolean
  my_status: JoinStatus | null
  distance_km: number | null
}

export interface GameDetail {
  id: string
  status: GameStatus
  sport_id: string
  starts_at: string
  ends_at: string
  spots_total: number
  skill_level: SkillLevel | null
  note: string | null
  is_host: boolean
  my_request: { id: string; status: JoinStatus } | null
  host: { name: string; skill_level: SkillLevel | null; phone: string | null }
  booking: { players_count: number; total_price: number; court_name: string; size_label: string | null }
  turf: { id: string; slug: string; name: string; area: string; address: string; lat: number; lng: number; cover_image: string | null }
  players: { name: string; skill_level: SkillLevel | null }[]
  requests:
    | {
        id: string
        status: JoinStatus
        message: string | null
        created_at: string
        name: string
        skill_level: SkillLevel | null
        phone: string | null
      }[]
    | null
}

export interface Profile {
  id: string
  full_name: string
  phone: string | null
  email: string | null
  avatar_url: string | null
  preferred_sports: string[]
  skill_level: SkillLevel | null
  onboarded: boolean
  is_owner?: boolean
  business_name?: string | null
  business_phone?: string | null
  strikes: number
  booking_blocked_until: string | null
}

export interface Review {
  id: string
  rating: number
  comment: string | null
  created_at: string
  reviewer_name: string
  sport_id: string
}

export interface AppNotification {
  id: string
  type: string
  title: string
  body: string
  url: string | null
  read_at: string | null
  created_at: string
}

// ---------- Turf Owner Portal Types ----------

export interface OwnerTurfSummary {
  id: string
  slug: string
  name: string
  area: string
  address: string
  lat: number
  lng: number
  cover_image: string | null
  is_active: boolean
  rating_avg: number
  rating_count: number
  slot_minutes: number
  courts_count: number
  min_price: number | null
  deals_count: number
  sports: string[]
  today_bookings: number
}

export interface OwnerDashboardBooking {
  id: string
  code: string
  turf_id: string
  turf_name: string
  court_name: string
  sport_id: string
  starts_at: string
  ends_at: string
  players_count: number
  total_price: number
  status: BookingStatus
  source: 'app' | 'walk_in' | 'blocked'
  note: string | null
  checked_in_at: string | null
  player_name: string
  player_phone: string | null
}

export interface OwnerDashboardData {
  today: string
  turfs_count: number
  today_bookings: number
  today_checked_in: number
  today_revenue: number
  week_revenue: number
  today_occupancy_pct: number
  upcoming_bookings: OwnerDashboardBooking[]
  turfs: OwnerTurfSummary[]
}

export interface OwnerBookingItem {
  id: string
  code: string
  qr_token: string
  turf_id: string
  turf_name: string
  court_id: string
  court_name: string
  court_size: string | null
  sport_id: string
  starts_at: string
  ends_at: string
  players_count: number
  total_price: number
  status: BookingStatus
  source: 'app' | 'walk_in' | 'blocked'
  note: string | null
  checked_in_at: string | null
  cancelled_at: string | null
  created_at: string
  player_name: string
  player_phone: string | null
}

export interface OwnerLookupBookingResult {
  id: string
  code: string
  qr_token: string
  signature_valid: boolean
  status: BookingStatus
  source: 'app' | 'walk_in' | 'blocked'
  starts_at: string
  ends_at: string
  players_count: number
  total_price: number
  sport_id: string
  note: string | null
  checked_in_at: string | null
  turf: {
    id: string
    name: string
    area: string
    address: string
  }
  court: {
    id: string
    name: string
    size_label: string | null
    max_players: number
  }
  player: {
    id: string
    name: string
    phone: string | null
    skill_level: SkillLevel | null
  }
}

export interface OwnerTurfPayload {
  id?: string | null
  name: string
  description?: string | null
  area: string
  city?: string
  address: string
  lat: number
  lng: number
  phone?: string | null
  whatsapp?: string | null
  cover_image?: string | null
  slot_minutes: number
  is_active: boolean
  rules: string[]
  photos: string[]
  amenities: string[]
  operating_hours: {
    day_of_week: number
    open_time: string
    close_time: string
  }[]
  courts: {
    id?: string | null
    key: string
    name: string
    size_label: string
    surface: string
    base_price: number
    max_players: number
    sports: {
      sport_id: string
      max_players: number
    }[]
  }[]
  pricing_rules: {
    court_id?: string | null
    court_key?: string | null
    days_of_week: number[]
    start_time: string
    end_time: string
    price?: number | null
    discount_pct?: number | null
    label: string
    is_offpeak: boolean
  }[]
}
