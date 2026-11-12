import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// How fast this watch charges, learnt on the charger, and how long a charge
// will take from it. A charge slows towards full, so the speed is kept per
// tenth of the battery: seconds per percent in each 10 % band, 0.0 until the
// band has been charged through once. It is stored apart from the log, which
// only goes back eight days: a watch that lasts three weeks is rarely on the
// charger. Runs in the background too (no Lib here).
(:background, :glance)
module BatteryCharge {

    const KEY = "charge";        // the learnt bands
    const LAST = "chargeAt";     // [time, level] of the reading the next one is measured from
    const EVERY = "every";       // minutes between background samples, when not SAMPLE_MINUTES
    const BANDS = 10;
    const BAND = 10.0;           // percent in a band
    const MIN_GAIN = 1.0;        // percent: less than this between two readings is not yet a speed
    const MAX_GAP = 20 * 60;     // seconds: readings further apart are not measured across
    const MIN_SECONDS = 5.0;     // per percent: anything faster is a clock change, not a charge
    const WEIGHT = 0.5;          // how far a band charged through once more moves towards the new speed
    const FAST_MINUTES = 5;      // the background samples this often on the charger (the shortest allowed)
    const FULL = 99.5;           // percent: full from here

    // The battery, percent, and whether the watch is on the charger
    (:live)
    function reading() as [Float, Boolean] {
        var stats = System.getSystemStats();
        return [stats.battery, stats.charging];
    }

    // The sample build off the charger (sample.jungle)
    (:sample, :shotidle)
    function reading() as [Float, Boolean] {
        return [System.getSystemStats().battery, false];
    }

    // The sample build on the charger at 64 % (sample-charge.jungle)
    (:sample, :shotcharge)
    function reading() as [Float, Boolean] {
        return [64.0, true];
    }

    (:live)
    function profile() as Array<Float> {
        var value = Storage.getValue(KEY);
        if (value instanceof Array && value.size() == BANDS) {
            return value as Array<Float>;
        }
        return blank();
    }

    // The sample builds' charger: empty to full in an hour and a half, the
    // last fifth taking a third of it
    (:sample)
    function profile() as Array<Float> {
        return [42.0, 42.0, 42.0, 42.0, 42.0, 43.0, 45.0, 50.0, 70.0, 110.0] as Array<Float>;
    }

    function blank() as Array<Float> {
        var bands = new [BANDS] as Array<Float>;
        for (var b = 0; b < BANDS; b++) {
            bands[b] = 0.0;
        }
        return bands;
    }

    // The bands after charging from `from` to `to` percent in `seconds`
    function learn(bands as Array<Float>, from as Float, to as Float, seconds as Number) as Array<Float> {
        if (to <= from || seconds <= 0) {
            return bands;
        }
        var each = seconds / (to - from);
        if (each < MIN_SECONDS) {
            return bands;
        }
        for (var b = 0; b < BANDS; b++) {
            var low = b * BAND;
            var high = low + BAND;
            var share = (((to < high) ? to : high) - ((from > low) ? from : low)) / BAND;
            if (share <= 0.0) {
                continue;
            }
            var known = bands[b];
            bands[b] = (known <= 0.0) ? each : known + (each - known) * WEIGHT * share;
        }
        return bands;
    }

    // Seconds per percent in a band: its own, or the nearest band's that has
    // one; null when nothing has been learnt
    function secondsEach(bands as Array<Float>, band as Number) as Float? {
        for (var d = 0; d < BANDS; d++) {
            if (band - d >= 0 && bands[band - d] > 0.0) {
                return bands[band - d];
            }
            if (band + d < BANDS && bands[band + d] > 0.0) {
                return bands[band + d];
            }
        }
        return null;
    }

    // Seconds on the charger from `level` to `target` percent; null when
    // nothing has been learnt
    function secondsTo(bands as Array<Float>, level as Float, target as Float) as Number? {
        var total = 0.0;
        for (var b = 0; b < BANDS; b++) {
            var low = b * BAND;
            var high = low + BAND;
            var span = ((target < high) ? target : high) - ((level > low) ? level : low);
            if (span <= 0.0) {
                continue;
            }
            var each = secondsEach(bands, b);
            if (each == null) {
                return null;
            }
            total += span * each;
        }
        return total.toNumber();
    }

    // Percent an hour at `level`; null when nothing has been learnt
    function perHour(bands as Array<Float>, level as Float) as Float? {
        var band = (level / BAND).toNumber();
        var each = secondsEach(bands, (band < BANDS) ? band : BANDS - 1);
        return (each != null) ? 3600.0 / each : null;
    }

    // A reading at `now`: on the charger it is measured against the one
    // before and the bands learn from the pair; off it the measuring stops.
    // The background samples every five minutes while the watch charges,
    // because half an hour is most of a charge.
    function observe(now as Number, level as Float, charging as Boolean) as Void {
        var last = Storage.getValue(LAST);
        if (!charging) {
            if (last != null) {
                Storage.deleteValue(LAST);
            }
            every(BatteryLog.SAMPLE_MINUTES);
            return;
        }
        every((level < FULL) ? FAST_MINUTES : BatteryLog.SAMPLE_MINUTES);
        if (last instanceof Array && last.size() == 2) {
            var seconds = now - (last[0] as Number);
            var before = (last[1] as Numeric).toFloat();
            if (seconds > 0 && seconds <= MAX_GAP && level >= before) {
                if (level - before < MIN_GAIN) {
                    return;   // keep measuring from the same reading
                }
                Storage.setValue(KEY, learn(profile(), before, level, seconds) as Array<Storage.ValueType>);
            }
        }
        Storage.setValue(LAST, [now, level] as Array<Storage.ValueType>);
    }

    // observe() with the watch's reading right now
    function check() as Void {
        var now = reading();
        observe(Time.now().value(), now[0], now[1]);
    }

    // Sample in the background every `minutes`, registering only on a change
    function every(minutes as Number) as Void {
        if (!(Toybox has :Background)) {
            return;
        }
        var set = Storage.getValue(EVERY);
        if (minutes.equals((set != null) ? set : BatteryLog.SAMPLE_MINUTES)) {
            return;
        }
        try {
            Background.registerForTemporalEvent(new Time.Duration(minutes * 60));
            Storage.setValue(EVERY, minutes);
        } catch (e) {
            // Nothing to do: the next reading will try again
        }
    }

    function clear() as Void {
        Storage.deleteValue(KEY);
        Storage.deleteValue(LAST);
    }
}
