# garmin-widgets

Connect IQ watch faces, widgets and apps for the **Garmin fēnix 8 Pro** (47 mm / 51 mm
AMOLED and 51 mm MicroLED, all non-solar; one device ID, `fenix8pro47mm`).

- [`EXPLORATION.md`](EXPLORATION.md) covers what the watch lets us modify:
  app types, APIs by SDK version, AMOLED rules, the toolchain, distribution,
  hard limits and open questions.
- [`designs/DESIGNS.md`](designs/DESIGNS.md) has the first designs, ranked (Field, Battery
  Planner, Daylight, Readiness, Sun & Moon), with mockups in `designs/svg/`.
- [`apps/field/`](apps/field/) is **Field**, the everyday watch face (design #1).
- [`apps/battery/`](apps/battery/) is **Battery Planner**, a glance and app
  that projects when to charge from the last week's drain (design #2).
- [`apps/daylight/`](apps/daylight/) is **Daylight**, a 24 h sun-dial watch
  face with golden hours, light left, altitude and pressure (design #3).
- [`apps/sunmoon/`](apps/sunmoon/) is **Sun and Moon**, a glance and app with
  the next sun event, golden and blue hour and the moon, offline (design #5).
- [`apps/nightsky/`](apps/nightsky/) is **Night Sky**, a watch face showing
  the real sky overhead: stars, constellations, the Moon and the planets
  (design #6).
- [`apps/horizon/`](apps/horizon/) is **Horizon**, a watch face whose bezel
  is the next twelve hours: rain chance per hour, dark after sunset, the
  sun event and the next calendar event (design #7).
- [`apps/suncompass/`](apps/suncompass/) is **Sun Compass**, a glance and
  app: a compass rose that turns with the watch, with today's sun path
  drawn across the sky inside it (design #8).
- [`apps/readiness/`](apps/readiness/) is **Readiness**, a watch face with
  Body Battery and stress gauges, sleep score, recovery time, resting heart
  rate and training status round the time (design #4).
- [`apps/pocketqr/`](apps/pocketqr/) is **Pocket QR**, a glance and app
  that shows up to six QR codes set up in the Connect IQ app, full screen
  for scanning (design #9).
- [`apps/sauna/`](apps/sauna/) is **Sauna and Steam**, a glance and app
  that tracks a sauna or steam-room visit round by round and coaches it
  against the published guidance: the watch thermometer notices the
  door, the heart-rate recovery is measured after each round, every
  button has its job written beside it, each kind has its own plan and
  weekly goals, and the visit is saved to Garmin Connect (design #10).
- [`apps/sound/`](apps/sound/) is **Sound Level**, a glance and app that
  turns the watch microphone into an approximate sound level meter: the
  level in big digits coloured by its band, the NIOSH danger range (85 dB
  for 8 hours, half the time for every 3 dB more) as "safe for" and a
  dose that accumulates while the app is open, a two-minute trend, a
  calibration screen for matching a phone meter, and every button's job
  written beside it (design #14).
- [`lib/`](lib/) is the `Lib` Monkey Barrel shared by every app: `Aod`
  (always-on helpers), `Arcs` (ring gauges), `Fmt` (text formatting), `Sun`
  (sunrise and sunset from the watch), `Moon` (phase), `Solar` (sun maths:
  position, golden and blue hour), `Location` (the last known position), `Sky`
  (sidereal time, the Sun, Moon and planets in the sky) and `Cues` (the
  button cues at Garmin's hint angles, and which cue a touch landed on).

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
> drawing every state in both modes and the press targets). Pocket QR
> builds cleanly at the strict type-check level and its three tests pass
> (parsing the array setting, encoding a code, drawing the glance and the
> app and paging through codes). Sauna and Steam builds cleanly at the
> strict level and its six tests pass (the text and units, a synthetic
> visit through the thermometer door detection and the recovery maths,
> the plan's coaching and the heat guard, the history and weekly counts,
> a FIT session, drawing every screen and the cues). Sound Level builds
> cleanly at the strict level and its seven tests pass (the level maths
> against synthetic sine windows, the NIOSH table and the dose, the
> session's smoothing, peak, energy average and buzz lines, the demo,
> the decode budget, the shared cues, drawing every screen); the
> microphone itself is only exercised in the live app. All ten earlier
> apps have been copied to a
> fēnix 8 47 mm with `scripts/watch.sh`; none has been checked by eye on
> it yet.

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
apps/pocketqr/   Pocket QR glance + app, same layout (resources/settings/ holds the array setting)
apps/sauna/      Sauna and Steam glance + app, same layout (resources/settings/ holds the plans)
apps/sound/      Sound Level glance + app, same layout (the microphone, AudioInput)
lib/             Lib barrel: manifest.xml, monkey.jungle, source/{Aod,Arcs,Fmt,Sun,Moon,Solar,Location,Sky,Cues}.mc
designs/         DESIGNS.md, mockups.py, svg/
scripts/         build.sh, sim.sh, test.sh, watch.sh, sdk-env.sh
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
scripts/build.sh pocketqr && scripts/sim.sh pocketqr       # and for Pocket QR
scripts/build.sh sauna && scripts/sim.sh sauna             # and for Sauna
scripts/build.sh sound && scripts/sim.sh sound             # and for Sound Level (the simulator uses the Mac microphone)
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
