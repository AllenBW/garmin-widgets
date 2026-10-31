import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Today: the owner's list, top to bottom, and nothing else (the readings
// come from Lib.Daily, shared with the Strata face). Alarms when any
// are set, the next sun event (sunrise until it has happened, then sunset),
// the date, the time in 24-hour form, heart rate / outside temperature /
// distance walked today, and the moon with its phase. No settings. Every
// position is a fraction of the screen size.
//
// Always-on: the next sun event, the hollow time and the date, all dim and
// shifted a few pixels each minute (Lib.Aod). Well under 10 % of pixels lit.
//
// System font heights at 454 px (getFontHeight): XTINY 37, TINY 47,
// SMALL 53, NUMBER_MEDIUM 153 ("10:08" is 264 px wide).
class TodayView extends WatchUi.WatchFace {

    // Palette (designs/mockups.py)
    private const WHITE = 0xF2F2F2;
    private const GRAY = 0x8A8A8A;
    private const DIM = 0x5A5A5A;
    private const AMBER = 0xFFB020;
    private const ORANGE = 0xFF7A3D;
    private const RED = 0xFF4D4D;

    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;

    // Vector fonts (system fallbacks): column labels, column values, the
    // sun line, and the small text beside the moon and the alarm mark
    private var _labelFont as FontType = Graphics.FONT_XTINY;
    private var _valueFont as FontType = Graphics.FONT_SMALL;
    private var _lineFont as FontType = Graphics.FONT_TINY;
    private var _smallFont as FontType = Graphics.FONT_XTINY;

    // Read when the minute changes, not on every redraw (the heart rate is live)
    private var _minute as Number = -1;
    private var _sun as [Boolean, Number]? = null;   // [isSunrise, secondsSinceMidnight]
    private var _date as String = "";
    private var _temperature as String = "--";
    private var _distance as String = "--";
    private var _alarms as Number = 0;
    private var _phase as Float = 0.0;

    // Press targets, [complication type, x, y, half width, half height]
    private var _targets as Array<Array<Number>> = [] as Array<Array<Number>>;

    function initialize() {
        WatchFace.initialize();
        _burnIn = Lib.Aod.required();
    }

    function onLayout(dc as Dc) as Void {
        var w = dc.getWidth();
        _labelFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (w * 0.048).toNumber(), Graphics.FONT_XTINY);
        _valueFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (w * 0.1).toNumber(), Graphics.FONT_SMALL);
        _lineFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (w * 0.075).toNumber(), Graphics.FONT_TINY);
        _smallFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (w * 0.062).toNumber(), Graphics.FONT_XTINY);
    }

    // The once-a-minute readings
    function refresh() as Void {
        var minute = System.getClockTime().min;
        if (minute == _minute) {
            return;
        }
        _minute = minute;
        _sun = Lib.Sun.next(Lib.Sun.today());
        _date = Lib.Daily.date();
        _temperature = Lib.Daily.temperature();
        _distance = Lib.Daily.distance();
        _alarms = Lib.Daily.alarms();
        _phase = Lib.Moon.phase();
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
        _minute = -1;   // re-read everything on the next draw
        WatchUi.requestUpdate();
    }

    // The native widget to open for a press at (x, y), or null
    function targetAt(x as Number, y as Number) as Complications.Type? {
        for (var i = 0; i < _targets.size(); i++) {
            var t = _targets[i];
            if ((x - t[1]).abs() <= t[3] && (y - t[2]).abs() <= t[4]) {
                return t[0] as Complications.Type;
            }
        }
        return null;
    }

    // ---------------------------------------------------------------- active

    private function drawActive(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var targets = [] as Array<Array<Number>>;

        // Alarms, only when any are set
        if (_alarms > 0) {
            drawAlarms(dc, cx, (h * 0.085).toNumber(), w, _alarms, GRAY);
        }

        // The next sun event: sunrise until it has happened, then sunset
        var sunY = (h * 0.17).toNumber();
        var sun = _sun;
        if (sun != null) {
            drawSunLine(dc, cx, sunY, w, sun[0], Lib.Fmt.clock24(sun[1]), _lineFont, sun[0] ? AMBER : ORANGE, WHITE);
            var type = sun[0] ? Complications.COMPLICATION_TYPE_SUNRISE : Complications.COMPLICATION_TYPE_SUNSET;
            targets.add([type as Number, cx, sunY, (w * 0.3).toNumber(), (h * 0.05).toNumber()]);
        } else {
            dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, sunY, _lineFont, "NO SUN TIMES YET", center);
        }

        // Date: weekday, month, day of the month
        var dateY = (h * 0.265).toNumber();
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, dateY, Graphics.FONT_TINY, _date, center);
        targets.add([Complications.COMPLICATION_TYPE_CALENDAR_EVENTS as Number, cx, dateY, (w * 0.25).toNumber(), (h * 0.045).toNumber()]);

        // Time, 24-hour
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.455).toNumber(), Graphics.FONT_NUMBER_MEDIUM, timeString(), center);

        // Three columns, label over value: heart rate, outside temperature,
        // distance walked today (the unit is the label)
        var columns = [
            [Complications.COMPLICATION_TYPE_HEART_RATE, "HR", Lib.Daily.heartRate(), RED],
            [Complications.COMPLICATION_TYPE_CURRENT_TEMPERATURE, "OUTSIDE", _temperature, WHITE],
            [Complications.COMPLICATION_TYPE_STEPS, Lib.Daily.distanceLabel(), _distance, WHITE]
        ];
        var xs = [w * 0.24, w * 0.5, w * 0.76];
        var labelY = (h * 0.655).toNumber();
        var valueY = (h * 0.735).toNumber();
        for (var i = 0; i < 3; i++) {
            var x = xs[i].toNumber();
            dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, labelY, _labelFont, columns[i][1] as String, center);
            dc.setColor(columns[i][3] as Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, valueY, _valueFont, columns[i][2] as String, center);
            targets.add([columns[i][0] as Number, x, (labelY + valueY) / 2, (w * 0.12).toNumber(), (h * 0.09).toNumber()]);
        }

        // The moon and the name of its phase
        drawMoon(dc, cx, (h * 0.865).toNumber(), w);
        _targets = targets;
    }

    // A triangle (up for sunrise, down for sunset), SUNRISE or SUNSET in
    // `color`, and the time in `textColor`, the whole line centred on (cx, y)
    private function drawSunLine(dc as Dc, cx as Number, y as Number, w as Number, isRise as Boolean,
                                 time as String, font as FontType, color as ColorType, textColor as ColorType) as Void {
        var label = isRise ? "SUNRISE " : "SUNSET ";
        var tri = (w * 0.03).toNumber();
        var gap = (w * 0.018).toNumber();
        var labelW = dc.getTextWidthInPixels(label, font);
        var timeW = dc.getTextWidthInPixels(time, font);
        var x = cx - (tri + gap + labelW + timeW) / 2;
        var half = tri / 2;
        var mx = x + half;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (isRise) {
            dc.fillPolygon([[mx, y - half], [mx - half, y + half], [mx + half, y + half]] as Array<Graphics.Point2D>);
        } else {
            dc.fillPolygon([[mx, y + half], [mx - half, y - half], [mx + half, y - half]] as Array<Graphics.Point2D>);
        }
        var left = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.drawText(x + tri + gap, y, font, label, left);
        dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + tri + gap + labelW, y, font, time, left);
    }

    // An alarm clock (a dial with two hands and two bells) and the number of
    // alarms set, centred on (cx, y). Public so the tests can draw it: the
    // simulator never has an alarm set.
    function drawAlarms(dc as Dc, cx as Number, y as Number, w as Number, count as Number, color as ColorType) as Void {
        var r = (w * 0.02).toNumber();
        var gap = (w * 0.015).toNumber();
        var text = count.toString();
        var textW = dc.getTextWidthInPixels(text, _smallFont);
        var x = cx - (2 * r + gap + textW) / 2 + r;   // the dial's centre
        var d = (r * 0.75).toNumber();
        dc.setPenWidth(2);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(x, y, r);
        dc.drawLine(x, y, x, y - r + 3);               // hand to 12
        dc.drawLine(x, y, x + r - 3, y);               // hand to 3
        dc.drawLine(x - d, y - d, x - d - 3, y - d - 3);   // bell at 10:30
        dc.drawLine(x + d, y - d, x + d + 3, y - d - 3);   // bell at 1:30
        dc.drawText(x + r + gap, y, _smallFont, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawMoon(dc as Dc, cx as Number, y as Number, w as Number) as Void {
        var r = (w * 0.035).toNumber();
        var gap = (w * 0.025).toNumber();
        var name = Lib.Moon.name(_phase);
        var textW = dc.getTextWidthInPixels(name, _smallFont);
        var x = cx - (2 * r + gap + textW) / 2;
        Lib.Moon.draw(dc, x + r, y, r, _phase, WHITE, DIM);
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + 2 * r + gap, y, _smallFont, name, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ------------------------------------------------------------- always-on

    private function drawAlwaysOn(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // Walk a 5x5 grid of offsets, one step per minute (±12 px at 454)
        var off = Lib.Aod.offset(System.getClockTime().min, (w * 0.013).toNumber());
        var cx = w / 2 + off[0];

        // The next sun event, dim
        var sun = _sun;
        if (sun != null) {
            drawSunLine(dc, cx, (h * 0.28).toNumber() + off[1], w, sun[0], Lib.Fmt.clock24(sun[1]), Graphics.FONT_XTINY, DIM, DIM);
        }

        // Hollow time: only the glyph outlines are lit
        Lib.Aod.drawHollowText(dc, cx, (h * 0.485).toNumber() + off[1],
            Graphics.FONT_NUMBER_MEDIUM, timeString(), GRAY, center);

        // The date, dim
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.70).toNumber() + off[1], Graphics.FONT_XTINY, _date, center);

        _targets = [] as Array<Array<Number>>;
    }

    // ---------------------------------------------------------------- shared

    private function timeString() as String {
        var clock = System.getClockTime();
        return Lib.Fmt.clock24(clock.hour * 3600 + clock.min * 60);
    }
}
