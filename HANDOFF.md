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
    (`Lib.Aod`, `Lib.Arcs`, `Lib.Fmt`, `Lib.Sun`), and `scripts/build.sh` / `scripts/sim.sh`
  - **Field** watch face (`apps/field/`): bezel ring (step goal by default,
    battery or off in settings), date, time, three configurable slots (HR,
    steps, Body Battery, calories, floors, distance, stress, sunrise, sunset),
    a footer with the next sun event (or weather and notifications, or off),
    always-on layout with hollow digits, the next sun event and per-minute
    shifting, press-and-hold on a slot opens the native widget. Compiles
    cleanly (`-l 3`) for `fenix8pro47mm`, `fenix847mm` and `fenix843mm`, and
    the active layout has been checked by eye in the simulator; the always-on
    layout has not.
- **Still to check in the simulator:** Low Power Mode (the hollow digits from
  `Lib.Aod.drawHollowText` overdraw in black; if anti-aliasing leaves grey
  fringes, switch to a dim solid font), the burn-in checker, peak memory
  (File → View Memory), and the 416 px layout on `fenix843mm`.
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

1. `scripts/sim.sh field`: check Low Power Mode, the burn-in checker and peak
   memory. Sideload to the watch and test the press-and-hold and the settings
   in Garmin Connect.
2. Consider the on-device watch face editor (`resources/configs/watchface.xml`,
   `WatchFaceConfig`, SDK sample `ConfigurableWatchFace`) for the slots and
   accent colour once the basics work.
3. **Battery Planner** (design #2) as `apps/battery/`. Before **Readiness**
   (#4), check which complications the SDK exposes (the list is in
   `<sdk>/doc/Toybox/Complications.html`).
