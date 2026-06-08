# Nightshade Mobile — iOS release setup (Mac + Apple Developer steps)

This document is the human runbook for everything that **cannot** be done from
the Linux build agent and must be done on a Mac with Xcode and a paid Apple
Developer account. The repository already contains a fully-configured Xcode
project plus all the iOS/Dart code; this file lists the GUI steps that finish
the build, sign it, and ship it.

**Bundle id:** `com.nightshade.nightshadeMobile`
**App Group:** `group.com.nightshade.app`
**Workspace to open:** `apps/mobile/ios/Runner.xcworkspace` (always the
*workspace*, never the bare `.xcodeproj` — CocoaPods integrates through it).

> What the agent already did (no Mac needed, validated by review):
> - `Info.plist`: added `UIBackgroundModes` (`remote-notification`, `fetch`).
>   Live Activities keys, Bonjour, and usage strings were already present.
> - `Runner/Runner.entitlements`: added `aps-environment = development`, the
>   App Group `group.com.nightshade.app`, and kept the existing Critical Alerts
>   key.
> - `project.pbxproj`: set `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements`
>   on all three Runner build configs (Debug/Release/Profile). This is the one
>   build-setting edit; it was verified to keep the pbxproj structurally intact.
> - `AppDelegate.swift`: APNs registration + token forwarding over the
>   `nightshade/push` MethodChannel, plus foreground critical-alert
>   presentation.
> - Dart: `apps/mobile/lib/services/push_registration_service.dart` POSTs the
>   APNs token to the desktop's `POST /api/push/register-token` (`platform=apns`),
>   wired into the connect flow in `mobile_connection_ops.dart`.

---

## 0. Prerequisites

- A Mac with **Xcode 15+** and command-line tools.
- A **paid Apple Developer Program** membership ($99/yr). The free/personal
  team **cannot** ship App Groups, Push Notifications, or Critical Alerts — all
  three are used by this app.
- CocoaPods installed (`sudo gem install cocoapods` or via Homebrew).
- The repo checked out, with Flutter 3.44+ on PATH.

First-time bootstrap on the Mac:

```sh
cd apps/mobile
flutter pub get
flutter precache --ios
cd ios && pod install && cd -
```

`flutter build ios` regenerates `Flutter/Generated.xcconfig` and runs
`pod install`, so the project opens clean.

---

## 1. Signing team (required for any device build)

The pbxproj intentionally ships with `CODE_SIGN_STYLE = Automatic` and **no**
`DEVELOPMENT_TEAM` — the team is machine/account specific and must be set in the
GUI so it does not leak into the repo.

1. Open `apps/mobile/ios/Runner.xcworkspace`.
2. Select the **Runner** project → **Runner** target → **Signing &
   Capabilities**.
3. Pick your **Team** from the dropdown. Leave **Automatically manage signing**
   checked.
4. Confirm the **Bundle Identifier** reads `com.nightshade.nightshadeMobile`
   (or change it to one your team owns, and update it everywhere noted below).

Repeat the Team selection on every target you create in the sections that
follow (extensions inherit nothing automatically).

---

## 2. Capabilities on the Runner target

The entitlements **file** is already linked (the agent set
`CODE_SIGN_ENTITLEMENTS`). You still add the capabilities in the GUI so Xcode
registers them against the App ID in the developer portal and regenerates the
provisioning profile.

On **Runner → Signing & Capabilities → + Capability**, add:

1. **Push Notifications** — this is what makes `aps-environment` meaningful and
   enables APNs token issuance. Without it the device never gets a token.
2. **Background Modes** — tick **Remote notifications** and **Background fetch**
   (these mirror the `UIBackgroundModes` already in `Info.plist`).
3. **App Groups** — add `group.com.nightshade.app`. If the group does not exist
   yet, click the **+** inside the App Groups editor to create it; this also
   creates it in the developer portal.

The **Critical Alerts** entitlement is special — see §5. It will show as
present in the entitlements file but Apple must grant it before it does
anything.

After saving, re-open `Runner.entitlements` and confirm these keys survive:
`aps-environment`, `com.apple.security.application-groups`,
`com.apple.developer.usernotifications.critical-alerts`.

---

## 3. APNs server-side key (one-time, for the desktop)

The phone token is useless unless the desktop can authenticate to APNs to send
the push. The desktop's remote-push delivery
(`packages/nightshade_remote_protocol/lib/src/push/remote_push_delivery.dart`)
expects an APNs **token-based** auth key (`.p8`).

1. In <https://developer.apple.com> → **Certificates, Identifiers & Profiles**
   → **Keys** → **+**.
2. Name it `Nightshade APNs`, enable **Apple Push Notifications service (APNs)**,
   and **Continue → Register**.
3. **Download** the `.p8` (you can only download it once). Note the **Key ID**
   and your **Team ID**.
4. Configure the desktop push config with the `.p8` path, Key ID, Team ID, and
   the app's **Topic** = the bundle id `com.nightshade.nightshadeMobile`. See
   `packages/nightshade_remote_protocol/lib/src/push/push_config.dart` for the
   field names the desktop reads.

> APNs environment: development tokens (from a development build) only work
> against the APNs **sandbox** host; App Store / TestFlight builds use the
> **production** host. The `aps-environment` value flips automatically with the
> signing profile (see §6). The desktop delivery must target the host matching
> the build that produced the token.

---

## 4. Create the extension targets (Live Activity, Watch, App Intents)

The Swift sources exist on disk but are **not** Xcode targets yet. The build
agent deliberately did **not** add them — adding native targets is the kind of
pbxproj surgery that corrupts the project file. Create them in the GUI.

### 4a. Live Activity widget extension

Source: `apps/mobile/ios/NightshadeLiveActivity/` (`*.swift` + `Info.plist`,
already `com.apple.widgetkit-extension`).

1. **File → New → Target… → iOS → Widget Extension.**
2. Product Name: `NightshadeLiveActivity`. Project: `Runner`. **Include Live
   Activity: checked.** Include Configuration App Intent: unchecked.
3. Delete the boilerplate Swift + `Info.plist` Xcode generates inside the new
   group (keep the repo files).
4. **Add Files to "Runner"…** the three repo files
   (`NightshadeLiveActivityAttributes.swift`,
   `NightshadeLiveActivityWidget.swift`, `Info.plist`) with **target =
   NightshadeLiveActivity only**, **Copy items if needed = unchecked**.
5. Build Settings → set `INFOPLIST_FILE` to
   `NightshadeLiveActivity/Info.plist`.
6. Set the **Team** and ensure the deployment target is **iOS 16.2+** (the
   `ActivityContent` API the widget uses is 16.2-gated — matching the host's
   `@available(iOS 16.2, *)` guards in `AppDelegate.swift`).
7. `NightshadeLiveActivityAttributes` must be in **both** the Runner target and
   the extension target (the host requests the activity, the widget renders it).
   Add the attributes file to Runner's target membership too.

### 4b. watchOS app + complication

Follow the existing, detailed runbook verbatim:
**`apps/mobile/ios/NightshadeWatchComplication/SETUP.md`** (§1–7). It covers the
watch app shell, the widget extension, attaching the repo Swift files, and the
App Group on all watch targets. Nothing here supersedes it.

### 4c. App Intents (Siri) extension

Source: `apps/mobile/ios/NightshadeAppIntents/`
(`NightshadeAppIntents.swift` + `Info.plist`). Modern AppIntents do **not** use
the legacy `NSExtension` entry point — the framework auto-discovers `AppIntent`
types.

Two supported options:

- **Simplest — in-app intents (recommended):** add
  `NightshadeAppIntents.swift` directly to the **Runner** target (target
  membership checkbox). No separate extension target is needed; Siri/Shortcuts
  discover the intents from the app binary. Skip the extension.
- **Or a dedicated App Intents Extension:** **File → New → Target… → iOS → App
  Intents Extension**, name it `NightshadeAppIntents`, then add the repo Swift
  file (target = extension only) and set its `INFOPLIST_FILE`.

Either way, the extension/app must have the **App Group**
`group.com.nightshade.app` capability — `NightshadeAppIntents.swift` reads the
shared `UserDefaults(suiteName:)` and fails loudly without it.

### 4d. App Group on every extension

For each new target (Live Activity, Watch app, Watch complication, App Intents
if a separate target): **Signing & Capabilities → + Capability → App Groups →**
add `group.com.nightshade.app`. The host writes snapshots there; the extensions
read them. A missing group is a loud runtime failure by design.

---

## 5. Critical Alerts entitlement (Apple grant required)

Critical Alerts bypass Do Not Disturb / Focus / the silent switch to wake a
sleeping operator. The entitlement key is already in `Runner.entitlements`, but
**Apple must approve a written request** before it does anything.

The full runbook — including the verbatim justification text to paste into
Apple's form, the App ID capability toggle, and the "regenerate profiles after
the grant" step — lives in
**`apps/mobile/ios/CRITICAL_ALERTS_SETUP.md`** (§B, §C). Follow it.

Until granted, builds still succeed; iOS silently downgrades the alert level.
The in-app `IosBackgroundBanner` shows the "not granted" copy — ship that
honestly to TestFlight reviewers.

---

## 6. Provisioning profiles

With automatic signing, Xcode regenerates profiles as you add capabilities. If
you sign manually, after **any** capability change (Push, App Groups, Critical
Alerts grant) you must:

1. In the developer portal, open the App ID `com.nightshade.nightshadeMobile`
   and confirm **Push Notifications**, **App Groups**, and (once granted)
   **Critical Alerts** are enabled.
2. **Regenerate** all distribution and development profiles — the entitlements
   only flow through profiles regenerated *after* the capability is enabled.
3. Repeat for each extension's App ID (Live Activity, Watch, App Intents) — each
   gets its own App ID and profile.

`aps-environment` resolves from the profile: a **development** profile embeds
`development`, a **distribution** profile embeds `production`. Do not hard-code
`production` in the entitlements file — it would break development device
installs (the file ships `development` for exactly this reason).

---

## 7. Build, run, and verify

```sh
cd apps/mobile
flutter build ios --release          # device archive build
# or, on a connected device for dev:
flutter run --release -d <device-id>
```

Smoke tests (need a physical device — the Simulator has no APNs and ignores
entitlements):

- **APNs token registration:** pair the phone with a desktop, then connect.
  Watch the Xcode console / `os_log` for `[PushRegistration] Registered APNs
  token with <host>:<port>`. Cross-check the desktop log for `registered apns
  token for device=<id>` from `PushHandlers`.
- **Foreground critical alert:** with the app open, trigger a safety event on
  the desktop; the banner + sound should present (the `willPresent` override).
- **Background/asleep critical alert:** lock the phone, take it off the LAN
  (cellular only), trigger a safety event; the APNs push should wake it (needs
  the Critical Alerts grant + the desktop APNs key from §3).
- **Live Activity:** start a sequence; confirm the lock-screen / Dynamic Island
  activity appears (needs §4a + iOS 16.2+).
- **Watch complication / Siri intents:** per their SETUP docs.

---

## 8. TestFlight / App Store submission

1. **Xcode → Product → Archive** (scheme: Runner, Any iOS Device).
2. In the Organizer, **Distribute App → App Store Connect → Upload**. Let Xcode
   manage signing, or pick your distribution profile.
3. In **App Store Connect**:
   - Create the app record (bundle id `com.nightshade.nightshadeMobile`) if it
     does not exist.
   - Fill in the privacy nutrition labels — note the app uses **Local Network**,
     **Camera** (QR), **Photos** (save), and **Location** (celestial calc); the
     usage strings are already in `Info.plist`.
   - For Critical Alerts review, point reviewers at the dashboard's
     weather/safety panel and the sequencer safety-monitor config (Apple often
     asks for screenshots — see `CRITICAL_ALERTS_SETUP.md`).
4. Submit the build to **TestFlight** (internal first), then to App Review.

---

## Appendix — channel / endpoint contract (for reference)

| Piece | Where |
| --- | --- |
| APNs registration + token forward | `apps/mobile/ios/Runner/AppDelegate.swift` (`nightshade/push`, methods `registerForRemoteNotifications` / `getApnsToken`; host→Dart `onApnsToken` / `onApnsRegistrationError`) |
| Dart token POST | `apps/mobile/lib/services/push_registration_service.dart` → `POST /api/push/register-token` body `{deviceId, platform:"apns", token}` |
| Connect-flow wiring | `apps/mobile/lib/main_parts/mobile_connection_ops.dart` (`_registerPushTokenIfIos`) |
| Server endpoint | `apps/desktop/lib/headless_api/handlers/push_handlers.dart` (`handleRegisterToken`; accepts `platform ∈ {fcm, apns}`) |
| Entitlements | `apps/mobile/ios/Runner/Runner.entitlements` |
| Background modes | `apps/mobile/ios/Runner/Info.plist` (`UIBackgroundModes`) |
| Critical Alerts runbook | `apps/mobile/ios/CRITICAL_ALERTS_SETUP.md` |
| Watch setup | `apps/mobile/ios/NightshadeWatchComplication/SETUP.md` |

> Platform string note: the server validates `platform` against `{'fcm',
> 'apns'}`, **not** `{'ios','android'}`. iOS registers as **`apns`**. The
> `deviceId` MUST be the same id the device paired with
> (`MobilePairingService.deviceId()`), or the server returns `404
> unknown_device`.
