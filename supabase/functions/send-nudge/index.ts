// Rise · Phase 5d · send-nudge edge function (typed copy — see README.md)
//
// A crew member's app invokes this with {to: <userId>, kind?: <enum>}.
// This function (server-side):
//   1. identifies the caller from their JWT,
//   2. validates `kind` against a fixed allowlist (400 on anything else),
//   3. verifies an ACCEPTED friendship between caller and target,
//   4. rate-limits (one push per caller→target per 5 minutes, from the
//      `nudges` log; `voice` may bypass — see the check below),
//   5. reads the target's FCM device tokens (service role),
//   6. sends an FCM HTTP v1 push to each token with SERVER-composed copy,
//   7. logs the send.
//
// SECURITY: the notification text is 100% server-controlled. The client sends
// only an enum `kind`; the title/body are composed HERE from a fixed copy map.
// Never accept free text from the request body — that is a push-injection
// vector (an attacker could make Rise display arbitrary notifications).
//
// Secrets: SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are
// injected automatically. FCM_SERVICE_ACCOUNT (the Firebase service-account
// JSON, as a string) must be set:  supabase secrets set FCM_SERVICE_ACCOUNT=@sa.json
//
// Deploy:  supabase functions deploy send-nudge --project-ref gnhaqkkwjkzkftnrojom

import { createClient } from 'jsr:@supabase/supabase-js@2';

const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });

const NUDGE_COOLDOWN_MS = 5 * 60 * 1000;
// A `voice` push may bypass the shared cooldown only when a voice_clips row
// from caller→target was created within this window (see the check below).
const VOICE_CLIP_WINDOW_MS = 2 * 60 * 1000;

// The only kinds a client may request. Anything else is a 400 — the request
// can steer WHICH message is sent, never WHAT it says.
const KINDS = ['nudge', 'voice', 'backup', 'sos'] as const;
type Kind = (typeof KINDS)[number];

// The full copy map. `handle` is the SENDER's username, read server-side from
// `profiles` — the one dynamic fragment, and it is our own validated column,
// never request text.
const COPY: Record<Kind, (handle: string) => { title: string; body: string }> = {
  nudge: (h) => ({
    title: 'Wake-up nudge 👋',
    body: `@${h} is nudging you awake.`,
  }),
  voice: (h) => ({
    title: 'New voice clip 🎙️',
    body: `@${h} sent you a wake-up clip — open Rise to listen.`,
  }),
  backup: (h) => ({
    title: 'Crew update 💪',
    body: `@${h} slipped today and is back on it — cheer them on.`,
  }),
  sos: (h) => ({
    title: `@${h} can't wake up 🚨`,
    body: 'They asked the crew for backup — give them a shout.',
  }),
};

function base64url(bytes: Uint8Array): string {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

function base64urlJson(obj: unknown): string {
  return base64url(new TextEncoder().encode(JSON.stringify(obj)));
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '');
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
}

// Mints an OAuth2 access token for FCM HTTP v1 from a service-account JSON.
async function getAccessToken(
  sa: { client_email: string; private_key: string },
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const unsigned =
    `${base64urlJson({ alg: 'RS256', typ: 'JWT' })}.` +
    base64urlJson({
      iss: sa.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    });
  const key = await importPrivateKey(sa.private_key);
  const sig = new Uint8Array(
    await crypto.subtle.sign(
      'RSASSA-PKCS1-v1_5',
      key,
      new TextEncoder().encode(unsigned),
    ),
  );
  const assertion = `${unsigned}.${base64url(sig)}`;
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body:
      'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=' +
      assertion,
  });
  const data = await res.json();
  if (!data.access_token) throw new Error('FCM token exchange failed');
  return data.access_token as string;
}

Deno.serve(async (req) => {
  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Not authenticated' }, 401);

    const { to, kind: kindRaw } = await req
      .json()
      .catch(() => ({ to: null, kind: null }));
    // Validate `to` is a UUID BEFORE it is used anywhere — it is spliced into a
    // PostgREST `.or()` filter string below, so an unvalidated value would be a
    // filter-injection / authorization-bypass vector. A real uuid can never
    // contain the filter grammar's meta-characters.
    const uuidRe =
        /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!to || typeof to !== 'string' || !uuidRe.test(to)) {
      return json({ error: 'Missing target' }, 400);
    }

    // Validate `kind` against the fixed allowlist. Absent → 'nudge' (backward
    // compat with pre-typed clients); anything not on the list → 400. The kind
    // selects a server-side copy entry and is never echoed into the message.
    if (
      kindRaw != null &&
      (typeof kindRaw !== 'string' || !(KINDS as readonly string[]).includes(kindRaw))
    ) {
      return json({ error: 'Unknown kind' }, 400);
    }
    const kind: Kind = (kindRaw as Kind | null | undefined) ?? 'nudge';

    // Identify the caller from their JWT.
    const caller = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user }, error: whoErr } = await caller.auth.getUser();
    if (whoErr || !user) return json({ error: 'Not authenticated' }, 401);
    const me = user.id;
    if (to === me) return json({ error: "You can't nudge yourself." }, 400);

    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Must be accepted crew.
    const { data: friendship } = await admin
      .from('friendships')
      .select('id')
      .eq('status', 'accepted')
      .or(
        `and(requester.eq.${me},addressee.eq.${to}),` +
        `and(requester.eq.${to},addressee.eq.${me})`,
      )
      .maybeSingle();
    if (!friendship) return json({ error: 'You can only nudge your crew.' }, 403);

    // Rate limit: one push per caller→target per cooldown, computed from the
    // `nudges` log. The log has no kind column and we deliberately add none
    // (no schema change in this pass) — so v1 is ONE SHARED per-pair bucket
    // for every kind. Fail CLOSED — if the count query errors we must not
    // silently skip the limit (a `count` of undefined would otherwise pass
    // the `> 0` check and send anyway).
    //
    // Exception: `voice` may bypass the shared bucket, but ONLY when a
    // voice_clips row from caller→target was created in the last 2 minutes.
    // That row is SERVER truth (its INSERT is RLS-gated on ownership +
    // accepted friendship, and creating one costs a real audio upload) — not
    // a client claim — so the bypass can't be farmed for push spam without
    // actually sending clips. The bypass check itself also fails CLOSED: on a
    // query error we fall back to the shared limit rather than skip it.
    const since = new Date(Date.now() - NUDGE_COOLDOWN_MS).toISOString();
    const { count, error: countErr } = await admin
      .from('nudges')
      .select('id', { count: 'exact', head: true })
      .eq('from_user', me)
      .eq('to_user', to)
      .gte('created_at', since);
    if (countErr) {
      console.error('send-nudge rate-limit query failed:', countErr);
      return json({ error: 'Internal error' }, 500);
    }
    if ((count ?? 0) > 0) {
      let voiceBypass = false;
      if (kind === 'voice') {
        const clipSince =
          new Date(Date.now() - VOICE_CLIP_WINDOW_MS).toISOString();
        const { count: clips, error: clipErr } = await admin
          .from('voice_clips')
          .select('id', { count: 'exact', head: true })
          .eq('owner_id', me)
          .eq('target_id', to)
          .gte('created_at', clipSince);
        if (clipErr) {
          console.error('send-nudge voice-bypass query failed:', clipErr);
        }
        voiceBypass = !clipErr && (clips ?? 0) > 0;
      }
      if (!voiceBypass) {
        return json({ error: 'You just nudged them — give it a minute.' }, 429);
      }
    }

    // Target's devices.
    const { data: tokens } = await admin
      .from('device_tokens')
      .select('token')
      .eq('user_id', to);
    if (!tokens || tokens.length === 0) {
      return json({ error: "They don't have notifications set up yet." }, 404);
    }

    // Caller handle for the message — read server-side from profiles, never
    // taken from the request.
    const { data: profile } = await admin
      .from('profiles')
      .select('username')
      .eq('id', me)
      .maybeSingle();
    const handle = profile?.username ?? 'A friend';
    const copy = COPY[kind](handle);

    // Send via FCM HTTP v1. Count only real 2xx deliveries (a `fetch` resolves
    // for a 4xx too), and prune tokens FCM reports as gone (404 UNREGISTERED).
    const sa = JSON.parse(Deno.env.get('FCM_SERVICE_ACCOUNT')!);
    const accessToken = await getAccessToken(sa);
    let sent = 0;
    const stale: string[] = [];
    await Promise.all(
      tokens.map(async (t: { token: string }) => {
        try {
          const resp = await fetch(
            `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
            {
              method: 'POST',
              headers: {
                Authorization: `Bearer ${accessToken}`,
                'Content-Type': 'application/json',
              },
              body: JSON.stringify({
                message: {
                  token: t.token,
                  notification: {
                    title: copy.title,
                    body: copy.body,
                  },
                  // `type` kept for any pre-typed reader; `kind` is the typed
                  // field the app routes on.
                  data: { type: kind, kind },
                  android: { priority: 'high' },
                },
              }),
            },
          );
          if (resp.ok) {
            sent++;
          } else if (resp.status === 404) {
            stale.push(t.token); // token no longer registered
          }
        } catch (_) {
          // network error — leave the token, it may work next time
        }
      }),
    );

    if (stale.length > 0) {
      await admin
        .from('device_tokens')
        .delete()
        .eq('user_id', to)
        .in('token', stale);
    }

    // Nothing was delivered — don't consume the rate limit; let them retry.
    if (sent === 0) {
      return json({ error: "Couldn't reach their devices right now." }, 502);
    }

    // Log the send (basis for the rate limit) only after a real delivery.
    // EVERY kind logs — including a bypassing `voice` — so the shared bucket
    // stays conservatively full; a follow-up clip re-earns its own bypass via
    // a fresh voice_clips row, and everything else waits out the cooldown.
    await admin.from('nudges').insert({ from_user: me, to_user: to });
    return json({ success: true, sent }, 200);
  } catch (e) {
    console.error('send-nudge failed:', e);
    return json({ error: 'Internal error' }, 500);
  }
});
