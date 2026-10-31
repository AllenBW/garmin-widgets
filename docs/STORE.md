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
