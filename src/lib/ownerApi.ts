import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from './supabase'
import { useAuth } from './auth'
import type {
  Booking,
  OwnerBookingItem,
  OwnerDashboardData,
  OwnerLookupBookingResult,
  OwnerTurfPayload,
  Profile,
  TurfDetail,
} from './types'

export function useRegisterOwner() {
  const qc = useQueryClient()
  const { refreshProfile } = useAuth()
  return useMutation({
    mutationFn: async (input: {
      fullName: string
      businessName: string
      businessPhone?: string | null
    }): Promise<Profile> => {
      const { data, error } = await supabase.rpc('register_owner', {
        p_full_name: input.fullName.trim(),
        p_business_name: input.businessName.trim(),
        p_business_phone: input.businessPhone?.trim() || null,
      })
      if (error) throw error
      return data as Profile
    },
    onSuccess: async () => {
      await refreshProfile()
      qc.invalidateQueries({ queryKey: ['owner_dashboard'] })
    },
  })
}

export function useOwnerDashboard() {
  const { user } = useAuth()
  return useQuery({
    queryKey: ['owner_dashboard', user?.id],
    enabled: Boolean(user),
    queryFn: async (): Promise<OwnerDashboardData> => {
      const { data, error } = await supabase.rpc('owner_dashboard')
      if (error) throw error
      return data as OwnerDashboardData
    },
  })
}

export function useOwnerTurfDetail(turfId: string | undefined) {
  const { user } = useAuth()
  return useQuery({
    queryKey: ['owner_turf_detail', turfId, user?.id],
    enabled: Boolean(turfId && user),
    queryFn: async (): Promise<(TurfDetail & { is_active: boolean }) | null> => {
      if (!turfId) return null
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
        .eq('id', turfId)
        .maybeSingle()
      if (error) throw error
      if (!data) return null
      const detail = data as TurfDetail & { is_active: boolean }
      detail.turf_photos = [...(detail.turf_photos ?? [])].sort((a, b) => a.sort_order - b.sort_order)
      detail.courts = [...(detail.courts ?? [])].sort((a, b) => a.sort_order - b.sort_order)
      return detail
    },
  })
}

export function useOwnerSaveTurf() {
  const qc = useQueryClient()
  const { refreshProfile } = useAuth()
  return useMutation({
    mutationFn: async (payload: OwnerTurfPayload): Promise<{ id: string; slug: string; name: string }> => {
      const { data, error } = await supabase.rpc('owner_save_turf', {
        p_payload: payload,
      })
      if (error) throw error
      return data as { id: string; slug: string; name: string }
    },
    onSuccess: async (saved) => {
      await refreshProfile()
      qc.invalidateQueries({ queryKey: ['owner_dashboard'] })
      qc.invalidateQueries({ queryKey: ['owner_turf_detail', saved.id] })
      qc.invalidateQueries({ queryKey: ['nearby_turfs'] })
      qc.invalidateQueries({ queryKey: ['turf_detail', saved.slug] })
    },
  })
}

export function useOwnerSetTurfActive() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ turfId, active }: { turfId: string; active: boolean }) => {
      const { data, error } = await supabase.rpc('owner_set_turf_active', {
        p_turf_id: turfId,
        p_active: active,
      })
      if (error) throw error
      return data
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['owner_dashboard'] })
      qc.invalidateQueries({ queryKey: ['owner_turf_detail'] })
      qc.invalidateQueries({ queryKey: ['nearby_turfs'] })
    },
  })
}

export function useOwnerDeleteTurf() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (turfId: string) => {
      const { error } = await supabase.rpc('owner_delete_turf', {
        p_turf_id: turfId,
      })
      if (error) throw error
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['owner_dashboard'] })
      qc.invalidateQueries({ queryKey: ['nearby_turfs'] })
    },
  })
}

export function useOwnerBookings(params: { from: string; to: string; turfId?: string | null }) {
  const { user } = useAuth()
  return useQuery({
    queryKey: ['owner_bookings', params, user?.id],
    enabled: Boolean(user),
    queryFn: async (): Promise<OwnerBookingItem[]> => {
      const { data, error } = await supabase.rpc('owner_list_bookings', {
        p_from: params.from,
        p_to: params.to,
        p_turf_id: params.turfId || null,
      })
      if (error) throw error
      return (data as OwnerBookingItem[]) ?? []
    },
  })
}

export function useOwnerLookupBooking() {
  return useMutation({
    mutationFn: async (query: string): Promise<OwnerLookupBookingResult> => {
      const { data, error } = await supabase.rpc('owner_lookup_booking', {
        p_query: query.trim(),
      })
      if (error) throw error
      return data as OwnerLookupBookingResult
    },
  })
}

export function useOwnerCheckIn() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ bookingId, qrToken }: { bookingId: string; qrToken?: string | null }): Promise<Booking> => {
      const { data, error } = await supabase.rpc('owner_check_in', {
        p_booking_id: bookingId,
        p_qr_token: qrToken || null,
      })
      if (error) throw error
      return data as Booking
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['owner_dashboard'] })
      qc.invalidateQueries({ queryKey: ['owner_bookings'] })
      qc.invalidateQueries({ queryKey: ['my_bookings'] })
      qc.invalidateQueries({ queryKey: ['booking'] })
    },
  })
}

export function useOwnerMarkNoShow() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (bookingId: string): Promise<Booking> => {
      const { data, error } = await supabase.rpc('owner_mark_no_show', {
        p_booking_id: bookingId,
      })
      if (error) throw error
      return data as Booking
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['owner_dashboard'] })
      qc.invalidateQueries({ queryKey: ['owner_bookings'] })
      qc.invalidateQueries({ queryKey: ['my_bookings'] })
    },
  })
}

export function useOwnerCancelBooking() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ bookingId, reason }: { bookingId: string; reason?: string }): Promise<Booking> => {
      const { data, error } = await supabase.rpc('owner_cancel_booking', {
        p_booking_id: bookingId,
        p_reason: reason?.trim() || null,
      })
      if (error) throw error
      return data as Booking
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['owner_dashboard'] })
      qc.invalidateQueries({ queryKey: ['owner_bookings'] })
      qc.invalidateQueries({ queryKey: ['turf_slots'] })
    },
  })
}

export function useOwnerBlockSlots() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (input: {
      courtId: string
      sportId: string
      startsAt: string
      slots: number
      players: number
      source: 'walk_in' | 'blocked'
      price?: number | null
      note?: string | null
    }): Promise<Booking> => {
      const { data, error } = await supabase.rpc('owner_block_slots', {
        p_court_id: input.courtId,
        p_sport_id: input.sportId,
        p_starts_at: input.startsAt,
        p_slots: input.slots,
        p_players: input.players,
        p_source: input.source,
        p_price: input.price ?? null,
        p_note: input.note?.trim() || null,
      })
      if (error) throw error
      return data as Booking
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['owner_dashboard'] })
      qc.invalidateQueries({ queryKey: ['owner_bookings'] })
      qc.invalidateQueries({ queryKey: ['turf_slots'] })
    },
  })
}

export async function uploadTurfPhoto(userId: string, file: File): Promise<string> {
  const ext = (file.name.split('.').pop() || 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '')
  const path = `${userId}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext || 'jpg'}`
  const { error } = await supabase.storage.from('turf-photos').upload(path, file, {
    cacheControl: '3600',
    upsert: false,
    contentType: file.type || 'image/jpeg',
  })
  if (error) throw error
  const { data } = supabase.storage.from('turf-photos').getPublicUrl(path)
  return data.publicUrl
}
