import { useEffect, useState } from 'react'
import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { Compass, Users, Ticket, Heart, User, WifiOff } from 'lucide-react'

const TABS = [
  { to: '/', label: 'Explore', icon: Compass, end: true },
  { to: '/games', label: 'Find Players', icon: Users, end: false },
  { to: '/bookings', label: 'Bookings', icon: Ticket, end: false },
  { to: '/saved', label: 'Saved', icon: Heart, end: false },
  { to: '/profile', label: 'Profile', icon: User, end: false },
]

export function Layout() {
  const [online, setOnline] = useState(() => (typeof navigator !== 'undefined' ? navigator.onLine : true))
  const navigate = useNavigate()

  useEffect(() => {
    const on = () => setOnline(true)
    const off = () => setOnline(false)
    window.addEventListener('online', on)
    window.addEventListener('offline', off)
    return () => {
      window.removeEventListener('online', on)
      window.removeEventListener('offline', off)
    }
  }, [])

  // Listen to Web Push click messages from service worker
  useEffect(() => {
    if (!('serviceWorker' in navigator)) return
    const handler = (event: MessageEvent) => {
      if (event.data?.type === 'NAVIGATE' && typeof event.data.url === 'string') {
        navigate(event.data.url)
      }
    }
    navigator.serviceWorker.addEventListener('message', handler)
    return () => navigator.serviceWorker.removeEventListener('message', handler)
  }, [navigate])

  return (
    <div className="min-h-dvh flex flex-col bg-ink text-text">
      {!online && (
        <div className="bg-warn/15 border-b border-warn/30 text-warn text-xs font-medium px-4 py-2 flex items-center justify-center gap-2">
          <WifiOff className="w-3.5 h-3.5 shrink-0" />
          <span>You’re offline. Your saved QR booking passes are still available in Bookings.</span>
        </div>
      )}

      <main className="flex-1 w-full max-w-2xl mx-auto pb-24">
        <Outlet />
      </main>

      {/* Bottom tab bar */}
      <nav className="fixed bottom-0 inset-x-0 z-40 bg-surface/95 backdrop-blur-md border-t border-line safe-bottom">
        <div className="max-w-2xl mx-auto grid grid-cols-5 h-16">
          {TABS.map(({ to, label, icon: Icon, end }) => (
            <NavLink
              key={to}
              to={to}
              end={end}
              className={({ isActive }) =>
                `flex flex-col items-center justify-center gap-1 text-[11px] font-medium transition ${
                  isActive ? 'text-neon' : 'text-muted hover:text-text'
                }`
              }
            >
              {({ isActive }) => (
                <>
                  <div
                    className={`px-3 py-1 rounded-full transition ${
                      isActive ? 'bg-neon/15 text-neon' : ''
                    }`}
                  >
                    <Icon className="w-4 h-4" />
                  </div>
                  <span>{label}</span>
                </>
              )}
            </NavLink>
          ))}
        </div>
      </nav>
    </div>
  )
}
