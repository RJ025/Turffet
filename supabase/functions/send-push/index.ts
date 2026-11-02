// Supabase Edge Function: send-push
// Triggered by the `notifications_dispatch_push` Postgres trigger via pg_net.
// Delivers Web Push notifications using VAPID keys.

import { createClient } from 'npm:@supabase/supabase-js@2'
import webpush from 'npm:web-push@3.6.7'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const VAPID_PUBLIC_KEY = Deno.env.get('VAPID_PUBLIC_KEY')!
const VAPID_PRIVATE_KEY = Deno.env.get('VAPID_PRIVATE_KEY')!
const VAPID_SUBJECT = Deno.env.get('VAPID_SUBJECT') || 'mailto:support@turffet.app'
const WEBHOOK_SECRET = Deno.env.get('PUSH_WEBHOOK_SECRET')

webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY)

Deno.serve(async (req) => {
  if (WEBHOOK_SECRET && req.headers.get('x-webhook-secret') !== WEBHOOK_SECRET) {
    return new Response('Unauthorized', { status: 401 })
  }

  const { notification_id } = await req.json()
  if (!notification_id) {
    return new Response(JSON.stringify({ error: 'notification_id required' }), { status: 400 })
  }

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)
  const { data: notif } = await admin
    .from('notifications')
    .select('*')
    .eq('id', notification_id)
    .maybeSingle()

  if (!notif) {
    return new Response(JSON.stringify({ ok: false, reason: 'not_found' }), { status: 404 })
  }

  const { data: subs } = await admin
    .from('push_subscriptions')
    .select('*')
    .eq('user_id', notif.user_id)

  let sent = 0
  for (const s of subs ?? []) {
    try {
      await webpush.sendNotification(
        {
          endpoint: s.endpoint,
          keys: { p256dh: s.p256dh, auth: s.auth },
        },
        JSON.stringify({
          title: notif.title,
          body: notif.body,
          url: notif.url || '/bookings',
        }),
      )
      sent++
    } catch (err: unknown) {
      const statusCode = (err as { statusCode?: number })?.statusCode
      if (statusCode === 404 || statusCode === 410) {
        await admin.from('push_subscriptions').delete().eq('id', s.id)
      }
    }
  }

  await admin
    .from('notifications')
    .update({ push_sent_at: new Date().toISOString() })
    .eq('id', notification_id)

  return new Response(JSON.stringify({ ok: true, sent }), {
    headers: { 'Content-Type': 'application/json' },
  })
})
