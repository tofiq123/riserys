# Rise Phase 5d — Push / nudges setup (Firebase + Supabase)

**Prerequisite:** Phases 5a–5c + 5e wired and working. 5d adds push notifications, which need a **Firebase project** (for FCM) in addition to your Supabase project.

You'll produce three things: a **`google-services.json`** (client, for the build), a **Firebase service-account key** (server secret, for sending), and the **`0005_push.sql`** migration.

---

## 1. Firebase project + Android app → `google-services.json` (unblocks the build)

1. **https://console.firebase.google.com** → **Add project** → name `Rise` (Analytics optional). *Or reuse an existing project.*
2. In the project → **Add app → Android**:
   - **Package name:** `com.riseapp.rise`
   - **Debug SHA-1:** `1E:09:84:00:C3:9C:A1:E0:ED:EA:F6:76:B3:B0:F4:8C:CE:69:A5:06` (same as the Google sign-in setup)
   - Register.
3. **Download `google-services.json`** → place it at **`android/app/google-services.json`** (gitignored). You can skip Firebase's "add the Firebase SDK" Gradle snippet steps — Rise's Android build already wires the `google-services` plugin + `firebase_messaging`, so the file is all it needs.
4. Firebase → **Build → Cloud Messaging** → make sure the **Firebase Cloud Messaging API (V1)** is enabled (usually on by default).

## 2. Service-account key → Supabase secret (for the send-nudge function)

1. Firebase → **Project settings** (gear) → **Service accounts** → **Generate new private key** → downloads a JSON. **This is a real secret** — never commit it or put it in the app.
2. Set it as a Supabase edge-function secret (from the repo root):
   ```bash
   supabase secrets set FCM_SERVICE_ACCOUNT="$(cat /path/to/service-account.json)" --project-ref gnhaqkkwjkzkftnrojom
   ```
   (Or paste the JSON contents into Supabase → Edge Functions → Secrets as `FCM_SERVICE_ACCOUNT`.)

## 3. Apply the migration

Supabase → SQL Editor → run `supabase/migrations/0005_push.sql` (creates `device_tokens` + `nudges` with RLS).

## 4. Deploy the function

```bash
supabase functions deploy send-nudge --project-ref gnhaqkkwjkzkftnrojom
```

## 5. Build + install

Once `google-services.json` is in place, the app is rebuilt with `firebase_messaging`:
```bash
flutter build apk --release --dart-define-from-file=rise.env.json
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## 6. Two-device nudge smoke test

Accounts **A** and **B**, accepted crew, each signed in on a device (a second phone/emulator for B).

1. Each app, once signed in, registers its FCM token — confirm a row per user in **Table Editor → device_tokens**.
2. On **A**'s **Crew** tab, on **B**'s row, tap **Nudge**.
3. Within a couple seconds **B's device** gets a push: **"@a is nudging you to wake up 👋"**. Tapping it opens Rise.
4. Immediately tap **Nudge** again on A → you should get **"You just nudged them — give it a minute."** (the 5-minute rate limit).
5. Nudging someone who isn't your crew (or yourself) is rejected server-side.

### What to check in the database
- `device_tokens` rows for signed-in users; `nudges` rows appear as you send.
- Rate-limit + crew checks happen in the function (service role); the client only sees the success/rejection message.

## Troubleshooting

- **App won't build after adding firebase_messaging** — `android/app/google-services.json` is missing or misplaced. It must be exactly there.
- **"They don't have notifications set up yet."** — the target has no `device_tokens` row: they haven't opened the app signed-in since 5d shipped, or token registration failed (check notification permission on their device).
- **Nudge sends but no push arrives** — the FCM V1 API isn't enabled, or `FCM_SERVICE_ACCOUNT` is wrong/missing (redeploy after setting it); check the function logs in the Supabase dashboard.
- **"You can only nudge your crew."** — the friendship isn't `accepted`.
- **Push arrives but tapping doesn't open the right place** — the app routes `data.type == 'nudge'` to the Crew tab; a cold start may just open Home (acceptable for v1).

## What's NOT in 5d (later)

Alarm-gifts (send a specific alarm/sound), voice-clips, auto-nudges when a friend sleeps through (a triggered variant), iOS push (APNs — with the iOS engine), nudge history UI.
