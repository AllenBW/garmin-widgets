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
- [`lib/`](lib/) is the `Lib` Monkey Barrel shared by every app: `Aod`
  (always-on helpers), `Arcs` (ring gauges), `Fmt` (text formatting), `Sun`
  (sunrise and sunset), `Moon` (phase).

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
> sampler, and drawing the glance and the app); it has not been looked at
> in the simulator or run on a watch yet.

## Layout

```
apps/field/      Field watch face: manifest.xml, monkey.jungle, source/, tests/, resources/
apps/battery/    Battery Planner glance + app, same layout
lib/             Lib barrel: manifest.xml, monkey.jungle, source/{Aod,Arcs,Fmt,Sun,Moon}.mc
designs/         DESIGNS.md, mockups.py, svg/
scripts/         build.sh, sim.sh, test.sh, sdk-env.sh
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
```

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

Connect the watch over USB. It shows up as an MTP device: use OpenMTP on macOS,
or `jmtpfs`/your file manager on Linux. Copy `apps/field/bin/field.prg` into
`GARMIN/APPS/`, eject, then pick the face under *Watch Face* on the watch.
