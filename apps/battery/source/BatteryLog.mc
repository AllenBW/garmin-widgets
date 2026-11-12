import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

// The battery log: written by the background service, read by the glance
// and the app. Stored flat in Application.Storage as
// [time, level, charging, time, level, charging, ...]: Unix seconds, whole
// percent, 0 or 1; oldest first; the newest MAX_SAMPLES are kept (eight
// days, so a full seven are always available).
(:background, :glance)
module BatteryLog {

    const KEY = "log";
    const STRIDE = 3;
    const SAMPLE_MINUTES = 30;
    const MAX_SAMPLES = 8 * 24 * 60 / SAMPLE_MINUTES;   // 384

    (:live)
    function samples() as Array<Number> {
        var value = Storage.getValue(KEY);
        if (value instanceof Array) {
            return value as Array<Number>;
        }
        return [] as Array<Number>;
    }

    // The sample build's log (sample.jungle), for the store screenshot: seven
    // and a half days of readings every half hour, about 12 % a day, twice
    // that the day before yesterday, a charge to full three days ago.
    // Normal builds leave it out.
    (:sample)
    function samples() as Array<Number> {
        var now = Time.now().value();
        var steps = 7 * 48 + 24;
        var clock = System.getClockTime();
        var heavyDay = now - (clock.hour * 3600 + clock.min * 60 + clock.sec) - 2 * 86400;
        var out = new [steps * STRIDE] as Array<Number>;
        var level = 92.0;
        for (var i = 0; i < steps; i++) {
            var t = now - (steps - 1 - i) * SAMPLE_MINUTES * 60;
            var hour = ((t / 3600) % 24).toNumber();
            var charging = (i >= 4 * 48 + 20 && i < 4 * 48 + 24);
            if (charging) {
                level = (level + 14.0 < 100.0) ? level + 14.0 : 100.0;
            } else {
                var drain = (hour >= 23 || hour < 7) ? 0.12 : ((hour >= 17 && hour < 19) ? 0.55 : 0.26);
                level -= (t >= heavyDay && t < heavyDay + 86400) ? 2 * drain : drain;
            }
            out[i * STRIDE] = t;
            out[i * STRIDE + 1] = (level + 0.5).toNumber();
            out[i * STRIDE + 2] = charging ? 1 : 0;
        }
        return out;
    }

    function count() as Number {
        return samples().size() / STRIDE;
    }

    // Append one sample, dropping the oldest beyond MAX_SAMPLES
    function record(time as Number, level as Number, charging as Boolean) as Void {
        var log = samples();
        var n = log.size() / STRIDE;
        if (n >= MAX_SAMPLES) {
            log = log.slice((n - MAX_SAMPLES + 1) * STRIDE, null);
        }
        log.add(time);
        log.add(level);
        log.add(charging ? 1 : 0);
        Storage.setValue(KEY, log as Array<Storage.ValueType>);
    }

    // Append the battery level right now; returns the number of samples
    function recordNow() as Number {
        var now = BatteryCharge.reading();
        record(Time.now().value(), (now[0] + 0.5).toNumber(), now[1]);
        return count();
    }

    // The battery as a whole percent
    function currentLevel() as Number {
        return (BatteryCharge.reading()[0] + 0.5).toNumber();
    }

    function clear() as Void {
        Storage.deleteValue(KEY);
    }
}
