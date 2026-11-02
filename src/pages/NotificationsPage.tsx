import { useNavigate } from 'react-router-dom'
import { ArrowLeft, Bell, CheckCheck } from 'lucide-react'
import { useMarkNotificationsRead, useNotifications } from '@/lib/api'
import { relativeTimeFromNow } from '@/lib/format'

export function NotificationsPage() {
  const navigate = useNavigate()
  const { data: notifications = [], isLoading } = useNotifications()
  const markRead = useMarkNotificationsRead()

  return (
    <div className="p-4 space-y-4 safe-top">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2.5">
          <button
            type="button"
            onClick={() => navigate(-1)}
            aria-label="Back"
            className="w-9 h-9 rounded-xl bg-surface-2 border border-line flex items-center justify-center"
          >
            <ArrowLeft className="w-4 h-4" />
          </button>
          <h1 className="text-xl font-bold">Notifications</h1>
        </div>
        {notifications.some((n) => !n.read_at) && (
          <button
            type="button"
            onClick={() => markRead.mutate(undefined)}
            className="btn-secondary h-8 px-3 text-xs"
          >
            <CheckCheck className="w-3.5 h-3.5 text-neon" />
            <span>Mark all read</span>
          </button>
        )}
      </div>

      {isLoading ? (
        <div className="space-y-2.5">
          {[1, 2, 3].map((n) => (
            <div key={n} className="card h-20 animate-pulse bg-surface-2" />
          ))}
        </div>
      ) : notifications.length === 0 ? (
        <div className="card p-8 text-center space-y-2">
          <Bell className="w-8 h-8 text-neon mx-auto" />
          <h3 className="text-base font-bold">All caught up</h3>
          <p className="text-xs text-muted max-w-xs mx-auto">
            Booking confirmations, 2-hour game reminders and join requests will appear here.
          </p>
        </div>
      ) : (
        <div className="space-y-2.5">
          {notifications.map((n) => (
            <button
              key={n.id}
              type="button"
              onClick={() => {
                if (!n.read_at) markRead.mutate(n.id)
                if (n.url) navigate(n.url)
              }}
              className={`w-full text-left card p-3.5 transition ${
                n.read_at ? 'opacity-75' : 'border-neon/40 bg-neon/5'
              }`}
            >
              <div className="flex items-center justify-between gap-2">
                <span className="text-sm font-bold text-text">{n.title}</span>
                <span className="text-[10px] text-muted shrink-0">
                  {relativeTimeFromNow(n.created_at)}
                </span>
              </div>
              <p className="text-xs text-muted mt-1">{n.body}</p>
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
