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
// Active:    battery ring (gap at 6 o'clock with "72% · 6d 4h"), date, time,
//            three slots (settings), footer with weather and notifications.
// Always-on: hollow time, dim date, 2 px battery hairline, everything shifted
//            a few pixels each minute. Well under 10 % of pixels lit.
class FieldView extends WatchUi.WatchFace {

    // Palette (designs/mockups.py)
    private const WHITE = 0xF2F2F2;
    private const GRAY = 0x8A8A8A;
    private const DIM = 0x5A5A5A;
    private const TRACK = 0x262626;

    // Battery ring: degrees clockwise from 12 o'clock (see Lib.Arcs)
    private const RING_START = 210;
    private const RING_SPAN = 300;

    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;

    // Settings (resources/settings/properties.xml)
    private var _accent as Number = 0xFFB020;
    private var _slots as Array<Number> = [Slots.HEART_RATE, Slots.STEPS, Slots.BODY_BATTERY];
    private var _showFooter as Boolean = true;

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
        _slots = [
            numberProperty("Slot1", Slots.HEART_RATE),
            numberProperty("Slot2", Slots.STEPS),
            numberProperty("Slot3", Slots.BODY_BATTERY)
        ];
        var footer = Application.Properties.getValue("ShowFooter");
        _showFooter = (footer instanceof Boolean) ? footer : true;
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

        // Battery ring: 300 degrees clockwise from 7 o'clock, 60 degree gap at
        // the bottom (214 px wide at 454) for the readout
        var stats = System.getSystemStats();
        var pct = stats.battery;
        Lib.Arcs.drawGauge(dc, cx, cy, w * 0.471, RING_START, RING_SPAN, pct / 100.0,
            (w * 0.022).toNumber(), TRACK, _accent);

        // Battery readout in the gap (XTINY, about 140 px wide)
        var batt = pct.format("%d") + "%";
        if (stats has :batteryInDays) {
            batt += " · " + Lib.Fmt.duration(stats.batteryInDays * 24.0);
        }
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.925).toNumber(), Graphics.FONT_XTINY, batt, center);

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

        // Footer: weather and notification count (XTINY, 37 px box). The chord
        // is about 316 px wide here, so drop the sky description if needed.
        if (_showFooter) {
            var maxWidth = (w * 0.56).toNumber();   // clears the ring at this height
            var text = footerText(true);
            if (dc.getTextWidthInPixels(text, Graphics.FONT_XTINY) > maxWidth) {
                text = footerText(false);
            }
            if (text.length() > 0) {
                dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, (h * 0.835).toNumber(), Graphics.FONT_XTINY, text, center);
            }
        }
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

        // 2 px battery hairline in a quarter-brightness accent
        var pct = System.getSystemStats().battery;
        dc.setColor(Lib.Aod.dim(_accent), Graphics.COLOR_TRANSPARENT);
        Lib.Arcs.drawClockwise(dc, cx, cy, w * 0.454, RING_START, RING_SPAN * pct / 100.0, 2);

        // Short date, dim
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var date = Lang.format("$1$ $2$", [info.day_of_week, info.day]).toUpper();
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.29).toNumber() + off[1], Graphics.FONT_XTINY, date, center);

        // Hollow time: only the glyph outlines are lit
        Lib.Aod.drawHollowText(dc, cx, (h * 0.485).toNumber() + off[1],
            Graphics.FONT_NUMBER_MEDIUM, timeString(), GRAY, center);
    }

    // ---------------------------------------------------------------- shared

    private function timeString() as String {
        var clock = System.getClockTime();
        var hour = clock.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        return Lang.format("$1$:$2$", [hour.format("%d"), clock.min.format("%02d")]);
    }

    private function numberProperty(key as String, fallback as Number) as Number {
        var value = Application.Properties.getValue(key);
        return (value instanceof Number) ? value : fallback;
    }
}
