import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Night Sky: the real sky over the watch. The bezel is the horizon, the
// centre is straight up, north at the top and east on the left, the way a
// sky looks when you lie back and look at it. Stars to magnitude 3.6 with
// the familiar constellation lines, the Moon with its phase, Venus, Mars,
// Jupiter and Saturn, and by day the Sun. All of it rotates with the
// sidereal clock, from the last known location, with no network.
//
// Always-on: the twenty brightest stars up right now as single dim dots,
// and the hollow time, shifted a few pixels each minute.
class NightSkyView extends WatchUi.WatchFace {

    private const WHITE = 0xF2F2F2;
    private const STAR2 = 0xC8C8C8;
    private const STAR3 = 0x8A8A8A;
    private const STAR4 = 0x5A5A5A;
    private const GRAY = 0x8A8A8A;
    private const DIM = 0x5A5A5A;
    private const LINE = 0x161E33;
    private const AMBER = 0xFFB020;
    private const MARS = 0xFF6B4A;
    private const JUPITER = 0xF2E6C8;
    private const SATURN = 0xE8D8A0;
    private const VENUS = 0xFFFFFF;

    private const DAY_ALTITUDE = -6.0;   // the Sun above this: daytime, stars dimmed
    private const AOD_STARS = 80;        // always-on looks only at the brightest 80 for its 20 dots

    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;
    private var _minute as Number = -1;        // minute the sky was last placed
    private var _fullMinute as Number = -1;    // minute every star was placed (always-on does fewer)

    private var _located as Boolean = false;
    private var _lat as Float = 0.0;
    private var _lst as Double = 0.0d;
    private var _day as Boolean = false;
    private var _sun as [Float, Float] = [-90.0, 0.0];      // altitude, azimuth
    private var _moon as [Float, Float] = [-90.0, 0.0];
    private var _planets as Array<[Float, Float]> = [[-90.0, 0.0], [-90.0, 0.0], [-90.0, 0.0], [-90.0, 0.0]] as Array<[Float, Float]>;

    // Screen position of every catalogue star this minute, -1 when below the horizon
    private var _sx as Array<Number> = new [Stars.COUNT] as Array<Number>;
    private var _sy as Array<Number> = new [Stars.COUNT] as Array<Number>;
    // sin and cos of each star's declination, once
    private var _sinDec as Array<Float> = new [Stars.COUNT] as Array<Float>;
    private var _cosDec as Array<Float> = new [Stars.COUNT] as Array<Float>;

    private var _dateFont as FontType = Graphics.FONT_XTINY;
    private var _labelFont as FontType = Graphics.FONT_XTINY;

    function initialize() {
        WatchFace.initialize();
        _burnIn = Lib.Aod.required();
        for (var i = 0; i < Stars.COUNT; i++) {
            _sx[i] = -1;
            _sy[i] = -1;
            var decR = Math.toRadians(Stars.DEC[i] / 10.0);
            _sinDec[i] = Math.sin(decR).toFloat();
            _cosDec[i] = Math.cos(decR).toFloat();
        }
    }

    function onLayout(dc as Dc) as Void {
        var h = dc.getHeight();
        _dateFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.046).toNumber(), Graphics.FONT_XTINY);
        _labelFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.036).toNumber(), Graphics.FONT_XTINY);
    }

    function onUpdate(dc as Dc) as Void {
        refresh(dc.getWidth(), dc.getHeight(), _awake || !_burnIn);
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (!_awake && _burnIn) {
            drawAlwaysOn(dc);
        } else {
            drawActive(dc);
        }
    }

    function onEnterSleep() as Void {
        _awake = false;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _awake = true;
        WatchUi.requestUpdate();
    }

    // ----------------------------------------------------------------- sky

    // Once a minute: where everything is, from the last known location.
    // `full` places every star; always-on only needs the brightest.
    function refresh(w as Number, h as Number, full as Boolean) as Void {
        var minute = System.getClockTime().min;
        var sameMinute = (minute == _minute);
        if (sameMinute && (!full || _fullMinute == minute)) {
            return;
        }
        if (!sameMinute) {
            _minute = minute;
            var where = Lib.Location.get();
            _located = (where != null);
            if (where == null) {
                return;
            }
            _lat = where[0];
            var now = Time.now().value();
            _lst = Lib.Sky.lst(now, where[1]);
            var sun = Lib.Sky.sun(now);
            _sun = Lib.Sky.altAz(sun[0], sun[1], _lat, _lst);
            _day = _sun[0] > DAY_ALTITUDE;
            var moon = Lib.Sky.moon(now);
            _moon = Lib.Sky.altAz(moon[0], moon[1], _lat, _lst);
            for (var p = 0; p < 4; p++) {
                var radec = Lib.Sky.planet(p, now);
                _planets[p] = Lib.Sky.altAz(radec[0], radec[1], _lat, _lst);
            }
        }
        if (!_located) {
            return;
        }
        placeStars(w, h, full ? Stars.COUNT : AOD_STARS);
        if (full) {
            _fullMinute = minute;
        }
    }

    // Screen positions for the first `count` stars (unshifted: the always-on
    // view adds its offset). The same maths as Lib.Sky.altAz, inlined with
    // the declinations precomputed and no allocation per star, since this
    // runs for hundreds of stars every minute.
    private function placeStars(w as Number, h as Number, count as Number) as Void {
        var cx = w / 2;
        var cy = h / 2;
        var scale = horizonRadius(w) / 90.0;
        var lst = _lst.toFloat();
        var latR = Math.toRadians(_lat);
        var sinLat = Math.sin(latR).toFloat();
        var cosLat = Math.cos(latR).toFloat();
        for (var i = 0; i < Stars.COUNT; i++) {
            if (i >= count) {
                _sx[i] = -1;
                continue;
            }
            var hR = Math.toRadians(lst - Stars.RA[i] / 10.0);
            var cosH = Math.cos(hR).toFloat();
            var sinAlt = _sinDec[i] * sinLat + _cosDec[i] * cosLat * cosH;
            if (sinAlt <= 0.0) {
                _sx[i] = -1;
                continue;
            }
            if (sinAlt > 1.0) {
                sinAlt = 1.0;
            }
            var alt = Math.toDegrees(Math.asin(sinAlt)).toFloat();
            var azR = Math.atan2(Math.sin(hR), cosH * sinLat - (_sinDec[i] / _cosDec[i]) * cosLat).toFloat() + Math.PI;
            var d = (90.0 - alt) * scale;
            _sx[i] = (cx - d * Math.sin(azR)).toNumber();
            _sy[i] = (cy - d * Math.cos(azR)).toNumber();
        }
    }

    function horizonRadius(w as Number) as Float {
        return w * 0.47;
    }

    // Straight up at the centre, the horizon on the bezel, north at the top,
    // east on the left (looking up, not down at a map)
    function project(alt as Float, az as Float, cx as Number, cy as Number, r as Float) as [Number, Number] {
        var d = r * (90.0 - alt) / 90.0;
        var a = Math.toRadians(az);
        return [(cx - d * Math.sin(a)).toNumber(), (cy - d * Math.cos(a)).toNumber()];
    }

    // --------------------------------------------------------------- active

    private function drawActive(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var r = horizonRadius(w);
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // Horizon and the compass points
        dc.setPenWidth(1);
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);
        var inset = (w * 0.04).toNumber();
        dc.drawText(cx, cy - r.toNumber() + inset, _labelFont, "N", center);
        dc.drawText(cx, cy + r.toNumber() - inset, _labelFont, "S", center);
        dc.drawText(cx - r.toNumber() + inset, cy, _labelFont, "E", center);
        dc.drawText(cx + r.toNumber() - inset, cy, _labelFont, "W", center);

        if (_located) {
            drawLines(dc);
            drawStars(dc);
            drawPlanets(dc, cx, cy, r, w);
            if (_moon[0] > -2.0) {
                var m = project(_moon[0], _moon[1], cx, cy, r);
                Lib.Moon.draw(dc, m[0], m[1], (w * 0.028).toNumber(), Lib.Moon.phase(), WHITE, DIM);
            }
            if (_sun[0] > -1.0) {
                var s = project(_sun[0], _sun[1], cx, cy, r);
                dc.setColor(AMBER, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(s[0], s[1], (w * 0.03).toNumber());
            }
        }

        // The time on a black backing, the date under it
        var boxW = (w * 0.62).toNumber();
        var boxH = (h * 0.28).toNumber();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - boxW / 2, cy - boxH / 2, boxW, boxH, (w * 0.03).toNumber());
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (h * 0.02).toNumber(), Graphics.FONT_NUMBER_MEDIUM, timeString(), center);
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var date = Lang.format("$1$ $2$ $3$", [info.day_of_week, info.day, info.month]).toUpper();
        dc.drawText(cx, cy + (h * 0.105).toNumber(), _dateFont, _located ? date : "no location yet", center);
    }

    private function drawLines(dc as Dc) as Void {
        dc.setPenWidth(1);
        dc.setColor(LINE, Graphics.COLOR_TRANSPARENT);
        var lines = Stars.LINES;
        for (var k = 0; k + 1 < lines.size(); k += 2) {
            var a = lines[k];
            var b = lines[k + 1];
            if (_sx[a] >= 0 && _sx[b] >= 0) {
                dc.drawLine(_sx[a], _sy[a], _sx[b], _sy[b]);
            }
        }
    }

    // Brighter stars are bigger and whiter; by day everything is dim. The
    // dots are drawn without anti-aliasing: hundreds of them, and at this
    // size it makes no visible difference.
    private function drawStars(dc as Dc) as Void {
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(false);
        }
        for (var i = 0; i < Stars.COUNT; i++) {
            if (_sx[i] < 0) {
                continue;
            }
            var mag = Stars.MAG[i];
            if (_day) {
                dc.setColor(STAR4, Graphics.COLOR_TRANSPARENT);
                if (mag <= 15) {
                    dc.fillCircle(_sx[i], _sy[i], 1);
                } else {
                    dc.drawPoint(_sx[i], _sy[i]);
                }
            } else if (mag <= 5) {
                dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(_sx[i], _sy[i], 4);
            } else if (mag <= 15) {
                dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(_sx[i], _sy[i], 3);
            } else if (mag <= 25) {
                dc.setColor(STAR2, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(_sx[i], _sy[i], 2);
            } else if (mag <= 30) {
                dc.setColor(STAR3, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(_sx[i], _sy[i], 1);
            } else {
                dc.setColor(STAR3, Graphics.COLOR_TRANSPARENT);
                dc.drawPoint(_sx[i], _sy[i]);
            }
        }
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
    }

    // Venus, Mars, Jupiter, Saturn with a letter so they are not taken for stars
    private function drawPlanets(dc as Dc, cx as Number, cy as Number, r as Float, w as Number) as Void {
        var colors = [VENUS, MARS, JUPITER, SATURN];
        var letters = ["V", "M", "J", "S"];
        var sizes = [3, 2, 3, 2];
        var left = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        for (var p = 0; p < 4; p++) {
            var altAz = _planets[p];
            if (altAz[0] <= 0.0) {
                continue;
            }
            var pt = project(altAz[0], altAz[1], cx, cy, r);
            dc.setColor(_day ? STAR3 : colors[p], Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(pt[0], pt[1], sizes[p]);
            dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(pt[0] + (w * 0.016).toNumber(), pt[1] - (w * 0.01).toNumber(), _labelFont, letters[p], left);
        }
    }

    // ------------------------------------------------------------ always-on

    private function drawAlwaysOn(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var clock = System.getClockTime();
        var off = Lib.Aod.offset(clock.min, (w * 0.013).toNumber());
        var cx = w / 2 + off[0];
        var cy = h / 2 + off[1];

        // The brightest stars up right now, as single dim dots (the catalogue
        // is brightest first)
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        var drawn = 0;
        for (var i = 0; i < AOD_STARS && drawn < 20; i++) {
            if (_sx[i] >= 0) {
                dc.drawPoint(_sx[i] + off[0], _sy[i] + off[1]);
                drawn++;
            }
        }

        Lib.Aod.drawHollowText(dc, cx, cy, Graphics.FONT_NUMBER_MEDIUM, timeString(), GRAY,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function timeString() as String {
        var clock = System.getClockTime();
        return Lib.Fmt.clock(clock.hour * 3600 + clock.min * 60);
    }
}
