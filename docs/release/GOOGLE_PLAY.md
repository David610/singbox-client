# Google Play compliance checklist

Same rule as `docs/release/APPLE.md`: every privacy/store-questionnaire
answer below must reflect this app's actual behavior. Items verifiable
directly from the repository are marked `[x]` with their source cited;
everything requiring a business/legal decision is `[ ]` with a
`TODO(you):` placeholder — not guessed here.

## Organization Play Console account

- [ ] Enroll a [Google Play Console](https://play.google.com/console) **Organization** account (not a personal/individual one) — a $25 one-time registration fee, but organization accounts get faster access to restricted-permission declarations and are what most Play policy guidance assumes for an app requesting `ACCESS_BACKGROUND_LOCATION` (see below).
      `TODO(you):` record the enrolled organization name and account owner here.
- [ ] Create a service account for CI uploads (**Play Console → Setup → API access → Create new service account**, following the linked Google Cloud Console flow), grant it at minimum "Release manager" access to this specific app, download its JSON key, and store it as the `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` secret — see `docs/release/RELEASE_CHECKLIST.md` "Secrets to configure".
- [ ] Confirm the package name matches `ANDROID_PACKAGE_NAME` in `.github/workflows/release.yml` (`com.nebula.karing` as of this audit — update both places together if/when this fork rebrands, `docs/FORK_ARCHITECTURE_AUDIT.md` §10).

### Service account setup (detail)

1. Play Console → **Setup → API access** → link (or create) a Google
   Cloud project.
2. In that Google Cloud project, **IAM & Admin → Service Accounts →
   Create Service Account**.
3. Back in Play Console's API access page, grant that service account
   access, scoped to **this app only**, with the **Release manager**
   permission preset (or a custom role with exactly: view app
   information, manage production/internal/alpha/beta releases — do not
   grant "Admin" or account-wide access for a CI credential).
4. Generate a JSON key for the service account (Google Cloud Console →
   the service account → Keys → Add Key → JSON), download it, and
   immediately store its content as the `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`
   GitHub secret — then delete the local copy.

## `VpnService` declaration

- [x] **Already implemented and declared** — verified directly:
  `packages/vpn_core/android/src/main/AndroidManifest.xml` declares
  `SingBoxVpnService` with `android:permission="android.permission.BIND_VPN_SERVICE"`
  and an `<intent-filter>` for `android.net.VpnService`
  (`packages/vpn_core/android/src/main/kotlin/.../SingBoxVpnService.kt`
  is the real implementing class — see `docs/ARCHITECTURE.md` §6).
- [ ] Play Console's app content questionnaire (Policy → App content) has
  a specific "VPN service" declaration under sensitive permissions —
  complete it truthfully once the app is otherwise ready to submit;
  Google reviews VPN apps' actual behavior against this declaration.

## Prominent disclosure

This app's manifest requests several permissions Google treats as
requiring **prominent in-app disclosure** (shown to the user, in context,
before the permission is used — not buried in a privacy policy alone) —
verified directly from `android/app/src/main/AndroidManifest.xml`:

| Permission | Why it needs disclosure |
|---|---|
| `ACCESS_BACKGROUND_LOCATION` | Google's most heavily scrutinized permission category — requires a separate Play Console "Background location" declaration form, a demonstrated in-app feature that needs it, AND prominent disclosure shown at the point of request |
| `ACCESS_FINE_LOCATION` / `ACCESS_COARSE_LOCATION` | Same disclosure expectation, lighter review than background location alone |
| `CAMERA` | Used for the QR-code scanning UI in Karing's existing codebase (`zxing2`/`qr_code_scanner_plus` in `pubspec.yaml`) — `TODO(you):` confirm this is the only camera use once that UI is reachable again (`docs/ARCHITECTURE.md` §9) |
| `QUERY_ALL_PACKAGES` | Requires its own Play Console declaration form (Policy → App content → "All apps that use this permission") with a justified use case — per-app VPN routing/exclusion (letting the user pick which installed apps go through the tunnel) is the plausible legitimate use here, but `TODO(you):` confirm against the actual reconstructed per-app-routing feature once it exists |

- [ ] `TODO(you):` implement the actual disclosure UI — same status as
  the iOS "pre-use VPN data disclosure" screen in `docs/release/APPLE.md`:
  not yet built, because the screens that would host it are part of the
  still-unreconstructed UI layer (`docs/ARCHITECTURE.md` §9).
- [ ] Complete the corresponding Play Console declaration forms for
  background location and `QUERY_ALL_PACKAGES` (Policy → App content) —
  each requires a specific written justification tied to an actual,
  reviewable in-app feature.

## Data Safety form

**Not filled in here** — same reasoning as Apple's App Privacy answers.
Worksheet, not answers:

| Data Safety question (paraphrased) | Where the real answer lives |
|---|---|
| Does the app collect approximate or precise location? | Permission is requested (see table above) for Wi-Fi SSID/BSSID-based routing rules, per the shared iOS usage-description string — `TODO(you):` confirm actual collection/transmission behavior once the networking layer is reconstructed, and answer based on that, not the permission's mere presence |
| Does the app collect personal info (email, user IDs, etc.)? | Depends on whether/how a subscription-token or account system is implemented — not present in what's currently reconstructed; re-check before submission |
| Does the app collect app activity / diagnostics? | `packages/vpn_core`'s diagnostics module (`docs/DEVICE_ACCEPTANCE.md`) only produces data on explicit user export — state this precisely, same guidance as Apple's App Privacy worksheet |
| Is data encrypted in transit? | Yes for the VPN tunnel itself (VLESS+REALITY / Hysteria2, both TLS-based — `docs/ARCHITECTURE.md` §4) — but this question is about the app's OWN network calls (e.g. subscription fetch), which needs its own answer once that code exists |
| Does the app allow users to request data deletion? | Depends entirely on whether any server-side account/data storage exists — likely N/A if this app only talks to a user-configured third-party server, but confirm before answering "not applicable" |

## 90-second review video

Google requires a short (typically ~30–90 second) demo video in Play
Console's app content submission for apps requesting sensitive
permissions this app requests (background location, `QUERY_ALL_PACKAGES`)
— confirm the current exact requirement in Play Console at submission
time, since Google's specific thresholds change.

- [ ] `TODO(you):` record a real screen capture showing: granting the VPN
  permission, connecting, the app's actual state while connected, and
  (if implemented by then) the per-app routing / background-location-use
  feature actually functioning — Google reviewers watch this to confirm
  the permission is genuinely used for what's declared, not requested
  speculatively. Do not submit a generic/stock video; it must be this
  app's real screen.

## Store listing disclosure of `VpnService` use

- [ ] The Play Store listing description itself (not just the Data
  Safety form) should plainly state this is a VPN client and briefly
  describe what routing it performs — Play policy expects a VPN app's
  purpose to be clear from the listing, not just the technical
  declaration form.
- [ ] `TODO(you):` draft the actual store listing copy — out of scope for
  this document (it's marketing/product copy, not a compliance
  checklist item with a verifiable-from-code answer), but note it here
  as a required release-blocking task.

## Target initially: Internal Testing, then Closed Testing

Matches `.github/workflows/release.yml`'s actual behavior — verified
against the workflow file, not aspirational:

1. Every tagged release automatically uploads to the **Internal Testing**
   track via `scripts/release/upload_google_play.py --track internal`
   (the script hard-allowlists `internal`/`alpha`/`beta` — it cannot
   target `production`, structurally).
2. **Manual**: in Play Console, promote a specific internal-testing
   release to **Closed Testing** once it's been validated (including the
   physical-device acceptance sign-off, `docs/DEVICE_ACCEPTANCE.md`).
3. **Manual**: after Closed Testing (Google also requires a minimum
   number of testers over a minimum period for some app categories before
   allowing a first production release — check current Play Console
   requirements for this app's category), promote to **Production**.

Neither step 2 nor step 3 is automated by this pipeline, by design — see
`docs/release/RELEASE_CHECKLIST.md`.
