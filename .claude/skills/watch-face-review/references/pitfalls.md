# Pitfalls that cost review rounds

Platform and process lessons from the Strata redesign (2026-10-30). Add to
this list when a new one bites.

## Rendering

- **Vector font sizes are heights, not ems.** `Graphics.getVectorFont`'s
  `:size` is the font's whole height, about 1.17 em for Roboto. A Pillow
  preview at the same number shows text about 15 % bigger than the watch.
  Ask the watch for 1.17 times the preview's size (StrataView's
  `EM_HEIGHT` and `font()`), and treat the simulator capture as the
  reference. Shapes (lines, circles, polygons) match exactly.
- **Text has no baseline anchor.** To set a number and its unit on one
  baseline, draw each at `baseline - Graphics.getFontAscent(font)` with
  `TEXT_JUSTIFY_LEFT`.
- **A keyline is text drawn black at eight offsets, then in colour.** That
  cuts big text cleanly out of busy decoration. An outline style is the
  same in reverse: colour at the offsets, black on top. On small text a
  keyline reads as a sticker; give small text its own clear space instead.
- **The moon from `Lib.Moon.draw`** used 8 steps and looked jagged at
  radius 30+; it is 24 now. Always-on's moon needs the terminator as well
  as the lit limb, or a gibbous reads as a crescent.
- **Watchdog:** a few thousand small calls per update (2,000 pass, 5,000
  trip it in the simulator; unit tests have it off). Precompute in
  `designs/gen_*.py`, draw big static things into a full-screen
  `BufferedBitmap` a batch per frame.
- **monkeyc's type checker overflows its stack on one long array literal**
  (around 2,700 numbers). Split generated tables into chunks of 1,000 and
  hand them back from a function (`Field.chunks()`).

- **Settings on the fēnix 8 go through Garmin's watch face editor**, not
  an app menu. The phone app only edits settings for faces installed from
  the store, and `AppBase.getSettingsView` shows nothing for a face on the
  fēnix 8 (only Apply and Delete). Declare `<watchface-config>` in
  `resources/configs/watchface.xml` (styles, accent colours, data
  colours, complication slots; minApiLevel 5.1.0), read it with
  `WatchFaceConfig.getSettings(null)`, and redraw from the delegate's
  `onWatchFaceConfigEdited`. Data slots can only offer Garmin's
  complication types. See the SDK sample `ConfigurableWatchFace`, Strata
  and Rings.

## Design

- Reviewers will ask for things the owner has ruled out; quote the owner
  verbatim in every brief and say what is off the table.
- Things the owner rejected on Strata: segmented sections or boxed panels;
  a full-width line for a reading (heart rate); a word where an icon does
  (the word "SUNSET"); time digits made of hatched decoration ("messy").
- Things that read as UI rather than design: halos round small text, flat
  grey discs with text on them, a filled triangle over a bar (reads as
  "download"), two icons for different things in the same colour or
  shape, uneven icon weights (count inked pixels; aim for a narrow band).
- Clearings in a decoration field: fit them to the measured ink of the
  widest values plus about 5 px, ease them out over about twice their
  height, and keep them as one smooth shape per group. Fully levelled
  clearings look like plaques; a clearing per reading in a row makes
  cells; merging neighbours that are too far apart makes a black funnel.
- Settings: give every colour option a measured distance from the others
  (ΔE of 10 or more) and check every accent on every base.

## Process

- **The simulator is one process for the whole Mac.** Claim
  `/tmp/ciq-simulator.lock` (`owner=<id>`, `until=<unix seconds>`) before
  any monkeydo, wait on another owner's live claim, remove it when done
  (`scripts/sim-shot.sh` does this).
- **Silent monkeydo or tests that print nothing means a stale simulator.**
  Kill `[M]onkeyDoDeux`, the SDK's `bin/shel[l]` and
  `[C]onnectIQ.app/Contents/MacOS` (one bracketed letter, or pkill kills
  its own shell), start `<sdk>/bin/connectiq`, wait 14 s.
- **Capturing the simulator:** find the window with
  `CGWindowListCopyWindowInfo(.optionAll)` (owner "Connect IQ Device
  Simulator", name starting "CIQ Simulator"), then `screencapture -x -o -l
  <id>`. The id changes after a restart. Never use a bare `screencapture`,
  which grabs the owner's whole screen. Needs the sandbox off.
- **Always-on and Low Power Mode can't be driven** from here (menus need
  Accessibility). Check always-on in the previews and in code, and say so.
- The spacing reviewer measures everything and can take over an hour;
  typography and the skeptic answer in a few minutes. Send narrow changes
  only to the lenses they touch.
