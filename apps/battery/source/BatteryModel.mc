import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

// What the glance and the app show, worked out from the battery log.
(:glance)
class BatterySummary {
    var level as Number = 0;                 // current charge, percent
    var pace as Float? = null;               // percent per day at the recent pace; null without history
    var paceDays as Number = 0;              // complete days behind the pace
    var hoursLeft as Float? = null;          // until empty at that pace
    var chargeBy as Time.Moment? = null;     // when the level reaches the reserve
    var drains as Array<Float?> = new [BatteryModel.DAYS] as Array<Float?>;   // percent lost per day, oldest first; null = no data
    var labels as Array<String> = new [BatteryModel.DAYS] as Array<String>;   // "W", "T", ...
    var dayStarts as Array<Number> = new [BatteryModel.DAYS] as Array<Number>; // local midnight of each day, Unix seconds
    var levels as Array<Number> = [] as Array<Number>;   // sparkline points, oldest first
    var watchDays as Float? = null;          // the watch's own estimate, the fallback

    function initialize() {
    }
}

(:glance)
module BatteryModel {

    const DAYS = 7;
    const RESERVE = 10;              // percent: "charge by" is when the level gets here
    const GAP = 3 * 3600;            // a longer gap between two samples is ignored
    const FULL_DAY = 20 * 3600;      // a day covered this well counts towards the pace
    const MIN_SPAN = 3 * 3600;       // with no complete day yet, this much history gives a rough pace
    const HEAVY = 1.5;               // a day this many times the pace is highlighted
    const SPARK_POINTS = 28;

    // The summary for the log at `now` (Unix seconds) with the battery at `level` percent
    function summarize(log as Array<Number>, now as Number, level as Number) as BatterySummary {
        var s = new BatterySummary();
        s.level = level;
        var stats = System.getSystemStats();
        s.watchDays = (stats has :batteryInDays) ? stats.batteryInDays : null;

        var today0 = dayStart(now);
        var drains = new [DAYS] as Array<Float>;
        var spans = new [DAYS] as Array<Number>;
        for (var i = 0; i < DAYS; i++) {
            s.dayStarts[i] = today0 - (DAYS - 1 - i) * 86400;
            s.labels[i] = dayLetter(s.dayStarts[i] + 43200);
            s.drains[i] = null;
            drains[i] = 0.0;
            spans[i] = 0;
        }

        // Drain between consecutive samples, skipping charging and gaps
        var stride = BatteryLog.STRIDE;
        var n = log.size() / stride;
        var totalDrain = 0.0;
        var totalSpan = 0;
        for (var k = 1; k < n; k++) {
            var t0 = log[(k - 1) * stride];
            var p0 = log[(k - 1) * stride + 1];
            var c0 = log[(k - 1) * stride + 2];
            var t1 = log[k * stride];
            var p1 = log[k * stride + 1];
            var c1 = log[k * stride + 2];
            if (c0 != 0 || c1 != 0 || p1 > p0 || t1 <= t0 || t1 - t0 > GAP) {
                continue;
            }
            var idx = DAYS - 1 - daysAgo(today0, t1);
            if (idx < 0) {
                continue;
            }
            drains[idx] += (p0 - p1).toFloat();
            spans[idx] += t1 - t0;
            totalDrain += p0 - p1;
            totalSpan += t1 - t0;
        }

        var complete = [] as Array<Float>;
        for (var i = 0; i < DAYS; i++) {
            if (spans[i] > 0) {
                s.drains[i] = drains[i];
            }
            if (spans[i] >= FULL_DAY) {
                complete.add(drains[i]);
            }
        }
        s.paceDays = complete.size();

        var pace = null;
        if (complete.size() > 0) {
            pace = median(complete);
        } else if (totalSpan >= MIN_SPAN) {
            pace = totalDrain * 86400.0 / totalSpan;
        }
        if (pace != null && pace > 0.0) {
            s.pace = pace;
            s.hoursLeft = level * 24.0 / pace;
            var toReserve = (level > RESERVE) ? (level - RESERVE) * 86400.0 / pace : 0.0;
            s.chargeBy = new Time.Moment(now + toReserve.toNumber());
        }
        s.levels = sparkline(log, SPARK_POINTS);
        return s;
    }

    // Index of the heaviest day when it stands out from the pace, else null
    function heavyDay(s as BatterySummary) as Number? {
        var pace = s.pace;
        if (pace == null) {
            return null;
        }
        var worst = null;
        var worstDrain = pace * HEAVY;
        for (var i = 0; i < DAYS; i++) {
            var d = s.drains[i];
            if (d != null && d > worstDrain) {
                worst = i;
                worstDrain = d;
            }
        }
        return worst;
    }

    // Local midnight before `now`, in Unix seconds
    function dayStart(now as Number) as Number {
        var info = Gregorian.info(new Time.Moment(now), Time.FORMAT_SHORT);
        return now - (info.hour * 3600 + info.min * 60 + info.sec);
    }

    // Whole days between a time and today's midnight: 0 for today, 1 for yesterday
    function daysAgo(today0 as Number, t as Number) as Number {
        if (t >= today0) {
            return 0;
        }
        return (today0 - t - 1) / 86400 + 1;
    }

    function dayLetter(t as Number) as String {
        var info = Gregorian.info(new Time.Moment(t), Time.FORMAT_MEDIUM);
        var letter = info.day_of_week.toString().substring(0, 1);
        return (letter != null) ? letter : "?";
    }

    function median(values as Array<Float>) as Float {
        var sorted = [] as Array<Float>;
        for (var i = 0; i < values.size(); i++) {
            var v = values[i];
            var j = 0;
            while (j < sorted.size() && sorted[j] < v) {
                j++;
            }
            sorted = sorted.slice(0, j).addAll([v]).addAll(sorted.slice(j, null));
        }
        var n = sorted.size();
        if (n % 2 == 1) {
            return sorted[n / 2];
        }
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0;
    }

    // Up to `points` battery levels spread evenly over the log, oldest first
    function sparkline(log as Array<Number>, points as Number) as Array<Number> {
        var stride = BatteryLog.STRIDE;
        var n = log.size() / stride;
        var out = [] as Array<Number>;
        if (n == 0) {
            return out;
        }
        if (points < 2) {
            points = 2;
        }
        // Every `step` samples from the first, plus the last: at most `points`
        var step = (n - 1 + points - 2) / (points - 1);
        if (step < 1) {
            step = 1;
        }
        for (var k = 0; k < n; k += step) {
            out.add(log[k * stride + 1]);
        }
        if ((n - 1) % step != 0) {
            out.add(log[(n - 1) * stride + 1]);
        }
        return out;
    }
}
