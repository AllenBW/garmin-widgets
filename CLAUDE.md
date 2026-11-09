# garmin-widgets

Connect IQ (Monkey C) watch faces, glances/widgets and device apps for
Garmin's round AMOLED watches, built on the fēnix 8 family. This tree is
the published source of the apps on the Connect IQ Store; the design
notes behind them are not part of it.

## Building

- SDK 9.3.0 from Garmin's Connect IQ page, with the device files for
  the watches in `scripts/devices.py` (`connect-iq-sdk-manager device
  download -F -d <ids>`), and a developer key at
  `~/.garmin/developer_key.der`. `scripts/sdk-env.sh` finds both.
- `scripts/build.sh <app> [device]` builds one app;
  `CIQ_JUNGLE="monkey.jungle;sample.jungle"` builds it with the sample
  readings the screenshots use. `scripts/sim.sh <app>` loads it into the
  simulator; `scripts/test.sh <app> [device]` runs the unit tests in
  `apps/<app>/tests/` (exit 0 on a pass). `scripts/package.sh <app>`
  writes the store package `dist/<app>.iq`.
- The simulator is one process per machine; `scripts/simlock.sh` claims
  it, or `scripts/simprivate.sh start` runs a private one for this
  checkout. `scripts/watch.sh` sideloads to a fēnix 8 over MTP.
- Shared code is the `Lib` barrel in `lib/`, linked per app by
  annotation (`apps/<app>/monkey.jungle`). Generated sources
  (`lib/source/Ink.mc`, `apps/nightsky/source/Stars.mc`,
  `apps/strata/source/Field.mc`, the stretch tables, `Numerals.mc`,
  `Digits.mc`, Clack's `Layout.mc`, `Drops.mc` and bitmap fonts, the
  settings resources) come from `designs/gen_*.py`; regenerate, never
  edit. The previews `designs/preview_*.py` render each face with sample
  readings (Pillow).
- Every app lists the watches in `scripts/devices.py`, which writes the
  manifests; lay out in fractions of the screen; keep always-on under
  10 % of pixels lit; gate anything a watch may lack (`Lib.Ink.resolve`,
  `Lib.Fmt.faces`, `Lib.Cues`, `has`).
- Never commit developer keys (`*.der`, `*.pem`) or build output.

The store listings and their descriptions are in `docs/STORE.md`; the
screenshots in `docs/store/`.
