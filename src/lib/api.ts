import { useEffect } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from './supabase'
import { useAuth } from './auth'
import {
  FALLBACK_AMENITIES,
  FALLBACK_SETTINGS,
  FALLBACK_SPORTS,
} from './fallbackData'
import { getOfflinePass, listOfflinePasses, saveOfflinePass, saveOfflinePasses } from './offlinePasses'
import type {
  Amenity,
  AppNotification,
  AppSettings,
  Booking,
  BookingWithRelations,
  GameDetail,
  GameListItem,
  Review,
  SkillLevel,
  Slot,
  Sport,
  TurfDetail,
  TurfListItem,
} from './types'

const LOCAL_FAVS_KEY = 'turffet.favourites.v1'

function isMissingSchemaError(err: unknown): boolean {
  if (!err || typeof err !== 'object') return false
  const code = (err as { code?: string }).code ?? ''
  const msg = (err as { message?: string }).message ?? ''
  return (
    code === 'PGRST205' ||
    code === 'PGRST202' ||
    code === '42P01' ||
    code === '42883' ||
    /schema cache|Could not find the/i.test(msg)
  )
}

export function useSports() {
  return useQuery({
    queryKey: ['sports'],
    staleTime: 1000 * 60 * 30,
    queryFn: async (): Promise<Sport[]> => {
      const { data, error } = await supabase.from('sports').select('*').order('sort_order')
      if (error) {
        if (isMissingSchemaError(error)) return FALLBACK_SPORTS
        throw error
      }
      return data?.length ? (data as Sport[]) : FALLBACK_SPORTS
    },
  })
}

export function useAmenities() {
  return useQuery({
    queryKey: ['amenities'],
    staleTime: 1000 * 60 * 30,
    queryFn: async (): Promise<Amenity[]> => {
      const { data, error } = await supabase.from('amenities').select('*').order('sort_order')
      if (error) {
        if (isMissingSchemaError(error)) return FALLBACK_AMENITIES
        throw error
      }
      return data?.length ? (data as Amenity[]) : FALLBACK_AMENITIES
    },
  })
}

export function useAppSettings() {
  return useQuery({
    queryKey: ['app_settings'],
    staleTime: 1000 * 60 * 15,
    queryFn: async (): Promise<AppSettings> => {
      const { data, error } = await supabase.from('app_settings').select('*').maybeSingle()
      if (error || !data) return FALLBACK_SETTINGS
      return data as AppSettings
    },
  })
}

export interface NearbyFilters {
  lat?: number | null
  lng?: number | null
  radiusKm?: number
  sport?: string | null
  maxPrice?: number | null
  search?: string | null
  amenities?: string[]
  offpeakOnly?: boolean
}

export function useNearbyTurfs(filters: NearbyFilters) {
  return useQuery({
    queryKey: ['nearby_turfs', filters],
    queryFn: async (): Promise<TurfListItem[]> => {
      const { data, error } = await supabase.rpc('nearby_turfs', {
        p_lat: filters.lat ?? null,
        p_lng: filters.lng ?? null,
        p_radius_km: filters.radiusKm ?? 60,
        p_sport: filters.sport ?? null,
        p_max_price: filters.maxPrice ?? null,
        p_search: filters.search?.trim() || null,
        p_amenities: filters.amenities?.length ? filters.amenities : null,
        p_offpeak_only: filters.offpeakOnly ?? false,
      })
      if (error) {
        if (isMissingSchemaError(error)) return []
        throw error
      }
      return (data as TurfListItem[]) ?? []
    },
  })
}

export function useTurfDetail(slug: string | undefined) {
  return useQuery({
    queryKey: ['turf_detail', slug],
    enabled: Boolean(slug),
    queryFn: async (): Promise<TurfDetail | null> => {
      if (!slug) return null
      const { data, error } = await supabase
        .from('turfs')
        .select(
          `*,
           turf_photos(id, url, sort_order),
           turf_amenities(amenity_id),
           operating_hours(day_of_week, open_time, close_time),
           courts(id, turf_id, name, size_label, surface, base_price, max_players, sort_order, court_sports(sport_id, max_players)),
           pricing_rules(id, court_id, days_of_week, start_time, end_time, price, discount_pct, label, is_offpeak)`,
        )
        .eq('slug', slug)
        .maybeSingle()
      if (error) {
        if (isMissingSchemaError(error)) return null
        throw error
      }
      if (!data) return null
      const detail = data as TurfDetail
      detail.turf_photos = [...(detail.turf_photos ?? [])].sort((a, b) => a.sort_order - b.sort_order)
      detail.courts = [...(detail.courts ?? [])].sort((a, b) => a.sort_order - b.sort_order)
      return detail
    },
  })
}

export function useTurfSlots(turfId: string | undefined, dateStr: string) {
  const qc = useQueryClient()

  // Live slot updates via Supabase Realtime broadcast channel `turf-<id>`
  useEffect(() => {
    if (!turfId) return
    const channel = supabase
      .channel(`turf-${turfId}`)
      .on('broadcast', { event: 'availability' }, () => {
        qc.invalidateQueries({ queryKey: ['turf_slots', turfId] })
      })
      .subscribe()
    return () => {
      supabase.removeChannel(channel)
    }
  }, [turfId, qc])

  return useQuery({
    queryKey: ['turf_slots', turfId, dateStr],
    enabled: Boolean(turfId && dateStr),
    queryFn: async (): Promise<Slot[]> => {
      if (!turfId) return []
      const { data, error } = await supabase.rpc('get_turf_slots', {
        p_turf_id: turfId,
        p_date: dateStr,
      })
      if (error) {
        if (isMissingSchemaError(error)) return []
        throw error
      }
      return (data as Slot[]) ?? []
    },
  })
}

export function useTurfReviews(turfId: string | undefined) {
  return useQuery({
    queryKey: ['turf_reviews', turfId],
    enabled: Boolean(turfId),
    queryFn: async (): Promise<Review[]> => {
      if (!turfId) return []
      const { data, error } = await supabase.rpc('get_turf_reviews', {
        p_turf_id: turfId,
        p_limit: 20,
      })
      if (error) {
        if (isMissingSchemaError(error)) return []
        throw error
      }
      return (data as Review[]) ?? []
    },
  })
}

function readLocalFavs(): string[] {
  try {
    return JSON.parse(localStorage.getItem(LOCAL_FAVS_KEY) ?? '[]') as string[]
  } catch {
    return []
  }
}

export function useFavourites() {
  const { user } = useAuth()
  return useQuery({
    queryKey: ['favourites', user?.id ?? 'anon'],
    queryFn: async (): Promise<string[]> => {
      if (!user) return readLocalFavs()
      const { data, error } = await supabase.from('favourites').select('turf_id').eq('user_id', user.id)
      if (error) {
        if (isMissingSchemaError(error)) return readLocalFavs()
        throw error
      }
      return (data ?? []).map((r: { turf_id: string }) => r.turf_id)
    },
  })
}

export function useToggleFavourite() {
  const { user } = useAuth()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ turfId, isFav }: { turfId: string; isFav: boolean }) => {
      const toggleLocal = () => {
        const cur = new Set(readLocalFavs())
        if (isFav) cur.delete(turfId)
        else cur.add(turfId)
        localStorage.setItem(LOCAL_FAVS_KEY, JSON.stringify([...cur]))
      }
      if (!user) {
        toggleLocal()
        return
      }
      if (isFav) {
        const { error } = await supabase.from('favourites').delete().eq('user_id', user.id).eq('turf_id', turfId)
        if (error) {
          if (isMissingSchemaError(error)) toggleLocal()
          else throw error
        }
      } else {
        const { error } = await supabase.from('favourites').insert({ user_id: user.id, turf_id: turfId })
        if (error) {
          if (isMissingSchemaError(error)) toggleLocal()
          else throw error
        }
      }
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['favourites'] })
    },
  })
}

export function useMyBookings() {
  const { user } = useAuth()
  return useQuery({
    queryKey: ['my_bookings', user?.id ?? 'local'],
    queryFn: async (): Promise<BookingWithRelations[]> => {
      if (!user) return listOfflinePasses()
      const { data, error } = await supabase
        .from('bookings')
        .select(
          `*,
           turfs(id, slug, name, area, address, lat, lng, cover_image, phone, whatsapp),
           courts(id, name, size_label),
           open_games(id, spots_total, status),
           reviews(id, rating, comment)`,
        )
        .eq('user_id', user.id)
        .order('starts_at', { ascending: false })
      if (error) {
        if (isMissingSchemaError(error)) return listOfflinePasses()
        // If offline, serve cached passes so the user can still view their QR at the venue
        const cached = listOfflinePasses()
        if (cached.length) return cached
        throw error
      }
      const list = (data as BookingWithRelations[]) ?? []
      saveOfflinePasses(list)
      return list
    },
  })
}

export function useBooking(bookingId: string | undefined) {
  const { user } = useAuth()
  return useQuery({
    queryKey: ['booking', bookingId],
    enabled: Boolean(bookingId),
    queryFn: async (): Promise<BookingWithRelations | null> => {
      if (!bookingId) return null
      if (!user) return getOfflinePass(bookingId)
      const { data, error } = await supabase
        .from('bookings')
        .select(
          `*,
           turfs(id, slug, name, area, address, lat, lng, cover_image, phone, whatsapp),
           courts(id, name, size_label),
           open_games(id, spots_total, status),
           reviews(id, rating, comment)`,
        )
        .eq('id', bookingId)
        .maybeSingle()
      if (error) {
        const cached = getOfflinePass(bookingId)
        if (cached) return cached
        throw error
      }
      if (data) {
        const b = data as BookingWithRelations
        saveOfflinePass(b)
        return b
      }
      return getOfflinePass(bookingId)
    },
  })
}

export interface CreateBookingInput {
  courtId: string
  sportId: string
  startsAt: string
  slots: number
  players: number
  lookingFor?: number
  skill?: SkillLevel | null
  note?: string | null
  // Used for offline / pre-migration local pass synthesis
  turf?: TurfDetail
  totalPrice?: number
}

export function useCreateBooking() {
  const qc = useQueryClient()
  const { user } = useAuth()
  return useMutation({
    mutationFn: async (input: CreateBookingInput): Promise<Booking> => {
      const { data, error } = await supabase.rpc('create_booking', {
        p_court_id: input.courtId,
        p_sport_id: input.sportId,
        p_starts_at: input.startsAt,
        p_slots: input.slots,
        p_players: input.players,
        p_looking_for: input.lookingFor ?? 0,
        p_skill: input.skill ?? null,
        p_note: input.note?.trim() || null,
      })
      if (error) {
        if (isMissingSchemaError(error) && input.turf) {
          const court = input.turf.courts.find((c) => c.id === input.courtId) ?? input.turf.courts[0]!
          const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
          let code = ''
          for (let i = 0; i < 6; i++) code += alphabet[Math.floor(Math.random() * alphabet.length)]
          const id = crypto.randomUUID()
          const startsMs = new Date(input.startsAt).getTime()
          const endsAt = new Date(startsMs + input.slots * input.turf.slot_minutes * 60000).toISOString()
          const sig = Array.from(crypto.getRandomValues(new Uint8Array(12)))
            .map((b) => b.toString(16).padStart(2, '0'))
            .join('')
          const full: BookingWithRelations = {
            id,
            code,
            qr_token: `TFT1.${id}.${code}.${sig}`,
            user_id: user?.id ?? 'local-user',
            turf_id: input.turf.id,
            court_id: court.id,
            sport_id: input.sportId,
            starts_at: input.startsAt,
            ends_at: endsAt,
            players_count: input.players,
            total_price: input.totalPrice ?? court.base_price * input.slots,
            status: 'confirmed',
            note: input.note?.trim() || null,
            cancelled_at: null,
            checked_in_at: null,
            created_at: new Date().toISOString(),
            turfs: {
              id: input.turf.id,
              slug: input.turf.slug,
              name: input.turf.name,
              area: input.turf.area,
              address: input.turf.address,
              lat: input.turf.lat,
              lng: input.turf.lng,
              cover_image: input.turf.cover_image,
              phone: input.turf.phone,
              whatsapp: input.turf.whatsapp,
            },
            courts: { id: court.id, name: court.name, size_label: court.size_label },
            open_games:
              input.lookingFor && input.lookingFor > 0
                ? [{ id: crypto.randomUUID(), spots_total: input.lookingFor, status: 'open' }]
                : null,
            reviews: null,
          }
          saveOfflinePass(full)
          return full
        }
        throw error
      }
      return data as Booking
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['my_bookings'] })
      qc.invalidateQueries({ queryKey: ['turf_slots'] })
      qc.invalidateQueries({ queryKey: ['games'] })
      qc.invalidateQueries({ queryKey: ['notifications'] })
    },
  })
}

export function useCancelBooking() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ bookingId, reason }: { bookingId: string; reason?: string }) => {
      const { data, error } = await supabase.rpc('cancel_booking', {
        p_booking_id: bookingId,
        p_reason: reason?.trim() || null,
      })
      if (error) {
        if (isMissingSchemaError(error)) {
          const pass = getOfflinePass(bookingId)
          if (!pass) throw new Error('BOOKING_NOT_FOUND')
          const minsUntil = (new Date(pass.starts_at).getTime() - Date.now()) / 60000
          if (minsUntil < 120) throw new Error('CANCELLATION_WINDOW_PASSED')
          const updated: BookingWithRelations = {
            ...pass,
            status: 'cancelled',
            cancelled_at: new Date().toISOString(),
          }
          saveOfflinePass(updated)
          return updated
        }
        throw error
      }
      const pass = getOfflinePass(bookingId)
      if (pass) saveOfflinePass({ ...pass, status: 'cancelled', cancelled_at: new Date().toISOString() })
      return data as Booking
    },
    onSuccess: (_data, vars) => {
      qc.invalidateQueries({ queryKey: ['booking', vars.bookingId] })
      qc.invalidateQueries({ queryKey: ['my_bookings'] })
      qc.invalidateQueries({ queryKey: ['turf_slots'] })
      qc.invalidateQueries({ queryKey: ['games'] })
    },
  })
}

export function useSubmitReview() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ bookingId, rating, comment }: { bookingId: string; rating: number; comment?: string }) => {
      const { data, error } = await supabase.rpc('submit_review', {
        p_booking_id: bookingId,
        p_rating: rating,
        p_comment: comment?.trim() || null,
      })
      if (error) {
        if (isMissingSchemaError(error)) {
          const pass = getOfflinePass(bookingId)
          if (pass) {
            saveOfflinePass({
              ...pass,
              reviews: [{ id: crypto.randomUUID(), rating, comment: comment?.trim() || null }],
            })
          }
          return
        }
        throw error
      }
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['my_bookings'] })
      qc.invalidateQueries({ queryKey: ['booking'] })
      qc.invalidateQueries({ queryKey: ['turf_reviews'] })
      qc.invalidateQueries({ queryKey: ['turf_detail'] })
      qc.invalidateQueries({ queryKey: ['nearby_turfs'] })
    },
  })
}

export function useGames(params: { lat?: number | null; lng?: number | null; sport?: string | null; mine?: boolean }) {
  const { user } = useAuth()
  return useQuery({
    queryKey: ['games', params, user?.id ?? 'anon'],
    queryFn: async (): Promise<GameListItem[]> => {
      if (params.mine && !user) return []
      const { data, error } = await supabase.rpc('list_games', {
        p_lat: params.lat ?? null,
        p_lng: params.lng ?? null,
        p_sport: params.sport ?? null,
        p_mine: params.mine ?? false,
      })
      if (error) {
        if (isMissingSchemaError(error)) return []
        throw error
      }
      return (data as GameListItem[]) ?? []
    },
  })
}

export function useGameDetail(gameId: string | undefined) {
  const { user } = useAuth()
  return useQuery({
    queryKey: ['game_detail', gameId, user?.id ?? 'anon'],
    enabled: Boolean(gameId),
    queryFn: async (): Promise<GameDetail | null> => {
      if (!gameId) return null
      const { data, error } = await supabase.rpc('get_game_detail', { p_game_id: gameId })
      if (error) {
        if (isMissingSchemaError(error)) return null
        throw error
      }
      return (data as GameDetail) ?? null
    },
  })
}

export function useRequestJoin() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ gameId, message }: { gameId: string; message?: string }) => {
      const { data, error } = await supabase.rpc('request_join', {
        p_game_id: gameId,
        p_message: message?.trim() || null,
      })
      if (error) throw error
      return data
    },
    onSuccess: (_d, v) => {
      qc.invalidateQueries({ queryKey: ['game_detail', v.gameId] })
      qc.invalidateQueries({ queryKey: ['games'] })
    },
  })
}

export function useRespondJoin() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ requestId, accept }: { requestId: string; accept: boolean; gameId: string }) => {
      const { data, error } = await supabase.rpc('respond_join', {
        p_request_id: requestId,
        p_accept: accept,
      })
      if (error) throw error
      return data
    },
    onSuccess: (_d, v) => {
      qc.invalidateQueries({ queryKey: ['game_detail', v.gameId] })
      qc.invalidateQueries({ queryKey: ['games'] })
    },
  })
}

export function useWithdrawJoin() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ gameId }: { gameId: string }) => {
      const { error } = await supabase.rpc('withdraw_join', { p_game_id: gameId })
      if (error) throw error
    },
    onSuccess: (_d, v) => {
      qc.invalidateQueries({ queryKey: ['game_detail', v.gameId] })
      qc.invalidateQueries({ queryKey: ['games'] })
    },
  })
}

export function useSetGameOpen() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ gameId, open }: { gameId: string; open: boolean }) => {
      const { error } = await supabase.rpc('set_game_open', { p_game_id: gameId, p_open: open })
      if (error) throw error
    },
    onSuccess: (_d, v) => {
      qc.invalidateQueries({ queryKey: ['game_detail', v.gameId] })
      qc.invalidateQueries({ queryKey: ['games'] })
    },
  })
}

export function useNotifications() {
  const { user } = useAuth()
  const qc = useQueryClient()

  useEffect(() => {
    if (!user) return
    const channel = supabase
      .channel(`notif-${user.id}`)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'notifications', filter: `user_id=eq.${user.id}` },
        () => {
          qc.invalidateQueries({ queryKey: ['notifications', user.id] })
        },
      )
      .subscribe()
    return () => {
      supabase.removeChannel(channel)
    }
  }, [user, qc])

  return useQuery({
    queryKey: ['notifications', user?.id],
    enabled: Boolean(user),
    queryFn: async (): Promise<AppNotification[]> => {
      if (!user) return []
      const { data, error } = await supabase
        .from('notifications')
        .select('*')
        .eq('user_id', user.id)
        .order('created_at', { ascending: false })
        .limit(40)
      if (error) {
        if (isMissingSchemaError(error)) return []
        throw error
      }
      return (data as AppNotification[]) ?? []
    },
  })
}

export function useMarkNotificationsRead() {
  const { user } = useAuth()
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (notificationId?: string) => {
      if (!user) return
      let q = supabase.from('notifications').update({ read_at: new Date().toISOString() }).eq('user_id', user.id)
      if (notificationId) q = q.eq('id', notificationId)
      else q = q.is('read_at', null)
      const { error } = await q
      if (error && !isMissingSchemaError(error)) throw error
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['notifications'] })
    },
  })
}
