import type { BookingWithRelations } from './types'

const KEY = 'turffet.offline_passes.v1'

function readMap(): Record<string, BookingWithRelations> {
  try {
    const raw = localStorage.getItem(KEY)
    return raw ? (JSON.parse(raw) as Record<string, BookingWithRelations>) : {}
  } catch {
    return {}
  }
}

function writeMap(map: Record<string, BookingWithRelations>) {
  try {
    localStorage.setItem(KEY, JSON.stringify(map))
  } catch {
    /* quota / private mode */
  }
}

export function saveOfflinePasses(bookings: BookingWithRelations[]) {
  const next = readMap()
  for (const b of bookings) next[b.id] = b
  writeMap(next)
}

export function saveOfflinePass(booking: BookingWithRelations) {
  const next = readMap()
  next[booking.id] = booking
  writeMap(next)
}

export function getOfflinePass(id: string): BookingWithRelations | null {
  return readMap()[id] ?? null
}

export function listOfflinePasses(): BookingWithRelations[] {
  return Object.values(readMap()).sort((a, b) => b.starts_at.localeCompare(a.starts_at))
}
