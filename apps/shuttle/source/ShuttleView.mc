import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Shuttle: Lockup's face (design #23) with the motion turned sideways. Rows of
// numbers stacked like a wood-type poster, reaching the bezel all the way
// round, in Lockup's numerals (Digits.mc); the date on top; the next sunset
// or sunrise, the countdown to it and the watch's battery; the time across
// the widest part; heart rate, steps and Body Battery; the temperature, with
// the high and low either side. No labels: size, weight, colour and place
// tell them apart, the families coloured as in Lib.Numbers.
//
// Every digit has a slot of its own. A digit that changed slides out of its
// slot sideways as the new one slides in behind it (ShuttleRow), units
// first, the bands alternating direction (the first to the right, the next
// to the left), so a busy wake weaves. Only what changed since it was last
// seen moves: a minute passing moves the time and the countdown, a new heart
// rate one digit, a wake whatever changed while asleep.
//
// The face is kept in a full-screen bitmap and only the rows that changed are
// redrawn, so an update is a blit and a row or two, at most BUDGET digits.
// The frames come from Lib.Motion.Pacer: its timer starts only once the face
// is shown awake (a timer started in low power mode kills a face), and the
// motion moves only by drawn frames.
//
// Standby (always-on): the date, the sun, the time and the temperature in
// outline, shifted each minute, as Lockup's (designs/preview_shuttle.py).
class ShuttleView extends WatchUi.WatchFace {

    // The readings: Lib.Numbers.Value, then these
    const BATTERY = Lib.Numbers.VALUES;
    const TIME = Lib.Numbers.VALUES + 1;
    const KEYS = Lib.Numbers.VALUES + 2;

    const FRAME = 50;          // ms between the timer's frames; the fēnix 8 draws one about every 63
    const MOST_FRAMES = 4;     // frames' worth one drawn frame may move: a stall skips, never stretches
    const BAND_LAG = 50;       // ms each band waits for the one above it, so a busy wake sweeps down
    const BUDGET = 40;         // digits an update, about a full face: the watchdog allows three
    const BUILD = 14;          // digits a frame while a start builds the face, the time alone first
    const TITLE = 0.050;       // the look's name, for a moment
    const ROW_GAP = 0.013;     // between rows
    const ITEM_GAP = 0.024;    // between readings in a row

    private var _values as Array<String> = [] as Array<String>;
    private var _asleep as Array<String>? = null;
    private var _rows as Array<ShuttleRow> = [] as Array<ShuttleRow>;
    private var _standby as Array<ShuttleRow> = [] as Array<ShuttleRow>;
    private var _rollFrom as Array<String?>;   // what a moving reading moves from
    private var _rollAt as Array<Number>;      // when its move began
    private var _lead as Array<Number>;        // ms its units digit waits, for its band and the readings to its right
    private var _tail as Array<Number>;        // ms its last digit waits
    private var _moved as Array<Number>;       // how many of its digits move

    private var _colors as Lib.Numbers.Colors = Lib.Numbers.colors(Lib.Look.YOURS);
    private var _look as Number = Lib.Look.YOURS;
    private var _day as Number = 0;           // the daily look's day
    private var _rolling as Boolean = true;
    private var _minute as Number = -1;
    private var _second as Number = -1;
    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;
    private var _titled as Boolean = false;
    private var _waking as Boolean = false;
    private var _pending as Boolean = false;   // rows left for the next frame
    private var _cursor as Number = 0;
    private var _late as Boolean = true;       // a start's first frame: the time alone
    private var _building as Boolean = true;   // a start: the rest a few rows a frame, a frame straight after another
    private var _asked as Boolean = false;     // this frame is one the build asked for, not the system's
    private var _drew as Number = 0;           // rows drawn by the last update
    private var _titleFont as Graphics.FontType? = null;   // made on the look's name's first frame, kept
    private var _fixed as Boolean = false;     // the tests' readings
    private var _clock as Number? = null;      // the tests' clock
    private var _motion as Number = 0;         // the motion's clock: ms of drawn frames

    private var _ref as Graphics.BufferedBitmapReference? = null;
    private var _bitmap as Graphics.BufferedBitmap? = null;
    private var _pacer as Lib.Motion.Pacer;
    private var _log as Lib.Timing.Log;         // how quickly it lights

    function initialize() {
        WatchFace.initialize();
        _log = new Lib.Timing.Log("Shuttle");
        _burnIn = Lib.Aod.required();
        _pacer = new Lib.Motion.Pacer(FRAME, MOST_FRAMES);
        _rollFrom = new [KEYS] as Array<String?>;
        _rollAt = new [KEYS] as Array<Number>;
        _lead = new [KEYS] as Array<Number>;
        _tail = new [KEYS] as Array<Number>;
        _moved = new [KEYS] as Array<Number>;
        for (var i = 0; i < KEYS; i++) {
            _rollAt[i] = 0;
            _lead[i] = 0;
            _tail[i] = 0;
            _moved[i] = 0;
        }
        reloadSettings();
    }

    function reloadSettings() as Void {
        _look = Lib.Look.mode();
        _colors = Lib.Numbers.colors(_look);
        _day = Lib.Look.today();
        _rolling = setting("SlidingDigits", true);
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

    private function row(key as Number, band as Number, black as Boolean, color as Number, alpha as Float, lx as Float, rx as Float,
                         y0 as Float, y1 as Float, bend as Float, least as Float, type as Complications.Type?) as ShuttleRow {
        var r = new ShuttleRow(key, black, lx, rx, y0, y1, bend, least, type);
        r.color = color;
        r.alpha = alpha;
        r.setBand(band);
        return r;
    }

    // The same numbers as designs/preview_shuttle.py (and Lockup's)
    private function build() as Void {
        var c = _colors;
        var edge = -1.0;
        var probe = new ShuttleRow(0, true, edge, edge, 0.0, 1.0, 0.3, 1.0, null);
        var h = probe.halfAt(0.214);
        var sunSplit = 0.5 - h + 2.0 * h * 0.60;
        h = probe.halfAt(0.661);
        var bodySplit = 0.5 - h + 2.0 * h * 0.46;
        var sunRoom = 0.148 - ROW_GAP;
        var bodyHalf = (0.148 - ROW_GAP) / 2.0;
        var sunType = Complications.COMPLICATION_TYPE_SUNRISE;
        var weatherType = Complications.COMPLICATION_TYPE_CURRENT_WEATHER;
        _rows = [
            row(Lib.Numbers.DATE, 0, true, c.neutral, (c.second == 1.0) ? 1.0 : 0.85, edge, edge, 0.052, 0.128, 0.60, 3.0, Complications.COMPLICATION_TYPE_CALENDAR_EVENTS),
            row(Lib.Numbers.SUN_TIME, 1, true, c.sun, 1.0, edge, sunSplit, 0.140, 0.288, 0.30, 3.6, sunType),
            row(Lib.Numbers.COUNTDOWN, 1, false, c.sun, 1.0, sunSplit + ITEM_GAP, edge, 0.140, 0.140 + sunRoom * 0.62, 0.30, 3.0, sunType),
            row(BATTERY, 1, false, c.neutral, c.third, sunSplit + ITEM_GAP, edge, 0.140 + sunRoom * 0.62 + ROW_GAP, 0.288, 0.30, 2.6,
                Complications.COMPLICATION_TYPE_BATTERY),
            row(TIME, 2, true, c.neutral, 1.0, edge, edge, 0.300, 0.575, 0.30, 3.6, null),
            row(Lib.Numbers.HEART, 3, true, c.body, 1.0, edge, bodySplit, 0.587, 0.735, 0.30, 1.6, Complications.COMPLICATION_TYPE_HEART_RATE),
            row(Lib.Numbers.STEPS, 3, false, c.body, c.second, bodySplit + ITEM_GAP, edge, 0.587, 0.587 + bodyHalf, 0.30, 2.6, Complications.COMPLICATION_TYPE_STEPS),
            row(Lib.Numbers.BODY, 3, false, c.body, c.third, bodySplit + ITEM_GAP, edge, 0.587 + bodyHalf + ROW_GAP, 0.735, 0.30, 1.5, Complications.COMPLICATION_TYPE_BODY_BATTERY),
            row(Lib.Numbers.TEMP, 4, true, c.weather, 1.0, 0.31, 0.69, 0.747, 0.945, 0.30, 1.8, weatherType),
            row(Lib.Numbers.HIGH, 4, false, c.weather, c.second, edge, 0.31 - ITEM_GAP, 0.747, 0.842, 0.70, 1.5, weatherType),
            row(Lib.Numbers.LOW, 4, false, c.weather, c.third, 0.69 + ITEM_GAP, edge, 0.747, 0.842, 0.70, 1.5, weatherType)
        ] as Array<ShuttleRow>;
        _standby = [
            row(Lib.Numbers.DATE, 0, false, c.neutral, 0.8, edge, edge, 0.052, 0.128, 0.60, 3.0, null),
            row(Lib.Numbers.SUN_TIME, 1, true, c.sun, 0.9, edge, edge, 0.160, 0.288, 0.30, 3.6, null),
            row(TIME, 2, true, c.neutral, 1.0, edge, edge, 0.300, 0.575, 0.30, 3.6, null),
            row(Lib.Numbers.TEMP, 4, true, c.weather, 0.9, 0.30, 0.70, 0.747, 0.945, 0.30, 1.8, null)
        ] as Array<ShuttleRow>;
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

    private function rowOf(key as Number) as ShuttleRow? {
        for (var i = 0; i < _rows.size(); i++) {
            if (_rows[i].key == key) {
                return _rows[i];
            }
        }
        return null;
    }

    function onLayout(dc as Dc) as Void {
        dirtyAll();
    }

    // ------------------------------------------------------------ readings

    private function now() as Number {
        var c = _clock;
        return (c != null) ? c : _motion;
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

    // New readings: a change marks its row, and slides while awake. On a wake
    // woke() decides what moves, from what was last seen.
    private function take(fresh as Array<String>) as Void {
        var old = _values;
        var started = [] as Array<Number>;
        var t = now();
        for (var k = 0; k < fresh.size(); k++) {
            if (old.size() <= k || !fresh[k].equals(old[k])) {
                _rollFrom[k] = null;
                if (_awake && !_waking && _rolling && moves(k) && old.size() > k && old[k].length() == fresh[k].length()) {
                    _rollFrom[k] = old[k];
                    _rollAt[k] = t;
                    started.add(k);
                }
                dirtyKey(k);
            }
        }
        _values = fresh;
        stagger(started);
    }

    // A reading on the face that may move: not the parts of the time or the
    // readings this face doesn't show
    private function moves(k as Number) as Boolean {
        return k != Lib.Numbers.HOURS && k != Lib.Numbers.MINUTES && k != Lib.Numbers.ALTITUDE && k != Lib.Numbers.WIND;
    }

    // Units first across a band: each reading that began to move waits for
    // its band's turn and for every changed digit in the readings to its
    // right that began with it
    private function stagger(started as Array<Number>) as Void {
        var n = started.size();
        if (n == 0) {
            return;
        }
        _building = false;      // a move draws its rows each frame, by the budget
        var lag = BAND_LAG;
        var each = 0;
        for (var a = 0; a < n; a++) {
            var k = started[a];
            _moved[k] = changed(k);
        }
        for (var a = 0; a < n; a++) {
            var k = started[a];
            var ra = rowOf(k);
            if (ra == null) {
                continue;
            }
            each = ra.STAGGER;
            var lead = lag * ra.band;
            for (var b = 0; b < n; b++) {
                var rb = rowOf(started[b]);
                if (rb != null && rb.band == ra.band && rb.lx > ra.lx) {
                    lead += each * _moved[started[b]];
                }
            }
            _lead[k] = lead;
            _tail[k] = lead + each * ((_moved[k] > 0) ? _moved[k] - 1 : 0);
        }
    }

    // How many of a moving reading's digits differ
    private function changed(k as Number) as Number {
        var from = _rollFrom[k];
        if (from == null || _values.size() <= k) {
            return 0;
        }
        var a = from.toCharArray();
        var b = _values[k].toCharArray();
        var n = 0;
        for (var j = 0; j < a.size() && j < b.size(); j++) {
            if (a[j] != b[j]) {
                n++;
            }
        }
        return n;
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
        pulse();
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
        drift(values);
    }

    // The screenshots hold still; sample-move.jungle makes the sample move
    // for a watchdog run on the simulator, which shows no live data
    (:still)
    private function drift(values as Array<String>) as Void {
    }

    (:still)
    private function pulse() as Void {
    }

    // Every other minute the readings of seven minutes before, so that each
    // minute moves nearly everything, as a busy wake does
    (:moving)
    private function drift(values as Array<String>) as Void {
        if (System.getClockTime().min % 2 == 1) {
            var away = ["10/31", "14", "31", "19:22", "4:51", "45°", "52", "38", "88", "5980", "83", "1240", "12", "88%"] as Array<String>;
            for (var i = 0; i < away.size(); i++) {
                values[i] = away[i];
            }
        }
    }

    // And a heart rate that changes every four seconds, one digit
    (:moving)
    private function pulse() as Void {
        setValue(Lib.Numbers.HEART, ((System.getClockTime().sec / 4) % 2 == 0) ? "72" : "74");
    }

    // ------------------------------------------------------------ sleep and wake

    function onShow() as Void {
        _pacer.onShow();
    }

    function onEnterSleep() as Void {
        _awake = false;
        _pacer.onEnterSleep();
        _asleep = _values;
        clearEffects();
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _log.wake();
        _awake = true;
        _waking = true;
        _pacer.onExitSleep();
        _minute = -1;
        _second = -1;
        WatchUi.requestUpdate();     // the bitmap is as it was: only what changed is drawn (woke, take)
    }

    function onHide() as Void {
        _pacer.onHide();
    }

    // A move cut short by sleep left its row half drawn in the bitmap: drawn
    // again at the next lit update
    private function clearEffects() as Void {
        for (var k = 0; k < KEYS; k++) {
            if (_rollFrom[k] != null) {
                _rollFrom[k] = null;
                dirtyKey(k);
            }
        }
    }

    // What changed while asleep moves from what was last seen; nothing else
    // does, not even what changed and changed back
    private function woke() as Void {
        _waking = false;
        var seen = _asleep;
        _asleep = null;
        if (seen == null) {
            return;
        }
        clearEffects();
        if (!_rolling) {
            return;
        }
        var t = now();
        var started = [] as Array<Number>;
        for (var k = 0; k < _values.size() && k < seen.size(); k++) {
            if (!moves(k) || seen[k].equals(_values[k]) || seen[k].length() != _values[k].length()) {
                continue;
            }
            _rollFrom[k] = seen[k];
            _rollAt[k] = t;
            started.add(k);
        }
        stagger(started);
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

    // ------------------------------------------------------------ drawing

    function onUpdate(dc as Dc) as Void {
        var started = System.getTimer();
        if (_look == Lib.Look.DAILY && Lib.Look.today() != _day) {
            reloadSettings();     // a new day, and on a Monday perhaps a muted week
        }
        _motion += _asked ? 0 : _pacer.step(started);    // a frame the face asked for itself says nothing of the power mode
        _asked = false;
        refresh();
        var thin = !_awake && _burnIn;
        if (thin) {
            drawStandby(dc);
            _pacer.want(false);
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
        var rows = System.getTimer();
        drawRows(target, bitmap == null);
        _log.part = System.getTimer() - rows;
        if (bitmap != null) {
            dc.drawBitmap(0, 0, bitmap);
        }
        if (titled) {
            var font = _titleFont;
            if (font == null) {
                font = Lib.Fmt.vectorFont("RobotoCondensedBold", (dc.getWidth() * TITLE * 1.173).toNumber(), Graphics.FONT_XTINY);
                _titleFont = font;
            }
            dc.setColor(_colors.neutral, Graphics.COLOR_TRANSPARENT);
            dc.drawText(dc.getWidth() / 2, dc.getHeight() * 0.09, font,
                        Lib.Look.title(_look, Lib.Numbers.names()), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        if (_building) {
            if (_pending) {
                _asked = true;
                WatchUi.requestUpdate();     // the start's next rows, straight away; the pacer's timer waits for proof of high power, which these frames must not give
            } else {
                _building = false;
            }
        }
        var busy = _awake && animating();
        _pacer.want(busy);
        measure(started, busy);
        _log.frame(started, !animating());
    }

    // The face's bitmap, from the graphics pool, made once and held. The pool
    // purges a bitmap that nothing holds, and get() then makes a new blank
    // one rather than returning null: holding only the reference left a face
    // showing just the readings that changed since (the heart rate, then the
    // time). Null without one; the rows are then all drawn each update.
    private function canvas(dc as Dc) as Graphics.BufferedBitmap? {
        var bitmap = _bitmap;
        if (bitmap != null || !(Graphics has :createBufferedBitmap)) {
            return bitmap;
        }
        try {
            var ref = _ref;
            if (ref == null) {
                ref = Graphics.createBufferedBitmap({:width => dc.getWidth(), :height => dc.getHeight()});
                _ref = ref;
            }
            bitmap = ref.get() as Graphics.BufferedBitmap?;
        } catch (e) {
            bitmap = null;
        }
        if (bitmap != null) {
            var b = bitmap.getDc();
            b.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            b.clear();
        } else {
            _ref = null;    // no room in the pool; try again next update
        }
        _bitmap = bitmap;
        dirtyAll();
        return bitmap;
    }

    // The rows that need it, up to BUDGET digits an update (a moving digit
    // counts three: two glyphs and its clip): a wake where everything moves
    // would pass the watchdog in one go, so it takes two or three frames,
    // each row's turn coming round. A start lights the time alone, then
    // BUILD digits a frame. `all` draws them regardless.
    private function drawRows(dc as Dc, all as Boolean) as Void {
        var t = now();
        var count = _rows.size();
        var budget = _building ? BUILD : BUDGET;
        var timeOnly = _late && !all;
        _late = false;
        _pending = false;
        _drew = 0;
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
            if (timeOnly && k != TIME) {
                _pending = true;
                continue;
            }
            var cost = (_values.size() > k ? _values[k].length() : 2) + (from != null ? 2 * _moved[k] : 0);
            if (!all && !timeOnly && _drew > 0 && cost > budget) {
                _pending = true;
                _cursor = at;
                break;
            }
            budget -= cost;
            _drew++;
            r.dirty = false;
            var since = 0;
            if (from != null) {
                since = t - _rollAt[k];
                if (since < 0 || Lib.Motion.done(since - _tail[k], r.SLIDE)) {
                    _rollFrom[k] = null;
                    from = null;
                }
            }
            var text = _values.size() > k ? _values[k] : "--";
            if (k == Lib.Numbers.DATE && _titled) {
                text = "";
            }
            r.draw(dc, text, from, since - _lead[k], Lib.Numbers.scale(r.color, r.alpha));
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

    // ------------------------------------------------------------ frame cost

    (:still)
    private function measure(started as Number, busy as Boolean) as Void {
    }

    // The moving sample build logs each move: the frames drawn while
    // something moved, the time they spanned, the longest draw, the longest
    // gap between frames
    (:moving) private var _moveFrames as Number = 0;
    (:moving) private var _moveStart as Number = 0;
    (:moving) private var _moveLast as Number = 0;
    (:moving) private var _drawMax as Number = 0;
    (:moving) private var _drawSum as Number = 0;
    (:moving) private var _gapMax as Number = 0;

    (:moving)
    private function measure(started as Number, busy as Boolean) as Void {
        var draw = System.getTimer() - started;
        if (busy || _moveFrames > 0) {
            if (_moveFrames == 0) {
                _moveStart = started;
                _drawMax = 0;
                _drawSum = 0;
                _gapMax = 0;
            } else if (started - _moveLast > _gapMax) {
                _gapMax = started - _moveLast;
            }
            _moveLast = started;
            _moveFrames++;
            _drawSum += draw;
            _drawMax = (draw > _drawMax) ? draw : _drawMax;
        }
        if (!busy && _moveFrames > 0) {
            System.println("shuttle: move of " + _moveFrames + " frames in " + (started - _moveStart) + " ms, draw avg/max "
                           + (_drawSum / _moveFrames) + "/" + _drawMax + " ms, gap max " + _gapMax + " ms");
            _moveFrames = 0;
        }
    }

    // ------------------------------------------------------------ for the tests

    // Fixed readings, in the order of Lib.Numbers.Value, then battery and time
    function setValues(values as Array<String>) as Void {
        _fixed = true;
        _pacer.setStill();
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

    function rowsDrawn() as Number {
        return _drew;
    }

    function isRolling(key as Number) as Boolean {
        return _rollFrom[key] != null;
    }

    // How long a reading's move waits before its units digit goes, ms
    function leadOf(key as Number) as Number {
        return _lead[key];
    }

    function movedOf(key as Number) as Number {
        return (_rollFrom[key] != null) ? _moved[key] : 0;
    }

    function valueOf(key as Number) as String {
        return _values[key];
    }
}
