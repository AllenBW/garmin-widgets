import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

// Orb: Lockup's rows printed round a globe (designs/README.md, design #27).
// Five bands, top to bottom: the date; the next sunset or sunrise, the
// countdown to it and the watch's battery; the time; heart rate, steps and
// Body Battery; the high, the temperature and the low. Each band's text
// spans +-1.25 rad about the globe's vertical axis (OrbBand), crowding toward
// the limb and dimming there; the families coloured as in Lib.Numbers.
//
// Only what changed since you last looked moves. A digit that changed turns
// like a small globe of its own, units first; when at least half of a band
// changed, the whole band turns half a revolution instead, the old readings
// going round the back, each band at its own pace. Nothing changed, nothing
// moves; a wake moves what changed while asleep; a setting turns it off.
// The motion is Lib.Motion's: its ease, and a clock moved only by drawn
// frames (Pacer), whose timer runs only once the face is shown awake.
//
// The face is kept in a full-screen bitmap: a band at rest is drawn once, a
// moving band each frame, a drum only in its slot, at most BUDGET polygons
// an update (the watchdog).
//
// Standby (always-on): the date, the sun, the time and the temperature as
// outlines on the globe, which turns a little each minute (+-0.07 rad) as
// its shift, with Lib.Aod's vertical one; under 6 % lit (designs/preview_orb.py).
class OrbView extends WatchUi.WatchFace {

    // The readings: Lib.Numbers.Value, then these
    const BATTERY = Lib.Numbers.VALUES;
    const TIME = Lib.Numbers.VALUES + 1;
    const KEYS = Lib.Numbers.VALUES + 2;
    const TIME_BAND = 2;         // the bands' order is build()'s

    // The motion, as the approved sketch has it
    const TURNS = true;          // a band turns whole when most of it changed (measured)
    const DRUM = 500;            // ms a digit's turn takes
    const DRUM_STEP = 70;        // ms between a band's changed digits, units first
    const DRUM_BAND = 50;        // ms between bands' drums
    const TURN = 850;            // ms the middle band's turn takes
    const TURN_GROW = 140;       // and more for each band out from the middle
    const TURN_STEP = 90;        // ms between bands' turns
    const PERIOD = 50;           // ms between frames asked for
    const MOST = 4;              // periods one drawn frame may move the motion: a stall skips
    const BUDGET = 100;          // polygons an update, roughly (cost): passes at four times, trips at five, measured
    const TITLE = 0.050;         // the look's name, for a moment
    const STANDBY_TURN = 0.035;  // the globe's turn in standby per step of the minute's five

    private var _values as Array<String> = [] as Array<String>;
    private var _asleep as Array<String>? = null;
    private var _bands as Array<OrbBand> = [] as Array<OrbBand>;
    private var _standby as Array<OrbBand> = [] as Array<OrbBand>;

    private var _colors as Lib.Numbers.Colors = Lib.Numbers.colors(Lib.Look.YOURS);
    private var _look as Number = Lib.Look.YOURS;
    private var _day as Number = 0;           // the daily look's day
    private var _motion as Boolean = true;
    private var _minute as Number = -1;
    private var _second as Number = -1;
    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;
    private var _titled as Boolean = false;
    private var _waking as Boolean = false;
    private var _pending as Boolean = false;    // bands left for the next frame
    private var _cursor as Number = TIME_BAND;  // a start draws the time first
    private var _late as Boolean = true;        // a start's first frame: the time alone
    private var _building as Boolean = true;    // a start: the rest a band a frame, a frame straight after another
    private var _asked as Boolean = false;      // this frame is one the build asked for, not the system's
    private var _drewBands as Array<Number> = [] as Array<Number>;   // the bands the last update drew
    private var _titleFont as Graphics.FontType? = null;   // made on the look's name's first frame, kept
    private var _fixed as Boolean = false;      // the tests' readings
    private var _clock as Number? = null;       // the tests' clock
    private var _t as Number = 0;               // the motion's clock: ms of drawn frames

    private var _pacer as Lib.Motion.Pacer;
    private var _ref as Graphics.BufferedBitmapReference? = null;
    private var _bitmap as Graphics.BufferedBitmap? = null;
    private var _log as Lib.Timing.Log;         // how quickly it lights

    function initialize() {
        WatchFace.initialize();
        _log = new Lib.Timing.Log("Orb");
        _burnIn = Lib.Aod.required();
        _pacer = new Lib.Motion.Pacer(PERIOD, MOST);
        reloadSettings();
    }

    function reloadSettings() as Void {
        _look = Lib.Look.mode();
        _colors = Lib.Numbers.colors(_look);
        _day = Lib.Look.today();
        _motion = setting("Motion", true);
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

    // ------------------------------------------------------------ the bands

    // The same bands as designs/preview_orb.py
    private function build() as Void {
        var c = _colors;
        var s = Lib.Numbers.scale(c.sun, c.second);
        var cal = Complications.COMPLICATION_TYPE_CALENDAR_EVENTS;
        var sun = Complications.COMPLICATION_TYPE_SUNRISE;
        var wx = Complications.COMPLICATION_TYPE_CURRENT_WEATHER;
        _bands = [
            new OrbBand([Lib.Numbers.DATE] as Array<Number>, [true] as Array<Boolean>, [c.neutral] as Array<Number>,
                        ["11/11"] as Array<String>, 0.052, 0.128, [cal] as Array<Complications.Type?>),
            new OrbBand([Lib.Numbers.SUN_TIME, Lib.Numbers.COUNTDOWN, BATTERY] as Array<Number>, [true, false, false] as Array<Boolean>,
                        [c.sun, s, Lib.Numbers.scale(c.neutral, c.third)] as Array<Number>,
                        ["11:11", "1:11", "11%"] as Array<String>, 0.150, 0.290,
                        [sun, sun, Complications.COMPLICATION_TYPE_BATTERY] as Array<Complications.Type?>),
            new OrbBand([TIME] as Array<Number>, [true] as Array<Boolean>, [c.neutral] as Array<Number>,
                        ["11:11"] as Array<String>, 0.300, 0.575, [null] as Array<Complications.Type?>),
            new OrbBand([Lib.Numbers.HEART, Lib.Numbers.STEPS, Lib.Numbers.BODY] as Array<Number>, [true, false, false] as Array<Boolean>,
                        [c.body, Lib.Numbers.scale(c.body, c.second), Lib.Numbers.scale(c.body, c.third)] as Array<Number>,
                        ["11", "1111", "11"] as Array<String>, 0.587, 0.735,
                        [Complications.COMPLICATION_TYPE_HEART_RATE, Complications.COMPLICATION_TYPE_STEPS,
                         Complications.COMPLICATION_TYPE_BODY_BATTERY] as Array<Complications.Type?>),
            new OrbBand([Lib.Numbers.HIGH, Lib.Numbers.TEMP, Lib.Numbers.LOW] as Array<Number>, [false, true, false] as Array<Boolean>,
                        [Lib.Numbers.scale(c.weather, c.second), c.weather, Lib.Numbers.scale(c.weather, c.third)] as Array<Number>,
                        ["11", "11°", "11"] as Array<String>, 0.747, 0.945, [wx, wx, wx] as Array<Complications.Type?>)
        ] as Array<OrbBand>;
        _standby = [
            new OrbBand([Lib.Numbers.DATE] as Array<Number>, [true] as Array<Boolean>, [c.neutral] as Array<Number>,
                        ["11/11"] as Array<String>, 0.052, 0.128, [null] as Array<Complications.Type?>),
            new OrbBand([Lib.Numbers.SUN_TIME] as Array<Number>, [true] as Array<Boolean>, [c.sun] as Array<Number>,
                        ["11:11"] as Array<String>, 0.150, 0.290, [null] as Array<Complications.Type?>),
            new OrbBand([TIME] as Array<Number>, [true] as Array<Boolean>, [c.neutral] as Array<Number>,
                        ["11:11"] as Array<String>, 0.300, 0.575, [null] as Array<Complications.Type?>),
            new OrbBand([Lib.Numbers.TEMP] as Array<Number>, [true] as Array<Boolean>, [c.weather] as Array<Number>,
                        ["11°"] as Array<String>, 0.747, 0.945, [null] as Array<Complications.Type?>)
        ] as Array<OrbBand>;
        if (_values.size() > 0) {
            for (var i = 0; i < _bands.size(); i++) {
                _bands[i].set(texts(_values, _bands[i]));
            }
        }
    }

    // A band's readings in `values`; the date gives way to the look's name
    private function texts(values as Array<String>, band as OrbBand) as Array<String> {
        var keys = band.keys;
        var out = new [keys.size()] as Array<String>;
        for (var i = 0; i < keys.size(); i++) {
            var k = keys[i];
            out[i] = (k == Lib.Numbers.DATE && _titled) ? "" : ((values.size() > k) ? values[k] : "--");
        }
        return out;
    }

    private function same(a as Array<String>, b as Array<String>) as Boolean {
        if (a.size() != b.size()) {
            return false;
        }
        for (var i = 0; i < a.size(); i++) {
            if (!a[i].equals(b[i])) {
                return false;
            }
        }
        return true;
    }

    // The complication a press and hold at (x, y) opens, or null on the time
    function targetAt(x as Number, y as Number) as Complications.Type? {
        var w = System.getDeviceSettings().screenWidth;
        for (var i = 0; i < _bands.size(); i++) {
            var s = _bands[i].readingAt(x, y, w);
            if (s >= 0) {
                return _bands[i].types[s];
            }
        }
        return null;
    }

    function onLayout(dc as Dc) as Void {
        for (var i = 0; i < _bands.size(); i++) {
            _bands[i].invalidate();
        }
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

    // New readings: a band that changed moves while awake, else just changes
    private function take(fresh as Array<String>) as Void {
        var first = _values.size() == 0;
        _values = fresh;
        for (var i = 0; i < _bands.size(); i++) {
            var b = _bands[i];
            var now = texts(fresh, b);
            if (first) {
                b.set(now);
                continue;
            }
            var was = b.texts();
            if (same(was, now)) {
                continue;
            }
            if (_awake && _motion) {
                plan(i, was, now);
            } else {
                b.set(now);
            }
        }
    }

    private function plan(i as Number, was as Array<String>, now as Array<String>) as Void {
        _building = false;      // a motion draws its bands each frame, by the budget
        var out = (i > 2) ? i - 2 : 2 - i;
        _bands[i].plan(was, now, TURNS, _t, i * TURN_STEP, TURN + TURN_GROW * out, i * DRUM_BAND, DRUM_STEP);
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

    function onShow() as Void {
        _pacer.onShow();
    }

    function onHide() as Void {
        _pacer.onHide();
    }

    function onEnterSleep() as Void {
        _awake = false;
        _pacer.onEnterSleep();
        _asleep = _values;
        _pending = false;     // what is left stays dirty for the next awake update
        settle();
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _log.wake();
        _awake = true;
        _waking = true;
        _minute = -1;
        _second = -1;
        _pacer.onExitSleep();
        WatchUi.requestUpdate();
    }

    // Asleep nothing moves: every band to its readings at rest
    private function settle() as Void {
        for (var i = 0; i < _bands.size(); i++) {
            var b = _bands[i];
            if (b.mode != OrbMoves.NONE) {
                b.set(b.texts());
            }
        }
    }

    // What changed while asleep moves from what was last seen
    private function woke() as Void {
        _waking = false;
        var seen = _asleep;
        _asleep = null;
        if (seen == null || !_motion) {
            return;
        }
        for (var i = 0; i < _bands.size(); i++) {
            var was = texts(seen, _bands[i]);
            var now = _bands[i].texts();
            if (!same(was, now)) {
                plan(i, was, now);
            }
        }
    }

    private function animating() as Boolean {
        if (_pending) {
            return true;
        }
        for (var i = 0; i < _bands.size(); i++) {
            if (_bands[i].mode != OrbMoves.NONE) {
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
        var step = _asked ? 0 : _pacer.step(now());    // a frame the face asked for itself says nothing of the power mode
        _asked = false;
        refresh();
        if (standbyRun(dc)) {
            return;
        }
        if (!_awake && _burnIn) {
            drawStandby(dc, _values);
            _pacer.want(false);
            return;
        }
        _t += step;
        if (_waking) {
            woke();
        }
        demo();
        var titled = _awake && Lib.Look.shown();
        if (titled != _titled) {
            _titled = titled;
            _bands[0].set(texts(_values, _bands[0]));
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
            onLayout(dc);
        }
        var bands = System.getTimer();
        var polys = drawBands(target, bitmap == null);
        _log.part = System.getTimer() - bands;
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
                WatchUi.requestUpdate();     // the start's next band, straight away; the pacer's timer waits for proof of high power, which these frames must not give
            } else {
                _building = false;
            }
        }
        var busy = animating();
        _pacer.want(busy);
        measure(started, polys, busy);
        _log.frame(started, !busy);
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
        onLayout(dc);
        return bitmap;
    }

    // The bands that need it, up to BUDGET polygons an update, each band's turn
    // coming round: a band left over moves on the next frame, its motion
    // skipping rather than slowing. A start lights the time alone, then a
    // band a frame. `all` draws them regardless. Returns the polygons drawn.
    private function drawBands(dc as Dc, all as Boolean) as Number {
        var count = _bands.size();
        var budget = _building ? 0 : allowance();    // a start: a band a frame
        var drew = 0;
        var times = stress();
        var timeOnly = _late && !all;
        _late = false;
        _pending = false;
        _drewBands = [] as Array<Number>;
        for (var n = 0; n < count; n++) {
            var at = (_cursor + n) % count;
            var b = _bands[at];
            if (b.mode == OrbMoves.NONE && !b.dirty) {
                continue;
            }
            if (timeOnly && at != TIME_BAND) {
                _pending = true;
                continue;
            }
            var cost = b.cost() * times;
            if (!all && drew > 0 && cost > budget) {
                _pending = true;
                _cursor = at;
                break;
            }
            _drewBands.add(at);
            budget -= cost;
            for (var r = 0; r < times; r++) {
                b.frame(dc, _t, DRUM);
                drew += b.polys;
            }
        }
        if (!_pending) {
            _cursor = (_cursor + 1) % count;
        }
        return drew;
    }

    private function drawStandby(dc as Dc, values as Array<String>) as Void {
        var minute = System.getClockTime().min;
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(false);    // hard outlines: no faint pixels to count against the 10 %
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setPenWidth(1);
        var rot = ((minute % 5) - 2) * STANDBY_TURN;
        var oy = Lib.Aod.offset(minute, (dc.getWidth() * 0.006).toNumber())[1];
        for (var i = 0; i < _standby.size(); i++) {
            var b = _standby[i];
            b.outline(dc, texts(values, b), rot.toFloat(), oy);
        }
    }

    // ------------------------------------------------------------ the frames' cost

    // Every build logs each motion to the console (on the watch,
    // GARMIN/Apps/LOGS/ORB.TXT): its frames, how long it ran, the longest
    // draw and the most polygons in one frame
    private var _frames as Number = 0;
    private var _since as Number = 0;
    private var _drawMax as Number = 0;
    private var _polyMax as Number = 0;

    private function measure(started as Number, polys as Number, busy as Boolean) as Void {
        var draw = System.getTimer() - started;
        if (busy || _frames > 0) {
            if (_frames == 0) {
                _since = started;
            }
            _frames++;
            _drawMax = (draw > _drawMax) ? draw : _drawMax;
            _polyMax = (polys > _polyMax) ? polys : _polyMax;
        }
        if (!busy && _frames > 0) {
            System.println("orb: motion " + _frames + " frames in " + (started - _since) + " ms, draw max " + _drawMax
                           + " ms, polygons max " + _polyMax + note());
            _frames = 0;
            _drawMax = 0;
            _polyMax = 0;
        }
    }

    // ------------------------------------------------------------ the simulator's motion run

    (:live)
    private function demo() as Void {
    }

    (:live)
    private function stress() as Number {
        return 1;
    }

    (:live)
    private function note() as String {
        return "";
    }

    (:live)
    private function allowance() as Number {
        return BUDGET;
    }

    (:live)
    private function standbyRun(dc as Dc) as Boolean {
        return false;
    }

    (:sample, :still)
    private function demo() as Void {
    }

    (:sample, :still)
    private function stress() as Number {
        return 1;
    }

    (:sample, :still)
    private function note() as String {
        return "";
    }

    (:sample, :still)
    private function allowance() as Number {
        return BUDGET;
    }

    (:sample, :still)
    private function standbyRun(dc as Dc) as Boolean {
        return false;
    }

    // sample-motion.jungle: every few seconds a wake from other readings to
    // the sample ones. First everything changed, with no budget (the worst
    // frame: every band turning at once); then a minute, a heart rate, seven
    // minutes away and everything again, as the face runs; then standby with
    // the inkiest readings drawn once, twice... four times in one update (five
    // trip the watchdog); then everything again with each update drawing what
    // it would two, three, four... times over, until the watchdog trips,
    // which says what margin an update at the budget has
    (:sample, :demo) private var _demoAt as Number = 0;
    (:sample, :demo) private var _demoStep as Number = 0;
    (:sample, :demo) private var _stress as Number = 1;
    (:sample, :demo) private var _demoName as String = "";
    (:sample, :demo) private var _free as Boolean = false;
    (:sample, :demo) private var _standbyTimes as Number = 0;
    (:sample, :demo) const DEMO_GAP = 4000;

    (:sample, :demo)
    private function demo() as Void {
        var t = System.getTimer();
        if (_demoAt == 0) {
            _demoAt = t + DEMO_GAP;
        }
        if (t < _demoAt || animating()) {
            return;
        }
        _demoAt = t + DEMO_GAP;
        var base = ["10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "72", "6214", "82", "1240", "12", "87%", "14:38"] as Array<String>;
        var seen = base.slice(null, null);
        var s = _demoStep;
        _demoStep++;
        if (s >= 5 && s <= 8) {
            _standbyTimes = s - 4;
            return;
        }
        _stress = (s < 5) ? 1 : s - 7;
        _free = s == 0;
        var kind = (s < 5) ? s % 4 : 0;
        if (kind == 0) {
            _demoName = _free ? "everything, no budget" : "everything";
            var all = ["12/28", "20", "08", "07:12", "11:58", "-12°", "-4", "-19", "148", "21114", "100", "", "", "100%", "20:08"];
            for (var i = 0; i < all.size(); i++) {
                seen[i] = all[i];
            }
        } else if (kind == 1) {
            _demoName = "a minute";
            seen[Lib.Numbers.MINUTES] = "37";
            seen[TIME] = "14:37";
            seen[Lib.Numbers.COUNTDOWN] = "4:45";
        } else if (kind == 2) {
            _demoName = "a heart rate";
            seen[Lib.Numbers.HEART] = "70";
        } else {
            _demoName = "seven minutes away";
            seen[Lib.Numbers.COUNTDOWN] = "4:51";
            seen[BATTERY] = "88%";
            seen[Lib.Numbers.MINUTES] = "31";
            seen[TIME] = "14:31";
            seen[Lib.Numbers.HEART] = "88";
            seen[Lib.Numbers.STEPS] = "5980";
            seen[Lib.Numbers.BODY] = "83";
            seen[Lib.Numbers.TEMP] = "45°";
        }
        System.println("orb: " + _demoName + ", stress " + _stress);
        _asleep = seen;
        woke();
    }

    (:sample, :demo)
    private function stress() as Number {
        return _stress;
    }

    (:sample, :demo)
    private function allowance() as Number {
        return _free ? 100000 : BUDGET * _stress;
    }

    (:sample, :demo)
    private function standbyRun(dc as Dc) as Boolean {
        var times = _standbyTimes;
        if (times == 0) {
            return false;
        }
        _standbyTimes = 0;
        var inky = ["12/28", "20", "08", "20:08", "20:08", "-88°", "-88", "-88", "188", "88888", "100", "", "", "88%", "20:08"]
                   as Array<String>;
        var started = System.getTimer();
        for (var r = 0; r < times; r++) {
            drawStandby(dc, inky);
        }
        System.println("orb: standby, the inkiest readings, " + times + " times in one update: " + (System.getTimer() - started) + " ms");
        return true;
    }

    (:sample, :demo)
    private function note() as String {
        var stats = System.getSystemStats();
        return " (" + _demoName + ", stress " + _stress + "; memory " + stats.usedMemory + " of " + stats.totalMemory + ")";
    }

    // ------------------------------------------------------------ for the tests

    // Fixed readings, in the order of Lib.Numbers.Value, then battery and time
    function setValues(values as Array<String>) as Void {
        _fixed = true;
        _pacer.setStill();
        take(values.slice(null, null));
    }

    function setClock(t as Number) as Void {
        _clock = t;
    }

    function setMotion(motion as Boolean) as Void {
        _motion = motion;
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

    // The bands the last update drew, top to bottom 0 to 4
    function bandsDrawn() as Array<Number> {
        return _drewBands;
    }

    // What moves in band i: "turn", a mark per character for drums, or ""
    function moving(i as Number) as String {
        return _bands[i].moving();
    }
}
