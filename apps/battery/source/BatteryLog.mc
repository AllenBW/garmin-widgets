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

    function samples() as Array<Number> {
        var value = Storage.getValue(KEY);
        if (value instanceof Array) {
            return value as Array<Number>;
        }
        return [] as Array<Number>;
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
        var stats = System.getSystemStats();
        record(Time.now().value(), currentLevel(), stats.charging);
        return count();
    }

    // The battery as a whole percent
    function currentLevel() as Number {
        return (System.getSystemStats().battery + 0.5).toNumber();
    }

    function clear() as Void {
        Storage.deleteValue(KEY);
    }
}
