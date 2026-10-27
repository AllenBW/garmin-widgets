# garmin-widgets

Connect IQ (Monkey C) watch faces, glances/widgets and device apps for the
Garmin fēnix 8 Pro (454×454 AMOLED/MicroLED, non-solar).

## Ground rules

- **This project is completely self-contained.** It has nothing to do with
  Artisan (`AllenBW/artisan`) or any other repository. Don't add integrations
  with, references to, or code from other projects unless the owner asks for
  them explicitly.
- Target device ID: `fenix8pro47mm` (unverified, see `EXPLORATION.md` §9).
  Lay out relative to `dc.getWidth()`/`dc.getHeight()`, never fixed pixels.
- Every watch face must respect the AMOLED always-on rules: at most 10 % of
  pixels lit, shift the layout each minute, and check `requiresBurnInProtection`.
- Never commit developer keys (`*.der`, `*.pem`).

## Layout

- `EXPLORATION.md`: what the platform lets us do, with sources
- `designs/`: design specs and mockups (`DESIGNS.md`, `mockups.py` → `svg/`)
- `watchface/`: starter watch face (not yet compiled)
