# garmin-widgets

Free, open-source watch faces, widgets and apps for the **Garmin fēnix 8**
family, written in Monkey C for Connect IQ.

## The apps

| App | Type | What it does | Store |
|---|---|---|---|
| [Field](apps/field/) | Watch face | The everyday face: large time, a daylight ring, three slots you choose, the next sun event | [Store](https://apps.garmin.com/apps/482f6139-7e6d-432c-b448-762fa167a467) |
| [Daylight](apps/daylight/) | Watch face | A 24-hour sun dial: golden hours, light left, altitude and pressure | [Store](https://apps.garmin.com/apps/91c393da-910d-43e9-986f-8c2bbc84994c) |
| [Readiness](apps/readiness/) | Watch face | Body Battery and stress gauges, sleep score, recovery and resting heart rate round the time | in review |
| [Night Sky](apps/nightsky/) | Watch face | The real sky overhead: stars, constellations, the Moon and the planets | [Store](https://apps.garmin.com/apps/a9a5898b-4678-42e7-bb82-3ac7f378b438) |
| [Horizon](apps/horizon/) | Watch face | The bezel is the next twelve hours: rain chance per hour, dark after sunset, the next event | [Store](https://apps.garmin.com/apps/c4305cc0-41b2-4604-9ab0-87e40858e8a4) |
| [Today](apps/today/) | Watch face | One plain list: the next sunrise or sunset, 24-hour time, date, moon phase, heart rate, outside temperature, distance walked, alarms | [Store](https://apps.garmin.com/apps/b954d6a3-123c-4d78-ac5b-f61db6fe90d9) |
| [Strata](apps/strata/) | Watch face | The same list set into a field of soil layers that part round each reading; colours and the four readings are yours to choose | [Store](https://apps.garmin.com/apps/b19aa78e-870c-4bdd-8060-1d9b9e0e6279) |
| [Rings](apps/rings/) | Watch face | Three goal rings (steps, floors, Body Battery) with their numbers along the curves and the day's readings down the side, in three colour sets | [Store](https://apps.garmin.com/apps/607da8f9-d15c-4116-982d-faa381de3d5f) |
| [Forage](apps/forage/) | Watch face | For beekeepers: whether the bees are flying, when to open the hive, the next twelve hours as comb | [Store](https://apps.garmin.com/apps/65afb30e-8950-471a-bfda-65b926d8828f) |
| [Vessel](apps/vessel/) | Watch face | The time as two glasses that fill to your readings (the temperature and heart rate by default), the next sunrise or sunset at the foot | [Store](https://apps.garmin.com/apps/744760ba-2ee2-4c0d-ada9-12a7e502f9b6) |
| [Inscription](apps/inscription/) | Watch face | A coin: the time in the middle, the date and five readings set round the rim (the weather, the barometer and its trend, heart rate, steps, the next sunrise or sunset) | [Store](https://apps.garmin.com/apps/491cc91a-09e1-4fd9-b7f5-8dcc6eff0614) |
| [Overlap](apps/overlap/) | Watch face | The hours enormous and quiet behind bright minutes, cropped by the bezel, the date and two readings (the next sunrise or sunset and the temperature) | [Store](https://apps.garmin.com/apps/0b67fd07-dbf4-4bc6-974b-344c4d78593a) |
| [Lockup](apps/lockup/) | Watch face | Rows of numbers reaching the bezel all the way round, in numerals of its own, coloured by family | in review |
| [Blocks](apps/blocks/) | Watch face | The screen full of numbers, sized by importance and coloured by family: hours and minutes on a diagonal, the sun, weather and body readings around them, no labels | in review |
| [Wall](apps/wall/) | Watch face | A wall of small digits from your readings, where the time is the part that lights up, with a band of readings across the middle | in review |
| [Clack](apps/clack/) | Watch face | A split-flap clock with no case: four leaves that flip each minute as the mechanism does, the minutes you missed rolling by when you wake the watch, an amber lamp after sunset, five styles | in review |
| [Battery Planner](apps/battery/) | Glance + app | When to charge, projected from the last week's drain | in review |
| [Sun and Moon](apps/sunmoon/) | Glance + app | The next sun event, golden and blue hour and the moon, offline | [Store](https://apps.garmin.com/apps/58e942b4-a87e-475d-a9d4-1cf8ec00551c) |
| [Sun Compass](apps/suncompass/) | Glance + app | A compass rose with today's sun path drawn across it | [Store](https://apps.garmin.com/apps/80bfaa63-896c-417b-be49-b961ed2b4af4) |
| [Sauna and Steam](apps/sauna/) | Glance + app | Times a sauna or steam visit round by round, coaches it against the published guidance, saves it to Garmin Connect | [Store](https://apps.garmin.com/apps/a5da0e99-f413-4173-8cb2-54e90a7ab815) |
| [Tally](apps/tally/) | Glance + app | Buttons you make (on the phone, with the hours each shows), one tap to log, and the pattern over two weeks: a ring per day and what came before; every entry also goes to your own Google Sheet | in review |
| [Stretching God](apps/stretch/) | Glance + app | Guided stretching: 39 stretches drawn as a figure that eases in and holds, strung into 12 routines (morning, desk, bed, before and after a run, ride, hike or lifting), coached with a buzz for each turn, saved to Garmin Connect | [Store](https://apps.garmin.com/apps/23ceaee4-4ad6-4107-85dd-09e0e8deada4) |
| [Sound Level](apps/sound/) | Glance + app | **Experimental.** An approximate sound level meter from the watch microphone, with the NIOSH safe-exposure range | in review |

> **Sound Level is experimental.** Earlier builds that started and stopped
> the microphone repeatedly made a fēnix 8 restart itself (a firmware
> crash). The current build keeps one continuous capture, as the one
> other app known to work does, and has run without a crash, but use it
> at your own risk.

The designs are indexed in [`designs/README.md`](designs/README.md); the
notes and research behind them are kept privately, and this repository is
the published source of what ships.

## What they look like

The store screenshots, from the simulator with sample readings. Every
listing's cover and screenshots are in [`docs/store/`](docs/store/).

### Watch faces

<table>
<tr><td align="center"><img src="docs/store/field-screen.jpg" width="200" alt="Field"><br>Field</td><td align="center"><img src="docs/store/daylight-screen.jpg" width="200" alt="Daylight"><br>Daylight</td><td align="center"><img src="docs/store/readiness-screen.jpg" width="200" alt="Readiness"><br>Readiness</td><td align="center"><img src="docs/store/nightsky-screen.jpg" width="200" alt="Night Sky"><br>Night Sky</td></tr>
<tr><td align="center"><img src="docs/store/horizon-screen.jpg" width="200" alt="Horizon"><br>Horizon</td><td align="center"><img src="docs/store/today-screen.jpg" width="200" alt="Today"><br>Today</td><td align="center"><img src="docs/store/strata-screen.jpg" width="200" alt="Strata"><br>Strata</td><td align="center"><img src="docs/store/rings-screen.jpg" width="200" alt="Rings"><br>Rings</td></tr>
<tr><td align="center"><img src="docs/store/forage-screen.jpg" width="200" alt="Forage"><br>Forage</td><td align="center"><img src="docs/store/vessel-screen.jpg" width="200" alt="Vessel"><br>Vessel</td><td align="center"><img src="docs/store/inscription-screen.jpg" width="200" alt="Inscription"><br>Inscription</td><td align="center"><img src="docs/store/overlap-screen.jpg" width="200" alt="Overlap"><br>Overlap</td></tr>
<tr><td align="center"><img src="docs/store/lockup-screen.jpg" width="200" alt="Lockup"><br>Lockup</td><td align="center"><img src="docs/store/blocks-screen.jpg" width="200" alt="Blocks"><br>Blocks</td><td align="center"><img src="docs/store/wall-screen.jpg" width="200" alt="Wall"><br>Wall</td><td align="center"><img src="docs/store/clack-screen.jpg" width="200" alt="Clack"><br>Clack</td></tr>
</table>

**Their colours.** Each of these faces has high visibility in orange,
blue or green and a low-light look, set in its settings; Rings and
Strata have colour sets of their own as well.

<table>
<tr><th align="left">Field</th><td align="center"><img src="docs/store/field-look-default.jpg" width="130" alt="default"><br>default</td><td align="center"><img src="docs/store/field-look-orange.jpg" width="130" alt="high visibility"><br>high visibility</td><td align="center"><img src="docs/store/field-look-blue.jpg" width="130" alt="blue"><br>blue</td><td align="center"><img src="docs/store/field-look-green.jpg" width="130" alt="green"><br>green</td><td align="center"><img src="docs/store/field-look-low.jpg" width="130" alt="low light"><br>low light</td></tr>
<tr><th align="left" rowspan="2">Strata</th><td align="center"><img src="docs/store/strata-soil.jpg" width="130" alt="Soil"><br>Soil</td><td align="center"><img src="docs/store/strata-clay.jpg" width="130" alt="Clay"><br>Clay</td><td align="center"><img src="docs/store/strata-moss.jpg" width="130" alt="Moss"><br>Moss</td><td align="center"><img src="docs/store/strata-slate.jpg" width="130" alt="Slate"><br>Slate</td><td align="center"><img src="docs/store/strata-sand.jpg" width="130" alt="Sand"><br>Sand</td></tr>
<tr><td align="center"><img src="docs/store/strata-look-orange.jpg" width="130" alt="high visibility"><br>high visibility</td><td align="center"><img src="docs/store/strata-look-blue.jpg" width="130" alt="blue"><br>blue</td><td align="center"><img src="docs/store/strata-look-green.jpg" width="130" alt="green"><br>green</td><td align="center"><img src="docs/store/strata-look-low.jpg" width="130" alt="low light"><br>low light</td></tr>
<tr><th align="left" rowspan="2">Rings</th><td align="center"><img src="docs/store/rings-sunset.jpg" width="130" alt="Sunset"><br>Sunset</td><td align="center"><img src="docs/store/rings-berry.jpg" width="130" alt="Berry"><br>Berry</td><td align="center"><img src="docs/store/rings-forest.jpg" width="130" alt="Forest"><br>Forest</td></tr>
<tr><td align="center"><img src="docs/store/rings-look-orange.jpg" width="130" alt="high visibility"><br>high visibility</td><td align="center"><img src="docs/store/rings-look-blue.jpg" width="130" alt="blue"><br>blue</td><td align="center"><img src="docs/store/rings-look-green.jpg" width="130" alt="green"><br>green</td><td align="center"><img src="docs/store/rings-look-low.jpg" width="130" alt="low light"><br>low light</td></tr>
<tr><th align="left">Vessel</th><td align="center"><img src="docs/store/vessel-look-default.jpg" width="130" alt="default"><br>default</td><td align="center"><img src="docs/store/vessel-look-orange.jpg" width="130" alt="high visibility"><br>high visibility</td><td align="center"><img src="docs/store/vessel-look-blue.jpg" width="130" alt="blue"><br>blue</td><td align="center"><img src="docs/store/vessel-look-green.jpg" width="130" alt="green"><br>green</td><td align="center"><img src="docs/store/vessel-look-low.jpg" width="130" alt="low light"><br>low light</td></tr>
<tr><th align="left">Inscription</th><td align="center"><img src="docs/store/inscription-look-default.jpg" width="130" alt="default"><br>default</td><td align="center"><img src="docs/store/inscription-look-orange.jpg" width="130" alt="high visibility"><br>high visibility</td><td align="center"><img src="docs/store/inscription-look-blue.jpg" width="130" alt="blue"><br>blue</td><td align="center"><img src="docs/store/inscription-look-green.jpg" width="130" alt="green"><br>green</td><td align="center"><img src="docs/store/inscription-look-low.jpg" width="130" alt="low light"><br>low light</td></tr>
<tr><th align="left">Overlap</th><td align="center"><img src="docs/store/overlap-look-default.jpg" width="130" alt="default"><br>default</td><td align="center"><img src="docs/store/overlap-look-orange.jpg" width="130" alt="high visibility"><br>high visibility</td><td align="center"><img src="docs/store/overlap-look-blue.jpg" width="130" alt="blue"><br>blue</td><td align="center"><img src="docs/store/overlap-look-green.jpg" width="130" alt="green"><br>green</td><td align="center"><img src="docs/store/overlap-look-low.jpg" width="130" alt="low light"><br>low light</td></tr>
<tr><th align="left">Lockup</th><td align="center"><img src="docs/store/lockup-look-default.jpg" width="130" alt="default"><br>default</td><td align="center"><img src="docs/store/lockup-look-orange.jpg" width="130" alt="high visibility"><br>high visibility</td><td align="center"><img src="docs/store/lockup-look-blue.jpg" width="130" alt="blue"><br>blue</td><td align="center"><img src="docs/store/lockup-look-green.jpg" width="130" alt="green"><br>green</td><td align="center"><img src="docs/store/lockup-look-low.jpg" width="130" alt="low light"><br>low light</td></tr>
<tr><th align="left">Blocks</th><td align="center"><img src="docs/store/blocks-look-default.jpg" width="130" alt="default"><br>default</td><td align="center"><img src="docs/store/blocks-look-orange.jpg" width="130" alt="high visibility"><br>high visibility</td><td align="center"><img src="docs/store/blocks-look-blue.jpg" width="130" alt="blue"><br>blue</td><td align="center"><img src="docs/store/blocks-look-green.jpg" width="130" alt="green"><br>green</td><td align="center"><img src="docs/store/blocks-look-low.jpg" width="130" alt="low light"><br>low light</td></tr>
<tr><th align="left">Wall</th><td align="center"><img src="docs/store/wall-look-default.jpg" width="130" alt="default"><br>default</td><td align="center"><img src="docs/store/wall-look-orange.jpg" width="130" alt="high visibility"><br>high visibility</td><td align="center"><img src="docs/store/wall-look-blue.jpg" width="130" alt="blue"><br>blue</td><td align="center"><img src="docs/store/wall-look-green.jpg" width="130" alt="green"><br>green</td><td align="center"><img src="docs/store/wall-look-low.jpg" width="130" alt="low light"><br>low light</td></tr>
</table>

### Glances and apps

<table>
<tr><td align="center"><img src="docs/store/battery-screen.jpg" width="200" alt="Battery Planner"><br>Battery Planner</td><td align="center"><img src="docs/store/sunmoon-screen.jpg" width="200" alt="Sun and Moon"><br>Sun and Moon</td><td align="center"><img src="docs/store/suncompass-screen.jpg" width="200" alt="Sun Compass"><br>Sun Compass</td><td align="center"><img src="docs/store/sauna-1-round.jpg" width="200" alt="Sauna and Steam"><br>Sauna and Steam</td></tr>
<tr><td align="center"><img src="docs/store/tally-screen.jpg" width="200" alt="Tally"><br>Tally</td><td align="center"><img src="docs/store/stretch-1-hold.jpg" width="200" alt="Stretching God"><br>Stretching God</td><td align="center"><img src="docs/store/sound-screen.jpg" width="200" alt="Sound Level"><br>Sound Level</td></tr>
</table>

**More of Stretching God:** the opening card with the routine that suits
now, a stretch shown whole before it starts, a moving warm-up counting
its reps, and the slow breath before bed.

<table>
<tr><td align="center"><img src="docs/store/stretch-2-card.jpg" width="160" alt="Stretching God: the opening card"><br>the card</td><td align="center"><img src="docs/store/stretch-3-setup.jpg" width="160" alt="Stretching God: a stretch shown before it starts"><br>before it starts</td><td align="center"><img src="docs/store/stretch-4-reps.jpg" width="160" alt="Stretching God: a warm-up counting reps"><br>counting reps</td><td align="center"><img src="docs/store/stretch-5-breathe.jpg" width="160" alt="Stretching God: the slow breath"><br>the slow breath</td></tr>
</table>

**More of Sauna and Steam:** a visit's break, its rounds, the heart-rate
recovery after the last round, and past visits.

<table>
<tr><td align="center"><img src="docs/store/sauna-2-break.jpg" width="160" alt="Sauna and Steam: the break"><br>the break</td><td align="center"><img src="docs/store/sauna-3-rounds.jpg" width="160" alt="Sauna and Steam: the rounds"><br>the rounds</td><td align="center"><img src="docs/store/sauna-4-recovery.jpg" width="160" alt="Sauna and Steam: recovery"><br>recovery</td><td align="center"><img src="docs/store/sauna-5-visits.jpg" width="160" alt="Sauna and Steam: past visits"><br>past visits</td></tr>
</table>

## Supported watches

Built on the fēnix 8, and built for every round AMOLED Garmin watch on
Connect IQ 5.1 or later that has vector fonts (`scripts/devices.py` is
the list, and writes it into each manifest):

| Family | Watches |
|---|---|
| fēnix 8 (the ones on the desk) | fēnix 8 AMOLED 43 mm, 47/51 mm and Pro (47 mm, 51 mm and MicroLED), tactix 8 AMOLED, quatix 8 AMOLED and Pro (416 and 454 px) |
| fēnix 9 | fēnix 9 43 mm, 47/51 mm, Pro 43/47/51 mm, fēnix E (416, 454 and 466 px) |
| Forerunner | 165 and 165 Music, 170 and 170 Music, 265, 265S, 570 42/47 mm, 70, 965, 970 (360 to 454 px) |
| Venu and vívoactive | Venu 3, 3S, 4 41 mm, 4 45 mm, vívoactive 6 (390 and 454 px) |
| epix, MARQ, Descent, D2, Approach | epix (Gen 2) and Pro 42/47/51 mm, quatix 7 Sapphire and Pro, tactix 7 AMOLED, MARQ Gen 2 (Aviator, Commander Carbon too) and Gen 3, Descent Mk3 43 mm and Mk3i 51 mm, D2 Mach 1 and 1 Pro, Mach 2 and 2 Pro, D2 Air X15, Approach S70 42/47 mm and S72 43/47 mm |

Those are the 41 Connect IQ device ids, which the store lists as 48 watches.

Everything lays out relative to the screen size. Where a watch lacks a
font the faces use, the nearest it has stands in (the Venu 3's
Yantramanav for Roboto Condensed, for instance), and where it lacks a
button, a tap on that button's cue or a hold on the screen does its job.
Sound Level needs a microphone, so it is built for the API 6 watches
only. Not built for: the Venu 2 family, vívoactive 5, Approach S50,
Descent G2 and the Instinct 3 AMOLEDs (no vector fonts), the Venu X1
(rectangular) and the MIP watches.

## Get them on your watch

**From the Connect IQ Store.** The Store column in the table above links
each approved listing; the rest are in Garmin's review. Install from the
Connect IQ app on your phone, and updates arrive by themselves. (The listings and their store descriptions:
[`docs/STORE.md`](docs/STORE.md).)

**Build and copy them yourself.** You need the free Connect IQ SDK and a
free Garmin account (for the device files):

1. Set up the SDK, the device files and a developer key ([Setup](#setup)).
2. Build the app for your watch, for example
   `scripts/build.sh forage fenix847mm`. The result is
   `apps/forage/bin/forage.prg`.
3. Plug the watch in with its USB mode set to MTP (hold UP → Watch
   Settings → System → Advanced → USB Mode → MTP).
   - **Windows:** open the watch in File Explorer, go to
     *Internal Storage → GARMIN → Apps*, and copy the `.prg` in.
   - **macOS:** the watch does not mount as a drive. Drag the `.prg` into
     `GARMIN/Apps` with [OpenMTP](https://openmtp.ganeshrvel.com/), or use
     `scripts/watch.sh push forage` ([details](#sideload-to-the-watch)).
4. Unplug. The watch installs the app; pick a face under *Watch Face*,
   or open an app from the apps list.

A copied app is removed by deleting its `.prg` from `GARMIN/Apps` the same
way.

## License and credits

MIT, see [`LICENSE`](LICENSE). The Connect IQ SDK and the device files are
Garmin's and are not included. Night Sky's stars come from the Yale Bright
Star Catalogue (via
[Bright-Star-Catalog-JSON](https://github.com/aduboisforge/Bright-Star-Catalog-JSON)).
Sound Level's way of using the microphone follows the notes of the
[iTuner](https://github.com/bogdancvisan/garmin-tuner) instrument tuner;
no code was copied.

## For developers

- [`designs/README.md`](designs/README.md) indexes the designs by number;
  the previews (`designs/preview_*.py`) render each face with sample
  readings, and the generators (`designs/gen_*.py`) write the tables and
  fonts the code is built from.
- [`lib/`](lib/) is the `Lib` Monkey Barrel shared by every app: `Aod`
  (always-on helpers), `Arcs` (ring gauges), `Fmt` (text formatting), `Sun`
  (sunrise and sunset from the watch), `Moon` (phase), `Solar` (sun maths:
  position, golden and blue hour), `Location` (the last known position), `Sky`
  (sidereal time, the Sun, Moon and planets in the sky), `Cues` (the
  button cues at Garmin's hint angles, and which cue a touch landed on),
  `Daily` (the everyday readings Today, Strata and Rings share) and `Look`
  (the looks a hold on the time steps through: high visibility in orange,
  blue or green, low light,
  a persona a day).

> **Status:** Field compiles cleanly at the strict type-check level for the
> fēnix 8 Pro (`fenix8pro47mm`), the fēnix 8 47/51 mm (`fenix847mm`) and the
> fēnix 8 43 mm (`fenix843mm`), loads in the simulator, and its unit tests
> pass on all three (`scripts/test.sh field <device>`): every ring, footer
> and slot mode is drawn awake and in always-on mode without error, and the
> `Lib` maths is checked against known values. Code plus data is 13 KB of
> the 128 KB watch face budget. It has not been checked on a watch yet, and
> the simulator's Low Power Mode and burn-in checker still need a look by eye.
> Battery Planner builds cleanly for the same three devices and its seven
> tests pass (projection maths, the storage ring buffer, the background
> sampler, and drawing the glance and the app); the app looked right in the
> simulator. Sun and Moon builds cleanly too and its five tests pass (sun
> times within a minute of the NOAA calculator, the golden and blue hour
> windows, drawing). Daylight builds cleanly and its three tests pass (the
> light-left line, dial placement, drawing both modes). The simulator
> supplies a location (Garmin's Kansas office) for both, so their screens
> show real times. Night Sky builds cleanly and its five tests pass (Sun,
> Moon and planet positions against published ones, the catalogue, the
> projection, drawing both modes). Horizon builds cleanly and its four tests
> pass (a synthetic day through the model, the calendar time parser, the
> dial, drawing both modes). Sun Compass builds cleanly and its four tests
> pass (sun bearings against the NOAA calculator, the day's path, the
> bearing maths and smoothing, drawing the glance and the app). Readiness
> builds cleanly and its three tests pass (the text, reading the metrics,
> drawing every state in both modes and the press targets). Sauna and Steam builds cleanly at the
> strict level and its six tests pass (the text and units, a synthetic
> visit through the thermometer door detection and the recovery maths,
> the plan's coaching and the heat guard, the history and weekly counts,
> a FIT session, drawing every screen and the cues). Sound Level builds
> cleanly at the strict level and its seven tests pass (the level maths
> against synthetic sine windows, the NIOSH table and the dose, the
> session's smoothing, peak, energy average and buzz lines, the demo,
> the decode budget, the shared cues, drawing every screen); the
> microphone itself is only exercised in the live app. Forage builds
> cleanly at the strict level and its four tests pass (each rule for the
> bees, a synthetic day through the outlook and the hive window, the
> nectar year, drawing both modes).
> Today builds cleanly
> at the strict level for all three devices and its two tests pass
> (drawing both modes and the press targets, the sources). Strata builds
> cleanly for all three and its six tests pass (the generated layers,
> pieces and stones, the temperature palette, the colour settings, every
> reading kind, the heart-rate trace, drawing both modes, every setting
> and the press targets). Rings builds cleanly for all three and its
> three tests pass (the goal fractions and readings, drawing every ring
> state, every colour set and both modes, the ring geometry and press
> targets, the themes). Vessel, Inscription and Overlap build
> cleanly for all three and their tests pass: Vessel's six (the shared
> reading arithmetic, the barometer's trend and the weather from a
> temperature, every complication kind and its words, the accent
> lift and the digit ink, drawing every mode with full, empty and
> rangeless glasses, standby and the bedside clock, the press targets,
> the phone app's settings), and three each for Inscription and Overlap
> (drawing every mode, the press targets, the phone app's settings). Most apps have been copied to a fēnix 8 47 mm
> with `scripts/watch.sh`.

## Layout

```
apps/field/      Field watch face: manifest.xml, monkey.jungle, source/, tests/, resources/
apps/battery/    Battery Planner glance + app, same layout
apps/daylight/   Daylight watch face, same layout
apps/sunmoon/    Sun and Moon glance + app, same layout
apps/nightsky/   Night Sky watch face, same layout (Stars.mc is generated by designs/gen_stars.py)
apps/horizon/    Horizon watch face, same layout
apps/suncompass/ Sun Compass glance + app, same layout
apps/readiness/  Readiness watch face, same layout
apps/sauna/      Sauna and Steam glance + app, same layout (resources/settings/ holds the plans)
apps/sound/      Sound Level glance + app, same layout (the microphone, AudioInput)
apps/tally/      Tally glance + app, same layout (sheet/ holds the Google Sheet's script; settings from designs/gen_tally_settings.py)
apps/forage/     Forage watch face, same layout
apps/today/      Today watch face, same layout
apps/strata/     Strata watch face, same layout (Field.mc is generated by designs/gen_strata.py)
apps/rings/      Rings watch face, same layout
apps/vessel/     Vessel watch face, same layout (Inscription and Overlap likewise)
lib/             Lib barrel: manifest.xml, monkey.jungle, source/{Aod,Arcs,Fmt,Sun,Moon,Solar,Location,Sky,Cues,Daily,Slots,Icons,Config,Ink,Look}.mc
designs/         README.md (the index), gen_*.py, preview_*.py, store_key.py, fonts/
scripts/         build.sh, sim.sh, test.sh, package.sh, devices.py, simlock.sh, simprivate.sh, watch.sh, sdk-env.sh
```

Each app is its own Connect IQ project (open `apps/field/` as the VS Code
workspace folder). It links the barrel with two jungle lines:

```
base.barrelPath = ../../lib/monkey.jungle
base.Lib.annotations = aod;arcs;fmt;sun;moon
```

## Setup

1. Install Java 17+ and the Connect IQ SDK. Either use the
   [SDK Manager](https://developer.garmin.com/connect-iq/sdk/) (GUI, needs a
   Garmin login), or download the SDK directly: the list is at
   `https://developer.garmin.com/downloads/connect-iq/sdks/sdks.json`, unpack
   the macOS `.dmg` into `~/Library/Application Support/Garmin/ConnectIQ/Sdks/`
   and write that folder's path into `.../ConnectIQ/current-sdk.cfg`.
   SDK **9.3.0** is what this repo is built against.
2. Install VS Code and the **Monkey C** extension
   (`code --install-extension garmin.monkey-c`).
3. Download the **fēnix 8 Pro device files**. This needs a Garmin account.
   With the community CLI:

   ```sh
   brew install lindell/connect-iq-sdk-manager-cli/connect-iq-sdk-manager-cli
   connect-iq-sdk-manager agreement accept
   connect-iq-sdk-manager login                 # interactive Garmin sign-in
   connect-iq-sdk-manager device download --manifest apps/field/manifest.xml
   ```

   or open the SDK Manager, sign in, and download the fēnix 8 devices.
   The CLI stores them in `~/.Garmin/ConnectIQ/Devices/` and `Fonts/`; on macOS
   the SDK looks in `~/Library/Application Support/Garmin/ConnectIQ/`, so link
   those two folders there (`ln -s ~/.Garmin/ConnectIQ/Devices "~/Library/Application Support/Garmin/ConnectIQ/Devices"`,
   same for `Fonts`). `compiler.json` in each device folder is the source of
   truth for memory limits and the API level.
4. Generate a developer key once and keep it **outside** the repo (`*.der`
   and `*.pem` are gitignored):

   ```sh
   mkdir -p ~/.garmin
   openssl genrsa -out ~/.garmin/developer_key.pem 4096
   openssl pkcs8 -topk8 -inform PEM -outform DER \
     -in ~/.garmin/developer_key.pem -out ~/.garmin/developer_key.der -nocrypt
   ```

   Back this key up. A store app can only be updated with the key that signed it.

## Build and run

```sh
scripts/build.sh field                 # -> apps/field/bin/field.prg for fenix8pro47mm
scripts/build.sh field fenix843mm -l 3      # other device; extra args go to monkeyc (-l 3 = strict types)
scripts/sim.sh field                   # starts the simulator and loads the build
scripts/test.sh field [fenix843mm]     # builds with --unit-test and runs the tests in the simulator
scripts/build.sh battery && scripts/sim.sh battery   # same for the Battery Planner
scripts/build.sh sunmoon && scripts/sim.sh sunmoon   # and for Sun and Moon
scripts/build.sh daylight && scripts/sim.sh daylight # and for Daylight
scripts/build.sh nightsky && scripts/sim.sh nightsky # and for Night Sky
scripts/build.sh horizon && scripts/sim.sh horizon   # and for Horizon
scripts/build.sh suncompass && scripts/sim.sh suncompass   # and for Sun Compass
scripts/build.sh readiness && scripts/sim.sh readiness     # and for Readiness
scripts/build.sh sauna && scripts/sim.sh sauna             # and for Sauna
scripts/build.sh sound && scripts/sim.sh sound             # and for Sound Level (the simulator uses the Mac microphone)
scripts/build.sh forage && scripts/sim.sh forage           # and for Forage (likewise today, strata, rings, vessel, inscription, overlap)
```

`build.sh` and `test.sh` drop one expected monkeyc warning: a watch face
that links a glance-safe `Lib` module (`Fmt`, `Solar`, `Location`) is told
the `(:glance)` annotation is ignored, which is fine (see `CLAUDE.md`).

The simulator is **one process per Mac** (a second one exits at once),
and whoever loads an app into it replaces what anyone else was looking
at. Several sessions or worktrees working at the same time must therefore
take turns, by ID:

```sh
scripts/simlock.sh status          # who holds the simulator
scripts/simlock.sh claim 10        # take it for ten minutes (fails if another ID holds it)
scripts/simlock.sh wait 10         # or wait for it, then take it
scripts/simlock.sh release         # give it back
```

The ID defaults to the checkout's folder name, so worktrees differ;
`CIQ_SIM_ID` overrides it. `test.sh` claims and releases around a run,
`sim.sh` claims and keeps the claim while the app is on screen, and a
claim expires by itself so a dead session cannot hold the simulator.

Unit tests live in `apps/<app>/tests/`, are annotated `(:test)` and are left
out of normal builds. `monkeydo … -t` prints one line per test and a RESULTS
table, then exits. If it prints nothing at all, the simulator has a stale
connection: quit and reopen the simulator (`connectiq`) and run it again.

In the simulator, **Simulation → Background Events → Temporal Event** fires
the Battery Planner's sampler by hand, and Select in the app logs a sample.

The scripts read the SDK from `current-sdk.cfg` and the key from
`~/.garmin/developer_key.der` (override with `CIQ_DEVELOPER_KEY`). By hand:

```sh
cd apps/field
monkeyc -d fenix8pro47mm -f monkey.jungle -o bin/field.prg -y ~/.garmin/developer_key.der -w
monkeydo bin/field.prg fenix8pro47mm                    # simulator must be running
monkeyc -e -r -f monkey.jungle -o bin/field.iq -y ~/.garmin/developer_key.der   # store/beta package
```

In the simulator, use **Settings → Low Power Mode** to see the always-on
layout, **File → View Memory** to check peak memory against the watch face
limit, and the burn-in checker under Settings to verify the 10 % rule.

## Sideload to the watch

Connect the watch over USB with its USB mode set to MTP (hold UP → Watch
Settings → System → Advanced → USB Mode). It does not mount as a drive on
macOS; `scripts/watch.sh` talks to it with libmtp (`brew install libmtp`,
and quit Garmin Express or OpenMTP, which would hold the connection):

```sh
scripts/watch.sh queue [other-checkout ...]  # build every app here (and extra ones in other worktrees) into watch-queue/
scripts/watch.sh flush                     # copy the whole queue onto the watch, then empty it
scripts/watch.sh push field [fenix847mm]   # build and copy FIELD.PRG and its log file onto the watch
scripts/watch.sh ls                        # what is in GARMIN/Apps and GARMIN/Apps/LOGS
scripts/watch.sh logs                      # download the logs into watch-logs/ (gitignored)
scripts/watch.sh rm FIELD.PRG              # delete one file
```

`queue` needs no watch: it builds everything now, this checkout's apps
first and then any app another worktree has that this one lacks (an app
present in both is taken from here). `flush` is the one command to run
the next time the watch is on the cable; it waits for MTP, replaces each
app's earlier copy by name, and empties the queue.

The watch installs a `.prg` when the USB session ends, so unplug after a
push, then pick the face under *Watch Face* or the app from the apps
list. `System.println` output lands in `GARMIN/Apps/LOGS/<NAME>.TXT`
(push creates it) and a crash writes `CIQ_LOG.YML` beside it. The default
device is `fenix847mm`, the watch on the desk; `CIQ_WATCH_DEVICE`
overrides it. OpenMTP (`brew install --cask openmtp`) is the drag-and-drop
fallback.
