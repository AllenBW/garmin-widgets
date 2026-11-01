import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

// What the glance and the app show for the current moment
(:glance)
class SunStatus {
    var located as Boolean = false;        // false: no position has ever been known
    var up as Boolean = false;             // the sun is above the horizon now
    var today as Lib.SunDay? = null;
    var nextIsRise as Boolean = true;
    var nextEvent as Number? = null;       // the next sunrise or sunset, Unix seconds
    var goldenNow as Boolean = false;
    var goldenAt as Number? = null;        // start of the next golden hour, or its end while goldenNow
    var blueNow as Boolean = false;
    var blueAt as Number? = null;          // start of the next blue hour, or its end while blueNow

    function initialize() {
    }
}

(:glance)
module SunModel {

    // The status right now, from the last known location
    function status(now as Number) as SunStatus {
        var where = Lib.Location.get();
        if (where == null) {
            return new SunStatus();
        }
        return statusAt(where[0], where[1], now);
    }

    function statusAt(lat as Float, lon as Float, now as Number) as SunStatus {
        var s = new SunStatus();
        s.located = true;
        var dayStart = localDayStart(now);
        var today = Lib.Solar.day(lat, lon, dayStart);
        var tomorrow = Lib.Solar.day(lat, lon, dayStart + 86400);
        s.today = today;

        // The next sunrise or sunset
        var rise = today.rise;
        var set = today.set;
        if (rise != null && now < rise) {
            s.nextIsRise = true;
            s.nextEvent = rise;
        } else if (set != null && now < set) {
            s.nextIsRise = false;
            s.nextEvent = set;
        } else {
            s.nextIsRise = true;
            s.nextEvent = tomorrow.rise;
        }

        // Golden hour is the sun between -4 and +6 degrees, blue hour between
        // -6 and -4. Whether we are in one comes from the sun's height now, so
        // a far-north winter day that never climbs past +6 is golden all day.
        // Its end, or the next one's start, is the next crossing of a band edge.
        var elevation = Lib.Solar.elevation(lat, lon, now);
        s.up = elevation > Lib.Solar.RISE_SET;
        s.goldenNow = elevation >= Lib.Solar.GOLDEN_LOW && elevation < Lib.Solar.GOLDEN_HIGH;
        s.goldenAt = nextCrossing(now, [
            today.goldenMorningStart, today.goldenMorningEnd, today.goldenEveningStart, today.goldenEveningEnd,
            tomorrow.goldenMorningStart, tomorrow.goldenMorningEnd, tomorrow.goldenEveningStart, tomorrow.goldenEveningEnd
        ] as Array<Number?>);
        s.blueNow = elevation >= Lib.Solar.BLUE_LOW && elevation < Lib.Solar.GOLDEN_LOW;
        s.blueAt = nextCrossing(now, [
            today.blueMorningStart, today.goldenMorningStart, today.goldenEveningEnd, today.blueEveningEnd,
            tomorrow.blueMorningStart, tomorrow.goldenMorningStart, tomorrow.goldenEveningEnd, tomorrow.blueEveningEnd
        ] as Array<Number?>);
        return s;
    }

    // The earliest of `times` after now, skipping the ones that never happen
    function nextCrossing(now as Number, times as Array<Number?>) as Number? {
        var best = null;
        for (var i = 0; i < times.size(); i++) {
            var t = times[i];
            if (t != null && t > now && (best == null || t < best)) {
                best = t;
            }
        }
        return best;
    }

    // Local midnight before `now`, Unix seconds
    function localDayStart(now as Number) as Number {
        var info = Gregorian.info(new Time.Moment(now), Time.FORMAT_SHORT);
        return now - (info.hour * 3600 + info.min * 60 + info.sec);
    }
}
