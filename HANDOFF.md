# Handoff: garmin-widgets

Connect IQ watch faces and glances for the Garmin fēnix 8 Pro. This file
records where the project stands so the next session can carry on.

## Where everything is

- **Repository:** https://github.com/AllenBW/garmin-widgets (private)
- **Design page** with the original mockups and a copy of the first import:
  https://claude.ai/artifact/CQcd2fNRPKsgigd9j7dfKd (private to the owner)
- **Input matrix** (every sensor and input by app type, with what the
  simulator proved and how to check each on the watch; ticks are kept in
  the browser): `designs/inputs-matrix.html`, published privately at
  https://claude.ai/artifact/PjY39dg6QJTrLa6wHVTcaN
- **Toolchain on the dev Mac:** SDK 9.3.0 in
  `~/Library/Application Support/Garmin/ConnectIQ/Sdks/`, the VS Code Monkey C
  extension, the `connect-iq-sdk-manager` CLI, and a developer key in
  `~/.garmin/developer_key.der` (not in git, back it up).

## State

- **Done**
  - Platform exploration with sources (`EXPLORATION.md`)
  - Five designs with mockups (`designs/`)
  - Repo layout: `apps/<name>/` per app plus the shared `lib/` barrel
    (`Lib.Aod`, `Lib.Arcs`, `Lib.Fmt`, `Lib.Sun`, `Lib.Moon`, `Lib.Solar`,
    `Lib.Location`, `Lib.Sky`; `Fmt`, `Solar` and `Location` are glance-safe), and
    `scripts/build.sh` / `scripts/sim.sh` / `scripts/test.sh`
  - **Field** watch face (`apps/field/`): a 24 h daylight dial on the bezel
    (step goal, battery or off in settings), a signals row that only shows
    rain ahead, pressure falling, phone disconnected or do not disturb, date,
    time, three configurable slots (HR, steps, Body Battery, calories, floors,
    distance, stress, sunrise, sunset, next calendar event, recovery, sleep
    score, high/low), a footer with the next sun event plus the moon phase at
    night (or weather and notifications, or off), always-on layout with hollow
    digits, the next sun event, a hairline daylight band and per-minute
    shifting, press-and-hold on a slot opens the native widget. Compiles
    cleanly (`-l 3`) for `fenix8pro47mm`, `fenix847mm` and `fenix843mm`, and
    the active layout has been checked by eye in the simulator; the always-on
    layout has not.
  - **Unit tests** (`apps/field/tests/`, `scripts/test.sh field <device>`):
    nine tests, passing on all three devices. They draw the face into an
    off-screen bitmap in every ring, footer and slot mode, awake and asleep,
    check the press targets, and check `Lib.Sun`, `Lib.Moon` (against known
    new and full moons), `Lib.Arcs`, `Lib.Aod` (all 25 offset cells in an
    hour) and `Lib.Fmt`. Memory: code + data 13.4 KB (`--build-stats 0`),
    about 30 KB in use at runtime, against the 128 KB watch face budget.
  - **Battery Planner** (`apps/battery/`, a widget: glance + app): a
    background service logs the battery level every 30 min into
    `Application.Storage`; `BatteryModel` turns the week into a drain per
    day, a pace (median of complete days), hours left and a charge-by date
    (10 % reserve); the glance shows the headline, the charge-by date and a
    sparkline, the app adds seven drain bars with the heavy day in orange and
    its activity time. Falls back to the watch's `batteryInDays` until there
    is history. Select in the app logs a sample. Seven tests pass on all
    three devices (`scripts/test.sh battery`). Loaded once in the simulator
    without console errors; not yet looked at by eye, and the background
    service has only been exercised by the test (it calls `onTemporalEvent`
    directly).
  - **Sun and Moon** (`apps/sunmoon/`, a widget: glance + app): `Lib.Solar`
    (NOAA sun maths, within a minute of the NOAA calculator for New York
    and London in the tests) gives sunrise/sunset, golden hour (+6° to −4°)
    and blue hour (−4° to −6°); the glance shows the next sun event and a
    golden hour countdown, the app the sun on its arc, the next golden and
    blue hour and the moon. Location: weather observation point, activity
    location, the last GPS fix, or the saved one. Five tests pass on all
    three devices. The simulator supplies no location in the test harness,
    so the "No location yet" path is what the tests draw; not looked at by
    eye, not run on a watch. Moonrise/moonset not done.
  - **Daylight** (`apps/daylight/`, watch face): the 24 h dial (navy night,
    amber day, orange golden hours from `Lib.Solar`, 24 ticks, a hand at
    the current time), light left or time to sunrise, the time, sunrise and
    sunset, altitude and sea-level pressure with a trend triangle; always-on
    with cardinal ticks, hollow marker and hollow time. Falls back to the
    watch's sunrise/sunset when no location was ever known. Three tests
    pass on `fenix8pro47mm`. No settings. Not looked at by eye.
  - **Night Sky** (`apps/nightsky/`, watch face): the sky overhead from the
    last known location: 345 stars with asterism lines (generated into
    `Stars.mc` by `designs/gen_stars.py` from the Yale Bright Star Catalog),
    the Moon with its phase, Venus/Mars/Jupiter/Saturn lettered, the Sun by
    day, north up and east left, the time on a black backing. `Lib.Sky`
    holds the maths (Schlyter), checked in the tests against published
    positions. Placing the sky costs 6 ms; always-on uses the brightest 80
    stars. Five tests pass. Not looked at by eye.
  - **Horizon** (`apps/horizon/`, watch face): the bezel is the next twelve
    hours, one segment per hour from the current one: grey by day, navy at
    night, blue in three shades for rain chance from the hourly forecast; a
    dot at now, a sun triangle and a calendar diamond on the ring; centre
    has date, time, the rain outlook in words, then temperature, sun event
    and event time. `HorizonModel.build()` is pure and tested with a
    synthetic day; the calendar complication's time string is parsed
    ("16:00", "4:05 pm"). Four tests pass. Not looked at by eye.
  - **Sun Compass** (`apps/suncompass/`, a widget: glance + app): a compass
    rose (ticks, N/E/S/W) that turns so the heading is at the top, with
    the sky seen from above inside it: horizon ring, hourly sun dots with
    every third hour labelled, sunrise ▲ and sunset ▼ on the ring, the sun now as a disc (hollow on
    the ring when it is down), the heading and the next sun event with its
    bearing in the centre. `Lib.Solar.altAz` (new) gives the sun's
    altitude and bearing; it agrees with an independent model to 0.02°.
    The heading comes from `Sensor.getInfo().heading`, polled at 4 Hz
    while the view is shown (plus the 1 Hz sensor event), smoothed; the
    sensor is released in `onHide`. Four tests pass on all three devices;
    a frame draws in about 60 ms in the simulator. Not looked at by eye.
    If the simulator gives no heading the rose stays north-up and the
    centre says "no compass".
  - **Readiness** (`apps/readiness/`, watch face): Body Battery (green,
    left) and stress (orange, right) gauges filling upward, date and time,
    tiles for sleep score, recovery time and resting HR, the training
    status as a cyan footer; press and hold opens the native widget.
    Sources are in `Metrics.mc` (SensorHistory, complications, UserProfile);
    HRV status and Training Readiness are not available to Connect IQ.
    Metrics are read once a minute awake, every five minutes always-on.
    Always-on: hollow time and "BB 74 · SLEEP 82". Three tests pass on all
    three devices; the simulator supplies values. Not looked at by eye.
  - **Pocket QR** (`apps/pocketqr/`, a widget: glance + app, design #9,
    picked by the owner on 2026-10-29): up to six QR codes from one
    array setting edited as a list in the Connect IQ app (name + content,
    one example entry by default); the app shows one code at a time on a
    white card with its name and "2 of 3 · Wi-Fi", up/down or swipe to
    page, select or menu for a list; the glance names the first code and
    counts the rest. `ScanCode.createQrCodeImage` encodes in about 12 ms;
    a value too long to encode throws and the card says so. Three tests
    pass on all three devices at `-l 3`. Loaded in the simulator; not yet
    looked at by eye, and not scanned with a phone camera.
  - **Sauna and Steam** (`apps/sauna/`, a widget: glance + app, design
    #10, asked for by the owner on 2026-10-29 after seeing the store's
    "Sauna App"; what they want: cueing on what buttons do, then both a
    sauna and a steam room with the same detail and coaching, and
    temperatures in Fahrenheit by default; then, on 2026-10-29 evening,
    an icon showing both rooms, an obvious way to end a visit, touch on
    the cue corners, and guided versus free sessions). START opens a
    selector (Guided sauna / Guided steam / Free sauna / Free steam /
    Clear visits); while recording the START cue reads END and opens
    Save / Resume / Switch to free or guided / Discard. A tap near a
    cue acts as that button (`SaunaView.cueAt`); other taps do nothing.
    Later the same evening, heart-rate coaching with a switch per rule
    (ceiling of 180 minus age for a minute, "not recovered" over 110 a
    minute after leaving extends the break, "stand up slowly"), and the
    other readings logged: breathing and stress per second, Body Battery
    at start and end, HRV (RMSSD per minute, `SaunaHrv.mc`) as an
    experiment. The simulator's profile gives a ceiling of 134 bpm.
    Later still: the manifest type is **watch-app** (widgets may not
    record activities: the first real start died at once), a Demo entry
    in the Start menu (`SaunaView.startDemo`, `SaunaTracker.seedDemo`,
    `SaunaHistory.demoRows`), bigger text with a title band and page
    dots on every screen, the glance's week line on one line, tables
    and the chart inside the cue-free area, cue words on black patches.
    Seen by eye in the simulator: the glance, the idle screen and all
    four demo pages. Driving the simulator: the session's swift script
    posts key events (Return = START, arrows = UP/DOWN, Escape = BACK)
    and `screencapture -l <window id>` grabs the window, both with the
    shell sandbox off; see the toolchain memory note. The simulator is
    one process shared with any other Claude session on the Mac, and on
    2026-10-29 a sibling session kept loading its watch face over this
    app, which looked like crashes and exits until the memory note
    explained it. `SaunaPlan` holds one kind's
    targets, cap, weekly goals and door rates (defaults from the
    published guidance, all settings in groups per kind);
    `SaunaTracker` is pure arithmetic ticked once a second: the door
    from the thermometer (rise above the minute's low, fall below its
    high, scaled by a sensitivity setting), the peak and the one- and
    two-minute falls after each round, the plan's events (round target,
    past the longest round, heat cap, cool-down done, plan done,
    recovery known) and `coach()`, the line under the timer.
    `SaunaHistory` rows carry the kind; `thisWeek(kind)` feeds the glance
    and the idle screen. `SaunaSettings` reads the phone settings and
    sets `SaunaText.fahrenheit`. `SaunaRecorder` names the activity by
    kind and adds a Kind session field. Cues on every screen at Garmin's
    own hint angles (58, 123, 237, 270 clockwise from twelve). Six tests
    pass on all three devices. Not seen by eye and not yet on the watch;
    the door rates are guesses until a real visit's FIT file is read.
- **The watch (2026-10-29):** the owner has a **fēnix 8 47 mm, not Pro**
  (`fenix847mm`, firmware 23.40). It reaches the Mac over MTP with
  libmtp once its USB mode is MTP (hold UP → Watch Settings → System →
  Advanced → USB Mode; in Garmin mode it shows as USB product 0003 and
  nothing can write to it). `scripts/watch.sh` pushes builds and pulls
  logs; the `mtp-*` tools need the shell sandbox off. All nine earlier
  apps were pushed as `GARMIN/Apps/<NAME>.PRG` with empty
  `LOGS/<NAME>.TXT` files; the owner has not reported what they saw yet.
- **Install queue (2026-10-30):** `scripts/watch.sh queue <other worktree>`
  builds every app in this checkout plus any app another worktree has
  that this one lacks into `watch-queue/<device>/` (gitignored), this
  checkout's versions winning; `scripts/watch.sh flush` copies the lot
  onto the watch the next time it is on the cable and empties the queue.
  Queued now for `fenix847mm`: the ten apps here and Rings, Strata and
  Today from the `bunyip` worktree (`AllenBW/bunyip`, another session's
  work). The simulator is shared across sessions: `scripts/simlock.sh`
  claims it by ID; the other session knows the convention.
- **Platform check (2026-10-29):** `EXPLORATION.md` section 10 lists every
  sensor and input by app type, verified against the SDK 9.3.0 docs, the
  device files and a probe face run in the simulator. Headlines: a watch
  face cannot touch `Sensor`, `Attention` or `Audio` (fatal "Permission
  Required", not catchable), but its background service *can* call
  `Sensor.getInfo()` every 5 min; `Position.getInfo()` and
  `Notifications.showNotification` run in a face; documented fields can be
  absent at runtime (`pushes`, `isNightModeEnabled`), so guard with `has`.
  `Audio.Capture` exists, so a sound level meter is feasible as a
  watch-app with a glance; the simulator records from the Mac microphone.
  Reviewed on 2026-10-29 against the Programmer's Guide, Garmin's web
  docs and about forty forum threads (section 10.7 lists the gaps).
  Two findings for the apps: **Field has no `Positioning` permission**,
  and the forum says the weather observation position is null without
  it, so its sun dial may be empty on a watch (add the permission, it is
  allowed for faces); and declaring `Sensor` (Sun Compass) reportedly
  costs about 1.5 %/h of battery while the app is open.
- **Still to check in the simulator by eye:** Low Power Mode (the hollow
  digits from `Lib.Aod.drawHollowText` overdraw in black; if anti-aliasing
  leaves grey fringes, switch to a dim solid font), the burn-in checker, and
  the 416 px layout on `fenix843mm` (it draws without error there). For the
  Battery Planner: the glance row (the simulator shows the glance loop from
  the watch face), the app layout, and **Simulation → Background Events →
  Temporal Event** to fire the sampler. For Sun and Moon: give the simulator
  a position (Simulation → Location, or play a GPS FIT file) and check the
  arc, the rows and the glance.
- **Still to check on a watch:** press-and-hold → `Complications.exitTo`,
  `SensorHistory` Body Battery/stress, settings in Garmin Connect, and the
  APIs still marked ⚠️ in `EXPLORATION.md` and `designs/DESIGNS.md`.
- **Permissions on the dev Mac:** the Claude shell can't take screenshots or
  drive the simulator's menus (Screen Recording / Automation not granted), so
  visual checks go through pasted screenshots.

## Rules

- **Self-contained project.** It has nothing to do with Artisan
  (`AllenBW/artisan`) or any other repository. Don't add references to or
  integrations with other projects.
- Never commit developer keys (`*.der`, `*.pem`) or `bin/`.

## Next steps

1. `scripts/sim.sh field`: check Low Power Mode and the burn-in checker by
   eye. Sideload to the watch and test the press-and-hold and the settings
   in Garmin Connect.
2. Consider the on-device watch face editor (`resources/configs/watchface.xml`,
   `WatchFaceConfig`, SDK sample `ConfigurableWatchFace`) for the slots and
   accent colour once the basics work.
3. Battery Planner on a watch: confirm the background service really fires
   every 30 min (the log should grow by 48 samples a day) and that the
   activity annotation finds activities. Sun and Moon on a watch: confirm a
   location is found after a phone sync or a GPS activity.
4. Readiness (#4) is built, so every design in `designs/DESIGNS.md` now
   exists. On a watch: check the sleep score and training status
   complications return real values (the simulator gives 15 and "No
   Result"), the recovery minutes, and that the always-on update stays
   inside the power budget (`onPowerBudgetExceeded` prints to the console).
5. Settings for Daylight (accent, show altitude/pressure), a constellation
   lines toggle for Night Sky, and the on-device editor for all faces, once
   the basics have been seen on a watch.
6. Sun Compass (picked by the owner on 2026-10-28) is built. On a watch:
   check the heading really updates at 4 Hz, how the smoothing feels, and
   that the sensor stops when the app closes (battery). Possible follow-ups
   the owner has not asked for yet: the moon's bearing, and the golden
   hour alert and sound level meter ideas from the same conversation.
7. **Sound level meter** (the owner likes it, 2026-10-29): a **watch-app
   with a glance**, not a widget and not a face (the permissions table and
   the simulator allow `AudioInput` for device apps and audio providers
   only; the compiler would accept a widget manifest but the runtime may
   not). `Audio.Capture` with 16-bit LPCM mono at 8 kHz, RMS per window
   to dBFS, a settings offset for approximate dB SPL. `:windowSize` is in
   bytes; skip a 44-byte WAV header if one appears at the start of a
   window; keep `FILTER_NREC` off (the simulator ignores filters anyway).
   First measure in the simulator: the window limit and how many samples
   `decodeNumber` can unpack per callback under the watchdog. The
   simulator will ask for macOS microphone access the first time. No
   developer has reported capture on a real watch yet.
8. **Pocket QR** is built. In the simulator: File → Edit Persistent
   Storage → Edit Application.Properties data to add codes and check the
   list, the menu and the empty state; point a phone camera at the
   simulator window to see whether the code scans at that size. On a
   watch: check the settings list in the Connect IQ app (array settings
   with a name and a content field) and scan a Wi-Fi code with a phone.
   Ideas not built: editing a code on the watch, a brightness boost.
9. **Sauna and Steam** is built; push it with `scripts/watch.sh push
   sauna` when the watch is plugged in. First on the watch: do the cues
   land beside the buttons; does the selector read well; is
   `Sensor.Info.temperature` ever non-null in a device app (the
   SensorHistory fallback covers it if not); start a sauna at home and
   hold the watch over a cup of hot water to see the thermometer move
   and the automatic IN fire; check the three settings groups show in
   the Connect IQ app and that the unit setting flips the readings. After
   a real visit of each kind, pull the FIT file from Garmin Connect and
   read the "Watch temp" chart to tune the door rates (steam may need
   LAP). Ideas not built: a breathing pacer during breaks, cold-plunge
   phases (cold-water crash reports on the fēnix 8), a glance that
   starts a visit directly.