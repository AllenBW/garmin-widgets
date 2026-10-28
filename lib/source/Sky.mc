import Toybox.Lang;
import Toybox.Math;

module Lib {

    // Where things are in the sky: sidereal time, equatorial to horizontal
    // coordinates, and the Sun, Moon and bright planets from Paul Schlyter's
    // low-precision method (a degree or so, plenty for a watch). Angles are
    // degrees; times are Unix seconds. Pure maths, no permissions.
    (:sky)
    module Sky {

        const VENUS = 0;
        const MARS = 1;
        const JUPITER = 2;
        const SATURN = 3;

        // Greenwich mean sidereal time in degrees
        function gmst(unix as Number) as Double {
            var days = unix.toDouble() / 86400.0d - 10957.5d;   // since J2000.0
            return norm360(280.46061837d + 360.98564736629d * days);
        }

        // Local sidereal time in degrees at longitude lon (east positive)
        function lst(unix as Number, lon as Float) as Double {
            return norm360(gmst(unix) + lon);
        }

        // Altitude and azimuth (degrees, azimuth from north through east) of a
        // point at right ascension ra and declination dec, seen from latitude
        // lat with local sidereal time lst
        function altAz(ra as Decimal, dec as Decimal, lat as Decimal, lst as Decimal) as [Float, Float] {
            var h = rad(lst - ra);
            var decR = rad(dec);
            var latR = rad(lat);
            var sinAlt = Math.sin(decR) * Math.sin(latR) + Math.cos(decR) * Math.cos(latR) * Math.cos(h);
            if (sinAlt > 1.0) {
                sinAlt = 1.0;    // rounding at the zenith
            } else if (sinAlt < -1.0) {
                sinAlt = -1.0;
            }
            var alt = Math.toDegrees(Math.asin(sinAlt));
            var az = Math.toDegrees(Math.atan2(Math.sin(h), Math.cos(h) * Math.sin(latR) - Math.tan(decR) * Math.cos(latR))) + 180.0d;
            return [alt.toFloat(), norm360(az).toFloat()];
        }

        // Days since 1999-12-31 00:00 UTC, the epoch of Schlyter's elements
        function daysSince2000(unix as Number) as Double {
            return unix.toDouble() / 86400.0d - 10956.0d;
        }

        // The Sun's [right ascension, declination]
        function sun(unix as Number) as [Float, Float] {
            var d = daysSince2000(unix);
            var s = sunEcliptic(d);
            return equatorial(s[0], s[1], 0.0d, d);
        }

        // The Moon's [right ascension, declination], geocentric
        function moon(unix as Number) as [Float, Float] {
            var d = daysSince2000(unix);
            var n = 125.1228d - 0.0529538083d * d;
            var w = 318.0634d + 0.1643573223d * d;
            var m = norm360(115.3654d + 13.0649929509d * d);
            var p = orbit(n, 5.1454d, w, 60.2666d, 0.054900d, m);
            var lon = norm360(Math.toDegrees(Math.atan2(p[1], p[0])));
            var lat = Math.toDegrees(Math.atan2(p[2], Math.sqrt(p[0] * p[0] + p[1] * p[1]))).toDouble();
            // The main perturbations by the Sun
            var ms = norm360(356.0470d + 0.9856002585d * d);
            var ls = norm360(ms + 282.9404d + 4.70935e-5d * d);
            var lm = norm360(m + w + n);
            var dd = norm360(lm - ls);
            var f = norm360(lm - n);
            lon += -1.274d * sinDeg(m - 2 * dd) + 0.658d * sinDeg(2 * dd) - 0.186d * sinDeg(ms)
                - 0.059d * sinDeg(2 * m - 2 * dd) - 0.057d * sinDeg(m - 2 * dd + ms) + 0.053d * sinDeg(m + 2 * dd)
                + 0.046d * sinDeg(2 * dd - ms) + 0.041d * sinDeg(m - ms) - 0.035d * sinDeg(dd)
                - 0.031d * sinDeg(m + ms) - 0.015d * sinDeg(2 * f - 2 * dd) + 0.011d * sinDeg(m - 4 * dd);
            lat += -0.173d * sinDeg(f - 2 * dd) - 0.055d * sinDeg(m - f - 2 * dd) - 0.046d * sinDeg(m + f - 2 * dd)
                + 0.033d * sinDeg(f + 2 * dd) + 0.017d * sinDeg(2 * m + f);
            var cl = cosDeg(lat);
            return equatorial(cosDeg(lon) * cl, sinDeg(lon) * cl, sinDeg(lat), d);
        }

        // A planet's [right ascension, declination], geocentric
        function planet(which as Number, unix as Number) as [Float, Float] {
            var d = daysSince2000(unix);
            var p;
            if (which == VENUS) {
                p = orbit(76.6799d + 2.46590e-5d * d, 3.3946d + 2.75e-8d * d, 54.8910d + 1.38374e-5d * d,
                          0.723330d, 0.006773d - 1.302e-9d * d, norm360(48.0052d + 1.6021302244d * d));
            } else if (which == MARS) {
                p = orbit(49.5574d + 2.11081e-5d * d, 1.8497d - 1.78e-8d * d, 286.5016d + 2.92961e-5d * d,
                          1.523688d, 0.093405d + 2.516e-9d * d, norm360(18.6021d + 0.5240207766d * d));
            } else if (which == JUPITER) {
                p = orbit(100.4542d + 2.76854e-5d * d, 1.3030d - 1.557e-7d * d, 273.8777d + 1.64505e-5d * d,
                          5.20256d, 0.048498d + 4.469e-9d * d, norm360(19.8950d + 0.0830853001d * d));
            } else {
                p = orbit(113.6634d + 2.38980e-5d * d, 2.4886d - 1.081e-7d * d, 339.3939d + 2.97661e-5d * d,
                          9.55475d, 0.055546d - 9.499e-9d * d, norm360(316.9670d + 0.0334442282d * d));
            }
            var r = Math.sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2]).toDouble();
            var lon = norm360(Math.toDegrees(Math.atan2(p[1], p[0])));
            var lat = Math.toDegrees(Math.atan2(p[2], Math.sqrt(p[0] * p[0] + p[1] * p[1]))).toDouble();
            if (which == JUPITER || which == SATURN) {
                var mj = norm360(19.8950d + 0.0830853001d * d);
                var ms = norm360(316.9670d + 0.0334442282d * d);
                if (which == JUPITER) {
                    lon += -0.332d * sinDeg(2 * mj - 5 * ms - 67.6d) - 0.056d * sinDeg(2 * mj - 2 * ms + 21.0d)
                        + 0.042d * sinDeg(3 * mj - 5 * ms + 21.0d) - 0.036d * sinDeg(mj - 2 * ms)
                        + 0.022d * cosDeg(mj - ms) + 0.023d * sinDeg(2 * mj - 3 * ms + 52.0d)
                        - 0.016d * sinDeg(mj - 5 * ms - 69.0d);
                } else {
                    lon += 0.812d * sinDeg(2 * mj - 5 * ms - 67.6d) - 0.229d * cosDeg(2 * mj - 4 * ms - 2.0d)
                        + 0.119d * sinDeg(mj - 2 * ms - 3.0d) + 0.046d * sinDeg(2 * mj - 6 * ms - 69.0d)
                        + 0.014d * sinDeg(mj - 3 * ms + 32.0d);
                    lat += -0.020d * cosDeg(2 * mj - 4 * ms - 2.0d) + 0.018d * sinDeg(2 * mj - 6 * ms - 49.0d);
                }
            }
            var cl = cosDeg(lat);
            var s = sunEcliptic(d);
            return equatorial(r * cosDeg(lon) * cl + s[0], r * sinDeg(lon) * cl + s[1], r * sinDeg(lat), d);
        }

        // The Sun's geocentric ecliptic [x, y] in AU
        function sunEcliptic(d as Double) as [Double, Double] {
            var p = orbit(0.0d, 0.0d, 282.9404d + 4.70935e-5d * d, 1.0d, 0.016709d - 1.151e-9d * d,
                          norm360(356.0470d + 0.9856002585d * d));
            return [p[0], p[1]];
        }

        // Heliocentric (or geocentric, for the Moon and Sun) ecliptic [x, y, z]
        // from orbital elements: ascending node, inclination, argument of
        // perihelion, semi-major axis, eccentricity, mean anomaly
        function orbit(n as Double, i as Double, w as Double, a as Double, e as Double, m as Double) as [Double, Double, Double] {
            var ea = m + Math.toDegrees(e * sinDeg(m) * (1.0d + e * cosDeg(m))).toDouble();
            for (var k = 0; k < 4; k++) {
                ea = ea - (ea - Math.toDegrees(e * sinDeg(ea)).toDouble() - m) / (1.0d - e * cosDeg(ea));
            }
            var x = a * (cosDeg(ea) - e);
            var y = a * Math.sqrt(1.0d - e * e).toDouble() * sinDeg(ea);
            var v = Math.toDegrees(Math.atan2(y, x)).toDouble();
            var r = Math.sqrt(x * x + y * y).toDouble();
            var vw = v + w;
            return [
                r * (cosDeg(n) * cosDeg(vw) - sinDeg(n) * sinDeg(vw) * cosDeg(i)),
                r * (sinDeg(n) * cosDeg(vw) + cosDeg(n) * sinDeg(vw) * cosDeg(i)),
                r * sinDeg(vw) * sinDeg(i)
            ];
        }

        // Ecliptic xyz -> [right ascension, declination] in degrees
        function equatorial(x as Double, y as Double, z as Double, d as Double) as [Float, Float] {
            var ecl = 23.4393d - 3.563e-7d * d;
            var yq = y * cosDeg(ecl) - z * sinDeg(ecl);
            var zq = y * sinDeg(ecl) + z * cosDeg(ecl);
            var ra = norm360(Math.toDegrees(Math.atan2(yq, x)));
            var dec = Math.toDegrees(Math.atan2(zq, Math.sqrt(x * x + yq * yq)));
            return [ra.toFloat(), dec.toFloat()];
        }

        function sinDeg(degrees as Decimal) as Double {
            return Math.sin(Math.toRadians(degrees)).toDouble();
        }

        function cosDeg(degrees as Decimal) as Double {
            return Math.cos(Math.toRadians(degrees)).toDouble();
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
