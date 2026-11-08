import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Lockup: rows of numbers stacked like a wood-type poster, reaching the bezel
// all the way round, in numerals of its own (Digits.mc) whose end digits bend
// to follow the circle. The date on top; the next sunset or sunrise, the
// countdown to it and the watch's battery; the time across the widest part;
// heart rate, steps and Body Battery; the temperature, with the high and low
// either side. No labels: size, weight, colour and place tell them apart,
// the families coloured as in Lib.Numbers.
//
// The face is kept in a full-screen bitmap and only the rows that changed are
// redrawn, so an update is a blit and a row or two. While awake a changed
// reading can roll to its new value (a setting), on a one-shot timer started
// only while awake: starting one in low power mode would crash a face.
//
// Standby (always-on): the date, the sun, the time and the temperature in
// outline, shifted each minute; under 5 % lit (designs/preview_lockup.py).
class LockupView extends WatchUi.WatchFace {

    // The readings: Lib.Numbers.Value, then these
    const BATTERY = Lib.Numbers.VALUES;
    const TIME = Lib.Numbers.VALUES + 1;
    const KEYS = Lib.Numbers.VALUES + 2;

    const ROLL = 380;          // ms a digit takes to roll
    const ROLL_FRAME = 100;    // ms between frames
    const BUDGET = 40;         // digits an update, about a full face: the watchdog allows three
    const TITLE = 0.050;       // the look's name, for a moment
    const ROW_GAP = 0.013;     // between rows
    const ITEM_GAP = 0.024;    // between readings in a row

    private var _values as Array<String> = [] as Array<String>;
    private var _asleep as Array<String>? = null;
    private var _rows as Array<LockupRow> = [] as Array<LockupRow>;
    private var _standby as Array<LockupRow> = [] as Array<LockupRow>;
    private var _rollFrom as Array<String?>;
    private var _rollAt as Array<Number>;

    private var _colors as Lib.Numbers.Colors = Lib.Numbers.colors(Lib.Look.YOURS);
    private var _look as Number = Lib.Look.YOURS;
    private var _rolling as Boolean = true;
    private var _minute as Number = -1;
    private var _second as Number = -1;
    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;
    private var _titled as Boolean = false;
    private var _waking as Boolean = false;
    private var _pending as Boolean = false;   // rows left for the next frame
    private var _cursor as Number = 0;
    private var _fixed as Boolean = false;     // the tests' readings
    private var _clock as Number? = null;      // the tests' clock
    private var _useTimer as Boolean = true;

    private var _ref as Graphics.BufferedBitmapReference? = null;
    private var _timer as Timer.Timer? = null;
    private var _ticking as Boolean = false;

    function initialize() {
        WatchFace.initialize();
        _burnIn = Lib.Aod.required();
        _rollFrom = new [KEYS] as Array<String?>;
        _rollAt = new [KEYS] as Array<Number>;
        for (var i = 0; i < KEYS; i++) {
            _rollAt[i] = 0;
        }
        reloadSettings();
    }

    function reloadSettings() as Void {
        _look = Lib.Look.mode();
        _colors = Lib.Numbers.colors(_look);
        _rolling = setting("RollingDigits", true);
        _minute = -1;
        build();
    }

    private function setting(key as String, fallback as Boolean) as Boolean {
        var v = null;
        try {
            v = Application.Properties.getValue(key);
        } catch (e) {
            v = null;
        }
        return (v instanceof Lang.Boolean) ? v as Boolean : fallback;
    }

    // ------------------------------------------------------------ the rows

    private function row(key as Number, black as Boolean, color as Number, alpha as Float, lx as Float, rx as Float, y0 as Float, y1 as Float,
                         bend as Float, least as Float, type as Complications.Type?) as LockupRow {
        var r = new LockupRow(key, black, lx, rx, y0, y1, bend, least, type);
        r.color = color;
        r.alpha = alpha;
        return r;
    }

    // The same numbers as designs/preview_lockup.py
    private function build() as Void {
        var c = _colors;
        var edge = -1.0;
        var probe = new LockupRow(0, true, edge, edge, 0.0, 1.0, 0.3, 1.0, null);
        var h = probe.halfAt(0.214);
        var sunSplit = 0.5 - h + 2.0 * h * 0.60;
        h = probe.halfAt(0.661);
        var bodySplit = 0.5 - h + 2.0 * h * 0.46;
        var sunRoom = 0.148 - ROW_GAP;
        var bodyHalf = (0.148 - ROW_GAP) / 2.0;
        var sunType = Complications.COMPLICATION_TYPE_SUNRISE;
        var weatherType = Complications.COMPLICATION_TYPE_CURRENT_WEATHER;
        _rows = [
            row(Lib.Numbers.DATE, true, c.neutral, (c.second == 1.0) ? 1.0 : 0.85, edge, edge, 0.052, 0.128, 0.60, 3.0, Complications.COMPLICATION_TYPE_CALENDAR_EVENTS),
            row(Lib.Numbers.SUN_TIME, true, c.sun, 1.0, edge, sunSplit, 0.140, 0.288, 0.30, 3.6, sunType),
            row(Lib.Numbers.COUNTDOWN, false, c.sun, 1.0, sunSplit + ITEM_GAP, edge, 0.140, 0.140 + sunRoom * 0.62, 0.30, 3.0, sunType),
            row(BATTERY, false, c.neutral, c.third, sunSplit + ITEM_GAP, edge, 0.140 + sunRoom * 0.62 + ROW_GAP, 0.288, 0.30, 2.6,
                Complications.COMPLICATION_TYPE_BATTERY),
            row(TIME, true, c.neutral, 1.0, edge, edge, 0.300, 0.575, 0.30, 3.6, null),
            row(Lib.Numbers.HEART, true, c.body, 1.0, edge, bodySplit, 0.587, 0.735, 0.30, 1.6, Complications.COMPLICATION_TYPE_HEART_RATE),
            row(Lib.Numbers.STEPS, false, c.body, c.second, bodySplit + ITEM_GAP, edge, 0.587, 0.587 + bodyHalf, 0.30, 2.6, Complications.COMPLICATION_TYPE_STEPS),
            row(Lib.Numbers.BODY, false, c.body, c.third, bodySplit + ITEM_GAP, edge, 0.587 + bodyHalf + ROW_GAP, 0.735, 0.30, 1.5, Complications.COMPLICATION_TYPE_BODY_BATTERY),
            row(Lib.Numbers.TEMP, true, c.weather, 1.0, 0.31, 0.69, 0.747, 0.945, 0.30, 1.8, weatherType),
            row(Lib.Numbers.HIGH, false, c.weather, c.second, edge, 0.31 - ITEM_GAP, 0.747, 0.842, 0.70, 1.5, weatherType),
            row(Lib.Numbers.LOW, false, c.weather, c.third, 0.69 + ITEM_GAP, edge, 0.747, 0.842, 0.70, 1.5, weatherType)
        ] as Array<LockupRow>;
        _standby = [
            row(Lib.Numbers.DATE, false, c.neutral, 0.8, edge, edge, 0.052, 0.128, 0.60, 3.0, null),
            row(Lib.Numbers.SUN_TIME, true, c.sun, 0.9, edge, edge, 0.160, 0.288, 0.30, 3.6, null),
            row(TIME, true, c.neutral, 1.0, edge, edge, 0.300, 0.575, 0.30, 3.6, null),
            row(Lib.Numbers.TEMP, true, c.weather, 0.9, 0.30, 0.70, 0.747, 0.945, 0.30, 1.8, null)
        ] as Array<LockupRow>;
    }

    // The complication a press and hold at (x, y) opens, or null on the time
    function targetAt(x as Number, y as Number) as Complications.Type? {
        var w = System.getDeviceSettings().screenWidth;
        for (var i = 0; i < _rows.size(); i++) {
            if (_rows[i].contains(x, y, w)) {
                return _rows[i].type;
            }
        }
        return null;
    }

    private function dirtyAll() as Void {
        for (var i = 0; i < _rows.size(); i++) {
            _rows[i].dirty = true;
        }
    }

    private function dirtyKey(key as Number) as Void {
        for (var i = 0; i < _rows.size(); i++) {
            if (_rows[i].key == key) {
                _rows[i].dirty = true;
            }
        }
    }

    function onLayout(dc as Dc) as Void {
        dirtyAll();
    }

    // ------------------------------------------------------------ readings

    private function now() as Number {
        var c = _clock;
        return (c != null) ? c : System.getTimer();
    }

    private function refresh() as Void {
        if (_fixed) {
            return;
        }
        var clock = System.getClockTime();
        if (clock.min != _minute || _values.size() == 0) {
            _minute = clock.min;
            var fresh = Lib.Numbers.read();
            fresh.add(battery());
            sample(fresh);
            fresh.add(fresh[Lib.Numbers.HOURS] + ":" + fresh[Lib.Numbers.MINUTES]);
            take(fresh);
        }
        if (_awake && clock.sec != _second) {
            _second = clock.sec;
            live();
        }
    }

    // New readings: a change marks its row, and rolls while awake
    private function take(fresh as Array<String>) as Void {
        var old = _values;
        for (var k = 0; k < fresh.size(); k++) {
            if (old.size() <= k || !fresh[k].equals(old[k])) {
                if (_awake && _rolling && moves(k) && old.size() > k && old[k].length() == fresh[k].length()) {
                    _rollFrom[k] = old[k];
                    _rollAt[k] = now();
                }
                dirtyKey(k);
            }
        }
        _values = fresh;
    }

    // A reading on the face that may roll: not the parts of the time or the
    // readings this face doesn't show
    private function moves(k as Number) as Boolean {
        return k != Lib.Numbers.HOURS && k != Lib.Numbers.MINUTES && k != Lib.Numbers.ALTITUDE && k != Lib.Numbers.WIND;
    }

    private function setValue(key as Number, text as String) as Void {
        if (_values.size() > key && !text.equals(_values[key])) {
            var fresh = _values.slice(null, null);
            fresh[key] = text;
            take(fresh);
        }
    }

    (:live)
    private function live() as Void {
        setValue(Lib.Numbers.HEART, Lib.Daily.heartRate());
    }

    (:sample)
    private function live() as Void {
    }

    // The watch's charge, as "87%"
    private function battery() as String {
        return System.getSystemStats().battery.format("%d") + "%";
    }

    (:live)
    private function sample(values as Array<String>) as Void {
    }

    // The screenshots' readings (sample.jungle)
    (:sample)
    private function sample(values as Array<String>) as Void {
        var fixed = ["10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "72", "6214", "82", "1240", "12", "87%"] as Array<String>;
        for (var i = 0; i < fixed.size(); i++) {
            values[i] = fixed[i];
        }
    }

    // ------------------------------------------------------------ sleep and wake

    function onEnterSleep() as Void {
        _awake = false;
        stopTimer();
        _asleep = _values;
        clearEffects();
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _awake = true;
        _waking = true;
        _minute = -1;
        _second = -1;
        dirtyAll();
        WatchUi.requestUpdate();
    }

    function onHide() as Void {
        stopTimer();
    }

    private function clearEffects() as Void {
        for (var k = 0; k < KEYS; k++) {
            _rollFrom[k] = null;
        }
    }

    // What changed while asleep rolls from what was last seen
    private function woke() as Void {
        _waking = false;
        var seen = _asleep;
        _asleep = null;
        if (seen == null || !_rolling) {
            return;
        }
        var t = now();
        for (var k = 0; k < _values.size() && k < seen.size(); k++) {
            if (!moves(k) || seen[k].equals(_values[k])) {
                continue;
            }
            if (seen[k].length() == _values[k].length()) {
                _rollFrom[k] = seen[k];
                _rollAt[k] = t;
            }
        }
    }

    private function animating() as Boolean {
        if (_pending) {
            return true;
        }
        for (var k = 0; k < KEYS; k++) {
            if (_rollFrom[k] != null) {
                return true;
            }
        }
        return false;
    }

    // Only while awake, and never in low power: a timer started there is fatal
    private function schedule() as Void {
        if (!_useTimer || !_awake || _ticking || !animating()) {
            return;
        }
        if ((System has :getDisplayMode) && System.getDisplayMode() != System.DISPLAY_MODE_HIGH_POWER) {
            return;
        }
        var timer = _timer;
        if (timer == null) {
            timer = new Timer.Timer();
            _timer = timer;
        }
        _ticking = true;
        timer.start(method(:onFrame), ROLL_FRAME, false);
    }

    function onFrame() as Void {
        _ticking = false;
        WatchUi.requestUpdate();
    }

    private function stopTimer() as Void {
        var timer = _timer;
        if (timer != null) {
            timer.stop();
        }
        _ticking = false;
    }

    // ------------------------------------------------------------ drawing

    function onUpdate(dc as Dc) as Void {
        refresh();
        var thin = !_awake && _burnIn;
        if (thin) {
            drawStandby(dc);
            return;
        }
        if (_waking) {
            woke();
        }
        var titled = _awake && Lib.Look.shown();
        if (titled != _titled) {
            _titled = titled;
            dirtyKey(Lib.Numbers.DATE);
        }
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        var bitmap = canvas(dc);
        var target = (bitmap != null) ? bitmap.getDc() : dc;
        if (target has :setAntiAlias) {
            target.setAntiAlias(true);
        }
        if (bitmap == null) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.clear();
            dirtyAll();
        }
        drawRows(target, bitmap == null);
        if (bitmap != null) {
            dc.drawBitmap(0, 0, bitmap);
        }
        if (titled) {
            dc.setColor(_colors.neutral, Graphics.COLOR_TRANSPARENT);
            dc.drawText(dc.getWidth() / 2, dc.getHeight() * 0.09,
                        Lib.Fmt.vectorFont("RobotoCondensedBold", (dc.getWidth() * TITLE * 1.173).toNumber(), Graphics.FONT_XTINY),
                        Lib.Look.title(_look, Lib.Numbers.NAMES), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        schedule();
    }

    // The face's bitmap, from the graphics pool, which can take it back at any
    // time; the rows are then all drawn again. Null without one.
    private function canvas(dc as Dc) as Graphics.BufferedBitmap? {
        if (!(Graphics has :createBufferedBitmap)) {
            return null;
        }
        var bitmap = null;
        var ref = _ref;
        if (ref != null) {
            bitmap = ref.get();
        }
        if (bitmap == null) {
            try {
                ref = Graphics.createBufferedBitmap({:width => dc.getWidth(), :height => dc.getHeight()});
                _ref = ref;
                bitmap = ref.get();
            } catch (e) {
                bitmap = null;
            }
            if (bitmap != null) {
                var b = (bitmap as Graphics.BufferedBitmap).getDc();
                b.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
                b.clear();
            }
            dirtyAll();
        }
        return bitmap as Graphics.BufferedBitmap?;
    }

    // The rows that need it, up to BUDGET digits an update: a wake where
    // everything rolls would pass the watchdog in one go, so it takes two or
    // three frames, each row's turn coming round. `all` draws them regardless.
    private function drawRows(dc as Dc, all as Boolean) as Void {
        var t = now();
        var count = _rows.size();
        var budget = BUDGET;
        _pending = false;
        for (var n = 0; n < count; n++) {
            var at = (_cursor + n) % count;
            var r = _rows[at];
            var k = r.key;
            var from = _rollFrom[k];
            if (from != null) {
                r.dirty = true;
            }
            if (!r.dirty) {
                continue;
            }
            var cost = (_values.size() > k ? _values[k].length() : 2) * (from != null ? 2 : 1);
            if (!all && cost > budget) {
                _pending = true;
                _cursor = at;
                break;
            }
            budget -= cost;
            r.dirty = false;
            var p = 1.0;
            if (from != null) {
                var q = (t - _rollAt[k]) / (ROLL * 1.0);
                if (q >= 1.0 || q < 0.0) {
                    _rollFrom[k] = null;
                    from = null;
                } else {
                    var e = 1.0 - q;
                    p = 1.0 - e * e * e;
                }
            }
            var text = _values.size() > k ? _values[k] : "--";
            if (k == Lib.Numbers.DATE && _titled) {
                text = "";
            }
            r.draw(dc, text, from, p, Lib.Numbers.scale(r.color, r.alpha));
        }
    }

    private function drawStandby(dc as Dc) as Void {
        var minute = System.getClockTime().min;
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(false);    // hard outlines: no faint pixels to count against the 10 %
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setPenWidth(1);
        var off = Lib.Aod.offset(minute, (dc.getWidth() * 0.006).toNumber());
        for (var i = 0; i < _standby.size(); i++) {
            var r = _standby[i];
            var text = _values.size() > r.key ? _values[r.key] : "--";
            r.outline(dc, text, Lib.Numbers.scale(r.color, r.alpha), off[0], off[1]);
        }
    }

    // ------------------------------------------------------------ for the tests

    // Fixed readings, in the order of Lib.Numbers.Value, then heading and time
    function setValues(values as Array<String>) as Void {
        _fixed = true;
        _useTimer = false;
        var fresh = values.slice(null, null);
        take(fresh);
    }

    function setClock(t as Number) as Void {
        _clock = t;
    }

    function setRolling(rolling as Boolean) as Void {
        _rolling = rolling;
    }

    function setAwake(awake as Boolean) as Void {
        _burnIn = true;
        if (awake) {
            onExitSleep();
        } else {
            onEnterSleep();
        }
    }

    function isAnimating() as Boolean {
        return animating();
    }

    function isRolling(key as Number) as Boolean {
        return _rollFrom[key] != null;
    }

    function valueOf(key as Number) as String {
        return _values[key];
    }
}
