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
`scripts/package.sh <app>` again and upload it as a new version from the
app's page (Upload New Version), with a version above the last one; the
listing carries over, and "What's New" says what changed. A beta app
(the Beta App box on the first step) is visible only to the developer
and cannot be made public: that takes a fresh upload under a new app id.

## Submitted and ready

The developer display name is **AllenBW**. Each listing's cover (500 × 500)
and screen image (454 × 454, the simulator's display cut round) are in
`docs/store/`.

| App | Store page | State |
|---|---|---|
| Strata | <https://apps.garmin.com/apps/b19aa78e-870c-4bdd-8060-1d9b9e0e6279> | Submitted 2026-10-31; 1.0.1 the same night, in review |
| Rings | <https://apps.garmin.com/apps/607da8f9-d15c-4116-982d-faa381de3d5f> | Submitted 2026-10-31; 1.0.1 the same night, in review |
| Sauna and Steam | <https://apps.garmin.com/apps/a5da0e99-f413-4173-8cb2-54e90a7ab815> | Submitted 2026-10-31; 1.0.1 the same night, in review |
| Forage | <https://apps.garmin.com/apps/65afb30e-8950-471a-bfda-65b926d8828f> | Submitted 2026-10-31, in review |
| Today | <https://apps.garmin.com/apps/b954d6a3-123c-4d78-ac5b-f61db6fe90d9> | Submitted 2026-10-31, in review |
| Daylight | <https://apps.garmin.com/apps/91c393da-910d-43e9-986f-8c2bbc84994c> | Submitted 2026-10-31, in review |
| Horizon | <https://apps.garmin.com/apps/c4305cc0-41b2-4604-9ab0-87e40858e8a4> | Submitted 2026-10-31, in review |
| Night Sky | <https://apps.garmin.com/apps/a9a5898b-4678-42e7-bb82-3ac7f378b438> | Submitted 2026-10-31, in review |
| Sun and Moon | <https://apps.garmin.com/apps/58e942b4-a87e-475d-a9d4-1cf8ec00551c> | Submitted 2026-10-31, in review |
| Sun Compass | <https://apps.garmin.com/apps/80bfaa63-896c-417b-be49-b961ed2b4af4> | Submitted 2026-10-31, in review |
| Sound Level | Beta app (only the developer sees it) | Submitted 2026-10-31 as a beta; going public needs a new app id in its manifest |
| Vessel | <https://apps.garmin.com/apps/744760ba-2ee2-4c0d-ada9-12a7e502f9b6> | Submitted 2026-10-31; 1.0.1 on 2026-11-01 (new defaults, larger text), in review |
| Inscription | <https://apps.garmin.com/apps/491cc91a-09e1-4fd9-b7f5-8dcc6eff0614> | Submitted 2026-10-31; 1.0.1 on 2026-11-01 (new defaults, larger text), in review |
| Overlap | <https://apps.garmin.com/apps/0b67fd07-dbf4-4bc6-974b-344c4d78593a> | Submitted 2026-10-31; 1.0.1 on 2026-11-01 (new defaults, larger text), in review |

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
altitude and the pressure trend (left out while you climb or descend).

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
from your phone; it says nothing rather than guess when the weather is
hours old. The time is in 24-hour form. The nectar calendar follows the
mid-Atlantic United States (Virginia, Maryland); elsewhere the seasons
along the bezel will be early or late.

**Today** (Watch face). One plain list and nothing else: the next sunrise
or sunset, the time in 24-hour form, the date, the moon and its phase,
heart rate, the outside temperature (in the watch's unit), distance walked
today and any alarms set. No settings.

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
readings: the hours fill to the temperature (between today's low and
high) and the minutes to your heart rate, each number sitting on its
waterline, and the next sunrise or sunset at the foot. Pick any reading for each glass and the foot
(complications from other apps too), any accent colour, a data colour and
one of three typefaces, in the watch's own face editor or the phone app.
Press and hold a reading to open it. A dim always-on mode keeps the
waterlines, and a red bedside clock takes over during your sleep hours.

**Inscription** (Watch face). A coin: the time struck large in the
middle, the date and five readings set round the rim in capitals inside
a beaded edge: the weather, the barometer with its trend, heart rate,
steps and the next sunrise or sunset. Choose each reading (complications from other apps
too), any accent colour, a data colour and the typeface (a serif by
default), in the watch's own face editor or the phone app. Press and hold
a reading to open it. A dim always-on mode and a red bedside clock during
your sleep hours.

**Overlap** (Watch face). A poster for your wrist: the hours enormous and
quiet, cropped by the edge of the screen and tinted by your accent, with
the minutes bright in front of them, the date and two readings tucked
below (the next sunrise or sunset and the temperature). Choose the readings (complications from other apps too), any
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
is, NIOSH's daily limit at that level (85 dB for 8 hours, half the time
for every 3 dB more), and a dose while the app is open. Past what the
microphone can read it says "too loud to measure" rather than showing a
number that is too low. It listens only while open, and never records,
stores or sends audio. Not a calibrated instrument and not a medical
device; calibrate it against a phone meter from the menu. If the
microphone stops sending sound, press BACK and open the app again.
