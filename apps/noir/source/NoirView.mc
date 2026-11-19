import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// Noir: an analog dial in neon. The hands are loops of tube (the hour
// hand in the hours' tube, the minute hand in the minutes'), the twelve a
// pair of strokes and the quarters one each in the details' tube, the date
// bent from thin tube where the hands leave room: at three o'clock, else
// nine, else six. Nothing else. Where the loops cross, the minute loop
// simply lies over the hour loop.
//
// The watch cannot blur, so every tube is baked by designs/gen_noir.py as
// white masks with the light in their alpha channel: the halo (the
// mockup's three Gaussians, with a grain of noise so the screen's 16 bits
// a pixel show no bands), the core, and the thin tube of standby.
// drawBitmap2 tints a mask with the tube's colour (the core with
// Lib.Neon.core of it) and turns a hand about the centre with a bilinear
// filter, so one upright hand serves every angle. Every colour comes from
// Lib.Neon, so all sixteen tubes, the seven sets and the looks work.
//
// The lit face is drawn into a full-screen bitmap when the minute, the
// date or the look changes, and copied each update: some thirty draws a
// minute. Holding the face steps through the looks (Lib.Look), the look's
// name standing in for the date for a moment, bent from the same tube.
//
// The transition. Hands can't swap as numerals do, so they sweep: on a
// wake each hand turns from where it stood when the face was last seen to
// where it is now, the shorter way round, eased (Lib.Motion.ease: slow
// out, slow in) and done in well under a second however far (Dial.sweepMs);
// a hand that hasn't moved stays still. When the minute turns while the
// face is awake the hands ease to it in a few hundred milliseconds. A hand
// never flickers. The date is struck as a neon tube comes on (Lib.Strike)
// when the day changed since the last look, and when a hand takes its
// place it dies where it was and is struck in its new place. While
// anything moves, what is still stays in the bitmap and what moves is
// drawn each frame over it; the frames come from Lib.Motion's pacer, which
// starts a timer only once the face is known to be awake and stops it the
// moment everything has settled.
//
// Standby (always-on): the two loops and the twelve as thin tubes in
// Lib.Neon.standby colours, no halo, shifted each minute (Lib.Aod); under
// 2 % of the screen lit (designs/preview_noir.py --check). It never
// animates.
class NoirView extends WatchUi.WatchFace {

    // A tube's layers
    private enum { HALO, CORE, THIN }

    private const SHIFT = 0.005;               // the minute shift's step
    private const FRAME = 50;                  // ms between the transition's frames
    private const MOST_FRAMES = 4;             // a stall moves the motion on by this many at most
    private const DATE_SEED = 2;               // the date's pattern of Lib.Strike's

    private var _w as Float = 454.0;
    private var _c as Float = 227.0;
    private var _hour as Number = 10;
    private var _minute as Number = 37;
    private var _day as Number = 15;
    private var _fixed as Boolean = false;     // the tests set the time
    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;
    private var _forceTitle as Boolean = false;

    private var _look as Number = Lib.Look.YOURS;
    private var _lookDay as Number = 0;        // the daily look's day
    private var _colors as Array<Number> = [0, 0, 0] as Array<Number>;

    // The tubes: for each, its layers and each layer's pivot in its own pixels
    private var _hourTube as Array<Graphics.BitmapType?> = [null, null, null] as Array<Graphics.BitmapType?>;
    private var _minuteTube as Array<Graphics.BitmapType?> = [null, null, null] as Array<Graphics.BitmapType?>;
    private var _twelve as Array<Graphics.BitmapType?> = [null, null, null] as Array<Graphics.BitmapType?>;
    private var _quarter as Array<Graphics.BitmapType?> = [null, null, null] as Array<Graphics.BitmapType?>;
    private var _hourAt as Array<Array<Numeric>?> = [null, null, null] as Array<Array<Numeric>?>;
    private var _minuteAt as Array<Array<Numeric>?> = [null, null, null] as Array<Array<Numeric>?>;
    private var _twelveAt as Array<Array<Numeric>?> = [null, null, null] as Array<Array<Numeric>?>;
    private var _quarterAt as Array<Array<Numeric>?> = [null, null, null] as Array<Array<Numeric>?>;
    // The lettering: the digits' sheets, and the letters' while a name shows
    private var _digits as Array<Graphics.BitmapType?> = [null, null] as Array<Graphics.BitmapType?>;
    private var _letters as Array<Graphics.BitmapType?> = [null, null] as Array<Graphics.BitmapType?>;
    private var _haloCell as Array<Number> = [1, 1, 0] as Array<Number>;
    private var _coreCell as Array<Number> = [1, 1, 0] as Array<Number>;
    private var _loaded as Boolean = false;

    private var _xf as Graphics.AffineTransform? = null;      // one transform, reused

    // The lit face, held in a field (the pool purges a bitmap nothing holds)
    private var _failed as Boolean = false;
    private var _faceRef as Graphics.BufferedBitmapReference? = null;
    private var _face as Graphics.BufferedBitmap? = null;
    private var _drawn as Number = -1;         // what the bitmap shows: minute, day, name and what is left out, in one number
    private var _dirty as Boolean = true;

    // The transition: its clock, and what is moving
    private var _pacer as Lib.Motion.Pacer;
    private var _motion as Number = 0;         // ms of drawn frames
    private var _step as Number? = null;       // the tests' frame, in place of the timer's
    private var _waking as Boolean = false;
    private var _titled as Boolean = false;
    private var _to as Array<Float>? = null;                   // the hands as the clock has them: hour, minute
    private var _from as Array<Float> = [0.0, 0.0] as Array<Float>;   // where a sweep began
    private var _dur as Array<Number> = [0, 0] as Array<Number>;      // and how long each hand takes
    private var _sweepAt as Number = -1;                       // when it began; -1 with the hands still
    private var _seen as Array<Float>? = null;                 // the hands when the face was last seen
    private var _date as String = "";                          // the date as shown, and its place
    private var _place as Number = 0;
    private var _seenDate as String = "";                      // and when last seen
    private var _seenPlace as Number = 0;
    private var _struckAt as Number = -1;                      // when the date was struck; -1 when steady
    private var _dying as String? = null;                      // a date going out, its place and since when
    private var _dyingPlace as Number = 0;
    private var _dyingAt as Number = 0;
    // What the transition's frames took, for the tests' log
    private var _frames as Number = 0;
    private var _slowest as Number = 0;
    private var _spent as Number = 0;

    function initialize() {
        WatchFace.initialize();
        _pacer = new Lib.Motion.Pacer(FRAME, MOST_FRAMES);
        _burnIn = Lib.Aod.required();
        if (standbyShot()) {
            _awake = false;
            _burnIn = true;
        }
        _forceTitle = titleShot();
        reloadSettings();
    }

    // Standby can't be driven in the simulator: sample-standby.jungle
    // builds a face that stays in it, for the capture
    (:awakeshot)
    private function standbyShot() as Boolean {
        return false;
    }

    (:standbyshot)
    private function standbyShot() as Boolean {
        return true;
    }

    // And sample-title.jungle one that keeps the look's name up
    (:plainshot)
    private function titleShot() as Boolean {
        return false;
    }

    (:titleshot)
    private function titleShot() as Boolean {
        return true;
    }

    // A wake held at one moment for a capture (sample-sweep-1.jungle to
    // -4): the ms since the face woke at 10:37 on the 15th having last been
    // seen at 6:15 on the 14th, so both hands sweep and the date dies at
    // nine and is struck at three. -1 in every other build.
    (:still)
    private function sweepHeld() as Number {
        return -1;
    }

    (:sweep1)
    private function sweepHeld() as Number {
        return 150;
    }

    (:sweep2)
    private function sweepHeld() as Number {
        return 300;
    }

    (:sweep3)
    private function sweepHeld() as Number {
        return 420;
    }

    (:sweep4)
    private function sweepHeld() as Number {
        return 560;
    }

    function reloadSettings() as Void {
        _look = Lib.Look.mode();
        _lookDay = Lib.Look.today();
        _colors = Lib.Neon.colors(_look);
        _dirty = true;
    }

    function onLayout(dc as Dc) as Void {
        _w = dc.getWidth().toFloat();
        _c = _w / 2.0;
        _face = null;
        _faceRef = null;
        _dirty = true;
        if (!_loaded) {
            load();
        }
    }

    // The tubes of this screen's width (resources-round-<w>x<w>)
    private function load() as Void {
        var at = WatchUi.loadResource(Rez.JsonData.Layout) as Dictionary<String, Array<Numeric> >;
        _hourTube = [bitmap(Rez.Drawables.HourHalo), bitmap(Rez.Drawables.HourCore), bitmap(Rez.Drawables.HourThin)] as Array<Graphics.BitmapType?>;
        _hourAt = [at["HourHalo"], at["HourCore"], at["HourThin"]] as Array<Array<Numeric>?>;
        _minuteTube = [bitmap(Rez.Drawables.MinuteHalo), bitmap(Rez.Drawables.MinuteCore), bitmap(Rez.Drawables.MinuteThin)] as Array<Graphics.BitmapType?>;
        _minuteAt = [at["MinuteHalo"], at["MinuteCore"], at["MinuteThin"]] as Array<Array<Numeric>?>;
        _twelve = [bitmap(Rez.Drawables.TwelveHalo), bitmap(Rez.Drawables.TwelveCore), bitmap(Rez.Drawables.TwelveThin)] as Array<Graphics.BitmapType?>;
        _twelveAt = [at["TwelveHalo"], at["TwelveCore"], at["TwelveThin"]] as Array<Array<Numeric>?>;
        _quarter = [bitmap(Rez.Drawables.QuarterHalo), bitmap(Rez.Drawables.QuarterCore), null] as Array<Graphics.BitmapType?>;
        _quarterAt = [at["QuarterHalo"], at["QuarterCore"], null] as Array<Array<Numeric>?>;
        _digits = [bitmap(Rez.Drawables.DigitsHalo), bitmap(Rez.Drawables.DigitsCore)] as Array<Graphics.BitmapType?>;
        _haloCell = at["haloCell"] as Array<Number>;
        _coreCell = at["coreCell"] as Array<Number>;
        _xf = new Graphics.AffineTransform();
        _loaded = true;
    }

    private function bitmap(id as ResourceId) as Graphics.BitmapType {
        return WatchUi.loadResource(id) as Graphics.BitmapType;
    }

    function onShow() as Void {
        _pacer.onShow();
    }

    function onHide() as Void {
        _pacer.onHide();
    }

    function onEnterSleep() as Void {
        _awake = false;
        _pacer.onEnterSleep();
        _seen = _to;            // where the hands stood when last seen: a wake sweeps from here
        _seenDate = _date;
        _seenPlace = _place;
        settle();
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _awake = true;
        _waking = true;
        _pacer.onExitSleep();
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------ state

    private function refresh() as Void {
        if (_fixed) {
            return;
        }
        read();
    }

    (:live)
    private function read() as Void {
        var clock = System.getClockTime();
        _hour = clock.hour;
        _minute = clock.min;
        _day = Gregorian.info(Time.now(), Time.FORMAT_SHORT).day as Number;
    }

    // The mockup's moment (sample.jungle): 10:37 on Tuesday 15 December
    // 2026; the other sample builds show the hands elsewhere
    (:sample)
    private function read() as Void {
        var at = moment();
        _hour = at[0];
        _minute = at[1];
        _day = 15;
    }

    (:sample, :t1037)
    private function moment() as Array<Number> {
        return [10, 37] as Array<Number>;
    }

    (:sample, :t1200)
    private function moment() as Array<Number> {
        return [12, 0] as Array<Number>;       // the loops nested
    }

    (:sample, :t0417)
    private function moment() as Array<Number> {
        return [4, 17] as Array<Number>;       // the loops crossing, the date moved to nine
    }

    (:sample, :t0915)
    private function moment() as Array<Number> {
        return [9, 15] as Array<Number>;       // both sides taken: the date at six
    }

    (:sample, :t0752)
    private function moment() as Array<Number> {
        return [7, 52] as Array<Number>;       // no angle in particular
    }

    // For the tests: a fixed time and day of the month
    function setTime(hour as Number, minute as Number, day as Number) as Void {
        _fixed = true;
        _hour = hour;
        _minute = minute;
        _day = day;
    }

    // For the tests: awake or standby, as on an AMOLED watch
    function setAwake(awake as Boolean) as Void {
        _burnIn = true;
        if (awake) {
            onExitSleep();
        } else {
            onEnterSleep();
        }
    }

    // For the tests: frames of a set length in place of the timer's
    function setFrame(ms as Number) as Void {
        _pacer.setStill();
        _step = ms;
    }

    // For the tests: whether anything is moving, where the hands are drawn
    // now, and what the transition's frames took
    function moving() as Boolean {
        return _sweepAt >= 0 || _struckAt >= 0 || _dying != null;
    }

    function hands() as Array<Float> {
        return [handAt(0), handAt(1)] as Array<Float>;
    }

    function frameLog() as String {
        var out = _frames + " frames, " + ((_frames > 0) ? _spent / _frames : 0) + " ms each, the slowest " + _slowest + " ms";
        _frames = 0;
        _slowest = 0;
        _spent = 0;
        return out;
    }

    // For the tests: the look's name up, or not
    function setTitled(titled as Boolean) as Void {
        _forceTitle = titled;
    }

    // For the tests: three tubes by number (Lib.Neon.TUBES), whatever the look
    function setTubes(tubes as Array<Number>) as Void {
        _colors = [Lib.Neon.TUBES[tubes[0]], Lib.Neon.TUBES[tubes[1]], Lib.Neon.TUBES[tubes[2]]] as Array<Number>;
        _dirty = true;
    }

    // For the tests: draw straight to the screen, as when the graphics
    // pool has no room for the bitmap
    function dropBitmap() as Void {
        _failed = true;
        _face = null;
        _faceRef = null;
    }

    // ------------------------------------------------------------ the transition

    // Where a hand (0 the hour hand, 1 the minute hand) is drawn now
    private function handAt(i as Number) as Float {
        var to = _to;
        if (to == null) {
            return 0.0;
        }
        if (_sweepAt < 0) {
            return to[i];
        }
        return Dial.swept(_from[i], to[i], _motion - _sweepAt, _dur[i]);
    }

    // Start what a change asks for: the hands sweep from `from` to `to`
    // (on a wake by the distance's time, awake by the tick's), and the date
    // is struck, after dying in its old place if it had one to leave
    private function begin(from as Array<Float>, to as Array<Float>, oldDate as String, oldPlace as Number,
                           date as String, place as Number, wake as Boolean) as Void {
        var hourTurn = Dial.turn(from[0], to[0]);
        var minuteTurn = Dial.turn(from[1], to[1]);
        if (hourTurn != 0.0 || minuteTurn != 0.0) {
            _from = from;
            _dur = [wake ? Dial.sweepMs(hourTurn) : Layout.TICK, wake ? Dial.sweepMs(minuteTurn) : Layout.TICK] as Array<Number>;
            _sweepAt = _motion;
        }
        if (oldDate.equals("")) {
            return;                 // nothing was shown before: nothing to change from
        }
        if (place != oldPlace || (!wake && !date.equals(oldDate))) {
            _dying = oldDate;
            _dyingPlace = oldPlace;
            _dyingAt = _motion;
            _struckAt = _motion + Lib.Strike.DEATH;
        } else if (!date.equals(oldDate)) {
            _struckAt = _motion;
        }
    }

    // Everything at rest
    private function settle() as Void {
        _sweepAt = -1;
        _struckAt = -1;
        _dying = null;
    }

    // What has finished comes to rest
    private function finish() as Void {
        if (_sweepAt >= 0) {
            var t = _motion - _sweepAt;
            if (!Dial.sweeping(t, _dur[0]) && !Dial.sweeping(t, _dur[1])) {
                _sweepAt = -1;
            }
        }
        if (_dying != null && Lib.Strike.dead(_motion - _dyingAt)) {
            _dying = null;
        }
        if (_struckAt >= 0 && _motion - _struckAt >= Lib.Strike.LONGEST) {
            _struckAt = -1;
        }
    }

    // ------------------------------------------------------------ drawing

    function onUpdate(dc as Dc) as Void {
        if (_look == Lib.Look.DAILY && Lib.Look.today() != _lookDay) {
            reloadSettings();     // a new day, a new set
        }
        var started = System.getTimer();
        var step = _pacer.step(started);
        var frame = _step;
        _motion += (frame != null) ? frame : step;
        refresh();
        if (!_loaded) {
            onLayout(dc);
        }
        var degs = Dial.angles(_hour, _minute);
        var date = _day.toString();
        var place = Dial.datePlace(degs[0], degs[1]);
        if (!_awake && _burnIn) {
            _letters = [null, null] as Array<Graphics.BitmapType?>;
            _to = degs;
            _date = date;
            _place = place;
            drawStandby(dc, degs);
            _pacer.want(false);
            return;
        }
        var titled = _forceTitle || Lib.Look.shown();
        if (!titled && _letters[0] != null) {
            _letters = [null, null] as Array<Graphics.BitmapType?>;
        }
        var face = buffer(dc);
        if (face == null) {
            settle();
            _to = degs;
            _date = date;
            _place = place;
            draw(dc, titled, degs, true, true);
            _pacer.want(false);
            return;
        }

        // What changed: since the face was last seen, on a wake; since the
        // last frame, while awake. A transition needs frames, so nothing
        // moves until the face is known to be awake.
        var hold = sweepHeld();
        var to = _to;
        if (hold >= 0) {
            _motion = 0;
            settle();
            var seen = Dial.angles(6, 15);
            begin(seen, degs, "14", Dial.datePlace(seen[0], seen[1]), date, place, true);
            _motion = hold;       // begun at 0, seen at `hold`, and never settling
        } else if (_waking) {
            _waking = false;
            var seen = _seen;
            _seen = null;
            if (seen != null && _pacer.proven()) {
                begin(seen, degs, _seenDate, _seenPlace, date, place, true);
            }
        } else if (to != null && _awake && _pacer.proven()
                   && (to[0] != degs[0] || to[1] != degs[1] || place != _place || !date.equals(_date))) {
            begin([handAt(0), handAt(1)] as Array<Float>, degs, _date, _place, date, place, false);
        }
        _to = degs;
        _date = date;
        _place = place;
        if (titled) {
            _struckAt = -1;       // the look's name stands where the date would be struck
            _dying = null;
        }
        if (hold < 0) {
            finish();
        }

        // What is still is in the bitmap; what moves is drawn over it
        var sweeping = _sweepAt >= 0;
        var striking = _struckAt >= 0 || _dying != null;
        var key = (((((_hour % 12) * 60 + _minute) * 32 + _day) * 2 + (titled ? 1 : 0)) * 2 + (sweeping ? 1 : 0)) * 2 + (striking ? 1 : 0);
        if (_dirty || key != _drawn || titled != _titled) {
            draw(face.getDc(), titled, degs, !sweeping, !striking);
            _drawn = key;
            _titled = titled;
            _dirty = false;
        }
        dc.drawBitmap(0, 0, face);
        if (sweeping || striking) {
            if (dc has :setAntiAlias) {
                dc.setAntiAlias(true);
            }
            move(dc, sweeping);
            var took = System.getTimer() - started;
            _frames++;
            _spent += took;
            _slowest = (took > _slowest) ? took : _slowest;
        }
        _pacer.want((sweeping || striking) && hold < 0);
    }

    // The lit face's bitmap; null when the pool has no room for it
    private function buffer(dc as Dc) as Graphics.BufferedBitmap? {
        if (_failed || !(Graphics has :createBufferedBitmap)) {
            return null;
        }
        if (_face == null) {
            try {
                _faceRef = Graphics.createBufferedBitmap({:width => dc.getWidth(), :height => dc.getHeight()});
                _face = (_faceRef as Graphics.BufferedBitmapReference).get() as Graphics.BufferedBitmap?;
            } catch (e) {
                _failed = true;
                return null;
            }
            if (_face == null) {
                _faceRef = null;   // reclaimed by the pool; try again next time
            }
            _dirty = true;
        }
        return _face;
    }

    // One layer of a tube, turned `deg` about (cx, cy) and tinted
    private function lay(dc as Dc, tube as Array<Graphics.BitmapType?>, pivots as Array<Array<Numeric>?>, kind as Number,
                         deg as Float, color as Number, cx as Float, cy as Float) as Void {
        var bmp = tube[kind];
        var at = pivots[kind];
        var xf = _xf;
        if (bmp == null || at == null || xf == null) {
            return;
        }
        if (deg == 0.0) {
            dc.drawBitmap2(cx - at[0], cy - at[1], bmp, {:tintColor => color});
            return;
        }
        xf.setToRotation(Math.toRadians(deg).toFloat());
        xf.translate(-(at[0].toFloat()), -(at[1].toFloat()));
        dc.drawBitmap2(cx, cy, bmp, {:tintColor => color, :filterMode => Graphics.FILTER_MODE_BILINEAR, :transform => xf});
    }

    // A line of lettering centred on (x, y): each letter's cell from its
    // sheet, the halo's or the core's, at whole pixels. The whole sheet is
    // drawn through a clip the size of the cell: drawBitmap2's own
    // :bitmapX leaves the cell where it sits in the sheet (the simulator
    // does; the documentation doesn't say)
    private function write(dc as Dc, text as String, x as Float, y as Float, color as Number, core as Boolean) as Void {
        var cell = core ? _coreCell : _haloCell;
        var cw = cell[0];
        var ch = cell[1];
        var m = cell[2];
        var h = Layout.TEXT_H * _w;
        var chars = text.toCharArray();
        var digits = Layout.DIGITS.length();
        var at = new [chars.size()] as Array<Number>;
        var total = Layout.TEXT_GAP * (chars.size() - 1);
        for (var i = 0; i < chars.size(); i++) {
            var s = chars[i].toString();
            var n = Layout.DIGITS.find(s);
            if (n == null) {
                n = Layout.LETTERS.find(s);
                n = (n == null) ? -1 : n + digits;
            }
            at[i] = n;
            total += (n < 0) ? Layout.SPACE : Layout.WIDTHS[n] / 1000.0;
        }
        var left = x - total * h / 2.0;
        var top = Math.floor(y - h / 2.0 + 0.5).toNumber() - m;
        for (var i = 0; i < chars.size(); i++) {
            var n = at[i];
            if (n < 0) {
                left += (Layout.SPACE + Layout.TEXT_GAP) * h;
                continue;
            }
            var sheet = _digits[core ? 1 : 0];
            var cols = digits;
            var k = n;
            if (n >= digits) {
                sheet = _letters[core ? 1 : 0];
                cols = Layout.COLS;
                k = n - digits;
            }
            if (sheet != null) {
                var gx = Math.floor(left + 0.5).toNumber() - m;
                dc.setClip(gx, top, cw, ch);
                dc.drawBitmap2(gx - (k % cols) * cw, top - (k / cols) * ch, sheet, {:tintColor => color});
            }
            left += (Layout.WIDTHS[n] / 1000.0 + Layout.TEXT_GAP) * h;
        }
        dc.clearClip();
    }

    // The date at one of its places: 0 at three o'clock, 1 at nine, 2 at six
    private function writeDate(dc as Dc, text as String, place as Number, color as Number, core as Boolean) as Void {
        var r = Layout.DATE_R * _w;
        if (place == 2) {
            write(dc, text, _c, _c + r, color, core);
        } else {
            write(dc, text, _c + ((place == 0) ? r : -r), _c, color, core);
        }
    }

    // The lit face: every halo first, then the cores over them, the hour
    // hand's before the minute hand's. Without the hands while they sweep
    // and without the date while it is struck: those are drawn each frame.
    private function draw(dc as Dc, titled as Boolean, degs as Array<Float>, hands as Boolean, dated as Boolean) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        var c = _c;
        var hours = _colors[0];
        var minutes = _colors[1];
        var detail = _colors[2];
        var hd = degs[0];
        var md = degs[1];
        var name = "";
        var ty = c;
        if (titled) {
            name = Lib.Neon.title(_look);
            if (_letters[0] == null) {
                _letters = [bitmap(Rez.Drawables.LettersHalo), bitmap(Rez.Drawables.LettersCore)] as Array<Graphics.BitmapType?>;
            }
            ty = c + (Dial.titleBelow(md) ? Layout.TITLE_Y : -Layout.TITLE_Y) * _w;
        }
        var core = Lib.Neon.core(detail);

        for (var q = 1; q < 4; q++) {
            lay(dc, _quarter, _quarterAt, HALO, q * 90.0, detail, c, c);
        }
        lay(dc, _twelve, _twelveAt, HALO, 0.0, detail, c, c);
        if (titled) {
            write(dc, name, c, ty, detail, false);
        } else if (dated) {
            writeDate(dc, _date, _place, detail, false);
        }
        if (hands) {
            lay(dc, _hourTube, _hourAt, HALO, hd, hours, c, c);
            lay(dc, _minuteTube, _minuteAt, HALO, md, minutes, c, c);
        }
        for (var q = 1; q < 4; q++) {
            lay(dc, _quarter, _quarterAt, CORE, q * 90.0, core, c, c);
        }
        lay(dc, _twelve, _twelveAt, CORE, 0.0, core, c, c);
        if (titled) {
            write(dc, name, c, ty, core, true);
        } else if (dated) {
            writeDate(dc, _date, _place, core, true);
        }
        if (hands) {
            lay(dc, _hourTube, _hourAt, CORE, hd, Lib.Neon.core(hours), c, c);
            lay(dc, _minuteTube, _minuteAt, CORE, md, Lib.Neon.core(minutes), c, c);
        }
    }

    // What moves, over the bitmap: the date dying or being struck at its
    // brightness of the moment, the hands where their sweep has them. Every
    // halo before any core.
    private function move(dc as Dc, sweeping as Boolean) as Void {
        var c = _c;
        var detail = _colors[2];
        var core = Lib.Neon.core(detail);
        var dying = _dying;
        var gone = (dying != null) ? Lib.Strike.dying(_motion - _dyingAt) : [0, 0] as Array<Number>;
        var lit = (_struckAt >= 0) ? Lib.Strike.lit(_motion - _struckAt, DATE_SEED) : [0, 0] as Array<Number>;
        if (dying != null && gone[1] > 0) {
            writeDate(dc, dying, _dyingPlace, Lib.Neon.wash(detail, 0, gone[1]), false);
        }
        if (lit[1] > 0) {
            writeDate(dc, _date, _place, Lib.Neon.wash(detail, 0, lit[1]), false);
        }
        var hd = handAt(0);
        var md = handAt(1);
        if (sweeping) {
            lay(dc, _hourTube, _hourAt, HALO, hd, _colors[0], c, c);
            lay(dc, _minuteTube, _minuteAt, HALO, md, _colors[1], c, c);
        }
        if (dying != null && gone[0] > 0) {
            writeDate(dc, dying, _dyingPlace, Lib.Neon.wash(core, 0, gone[0]), true);
        }
        if (lit[0] > 0) {
            writeDate(dc, _date, _place, Lib.Neon.wash(core, 0, lit[0]), true);
        }
        if (sweeping) {
            lay(dc, _hourTube, _hourAt, CORE, hd, Lib.Neon.core(_colors[0]), c, c);
            lay(dc, _minuteTube, _minuteAt, CORE, md, Lib.Neon.core(_colors[1]), c, c);
        }
    }

    // Standby: the loops and the twelve, thin, shifted each minute
    private function drawStandby(dc as Dc, degs as Array<Float>) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        var step = (SHIFT * _w + 0.5).toNumber();
        var off = Lib.Aod.offset(_minute, (step < 1) ? 1 : step);
        var cx = _c + off[0];
        var cy = _c + off[1];
        lay(dc, _twelve, _twelveAt, THIN, 0.0, Lib.Neon.standby(_colors[2]), cx, cy);
        lay(dc, _hourTube, _hourAt, THIN, degs[0], Lib.Neon.standby(_colors[0]), cx, cy);
        lay(dc, _minuteTube, _minuteAt, THIN, degs[1], Lib.Neon.standby(_colors[1]), cx, cy);
    }
}
