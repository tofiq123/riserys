# Rise Phase 5a — Supabase + Google sign-in setup

**What this unlocks:** an optional account (Google sign-in → a `profiles` row with a claimed username → sign out / delete account). Until you finish these steps, the app runs exactly as it does today — the alarm engine never touches the network, and the "Sign in" affordance stays hidden because no credentials are configured.

You'll produce **three values** and pass them to the build as `--dart-define`s:

| Value | Where it comes from |
|---|---|
| `SUPABASE_URL` | Supabase → Project Settings → API → Project URL |
| `SUPABASE_ANON_KEY` | Supabase → Project Settings → API → the **anon / publishable** key |
| `GOOGLE_SERVER_CLIENT_ID` | The **Web** OAuth client ID from Google Cloud (used for native ID-token sign-in) |

Nothing secret lives in the repo — these are supplied at build time only.

---

## 1. Create the Supabase project

1. Go to <https://supabase.com/dashboard> → **New project**. Pick a name, a strong database password, and a region close to your users.
2. When it's ready: **Project Settings → API**. Copy the **Project URL** (→ `SUPABASE_URL`) and the **anon / public** key (→ `SUPABASE_ANON_KEY`). *(Newer dashboards label this the "publishable" key — same value; the app passes it as the anon/publishable key.)*

## 2. Apply the database migration

1. Open **SQL Editor** → **New query**.
2. Paste the entire contents of `supabase/migrations/0001_profiles.sql` and **Run**.
3. Confirm under **Table Editor** that a `profiles` table exists with RLS enabled, and under **Database → Functions** that `username_available` exists.

*(CLI alternative: `supabase link --project-ref <ref>` then `supabase db push`.)*

## 3. Create the Google OAuth clients

Native Google sign-in on Android needs **two** OAuth clients in the same Google Cloud project: an **Android** client (authorizes the app) and a **Web** client (its ID is the audience of the ID token Supabase verifies).

1. Go to <https://console.cloud.google.com> → create/select a project.
2. **APIs & Services → OAuth consent screen**: choose **External**, fill in the app name, support email, and developer email. While testing you can leave it in *Testing* mode and add your Google account under **Test users**.
3. **APIs & Services → Credentials → Create credentials → OAuth client ID → Android**:
   - **Package name:** `com.riseapp.rise`
   - **SHA-1 fingerprint:** your signing cert's SHA-1 (see the box below).
4. **Create credentials → OAuth client ID → Web application** (name it e.g. "Rise Web / server"). **Copy its Client ID** — this is your `GOOGLE_SERVER_CLIENT_ID`. Also copy its **Client secret** (needed in step 4).

> **Getting your SHA-1**
> - **Debug builds:** `keytool -list -v -keystore "$HOME/.android/debug.keystore" -alias androiddebugkey -storepass android -keypass android` (on Windows PowerShell the keystore is at `$env:USERPROFILE\.android\debug.keystore`).
> - **Release builds:** run `keytool` against your release keystore, or use the **SHA-1** shown in Google Play Console → *Release → Setup → App signing* once you upload a build.
> - Add every SHA-1 you build/ship with (debug machine, release, Play App Signing) as separate Android OAuth clients or entries.

## 4. Enable Google in Supabase Auth

1. Supabase → **Authentication → Providers → Google** → enable.
2. Paste the **Web** client's **Client ID** and **Client secret** (from step 3.4).
3. In **Authorized Client IDs**, add the **Web** client ID (and, if present, the Android client ID) so Supabase accepts ID tokens minted for them. Save.

## 5. Deploy the delete-account function

The "Delete account" button calls a server function that removes the auth user (the `profiles` row cascades away).

```bash
supabase functions deploy delete-account
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are provided to the function automatically — you don't set any secrets. (If you skip this step, everything else works; only "Delete account" will error.)

## 6. Build with credentials and smoke-test on device

```bash
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://YOURREF.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

Install it (`adb install -r build/app/outputs/flutter-apk/app-release.apk`) and verify:

1. **Profile tab** now shows **"Sign in with Google"** (instead of the Guest card).
2. Tap it → pick your Google account → you land on **"Claim your handle"**.
3. Enter a username (3–20 chars, `a–z 0–9 _`); it should show **available** in green, then tap **Claim username**.
4. You return to the app; the Profile tab shows your **@handle** with **Sign out** and **Delete account**.
5. In Supabase → **Table Editor → profiles**, confirm a row appeared with your `id`, `username`, and `display_name`.
6. Sign out, sign back in with the same account → you should **skip** the claim screen (the row already exists).
7. (Optional) **Delete account** → type `DELETE` → confirm; the `profiles` row disappears and you're back to the signed-out Profile.

### Passing dart-defines in an IDE / Codemagic

- **VS Code:** add `"args": ["--dart-define=SUPABASE_URL=…", …]` to the launch config.
- **A `--dart-define-from-file`** JSON is cleaner for many keys: `flutter build apk --release --dart-define-from-file=rise.env.json` where `rise.env.json` holds the three keys. **Do not commit** that file.
- **Codemagic:** set the three as encrypted environment variables and reference them in the build's `--dart-define`s.

---

## Troubleshooting

- **Sign-in dialog closes immediately / `ApiException: 10`** — the SHA-1 or package name on the Android OAuth client doesn't match the build. Re-check step 3.3 (and add the Play App Signing SHA-1 for store builds).
- **"Sign in with Google" doesn't appear** — a `--dart-define` is missing/empty, so `SupabaseConfig.isConfigured` is false. All three must be non-empty.
- **Signed in but sent to claim every time** — the `profiles` insert is failing (check the migration ran and RLS policies exist) — the app treats "no row" as "not yet claimed".
- **Availability always says "available", then claim says taken** — the `username_available` function didn't deploy; re-run the migration. The claim still fails safely on the unique constraint.
- **Delete account errors** — the `delete-account` function isn't deployed (step 5).

## What's intentionally NOT here (later sub-plans)

Friends/crew, live status, push/FCM, nudges, leaderboard, cloud sync of stats/wake events, alarm gifts, voice clips, Apple/email sign-in. 5a is only the account foundation the rest builds on.
