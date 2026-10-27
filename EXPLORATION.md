# fēnix 8 Pro: how far can it be modified?

An exploration of what we can build for the **Garmin fēnix 8 Pro** (non-solar:
47 mm AMOLED, 51 mm AMOLED, and the 51 mm MicroLED) and where Garmin draws the
line. Researched late October 2026.

**Confidence markers used below**

- ✅ confirmed by several independent sources, or long-standing Connect IQ behaviour
- ⚠️ reported by one source or by forum posts; check it in the SDK Manager or
  on the device before relying on it

---

## 1. TL;DR

- **The only supported way to run our own code on the watch is Connect IQ (CIQ).**
  CIQ apps are written in **Monkey C**, compiled to bytecode, and run in a
  sandboxed VM. There is no native SDK, no root access and no custom firmware.
  Firmware is signed by Garmin. ✅
- CIQ supports five kinds of app. Ordered from most to least constrained:
  **watch face → data field → glance/widget → device app → audio content provider**.
  Watch faces are the most locked down. Device apps can reach GPS, sensors,
  BLE, the network and FIT recording. ✅
- Every fēnix 8 Pro is **non-solar**, so the "non-solar" requirement holds
  automatically. All variants share a **454×454 round touch display** ✅. The
  SDK exposes them under a **single device ID, `fenix8pro47mm`** ✅ (SDK 9.3.0
  lists "fēnix® 8 Pro 47mm / 51mm / MicroLED / quatix® 8 Pro" as one entry).
- The fēnix 8 family is on the **current platform generation**: Connect IQ 9,
  API level 6.0 ⚠️. The newest SDK is **9.3.0** (20 Oct 2026). It lets apps
  use the **microphone, the speaker and LTE**, and Garmin explicitly lists the
  fēnix 8 Pro for all three ⚠️.
- The fēnix 8 Pro has real **LTE and inReach satellite** hardware. As of SDK 9.3,
  CIQ apps can bring LTE up themselves for web requests ⚠️. Satellite messaging
  is **not** exposed to apps.
- The biggest constraints are **memory** (about 128 KB for a watch face or
  data field ⚠️), the **AMOLED always-on rules** (at most 10 % of pixels lit,
  no pixel lit for more than 3 minutes ✅), and **background tasks** (at most
  once every 5 minutes, about 30 seconds each ✅).

---

## 2. The device

| | fēnix 8 Pro 47 mm | fēnix 8 Pro 51 mm | fēnix 8 Pro MicroLED 51 mm |
|---|---|---|---|
| Display | AMOLED, 1.4" | AMOLED, 1.4" | MicroLED, about 4,500 nits |
| Resolution | 454×454 ✅ | 454×454 ✅ | 454×454 ⚠️ |
| Touch | yes, plus 5 buttons | yes | yes |
| Solar | **no** | **no** | **no** |
| Battery, smartwatch mode | up to 27 days (AOD off) | up to 27 days | up to 10 days |
| Connectivity | BT, Wi-Fi, LTE, inReach satellite | same | same |
| Speaker / mic | yes | yes | yes |
| CIQ device ID | `fenix8pro47mm` ✅ (one ID covers all three, plus the quatix 8 Pro) | ← | ← |
| Launcher icon | 65×65 ⚠️ | ← | ← |

The regular fēnix 8 47 mm uses a different panel: 1.3" at 416×416 on the AMOLED
model, 260×260 on the solar MIP model. Never assume a resolution. Read
`dc.getWidth()` / `dc.getHeight()` and lay out relative to the centre, so the
same code runs on other fēnix 8 and fēnix 9 variants.

**Action item:** after installing the SDK, open
`~/.Garmin/ConnectIQ/Devices/fenix8pro47mm/compiler.json` (Linux/macOS path).
It is the source of truth for memory limits, fonts, colour depth, API level and
the supported app types. Fill in §9 from it.

---

## 3. The modification surface: what can be changed, by whom, and how

### 3.1 Things any user can change, with no code (built into the firmware)

- Native watch faces and their data slots, colours, and on-device editing
  ("Customize")
- Photo watch faces made in the **Face It** feature of the Garmin Connect app
- Glance loop order, the controls menu, hot keys, data screens per activity
  profile, activity profiles themselves, display mode (gesture vs. always-on),
  and brightness

### 3.2 Things we can change with Connect IQ (our code)

| App type | What it is | Gets input? | Notable access | Main limits |
|---|---|---|---|---|
| **Watch face** | Replaces the home screen | No buttons. One gesture: **press and hold** via `WatchFaceDelegate.onPress` (CIQ 4.2+). Plain taps only reach a face inside the on-device config editor (`onTap`, 5.1+) ✅ | Time, battery, steps, HR, weather, **complications** (subscribe to native data), settings, background service for web data | About 128 KB of RAM ⚠️. Redrawn once a minute in sleep mode. AMOLED burn-in rules. No direct web requests from the foreground. |
| **Data field** | One field on a native activity's data screen | No (it runs inside the native activity) | Live activity metrics, ANT+ and BLE sensors, **writes FIT developer fields** that show up in Garmin Connect | About 128 KB ⚠️. Up to **4 CIQ data fields** active at once on the fēnix 8 ✅ |
| **Glance / widget** | A row in the glance loop that opens into a full app | Yes, once opened | Like a device app | Glance view about 64 KB ⚠️ |
| **Device app** | A full-screen app launched from the apps menu or a hot key | Full: buttons, touch, menus | GPS (`Position`), sensors and sensor history, **FIT recording** (`ActivityRecording`), **BLE central** (up to 3 registered profiles ✅), `Communications` (web requests, OAuth, phone messaging), storage, vibration and tones, **QR codes** (9.1), **mic/speaker** (9.3), **LTE control** (9.3) | Fēnix 8 figure unconfirmed. The fēnix 7 Pro allows about 768 KB ⚠️ |
| **Audio content provider** | Syncs music or podcasts to the watch from a service | Playback UI hooks | Download and playback management | Only makes sense if we run an audio service |

Shared features:

- **Settings.** `properties.xml` and `settings.xml` define them. Users edit them
  in the Connect IQ / Garmin Connect phone app, and on the fēnix 8 and later also
  in the **native on-device watch face editor** (SDK 8.1+) ✅. Launch-era fēnix 8
  Pro firmware refused to select some faces that used on-device customization
  (forum report, Sept 2025) ⚠️. Test this early on real hardware.
- **Complications.** Watch faces can *subscribe* to complications. Device apps
  can *publish* complications that faces then show. Native complications
  (HR, training status, Sleep Score in 9.2, and others) are readable ✅.
- **Background service.** A temporal event fires at most every **5 minutes**
  and runs for about **30 seconds** ✅. This is how a watch face fetches
  weather, prices, status pages and similar web data.
- **Themes / skins (SDK 9.3).** Apps and faces can switch colour, font and
  artwork sets, and the developer can ship new looks later without a store
  update ⚠️. Exact API names are not verified yet.
- **Dynamic resources (9.x).** An app can turn data it fetched into images
  (PNG, JPEG, first GIF frame), sounds, or saved FIT/GPX files at runtime ⚠️.
  Web requests gained request bodies with custom content types and raw binary
  responses ⚠️.

### 3.3 Things we can change *off* the watch

| Surface | Use | Access |
|---|---|---|
| **Connect IQ Mobile SDK** (Android/iOS) | Our own phone app exchanges messages with our CIQ app | Free. The Garmin Connect app must be installed. Sideloaded watch apps may not be reachable from the phone ⚠️ |
| **FIT SDK** | Read and write the activity files the watch produces, including our developer fields | Free |
| **Garmin Connect Developer Program** (Health, Activity, Training/Courses APIs) | Cloud access to user data, or pushing workouts and courses to the watch | Requires an approved business application |

### 3.4 Things we cannot change

- Firmware, the bootloader, the OS, system menus, the native watch faces' code,
  and the behaviour of native apps and activities. There is no root or jailbreak
  route, and attempting one would void the warranty and break the signature
  check. ✅
- Raw sensors beyond what the `Sensor` / `SensorHistory` APIs expose. That
  means no raw ECG or optical HR waveforms.
- **"Okay, Garmin" voice commands, the course or route currently loaded, and
  the GPS sampling rate** are all off-limits, even in 9.3 ⚠️.
- **inReach satellite messaging** is not available to apps.
- The **flashlight**. No CIQ API is known.
- Notifications cannot be redrawn by us. CIQ notification APIs (SDK 8.1+) can
  *post* richer notifications from a running or background app ✅.
- **WebSockets and raw TCP/UDP are not available.** `makeWebRequest` is
  HTTP(S) request/response only, proxied through the phone, or through LTE/Wi-Fi
  when there is no phone ✅.

---

## 4. Platform version map (what each SDK unlocks on our watch)

| SDK | When | Relevant additions |
|---|---|---|
| 8.1 | 2025 | System 8 / API 5.1. New VS Code extension. On-device watch face editor. Richer Notifications API. Extra code space. **Minimum SDK for store uploads to System 8 devices.** |
| 8.2 / 8.3 | 2025 | Native setup flow for data fields. `SensorDelegate` for pairing BLE/ANT sensors through the native UI. Activity filter in the manifest. |
| 8.4.1 | early 2026 | Tooling fixes. The ERA crash-report viewer now needs Connect credentials. |
| 9.1 | Mar 2026 | API 6.0. QR codes. Read HR/power zones and FTP, the current sport profile, and the planned sleep and wake times. |
| 9.2 | Jun 2026 | Sleep Score complication. **Bonded BLE connections.** Dynamic resources. |
| **9.3** | **20 Oct 2026** | **`Audio` capture (mic) and output (speaker).** **LTE control**: an app turns LTE on, and it drops when the app closes or after 5 minutes without web traffic. Themes/skins. |

⚠️ The 9.x details come from news coverage (the5krunner, Garmin Rumors). Garmin
shipped 9.x without much announcement. Confirm against the SDK release notes
before building on any of it.

---

## 5. Designing for the AMOLED (watch faces)

- **High-power mode** follows a wrist gesture or touch and lasts a few seconds.
  `onUpdate` runs once a second, so anything can be drawn.
- **Low-power (always-on) mode** starts with `onEnterSleep`. `onUpdate` runs
  **once a minute**. When `System.getDeviceSettings().requiresBurnInProtection`
  is true:
  - **at most 10 % of pixels lit**
  - **no pixel lit for more than 3 minutes**, so shift the layout a few pixels
    every minute
  - use thin fonts and outlines, never filled shapes
  - per-second `onPartialUpdate` is MIP-only and does **not** apply here ✅
- The firmware enforces these rules. A face that breaks them can be blanked or
  removed.
- The MicroLED panel is much brighter and drains the battery faster (10 vs. 27
  days). Treat AOD power as a design budget.
- Use `dc.setAntiAlias(true)` (behind a `has` check) for smooth arcs on 454 px.

The Field face in `apps/field/` implements these rules (`Lib.Aod`).

---

## 6. Toolchain

| Piece | Notes |
|---|---|
| **Connect IQ SDK Manager** | Downloads SDKs and per-device files. The SDK itself is a public download (`developer.garmin.com/downloads/connect-iq/sdks/sdks.json`), but the **device files need a Garmin account login**, through the GUI manager or the community CLI `connect-iq-sdk-manager` (`brew install lindell/connect-iq-sdk-manager-cli/connect-iq-sdk-manager-cli`). ✅ |
| **VS Code + Monkey C extension** | Official IDE path: build, run in the simulator, debug, "Generate Developer Key". |
| **Java** | Needed by the `monkeyc` compiler. |
| **Simulator** | Windows, macOS and Linux (Ubuntu, needs webkit2gtk). Simulates sleep mode, the burn-in checker, settings, low battery, GPS playback and more. |
| **Developer key** | An RSA-4096 key in DER format. It signs every build. **Keep it safe and out of git.** Losing it means we can no longer update a store app. |
| **CLI** | `monkeyc` (build), `connectiq` (start the simulator), `monkeydo` (run a `.prg` in the simulator, `-t` for unit tests). See `README.md`. |
| **CI** | Building with `monkeyc` in Docker works (community images such as `cedric-dufour/connectiq-sdk-docker` and `wistrand/garmin-dev`). Running tests needs the simulator, which needs an X server or Xvfb, so plan for a heavier CI image. |
| **Testing on the watch** | Build for the exact device ID, then copy the `.prg` to `GARMIN/APPS` over USB. The watch uses **MTP**: on macOS this needs a tool such as OpenMTP, on Linux `jmtpfs`/gvfs. Sideloads need SDK 7.4.3 or later. Garmin watches have no "developer mode". |

SDK 9.3.0 is installed on the development Mac (27 Oct 2026) under
`~/Library/Application Support/Garmin/ConnectIQ/Sdks/`, with the VS Code
extension and a developer key in `~/.garmin/`. See `README.md` for the state of
the device files and the first build.

---

## 7. Distribution

1. **Sideload**: personal use and fast iteration (see §6).
2. **Beta apps**: upload a `.iq` as a beta. Only our own Garmin account can see
   it. It is the closest test to a real store install, and the phone settings
   and Mobile SDK messaging work.
3. **Connect IQ Store**: public, after Garmin review. Free developer account.
   Store uploads to System 8+ devices need SDK 8.1 or later.
4. **Paid apps** (since Aug 2024): Garmin Pay-based purchases after merchant
   onboarding. For watch faces, telling the time counts as the "primary
   feature", so a paid face carries a "Payment Required" badge.

---

## 8. Candidate first projects

These are ordered by effort. Each is a separate project.

1. **A custom watch face** (`apps/field/`). It teaches layouts,
   AMOLED rules, settings, complications and memory profiling, and is the
   lowest-risk way into the toolchain.
2. **A data field** that writes a FIT developer field, for any activity metric
   we want to compute live. It shows up in Garmin Connect charts.
3. **A glance plus device app** that pulls from our own HTTPS backend. With the
   9.3 LTE control it can work without the phone.
   Networking constraints for anything web-backed:
   - Requests go through the phone. **Android requires HTTPS with a valid
     certificate.** iOS allows plain HTTP to simple LAN hostnames but has
     quirks ⚠️.
   - Without a phone, LTE can't reach a LAN address, so any service must be
     reachable on the public internet over HTTPS.
   - **No WebSockets**: anything live has to be polled.

The concrete designs we chose are in [`designs/DESIGNS.md`](designs/DESIGNS.md).

---

## 9. Open questions (to verify once the SDK is installed)

- [x] The exact device ID: `fenix8pro47mm` covers the 47 mm, 51 mm, MicroLED
      and quatix 8 Pro (SDK 9.3.0 device-reference and API docs).
- [ ] Memory limits for watch face, data field, glance, background and device
      app (from `compiler.json`).
- [ ] The current API level on the shipped firmware (expected 6.0), and whether
      9.3 features need a firmware update.
- [ ] Whether the on-device customization bug is fixed in current firmware.
- [ ] The 9.3 theme API, `Audio` module names and permissions, and LTE APIs.
      Read the SDK API docs.
- [ ] Whether `makeWebRequest` over LTE needs an active LTE/inReach plan.
- [ ] Custom fonts and bitmap budget at 454 px: how many glyph sets fit in
      128 KB.

---

## Sources

- Garmin Connect IQ overview of app types: <https://developer.garmin.com/connect-iq/overview/>
- Complications API: <https://developer.garmin.com/connect-iq/api-docs/Toybox/Complications.html>
- BLE API: <https://developer.garmin.com/connect-iq/api-docs/Toybox/BluetoothLowEnergy.html>
- Mobile SDK for iOS: <https://developer.garmin.com/connect-iq/core-topics/mobile-sdk-for-ios>
- Adapting CIQ apps to LTE (Garmin blog): <https://www.garmin.com/en-US/blog/developer/adapting-connect-iq-app-to-lte/>
- Monetization: <https://developer.garmin.com/connect-iq/monetization/app-sales/>
- fēnix 8 Pro device ID (`fenix8pro47mm`, SDK 9.2.0 device files): <https://github.com/wwarby/walker/pull/23>
- fēnix 8 Pro specs: <https://the5krunner.com/specs/garmin/fenix-8-pro/>, <https://www.androidcentral.com/wearables/garmin-fenix-8-pro-vs-fenix-8>, <https://www.tomsguide.com/wellness/smartwatches/the-garmin-fenix-8-pro-has-the-brightest-screen-on-any-smartwatch-and-lte-connectivity-but-it-comes-at-a-huge-price>
- Connect IQ 9 (9.1/9.2): <https://the5krunner.com/2026/06/11/garmin-connect-iq-9/>
- SDK 9.3 (mic, speaker, LTE, themes): <https://garminrumors.com/connect-iq-sdk-9-3-microphone-speaker-lte/>, <https://the5krunner.com/2026/10/21/garmin-connect-iq-sdk-themes/>
- SDK 8.x: <https://forums.garmin.com/developer/connect-iq/b/news-announcements/posts/connect-iq-sdk-8-2-now-available>, <https://forums.garmin.com/developer/connect-iq/f/discussion/430658/sdk-8-4-1-release-notes>
- System 8 API level and SDK minimums: <https://forums.garmin.com/developer/connect-iq/f/discussion/407332/forced-to-build-with-sdk-8-1-0-compatibility-issues/1915305>
- fēnix 8 Pro on-device customization bug: <https://forums.garmin.com/developer/connect-iq/f/discussion/422197/fenix-8-pro-ciq-watch-face-selection-customization-not-possible/1975155>
- On-device watch face settings: <https://forums.garmin.com/developer/connect-iq/f/discussion/405661/how-to-implement-watch-face-settings-without-using-customize/1908088>
- AMOLED always-on rules: <https://forums.garmin.com/developer/connect-iq/f/discussion/192673/how-to-enable-an-always-on-mode-for-venu-amoled/1251927>
- fēnix 8 memory and 4 data fields: <https://the5krunner.com/2024/09/09/garmin-fenix-8-supports-4-ciq-data-fields/>, <https://forums.garmin.com/developer/connect-iq/f/discussion/427049/instinct-crossover-amoled-memory-limit/1994093>
- Sideloading on the fēnix 8: <https://forums.garmin.com/developer/connect-iq/f/discussion/419051/sideloading-on-a-watch>, <https://forums.garmin.com/developer/connect-iq/f/discussion/431942/fenix-8-developer-mode>
- HTTP vs HTTPS: <https://forums.garmin.com/developer/connect-iq/f/discussion/370945/how-to-do-a-http-not-https-web-request>, <https://forums.garmin.com/developer/connect-iq/f/discussion/439972/http-fails-on-ios-with-fqdns-https-works-with-a-local-ca>
- BLE profile limit: <https://forums.garmin.com/developer/connect-iq/f/discussion/355330/maximum-number-of-active-bluetooth-connections>
- Docker/CI: <https://forums.garmin.com/developer/connect-iq/f/discussion/303170/connectiq-docker-image-and-github-action>, <https://github.com/wistrand/garmin-dev>
- Paid apps: <https://the5krunner.com/2024/08/07/garmin-connect-iq-store-allows-paid-for-apps-using-garmin-pay/>
