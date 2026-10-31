import Toybox.Application;
import Toybox.Application.WatchFaceConfig;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

// Rings, after the store face the owner picked. Three thick rings run up
// the left side from a common lower edge just left of six o'clock, each
// ending a little short of the one outside it near one o'clock. Each fills
// clockwise from its lower end in its colour over a track of the same hue,
// dimmed: steps against the step goal outside, floors against the floors
// goal in the middle (a segment per floor), Body Battery inside. Each
// ring's number is written along its own circle past its lower end, in its
// colour, after an icon: the miles walked (a star once the step goal is
// met), the floors, the Body Battery. Down the right side, right-aligned
// with an icon after each: the moon, the heart rate, the date (an alarm
// clock when alarms are set), the time in 24-hour form and the theme's
// colour, the next sunrise or sunset, the outside temperature.
//
// Always-on: the rings' fills as hairlines in a quarter of their colour,
// the hollow time, the date and the sun event, dim, shifted each minute.
class RingsView extends WatchUi.WatchFace {

    private const WHITE = 0xF2F2F2;
    private const DIM = 0x5A5A5A;
    private const AMBER = 0xFFB020;
    private const ORANGE = 0xFF7A3D;
    private const YELLOW = 0xFFD83D;

    // Ring geometry, fractions of the width: radius and the clockwise-from-
    // 12 angle each ring ends at near the top. The lower ends line up on a
    // vertical a little left of the centre.
    private const RADII = [0.455, 0.375, 0.295] as Array<Float>;
    private const TOPS = [38.0, 30.0, 20.0] as Array<Float>;
    private const LOWER_X = 0.07;
    private const RING_WIDTH = 0.062;
    private const TRACK = 0.36;          // a track's brightness against its ring
    private const SEGMENT_GAP = 4.0;     // degrees between floor segments

    // The right column
    private const VALUE_X = 0.80;
    private const ICON_X = 0.862;
    private const TIME_RIGHT = 0.905;
    private const ROWS = [0.205, 0.285, 0.36, 0.5, 0.645, 0.725] as Array<Float>;   // moon, HR, date, time, sun, temperature

    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;
    private var _theme as Array<Number> = Themes.colors(Themes.SUNSET);

    private var _timeFont as FontType = Graphics.FONT_NUMBER_MILD;
    private var _rowFont as FontType = Graphics.FONT_TINY;
    private var _ringFont as Graphics.VectorFont? = null;   // the numbers along the rings
    private var _smallFont as FontType = Graphics.FONT_XTINY;

    // Read when the minute changes; the heart rate is live
    private var _minute as Number = -1;
    private var _sun as [Boolean, Number]? = null;
    private var _date as String = "";
    private var _temperature as String = "--";
    private var _distance as String = "--";
    private var _steps as Number? = null;
    private var _stepGoal as Number? = null;
    private var _floors as Number? = null;
    private var _floorGoal as Number? = null;
    private var _body as Number? = null;
    private var _alarms as Number = 0;
    private var _phase as Float = 0.0;

    // Press targets, [complication type, x, y, half width, half height];
    // the rings are hit by radius and angle instead
    private var _targets as Array<Array<Number>> = [] as Array<Array<Number>>;

    function initialize() {
        WatchFace.initialize();
        _burnIn = Lib.Aod.required();
        reloadSettings();
    }

    // The theme from the fēnix 8's watch face editor (its style), else the
    // Theme property (the phone app, the simulator)
    function reloadSettings() as Void {
        var theme = Application.Properties.getValue("Theme");
        if (Application has :WatchFaceConfig) {
            var config = WatchFaceConfig.getSettings(null);
            if (config != null && config.styleId != null) {
                theme = config.styleId;
            }
        }
        _theme = Themes.colors((theme instanceof Number) ? theme : Themes.SUNSET);
    }

    function onLayout(dc as Dc) as Void {
        var w = dc.getWidth();
        _timeFont = Lib.Fmt.vectorFont("BionicBold", (w * 0.3).toNumber(), Graphics.FONT_NUMBER_MEDIUM);
        _rowFont = Lib.Fmt.vectorFont("BionicBold", (w * 0.088).toNumber(), Graphics.FONT_TINY);
        _smallFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (w * 0.055).toNumber(), Graphics.FONT_XTINY);
        var ring = Lib.Fmt.vectorFont("BionicBold", (w * 0.085).toNumber(), Graphics.FONT_TINY);
        _ringFont = (ring instanceof Graphics.VectorFont) ? ring : null;
    }

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
        var steps = Goals.steps();
        _steps = steps[0];
        _stepGoal = steps[1];
        var floors = Goals.floors();
        _floors = floors[0];
        _floorGoal = floors[1];
        _body = Goals.bodyBattery();
        _alarms = Lib.Daily.alarms();
        _phase = Lib.Moon.phase();
    }

    // For the tests: show these goal values until the next read is due
    function setGoals(steps as Number?, stepGoal as Number?, floors as Number?, floorGoal as Number?, body as Number?) as Void {
        _steps = steps;
        _stepGoal = stepGoal;
        _floors = floors;
        _floorGoal = floorGoal;
        _body = body;
        _minute = System.getClockTime().min;
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
        _minute = -1;
        WatchUi.requestUpdate();
    }

    // Where ring i starts, clockwise from 12: its lower end
    function lowerAngle(i as Number) as Float {
        return 180.0 + Math.toDegrees(Math.asin(LOWER_X / RADII[i])).toFloat();
    }

    // How far ring i sweeps, clockwise, to its upper end
    function span(i as Number) as Float {
        return 360.0 + TOPS[i] - lowerAngle(i);
    }

    // The native widget to open for a press at (x, y): a ring by its radius
    // and angle, else a row of the column, else null
    function targetAt(x as Number, y as Number) as Complications.Type? {
        if (_targets.size() == 0) {
            return null;
        }
        var settings = System.getDeviceSettings();
        var w = settings.screenWidth;
        var dx = x - w / 2.0;
        var dy = y - settings.screenHeight / 2.0;
        var r = Math.sqrt(dx * dx + dy * dy) / w;
        var deg = Math.toDegrees(Math.atan2(dx, -dy));   // clockwise from 12
        if (deg < 0) {
            deg += 360;
        }
        var types = [Complications.COMPLICATION_TYPE_STEPS, Complications.COMPLICATION_TYPE_FLOORS_CLIMBED, Complications.COMPLICATION_TYPE_BODY_BATTERY];
        for (var i = 0; i < 3; i++) {
            var along = deg - lowerAngle(i);
            if (along < 0) {
                along += 360;
            }
            if ((r - RADII[i]).abs() <= RING_WIDTH * 0.8 && along <= span(i)) {
                return types[i];
            }
        }
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
        var cy = h / 2;
        var right = Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER;
        var targets = [] as Array<Array<Number>>;
        var width = (w * RING_WIDTH).toNumber();

        // The rings and their numbers
        drawRing(dc, cx, cy, w, 0, Goals.fraction(_steps, _stepGoal), width);
        drawSegments(dc, cx, cy, w, 1, _floors, _floorGoal, width);
        drawRing(dc, cx, cy, w, 2, Goals.fraction(_body, 100), width);
        var goalMet = _steps != null && _stepGoal != null && (_stepGoal as Number) > 0 && (_steps as Number) >= (_stepGoal as Number);
        drawRingLabel(dc, cx, cy, w, 0, _distance + " " + Lib.Fmt.distanceUnit().toUpper(), goalMet ? :star : :feet);
        drawRingLabel(dc, cx, cy, w, 1, (_floors != null) ? (_floors as Number).toString() : "--", :stairs);
        drawRingLabel(dc, cx, cy, w, 2, (_body != null) ? (_body as Number).toString() : "--", :bolt);

        // The right column
        var valueX = (w * VALUE_X).toNumber();
        var iconX = (w * ICON_X).toNumber();
        var icon = (w * 0.052).toNumber();
        var rows = [] as Array<Number>;
        for (var i = 0; i < ROWS.size(); i++) {
            rows.add((h * ROWS[i]).toNumber());
        }

        Lib.Moon.draw(dc, iconX, rows[0], (w * 0.032).toNumber(), _phase, WHITE, DIM);

        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(valueX, rows[1], _rowFont, Lib.Daily.heartRate(), right);
        drawHeart(dc, iconX, rows[1], icon, WHITE);
        targets.add([Complications.COMPLICATION_TYPE_HEART_RATE as Number, valueX - (w * 0.06).toNumber(), rows[1], (w * 0.14).toNumber(), (h * 0.035).toNumber()]);

        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(valueX, rows[2], _rowFont, _date, right);
        if (_alarms > 0) {
            drawAlarm(dc, iconX, rows[2], icon, _alarms, WHITE);
        }
        targets.add([Complications.COMPLICATION_TYPE_CALENDAR_EVENTS as Number, valueX - (w * 0.15).toNumber(), rows[2], (w * 0.18).toNumber(), (h * 0.03).toNumber()]);

        dc.setColor(_theme[3], Graphics.COLOR_TRANSPARENT);
        dc.drawText((w * TIME_RIGHT).toNumber(), rows[3], _timeFont, timeString(), right);

        var sun = _sun;
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        if (sun != null) {
            dc.drawText(valueX, rows[4], _rowFont, Lib.Fmt.clock24(sun[1]), right);
            drawSunIcon(dc, iconX, rows[4], icon, sun[0]);
            var type = sun[0] ? Complications.COMPLICATION_TYPE_SUNRISE : Complications.COMPLICATION_TYPE_SUNSET;
            targets.add([type as Number, valueX - (w * 0.06).toNumber(), rows[4], (w * 0.14).toNumber(), (h * 0.035).toNumber()]);
        } else {
            dc.drawText(valueX, rows[4], _rowFont, "--:--", right);
        }

        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(valueX, rows[5], _rowFont, _temperature, right);
        drawThermometer(dc, iconX, rows[5], icon, WHITE);
        targets.add([Complications.COMPLICATION_TYPE_CURRENT_TEMPERATURE as Number, valueX - (w * 0.06).toNumber(), rows[5], (w * 0.14).toNumber(), (h * 0.035).toNumber()]);

        _targets = targets;
    }

    // Ring i: the dim track over its whole sweep, then `fraction` of it lit
    // from the lower end, round ends on both
    private function drawRing(dc as Dc, cx as Number, cy as Number, w as Number, i as Number, fraction as Float, width as Number) as Void {
        var r = w * RADII[i];
        var color = _theme[i];
        var start = lowerAngle(i);
        var sweep = span(i);
        arc(dc, cx, cy, r, start, sweep, width, Themes.shade(color, TRACK));
        if (fraction > 0.0) {
            arc(dc, cx, cy, r, start, sweep * fraction, width, color);
        }
    }

    // The floors ring: a segment per floor of the goal, the climbed ones
    // lit from the lower end; a plain ring with no goal or a huge one
    private function drawSegments(dc as Dc, cx as Number, cy as Number, w as Number, i as Number,
                                  climbed as Number?, goal as Number?, width as Number) as Void {
        if (goal == null || goal <= 0 || goal > 30) {
            drawRing(dc, cx, cy, w, i, Goals.fraction(climbed, goal), width);
            return;
        }
        var r = w * RADII[i];
        var color = _theme[i];
        var track = Themes.shade(color, TRACK);
        // Square-ended segments with gaps between, round ends on the ring's two ends
        var start = lowerAngle(i);
        var each = span(i) / goal;
        var done = (climbed != null) ? climbed : 0;
        for (var s = 0; s < goal; s++) {
            var from = start + s * each + ((s == 0) ? 0.0 : SEGMENT_GAP / 2);
            var to = start + (s + 1) * each - ((s == goal - 1) ? 0.0 : SEGMENT_GAP / 2);
            dc.setColor(s < done ? color : track, Graphics.COLOR_TRANSPARENT);
            Lib.Arcs.drawClockwise(dc, cx, cy, r, from, to - from, width);
        }
        var a = Lib.Arcs.point(cx, cy, r, start);
        var b = Lib.Arcs.point(cx, cy, r, start + span(i));
        dc.setColor(done > 0 ? color : track, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(a[0], a[1], width / 2);
        dc.setColor(done >= goal ? color : track, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(b[0], b[1], width / 2);
    }

    // An arc with round ends, clockwise from startDeg (clockwise from 12)
    private function arc(dc as Dc, cx as Number, cy as Number, r as Float, startDeg as Float, sweep as Float, width as Number, color as Number) as Void {
        if (sweep <= 0.0) {
            return;
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        Lib.Arcs.drawClockwise(dc, cx, cy, r, startDeg, sweep, width);
        var a = Lib.Arcs.point(cx, cy, r, startDeg);
        var b = Lib.Arcs.point(cx, cy, r, startDeg + sweep);
        dc.fillCircle(a[0], a[1], width / 2);
        dc.fillCircle(b[0], b[1], width / 2);
    }

    // Ring i's number: an icon straight below the centre on the ring's
    // circle, then the text along the circle towards three o'clock
    private function drawRingLabel(dc as Dc, cx as Number, cy as Number, w as Number, i as Number, text as String, icon as Symbol) as Void {
        var r = w * RADII[i];
        var color = _theme[i];
        var size = (w * 0.052).toNumber();
        var at = Lib.Arcs.point(cx, cy, r, 180);
        drawIcon(dc, at[0].toNumber(), at[1].toNumber(), size, icon, (icon == :star) ? YELLOW : color);

        // The text starts this far round from the icon
        var startDeg = 180.0 - Math.toDegrees((w * 0.045) / r).toFloat();
        var font = _ringFont;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (font != null && (dc has :drawRadialText)) {
            dc.drawRadialText(cx, cy, font, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER,
                Lib.Arcs.toDc(startDeg), r, Graphics.RADIAL_TEXT_DIRECTION_COUNTER_CLOCKWISE);
        } else {
            var p = Lib.Arcs.point(cx, cy, r, startDeg);
            dc.drawText(p[0], p[1], _smallFont, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // ---------------------------------------------------------------- glyphs

    private function drawIcon(dc as Dc, x as Number, y as Number, size as Number, icon as Symbol, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (icon == :star) {
            drawStar(dc, x, y, size / 2 + 1, color);
        } else if (icon == :feet) {
            var rx = size * 0.16;
            var ry = size * 0.3;
            dc.fillEllipse(x - size * 0.2, y + size * 0.12, rx, ry);
            dc.fillEllipse(x + size * 0.2, y - size * 0.08, rx, ry);
            dc.fillCircle(x - size * 0.2, y - size * 0.3, size * 0.11);
            dc.fillCircle(x + size * 0.2, y - size * 0.5, size * 0.11);
        } else if (icon == :stairs) {
            var s = size / 3;
            var x0 = x - size / 2;
            var y0 = y + size / 2;
            dc.fillPolygon([[x0, y0], [x0, y0 - s], [x0 + s, y0 - s], [x0 + s, y0 - 2 * s], [x0 + 2 * s, y0 - 2 * s],
                [x0 + 2 * s, y0 - 3 * s], [x0 + 3 * s, y0 - 3 * s], [x0 + 3 * s, y0]] as Array<Graphics.Point2D>);
        } else if (icon == :bolt) {
            var hs = size / 2;
            dc.fillPolygon([[x + hs * 0.3, y - hs], [x - hs * 0.55, y + hs * 0.15], [x - hs * 0.05, y + hs * 0.15],
                [x - hs * 0.3, y + hs], [x + hs * 0.55, y - hs * 0.15], [x + hs * 0.05, y - hs * 0.15]] as Array<Graphics.Point2D>);
        }
    }

    private function drawHeart(dc as Dc, x as Number, y as Number, size as Number, color as Number) as Void {
        var r = size * 0.27;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - r, y - r * 0.6, r);
        dc.fillCircle(x + r, y - r * 0.6, r);
        dc.fillPolygon([[x - 2 * r + 0.5, y - r * 0.2], [x + 2 * r - 0.5, y - r * 0.2], [x, y + size * 0.5]] as Array<Graphics.Point2D>);
    }

    // The sun on a horizon line with an arrow: up for sunrise, down for sunset
    private function drawSunIcon(dc as Dc, x as Number, y as Number, size as Number, rise as Boolean) as Void {
        var half = size / 2;
        dc.setColor(rise ? AMBER : ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y - 2, half * 0.5);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - half, y - 1, size, half + 2);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - half, y - 1, size, 2);
        var a = y + 3;
        var b = y + half + 2;
        if (rise) {
            dc.fillPolygon([[x, a], [x - half * 0.45, b], [x + half * 0.45, b]] as Array<Graphics.Point2D>);
        } else {
            dc.fillPolygon([[x, b], [x - half * 0.45, a], [x + half * 0.45, a]] as Array<Graphics.Point2D>);
        }
    }

    private function drawThermometer(dc as Dc, x as Number, y as Number, size as Number, color as Number) as Void {
        var tube = (size * 0.3).toNumber();
        var bulb = (size * 0.25).toNumber();
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRoundedRectangle(x - tube / 2, y - size / 2, tube, size * 0.75, tube / 2);
        dc.fillCircle(x, y + size / 2 - bulb, bulb);
        dc.fillRectangle(x - 1, y - size * 0.15, 2, size * 0.45);
    }

    private function drawStar(dc as Dc, x as Number, y as Number, r as Number, color as Number) as Void {
        var points = [] as Array<Graphics.Point2D>;
        for (var i = 0; i < 10; i++) {
            var a = Math.PI * i / 5 - Math.PI / 2;
            var rr = (i % 2 == 0) ? r : r * 0.45;
            points.add([x + rr * Math.cos(a), y + rr * Math.sin(a)] as Graphics.Point2D);
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(points);
    }

    // An alarm clock and, past one, the count beside it
    private function drawAlarm(dc as Dc, x as Number, y as Number, size as Number, count as Number, color as Number) as Void {
        var r = (size * 0.4).toNumber();
        var d = (r * 0.75).toNumber();
        dc.setPenWidth(2);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(x, y, r);
        dc.drawLine(x, y, x, y - r + 3);
        dc.drawLine(x, y, x + r - 3, y);
        dc.drawLine(x - d, y - d, x - d - 3, y - d - 3);
        dc.drawLine(x + d, y - d, x + d + 3, y - d - 3);
        if (count > 1) {
            dc.drawText(x + r + 3, y, _smallFont, count.toString(), Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // ------------------------------------------------------------- always-on

    private function drawAlwaysOn(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var right = Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER;
        var off = Lib.Aod.offset(System.getClockTime().min, (w * 0.013).toNumber());
        var cx = w / 2 + off[0];
        var cy = h / 2 + off[1];

        // The fills as hairlines, a quarter of their colour
        var fills = [Goals.fraction(_steps, _stepGoal), Goals.fraction(_floors, _floorGoal), Goals.fraction(_body, 100)];
        for (var i = 0; i < 3; i++) {
            if (fills[i] > 0.0) {
                dc.setColor(Lib.Aod.dim(_theme[i]), Graphics.COLOR_TRANSPARENT);
                Lib.Arcs.drawClockwise(dc, cx, cy, w * RADII[i], lowerAngle(i), span(i) * fills[i], 2);
            }
        }

        var valueX = (w * VALUE_X).toNumber() + off[0];
        Lib.Aod.drawHollowText(dc, (w * TIME_RIGHT).toNumber() + off[0], (h * ROWS[3]).toNumber() + off[1], _timeFont, timeString(), Themes.shade(_theme[3], 0.6), right);
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(valueX, (h * ROWS[2]).toNumber() + off[1], Graphics.FONT_XTINY, _date, right);
        var sun = _sun;
        if (sun != null) {
            dc.drawText(valueX, (h * ROWS[4]).toNumber() + off[1], Graphics.FONT_XTINY, Lib.Fmt.clock24(sun[1]), right);
        }
        _targets = [] as Array<Array<Number>>;
    }

    // ---------------------------------------------------------------- shared

    private function timeString() as String {
        var clock = System.getClockTime();
        return Lib.Fmt.clock24(clock.hour * 3600 + clock.min * 60);
    }
}
