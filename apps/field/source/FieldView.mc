import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;
import Toybox.Weather;

// Field: the time large and legible, plus the handful of things checked all
// day. Layout follows designs/svg/face-field-active.svg and face-field-aod.svg;
// every position is a fraction of the screen size so it survives other
// round AMOLED devices.
//
// Active:    bezel ring (a 24 h daylight dial by default; step goal, battery
//            or off in settings), a row of signals that only appear when they
//            matter (rain ahead, pressure falling, phone disconnected, do not
//            disturb), date, time, three slots (settings), footer with the
//            next sun event plus the moon at night (or weather and
//            notifications, or off).
// Always-on: hollow time, dim date, the next sun event, a 2 px hairline ring,
//            everything shifted a few pixels each minute. Well under 10 % of
//            pixels lit.
//
// System font heights measured in the simulator at 454x454 (getFontHeight,
// which includes line spacing; the ink is roughly 70 % of it):
//   XTINY 37, TINY 47, SMALL 53, MEDIUM 61, LARGE 71,
//   NUMBER_MILD 113, NUMBER_MEDIUM 153, NUMBER_HOT 173, NUMBER_THAI_HOT 210.
// "10:08" is 264 px wide in NUMBER_MEDIUM; "8,412" is 109 px wide in SMALL.
class FieldView extends WatchUi.WatchFace {

    // Palette (designs/mockups.py)
    private const WHITE = 0xF2F2F2;
    private const GRAY = 0x8A8A8A;
    private const DIM = 0x5A5A5A;
    private const TRACK = 0x262626;
    private const NIGHT = 0x1A2A4A;
    private const AMBER = 0xFFB020;
    private const ORANGE = 0xFF7A3D;
    private const CYAN = 0x3EC6E0;
    private const RED = 0xFF4D4D;

    // What the bezel ring shows (resources/settings/properties.xml "Ring")
    private const RING_STEPS = 0;
    private const RING_BATTERY = 1;
    private const RING_OFF = 2;
    private const RING_DAYLIGHT = 3;

    // What the footer shows ("Footer")
    private const FOOTER_SUN = 0;
    private const FOOTER_WEATHER = 1;
    private const FOOTER_OFF = 2;

    // Signals
    private const RAIN_CHANCE = 40;          // percent, within the next 3 hours
    private const RAIN_WINDOW = 3 * 3600;    // seconds
    private const PRESSURE_WINDOW = 3 * 3600;
    private const PRESSURE_DROP = -400.0;    // pascals over the window: 4 hPa, the usual storm-alert setting

    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;

    // Settings
    private var _accent as Number = AMBER;
    private var _ring as Number = RING_DAYLIGHT;
    private var _footer as Number = FOOTER_SUN;
    private var _signals as Boolean = true;
    private var _slots as Array<Number> = [Slots.HEART_RATE, Slots.STEPS, Slots.BODY_BATTERY];

    // Hit areas of the three slots, [x, y, halfWidth, halfHeight], filled in
    // by drawActive so the delegate can map a press to a slot.
    private var _slotBoxes as Array<Array<Number>> = [] as Array<Array<Number>>;

    // Slot labels: a 22 px condensed vector font (XTINY, the smallest system
    // font, is 37 px and too wide for "BODY BATT" in a 118 px column).
    private var _labelFont as FontType = Graphics.FONT_XTINY;

    // Signals are refreshed once a minute, not on every redraw
    private var _signalMinute as Number = -1;
    private var _rainChance as Number? = null;
    private var _pressureFalling as Boolean = false;

    function initialize() {
        WatchFace.initialize();
        _burnIn = Lib.Aod.required();
        reloadSettings();
    }

    function onLayout(dc as Dc) as Void {
        _labelFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (dc.getWidth() * 0.048).toNumber(), Graphics.FONT_XTINY);
    }

    function reloadSettings() as Void {
        _accent = numberProperty("AccentColor", AMBER);
        _ring = numberProperty("Ring", RING_DAYLIGHT);
        _footer = numberProperty("Footer", FOOTER_SUN);
        var signals = Application.Properties.getValue("Signals");
        _signals = (signals instanceof Boolean) ? signals : true;
        _slots = [
            numberProperty("Slot1", Slots.HEART_RATE),
            numberProperty("Slot2", Slots.STEPS),
            numberProperty("Slot3", Slots.BODY_BATTERY)
        ];
        _signalMinute = -1;
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

        // Bezel ring
        var ringR = w * 0.471;
        var ringW = (w * 0.022).toNumber();
        if (_ring == RING_DAYLIGHT) {
            drawDaylightRing(dc, cx, cy, ringR, ringW, w);
        } else {
            var fraction = ringFraction();
            if (fraction != null) {
                Lib.Arcs.drawGauge(dc, cx, cy, ringR, 0, 360, fraction, ringW, TRACK, _accent);
            }
        }

        // Signals row at the top, only what applies right now
        if (_signals) {
            refreshSignals();
            drawSignals(dc, cx, (h * 0.13).toNumber(), w);
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

    // A 24 h dial with noon at the top: night in navy, daylight in the accent
    // colour from sunrise to sunset, and a sun marker at the current time.
    private function drawDaylightRing(dc as Dc, cx as Number, cy as Number, r as Float, width as Number, w as Number) as Void {
        dc.setColor(NIGHT, Graphics.COLOR_TRANSPARENT);
        Lib.Arcs.drawClockwise(dc, cx, cy, r, 0, 360, width);

        var times = Lib.Sun.today();
        var rise = times[0];
        var set = times[1];
        if (rise != null && set != null && set > rise) {
            dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
            Lib.Arcs.drawClockwise(dc, cx, cy, r, Lib.Sun.dialDegrees(rise), (set - rise) * 360.0 / 86400.0, width);
        }

        var clock = System.getClockTime();
        var now = clock.hour * 3600 + clock.min * 60;
        var sun = Lib.Arcs.point(cx, cy, r, Lib.Sun.dialDegrees(now));
        var markerR = (w * 0.016).toNumber();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sun[0], sun[1], markerR + 2);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(sun[0], sun[1], markerR);
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

    // --------------------------------------------------------------- signals

    private function refreshSignals() as Void {
        var minute = System.getClockTime().min;
        if (minute == _signalMinute) {
            return;
        }
        _signalMinute = minute;
        _rainChance = rainAhead();
        _pressureFalling = pressureFalling();
    }

    // Highest precipitation chance in the next few hours, when it is worth
    // mentioning; otherwise null.
    private function rainAhead() as Number? {
        if (!(Toybox has :Weather) || !(Weather has :getHourlyForecast)) {
            return null;
        }
        var hours = Weather.getHourlyForecast();
        if (hours == null) {
            return null;
        }
        var now = Time.now().value();
        var worst = 0;
        for (var i = 0; i < hours.size(); i++) {
            var when = hours[i].forecastTime;
            var chance = hours[i].precipitationChance;
            if (when == null || chance == null) {
                continue;
            }
            var t = when.value();
            if (t >= now - 1800 && t <= now + RAIN_WINDOW && chance > worst) {
                worst = chance;
            }
        }
        return (worst >= RAIN_CHANCE) ? worst : null;
    }

    // True when the barometer has dropped by the storm-alert amount over the
    // window: the oldest sample in the window against the newest.
    private function pressureFalling() as Boolean {
        if (!(Toybox has :SensorHistory) || !(Toybox.SensorHistory has :getPressureHistory)) {
            return false;
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
            return false;
        }
        return (newest - oldest) <= PRESSURE_DROP;
    }

    // Glyphs for whatever applies, centred on cx: rain (droplet + chance),
    // pressure falling (red triangle + "hPa"), phone disconnected (red dot),
    // do not disturb (circle with a bar).
    private function drawSignals(dc as Dc, cx as Number, y as Number, w as Number) as Void {
        var settings = System.getDeviceSettings();
        var phoneOff = !settings.phoneConnected;
        var dnd = (settings has :doNotDisturb) && settings.doNotDisturb;
        var rain = _rainChance;

        var font = Graphics.FONT_XTINY;
        var glyph = (w * 0.035).toNumber();   // 16 px
        var gap = (w * 0.012).toNumber();     // 5 px
        var between = (w * 0.04).toNumber();  // 18 px

        var rainText = (rain != null) ? rain.toString() + "%" : "";
        var total = 0;
        if (rain != null) {
            total += glyph + gap + dc.getTextWidthInPixels(rainText, font) + between;
        }
        if (_pressureFalling) {
            total += glyph + gap + dc.getTextWidthInPixels("hPa", font) + between;
        }
        if (phoneOff) {
            total += glyph + between;
        }
        if (dnd) {
            total += glyph + between;
        }
        if (total == 0) {
            return;
        }
        total -= between;

        var x = cx - total / 2;
        var left = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        if (rain != null) {
            drawDroplet(dc, x + glyph / 2, y, glyph, CYAN);
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + glyph + gap, y, font, rainText, left);
            x += glyph + gap + dc.getTextWidthInPixels(rainText, font) + between;
        }
        if (_pressureFalling) {
            var half = glyph / 2;
            var mx = x + half;
            dc.setColor(RED, Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[mx, y + half], [mx - half, y - half], [mx + half, y - half]] as Array<Graphics.Point2D>);
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + glyph + gap, y, font, "hPa", left);
            x += glyph + gap + dc.getTextWidthInPixels("hPa", font) + between;
        }
        if (phoneOff) {
            dc.setColor(RED, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x + glyph / 2, y, glyph / 4);
            x += glyph + between;
        }
        if (dnd) {
            var r = glyph / 2 - 1;
            dc.setPenWidth(2);
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(x + glyph / 2, y, r);
            dc.drawLine(x + glyph / 2 - r + 3, y, x + glyph / 2 + r - 2, y);
            x += glyph + between;
        }
    }

    // A water drop: a triangle on top of a circle
    private function drawDroplet(dc as Dc, x as Number, y as Number, size as Number, color as ColorType) as Void {
        var r = (size * 0.3).toNumber();
        var cy = y + (size * 0.18).toNumber();
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, cy, r);
        dc.fillPolygon([[x, y - size / 2], [x - r, cy - 1], [x + r, cy - 1]] as Array<Graphics.Point2D>);
    }

    // ---------------------------------------------------------------- footer

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

    // The next sun event only ("▲ 6:52" before sunrise, "▼ 17:41" during the
    // day), with the moon's phase beside it while the sun is down. Centred on
    // cx. The triangle is drawn, since the system fonts have no arrow glyphs.
    private function drawSunFooter(dc as Dc, cx as Number, y as Number, w as Number,
                                   textColor as ColorType, riseColor as ColorType, setColor as ColorType) as Void {
        var next = Lib.Sun.next(Lib.Sun.today());
        if (next == null) {
            return;
        }
        var night = next[0];
        var font = Graphics.FONT_XTINY;
        var text = Lib.Fmt.clock(next[1]);
        var tri = (w * 0.026).toNumber();
        var gap = (w * 0.018).toNumber();
        var moonR = (w * 0.022).toNumber();
        var moonSpace = night ? (2 * moonR + (w * 0.03).toNumber()) : 0;
        var x = cx - (moonSpace + tri + gap + dc.getTextWidthInPixels(text, font)) / 2;
        if (night) {
            Lib.Moon.draw(dc, x + moonR, y, moonR, Lib.Moon.phase(), GRAY, DIM);
            x += moonSpace;
        }
        drawSunTime(dc, x, y, night, text, tri, gap, font, night ? riseColor : setColor, textColor);
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
            dc.fillPolygon([[mx, y - half], [mx - half, y + half], [mx + half, y + half]] as Array<Graphics.Point2D>);
        } else {
            dc.fillPolygon([[mx, y + half], [mx - half, y - half], [mx + half, y - half]] as Array<Graphics.Point2D>);
        }
        dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + tri + gap, y, font, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        return tri + gap + dc.getTextWidthInPixels(text, font);
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
        var ringR = w * 0.454;
        if (_ring == RING_DAYLIGHT) {
            var times = Lib.Sun.today();
            var rise = times[0];
            var set = times[1];
            if (rise != null && set != null && set > rise) {
                dc.setColor(Lib.Aod.dim(_accent), Graphics.COLOR_TRANSPARENT);
                Lib.Arcs.drawClockwise(dc, cx, cy, ringR, Lib.Sun.dialDegrees(rise), (set - rise) * 360.0 / 86400.0, 2);
            }
            var clock = System.getClockTime();
            var sun = Lib.Arcs.point(cx, cy, ringR, Lib.Sun.dialDegrees(clock.hour * 3600 + clock.min * 60));
            dc.setPenWidth(2);
            dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(sun[0], sun[1], (w * 0.016).toNumber());
        } else {
            var fraction = ringFraction();
            if (fraction != null && fraction > 0.0) {
                dc.setColor(Lib.Aod.dim(_accent), Graphics.COLOR_TRANSPARENT);
                Lib.Arcs.drawClockwise(dc, cx, cy, ringR, 0, 360.0 * fraction, 2);
            }
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
