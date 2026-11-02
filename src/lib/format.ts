const TZ = 'Asia/Kolkata'

const inr = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 })
export const formatINR = (n: number | null | undefined) => (n == null ? '-' : inr.format(n))

const timeFmt = new Intl.DateTimeFormat('en-IN', { timeZone: TZ, hour: 'numeric', minute: '2-digit', hour12: true })
export const formatTime = (iso: string | Date) => timeFmt.format(new Date(iso)).replace(':00', '').toLowerCase()

const timeFmtFull = new Intl.DateTimeFormat('en-IN', { timeZone: TZ, hour: 'numeric', minute: '2-digit', hour12: true })
export const formatTimeFull = (iso: string | Date) => timeFmtFull.format(new Date(iso)).toLowerCase()

const dayFmt = new Intl.DateTimeFormat('en-IN', { timeZone: TZ, weekday: 'short', day: 'numeric', month: 'short' })
export const formatDay = (iso: string | Date) => dayFmt.format(new Date(iso))

const longDayFmt = new Intl.DateTimeFormat('en-IN', { timeZone: TZ, weekday: 'long', day: 'numeric', month: 'long' })
export const formatLongDay = (iso: string | Date) => longDayFmt.format(new Date(iso))

export const formatRange = (start: string, end: string) => `${formatTime(start)} – ${formatTime(end)}`

/** YYYY-MM-DD for a date in IST */
export function istDateKey(d: Date = new Date()): string {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit' }).format(d)
  return parts // en-CA gives YYYY-MM-DD
}

/** Next N days (IST) as { key, label, sub } */
export function nextDays(n: number) {
  const out: { key: string; weekday: string; day: string; month: string; isToday: boolean }[] = []
  const now = new Date()
  for (let i = 0; i < n; i++) {
    const d = new Date(now.getTime() + i * 86400000)
    const key = istDateKey(d)
    const wd = new Intl.DateTimeFormat('en-IN', { timeZone: TZ, weekday: 'short' }).format(d)
    const day = new Intl.DateTimeFormat('en-IN', { timeZone: TZ, day: 'numeric' }).format(d)
    const month = new Intl.DateTimeFormat('en-IN', { timeZone: TZ, month: 'short' }).format(d)
    out.push({ key, weekday: i === 0 ? 'Today' : i === 1 ? 'Tmrw' : wd, day, month, isToday: i === 0 })
  }
  return out
}

/** '06:00:00' → '6 am' */
export function formatClock(t: string | null | undefined) {
  if (!t) return ''
  const [hS, mS] = t.split(':')
  let h = Number(hS)
  const m = Number(mS)
  if (h === 24) h = 0
  const suffix = h >= 12 ? 'pm' : 'am'
  const h12 = h % 12 === 0 ? 12 : h % 12
  if (t.startsWith('24')) return '12 am'
  return m ? `${h12}:${String(m).padStart(2, '0')} ${suffix}` : `${h12} ${suffix}`
}

export function relativeTimeFromNow(iso: string) {
  const diff = new Date(iso).getTime() - Date.now()
  const mins = Math.round(diff / 60000)
  const abs = Math.abs(mins)
  const rtf = new Intl.RelativeTimeFormat('en', { numeric: 'auto' })
  if (abs < 60) return rtf.format(mins, 'minute')
  if (abs < 60 * 24) return rtf.format(Math.round(mins / 60), 'hour')
  return rtf.format(Math.round(mins / 1440), 'day')
}

export function initials(name: string | null | undefined) {
  if (!name) return '🙂'
  return name
    .split(' ')
    .filter(Boolean)
    .slice(0, 2)
    .map((s) => s[0]!.toUpperCase())
    .join('')
}

export function directionsUrl(lat: number, lng: number) {
  return `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}`
}

export function whatsappUrl(phone: string, text?: string) {
  const digits = phone.replace(/\D/g, '')
  return `https://wa.me/${digits}${text ? `?text=${encodeURIComponent(text)}` : ''}`
}

export const SKILL_LABEL: Record<string, string> = {
  beginner: 'Beginner',
  intermediate: 'Intermediate',
  advanced: 'Advanced',
}
