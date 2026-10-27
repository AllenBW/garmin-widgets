import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;
import Toybox.Weather;

// Field: the time large and legible, plus the handful of numbers checked all
// day. Layout follows designs/svg/face-field-active.svg and face-field-aod.svg;
// every position is a fraction of the screen size so it survives other
// round AMOLED devices.
//
// System font heights measured in the simulator at 454x454 (getFontHeight,
// which includes line spacing; the ink is roughly 70 % of it):
//   XTINY 37, TINY 47, SMALL 53, MEDIUM 61, LARGE 71,
//   NUMBER_MILD 113, NUMBER_MEDIUM 153, NUMBER_HOT 173, NUMBER_THAI_HOT 210.
// "10:08" is 264 px wide in NUMBER_MEDIUM; "8,412" is 109 px wide in SMALL.
//
// Active:    bezel ring (step goal progress by default; battery or off in
//            settings), date, time, three slots (settings), footer with
//            sunrise and sunset (or weather and notifications, or off).
// Always-on: hollow time, dim date, the next sun event, 2 px hairline ring,
//            everything shifted a few pixels each minute. Well under 10 % of
//            pixels lit.
class FieldView extends WatchUi.WatchFace {

    // Palette (designs/mockups.py)
    private const WHITE = 0xF2F2F2;
    private const GRAY = 0x8A8A8A;
    private const DIM = 0x5A5A5A;
    private const TRACK = 0x262626;

    // What the bezel ring shows (resources/settings/properties.xml "Ring")
    private const RING_STEPS = 0;
    private const RING_BATTERY = 1;
    private const RING_OFF = 2;

    // What the footer shows ("Footer")
    private const FOOTER_SUN = 0;
    private const FOOTER_WEATHER = 1;
    private const FOOTER_OFF = 2;

    private const AMBER = 0xFFB020;
    private const ORANGE = 0xFF7A3D;

    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;

    // Settings (resources/settings/properties.xml)
    private var _accent as Number = 0xFFB020;
    private var _ring as Number = RING_STEPS;
    private var _slots as Array<Number> = [Slots.HEART_RATE, Slots.STEPS, Slots.BODY_BATTERY];
    private var _footer as Number = FOOTER_SUN;

    // Hit areas of the three slots, [x, y, halfWidth, halfHeight], filled in
    // by drawActive so the delegate can map a press to a slot.
    private var _slotBoxes as Array<Array<Number>> = [] as Array<Array<Number>>;

    // Slot labels: a 22 px condensed vector font (XTINY, the smallest system
    // font, is 37 px and too wide for "BODY BATT" in a 118 px column).
    private var _labelFont as FontType = Graphics.FONT_XTINY;

    function initialize() {
        WatchFace.initialize();
        _burnIn = Lib.Aod.required();
        reloadSettings();
    }

    function onLayout(dc as Dc) as Void {
        _labelFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (dc.getWidth() * 0.048).toNumber(), Graphics.FONT_XTINY);
    }

    function reloadSettings() as Void {
        _accent = numberProperty("AccentColor", 0xFFB020);
        _ring = numberProperty("Ring", RING_STEPS);
        _slots = [
            numberProperty("Slot1", Slots.HEART_RATE),
            numberProperty("Slot2", Slots.STEPS),
            numberProperty("Slot3", Slots.BODY_BATTERY)
        ];
        _footer = numberProperty("Footer", FOOTER_SUN);
    }

    function onUpdate(dc as Dc) as Void {
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

    // The slot kind under (x, y), or null if the point is outside every slot.
    function slotAt(x as Number, y as Number) as Number? {
        for (var i = 0; i < _slotBoxes.size(); i++) {
            var b = _slotBoxes[i];
            if ((x - b[0]).abs() <= b[2] && (y - b[1]).abs() <= b[3]) {
                return _slots[i];
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
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // Bezel ring: a full circle filled clockwise from 12 o'clock
        var fraction = ringFraction();
        if (fraction != null) {
            Lib.Arcs.drawGauge(dc, cx, cy, w * 0.471, 0, 360, fraction,
                (w * 0.022).toNumber(), TRACK, _accent);
        }

        // Date (TINY: 47 px box, sits above the time box)
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var date = Lang.format("$1$ $2$ $3$", [info.day_of_week, info.day, info.month]).toUpper();
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.22).toNumber(), Graphics.FONT_TINY, date, center);

        // Time (NUMBER_MEDIUM: 153 px box, ink about 105 px, 264 px wide)
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.452).toNumber(), Graphics.FONT_NUMBER_MEDIUM, timeString(), center);

        // Three slots, 118 px apart at 454: condensed label over a SMALL value
        var xs = [w * 0.24, w * 0.5, w * 0.76];
        var labelY = (h * 0.655).toNumber();
        var valueY = (h * 0.735).toNumber();
        var boxes = [] as Array<Array<Number>>;
        for (var i = 0; i < 3; i++) {
            var kind = _slots[i];
            var x = xs[i].toNumber();
            dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, labelY, _labelFont, Slots.label(kind), center);
            dc.setColor(Slots.color(kind), Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, valueY, Graphics.FONT_SMALL, Slots.value(kind), center);
            boxes.add([x, (labelY + valueY) / 2, (w * 0.13).toNumber(), (h * 0.10).toNumber()]);
        }
        _slotBoxes = boxes;

        // Footer (XTINY, 37 px box); at most about 240 px wide here to clear
        // the ring on both sides.
        var footerY = (h * 0.85).toNumber();
        var maxWidth = (w * 0.53).toNumber();
        if (_footer == FOOTER_OFF) {
            // nothing
        } else if (_footer == FOOTER_SUN) {
            drawSunFooter(dc, cx, footerY, w, GRAY, AMBER, ORANGE);
        } else if (_footer == FOOTER_WEATHER) {
            var text = footerText(true);
            if (dc.getTextWidthInPixels(text, Graphics.FONT_XTINY) > maxWidth) {
                text = footerText(false);
            }
            if (text.length() > 0) {
                dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, footerY, Graphics.FONT_XTINY, text, center);
            }
        }
    }

    // "▲ 6:52   ▼ 17:41", centred on cx. The triangles are drawn, since the
    // system fonts have no arrow glyphs.
    private function drawSunFooter(dc as Dc, cx as Number, y as Number, w as Number,
                                   textColor as ColorType, riseColor as ColorType, setColor as ColorType) as Void {
        var times = Lib.Sun.today();
        var rise = times[0];
        var set = times[1];
        if (rise == null && set == null) {
            return;
        }
        var font = Graphics.FONT_XTINY;
        var riseText = (rise != null) ? Lib.Fmt.clock(rise) : "--";
        var setText = (set != null) ? Lib.Fmt.clock(set) : "--";
        var tri = (w * 0.026).toNumber();
        var gap = (w * 0.018).toNumber();
        var mid = (w * 0.06).toNumber();
        var riseWidth = dc.getTextWidthInPixels(riseText, font);
        var setWidth = dc.getTextWidthInPixels(setText, font);
        var x = cx - (tri + gap + riseWidth + mid + tri + gap + setWidth) / 2;
        x += drawSunTime(dc, x, y, true, riseText, tri, gap, font, riseColor, textColor) + mid;
        drawSunTime(dc, x, y, false, setText, tri, gap, font, setColor, textColor);
    }

    // A triangle (up for sunrise, down for sunset) and a time, left-aligned
    // at x and centred on y. Returns the width drawn.
    private function drawSunTime(dc as Dc, x as Number, y as Number, isRise as Boolean, text as String,
                                 tri as Number, gap as Number, font as FontType,
                                 triColor as ColorType, textColor as ColorType) as Number {
        var half = tri / 2;
        var mx = x + half;
        dc.setColor(triColor, Graphics.COLOR_TRANSPARENT);
        if (isRise) {
            dc.fillPolygon([[mx, y - half], [mx - half, y + half], [mx + half, y + half]]);
        } else {
            dc.fillPolygon([[mx, y + half], [mx - half, y - half], [mx + half, y - half]]);
        }
        dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + tri + gap, y, font, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        return tri + gap + dc.getTextWidthInPixels(text, font);
    }

    // How much of the bezel ring to fill (0..1), or null when the ring is off.
    private function ringFraction() as Float? {
        if (_ring == RING_OFF) {
            return null;
        }
        if (_ring == RING_BATTERY) {
            return System.getSystemStats().battery / 100.0;
        }
        if (_ring == RING_STEPS) {
            var info = ActivityMonitor.getInfo();
            var steps = info.steps;
            var goal = info.stepGoal;
            if (steps == null || goal == null || goal <= 0) {
                return 0.0;
            }
            return steps.toFloat() / goal;
        }
        return null;
    }

    private function footerText(withSky as Boolean) as String {
        var parts = [] as Array<String>;
        if (Toybox has :Weather) {
            var cc = Weather.getCurrentConditions();
            var celsius = (cc != null) ? cc.temperature : null;
            if (cc != null && celsius != null) {
                var temp = Lib.Fmt.temperature(celsius);
                var sky = withSky ? WeatherText.describe(cc.condition) : "";
                parts.add(sky.length() > 0 ? temp + " " + sky : temp);
            }
        }
        var n = System.getDeviceSettings().notificationCount;
        if (n > 0) {
            parts.add(n.toString() + (withSky ? (n == 1 ? " notification" : " notifications") : " notif"));
        }
        var text = "";
        for (var i = 0; i < parts.size(); i++) {
            text += (i > 0 ? "  ·  " : "") + parts[i];
        }
        return text;
    }

    // ------------------------------------------------------------- always-on

    private function drawAlwaysOn(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        // Walk a 5x5 grid of offsets, one step per minute (±12 px at 454)
        var off = Lib.Aod.offset(System.getClockTime().min, (w * 0.013).toNumber());
        var cx = w / 2 + off[0];
        var cy = h / 2 + off[1];

        // 2 px hairline ring in a quarter-brightness accent
        var fraction = ringFraction();
        if (fraction != null && fraction > 0.0) {
            dc.setColor(Lib.Aod.dim(_accent), Graphics.COLOR_TRANSPARENT);
            Lib.Arcs.drawClockwise(dc, cx, cy, w * 0.454, 0, 360.0 * fraction, 2);
        }

        // Short date, dim
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var date = Lang.format("$1$ $2$", [info.day_of_week, info.day]).toUpper();
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.29).toNumber() + off[1], Graphics.FONT_XTINY, date, center);

        // Hollow time: only the glyph outlines are lit
        Lib.Aod.drawHollowText(dc, cx, (h * 0.485).toNumber() + off[1],
            Graphics.FONT_NUMBER_MEDIUM, timeString(), GRAY, center);

        // Next sun event, dim
        var next = Lib.Sun.next(Lib.Sun.today());
        if (next != null) {
            var font = Graphics.FONT_XTINY;
            var text = Lib.Fmt.clock(next[1]);
            var tri = (w * 0.02).toNumber();
            var gap = (w * 0.018).toNumber();
            var x = cx - (tri + gap + dc.getTextWidthInPixels(text, font)) / 2;
            drawSunTime(dc, x, (h * 0.72).toNumber() + off[1], next[0], text, tri, gap, font, DIM, DIM);
        }
    }

    // ---------------------------------------------------------------- shared

    private function timeString() as String {
        var clock = System.getClockTime();
        return Lib.Fmt.clock(clock.hour * 3600 + clock.min * 60);
    }

    private function numberProperty(key as String, fallback as Number) as Number {
        var value = Application.Properties.getValue(key);
        return (value instanceof Number) ? value : fallback;
    }
}
