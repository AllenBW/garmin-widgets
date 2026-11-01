import Toybox.Lang;
import Toybox.Math;

module Lib {

    // The times of one day's sun events: Unix seconds, or null when the sun
    // never reaches that altitude (polar day or night).
    (:solar, :glance)
    class SunDay {
        var rise as Number? = null;                 // upper limb on the horizon
        var set as Number? = null;
        var blueMorningStart as Number? = null;     // -6 degrees, going up
        var goldenMorningStart as Number? = null;   // -4
        var goldenMorningEnd as Number? = null;     // +6
        var goldenEveningStart as Number? = null;   // +6, going down
        var goldenEveningEnd as Number? = null;     // -4
        var blueEveningEnd as Number? = null;       // -6

        function initialize() {
        }
    }

    // Where the sun is and when it crosses a given altitude, from the NOAA
    // solar calculator equations (Meeus): good to about a minute. Pure maths
    // on latitude, longitude and time, so it works offline and needs no
    // permission. It carries the (:glance) annotation for the Sun & Moon
    // glance, which means watch faces must not link it (the compiler warns).
    (:solar, :glance)
    module Solar {

        const RISE_SET = -0.833;    // degrees: upper limb on the horizon, with refraction
        const GOLDEN_HIGH = 6.0;    // golden hour: the sun between +6 and -4 degrees
        const GOLDEN_LOW = -4.0;
        const BLUE_LOW = -6.0;      // blue hour: between -4 and -6 (civil twilight)

        // Everything for the local day starting at dayStart (Unix seconds)
        function day(lat as Float, lon as Float, dayStart as Number) as SunDay {
            var d = new SunDay();
            var riseSet = crossings(lat, lon, dayStart, RISE_SET);
            var golden = crossings(lat, lon, dayStart, GOLDEN_HIGH);
            var low = crossings(lat, lon, dayStart, GOLDEN_LOW);
            var blue = crossings(lat, lon, dayStart, BLUE_LOW);
            d.rise = riseSet[0];
            d.set = riseSet[1];
            d.goldenMorningEnd = golden[0];
            d.goldenEveningStart = golden[1];
            d.goldenMorningStart = low[0];
            d.goldenEveningEnd = low[1];
            d.blueMorningStart = blue[0];
            d.blueEveningEnd = blue[1];
            return d;
        }

        // [sunrise, sunset, tomorrow's sunrise] as seconds after dayStart, for
        // faces that lay the day out from local midnight. Polar day is light
        // from midnight until two days on, polar night never light.
        function riseSet(lat as Float, lon as Float, dayStart as Number) as [Number?, Number?, Number?] {
            var today = crossings(lat, lon, dayStart, RISE_SET);
            var rise = today[0];
            var set = today[1];
            if (rise == null || set == null) {
                var up = elevation(lat, lon, dayStart + 43200) > RISE_SET;
                return up ? [0, 2 * 86400, 0] : [0, 0, 2 * 86400];
            }
            var tomorrow = crossings(lat, lon, dayStart + 86400, RISE_SET)[0];
            return [rise - dayStart, set - dayStart, (tomorrow != null) ? tomorrow - dayStart : null];
        }

        // Unix seconds when the sun reaches `altitude` degrees on the local
        // day beginning at dayStart: [morning, evening], either null when it
        // never gets there.
        function crossings(lat as Float, lon as Float, dayStart as Number, altitude as Float) as [Number?, Number?] {
            // The UTC day whose solar noon (about 12:00 UTC less 4 minutes per
            // degree east) falls in this local day. Anchoring on clock noon
            // instead picks yesterday where the clock runs far ahead of the
            // sun, as in New Zealand's summer (UTC+13 at 175 E).
            var utcMidnight = ((dayStart + (lon * 240.0).toNumber() + 43200) / 86400) * 86400;
            return [crossing(lat, lon, utcMidnight, altitude, -1.0d), crossing(lat, lon, utcMidnight, altitude, 1.0d)];
        }

        // One crossing: side -1 for the morning, +1 for the evening. Two
        // passes, the second with the sun's position at the first estimate.
        function crossing(lat as Float, lon as Float, utcMidnight as Number, altitude as Float, side as Double) as Number? {
            var estimate = utcMidnight + 43200;
            var latR = rad(lat);
            var altR = rad(altitude);
            for (var pass = 0; pass < 2; pass++) {
                var pos = position(century(estimate));
                var decl = rad(pos[0]);
                var cosH = (Math.sin(altR) - Math.sin(latR) * Math.sin(decl)) / (Math.cos(latR) * Math.cos(decl));
                if (cosH > 1.0 || cosH < -1.0) {
                    return null;
                }
                var h = Math.toDegrees(Math.acos(cosH));
                var noon = 720.0d - 4.0d * lon - pos[1];   // minutes after UTC midnight
                estimate = utcMidnight + ((noon + side * 4.0d * h) * 60.0d).toNumber();
            }
            return estimate;
        }

        // The sun's altitude above the horizon, in degrees, at a Unix time
        function elevation(lat as Float, lon as Float, unix as Number) as Float {
            return altAz(lat, lon, unix)[0];
        }

        // Where the sun is at a Unix time: [altitude above the horizon,
        // azimuth clockwise from true north], both in degrees
        function altAz(lat as Float, lon as Float, unix as Number) as [Float, Float] {
            var pos = position(century(unix));
            var minutes = (unix % 86400).toDouble() / 60.0d;
            var hourAngle = rad(norm360((minutes + pos[1] + 4.0d * lon) / 4.0d) - 180.0d);
            var latR = rad(lat);
            var decl = rad(pos[0]);
            var cosH = Math.cos(hourAngle);
            var sinEl = Math.sin(latR) * Math.sin(decl) + Math.cos(latR) * Math.cos(decl) * cosH;
            if (sinEl > 1.0d) {
                sinEl = 1.0d;
            } else if (sinEl < -1.0d) {
                sinEl = -1.0d;
            }
            var az = Math.toDegrees(Math.atan2(Math.sin(hourAngle), cosH * Math.sin(latR) - Math.tan(decl) * Math.cos(latR))) + 180.0d;
            return [Math.toDegrees(Math.asin(sinEl)).toFloat(), norm360(az).toFloat()];
        }

        // Julian centuries since J2000.0 at a Unix time
        function century(unix as Number) as Double {
            return (unix.toDouble() / 86400.0d - 10957.5d) / 36525.0d;
        }

        // [declination in degrees, equation of time in minutes] at century t
        function position(t as Double) as [Double, Double] {
            var l0 = norm360(280.46646d + t * (36000.76983d + t * 0.0003032d));
            var m = norm360(357.52911d + t * (35999.05029d - 0.0001537d * t));
            var e = 0.016708634d - t * (0.000042037d + 0.0000001267d * t);
            var mr = rad(m);
            var c = Math.sin(mr) * (1.914602d - t * (0.004817d + 0.000014d * t))
                + Math.sin(2.0d * mr) * (0.019993d - 0.000101d * t)
                + Math.sin(3.0d * mr) * 0.000289d;
            var omega = rad(125.04d - 1934.136d * t);
            var lambda = l0 + c - 0.00569d - 0.00478d * Math.sin(omega);
            var eps0 = 23.0d + (26.0d + (21.448d - t * (46.815d + t * (0.00059d - t * 0.001813d))) / 60.0d) / 60.0d;
            var eps = rad(eps0 + 0.00256d * Math.cos(omega));
            var decl = Math.toDegrees(Math.asin(Math.sin(eps) * Math.sin(rad(lambda))));
            var y = Math.tan(eps / 2.0d);
            y = y * y;
            var l0r = rad(l0);
            var eot = 4.0d * Math.toDegrees(y * Math.sin(2.0d * l0r) - 2.0d * e * Math.sin(mr)
                + 4.0d * e * y * Math.sin(mr) * Math.cos(2.0d * l0r)
                - 0.5d * y * y * Math.sin(4.0d * l0r) - 1.25d * e * e * Math.sin(2.0d * mr));
            return [decl.toDouble(), eot.toDouble()];
        }

        function rad(degrees as Decimal) as Decimal {
            return Math.toRadians(degrees);
        }

        function norm360(degrees as Decimal) as Double {
            var d = degrees.toDouble();
            return d - 360.0d * Math.floor(d / 360.0d).toDouble();
        }
    }
}
