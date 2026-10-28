import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Where the sun is now and where it goes during the day's daylight
(:glance)
class SunSky {
    var located as Boolean = false;        // false: no position has ever been known
    var alt as Float = 0.0;                // degrees above the horizon, now
    var az as Float = 0.0;                 // degrees clockwise from true north, now
    var up as Boolean = false;             // the upper limb is above the horizon
    var rise as Number? = null;            // the path's sunrise and sunset, Unix seconds
    var set as Number? = null;
    var riseAz as Float? = null;           // and the bearings they happen at
    var setAz as Float? = null;
    var hours as Array<[Float, Float]> = [] as Array<[Float, Float]>;   // [alt, az] at each full hour the sun is up
    var nextIsRise as Boolean = true;
    var nextEvent as Number? = null;       // the next sunrise or sunset
    var nextAz as Float? = null;

    function initialize() {
    }
}

(:glance)
module CompassModel {

    const POINTS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"] as Array<String>;

    // The sky right now, from the last known location
    function status(now as Number) as SunSky {
        var where = Lib.Location.get();
        if (where == null) {
            return new SunSky();
        }
        return statusAt(where[0], where[1], now);
    }

    function statusAt(lat as Float, lon as Float, now as Number) as SunSky {
        var s = new SunSky();
        s.located = true;
        var here = Lib.Solar.altAz(lat, lon, now);
        s.alt = here[0];
        s.az = here[1];
        s.up = s.alt >= Lib.Solar.RISE_SET;

        // The path: today's daylight, or tomorrow's once the sun has set
        var dayStart = localDayStart(now);
        var day = Lib.Solar.crossings(lat, lon, dayStart, Lib.Solar.RISE_SET);
        var set = day[1];
        if (set != null && now >= set) {
            dayStart += 86400;
            day = Lib.Solar.crossings(lat, lon, dayStart, Lib.Solar.RISE_SET);
        }
        var rise = day[0];
        set = day[1];
        s.rise = rise;
        s.set = set;
        if (rise != null) {
            s.riseAz = Lib.Solar.altAz(lat, lon, rise)[1];
        }
        if (set != null) {
            s.setAz = Lib.Solar.altAz(lat, lon, set)[1];
        }
        var hours = [] as Array<[Float, Float]>;
        for (var h = 0; h < 24; h++) {
            var pos = Lib.Solar.altAz(lat, lon, dayStart + h * 3600);
            if (pos[0] > 0.0) {
                hours.add(pos);
            }
        }
        s.hours = hours;

        // The next sunrise or sunset; neither in polar day or night
        if (rise != null && now < rise) {
            s.nextIsRise = true;
            s.nextEvent = rise;
            s.nextAz = s.riseAz;
        } else if (set != null && now < set) {
            s.nextIsRise = false;
            s.nextEvent = set;
            s.nextAz = s.setAz;
        }
        return s;
    }

    // Local midnight before `now`, Unix seconds
    function localDayStart(now as Number) as Number {
        var info = Gregorian.info(new Time.Moment(now), Time.FORMAT_SHORT);
        return now - (info.hour * 3600 + info.min * 60 + info.sec);
    }

    // "N", "NE", "E"... for a bearing in degrees, 45 degrees per point
    function cardinal(degrees as Float) as String {
        return POINTS[((norm360(degrees) + 22.5) / 45.0).toNumber() % 8];
    }

    // Degrees clockwise from true north for a Sensor heading in radians,
    // which the watch may report on either side of zero
    function headingDegrees(radians as Float) as Float {
        return norm360(Math.toDegrees(radians).toFloat());
    }

    // The signed short way round from one bearing to another, -180..180
    function angleDiff(from as Float, to as Float) as Float {
        var diff = to - from;
        if (diff > 180.0) {
            diff -= 360.0;
        } else if (diff < -180.0) {
            diff += 360.0;
        }
        return diff;
    }

    // A bearing moved part of the way towards a target, the short way round
    function smooth(current as Float, target as Float, fraction as Float) as Float {
        return norm360(current + angleDiff(current, target) * fraction);
    }

    function norm360(degrees as Float) as Float {
        return degrees - 360.0 * Math.floor(degrees / 360.0).toFloat();
    }
}
