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
    (`Lib.Aod`, `Lib.Arcs`, `Lib.Fmt`), and `scripts/build.sh` / `scripts/sim.sh`
  - **Field** watch face (`apps/field/`): battery ring with days-left readout,
    date, time, three configurable slots (HR, steps, Body Battery, calories,
    floors, distance, stress), weather and notification footer, always-on
    layout with hollow digits and per-minute shifting, press-and-hold on a
    slot opens the native widget, settings for accent colour, slots and footer
- **Not yet compiled.** The device files for `fenix8pro47mm` need a Garmin
  login (`connect-iq-sdk-manager login`, then
  `device download --manifest apps/field/manifest.xml`). Until then nothing
  here has been through `monkeyc`, so expect the first build to surface
  type-check and API errors. Candidates to check first:
  - `Lib.Aod.drawHollowText` relies on overdrawing in black to hollow the
    glyphs; if anti-aliasing leaves grey fringes, switch to a dim solid font.
  - `Slots.newestSample` uses `SensorHistory` with `:period => 1`.
  - `FieldDelegate.onPress` → `Complications.exitTo(new Complications.Id(type))`.
  - Font sizes (`FONT_NUMBER_THAI_HOT`, `FONT_MEDIUM`, ...) against the
    454 px mockup; adjust the layout fractions in `FieldView` if needed.
- **Unverified:** memory limits and API level from `compiler.json`, and the
  APIs still marked ⚠️ in `EXPLORATION.md` and `designs/DESIGNS.md`.

## Rules

- **Self-contained project.** It has nothing to do with Artisan
  (`AllenBW/artisan`) or any other repository. Don't add references to or
  integrations with other projects.
- Never commit developer keys (`*.der`, `*.pem`) or `bin/`.

## Next steps

1. Log in and download the device files, then record the memory limits and
   API level from `compiler.json` in `EXPLORATION.md` §9.
2. `scripts/build.sh field`, fix what the compiler reports, then
   `scripts/sim.sh field`: check the active layout, Low Power Mode, the
   burn-in checker and peak memory. Sideload to the watch and test the
   press-and-hold and the settings in Garmin Connect.
3. Consider the on-device watch face editor (`resources/configs/watchface.xml`,
   `WatchFaceConfig`, SDK sample `ConfigurableWatchFace`) for the slots and
   accent colour once the basics work.
4. **Battery Planner** (design #2) as `apps/battery/`. Before **Readiness**
   (#4), check which complications the SDK exposes (the list is in
   `<sdk>/doc/Toybox/Complications.html`).
