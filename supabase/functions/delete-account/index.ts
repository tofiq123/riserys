// Rise · Phase 5a · delete-account edge function
//
// Deletes the calling user's auth account. The `profiles` row is removed
// automatically by the ON DELETE CASCADE on `profiles.id`.
//
// The client calls this via `supabase.functions.invoke('delete-account')`,
// which forwards the user's JWT in the Authorization header. We:
//   1. identify the caller from that JWT (anon client, RLS-scoped), then
//   2. delete that user with the service-role key (admin client).
// The service-role key never leaves the server. `SUPABASE_URL`,
// `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are injected into every
// edge function by Supabase automatically — no manual secrets needed.
//
// Deploy with:  supabase functions deploy delete-account

import { createClient } from 'jsr:@supabase/supabase-js@2';

const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });

Deno.serve(async (req) => {
  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Missing Authorization header' }, 401);

    // A client scoped to the caller's JWT, used only to identify them.
    const caller = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user }, error: whoErr } = await caller.auth.getUser();
    if (whoErr || !user) return json({ error: 'Not authenticated' }, 401);

    // The admin client (service role) actually deletes the auth user; the
    // cascade on profiles.id removes their profile row.
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );
    const { error: delErr } = await admin.auth.admin.deleteUser(user.id);
    if (delErr) {
      // Log the detail server-side; return a generic message to the client
      // (matches the catch block below — never forward raw admin errors).
      console.error('delete-account admin.deleteUser failed:', delErr);
      return json({ error: 'Internal error' }, 500);
    }

    return json({ success: true }, 200);
  } catch (e) {
    // Log the detail server-side; return a generic message to the client.
    console.error('delete-account failed:', e);
    return json({ error: 'Internal error' }, 500);
  }
});
