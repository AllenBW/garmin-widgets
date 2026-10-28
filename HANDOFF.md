# Handoff: garmin-widgets

Connect IQ watch faces and glances for the Garmin fēnix 8 Pro. This file
records where the project stands so the next session can carry on.

## Where everything is

- **Repository:** https://github.com/AllenBW/garmin-widgets (private)
- **Design page** with the original mockups and a copy of the first import:
  https://claude.ai/artifact/CQcd2fNRPKsgigd9j7dfKd (private to the owner)
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
4. **Readiness** (#4) is the last design. The SDK 9.3 complication list
   has Body Battery, stress, sleep score, recovery time, training status,
   respiration, pulse ox and VO2 max, but no HRV status, Training
   Readiness or resting HR (resting HR is in `UserProfile.getProfile()`).
   So the face can show what the sketch wanted except HRV.
5. Settings for Daylight (accent, show altitude/pressure), a constellation
   lines toggle for Night Sky, and the on-device editor for all faces, once
   the basics have been seen on a watch.
6. Picked by the owner on 2026-10-28, in this order: **Horizon** face (the
   bezel is the next 12 hours: rain chance per hour from
   `Weather.getHourlyForecast()`, sunset/sunrise marker, the next calendar
   event from its complication, a hand at now) and **Sun Compass** app (a
   compass rose from `Sensor.getInfo().heading` with today's sun path from
   `Lib.Sky`, needs the Sensor permission).
