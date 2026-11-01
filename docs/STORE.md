# Publishing to the Connect IQ Store

Each app is its own store listing. Garmin reviews a submission in about
72 hours; until then it is visible only to the developer, who can install
it to test.

## Once

1. Sign in at <https://apps.garmin.com/developer/> with the Garmin account
   and accept the developer agreement.
2. Keep `~/.garmin/developer_key.der` backed up. Every later version of an
   app must be signed with the key that signed its first upload.

## Each app

1. `scripts/package.sh <app>` writes `dist/<app>.iq` (all three devices).
2. Submit an App → upload the `.iq`, then fill in the listing below.
3. Screenshots: load the app in the simulator (`scripts/sim.sh <app>
   fenix847mm`) and take the watch screen, awake and, for faces, in Low
   Power Mode. 454 × 454 PNG.
4. After approval, add the store link to the table in `README.md`.

To update, run
`scripts/package.sh <app>` again and upload it as a new version.

## Submitted and ready

The developer display name is **AllenBW**. Each listing's cover (500 × 500)
and screen image (454 × 454, the simulator's display cut round) are in
`docs/store/`.

| App | Store page | State |
|---|---|---|
| Strata | <https://apps.garmin.com/apps/b19aa78e-870c-4bdd-8060-1d9b9e0e6279> | Submitted 2026-10-31, in review |
| Rings | <https://apps.garmin.com/apps/607da8f9-d15c-4116-982d-faa381de3d5f> | Submitted 2026-10-31, in review |
| Sauna and Steam | <https://apps.garmin.com/apps/a5da0e99-f413-4173-8cb2-54e90a7ab815> | Submitted 2026-10-31, in review |
| Vessel | | Ready: `dist/vessel.iq`, `docs/store/vessel-*.jpg` |
| Inscription | | Ready: `dist/inscription.iq`, `docs/store/inscription-*.jpg` |
| Overlap | | Ready: `dist/overlap.iq`, `docs/store/overlap-*.jpg` |

Screenshots: the store takes at most five. Sauna and Steam has the demo
mode's screens (a round in the heat, the break, the rounds table, the
recovery chart, the visits), Rings its three colour sets, Strata Soil, Moss
and Clay. They were taken from throwaway copies of each app built in the
scratchpad (never committed): Sauna started straight into its demo at a
given screen, with no glance so the simulator opens the app, and the
faces with a setting's default changed and the watch-face editor's style
ignored (the simulator always reports the first style). Each copy needs
its own .prg name, since the simulator keeps settings by file name. The
store pages kept showing the first screenshot for a while after the edit
was saved.

Every upload so far showed "Status: Verified" with "Signature check
failed." beside it; Garmin's forum reports the same message on first
uploads with SDK 9.x, and the upload went through.

## Listings

Category, then the description. Every app is free, with no ads and no
data collected.

**Field** (Watch face). An everyday face: the time large and legible, a
24-hour daylight ring (or steps, or battery), three slots you choose
(heart rate, steps and Body Battery by default), the next sunrise or
sunset, and a row that lights up only for rain ahead, a falling barometer
or a lost phone. Built for the fēnix 8's AMOLED screen, with a dim
always-on mode that shifts each minute.

**Daylight** (Watch face). A 24-hour sun dial. The day's light runs round
the edge, with golden hours marked and how much light is left, plus
altitude and pressure.

**Readiness** (Watch face). Your body metrics without opening a widget:
Body Battery and stress gauges, sleep score, recovery time, resting heart
rate and training status round the time.

**Night Sky** (Watch face). The real sky over you right now: the bright
stars, the constellations, the Moon and the planets, worked out on the
watch from your last known position. No phone needed.

**Horizon** (Watch face). The bezel is the next twelve hours: the chance of
rain each hour, dark after sunset, and where the sun sets or rises and
your next calendar event fall.

**Forage** (Watch face). For beekeepers. Whether your bees are flying right
now, the next good hours to open the hive (warm, calm, dry, late morning to
mid-afternoon), the next twelve hours as a strip of comb, and the
beekeeper's year along the bottom of the bezel. Uses the hourly forecast
from your phone.

**Today** (Watch face). One plain list and nothing else: the next sunrise
or sunset, the time in 24-hour form, the date, the moon and its phase,
heart rate, the outside temperature, distance walked today and any alarms
set. No settings.

**Strata** (Watch face). The day's readings set into a field of soil
layers that part round each one like water round a stone. The time is cut
cleanly out of the layers, a stone turns up for every quarter mile walked,
and the moon sits at the foot. Choose the colours and what each of the
four readings shows (temperature, rain, heart rate, distance, Body
Battery, elevation, humidity, wind, battery or steps).

**Rings** (Watch face). Three goal rings open to the right (steps, floors
and Body Battery) with their numbers written along the curves, and the
day's readings down the right side. Three colour sets.

**Vessel** (Watch face). The time as two glasses that fill to your
readings: the hours fill to your Body Battery and the minutes to your
step goal, each number sitting on its waterline, and the next sunrise or
sunset at the foot. Pick any reading for each glass and the foot
(complications from other apps too), any accent colour, a data colour and
one of three typefaces, in the watch's own face editor or the phone app.
Press and hold a reading to open it. A dim always-on mode keeps the
waterlines, and a red bedside clock takes over during your sleep hours.

**Inscription** (Watch face). A coin: the time struck large in the
middle, the date and five readings set round the rim in small capitals
inside a beaded edge. Choose each reading (complications from other apps
too), any accent colour, a data colour and the typeface (a serif by
default), in the watch's own face editor or the phone app. Press and hold
a reading to open it. A dim always-on mode and a red bedside clock during
your sleep hours.

**Overlap** (Watch face). A poster for your wrist: the hours enormous and
quiet, cropped by the edge of the screen and tinted by your accent, with
the minutes bright in front of them, the date and two readings tucked
below. Choose the readings (complications from other apps too), any
accent colour, a data colour and one of three typefaces, in the watch's
own face editor or the phone app. A dim always-on mode and a red bedside
clock during your sleep hours.

**Battery Planner** (Widget). Tells you when to charge. It records the
battery every half hour, learns your drain over the last week and projects
the day you will need the charger.

**Sun and Moon** (Widget). The next sunrise or sunset, golden and blue
hour, and the moon's phase, worked out on the watch, offline.

**Sun Compass** (Widget). A compass rose that turns with the watch, with
today's path of the sun drawn across it: where it rises, where it is now
and where it sets.

**Sauna and Steam** (Health and fitness). Times a sauna or steam-room
visit round by round. The watch's thermometer notices the door, your heart
rate recovery is measured after each round, the coaching follows the
published guidance, every button has its job written beside it, and the
visit is saved to Garmin Connect.

**Sound Level** (Tools). Experimental. An approximate sound level meter
from the watch microphone: the level in decibels coloured by how loud it
is, how long it is safe to stay at that level (NIOSH: 85 dB for 8 hours,
half the time for every 3 dB more), and a dose while the app is open. Not
a calibrated instrument.
