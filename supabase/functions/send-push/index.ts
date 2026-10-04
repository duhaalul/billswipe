import { createClient } from 'npm:@supabase/supabase-js@2';
import { SignJWT, importPKCS8 } from 'npm:jose@6';

// Only a database webhook with the separate secret may invoke this function.
Deno.serve(async (request: Request) => {
  const secret = Deno.env.get('PUSH_WEBHOOK_SECRET');
  if (!secret || request.headers.get('x-push-secret') !== secret) return new Response('Unauthorized', { status: 401 });
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  try {
    const payload = await request.json();
    if (payload.type !== 'INSERT' || payload.schema !== 'public' || payload.table !== 'notifications' || !payload.record?.id) {
      return new Response('Invalid event', { status: 400 });
    }
    const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
    const { data: notice, error } = await db.from('notifications').select('id,user_id,is_read').eq('id', payload.record.id).single();
    if (error || !notice) return new Response('Notification missing', { status: 404 });
    if (notice.is_read) return Response.json({ skipped: 'already_read' });
    const { data: devices, error: devicesError } = await db.from('push_devices').select('token').eq('user_id', notice.user_id);
    if (devicesError) throw devicesError;
    if (!devices?.length) return Response.json({ sent: 0 });
    const account = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT')!);
    const key = await importPKCS8(account.private_key, 'RS256');
    const assertion = await new SignJWT({ scope: 'https://www.googleapis.com/auth/firebase.messaging' })
      .setProtectedHeader({ alg: 'RS256' }).setIssuer(account.client_email)
      .setAudience('https://oauth2.googleapis.com/token').setIssuedAt().setExpirationTime('1h').sign(key);
    const auth = await fetch('https://oauth2.googleapis.com/token', { method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }) });
    if (!auth.ok) throw new Error('FCM authentication failed');
    const { access_token } = await auth.json();
    let sent = 0, failed = 0;
    for (const device of devices) {
      const response = await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
        method: 'POST', headers: { Authorization: `Bearer ${access_token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: { token: device.token,
          // Generic lock-screen text avoids exposing names or amounts on shared devices.
          notification: { title: 'BillSwipe', body: 'Ada pembaruan untuk akun Anda. Buka aplikasi untuk melihatnya.' },
          data: { user_id: notice.user_id, notification_id: notice.id },
          android: { priority: 'high', ttl: '3600s', notification: { tag: notice.id, icon: 'ic_stat_billswipe', color: '#3B82F6' } },
        } }),
      });
      if (response.ok) { sent++; continue; }
      failed++;
      const body = await response.json();
      if (body.error?.details?.some((d: { errorCode?: string }) => d.errorCode === 'UNREGISTERED')) {
        await db.from('push_devices').delete().eq('token', device.token);
      }
    }
    return Response.json({ sent, failed }, { status: failed ? 502 : 200 });
  } catch (_) {
    console.error('Push delivery failed. Check Firebase credentials and configuration.');
    return new Response('Push delivery failed', { status: 500 });
  }
});
