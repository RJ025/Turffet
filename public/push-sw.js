/* global self, clients */
// Imported by the Workbox service worker (see vite.config.ts -> workbox.importScripts).

self.addEventListener('push', (event) => {
  let payload = {
    title: 'Turffet',
    body: 'You have an update on your booking.',
    url: '/bookings',
  }
  try {
    if (event.data) payload = { ...payload, ...event.data.json() }
  } catch {
    if (event.data) payload.body = event.data.text()
  }

  event.waitUntil(
    self.registration.showNotification(payload.title, {
      body: payload.body,
      icon: '/icons/icon-192.png',
      badge: '/icons/favicon-48.png',
      data: { url: payload.url || '/' },
      vibrate: [120, 60, 120],
    }),
  )
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const targetUrl = (event.notification.data && event.notification.data.url) || '/'
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
      for (const client of windowClients) {
        if ('focus' in client) {
          client.postMessage({ type: 'NAVIGATE', url: targetUrl })
          return client.focus()
        }
      }
      if (clients.openWindow) return clients.openWindow(targetUrl)
    }),
  )
})
