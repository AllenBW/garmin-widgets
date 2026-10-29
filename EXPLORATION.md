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
  **API level 6.0.3** ✅ (`compiler.json`, firmware 2339, for the 8 Pro, the 8
  43 mm and the 8 47/51 mm alike). The newest SDK is **9.3.0** (20 Oct 2026). It lets apps
  use the **microphone, the speaker and LTE**, and Garmin explicitly lists the
  fēnix 8 Pro for all three ⚠️.
- The fēnix 8 Pro has real **LTE and inReach satellite** hardware. As of SDK 9.3,
  CIQ apps can bring LTE up themselves for web requests ⚠️. Satellite messaging
  is **not** exposed to apps.
- The biggest constraints are **memory** (**128 KB** for a watch face or
  data field, 64 KB for a glance or background process, 768 KB for a device
  app, 512 KB for an audio content provider ✅ from `compiler.json`), the
  **AMOLED always-on rules** (at most 10 % of pixels lit,
  no pixel lit for more than 3 minutes ✅), and **background tasks** (at most
  once every 5 minutes, about 30 seconds each ✅).

---

## 2. The device

| | fēnix 8 Pro 47 mm | fēnix 8 Pro 51 mm | fēnix 8 Pro MicroLED 51 mm |
|---|---|---|---|
| Display | AMOLED, 1.4" | AMOLED, 1.4" | MicroLED, about 4,500 nits |
| Resolution | 454×454 ✅ | 454×454 ✅ | 454×454 ✅ (same device files) |
| Touch | yes, plus 5 buttons | yes | yes |
| Solar | **no** | **no** | **no** |
| Battery, smartwatch mode | up to 27 days (AOD off) | up to 27 days | up to 10 days |
| Connectivity | BT, Wi-Fi, LTE, inReach satellite | same | same |
| Speaker / mic | yes | yes | yes |
| CIQ device ID | `fenix8pro47mm` ✅ (one ID covers all three, plus the quatix 8 Pro) | ← | ← |
| Launcher icon | 65×65 ⚠️ | ← | ← |

The regular fēnix 8 AMOLED models are also targets, in case the Pro doesn't
happen: `fenix843mm` is **416×416** (family `round-416x416`) and `fenix847mm`
covers the 47 mm and 51 mm at **454×454**, with the same memory limits and API
level as the Pro ✅. The solar models use a MIP panel (260×260 / 280×280) and
are out of scope. Never assume a resolution. Read `dc.getWidth()` /
`dc.getHeight()` and lay out relative to the centre.

Device files live in `~/.Garmin/ConnectIQ/Devices/<id>/` (symlinked into
`~/Library/Application Support/Garmin/ConnectIQ/Devices` on the Mac so the SDK
finds them). `compiler.json` there is the source of truth for memory limits,
app types, colour depth (16 bpp) and API level; `simulator.json` has the
display size, fonts and 326 ppi.

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
| **Watch face** | Replaces the home screen | No buttons. One gesture: **press and hold** via `WatchFaceDelegate.onPress` (CIQ 4.2+). Plain taps only reach a face inside the on-device config editor (`onTap`, 5.1+) ✅ | Time, battery, steps, HR, weather, **complications** (subscribe to native data), settings, background service for web data | 128 KB of RAM ✅. Redrawn once a minute in sleep mode. AMOLED burn-in rules. No direct web requests from the foreground. |
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
- The **flashlight** from a watch face. Apps and widgets can drive it
  (`Attention.setFlashlightMode`, white or red on the fēnix 8 Pro, API
  3.4.3+), but `Attention` is not available to watch faces (verified in the
  simulator: calling it is a fatal "Permission Required" error).
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
- [x] Memory limits: watch face 128 KB, data field 128 KB, glance 64 KB,
      background 64 KB, device app 768 KB, audio provider 512 KB.
- [x] API level 6.0.3 in the SDK 9.3.0 device files (firmware 2339). Whether
      the watch's installed firmware matches is still to check on hardware.
- [ ] Whether the on-device customization bug is fixed in current firmware.
- [x] `Audio` (9.3, API 6.0.3): `Audio.Capture` (permission `AudioInput`,
      16-bit LPCM or Opus, 8 to 44.1 kHz, mono or stereo, data arrives in a
      callback per window) and `Audio.Output` (permission `AudioOutput`).
      Watch apps, glances and audio providers only; the manifest is rejected
      for a watch face. The simulator records from the Mac microphone. See
      section 10.
- [ ] The 9.3 theme API and LTE APIs. Read the SDK API docs.
- [ ] Whether `makeWebRequest` over LTE needs an active LTE/inReach plan.
- [x] Fonts: the fēnix 8 family ships TrueType fonts, so
      `Graphics.getVectorFont({:face => ..., :size => px})` gives any size
      without bitmap font resources. Face names (no hyphens): `RobotoRegular`,
      `RobotoMedium`, `RobotoCondensedRegular`, `RobotoCondensedBold`,
      `BionicMedium`, `BionicBold`. System font heights at 454 px
      (`getFontHeight`): XTINY 37, TINY 47, SMALL 53, MEDIUM 61, LARGE 71,
      NUMBER_MILD 113, NUMBER_MEDIUM 153, NUMBER_HOT 173, NUMBER_THAI_HOT 210.
- [ ] Bitmap budget at 454 px, if we ever need custom bitmap fonts or large
      images.

---

## 10. Sensors and inputs, by app type (SDK 9.3.0, checked 2026-10-29)

How this was checked: the "App Types and Runtime Contexts" line of every
module in the SDK's own docs (`<sdk>/doc/Toybox/`), the fēnix 8 Pro device
files (`compiler.json`, `simulator.json`), and a throwaway watch face run in
the simulator that called each tempting API in turn. Where the simulator
contradicts the docs, the simulator is quoted. None of it has been run on a
watch.

### 10.1 What a watch face can read

| Source | Fields | Notes |
|---|---|---|
| **Time** `System.getClockTime`, `Time`, `Gregorian` | hour, min, sec, `timeZoneOffset`, `dst`; `Time.now()`, local and UTC calendar info | Plus `is24Hour`, `firstDayOfWeek` and `systemLanguage` from the device settings |
| **Daily body stats** `ActivityMonitor.getInfo()` | steps and goal, calories, distance, floors climbed/descended and goal, metres climbed/descended, active minutes today and this week (moderate, vigorous, total) and the weekly goal, move bar level, stress score, time to recovery (hours), respiration rate, `isSleepMode` (deprecated) | Wheelchair `pushes`, `pushDistance`, `pushGoal` are documented but **absent on this device**: reading one is a fatal "Symbol Not Found", so guard with `has` |
| **Seven-day history** `ActivityMonitor.getHistory()` | one entry per day: steps, floors, calories, active minutes, goals, `startOfDay` | No permission needed |
| **Heart rate history** `ActivityMonitor.getHeartRateHistory` | samples back to 6 h | No permission; `SensorHistory` has the same with a permission |
| **Sensor history** `SensorHistory` (permission `SensorHistory`) | heart rate (1-min samples, 6 h), elevation, pressure, temperature (2-min samples, 6 h), pulse ox (hourly, 7 days), Body Battery, stress | Sizes from `simulator.json`; Body Battery and stress are not listed there but the simulator returns all seven (21 °C, SpO2 95, 1372 m, 861 hPa, HR 80, Body Battery 88, stress 35) |
| **Live values** `Activity.getActivityInfo()` | `currentHeartRate`, `altitude`, `ambientPressure`, `meanSeaLevelPressure`, `rawAmbientPressure`, `currentOxygenSaturation`, `currentLocation` and its accuracy, `currentHeading`, `currentSpeed`, `timerState` (is an activity running), `startTime` | In the simulator a face sees altitude and heading/speed 0 only; HR, pressure and location stay null unless they are simulated (the Field tests print "HR = --" too). Heading and speed come from GPS, so outside an activity they mean nothing |
| **Last position** `Position.getInfo()` (permission `Positioning`) | position, accuracy, altitude, heading, speed, `when` | **Allowed in a watch face**: monkeyc accepts the permission and the call runs (accuracy 0, no position in the simulator). What a watch returns outside an activity is unverified; `Lib.Location` uses the weather observation point and the activity info instead |
| **Profile** `UserProfile` (permission `UserProfile`) | resting HR and 7-day average, birth year, gender, height, weight, activity class, VO2max running/cycling, sleep and wake times (durations from midnight) and the upcoming ones as moments, walking/running step length, HR zones per sport, FTP and power zones | `getUserActivityHistory()` iterates recent activities: sport, start, duration, distance |
| **Weather** `Weather` | current: temperature, feels like, high/low, humidity, dew point, pressure, wind speed and bearing, precipitation chance, cloud cover, UV index, visibility, condition, observation time, location name (deprecated) and position; hourly forecast; daily forecast; `getSunrise`/`getSunset` for any location and date | Needs a phone sync; null until then |
| **Complications** (permission `ComplicationSubscriber`) | 43 types in the SDK, **41 on this watch**: everything except `INVALID` and `WHEELCHAIR_PUSHES`. Present but not meaningful: `SOLAR_INPUT` (no solar panel; the simulator still says 50 %). Calendar events, notification count, race and pace predictors, VO2max, weekly run and bike distance, intensity minutes, pulse ox, respiration, 1-3 day forecasts, high/low and current temperature, last golf score, sleep score are all there | `getComplications()` iterates what the device has; `subscribeToUpdates` + `registerComplicationChangeCallback` push changes; `exitTo` opens the native widget from press-and-hold |
| **Device and phone** `System.getDeviceSettings()` | `phoneConnected`, `phoneOperatingSystem`, `connectionInfo` with a state per `:bluetooth`, `:wifi`, `:lte`, `notificationCount`, `alarmCount`, `doNotDisturb`, `isNightModeEnabled`, `isEnhancedReadabilityModeEnabled`, `fontScale`, `activityTrackingOn`, `tonesOn`, `vibrateOn`, units for distance/elevation/height/weight/pace/temperature, screen size and shape, `isTouchScreen`, `inputButtons`, `requiresBurnInProtection`, `firmwareVersion`, `partNumber`, `uniqueIdentifier` | Notification *count* only; never the notifications themselves |
| **Power and memory** `System.getSystemStats()`, `getDisplayMode()` | battery %, `batteryInDays`, `charging`, `solarIntensity` (null, no solar), used/free/total memory; high or low power display mode | |
| **Own state** `Application.Properties`, `Storage`, `onBackgroundData` | settings from Garmin Connect or the on-device editor, persisted values, what the background service returned | |

### 10.2 Events a watch face receives

- `onUpdate` every second while awake, once a minute asleep;
  `onEnterSleep` / `onExitSleep` (a wrist raise, touch or button wakes the
  face, so `onExitSleep` is the only "the user looked" signal there is);
  `Timer` only while awake.
- `WatchFaceDelegate.onPress` (touch and hold, with coordinates); `onTap`
  only inside the on-device config editor; `onWatchFaceConfigEdited`;
  `onPowerBudgetExceeded`.
- `AppBase.onSettingsChanged`, `onDeviceSettingChanged(symbol, value)`,
  `onNightModeChanged`, `onDisplayModeChanged`,
  `onEnhancedReadabilityModeChanged`, `onStorageChanged`, `onBackgroundData`.
- Complication change callbacks after `subscribeToUpdates`.
- `WatchUi.showToast` runs without error from a face in the simulator;
  whether anything is drawn is unverified.

### 10.3 The background service (permission `Background`)

A watch face may carry a background service (64 KB, about 30 s per run).
Triggers: a temporal event (never closer than 5 minutes; the simulator
refuses a registration sooner than 5 minutes after the last run), the
configured sleep and wake times, every 1000 steps, a goal reached (steps,
floors, active minutes), an activity completed, a phone app message, and
an OAuth response. `Communications.makeWebRequest` works there, which is how
a face gets anything from the internet.

**`Sensor` works in the background service of a watch face.** monkeyc
accepts the `Sensor` permission for a watch face as long as `Background`
is selected too, and `Sensor.getInfo()` runs inside `onTemporalEvent`: in
the simulator it returned the heading (0) and the altitude, with
temperature, pressure, heart rate, accelerometer and magnetometer null,
which is what the simulator gives when nothing is being simulated.
`Position.getInfo()`, `Activity.getActivityInfo()`, `ActivityMonitor` and
`SensorHistory` run there too, and the result reaches the face through
`Background.exit` and `onBackgroundData` five minutes later, every five
minutes. So a face can show a compass heading or a thermometer reading
that is up to five minutes old, provided a real watch fills those fields
for a background process (unverified). `enableSensorEvents` needs a run
loop and was not tried there.

### 10.4 Not available to a watch face (verified in the simulator)

- **`Sensor`**: accelerometer, gyroscope, magnetometer and compass heading,
  live temperature, live pressure, pulse ox on demand, paired ANT+/BLE
  sensors. The manifest refuses the `Sensor` permission for a watch face
  unless `Background` is also selected, and calling the module in the face
  is a fatal **"Permission Required: Module 'Toybox.Sensor' not available
  to 'Watch Face'"**. `Toybox has :Sensor` is true and `try`/`catch` does
  not catch it: the face simply dies. So no tilt, shake, orientation,
  heading, or cadence on a face.
- **`Attention`**: vibration, tones, backlight and the flashlight
  (`setFlashlightMode`, white or red on this watch). Same fatal error. A
  face cannot alert.
- **`Audio`**: the manifest is rejected ("'AudioInput' invalid for app type
  'watchface'"). Watch apps, glances and audio providers only.
- **Foreground `Communications`**, `BluetoothLowEnergy`, `Ant`,
  `ActivityRecording`, `FitContributor`, `PersistedContent`,
  `PersistedLocations`, `Media`, `ActivityPrompts`, `SensorLogging`: the
  docs list no watch-face context for any of them.
- `Notifications.showNotification` **runs without error from a face** in the
  simulator (the `Notifications` permission is accepted for a watch face).
  Whether the watch displays it, and whether the store allows it, is
  unverified. If it works, a face can raise its own alert (golden hour)
  without `Attention`.
- **Buttons, swipes and plain taps** never reach a face (see 10.2).
- **Hardware with no API at all**, for any app type: the ambient light
  sensor, ECG, skin temperature, raw optical HR (PPG), the contents of phone
  notifications, music playback state, the loaded course or route, the
  voice assistant.
- `onPartialUpdate` is not supported on this AMOLED device (section 5).
- Documented fields can be missing on a given device: `ActivityMonitor.Info.pushes`
  and `DeviceSettings.isNightModeEnabled` both died with "Symbol Not Found"
  here, and `isEnhancedReadabilityModeEnabled` is absent too. Guard anything
  newer than API 3 with `has`.

### 10.5 What widgets and apps get on top

- `Sensor.getInfo()` at 1 Hz: heading (true north, radians), accel, mag,
  altitude, pressure, temperature, heart rate, SpO2, and speed, cadence and
  power from paired sensors.
- `Sensor.registerSensorDataListener`: accelerometer up to 100 Hz (x, y, z,
  pitch, roll, power), gyroscope 100 Hz, magnetometer 50 Hz, and
  **`heartBeatIntervals`** in ms (beat-to-beat, so an app can compute its
  own HRV even though HRV status is not a complication). Period up to 4 s.
- `Audio.Capture` (microphone) and `Audio.Output` (speaker).
- `Position.enableLocationEvents` (multi-band GNSS), `PersistedLocations`
  (saved waypoints), BLE central, ANT, `Communications`, `Attention`
  (vibration, tones, backlight, flashlight), FIT recording and developer
  fields, and real input: five buttons, tap, hold, and four swipes.

### 10.6 Sound level meter: feasible as a widget, not a face

`Audio.Capture.initializeAudioCapture(callbacks, settings)` with
`CODEC_LPCM`, mono, `FREQ_8_KHZ` and `WINDOW_FILLED_CONTINUE` delivers a
`ByteArray` of 16-bit samples per window to `onData`; RMS of the samples
gives dBFS, and a settings offset turns that into an approximate dB SPL
(the watch is not a calibrated meter). Open points, all to be measured in
the simulator, which records from the Mac microphone: the unit of
`windowSize` and its maximum (`ValueOutOfBoundsException`), whether the WAV
container puts a header in the first window, how many samples
`decodeNumber` can unpack per callback under the watchdog (decode every
n-th sample if not), whether to leave the `FILTER_NREC` noise-reduction
filter off (it would change the level), and what the watch asks the user
the first time an app uses the microphone. Capture is refused in the
background (`CAPTURE_ERR_BACKGROUNDED`), so the meter only runs while its
view is open.

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
