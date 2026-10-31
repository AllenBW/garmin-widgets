import Toybox.Application;
import Toybox.Application.WatchFaceConfig;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

// Strata: one field of soil layers over the whole face, from the owner's
// laser-cut planter, and the day's readings set into it. The layers part
// round a clearing for each reading, like water round a stone (the field
// is generated offline with the clearings in it), so every reading sits
// on clean black. The time is the largest thing, in clean numerals cut
// out of the layers by a black keyline. Over it, the next sun event: its
// time on the centre line, the sun on the horizon to its left with a
// chevron over it (up for sunrise, down for sunset), and a bell to its
// right while an alarm is set; under that the date. The two share one
// clearing. Below the time four readings in a row, each a number under a
// coloured cue, chosen in the settings (Readings): by default a
// thermometer in the temperature's colour, a raindrop for the chance of
// rain, a heart, and footprints for the distance. The moon at the foot
// with its phase written in it.
//
// The layers are brown by day and graphite by night; every fourth takes
// the outside temperature's colour in a mineral tone, dimmed so it stays
// earth and not neon. From the first mile walked, a dark stone turns up
// in the layers for every quarter mile. Settings change the layers'
// colour, every fourth layer's, the time's, whether night has its own
// colours and whether the stones show (Palette), whether the time is
// filled or in outline (its colour goes to whichever), and what each of
// the four readings is.
//
// Always-on: one layer in eight, dim, the time in outline, the sun line,
// the date and the moon's lit limb and terminator, shifted each minute
// (Lib.Aod).
class StrataView extends WatchUi.WatchFace {

    // The layout, as fractions of the screen: the same numbers as
    // designs/preview_strata.py and the clearings in designs/gen_strata.py
    private const SUN_Y = 0.150;
    private const DATE_Y = 0.252;
    private const TIME_Y = 0.473;
    private const CUE_Y = 0.657;
    private const ROW_Y = 0.738;                                      // the readings' baseline
    private const ROW_X = [0.186, 0.391, 0.596, 0.801] as Array<Float>; // four reading slots
    private const MOON_Y = 0.862;
    private const MOON_R = 0.074;

    private const WHITE = 0xF2ECE2;          // warm white, like paper
    private const CREAM = 0xE6DCCB;
    private const GRAY = 0x8A8478;
    private const SUNRISE = 0xE9B04F;
    private const SUNSET = 0xE8854A;
    private const HEART = 0xC4584A;          // rosehip
    private const FEET_DAY = 0xB8AD9A;
    private const RAIN = 0x8FB8C8;           // the rain cloud
    private const DEW = 0x7FA8B8;            // the humidity drop
    private const LEAF = 0x9CC07A;           // Body Battery
    private const STONE = 0xB8AD9A;          // the watch's battery
    private const WIND = 0xA8B4BC;
    private const STONE_DAY = 0x4E3E26;
    private const STONE_NIGHT = 0x353B49;
    private const FEET_NIGHT = 0x8A94A6;
    private const MOON_LIT = 0x4E4A42;
    private const MOON_RIM = 0x9C937F;
    private const AOD_DATE = 0x8A8478;
    private const AOD_MOON = 0x6A6458;
    private const AOD_TERMINATOR = 0x5A564E;
    private const AOD_TIME = 0x9A9488;
    private const AOD_SUN = 0x6A6458;

    private const PEBBLE_CM = 40234;         // a quarter mile per stone
    private const PEBBLE_LEAST = 4;          // and none until the first mile
    private const KEYLINE = 3;               // px of black round the time
    private const EM_HEIGHT = 1.17;          // a vector font's height, in ems

    // Settings (resources/settings)
    private var _strata as Number = 0;
    private var _accent as Number = Palette.ACCENT_TEMPERATURE;
    private var _timeColor as Number = 0;
    private var _timeColorValue as Number? = null;   // the editor's data colour, over _timeColor
    private var _timeOutline as Boolean = false;   // the time in outline, not filled (fewer pixels lit)
    private var _dayNight as Boolean = true;
    private var _stones as Boolean = true;
    private var _slots as Array<Number> = Readings.DEFAULTS;   // the kind in each reading slot

    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;
    private var _layers as Layers?;

    private var _timeFont as FontType = Graphics.FONT_NUMBER_HOT;
    private var _sunFont as FontType = Graphics.FONT_TINY;
    private var _dateFont as FontType = Graphics.FONT_SMALL;
    private var _valueFont as FontType = Graphics.FONT_TINY;
    private var _unitFont as FontType = Graphics.FONT_XTINY;
    private var _moonFont as FontType = Graphics.FONT_XTINY;
    private var _aodDateFont as FontType = Graphics.FONT_XTINY;

    // Read when the minute changes
    private var _minute as Number = -1;
    private var _time as String = "";
    private var _sun as [Boolean, Number]? = null;
    private var _date as String = "";
    private var _celsius as Float? = null;
    private var _values as Array<[String, String]> = [["--", ""], ["--", ""], ["--", ""], ["--", ""]] as Array<[String, String]>;
    private var _pebbleCount as Number = 0;
    private var _alarms as Number = 0;
    private var _phase as Float = 0.0;

    // Press targets, [complication type, x, y, half width, half height]
    private var _targets as Array<Array<Number>> = [] as Array<Array<Number>>;

    // The layers in a full-screen bitmap in the graphics pool (3 MB on the
    // fenix 8, apart from the 128 KB the face itself gets), filled a batch
    // per frame so no call does more than the watchdog allows, then one
    // blit a frame. Without it the layers go straight to the screen.
    private const BATCH = 16;
    private var _base as Graphics.BufferedBitmapReference? = null;
    private var _key as String = "";
    private var _baseLayer as Number = 0;    // the next layer to draw into the bitmap
    private var _failed as Boolean = false;

    // The pen and colour last set on the dc being drawn, to skip repeats
    private var _pen as Number = 0;
    private var _color as Number = -1;

    function initialize() {
        WatchFace.initialize();
        _burnIn = Lib.Aod.required();
        reloadSettings();
    }

    // Read the settings (and again when they change in the phone app)
    function reloadSettings() as Void {
        _strata = setting("Strata", 0);
        _accent = setting("Accent", Palette.ACCENT_TEMPERATURE);
        _timeColor = setting("TimeColor", 0);
        _timeOutline = setting("TimeStyle", 0) == 1;
        var slots = [] as Array<Number>;
        for (var n = 0; n < 4; n++) {
            slots.add(Readings.kind(Application.Properties.getValue("Slot" + (n + 1)), n));
        }
        _slots = slots;
        var dayNight = Application.Properties.getValue("DayNight");
        _dayNight = (dayNight instanceof Boolean) ? dayNight : true;
        var stones = Application.Properties.getValue("Stones");
        _stones = (stones instanceof Boolean) ? stones : true;
        _timeColorValue = null;
        readEditor();
        _minute = -1;
    }

    // The fēnix 8's watch face editor (resources/configs/watchface.xml), over
    // the properties: the style is the time filled or in outline, the accent
    // colour the strata, the data colour the time's colour, data 1 to 4 the
    // readings. Watches without the editor keep the properties.
    private function readEditor() as Void {
        if (!(Application has :WatchFaceConfig)) {
            return;
        }
        var config = WatchFaceConfig.getSettings(null);
        if (config == null) {
            return;
        }
        var style = config.styleId;
        if (style != null) {
            _timeOutline = style == 1;
        }
        var accent = config.accentColor;
        if (accent != null && accent.color != null) {
            _strata = Palette.strataFromColor(accent.color as Number);
        }
        var data = config.complicationColor;
        if (data != null && data.color != null) {
            _timeColorValue = data.color as Number;
        }
        var refs = config.complicationSettings;
        if (refs != null) {
            for (var i = 0; i < refs.size(); i++) {
                var slot = refs[i].uniqueIdentifier;
                var id = refs[i].complicationId;
                if (slot != null && slot >= 1 && slot <= _slots.size() && id != null) {
                    var kind = Readings.fromComplication(id.getType());
                    if (kind != null) {
                        _slots[slot - 1] = kind;
                    }
                }
            }
        }
    }

    // The reading slot (1 to 4) at (x, y), for the editor's taps, or null
    function slotAt(x as Number, y as Number) as Number? {
        var w = System.getDeviceSettings().screenWidth;
        var h = System.getDeviceSettings().screenHeight;
        if ((y - h * (CUE_Y + ROW_Y) / 2).abs() > h * 0.08) {
            return null;
        }
        for (var n = 0; n < ROW_X.size(); n++) {
            if ((x - w * ROW_X[n]).abs() <= w * 0.1) {
                return n + 1;
            }
        }
        return null;
    }

    private function setting(key as String, fallback as Number) as Number {
        var value = Application.Properties.getValue(key);
        return (value instanceof Number) ? value : fallback;
    }

    function onLayout(dc as Dc) as Void {
        var w = dc.getWidth();
        _timeFont = font("RobotoCondensedBold", w, 0.31, Graphics.FONT_NUMBER_HOT);
        _sunFont = font("RobotoCondensedBold", w, 0.064, Graphics.FONT_TINY);
        _dateFont = font("RobotoCondensedRegular", w, 0.086, Graphics.FONT_SMALL);
        _valueFont = font("RobotoCondensedBold", w, 0.060, Graphics.FONT_TINY);
        _unitFont = font("RobotoCondensedRegular", w, 0.036, Graphics.FONT_XTINY);
        _moonFont = font("RobotoCondensedRegular", w, 0.034, Graphics.FONT_XTINY);
        _aodDateFont = font("RobotoCondensedRegular", w, 0.070, Graphics.FONT_XTINY);
        _layers = new Layers(w, dc.getHeight());
    }

    // A vector font whose em is `em` of the width, as the preview sets it:
    // the watch sizes a vector font by its whole height, about 1.17 ems
    // (measured on the simulator against designs/preview_strata.py)
    private function font(face as String, w as Number, em as Float, fallback as FontType) as FontType {
        return Lib.Fmt.vectorFont(face, (w * em * EM_HEIGHT).toNumber(), fallback);
    }

    // The once-a-minute readings
    function refresh() as Void {
        var clock = System.getClockTime();
        if (clock.min == _minute) {
            return;
        }
        _minute = clock.min;
        _time = Lib.Fmt.clock24(clock.hour * 3600 + clock.min * 60);
        _sun = Lib.Sun.next(Lib.Sun.today());
        _date = Lib.Daily.date();
        _celsius = Lib.Daily.temperatureCelsius();
        var values = [] as Array<[String, String]>;
        for (var n = 0; n < _slots.size(); n++) {
            values.add(Readings.read(_slots[n], _celsius));
        }
        _values = values;
        var cm = Lib.Daily.distanceCm();
        _pebbleCount = (cm != null) ? cm / PEBBLE_CM : 0;
        if (_pebbleCount < PEBBLE_LEAST || !_stones) {
            _pebbleCount = 0;
        }
        _alarms = Lib.Daily.alarms();
        _phase = Lib.Moon.phase();
        sample();
    }

    // Live builds read the watch; the sample build (sample.jungle) puts in
    // the readings designs/preview_strata.py uses, for screenshots
    (:live)
    private function sample() as Void {
    }

    (:sample)
    private function sample() as Void {
        _time = "14:38";
        _sun = [false, 19 * 3600 + 22 * 60] as [Boolean, Number];
        _date = "FRI OCT 30";
        _celsius = 7.8;
        var samples = [["46", "°F"], ["20", "%"], ["72", "bpm"], ["3.4", "mi"], ["64", ""], ["5280", "ft"],
                       ["68", "%"], ["8", "mph"], ["81", "%"], ["8412", ""]] as Array<[String, String]>;
        var values = [] as Array<[String, String]>;
        for (var n = 0; n < _slots.size(); n++) {
            values.add(samples[_slots[n]]);
        }
        _values = values;
        _pebbleCount = 13;
        _alarms = 1;
        _phase = 0.62;
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

    // How many stones the day's walking has turned up (for the tests)
    function pebblesShown() as Number {
        var layers = _layers;
        if (layers == null) {
            return 0;
        }
        return (_pebbleCount < layers.pebbles.size()) ? _pebbleCount : layers.pebbles.size();
    }

    // True once the layers are all in the bitmap (for the tests)
    function fieldReady() as Boolean {
        var layers = _layers;
        return _failed || (layers != null && _baseLayer >= layers.lines.size());
    }

    // ---------------------------------------------------------------- active

    private function drawActive(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var layers = _layers as Layers;
        var targets = [] as Array<Array<Number>>;
        var day = isDay();
        var night = !day && _dayNight;
        var earth = Palette.strata(_strata, night);
        var fieldAccent = Palette.layerAccent(_accent, _celsius, earth, night);
        var timeColor = (_timeColorValue != null) ? _timeColorValue as Number : Palette.time(_timeColor, _accent, _celsius, earth);

        // The field, then the stones the miles turned up
        var base = prepare(dc, layers, earth, fieldAccent);
        if (base != null) {
            dc.drawBitmap(0, 0, base);
        } else {
            drawLayers(dc, layers, layers.lines, layers.starts, 0, layers.lines.size(), 0, 0, earth, fieldAccent);
        }
        var shown = pebblesShown();
        dc.setColor(night ? STONE_NIGHT : STONE_DAY, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < shown; i++) {
            var p = layers.pebbles[i];
            dc.fillEllipse(p[0], p[1], p[2], (p[3] * 0.8).toNumber());
        }

        // The time, cut out of the layers
        var timeY = (h * TIME_Y).toNumber();
        if (_timeOutline) {
            // A wider keyline clears the layers round the outline; inside it stays black. The
            // outline is 3 px on the big screens, so the time stays heavier than the date.
            var line = (w >= 440) ? 3 : 2;
            drawCutOut(dc, cx, timeY, _timeFont, _time, Graphics.COLOR_BLACK, KEYLINE + line);
            drawOutline(dc, cx, timeY, _timeFont, _time, timeColor, line);
        } else {
            drawCutOut(dc, cx, timeY, _timeFont, _time, timeColor, KEYLINE);
        }

        // The next sun event, and any alarm
        var sunY = (h * SUN_Y).toNumber();
        var sun = _sun;
        if (sun != null) {
            drawSunLine(dc, cx, sunY, w, sun[0], Lib.Fmt.clock24(sun[1]), sun[0] ? SUNRISE : SUNSET, CREAM, _alarms);
            var type = sun[0] ? Complications.COMPLICATION_TYPE_SUNRISE : Complications.COMPLICATION_TYPE_SUNSET;
            targets.add([type as Number, cx, sunY, (w * 0.15).toNumber(), (h * 0.04).toNumber()]);
        } else {
            drawSunLine(dc, cx, sunY, w, false, "--:--", GRAY, GRAY, _alarms);
        }

        // The date
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var dateY = (h * DATE_Y).toNumber();
        dc.setColor(CREAM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, dateY, _dateFont, _date, center);
        targets.add([Complications.COMPLICATION_TYPE_CALENDAR_EVENTS as Number, cx, dateY, (w * 0.26).toNumber(), (h * 0.045).toNumber()]);

        // The four readings the settings chose: a cue over each number
        var cueY = (h * CUE_Y).toNumber();
        var rowY = (h * ROW_Y).toNumber();
        var cue = (w * 0.036).toNumber();
        var midY = (cueY + rowY) / 2 - (h * 0.01).toNumber();   // a reading's cue and number together
        for (var n = 0; n < _slots.size() && n < ROW_X.size(); n++) {
            var x = (w * ROW_X[n]).toNumber();
            var value = _values[n];
            drawCue(dc, _slots[n], x, cueY, cue, night);
            drawReading(dc, x, rowY, w, value[0], value[1]);
            targets.add([Readings.complication(_slots[n]) as Number, x, midY, (w * 0.095).toNumber(), (h * 0.065).toNumber()]);
        }

        // The moon at the foot, its phase written in it
        drawMoon(dc, cx, (h * MOON_Y).toNumber(), (w * MOON_R).toNumber());

        _targets = targets;
    }

    // Make the bitmap and fill it a batch of layers per call. Returns it
    // once it has something to show, else null.
    private function prepare(dc as Dc, layers as Layers, earth as Number, accent as Number) as Graphics.BufferedBitmap? {
        if (_failed || !(Graphics has :createBufferedBitmap)) {
            return null;
        }
        if (_base == null) {
            try {
                _base = Graphics.createBufferedBitmap({:width => dc.getWidth(), :height => dc.getHeight()});
            } catch (e) {
                _failed = true;
                return null;
            }
            _key = "";
        }
        var base = (_base as Graphics.BufferedBitmapReference).get() as Graphics.BufferedBitmap?;
        if (base == null) {
            _base = null;   // reclaimed by the pool; make it again next time
            _key = "";
            return null;
        }
        var bdc = base.getDc();
        var key = earth.toString() + "/" + accent.toString();
        if (!key.equals(_key)) {
            bdc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            bdc.clear();
            if (bdc has :setAntiAlias) {
                bdc.setAntiAlias(true);
            }
            _key = key;
            _baseLayer = 0;
        }
        var count = layers.lines.size();
        if (_baseLayer < count) {
            var end = _baseLayer + BATCH;
            if (end > count) {
                end = count;
            }
            drawLayers(bdc, layers, layers.lines, layers.starts, _baseLayer, end, 0, 0, earth, accent);
            _baseLayer = end;
            if (_baseLayer < count) {
                WatchUi.requestUpdate();   // keep going
            }
        }
        return base;
    }

    private function setLine(dc as Dc, pen as Number, color as Number) as Void {
        if (pen != _pen) {
            dc.setPenWidth(pen);
            _pen = pen;
        }
        if (color != _color) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            _color = color;
        }
    }

    // Pieces from..to-1 of `lines` (always-on's, or the layers'), thin,
    // offset by (ox, oy), in `earth` and the accents in `accent` (all of
    // always-on's are accents)
    private function drawLayers(dc as Dc, layers as Layers, lines as Array<Array<Float>>, starts as Array<Float>,
                                from as Number, to as Number, ox as Number, oy as Number, earth as Number, accent as Number) as Void {
        var aod = lines != layers.lines;
        var step = layers.step;
        _pen = 0;
        _color = -1;
        for (var k = from; k < to; k++) {
            var isAccent = aod || layers.isAccent(k);
            setLine(dc, 1, isAccent ? accent : earth);
            var ys = lines[k];
            var x0 = starts[k];
            var x1 = x0 + ox;
            var y1 = ys[0] + oy;
            for (var i = 1; i < ys.size(); i++) {
                var x2 = x0 + i * step + ox;
                var y2 = ys[i] + oy;
                dc.drawLine(x1, y1, x2, y2);
                x1 = x2;
                y1 = y2;
            }
        }
    }

    // Day while the next sun event is sunset (and with no sun data at all)
    private function isDay() as Boolean {
        var sun = _sun;
        return sun == null || !sun[0];
    }

    // Text centred on (x, y), cut out of whatever is under it by a black
    // keyline `line` px wide
    private function drawCutOut(dc as Dc, x as Number, y as Number, font as FontType, text as String,
                                color as ColorType, line as Number) as Void {
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var d = (line * 0.7).toNumber();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x - line, y, font, text, center);
        dc.drawText(x + line, y, font, text, center);
        dc.drawText(x, y - line, font, text, center);
        dc.drawText(x, y + line, font, text, center);
        dc.drawText(x - d, y - d, font, text, center);
        dc.drawText(x + d, y - d, font, text, center);
        dc.drawText(x - d, y + d, font, text, center);
        dc.drawText(x + d, y + d, font, text, center);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text, center);
    }

    // The sun event's time centred on (cx, y), the sun on its horizon hung
    // to its left and a bell to its right while an alarm is set. Public so
    // the tests can draw it with an alarm: the simulator never has one set.
    function drawSunLine(dc as Dc, cx as Number, y as Number, w as Number, isRise as Boolean, time as String,
                         color as ColorType, textColor as ColorType, alarms as Number) as Void {
        var a = w * 0.052;
        var gap = w * 0.020;
        var bell = w * 0.030;
        var half = dc.getTextWidthInPixels(time, _sunFont) / 2.0;
        dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, _sunFont, time, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        drawSun(dc, cx - half - gap - a / 2.0, y, a, isRise, color);
        if (alarms > 0) {
            drawBell(dc, cx + half + gap + bell / 2.0, y, bell, MOON_RIM);
        }
    }

    // The sun half risen on a horizon `s` long, centred on (cx, cy), and an
    // open chevron over it: up for sunrise, down for sunset
    private function drawSun(dc as Dc, cx as Float, cy as Number, s as Float, isRise as Boolean, color as ColorType) as Void {
        var horizon = cy + s * 0.36;
        var r = s * 0.33;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.fillPolygon(halfDisc(cx, horizon, r));
        dc.drawLine(cx - s / 2.0, horizon, cx + s / 2.0, horizon);
        var c = s * 0.24;
        var near = horizon - r - s * 0.2;
        var far = near - s * 0.22;
        var wing = isRise ? near : far;
        var tip = isRise ? far : near;
        dc.drawLine(cx - c, wing, cx, tip);
        dc.drawLine(cx, tip, cx + c, wing);
    }

    // The upper half of a disc on (cx, cy), as a polygon
    private function halfDisc(cx as Float, cy as Float, r as Float) as Array<Graphics.Point2D> {
        var points = [] as Array<Graphics.Point2D>;
        var steps = 10;
        for (var i = 0; i <= steps; i++) {
            var t = Math.PI * i / steps;
            points.add([cx + r * Math.cos(t), cy - r * Math.sin(t)] as Graphics.Point2D);
        }
        return points;
    }

    // An outline bell `s` tall centred on (cx, cy)
    private function drawBell(dc as Dc, cx as Float, cy as Number, s as Float, color as ColorType) as Void {
        var r = s * 0.32;
        var top = cy - s * 0.14;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawArc(cx, top, r, Graphics.ARC_COUNTER_CLOCKWISE, 0, 180);
        dc.drawLine(cx - r, top, cx - s * 0.36, cy + s * 0.22);
        dc.drawLine(cx + r, top, cx + s * 0.36, cy + s * 0.22);
        dc.drawLine(cx - s * 0.46, cy + s * 0.24, cx + s * 0.46, cy + s * 0.24);
        dc.fillCircle(cx, cy + s * 0.38, s * 0.08);
    }

    // A reading's cue, `s` tall, centred on (x, y): its own shape and colour
    private function drawCue(dc as Dc, kind as Number, x as Number, y as Number, s as Number, night as Boolean) as Void {
        switch (kind) {
            case Readings.TEMPERATURE:
                drawThermometer(dc, x, y, s, Palette.temperature(_celsius));
                break;
            case Readings.RAIN:
                drawCloud(dc, x, y, s, RAIN);
                break;
            case Readings.HEART:
                drawHeart(dc, x, y, (s * 0.85).toNumber(), HEART);
                break;
            case Readings.DISTANCE:
                drawTrail(dc, x, y, s, night ? FEET_NIGHT : FEET_DAY);
                break;
            case Readings.STEPS:
                drawFootprints(dc, x, y, s, night ? FEET_NIGHT : FEET_DAY);
                break;
            case Readings.BODY_BATTERY:
                drawBolt(dc, x, y, s, LEAF);
                break;
            case Readings.ELEVATION:
                drawMountain(dc, x, y, s, night ? FEET_NIGHT : FEET_DAY);
                break;
            case Readings.HUMIDITY:
                drawDrop(dc, x, y, s, DEW);
                break;
            case Readings.WIND:
                drawWind(dc, x, y, s, WIND);
                break;
            case Readings.BATTERY:
                drawBattery(dc, x, y, s, STONE, Lib.Daily.watchBattery());
                break;
        }
    }

    // A raindrop `s` tall (humidity)
    private function drawDrop(dc as Dc, cx as Number, cy as Number, s as Number, color as ColorType) as Void {
        var r = s * 0.27;
        var by = cy + s * 0.5 - r;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var points = [[cx, cy - s * 0.5]] as Array<Graphics.Point2D>;
        for (var i = 0; i <= 8; i++) {
            var a = Math.PI * (-0.2 + 1.4 * i / 8);   // round the bottom from the right shoulder to the left
            points.add([cx + r * Math.cos(a), by + r * Math.sin(a)] as Graphics.Point2D);
        }
        dc.fillPolygon(points);
    }

    // A cloud with two drops falling from it, `s` tall (chance of rain)
    private function drawCloud(dc as Dc, cx as Number, cy as Number, s as Number, color as ColorType) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - s * 0.2, cy - s * 0.08, s * 0.2);
        dc.fillCircle(cx + s * 0.06, cy - s * 0.2, s * 0.26);
        dc.fillCircle(cx + s * 0.3, cy - s * 0.06, s * 0.18);
        dc.fillRoundedRectangle(cx - s * 0.4, cy - s * 0.08, s * 0.88, s * 0.2, s * 0.1);
        dc.setPenWidth(2);
        dc.drawLine(cx - s * 0.12, cy + s * 0.26, cx - s * 0.18, cy + s * 0.46);
        dc.drawLine(cx + s * 0.16, cy + s * 0.26, cx + s * 0.1, cy + s * 0.46);
    }

    // A trail of dots winding up to a map pin, `s` tall (distance)
    private function drawTrail(dc as Dc, cx as Number, cy as Number, s as Number, color as ColorType) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var r = (s * 0.1 < 1.5) ? 1.5 : s * 0.1;
        dc.fillCircle(cx - s * 0.42, cy + s * 0.36, r);
        dc.fillCircle(cx - s * 0.16, cy + s * 0.4, r);
        dc.fillCircle(cx + s * 0.02, cy + s * 0.16, r);
        var px = cx + s * 0.22;
        var py = cy - s * 0.2;
        var pr = s * 0.2;
        dc.fillCircle(px, py, pr);
        dc.fillPolygon([[px - pr * 0.85, py + pr * 0.5], [px + pr * 0.85, py + pr * 0.5], [px, py + pr * 2.1]] as Array<Graphics.Point2D>);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(px, py, pr * 0.4);
    }

    // A solid lightning bolt `s` tall (Body Battery)
    private function drawBolt(dc as Dc, cx as Number, cy as Number, s as Number, color as ColorType) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [cx + s * 0.22, cy - s * 0.5], [cx - s * 0.4, cy + s * 0.08], [cx - s * 0.03, cy + s * 0.08],
            [cx - s * 0.22, cy + s * 0.5], [cx + s * 0.4, cy - s * 0.1], [cx + s * 0.03, cy - s * 0.1]
        ] as Array<Graphics.Point2D>);
    }

    // Two peaks `s` tall (elevation)
    private function drawMountain(dc as Dc, cx as Number, cy as Number, s as Number, color as ColorType) as Void {
        var foot = cy + s * 0.4;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx - s * 0.12, cy - s * 0.45], [cx + s * 0.32, foot], [cx - s * 0.56, foot]] as Array<Graphics.Point2D>);
        dc.fillPolygon([[cx + s * 0.28, cy - s * 0.12], [cx + s * 0.56, foot], [cx, foot]] as Array<Graphics.Point2D>);
    }

    // Three gusts `s` tall (wind): the outer two end in a curl, the middle
    // one shorter
    private function drawWind(dc as Dc, cx as Number, cy as Number, s as Number, color as ColorType) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        var lengths = [0.85, 0.6, 0.75] as Array<Float>;
        for (var i = 0; i < 3; i++) {
            var y = cy + (i - 1) * s * 0.3;
            var left = cx - s * 0.5;
            var right = left + s * lengths[i];
            dc.drawLine(left, y, right, y);
            if (i != 1) {
                var r = (s * 0.13).toNumber();
                // From the line's end round three quarters of a circle: up and back for the top gust, down and back for the bottom one
                if (i == 0) {
                    dc.drawArc(right, y - r, r, Graphics.ARC_COUNTER_CLOCKWISE, 270, 180);
                } else {
                    dc.drawArc(right, y + r, r, Graphics.ARC_CLOCKWISE, 90, 180);
                }
            }
        }
    }

    // A battery `s` tall, standing, filled to `level` per cent
    private function drawBattery(dc as Dc, cx as Number, cy as Number, s as Number, color as ColorType, level as Number) as Void {
        var bw = (s * 0.5).toNumber();
        var bh = (s * 0.86).toNumber();
        var left = cx - bw / 2;
        var top = cy - s / 2 + (s * 0.14).toNumber();
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRoundedRectangle(left, top, bw, bh, 2);
        dc.fillRectangle(cx - bw / 4, cy - s / 2, bw / 2, (s * 0.12).toNumber() + 1);
        var inner = ((bh - 6) * (level < 0 ? 0 : (level > 100 ? 100 : level)) / 100).toNumber();
        dc.fillRectangle(left + 3, top + bh - 3 - inner, bw - 6, inner);
    }

    // A filled thermometer `s` tall: a stem and a bulb
    private function drawThermometer(dc as Dc, cx as Number, cy as Number, s as Number, color as ColorType) as Void {
        var r = s * 0.22;
        var bulb = cy + s * 0.5 - r;
        var stem = s * 0.14;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - stem, cy - s * 0.5, 2 * stem, bulb - (cy - s * 0.5), stem);
        dc.fillCircle(cx, bulb, r);
    }

    // A filled heart `s` tall
    private function drawHeart(dc as Dc, cx as Number, cy as Number, s as Number, color as ColorType) as Void {
        var r = s * 0.27;
        var top = cy - s * 0.30;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx - r, top, r);
        dc.fillCircle(cx + r, top, r);
        dc.fillPolygon([[cx - 2 * r + r * 0.08, top + r * 0.35], [cx + 2 * r - r * 0.08, top + r * 0.35], [cx, cy + s * 0.42]] as Array<Graphics.Point2D>);
    }

    // Two footprints `s` tall, one ahead of the other: a sole and a heel
    private function drawFootprints(dc as Dc, cx as Number, cy as Number, s as Number, color as ColorType) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 2; i++) {
            var x = cx + ((i == 0) ? -0.28 : 0.28) * s;
            var y = cy + ((i == 0) ? 0.08 : -0.08) * s;
            dc.fillEllipse(x, y - s * 0.17, s * 0.18, s * 0.28);   // the sole
            dc.fillEllipse(x, y + s * 0.3, s * 0.13, s * 0.115);   // the heel
        }
    }

    // A number in cream bold centred on x, its unit in small grey hung off
    // its right, on one baseline
    private function drawReading(dc as Dc, x as Number, baseline as Number, w as Number, value as String, unit as String) as Void {
        var half = dc.getTextWidthInPixels(value, _valueFont) / 2;
        dc.setColor(CREAM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x - half, baseline - Graphics.getFontAscent(_valueFont), _valueFont, value, Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + half + (w * 0.008).toNumber(), baseline - Graphics.getFontAscent(_unitFont), _unitFont, unit, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // The moon as it is tonight, its phase written across it in mixed case
    private function drawMoon(dc as Dc, cx as Number, cy as Number, r as Number) as Void {
        Lib.Moon.draw(dc, cx, cy, r, _phase, MOON_LIT, MOON_RIM);
        var name = Lib.Moon.name(_phase);
        var space = name.find(" ");
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var gap = (dc.getWidth() * 0.021).toNumber();
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        if (space == null) {
            dc.drawText(cx, cy, _moonFont, name, center);
        } else {
            dc.drawText(cx, cy - gap, _moonFont, name.substring(0, space) as String, center);
            dc.drawText(cx, cy + gap, _moonFont, capitalised(name.substring(space + 1, name.length()) as String), center);
        }
    }

    // "gibbous" -> "Gibbous"
    private function capitalised(word as String) as String {
        if (word.length() == 0) {
            return word;
        }
        return (word.substring(0, 1) as String).toUpper() + (word.substring(1, word.length()) as String);
    }

    // ------------------------------------------------------------- always-on

    private function drawAlwaysOn(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var off = Lib.Aod.offset(System.getClockTime().min, (w * 0.013).toNumber());
        var cx = w / 2 + off[0];
        var layers = _layers as Layers;

        // One layer in eight, dim, then the time in outline and the sun line
        var night = !isDay() && _dayNight;
        var accent = Palette.layerAccent(_accent, _celsius, Palette.strata(_strata, night), night);
        drawLayers(dc, layers, layers.aodLines, layers.aodStarts, 0, layers.aodLines.size(), off[0], off[1], 0, Palette.scale(accent, 0.6));
        drawOutline(dc, cx, (h * TIME_Y).toNumber() + off[1], _timeFont, _time, AOD_TIME, 1);
        var sun = _sun;
        if (sun != null) {
            drawSunLine(dc, cx, (h * SUN_Y).toNumber() + off[1], w, sun[0], Lib.Fmt.clock24(sun[1]), AOD_SUN, AOD_SUN, 0);
        }
        dc.setColor(AOD_DATE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * DATE_Y).toNumber() + off[1], _aodDateFont, _date, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        // The moon's lit limb and its terminator
        var c = Math.cos(2.0 * Math.PI * _phase).toFloat();
        if (c < 0.98) {
            var my = (h * MOON_Y).toNumber() + off[1];
            var r = (w * MOON_R).toNumber();
            var start = (_phase < 0.5) ? 270 : 90;
            dc.setPenWidth(2);
            dc.setColor(AOD_MOON, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, my, r, Graphics.ARC_COUNTER_CLOCKWISE, start, (start + 180) % 360);
            dc.setPenWidth(1);
            dc.setColor(AOD_TERMINATOR, Graphics.COLOR_TRANSPARENT);
            var side = (_phase < 0.5) ? 1.0 : -1.0;
            var steps = 12;
            var px = cx.toFloat();
            var py = (my - r).toFloat();
            for (var i = 1; i <= steps; i++) {
                var dy = -r + 2.0 * r * i / steps;
                var x = cx + side * c * Math.sqrt(r * r - dy * dy).toFloat();
                dc.drawLine(px, py, x, my + dy);
                px = x;
                py = my + dy;
            }
        }
        _targets = [] as Array<Array<Number>>;
    }

    // Text centred on (x, y) as an outline `line` px wide: drawn in colour
    // round the spot, then black on it
    private function drawOutline(dc as Dc, x as Number, y as Number, font as FontType, text as String, color as ColorType,
                                 line as Number) as Void {
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x - line, y - line, font, text, center);
        dc.drawText(x + line, y - line, font, text, center);
        dc.drawText(x - line, y + line, font, text, center);
        dc.drawText(x + line, y + line, font, text, center);
        if (line > 1) {
            dc.drawText(x - line, y, font, text, center);
            dc.drawText(x + line, y, font, text, center);
            dc.drawText(x, y - line, font, text, center);
            dc.drawText(x, y + line, font, text, center);
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text, center);
    }
}
