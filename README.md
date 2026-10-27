# garmin-widgets

Connect IQ watch faces, widgets and apps for the **Garmin fēnix 8 Pro** (47 mm / 51 mm
AMOLED and 51 mm MicroLED, all non-solar).

- [`EXPLORATION.md`](EXPLORATION.md) covers what the watch lets us modify:
  app types, APIs by SDK version, AMOLED rules, the toolchain, distribution,
  hard limits and open questions.
- [`designs/DESIGNS.md`](designs/DESIGNS.md) has the first designs, ranked (Field, Battery
  Planner, Daylight, Readiness, Sun & Moon), with mockups in `designs/svg/`.
- [`watchface/`](watchface/) is a starter AMOLED-aware watch face in Monkey C.

> **Status:** the starter face has not been compiled yet. Build it first and
> fix anything the compiler reports. See "Open questions" in `EXPLORATION.md`.

## Setup

1. Install Java (17 or later) and the
   [Connect IQ SDK Manager](https://developer.garmin.com/connect-iq/sdk/).
2. In the SDK Manager, install **SDK 9.3.x** and the **fēnix 8 Pro** device files.
3. Install VS Code and the **Monkey C** extension, then run
   *Monkey C: Verify Installation*.
4. Generate a developer key once and keep it **outside** the repo (`*.der` is
   gitignored):

   ```sh
   openssl genrsa -out ~/.garmin/developer_key.pem 4096
   openssl pkcs8 -topk8 -inform PEM -outform DER \
     -in ~/.garmin/developer_key.pem -out ~/.garmin/developer_key.der -nocrypt
   ```

   Back this key up. A store app can only be updated with the key that signed it.

## Build and run

From `watchface/`, with the SDK `bin/` directory on `PATH`:

```sh
# build for the simulator / a sideload
monkeyc -d fenix8pro47mm -f monkey.jungle -o bin/StarterFace.prg -y ~/.garmin/developer_key.der

# start the simulator, then load the build into it
connectiq &
monkeydo bin/StarterFace.prg fenix8pro47mm

# package for the Connect IQ Store (or a private beta upload)
monkeyc -e -r -f monkey.jungle -o bin/StarterFace.iq -y ~/.garmin/developer_key.der
```

In the simulator, use **Settings → Low Power Mode** to see the always-on
layout, and **File → View Memory** to check peak memory against the watch
face limit.

## Sideload to the watch

Connect the watch over USB. It shows up as an MTP device: use OpenMTP on macOS,
or `jmtpfs`/your file manager on Linux. Copy `bin/StarterFace.prg` into
`GARMIN/APPS/`, eject, then pick the face under *Watch Face* on the watch.
