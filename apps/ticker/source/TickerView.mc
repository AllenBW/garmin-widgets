import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

// Ticker: the time as a tape of minutes in Lockup's numerals (Digits.mc)
// across the middle, the time centred, the minute before peeking dim at the
// left edge and the next not shown, since the future isn't known. A thin tape
// above carries the date, the next sunset or sunrise, the countdown to it and
// the watch's battery; one below heart rate, steps, Body Battery, the
// temperature and today's high and low. Each reading in its family's colour
// (Lib.Numbers), the centre one bright and its neighbours a third as bright.
//
// Only what changed since you last looked moves (TickerMove). A minute
// passing while awake steps the minute tape on; a wake runs it through every
// minute missed, twelve at most, and stops on now. Each thin tape turns to
// the first of its readings that changed, then that reading's changed digits
// slide sideways in their own slots, units first. At rest, and at every
// sleep, the thin tapes show the sun and the temperature; if nothing changed,
// nothing moves. Motion advances only by drawn frames (Lib.Motion.Pacer),
// whose timer runs only once the face is shown awake.
//
// The face is kept in a full-screen bitmap and only a band that moves or
// changed is redrawn, at most BUDGET characters a frame (a band over it waits
// a frame), so an update at rest is a blit.
//
// Standby (always-on): the time and the two centre readings at rest as
// outlines, shifted each minute (Lib.Aod); 3.2 % lit at most, on the 360 px
// screens (designs/preview_ticker.py --check).
class TickerView extends WatchUi.WatchFace {

    // The readings: Lib.Numbers.Value, then these
    const BATTERY = Lib.Numbers.VALUES;
    const TIME = Lib.Numbers.VALUES + 1;
    const KEYS = Lib.Numbers.VALUES + 2;

    // The bands, top to bottom, and their rows as fractions of the width (the sketch's)
    const TOP_BAND = 0;
    const TIME_BAND = 1;
    const BOTTOM_BAND = 2;
    const BANDS = 3;
    const Y0 = [0.17, 0.35, 0.74] as Array<Float>;
    const Y1 = [0.26, 0.65, 0.83] as Array<Float>;

    const PITCH = 0.291;       // between readings on a thin tape, of the width (132 px on 454)
    const SPACE = 350;         // thousandths of a block between minutes on the minute tape
    const DIM = 0.34;          // a thin tape's neighbours, of full brightness
    const REACH = 1.75;        // a thin tape's readings drawn this far from its centre, in readings
    const FADE = 0.8;          // the brightness a minute loses per minute from the centre
    const FAINT = 0.16;        // and the least it keeps
    const TIME_REACH = 2.0;    // minutes drawn this far from the centre
    const MOST_MINUTES = 12;   // a wake runs through this many minutes at most
    const PERIOD = 50;         // ms between frames asked for
    const MOST_FRAMES = 4;     // frames' worth one drawn frame may move the tapes: a stall skips
    const BUDGET = 48;         // characters a frame: about Lockup's 40, its digits upright rectangles only
    const STANDBY_STEP = 0.006; // Lib.Aod's step, of the width
    const TITLE = 0.050;       // the look's name, for a moment after a hold
    const TITLE_Y = 0.09;

    // The thin tapes' readings in order, [top, bottom], and where each rests
    private var _tapes as Array<Array<Number>>;
    private var _rest as Array<Number> = [1, 3] as Array<Number>;   // the sun, the temperature
    private var _pos as Array<Number> = [1, 3] as Array<Number>;    // each one's centre reading now

    private var _values as Array<String> = [] as Array<String>;
    private var _shown as Array<String>? = null;   // the readings last shown awake
    private var _shownMinute as Number = 0;        // and the minute
    private var _move as TickerMove? = null;
    private var _pacer as Lib.Motion.Pacer;
    private var _type as TickerType;

    private var _colors as Lib.Numbers.Colors = Lib.Numbers.colors(Lib.Look.YOURS);
    private var _look as Number = Lib.Look.YOURS;
    private var _day as Number = 0;           // the daily look's day
    private var _motion as Boolean = true;
    private var _minute as Number = -1;
    private var _second as Number = -1;
    private var _burnIn as Boolean = false;
    private var _wasAwake as Boolean = true;
    private var _fixed as Boolean = false;     // the tests' readings
    private var _clock as Number? = null;      // the tests' clock

    private var _ref as Graphics.BufferedBitmapReference? = null;
    private var _bitmap as Graphics.BufferedBitmap? = null;
    private var _dirty as Array<Boolean> = [true, true, true] as Array<Boolean>;
    private var _cost as Array<Number> = [16, 16, 16] as Array<Number>;   // characters each band drew last
    private var _pending as Boolean = false;   // a band left for the next frame
    private var _cursor as Number = TIME_BAND; // a start draws the time first
    private var _late as Boolean = true;       // a start's first frame: the time alone
    private var _building as Boolean = true;   // a start: the rest a band a frame, a frame straight after another
    private var _asked as Boolean = false;     // this frame is one the build asked for, not the system's
    private var _titleFont as Graphics.FontType? = null;   // made on the look's name's first frame, kept
    private var _frameChars as Number = 0;
    private var _frameBands as Array<Number> = [] as Array<Number>;   // the bands the last frame drew
    private var _log as Lib.Timing.Log;         // how quickly it lights

    function initialize() {
        WatchFace.initialize();
        _log = new Lib.Timing.Log("Ticker");
        _burnIn = Lib.Aod.required();
        _tapes = [
            [Lib.Numbers.DATE, Lib.Numbers.SUN_TIME, Lib.Numbers.COUNTDOWN, BATTERY] as Array<Number>,
            [Lib.Numbers.HEART, Lib.Numbers.STEPS, Lib.Numbers.BODY, Lib.Numbers.TEMP, Lib.Numbers.HIGH, Lib.Numbers.LOW] as Array<Number>
        ] as Array<Array<Number>>;
        _pacer = new Lib.Motion.Pacer(PERIOD, MOST_FRAMES);
        _type = new TickerType();
        reloadSettings();
        holdStandby();
    }

    function reloadSettings() as Void {
        _look = Lib.Look.mode();
        _colors = Lib.Numbers.colors(_look);
        _day = Lib.Look.today();
        _motion = setting("Motion", true);
        dirtyAll();
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

    // A reading's family colour (Lib.Numbers)
    private function colorOf(key as Number) as Number {
        var c = _colors;
        if (key == Lib.Numbers.SUN_TIME || key == Lib.Numbers.COUNTDOWN) {
            return c.sun;
        }
        if (key == Lib.Numbers.HEART || key == Lib.Numbers.STEPS || key == Lib.Numbers.BODY) {
            return c.body;
        }
        if (key == Lib.Numbers.TEMP || key == Lib.Numbers.HIGH || key == Lib.Numbers.LOW) {
            return c.weather;
        }
        return c.neutral;
    }

    // The complication a hold on a reading opens
    private function typeOf(key as Number) as Complications.Type {
        if (key == Lib.Numbers.DATE) {
            return Complications.COMPLICATION_TYPE_CALENDAR_EVENTS;
        }
        if (key == Lib.Numbers.SUN_TIME || key == Lib.Numbers.COUNTDOWN) {
            return Complications.COMPLICATION_TYPE_SUNRISE;
        }
        if (key == BATTERY) {
            return Complications.COMPLICATION_TYPE_BATTERY;
        }
        if (key == Lib.Numbers.HEART) {
            return Complications.COMPLICATION_TYPE_HEART_RATE;
        }
        if (key == Lib.Numbers.STEPS) {
            return Complications.COMPLICATION_TYPE_STEPS;
        }
        if (key == Lib.Numbers.BODY) {
            return Complications.COMPLICATION_TYPE_BODY_BATTERY;
        }
        return Complications.COMPLICATION_TYPE_CURRENT_WEATHER;
    }

    private function dirtyAll() as Void {
        for (var b = 0; b < BANDS; b++) {
            _dirty[b] = true;
        }
    }

    function onLayout(dc as Dc) as Void {
        dirtyAll();
    }

    // ------------------------------------------------------------ press and hold

    // Whether (x, y) is on the time, where a hold steps the look
    function onTime(x as Number, y as Number) as Boolean {
        var w = System.getDeviceSettings().screenWidth;
        return y >= Y0[TIME_BAND] * w && y <= Y1[TIME_BAND] * w;
    }

    // The complication a hold at (x, y) opens: a thin tape's centre reading's, else null
    function targetAt(x as Number, y as Number) as Complications.Type? {
        var w = System.getDeviceSettings().screenWidth;
        if ((x - w / 2.0).abs() > PITCH * w / 2.0) {
            return null;
        }
        for (var i = 0; i < 2; i++) {
            var b = i * 2;
            if (y >= (Y0[b] - 0.03) * w && y <= (Y1[b] + 0.03) * w) {
                return typeOf(_tapes[i][_pos[i]]);
            }
        }
        return null;
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
        var key = minuteKey();
        if (key != _minute || _values.size() == 0) {
            _minute = key;
            var fresh = Lib.Numbers.read();
            fresh.add(battery());
            sample(fresh);
            fresh.add(fresh[Lib.Numbers.HOURS] + ":" + fresh[Lib.Numbers.MINUTES]);
            _values = fresh;
        }
        if (_pacer.awake) {
            var sec = System.getClockTime().sec;
            if (sec != _second) {
                _second = sec;
                live();
            }
        }
    }

    // A new heart rate between minutes, while awake
    (:live)
    private function live() as Void {
        var heart = Lib.Daily.heartRate();
        if (_values.size() == KEYS && !heart.equals(_values[Lib.Numbers.HEART])) {
            var fresh = _values.slice(null, null);
            fresh[Lib.Numbers.HEART] = heart;
            _values = fresh;
        }
    }

    (:sample)
    private function live() as Void {
    }

    // The watch's charge, as "87%"
    private function battery() as String {
        return System.getSystemStats().battery.format("%d") + "%";
    }

    // The minute the readings were read for
    (:live)
    private function minuteKey() as Number {
        return System.getClockTime().min;
    }

    // The sample's: minutes since it started, so the time moves on a minute
    // a minute from 14:38 however the real clock stands
    (:sample) private var _sampleStart as Number = -1;

    (:sample)
    private function minuteKey() as Number {
        var t = System.getTimer();
        if (_sampleStart < 0) {
            _sampleStart = t;
        }
        return (t - _sampleStart) / 60000;
    }

    (:live)
    private function sample(values as Array<String>) as Void {
    }

    // The screenshots' readings (sample.jungle), Lockup's, the time and the
    // countdown moving on with minuteKey
    (:sample)
    private function sample(values as Array<String>) as Void {
        var fixed = ["10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "72", "6214", "82", "1240", "12", "87%"] as Array<String>;
        for (var i = 0; i < fixed.size(); i++) {
            values[i] = fixed[i];
        }
        var m = 14 * 60 + 38 + _minute;
        values[Lib.Numbers.HOURS] = ((m / 60) % 24).format("%02d");
        values[Lib.Numbers.MINUTES] = (m % 60).format("%02d");
        values[Lib.Numbers.COUNTDOWN] = Lib.Numbers.countdown(m * 60, (19 * 60 + 22) * 60);
    }

    // What the face last showed awake when it starts: nothing, so it shows now
    (:live)
    private function lastSeen(values as Array<String>) as Array<String> {
        return values;
    }

    (:sample, :rested)
    private function lastSeen(values as Array<String>) as Array<String> {
        return values;
    }

    // sample-wake.jungle: last looked at seven minutes ago (the sketch's
    // "seven minutes away"), so the face runs the wake on load
    (:sample, :wake)
    private function lastSeen(values as Array<String>) as Array<String> {
        var seen = values.slice(null, null);
        var m = minuteOf(values) - 7;
        seen[Lib.Numbers.HOURS] = (m / 60).format("%02d");
        seen[Lib.Numbers.MINUTES] = (m % 60).format("%02d");
        seen[TIME] = seen[Lib.Numbers.HOURS] + ":" + seen[Lib.Numbers.MINUTES];
        seen[Lib.Numbers.COUNTDOWN] = "4:51";
        seen[BATTERY] = "88%";
        seen[Lib.Numbers.HEART] = "88";
        seen[Lib.Numbers.STEPS] = "5980";
        seen[Lib.Numbers.BODY] = "83";
        seen[Lib.Numbers.TEMP] = "45°";
        return seen;
    }

    (:live)
    private function holdStandby() as Void {
    }

    (:sample, :lit)
    private function holdStandby() as Void {
    }

    // sample-standby.jungle: low power mode held, which the simulator cannot
    // be put into from a script
    (:sample, :standby)
    private function holdStandby() as Void {
        _burnIn = true;
        _pacer.onEnterSleep();
    }

    // The minute of the day the readings say
    private function minuteOf(values as Array<String>) as Number {
        if (values.size() <= Lib.Numbers.MINUTES) {
            return 0;
        }
        var h = values[Lib.Numbers.HOURS].toNumber();
        var m = values[Lib.Numbers.MINUTES].toNumber();
        return ((h != null) ? h : 0) * 60 + ((m != null) ? m : 0);
    }

    // "14:38" for a minute of the day, any day
    private function clockText(m as Number) as String {
        m = ((m % 1440) + 1440) % 1440;
        return (m / 60).format("%02d") + ":" + (m % 60).format("%02d");
    }

    // ------------------------------------------------------------ what moves

    // Compares what is with what was last shown awake: the same, nothing to
    // do; changed, a move from the one to the other once the face is shown
    // awake (until then the old stays), or straight to it without motion
    private function compare() as Void {
        if (_values.size() < KEYS) {
            return;
        }
        var shown = _shown;
        if (shown == null) {
            shown = lastSeen(_values);
            _shown = shown;
            _shownMinute = minuteOf(shown);
            dirtyAll();
        }
        var minute = minuteOf(_values);
        var steps = ((minute - _shownMinute) % 1440 + 1440) % 1440;
        if (steps == 0 && !differs(shown, _values)) {
            return;
        }
        if (_motion && _pacer.awake) {
            if (_pacer.proven()) {
                start(shown, minute, steps);
            }
            return;
        }
        for (var i = 0; i < 2; i++) {
            var first = firstChanged(i, shown, _values);
            if (first >= 0) {
                _pos[i] = first;
            }
        }
        _shown = _values;
        _shownMinute = minute;
        dirtyAll();
    }

    private function differs(a as Array<String>, b as Array<String>) as Boolean {
        for (var i = 0; i < 2; i++) {
            if (firstChanged(i, a, b) >= 0) {
                return true;
            }
        }
        return false;
    }

    // The first of thin tape i's readings that differs, or -1
    private function firstChanged(i as Number, a as Array<String>, b as Array<String>) as Number {
        var keys = _tapes[i];
        for (var k = 0; k < keys.size(); k++) {
            if (!a[keys[k]].equals(b[keys[k]])) {
                return k;
            }
        }
        return -1;
    }

    private function start(shown as Array<String>, minute as Number, steps as Number) as Void {
        if (steps > MOST_MINUTES) {
            steps = MOST_MINUTES;   // a long gap: the run starts twelve back
        }
        var tape0 = [_pos[0], _pos[1]] as Array<Number>;
        var tape1 = [_pos[0], _pos[1]] as Array<Number>;
        var slides = [0, 0] as Array<Number>;
        for (var i = 0; i < 2; i++) {
            var keys = _tapes[i];
            var count = keys.size();
            var first = firstChanged(i, shown, _values);
            if (first >= 0) {
                var delta = first - _pos[i];       // round the short way
                if (delta > count / 2) {
                    delta -= count;
                } else if (delta < -count / 2) {
                    delta += count;
                }
                tape1[i] = _pos[i] + delta;
            }
            for (var k = 0; k < count; k++) {
                var a = shown[keys[k]];
                var b = _values[keys[k]];
                if (a.length() == b.length() && !a.equals(b)) {
                    var ac = a.toCharArray();
                    var bc = b.toCharArray();
                    var n = 0;
                    for (var j = 0; j < ac.size(); j++) {
                        if (ac[j] != bc[j]) {
                            n++;
                        }
                    }
                    slides[i] = (n > slides[i]) ? n : slides[i];
                }
            }
        }
        _move = new TickerMove(shown, _values, minute - steps, steps, tape0, tape1, slides);
        _building = false;      // a move draws its bands each frame, by the budget
        _shown = _values;
        _shownMinute = minute;
    }

    // A move over: the tapes where it left them, any band not yet drawn settled drawn
    private function land(move as TickerMove) as Void {
        for (var i = 0; i < 2; i++) {
            var count = _tapes[i].size();
            _pos[i] = ((move.tape1[i] % count) + count) % count;
        }
        for (var b = 0; b < BANDS; b++) {
            if (move.live[b]) {
                _dirty[b] = true;
            }
        }
        _move = null;
    }

    // Asleep: a move under way lands and the thin tapes go back to rest,
    // so a wake turns them from there to whatever changed
    private function asleep() as Void {
        var move = _move;
        if (move != null) {
            land(move);
        }
        for (var i = 0; i < 2; i++) {
            if (_pos[i] != _rest[i]) {
                _pos[i] = _rest[i];
                _dirty[(i == 0) ? TOP_BAND : BOTTOM_BAND] = true;   // only a tape that turns back: the bitmap keeps the rest for the wake
            }
        }
    }

    // ------------------------------------------------------------ sleep and wake

    function onShow() as Void {
        _pacer.onShow();
        _minute = -1;
        WatchUi.requestUpdate();
    }

    function onHide() as Void {
        _pacer.onHide();
    }

    function onExitSleep() as Void {
        _log.wake();
        _pacer.onExitSleep();
        _minute = -1;
        _second = -1;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        _pacer.onEnterSleep();
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------ drawing

    function onUpdate(dc as Dc) as Void {
        var started = System.getTimer();
        if (_look == Lib.Look.DAILY && Lib.Look.today() != _day) {
            reloadSettings();     // a new day, and on a Monday perhaps a muted week
        }
        var gap = _asked ? 0 : _pacer.step(now());    // a frame the face asked for itself says nothing of the power mode
        _asked = false;
        refresh();
        var awake = _pacer.awake;
        if (awake != _wasAwake) {
            _wasAwake = awake;
            if (!awake) {
                asleep();
            }
        }
        if (!awake && _burnIn) {
            drawStandby(dc);
            _pacer.want(false);
            return;
        }
        var move = _move;
        if (move != null) {
            move.t += gap;
            if (move.done()) {
                land(move);
            }
        }
        if (_move == null) {
            compare();
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
        var bands = System.getTimer();
        drawBands(target, bitmap == null);
        _log.part = System.getTimer() - bands;
        if (bitmap != null) {
            dc.drawBitmap(0, 0, bitmap);
        }
        if (Lib.Look.shown()) {
            if (dc has :setAntiAlias) {
                dc.setAntiAlias(true);
            }
            var font = _titleFont;
            if (font == null) {
                font = Lib.Fmt.vectorFont("RobotoCondensedBold", (dc.getWidth() * TITLE * 1.173).toNumber(), Graphics.FONT_XTINY);
                _titleFont = font;
            }
            dc.setColor(_colors.neutral, Graphics.COLOR_TRANSPARENT);
            dc.drawText(dc.getWidth() / 2, dc.getHeight() * TITLE_Y, font,
                        Lib.Look.title(_look, Lib.Numbers.names()), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        if (_building) {
            if (_pending) {
                _asked = true;
                WatchUi.requestUpdate();     // the start's next band, straight away; the pacer's timer waits for proof of high power, which these frames must not give
            } else {
                _building = false;
            }
        }
        _pacer.want(_move != null || _pending);
        measure(started);
        _log.frame(started, _move == null && !_pending);
    }

    // The face's bitmap, from the graphics pool, made once and held. The pool
    // purges a bitmap that nothing holds, and get() then makes a new blank
    // one rather than returning null: holding only the reference left a face
    // showing just the readings that changed since (the heart rate, then the
    // time). Null without one; the bands are then all drawn each update.
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

    // The bands that changed or move, up to BUDGET characters a frame: a band
    // over it waits for the next frame, each band's turn coming round. A
    // start lights the time alone, then a band a frame. `all` draws them
    // regardless.
    private function drawBands(dc as Dc, all as Boolean) as Void {
        var budget = _building ? 0 : BUDGET;    // a start: a band a frame
        var drawn = 0;
        var timeOnly = _late && !all;
        _late = false;
        _pending = false;
        _frameBands = [] as Array<Number>;
        for (var n = 0; n < BANDS; n++) {
            var b = (_cursor + n) % BANDS;
            var move = _move;
            if (!_dirty[b] && !(move != null && move.live[b])) {
                continue;
            }
            if (timeOnly && b != TIME_BAND) {
                _pending = true;
                continue;
            }
            if (!all && drawn > 0 && _cost[b] > budget) {
                _pending = true;
                _cursor = b;
                break;
            }
            _type.count = 0;
            drawBand(dc, b);
            _cost[b] = _type.count;
            budget -= _type.count;
            drawn += _type.count;
            _dirty[b] = false;
            _frameBands.add(b);
            if (move != null && move.t >= move.ends[b]) {
                move.live[b] = false;   // drawn settled
            }
        }
        _frameChars = drawn;
    }

    private function drawBand(dc as Dc, b as Number) as Void {
        var w = dc.getWidth();
        var top = (Y0[b] * w).toNumber() - 1;
        var tall = (Y1[b] * w + 0.999).toNumber() + 1 - top;
        dc.setClip(0, top, w, tall);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(0, top, w, tall);
        if (b == TIME_BAND) {
            drawTime(dc, w, top, tall);
        } else {
            drawThin(dc, (b == TOP_BAND) ? 0 : 1, w, top, tall);
        }
        dc.clearClip();
    }

    // The minute tape: the minutes up to the one it shows or runs toward,
    // fading from the centre; none after it
    private function drawTime(dc as Dc, w as Number, clipY as Number, clipH as Number) as Void {
        var y0 = Y0[TIME_BAND];
        _type.setLine(y0 * w, (Y1[TIME_BAND] - y0) * w, 0.0, w.toFloat(), clipY, clipH, w);
        var move = _move;
        var last = (move != null) ? move.minuteFrom + move.steps : _shownMinute;
        var pos = (move != null) ? move.minutePos() : last.toFloat();
        var pitch = (_type.width(clockText(last)) + SPACE) * _type.scale();
        for (var m = last; m >= last - MOST_MINUTES - 3; m--) {
            var d = m - pos;
            if (d > TIME_REACH) {
                continue;
            }
            if (d < -TIME_REACH) {
                break;
            }
            var a = 1.0 - d.abs() * FADE;
            _type.line(dc, clockText(m), null, w / 2.0 + d * pitch, Lib.Numbers.scale(_colors.neutral, (a < FAINT) ? FAINT : a), null, 0);
        }
    }

    // Thin tape i: its readings round a loop, the centre one bright; moving,
    // the readings last seen with the changed digits sliding to now's
    private function drawThin(dc as Dc, i as Number, w as Number, clipY as Number, clipH as Number) as Void {
        var b = (i == 0) ? TOP_BAND : BOTTOM_BAND;
        var y0 = Y0[b];
        var y1 = Y1[b];
        var inner = ((i == 0) ? y1 : y0) - 0.5;          // the band's edge nearest the middle, where the circle is widest
        var half = Math.sqrt(0.25 - inner * inner).toFloat();
        _type.setLine(y0 * w, (y1 - y0) * w, (0.5 - half) * w, (0.5 + half) * w, clipY, clipH, w);
        var keys = _tapes[i];
        var count = keys.size();
        var move = _move;
        var pos = (move != null) ? move.tapePos(i) : _pos[i].toFloat();
        var from = (move != null) ? move.from : null;
        var shown = _shown;
        var texts = _values;
        if (move != null) {
            texts = move.to;
        } else if (shown != null) {
            texts = shown;
        }
        var pitch = PITCH * w;
        var base = pos.toNumber();
        for (var j = base - 3; j <= base + 3; j++) {
            var d = j - pos;
            if (d < -REACH || d > REACH) {
                continue;
            }
            var k = keys[((j % count) + count) % count];
            var near = 1.0 - d.abs();
            var shade = DIM + (1.0 - DIM) * ((near > 0.0) ? near : 0.0);
            _type.line(dc, texts[k], (from != null) ? from[k] : null, w / 2.0 + d * pitch, Lib.Numbers.scale(colorOf(k), shade), move, i);
        }
    }

    // Standby: the time and the thin tapes' resting readings as outlines a
    // pixel wide, shifted each minute; drawn from the clock's readings, not
    // the tapes' (which keep what was last seen for the wake)
    private function drawStandby(dc as Dc) as Void {
        var w = dc.getWidth();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(false);    // hard outlines: no faint pixels to count against the 10 %
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setPenWidth(1);
        if (_values.size() < KEYS) {
            return;
        }
        var off = Lib.Aod.offset(System.getClockTime().min, (w * STANDBY_STEP).toNumber());
        _type.setLine(Y0[TIME_BAND] * w, (Y1[TIME_BAND] - Y0[TIME_BAND]) * w, 0.0, w.toFloat(), 0, w, w);
        _type.outline(dc, _values[TIME], w / 2.0, _colors.neutral, off[0], off[1]);
        for (var i = 0; i < 2; i++) {
            var b = (i == 0) ? TOP_BAND : BOTTOM_BAND;
            _type.setLine(Y0[b] * w, (Y1[b] - Y0[b]) * w, 0.0, w.toFloat(), 0, w, w);
            var k = _tapes[i][_rest[i]];
            _type.outline(dc, _values[k], w / 2.0, colorOf(k), off[0], off[1]);
        }
    }

    // ------------------------------------------------------------ the log

    // Each move's frames, the time they took, the longest draw and the most
    // characters a frame drew (the watch writes it to GARMIN/Apps/LOGS/TICKER.TXT)
    private var _moveFrames as Number = 0;
    private var _moveStart as Number = 0;
    private var _drawMax as Number = 0;
    private var _charsMax as Number = 0;

    private function measure(started as Number) as Void {
        if (_move != null) {
            var draw = System.getTimer() - started;
            if (_moveFrames == 0) {
                _moveStart = started;
                _drawMax = 0;
                _charsMax = 0;
            }
            _moveFrames++;
            _drawMax = (draw > _drawMax) ? draw : _drawMax;
            _charsMax = (_frameChars > _charsMax) ? _frameChars : _charsMax;
        } else if (_moveFrames > 0) {
            System.println("ticker: move " + _moveFrames + " frames in " + (started - _moveStart) + " ms, draw max " + _drawMax
                           + " ms, " + _charsMax + " characters a frame at most");
            _moveFrames = 0;
        }
    }

    // ------------------------------------------------------------ for the tests

    // Fixed readings, in the order of Lib.Numbers.Value, then battery and time
    function setValues(values as Array<String>) as Void {
        _fixed = true;
        _pacer.setStill();
        _values = values.slice(null, null);
    }

    function setClock(t as Number) as Void {
        _clock = t;
    }

    function setMotion(motion as Boolean) as Void {
        _motion = motion;
    }

    function setAwake(awake as Boolean) as Void {
        _burnIn = true;
        _pacer.setStill();
        if (awake) {
            onExitSleep();
        } else {
            onEnterSleep();
        }
    }

    function isAnimating() as Boolean {
        return _move != null || _pending;
    }

    // Minutes the minute tape runs through in the move under way
    function minuteSteps() as Number {
        var move = _move;
        return (move != null) ? move.steps : 0;
    }

    // The reading at thin tape i's centre, or that it turns to
    function centre(i as Number) as Number {
        var move = _move;
        var count = _tapes[i].size();
        var p = (move != null) ? move.tape1[i] : _pos[i];
        return _tapes[i][((p % count) + count) % count];
    }

    // Whether a reading's digits slide in the move under way
    function slides(key as Number) as Boolean {
        var move = _move;
        if (move == null || key == TIME) {
            return false;
        }
        var a = move.from[key];
        var b = move.to[key];
        return a.length() == b.length() && !a.equals(b);
    }

    function turns(i as Number) as Boolean {
        var move = _move;
        return move != null && move.tape0[i] != move.tape1[i];
    }

    function charsLastFrame() as Number {
        return _frameChars;
    }

    // Whether the last frame drew the time band and nothing else
    function timeOnly() as Boolean {
        return _frameBands.size() == 1 && _frameBands[0] == TIME_BAND;
    }
}
