# garmin-widgets

Connect IQ (Monkey C) watch faces, glances/widgets and device apps for the
Garmin fēnix 8 Pro (454×454 AMOLED/MicroLED, non-solar).

## Ground rules

- **This project is completely self-contained.** It has nothing to do with
  Artisan (`AllenBW/artisan`) or any other repository. Don't add integrations
  with, references to, or code from other projects unless the owner asks for
  them explicitly.
- Target devices: `fenix8pro47mm` (fēnix 8 Pro 47 mm, 51 mm and MicroLED,
  454×454), `fenix847mm` (fēnix 8 47/51 mm, 454×454) and `fenix843mm` (fēnix 8
  43 mm, 416×416). All API 6.0.3, 128 KB watch face budget. Lay out relative
  to `dc.getWidth()` / `dc.getHeight()`, never fixed pixels, and build for all
  three before committing.
- Every watch face must respect the AMOLED always-on rules: at most 10 % of
  pixels lit, shift the layout each minute, and check `requiresBurnInProtection`.
  Use `Lib.Aod` for this rather than re-implementing it.
- Shared code goes in the `lib/` barrel as an annotated sub-module, and apps
  link only the annotations they use (see `apps/field/monkey.jungle`).
- Build with `scripts/build.sh <app>`; run `scripts/sim.sh <app>` to see it in
  the simulator. Check the Garmin API docs that ship with the SDK
  (`<sdk>/doc/Toybox/`) before using an API; don't rely on memory.
- Never commit developer keys (`*.der`, `*.pem`) or `bin/` output.

## Layout

- `EXPLORATION.md`: what the platform lets us do, with sources
- `designs/`: design specs and mockups (`DESIGNS.md`, `mockups.py` → `svg/`)
- `lib/`: the `Lib` Monkey Barrel shared by all apps (`Aod`, `Arcs`, `Fmt`, `Sun`)
- `apps/<name>/`: one Connect IQ project per app (`apps/field/` is the Field
  watch face, design #1)
- `scripts/`: build and simulator helpers
