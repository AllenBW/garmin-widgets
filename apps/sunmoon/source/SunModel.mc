import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

// What the glance and the app show for the current moment
(:glance)
class SunStatus {
    var located as Boolean = false;        // false: no position has ever been known
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

        // Golden hour: -4 up to +6 in the morning, +6 down to -4 in the evening
        var golden = nextWindow(now, [
            [today.goldenMorningStart, today.goldenMorningEnd],
            [today.goldenEveningStart, today.goldenEveningEnd],
            [tomorrow.goldenMorningStart, tomorrow.goldenMorningEnd]
        ] as Array<[Number?, Number?]>);
        s.goldenNow = golden[0];
        s.goldenAt = golden[1];

        // Blue hour: -6 up to -4 in the morning, -4 down to -6 in the evening
        var blue = nextWindow(now, [
            [today.blueMorningStart, today.goldenMorningStart],
            [today.goldenEveningEnd, today.blueEveningEnd],
            [tomorrow.blueMorningStart, tomorrow.goldenMorningStart]
        ] as Array<[Number?, Number?]>);
        s.blueNow = blue[0];
        s.blueAt = blue[1];
        return s;
    }

    // Windows in time order: [inside one now?, the moment that matters]: the
    // end of the current window, or the start of the next one. Windows
    // missing a start (polar summer) are skipped.
    function nextWindow(now as Number, windows as Array<[Number?, Number?]>) as [Boolean, Number?] {
        for (var i = 0; i < windows.size(); i++) {
            var start = windows[i][0];
            var end = windows[i][1];
            if (start == null) {
                continue;
            }
            if (now < start) {
                return [false, start];
            }
            if (end != null && now < end) {
                return [true, end];
            }
        }
        return [false, null];
    }

    // Local midnight before `now`, Unix seconds
    function localDayStart(now as Number) as Number {
        var info = Gregorian.info(new Time.Moment(now), Time.FORMAT_SHORT);
        return now - (info.hour * 3600 + info.min * 60 + info.sec);
    }
}
