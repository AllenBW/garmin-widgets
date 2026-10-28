import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Daylight: the shape of the day at a glance. A 24 h dial with noon at the
// top: night in navy, daylight in amber, golden hours in orange, a hand at
// the current time. Centre: light left, the time, sunrise and sunset,
// altitude and the pressure trend. Layout follows
// designs/svg/face-daylight-active.svg and face-daylight-aod.svg; every
// position is a fraction of the screen size.
//
// Always-on: four cardinal ticks, a hollow sun marker, hollow time and the
// next sun event, shifted a few pixels each minute. Well under 10 % lit.
class DaylightView extends WatchUi.WatchFace {

    private const WHITE = 0xF2F2F2;
    private const GRAY = 0x8A8A8A;
    private const DIM = 0x5A5A5A;
    private const NIGHT = 0x1A2A4A;
    private const AMBER = 0xFFB020;
    private const ORANGE = 0xFF7A3D;

    private const PRESSURE_WINDOW = 3 * 3600;   // seconds
    private const PRESSURE_TREND = 100.0;       // pascals over the window: 1 hPa

    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;
    private var _minute as Number = -1;

    // Today's sun as seconds since local midnight (null: unknown or never)
    private var _dayStart as Number = 0;
    private var _located as Boolean = false;
    private var _rise as Number? = null;
    private var _set as Number? = null;
    private var _goldenMorningStart as Number? = null;
    private var _goldenMorningEnd as Number? = null;
    private var _goldenEveningStart as Number? = null;
    private var _goldenEveningEnd as Number? = null;
    private var _tomorrowRise as Number? = null;   // Unix seconds

    private var _altitude as String = "";
    private var _pressure as String = "";
    private var _trend as Number = 0;              // -1 falling, 0 steady, 1 rising

    private var _smallFont as FontType = Graphics.FONT_XTINY;
    private var _timesFont as FontType = Graphics.FONT_XTINY;
    private var _labelFont as FontType = Graphics.FONT_XTINY;

    function initialize() {
        WatchFace.initialize();
        _burnIn = Lib.Aod.required();
    }

    function onLayout(dc as Dc) as Void {
        var h = dc.getHeight();
        _smallFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.046).toNumber(), Graphics.FONT_XTINY);
        _timesFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.053).toNumber(), Graphics.FONT_XTINY);
        _labelFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.044).toNumber(), Graphics.FONT_XTINY);
    }

    function onUpdate(dc as Dc) as Void {
        refresh();
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

    // ----------------------------------------------------------------- data

    // The sun maths once a minute, from the last known location; the watch's
    // own sunrise/sunset when there has never been one.
    function refresh() as Void {
        var clock = System.getClockTime();
        if (clock.min == _minute) {
            return;
        }
        _minute = clock.min;
        var now = Time.now().value();
        _dayStart = now - (clock.hour * 3600 + clock.min * 60 + clock.sec);

        var where = Lib.Location.get();
        _located = (where != null);
        if (where != null) {
            var today = Lib.Solar.day(where[0], where[1], _dayStart);
            _rise = sinceMidnight(today.rise);
            _set = sinceMidnight(today.set);
            _goldenMorningStart = sinceMidnight(today.goldenMorningStart);
            _goldenMorningEnd = sinceMidnight(today.goldenMorningEnd);
            _goldenEveningStart = sinceMidnight(today.goldenEveningStart);
            _goldenEveningEnd = sinceMidnight(today.goldenEveningEnd);
            _tomorrowRise = Lib.Solar.day(where[0], where[1], _dayStart + 86400).rise;
        } else {
            var times = Lib.Sun.today();
            _rise = times[0];
            _set = times[1];
            _goldenMorningStart = null;
            _goldenMorningEnd = null;
            _goldenEveningStart = null;
            _goldenEveningEnd = null;
            var rise = _rise;
            _tomorrowRise = (rise != null) ? _dayStart + 86400 + rise : null;
        }
        refreshEnvironment();
    }

    private function sinceMidnight(unix as Number?) as Number? {
        return (unix == null) ? null : unix - _dayStart;
    }

    private function refreshEnvironment() as Void {
        var info = Activity.getActivityInfo();
        var altitude = (info != null) ? info.altitude : null;
        if (altitude != null) {
            var metric = System.getDeviceSettings().elevationUnits == System.UNIT_METRIC;
            _altitude = metric
                ? Lib.Fmt.thousands(Math.round(altitude).toNumber()) + " m"
                : Lib.Fmt.thousands(Math.round(altitude * 3.28084).toNumber()) + " ft";
        } else {
            _altitude = "";
        }
        var pressure = (info != null) ? info.meanSeaLevelPressure : null;
        if (pressure == null && info != null) {
            pressure = info.ambientPressure;
        }
        _pressure = (pressure != null) ? (pressure / 100.0 + 0.5).toNumber().toString() + " hPa" : "";
        _trend = pressureTrend();
    }

    // The barometer over the last few hours: newest against oldest sample
    private function pressureTrend() as Number {
        if (!(Toybox has :SensorHistory) || !(Toybox.SensorHistory has :getPressureHistory)) {
            return 0;
        }
        var iterator = SensorHistory.getPressureHistory({
            :period => new Time.Duration(PRESSURE_WINDOW),
            :order => SensorHistory.ORDER_NEWEST_FIRST
        });
        var newest = null;
        var oldest = null;
        var sample = iterator.next();
        while (sample != null) {
            var data = sample.data;
            if (data != null) {
                if (newest == null) {
                    newest = data;
                }
                oldest = data;
            }
            sample = iterator.next();
        }
        if (newest == null || oldest == null) {
            return 0;
        }
        var delta = newest - oldest;
        if (delta >= PRESSURE_TREND) {
            return 1;
        }
        if (delta <= -PRESSURE_TREND) {
            return -1;
        }
        return 0;
    }

    // --------------------------------------------------------------- active

    private function drawActive(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var ringR = w * 0.432;
        var ringW = (w * 0.057).toNumber();

        // Night, then the day band, then the golden hours on top
        dc.setColor(NIGHT, Graphics.COLOR_TRANSPARENT);
        Lib.Arcs.drawClockwise(dc, cx, cy, ringR, 0, 360, ringW);
        drawSpan(dc, cx, cy, ringR, ringW, _rise, _set, AMBER);
        drawSpan(dc, cx, cy, ringR, ringW, _goldenMorningStart, _goldenMorningEnd, ORANGE);
        drawSpan(dc, cx, cy, ringR, ringW, _goldenEveningStart, _goldenEveningEnd, ORANGE);

        // Hour ticks outside the ring, 0 / 6 / 12 / 18 labelled inside it
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        for (var hour = 0; hour < 24; hour++) {
            var deg = Lib.Sun.dialDegrees(hour * 3600);
            var major = (hour % 6 == 0);
            var inner = Lib.Arcs.point(cx, cy, w * (major ? 0.458 : 0.471), deg);
            var outer = Lib.Arcs.point(cx, cy, w * 0.493, deg);
            dc.setPenWidth(major ? 3 : 2);
            dc.drawLine(inner[0], inner[1], outer[0], outer[1]);
        }
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        var labels = ["0", "6", "12", "18"];
        for (var i = 0; i < 4; i++) {
            var p = Lib.Arcs.point(cx, cy, w * 0.366, Lib.Sun.dialDegrees(i * 6 * 3600));
            dc.drawText(p[0], p[1], _labelFont, labels[i], center);
        }

        // The sun hand: a short line and a dot on the ring at the current time
        var clock = System.getClockTime();
        var nowSecs = clock.hour * 3600 + clock.min * 60;
        var deg = Lib.Sun.dialDegrees(nowSecs);
        var tip = Lib.Arcs.point(cx, cy, ringR, deg);
        var base = Lib.Arcs.point(cx, cy, w * 0.33, deg);
        dc.setPenWidth(4);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(base[0], base[1], tip[0], tip[1]);
        var dotR = (w * 0.033).toNumber();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(tip[0], tip[1], dotR + 3);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(tip[0], tip[1], dotR);

        // Centre stack
        dc.setColor(AMBER, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.37).toNumber(), _smallFont,
            DaylightText.light(nowSecs, _rise, _set, _tomorrowRise, _dayStart, _located), center);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.489).toNumber(), Graphics.FONT_NUMBER_MEDIUM, Lib.Fmt.clock(nowSecs), center);
        drawSunTimes(dc, cx, (h * 0.612).toNumber(), w, _timesFont, GRAY, AMBER, ORANGE);
        drawEnvironment(dc, cx, (h * 0.692).toNumber(), w);
    }

    // A band on the ring between two times of day (seconds since midnight)
    private function drawSpan(dc as Dc, cx as Number, cy as Number, r as Float, width as Number,
                              from as Number?, to as Number?, color as ColorType) as Void {
        if (from == null || to == null || to <= from) {
            return;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        Lib.Arcs.drawClockwise(dc, cx, cy, r, Lib.Sun.dialDegrees(from), (to - from) * 360.0 / 86400.0, width);
    }

    // "▲ 6:52   ▼ 17:41", the triangles drawn, centred on cx
    private function drawSunTimes(dc as Dc, cx as Number, y as Number, w as Number, font as FontType,
                                  textColor as ColorType, riseColor as ColorType, setColor as ColorType) as Void {
        var rise = _rise;
        var set = _set;
        if (rise == null && set == null) {
            return;
        }
        var tri = (w * 0.026).toNumber();
        var gap = (w * 0.015).toNumber();
        var between = (w * 0.06).toNumber();
        var riseText = (rise != null) ? Lib.Fmt.clock(rise) : "--";
        var setText = (set != null) ? Lib.Fmt.clock(set) : "--";
        var riseW = tri + gap + dc.getTextWidthInPixels(riseText, font);
        var setW = tri + gap + dc.getTextWidthInPixels(setText, font);
        var x = cx - (riseW + between + setW) / 2;
        drawTriangle(dc, x, y, tri, true, riseColor);
        dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + tri + gap, y, font, riseText, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        x += riseW + between;
        drawTriangle(dc, x, y, tri, false, setColor);
        dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + tri + gap, y, font, setText, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // "1,240 m   1012 hPa" with a trend triangle after the pressure
    private function drawEnvironment(dc as Dc, cx as Number, y as Number, w as Number) as Void {
        var parts = [] as Array<String>;
        if (_altitude.length() > 0) {
            parts.add(_altitude);
        }
        if (_pressure.length() > 0) {
            parts.add(_pressure);
        }
        if (parts.size() == 0) {
            return;
        }
        var text = (parts.size() == 2) ? parts[0] + "   " + parts[1] : parts[0];
        var tri = (_trend != 0 && _pressure.length() > 0) ? (w * 0.02).toNumber() : 0;
        var gap = (tri > 0) ? (w * 0.012).toNumber() : 0;
        var textW = dc.getTextWidthInPixels(text, _smallFont);
        var x = cx - (textW + gap + tri) / 2;
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, _smallFont, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        if (tri > 0) {
            drawTriangle(dc, x + textW + gap, y, tri, _trend > 0, DIM);
        }
    }

    // An up or down triangle `size` wide, left-aligned at x, centred on y
    private function drawTriangle(dc as Dc, x as Number, y as Number, size as Number, up as Boolean, color as ColorType) as Void {
        var half = size / 2;
        var mx = x + half;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (up) {
            dc.fillPolygon([[mx, y - half], [mx - half, y + half], [mx + half, y + half]] as Array<Graphics.Point2D>);
        } else {
            dc.fillPolygon([[mx, y + half], [mx - half, y - half], [mx + half, y - half]] as Array<Graphics.Point2D>);
        }
    }

    // ------------------------------------------------------------ always-on

    private function drawAlwaysOn(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var clock = System.getClockTime();
        var off = Lib.Aod.offset(clock.min, (w * 0.013).toNumber());
        var cx = w / 2 + off[0];
        var cy = h / 2 + off[1];

        // Four cardinal ticks
        dc.setPenWidth(2);
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 4; i++) {
            var deg = i * 90;
            var inner = Lib.Arcs.point(cx, cy, w * 0.454, deg);
            var outer = Lib.Arcs.point(cx, cy, w * 0.489, deg);
            dc.drawLine(inner[0], inner[1], outer[0], outer[1]);
        }

        // Hollow sun marker on the ring
        var nowSecs = clock.hour * 3600 + clock.min * 60;
        var sun = Lib.Arcs.point(cx, cy, w * 0.432, Lib.Sun.dialDegrees(nowSecs));
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(sun[0], sun[1], (w * 0.026).toNumber());

        // Hollow time
        Lib.Aod.drawHollowText(dc, cx, (h * 0.498).toNumber() + off[1], Graphics.FONT_NUMBER_MEDIUM, Lib.Fmt.clock(nowSecs), GRAY, center);

        // Next sun event
        var next = Lib.Sun.next([_rise, _set]);
        if (next != null) {
            var tri = (w * 0.02).toNumber();
            var gap = (w * 0.015).toNumber();
            var text = Lib.Fmt.clock(next[1]);
            var x = cx - (tri + gap + dc.getTextWidthInPixels(text, Graphics.FONT_XTINY)) / 2;
            var y = (h * 0.62).toNumber() + off[1];
            drawTriangle(dc, x, y, tri, next[0], DIM);
            dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + tri + gap, y, Graphics.FONT_XTINY, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }
}
