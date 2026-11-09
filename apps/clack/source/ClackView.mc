import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

// Clack: a split-flap clock with no case. Four leaves, one per digit, dark
// plastic split by the slot with the pivot pins at its ends, the digits as
// large as the circle allows. The original view sets the leaves across the
// middle; the zoomed-in view runs them off the screen top and bottom so the
// bezel cuts them, the numbers whole, in League Gothic, Antonio Bold, Bebas
// Neue (bitmap fonts made from the TTFs) or Roboto. After sunset an amber
// lamp from the upper left lights the hour leaves and leaves the minutes in
// shadow.
//
// The roll: awake, the face draws at twenty frames a second (a timer, started
// only once the watch has shown it is in high power mode: onExitSleep, or the
// system's own once-a-second updates; Timer.start in low power mode kills a
// face) and the leaves flip as the mechanism does (Roll, Drops): the push off
// the stop, the fall, the bounce; the next leaf in view behind the falling
// flap from the moment it lifts, the flap's back bringing the new lower half
// down. The flips keep the clock's time, not the frame count, so a slow frame
// skips motion rather than stretching it. A wake rolls every missed minute up
// to four. Standby cannot animate:
// the digits as edges (the hour leaves' upper flaps filled in the original
// view and in zoomed Roboto, eroded), the hinge across the face, shifted
// each minute (Lib.Aod), under ten percent lit (designs/preview_clack.py).
class ClackView extends WatchUi.WatchFace {

    // The palettes (designs/preview_clack.py DAY and NIGHT)
    enum Pal { TOP, MID, SHADE, BOT, EDGE, PIN, PIN_HL, STACK, INK, INK_LIT, DATE }
    private const DAY = [0x2C2C2C, 0x1A1A1A, 0x0E0E0E, 0x202020, 0x4E4E4E, 0x3C3C3C, 0x787878, 0x282828, 0xE8E8E8, 0xE8E8E8, 0xAAAAAA]
                        as Array<Number>;
    private const NIGHT = [0x1A0F07, 0x0E0804, 0x060302, 0x120A05, 0x78461C, 0x3C240E, 0xAA6E32, 0x2C1A0A, 0x966030, 0xFFDAA0, 0xD69654]
                          as Array<Number>;
    private const LIT = 0x5C3412;                // the lamp's tint on the plastic
    private const LIT_SHARE = 0.44;              // how far the plastic goes toward it under the lamp at full
    private const SPILL = 0xFF963C;              // the lamp's pool on the black
    private const SPILL_SHARE = 0.17;
    private const SPILL_RINGS = 20;
    private const AOD_DAY = 0x808080;
    private const AOD_NIGHT = 0x966836;
    private const AOD_STEP = 4;                  // Lib.Aod.offset's step on 454
    private const DARK_DAY = 0.35;               // the falling flap's darkening, turned from the lamp
    private const DARK_NIGHT = 0.6;
    private const EM_HEIGHT = 1.173;             // Roboto Condensed's height per em (Lib.Ink.HEIGHT)
    // The original view's digit face: Roboto Condensed Bold, or where a watch lacks it (the Venu 3)
    // the nearest it has, set when the fonts are made
    private var _face as Number = Lib.Ink.CONDENSED_BOLD;
    private const TRACK = 0.10;                  // the captions' letter spacing, of their em
    private const PERIOD = 1000 / Roll.FPS;      // ms between frames
    private const MOST_FRAMES = 4;               // frames one drawn frame may move the flips: a stall skips, never stretches
    private const QUICK = 1500;                  // ms: an update this soon after the last is the system's once-a-second one
    private const QUICK_RUN = 2;                 // quick gaps in a row that prove high power mode
    private const ASLEEP_GAP = 5000;             // ms without an update: low power mode, when nothing has said otherwise

    // Settings
    private var _style as Number = 1;
    private var _date as Boolean = true;

    // The layout for this device and style (Layout.table)
    private var _w as Number = 454;
    private var _h as Number = 454;
    private var _t as Array<Number> = Layout.W454[1];
    private var _leafW as Number = 97;
    private var _leafH as Number = 479;
    private var _y0 as Number = -13;
    private var _hinge as Number = 227;
    private var _x as Array<Number> = [21, 123, 233, 336] as Array<Number>;
    private var _cx as Array<Number> = [69, 172, 282, 385] as Array<Number>;
    private var _zoomed as Boolean = true;
    private var _lamp as Array<Float> = [0.3, 0.2, 0.08, 0.01] as Array<Float>;
    // The stacks' edges on the screen, per leaf, as [x0, y, x1] triples
    // (none in the zoomed view, where they fall off the screen)
    private var _stackLines as Array<Array<Number>> = [[], [], [], []] as Array<Array<Number>>;
    private var _stacks as Boolean = false;
    private var _tint as Boolean = false;        // drawBitmap2 (its tint darkens the falling flap)
    private var _xf as Graphics.AffineTransform? = null;   // the flap's foreshortening, one object reused

    // Fonts
    private var _digitFont as FontType = Graphics.FONT_NUMBER_HOT;
    private var _bitmapDigits as Boolean = false;
    private var _standbyFont as FontType? = null;
    private var _small as FontType = Graphics.FONT_XTINY;
    private var _em as Float = 0.0;              // Roboto's em, when the digits are the vector font
    private var _laidOut as Boolean = false;

    // Awake or in low power mode: told by onExitSleep and onEnterSleep; until
    // the first of those, inferred from the updates' cadence (every second
    // awake, every minute asleep)
    private var _awake as Boolean = true;
    private var _powerKnown as Boolean = false;
    private var _burnIn as Boolean = false;

    // The once-a-minute state
    private var _minute as Number = -1;
    private var _is24 as Boolean = true;
    private var _night as Boolean = false;
    private var _dateText as String = "";

    // The leaves: the digit each shows, its halves as bitmaps, the flip in progress
    private var _leaves as Array<String> = ["2", "1", "0", "5"] as Array<String>;
    private var _top as Array<BufferedBitmapReference?> = [null, null, null, null] as Array<BufferedBitmapReference?>;
    private var _bot as Array<BufferedBitmapReference?> = [null, null, null, null] as Array<BufferedBitmapReference?>;
    private var _flips as Array<Roll.Flip?> = [null, null, null, null] as Array<Roll.Flip?>;
    private var _nextTop as Array<BufferedBitmapReference?> = [null, null, null, null] as Array<BufferedBitmapReference?>;
    private var _nextBot as Array<BufferedBitmapReference?> = [null, null, null, null] as Array<BufferedBitmapReference?>;
    private var _dirty as Boolean = true;        // the bitmaps need remaking (style, lamp or format changed)
    private var _spill as BufferedBitmapReference? = null; // the lamp's pool on the black, drawn once
    private const DEPTH = 16;                    // bits a pixel in the graphics pool: the fenix 8's own
    private const BAND = 8;                      // rows a band of a half's gradient covers (half)
    private const NEXT_BOT_AT = 2;               // frames into a push when the next lower half is built (advance)

    // The schedule: the minute the leaves show or roll toward, the missed
    // minutes still to roll, the next minute's push once drawn, frames of
    // rest between catch-up steps
    private var _shownMinute as Number = -1;
    private var _queue as Array<Number> = [] as Array<Number>;
    private var _creep as Float = 0.0;
    private var _armed as Number = -1;
    private var _hold as Number = 0;
    private var _timer as Timer.Timer? = null;
    private var _running as Boolean = false;
    private var _still as Boolean = false;       // the tests: no timer, no frames from onUpdate
    private var _lastSec as Number = -1;
    private var _secStart as Number = 0;
    // The frames' clock: the last frame's time and the milliseconds not yet
    // turned into frames; the updates' cadence (quick ones in a row prove
    // high power mode)
    private var _lastFrame as Number = 0;
    private var _carry as Number = 0;
    private var _lastUpdate as Number = 0;
    private var _quick as Number = 0;
    private var _noSpill as Boolean = false;     // the pool had no room for the lamp's pool

    function initialize() {
        WatchFace.initialize();
        _burnIn = Lib.Aod.required();
        reloadSettings();
    }

    // ------------------------------------------------------------ settings

    function reloadSettings() as Void {
        var style = ClackSettings.style();
        var date = ClackSettings.date();
        var changed = style != _style || date != _date;
        _style = style;
        _date = date;
        if (changed && _laidOut) {
            relayout();
        }
    }

    // ------------------------------------------------------------ layout

    function onLayout(dc as Dc) as Void {
        _w = dc.getWidth();
        _h = dc.getHeight();
        _tint = dc has :drawBitmap2;
        relayout();
        _laidOut = true;
    }

    private function relayout() as Void {
        var t = Layout.table(_w, _style);
        _t = t;
        _leafW = t[Layout.LEAF_W];
        _leafH = t[Layout.LEAF_H];
        _y0 = t[Layout.Y0];
        _hinge = t[Layout.HINGE];
        _x = [t[Layout.X0], t[Layout.X1], t[Layout.X2], t[Layout.X3]] as Array<Number>;
        _cx = [t[Layout.CX0], t[Layout.CX1], t[Layout.CX2], t[Layout.CX3]] as Array<Number>;
        _zoomed = t[Layout.ZOOMED] == 1;
        _lamp = Layout.lamp(_w, _zoomed);
        _stackLines = stackLines();
        _stacks = _stackLines[0].size() > 0;
        makeFonts();
        _dirty = true;
    }

    // The leaves yet to fall and the fallen ones: their edges above and
    // below each leaf, those on the screen (off it in the zoomed view),
    // worked out once so a frame only draws them
    private function stackLines() as Array<Array<Number>> {
        var step = _t[Layout.STEP];
        var inset = _w * 4 / 1000;
        var r = _t[Layout.CORNER];
        var all = [] as Array<Array<Number>>;
        for (var i = 0; i < 4; i++) {
            var lines = [] as Array<Number>;
            for (var k = 1; k <= 3; k++) {
                var x0 = _x[i] + inset * k + r * 2 / 5;
                var x1 = _x[i] + _leafW - inset * k - r * 2 / 5;
                var below = _y0 + _leafH + step * k;
                if (below < _h) {
                    lines.addAll([x0, below, x1] as Array<Number>);
                }
                var above = _y0 - step * k;
                if (k <= 2 && above >= 0) {
                    lines.addAll([x0, above, x1] as Array<Number>);
                }
            }
            all.add(lines);
        }
        return all;
    }

    private function makeFonts() as Void {
        var t = _t;
        var font = t[Layout.FONT];
        if (font == Layout.ROBOTO) {
            _face = Lib.Ink.resolve(Lib.Ink.CONDENSED_BOLD);
            _em = Lib.Ink.em(_face, t[Layout.DIGIT].toFloat());
            _digitFont = Lib.Ink.font(_face, _em, Graphics.FONT_NUMBER_HOT);
            _bitmapDigits = false;
        } else {
            _bitmapDigits = true;
            if (font == Layout.LEAGUE) {
                _digitFont = WatchUi.loadResource(Rez.Fonts.LeagueDigits) as FontResource;
            } else if (font == Layout.ANTONIO) {
                _digitFont = WatchUi.loadResource(Rez.Fonts.AntonioDigits) as FontResource;
            } else {
                _digitFont = WatchUi.loadResource(Rez.Fonts.BebasDigits) as FontResource;
            }
        }
        _standbyFont = null;
        if (_zoomed) {
            if (font == Layout.LEAGUE) {
                _standbyFont = WatchUi.loadResource(Rez.Fonts.LeagueStandby) as FontResource;
            } else if (font == Layout.ANTONIO) {
                _standbyFont = WatchUi.loadResource(Rez.Fonts.AntonioStandby) as FontResource;
            } else if (font == Layout.BEBAS) {
                _standbyFont = WatchUi.loadResource(Rez.Fonts.BebasStandby) as FontResource;
            } else {
                _standbyFont = WatchUi.loadResource(Rez.Fonts.RobotozoomStandby) as FontResource;
            }
        }
        _small = Lib.Fmt.vectorFont("RobotoCondensedRegular", (t[Layout.SMALL] * EM_HEIGHT).toNumber(), Graphics.FONT_XTINY);
    }

    // ------------------------------------------------------------ state

    // The once-a-minute readings: the format, the lamp, the date
    function refresh() as Void {
        var clock = System.getClockTime();
        if (clock.min == _minute) {
            return;
        }
        _minute = clock.min;
        var is24 = System.getDeviceSettings().is24Hour;
        var next = Lib.Sun.next(Lib.Sun.today());
        var night = next != null && next[0];
        if (is24 != _is24 || night != _night) {
            _is24 = is24;
            _night = night;
            _dirty = true;
        }
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        _dateText = (info.day_of_week + " " + info.day).toUpper();
        sample();
    }

    (:live)
    private function sample() as Void {
    }

    // The screenshots' time (sample.jungle: 21:05 after sunset, the lamp on;
    // sample-day.jungle: 14:38 by day), the leaves three minutes behind so the
    // face rolls to it on load (and again each real minute), as a wake does
    (:sample, :night)
    private function sample() as Void {
        _night = true;
        _dateText = "SAT 31";
        roll();
    }

    (:sample, :day)
    private function sample() as Void {
        _night = false;
        _dateText = "SAT 31";
        roll();
    }

    (:sample)
    private function roll() as Void {
        _dirty = true;
        _shownMinute = sampleMinute() - 3;
        _leaves = Roll.digits(_shownMinute, _is24);
        _queue = [] as Array<Number>;
        _flips = [null, null, null, null] as Array<Roll.Flip?>;
        standbySample();
    }

    // The standby screenshot (sample-standby.jungle): low power mode held,
    // which the simulator cannot be put into from a script
    (:sample, :standby)
    private function standbySample() as Void {
        _awake = false;
        _powerKnown = true;
        _burnIn = true;
    }

    (:sample, :lit)
    private function standbySample() as Void {
    }

    (:live)
    private function sampleMinute() as Number {
        return -1;
    }

    (:sample, :night)
    private function sampleMinute() as Number {
        return 21 * 60 + 5;
    }

    (:sample, :day)
    private function sampleMinute() as Number {
        return 14 * 60 + 38;
    }

    // The minute of the day now, and the seconds to the next one
    private function nowMinute() as Number {
        var fixed = sampleMinute();
        if (fixed >= 0) {
            return fixed;
        }
        var clock = System.getClockTime();
        return clock.hour * 60 + clock.min;
    }

    private function toBoundary() as Float {
        if (sampleMinute() >= 0) {
            return 30.0;
        }
        var clock = System.getClockTime();
        var now = System.getTimer();
        if (clock.sec != _lastSec) {
            _lastSec = clock.sec;
            _secStart = now;
        }
        var frac = (now - _secStart) / 1000.0;
        if (frac > 0.999) {
            frac = 0.999;
        }
        return 60.0 - clock.sec - frac;
    }

    // For the tests: a fixed time, format and lamp, the leaves showing it
    function setState(hours as Number, minutes as Number, night as Boolean, is24 as Boolean) as Void {
        refresh();
        _is24 = is24;
        _night = night;
        _dateText = "SAT 31";
        _shownMinute = hours * 60 + minutes;
        _leaves = Roll.digits(_shownMinute, is24);
        _flips = [null, null, null, null] as Array<Roll.Flip?>;
        _queue = [] as Array<Number>;
        _armed = -1;
        _dirty = true;
    }

    // For the tests: leaf i mid-flip to `to` at `angle` degrees
    function setFlip(i as Number, to as String, angle as Number) as Void {
        makeLeaves();
        var before = _flips[i];
        _flips[i] = new Roll.Flip(_leaves[i], to, [angle.toFloat()] as Array<Float>, 0);
        if (before == null || !before.to.equals(to) || _nextTop[i] == null) {
            _nextTop[i] = half(i, to, true);
            _nextBot[i] = half(i, to, false);
        }
    }

    // For the tests: let the pool go
    function release() as Void {
        _top = [null, null, null, null] as Array<BufferedBitmapReference?>;
        _bot = [null, null, null, null] as Array<BufferedBitmapReference?>;
        _nextTop = [null, null, null, null] as Array<BufferedBitmapReference?>;
        _nextBot = [null, null, null, null] as Array<BufferedBitmapReference?>;
        _flips = [null, null, null, null] as Array<Roll.Flip?>;
        _spill = null;
        _dirty = true;
    }

    // For the tests: roll from the minute shown to `minute` as a wake does,
    // one frame at a time; returns the frames it took
    function rollTo(minute as Number) as Number {
        enqueue(minute);
        var frames = 0;
        while ((_queue.size() > 0 || busy() || _hold > 0) && frames < 400) {
            schedule(1);
            advance(1);
            frames++;
        }
        return frames;
    }

    function shows() as Array<String> {
        return _leaves;
    }

    function setAwake(awake as Boolean) as Void {
        _awake = awake;
        _powerKnown = true;
        _burnIn = true;
    }

    // For the tests: no timer, and no frames from onUpdate, so a state set
    // stays as set while it is drawn
    function setStill() as Void {
        _still = true;
    }

    // ------------------------------------------------------------ the roll

    // Shown: in either power mode (the watch has shown the face in low power
    // mode, CIQ_LOG.YML 2026-11-07), so no timer yet; the updates' cadence
    // decides (cadence)
    function onShow() as Void {
        _minute = -1;
        _quick = 0;
        _lastUpdate = 0;
        WatchUi.requestUpdate();
    }

    function onHide() as Void {
        stop();
    }

    // A wake: high power mode for certain, the timer may run
    function onExitSleep() as Void {
        _awake = true;
        _powerKnown = true;
        _minute = -1;
        start("wake");
    }

    function onEnterSleep() as Void {
        _awake = false;
        _powerKnown = true;
        stop();
        WatchUi.requestUpdate();
    }

    // The frames' timer. Timer.start kills a watch face in low power mode
    // ("Permission Required: Symbol 'start' not available to 'Watch Face'"),
    // so it is called only from onExitSleep, or once the system's own
    // once-a-second updates have shown the face awake (cadence)
    private function start(why as String) as Void {
        if (_running || _still) {
            return;
        }
        var timer = _timer;
        if (timer == null) {
            timer = new Timer.Timer();
            _timer = timer;
        }
        timer.start(method(:tick), PERIOD, true);
        _running = true;
        _lastFrame = System.getTimer();
        _carry = 0;
        log("timer on: " + why);
        WatchUi.requestUpdate();
    }

    private function stop() as Void {
        var timer = _timer;
        if (timer != null && _running) {
            timer.stop();
            log("timer off");
        }
        _running = false;
        _quick = 0;
        settle();
    }

    // A leaf caught mid-flip lands
    private function settle() as Void {
        for (var i = 0; i < 4; i++) {
            var flip = _flips[i];
            if (flip != null) {
                land(i, flip);
            }
        }
        _hold = 0;
    }

    // The timer's tick: a redraw. The frame itself happens in onUpdate, so
    // the flips move only when the watch draws: after a wake it draws
    // nothing for a moment, and a roll that ran on the clock alone went by
    // unseen (the watch's log, 2026-11-07)
    function tick() as Void {
        WatchUi.requestUpdate();
    }

    // A frame: the clock, the schedule, the flips on by the frames the clock
    // has passed since the last drawn frame (none when it came early, four
    // at most: a stall skips motion rather than stretching the roll)
    private function frame() as Void {
        var now = System.getTimer();
        var gap = now - _lastFrame;
        if (_lastFrame == 0 || gap < 0 || gap > 2000) {
            gap = PERIOD;
        }
        _lastFrame = now;
        _carry += gap;
        var frames = _carry / PERIOD;
        _carry -= frames * PERIOD;
        if (frames > MOST_FRAMES) {
            frames = MOST_FRAMES;
        }
        var m = nowMinute();
        if (_shownMinute < 0) {
            _shownMinute = m;                  // the first frame ever: show now, no roll
            _leaves = Roll.digits(m, _is24);
            _dirty = true;
        }
        enqueue(m);
        schedule(frames);
        if (!busy() && _queue.size() == 0 && _hold == 0) {
            // arm the next minute: its push must end on the minute, so it starts a push's length before
            var next = (m + 1) % Roll.MINUTES;
            if (_armed != next) {
                _armed = next;
                _creep = Roll.between(Roll.CREEP_LO, Roll.CREEP_HI);
            }
            if (toBoundary() <= _creep) {
                _shownMinute = next;
                step(Roll.digits(next, _is24), _creep, false);
                _armed = -1;
            }
        }
        advance(frames);
    }

    // The minutes the clock passed that the leaves have not shown or been
    // sent toward: queued to roll, each of them up to four, else now alone
    private function enqueue(m as Number) as Void {
        var last = (_queue.size() > 0) ? _queue[_queue.size() - 1] : _shownMinute;
        var steps = Roll.steps(last, m);
        if (steps.size() == 0) {
            return;
        }
        _queue.addAll(steps);
        if (_queue.size() > Roll.MOST_STEPS) {
            _queue = [m] as Array<Number>;
        }
        _armed = -1;
    }

    // The next queued step starts when the leaves are idle and rested
    private function schedule(frames as Number) as Void {
        if (busy()) {
            return;
        }
        if (_hold > 0) {
            _hold = (_hold > frames) ? _hold - frames : 0;
            return;
        }
        if (_queue.size() > 0) {
            var minute = _queue[0];
            _queue = _queue.slice(1, null);
            _shownMinute = minute;
            step(Roll.digits(minute, _is24), Roll.between(Roll.CATCHUP_LO, Roll.CATCHUP_HI), true);
            _hold = Roll.HOLD;
            note("step to " + minute + ", " + _queue.size() + " more queued");
        }
    }

    (:live)
    private function note(s as String) as Void {
    }

    (:sample)
    private function note(s as String) as Void {
        System.println("clack: " + s);
    }

    // Both builds: the watch writes it to GARMIN/Apps/LOGS/CLACK.TXT
    private function log(s as String) as Void {
        System.println("clack: " + s);
    }

    private function busy() as Boolean {
        for (var i = 0; i < 4; i++) {
            if (_flips[i] != null) {
                return true;
            }
        }
        return false;
    }

    // One minute's flips: the units leaf, the tens leaf with the same push
    // two frames behind, the hour leaves a beat after the minutes slip
    private function step(digits as Array<String>, creep as Float, catchup as Boolean) as Void {
        makeLeaves();
        var slip = Roll.pushFrames(creep);
        var beat = Roll.between(Roll.BEAT_LO.toFloat(), Roll.BEAT_HI.toFloat()).toNumber();
        var hours = catchup ? Roll.HOUR_CATCHUP : Roll.HOUR_CREEP;
        flip(3, digits[3], creep, 0);
        flip(2, digits[2], creep, Roll.TENS_LAG);
        flip(1, digits[1], hours, slip + beat);
        flip(0, digits[0], hours, slip + beat + Roll.TENS_LAG);
    }

    private function flip(i as Number, to as String, creep as Float, delay as Number) as Void {
        if (to.equals(_leaves[i])) {
            return;
        }
        var current = _flips[i];
        if (current != null) {
            land(i, current);
        }
        _flips[i] = new Roll.Flip(_leaves[i], to, Roll.profile(creep, Roll.table()), delay);
        _nextTop[i] = null;                     // built on the flip's first moving frame (advance), so a step
        _nextBot[i] = null;                     // of four leaves spreads its bitmaps over the frames
    }

    // The flips `frames` on; a flip that is over lands
    private function advance(frames as Number) as Void {
        for (var i = 0; i < 4; i++) {
            var f = _flips[i];
            if (f == null) {
                continue;
            }
            f.k += frames;
            // the next leaf's halves, one a frame: the upper as the push
            // begins (in view behind the flap from the moment it lifts),
            // the lower a frame later (in view once the flap passes flat)
            if (f.k >= 0 && _nextTop[i] == null) {
                var t0 = System.getTimer();
                _nextTop[i] = half(i, f.to, true);
                built(System.getTimer() - t0);
            } else if (f.k >= NEXT_BOT_AT && _nextBot[i] == null) {
                var t0 = System.getTimer();
                _nextBot[i] = half(i, f.to, false);
                built(System.getTimer() - t0);
            }
            if (f.done()) {
                land(i, f);
            }
        }
    }

    private function land(i as Number, f as Roll.Flip) as Void {
        _leaves[i] = f.to;
        var top = _nextTop[i];
        _top[i] = (top != null) ? top : half(i, f.to, true);
        var bot = _nextBot[i];
        _bot[i] = (bot != null) ? bot : half(i, f.to, false);
        _nextTop[i] = null;
        _nextBot[i] = null;
        _flips[i] = null;
    }

    // ------------------------------------------------------------ the leaves

    // Every leaf's halves as bitmaps, when something changed them
    private function makeLeaves() as Void {
        if (!_dirty) {
            return;
        }
        for (var i = 0; i < 4; i++) {
            _top[i] = half(i, _leaves[i], true);
            _bot[i] = half(i, _leaves[i], false);
            var f = _flips[i];
            if (f != null) {
                _nextTop[i] = half(i, f.to, true);
                _nextBot[i] = half(i, f.to, false);
            }
        }
        _dirty = false;
    }

    // One half of leaf i showing `digit`: black plastic lit from above, the
    // upper half brightest at its top, the lower half in the upper half's
    // shadow just under the slot; rounded corners; the digit centred on the
    // hinge, so each half shows its share; the lit edge where the upper half
    // ends; zoomed, the caption printed on the lower flap. Under the lamp the
    // plastic and the ink warm by how much of the lamp reaches the leaf.
    private function half(i as Number, digit as String, top as Boolean) as BufferedBitmapReference? {
        var w = _leafW;
        var hh = top ? _hinge - _y0 : _y0 + _leafH - _hinge;
        var ref = Graphics.createBufferedBitmap({:width => w, :height => hh, :colorDepth => DEPTH});
        var b = pool(ref);
        if (b == null) {
            return null;
        }
        var d = b.getDc();
        d.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        d.clear();
        if (d has :setAntiAlias) {
            d.setAntiAlias(true);
        }
        var pal = _night ? NIGHT : DAY;
        var f = _lamp[i];
        var slot = _t[Layout.SLOT];
        var r = _t[Layout.CORNER];
        var c0 = top ? pal[TOP] : pal[SHADE];
        var c1 = top ? pal[MID] : pal[BOT];
        if (_night) {
            c0 = mix(c0, LIT, LIT_SHARE * f);
            c1 = mix(c1, LIT, LIT_SHARE * f);
        }
        var y0 = top ? 0 : slot;
        var y1 = top ? hh - slot : hh;
        var n = y1 - y0;
        // the gradient in bands: the plastic's shades are a few levels apart
        // over the whole half, so a band of BAND rows shows no step; the
        // rounded corners in rows of two. Each band is a handful of calls,
        // and a frame that remakes every half (the first, sunset) has only
        // a few thousand before the watchdog (CLAUDE.md)
        var y = y0;
        while (y < y1) {
            var step = (y < y0 + r || y + BAND > y1 - r) ? 2 : BAND;
            if (y + step > y1) {
                step = y1 - y;
            }
            var t = (y - y0).toFloat() / n;
            if (!top) {
                t = Math.pow(t, 0.6).toFloat();
            }
            var dy = (y < y0 + r) ? (y0 + r - y) : ((y >= y1 - r) ? (y + 1 - (y1 - r)) : 0);
            var inset = (dy > 0) ? (r - Math.sqrt((r * r - dy * dy).toFloat())).toNumber() : 0;
            ink(d, mix(c0, c1, t));
            d.fillRectangle(inset, y, w - 2 * inset, step);
            y += step;
        }
        var ink = _night ? mix(pal[INK], pal[INK_LIT], f) : pal[INK];
        drawDigit(d, digit, w / 2, top ? hh : 0, ink);
        ink(d, pal[EDGE]);
        d.fillRectangle(r / 2, (top ? hh - slot : hh) - 1, w - r, 1);
        if (!top && _zoomed) {
            var text = leafCaption(i);
            if (text != null) {
                spaced(d, text, (w / 2).toFloat(), (_t[Layout.CAPTION_Y] - _hinge).toFloat(), pal[DATE]);
            }
        }
        // the pivot pins, half in each half: a falling flap carries its
        // squashed share over the next leaf's whole one, so they look
        // fixed, and a frame draws no circles
        pinsOn(d, 0, top ? hh : 0, pal);
        return ref;
    }

    // The caption printed on leaf i's lower flap in the zoomed view: the
    // date on the minute tens leaf, the AM/PM flag on the hour units leaf
    private function leafCaption(i as Number) as String? {
        if (i == 2 && _date) {
            return _dateText;
        }
        if (i == 1 && !_is24) {
            return Roll.flag(_shownMinute, false);
        }
        return null;
    }

    // A digit with its ink centred on (cx, hingeY): the bitmap fonts' cells
    // are their ink, Roboto's placed by its bearings (Lib.Ink)
    private function drawDigit(d as Dc, digit as String, cx as Number, hingeY as Number, color as Number) as Void {
        if (digit.equals("")) {
            return;
        }
        ink(d, color);
        if (_bitmapDigits) {
            d.drawText(cx, hingeY, _digitFont, digit, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var face = _face;
        var left = Lib.Ink.left(face, digit, _em);
        var ink = d.getTextWidthInPixels(digit, _digitFont) - left - Lib.Ink.right(face, digit, _em);
        d.drawText(cx - ink / 2 - left, Lib.Ink.top(face, _digitFont, hingeY.toFloat(), _em), _digitFont, digit,
                   Graphics.TEXT_JUSTIFY_LEFT);
    }

    // Small spaced capitals centred on (cx, y)
    private function spaced(d as Dc, text as String, cx as Float, y as Float, color as Number) as Void {
        var track = _t[Layout.SMALL] * TRACK;
        var chars = text.toCharArray();
        var width = d.getTextWidthInPixels(text, _small) + track * ((chars.size() > 1) ? chars.size() - 1 : 0);
        var x = cx - width / 2;
        ink(d, color);
        for (var i = 0; i < chars.size(); i++) {
            var ch = chars[i].toString();
            d.drawText(x, y, _small, ch, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            x += d.getTextWidthInPixels(ch, _small) + track;
        }
    }

    // ------------------------------------------------------------ drawing

    function onUpdate(dc as Dc) as Void {
        var started = System.getTimer();
        cadence(started);
        refresh();
        if (_shownMinute < 0) {
            _shownMinute = nowMinute();
            _leaves = Roll.digits(_shownMinute, _is24);
            _dirty = true;
        }
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        paint(dc, 0x000000);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (!_awake && _burnIn) {
            drawStandby(dc);
        } else {
            if (!_still) {
                frame();
            }
            drawAwake(dc);
        }
        measure(started);
    }

    // The updates' cadence tells the power mode when onEnterSleep and
    // onExitSleep have not: awake, the system redraws the face every second;
    // asleep, once a minute. Three updates in quick succession prove the face
    // awake, when the timer may start; a long gap, before either call has
    // spoken, means asleep
    private function cadence(now as Number) as Void {
        var gap = (_lastUpdate > 0) ? now - _lastUpdate : -1;
        _lastUpdate = now;
        if (gap < 0) {
            return;
        }
        if (gap <= QUICK) {
            if (_quick < QUICK_RUN) {
                _quick++;
            }
        } else {
            _quick = 0;
            if (gap > ASLEEP_GAP && !_powerKnown) {
                _awake = false;
            }
        }
        if (_quick >= QUICK_RUN && !_running) {
            if (!_powerKnown) {
                _awake = true;
            }
            if (_awake) {
                start("cadence");
            }
        }
    }

    // The live build reports each roll to the log: the frames drawn while a
    // leaf moved, the time they took, the longest draw, the longest build of
    // a leaf's next halves
    (:live) private var _rollFrames as Number = 0;
    (:live) private var _rollStart as Number = 0;
    (:live) private var _rollDrawMax as Number = 0;
    (:live) private var _rollBuildMax as Number = 0;

    (:live)
    private function measure(started as Number) as Void {
        var draw = System.getTimer() - started;
        if (busy()) {
            if (_rollFrames == 0) {
                _rollStart = started;
                _rollDrawMax = 0;
            }
            _rollFrames++;
            if (draw > _rollDrawMax) {
                _rollDrawMax = draw;
            }
        } else if (_rollFrames > 0) {
            log("roll: " + _rollFrames + " frames in " + (started - _rollStart) + " ms, draw max " + _rollDrawMax
                + " ms, halves max " + _rollBuildMax + " ms");
            _rollFrames = 0;
            _rollBuildMax = 0;
        }
    }

    (:live)
    private function built(ms as Number) as Void {
        if (ms > _rollBuildMax) {
            _rollBuildMax = ms;
        }
    }

    (:sample)
    private function built(ms as Number) as Void {
    }

    // The screenshot build reports the frame rate and the draw time every
    // 64 frames, as the spike did (designs/clack/spike)
    (:sample) private var _frames as Number = 0;
    (:sample) private var _last as Number = 0;
    (:sample) private var _gapSum as Number = 0;
    (:sample) private var _gapMax as Number = 0;
    (:sample) private var _drawSum as Number = 0;
    (:sample) private var _drawMax as Number = 0;
    (:sample) private var _moveMax as Number = 0;
    (:sample) private var _moving as Number = 0;

    (:sample)
    private function measure(started as Number) as Void {
        var now = System.getTimer();
        var draw = now - started;
        if (_last > 0) {
            var gap = started - _last;
            _gapSum += gap;
            _gapMax = (gap > _gapMax) ? gap : _gapMax;
        }
        _last = started;
        _drawSum += draw;
        _drawMax = (draw > _drawMax) ? draw : _drawMax;
        if (busy()) {
            _moving++;
            _moveMax = (draw > _moveMax) ? draw : _moveMax;
        }
        _frames++;
        if (_frames % 64 == 0) {
            System.println("clack: " + _frames + " frames, gap avg/max " + (_gapSum / 63) + "/" + _gapMax + " ms, draw avg/max "
                           + (_drawSum / 64) + "/" + _drawMax + " ms; " + _moving + " moving, their draw max " + _moveMax + " ms");
            _gapSum = 0;
            _gapMax = 0;
            _drawSum = 0;
            _drawMax = 0;
            _moving = 0;
            _moveMax = 0;
        }
    }

    // The face awake: the lamp's pool, the stacks' edges, each leaf whole or
    // mid-flip, the pins, and in the original view the captions under the leaves
    private function drawAwake(dc as Dc) as Void {
        makeLeaves();
        var pal = _night ? NIGHT : DAY;
        if (_night) {
            if (_spill == null && !_noSpill) {
                var ref = Graphics.createBufferedBitmap({:width => _w, :height => _h, :colorDepth => DEPTH});
                var fresh = pool(ref);
                if (fresh != null) {
                    spill(fresh.getDc());
                    _spill = ref;
                } else {
                    _noSpill = true;
                }
            }
            var spill = _spill;
            var glow = (spill != null) ? pool(spill) : null;
            if (glow != null) {
                dc.drawBitmap(0, 0, glow);
            }
        }
        if (!_zoomed) {
            // the captions under the leaves, before any fill tool is set
            var y = _t[Layout.CAPTION_Y].toFloat();
            if (_date) {
                spaced(dc, _dateText, ((_cx[2] + _cx[3]) / 2).toFloat(), y, pal[DATE]);
            }
            if (!_is24) {
                spaced(dc, Roll.flag(_shownMinute, false), ((_cx[0] + _cx[1]) / 2).toFloat(), y, pal[DATE]);
            }
        }
        if (_stacks) {
            ink(dc, pal[STACK]);
            for (var i = 0; i < 4; i++) {
                stack(dc, i);
            }
        }
        for (var i = 0; i < 4; i++) {
            var f = _flips[i];
            var topRef = _top[i];
            var botRef = _bot[i];
            var top = (topRef != null) ? pool(topRef) : null;
            var bot = (botRef != null) ? pool(botRef) : null;
            if (top == null || bot == null) {
                flatLeaf(dc, i, pal);              // the pool is short: the leaf plain, no flip
            } else if (f == null || f.angle() <= 0.0) {
                dc.drawBitmap(_x[i], _y0, top);
                dc.drawBitmap(_x[i], _hinge, bot);
            } else {
                flapFrame(dc, i, f, top, bot, pal);
            }
        }
    }

    // Leaf i mid-flip (preview_clack.flap_frame): the next leaf whole, in
    // view behind the flap from the moment it lifts; the current lower half
    // until the flap's back lands on it; the flap foreshortened by the cosine
    // of its angle, turning from the lamp as it falls, its back with a shadow
    // under it as it lands; the edge of the flap a line
    private function flapFrame(dc as Dc, i as Number, f as Roll.Flip, top as BufferedBitmap, bot as BufferedBitmap,
                               pal as Array<Number>) as Void {
        var nextTopRef = _nextTop[i];
        var nextTop = (nextTopRef != null) ? pool(nextTopRef) : null;
        if (nextTop == null) {
            dc.drawBitmap(_x[i], _y0, top);
            dc.drawBitmap(_x[i], _hinge, bot);
            return;
        }
        var theta = f.angle();
        // the next lower half is under the current one until the flap
        // passes flat; built a frame after the upper (advance), or here
        // when a stall skipped that frame
        var nextBot = null as BufferedBitmap?;
        if (theta > 90.0) {
            var nextBotRef = _nextBot[i];
            if (nextBotRef == null) {
                nextBotRef = half(i, f.to, false);
                _nextBot[i] = nextBotRef;
            }
            nextBot = (nextBotRef != null) ? pool(nextBotRef) : null;
            if (nextBot == null) {
                dc.drawBitmap(_x[i], _y0, top);
                dc.drawBitmap(_x[i], _hinge, bot);
                return;
            }
        }
        var x = _x[i];
        var w = _leafW;
        var rad = Math.toRadians(theta);
        var c = Math.cos(rad);
        var s = Math.sin(rad);
        var hT = _hinge - _y0;
        var hB = _y0 + _leafH - _hinge;
        dc.drawBitmap(x, _y0, nextTop);
        dc.drawBitmap(x, _hinge, bot);
        // the darkening: drawBitmap2's tint multiplies the bitmap as it is
        // drawn, in the one call that also foreshortens it; without
        // drawBitmap2, a translucent fill over the flap by the fill tool
        var tint = _tint;
        if (theta < 90.0) {
            var fh = (hT * c).toNumber();
            if (fh < 1) {
                fh = 1;
            }
            var dark = ((_night ? DARK_NIGHT : DARK_DAY) * s).toFloat();
            if (tint) {
                var xf = _xf;
                if (xf == null) {
                    xf = new Graphics.AffineTransform();
                    _xf = xf;
                }
                xf.setToScale(1.0, fh.toFloat() / hT);
                dc.drawBitmap2(x, _hinge - fh, top, {:tintColor => grey(1.0 - dark), :transform => xf});
            } else {
                dc.drawScaledBitmap(x, _hinge - fh, w, fh, top);
                var alpha = (dark * 255).toNumber();
                if (alpha > 0) {
                    shade(dc, alpha);
                    dc.fillRectangle(x, _hinge - fh, w, fh);
                }
            }
            if (theta > 15.0) {
                dc.setColor(scale(pal[EDGE], s.toFloat()), Graphics.COLOR_TRANSPARENT);
                dc.drawLine(x, _hinge - fh, x + w, _hinge - fh);
            }
        } else if (theta > 90.0) {
            var fh = (hB * -c).toNumber();
            if (fh < 1) {
                fh = 1;
            }
            var t = (theta - 90.0) / 90.0;
            dc.drawScaledBitmap(x, _hinge, w, fh, nextBot as BufferedBitmap);
            if (_hinge + fh + 1 < _y0 + _leafH) {
                var sh = (0.12 * _leafH * (1.0 - t) + 0.01 * _leafH).toNumber();
                var a0 = 0.7 * (1.0 - t) + 0.1;
                var bands = 4;
                var band = sh / bands;
                if (band < 1) {
                    band = 1;
                }
                for (var k = 0; k < bands; k++) {
                    var a = (a0 * (1.0 - k.toFloat() / bands)).toFloat();
                    var by = fh + k * band;            // the band's top in the lower half
                    if (tint) {
                        var bh = (by + band > hB) ? hB - by : band;
                        if (bh > 0) {
                            dc.drawBitmap2(x, _hinge + by, bot, {:bitmapY => by, :bitmapHeight => bh, :tintColor => grey(1.0 - a)});
                        }
                    } else {
                        shade(dc, (a * 255).toNumber());
                        dc.fillRectangle(x, _hinge + by, w, band);
                    }
                }
            }
            dc.setColor(pal[EDGE], Graphics.COLOR_TRANSPARENT);
            dc.drawLine(x, _hinge + fh, x + w, _hinge + fh);
        } else {
            paint(dc, pal[EDGE]);
            dc.fillRectangle(x, _hinge - 1, w, 2);
        }
    }

    // The pivot pins at the slot's ends, with a highlight, on a leaf whose
    // left edge is x and hinge y: a half's bitmap (half) or the screen
    // (flatLeaf)
    private function pinsOn(d as Dc, x as Number, y as Number, pal as Array<Number>) as Void {
        var r = _t[Layout.PIN];
        var xs = [x + r * 6 / 5, x + _leafW - r * 6 / 5] as Array<Number>;
        for (var k = 0; k < 2; k++) {
            paint(d, pal[PIN]);
            d.fillCircle(xs[k], y, r);
            paint(d, pal[PIN_HL]);
            d.fillCircle(xs[k] - r * 15 / 100, y - r * 40 / 100, r * 40 / 100);
        }
    }

    // Leaf i with no bitmaps (the graphics pool short): plain plastic, the
    // digit on it, the slot; it changes with the minute but cannot flip
    private function flatLeaf(dc as Dc, i as Number, pal as Array<Number>) as Void {
        var x = _x[i];
        var w = _leafW;
        var f = _lamp[i];
        var up = _night ? mix(pal[MID], LIT, LIT_SHARE * f) : pal[MID];
        var down = _night ? mix(pal[BOT], LIT, LIT_SHARE * f) : pal[BOT];
        paint(dc, up);
        dc.fillRectangle(x, _y0, w, _hinge - _y0);
        paint(dc, down);
        dc.fillRectangle(x, _hinge, w, _y0 + _leafH - _hinge);
        var ink = _night ? mix(pal[INK], pal[INK_LIT], f) : pal[INK];
        drawDigit(dc, _leaves[i], x + w / 2, _hinge, ink);
        paint(dc, pal[EDGE]);
        dc.fillRectangle(x, _hinge - 1, w, 2);
        pinsOn(dc, x, _hinge, pal);
    }

    // The bitmap a reference holds, allocated in the graphics pool on the
    // first get(): null when the pool has no room for it
    private function pool(ref as BufferedBitmapReference) as BufferedBitmap? {
        try {
            var b = ref.get();
            if (b instanceof BufferedBitmap) {
                return b;
            }
        } catch (e instanceof Lang.Exception) {
            log("graphics pool: " + e.getErrorMessage());
        }
        return null;
    }

    // The colour for the next fills and text: setColor, the watch's fast
    // path (24-bit colours; its alpha the watch draws opaque)
    private function ink(d as Dc, color as Number) as Void {
        d.setColor(color, Graphics.COLOR_TRANSPARENT);
    }

    // An opaque colour for the next fills on the screen: the fill tool too,
    // which once set (shade) takes precedence over setColor
    // for every fill. The screen's opaque fills are small (the pins, the
    // slot); the leaves' own fills happen on their bitmaps, through ink
    private function paint(dc as Dc, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (dc has :setFill) {
            dc.setFill(Graphics.createColor(255, (color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF));
        }
    }

    // Translucent black for the next fills: the fill tool (setFill takes
    // 0xAARRGGBB, the documented translucent fill). Costly on the watch, so
    // only where drawBitmap2's tint cannot darken instead
    private function shade(dc as Dc, alpha as Number) as Void {
        dc.setFill(Graphics.createColor(alpha, 0, 0, 0));
    }

    // Grey at f of white, opaque, as drawBitmap2's tint: it multiplies the
    // bitmap's colours, so this darkens a flap by 1 - f
    private function grey(f as Float) as Number {
        var g = clamp((f * 255.0).toNumber());
        return Graphics.createColor(255, g, g, g);
    }

    // Leaf i's stack edges (stackLines), in the colour set
    private function stack(dc as Dc, i as Number) as Void {
        var lines = _stackLines[i];
        for (var j = 0; j < lines.size(); j += 3) {
            dc.drawLine(lines[j], lines[j + 1], lines[j + 2], lines[j + 1]);
        }
    }

    // The lamp's pool on the black after sunset: a radial falloff from the
    // upper left, out of frame, as rings from the outside in
    private function spill(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var cx = _w * 4 / 100;
        var cy = -_w * 6 / 100;
        var radius = _w * 75 / 100;
        for (var k = SPILL_RINGS; k >= 1; k--) {
            var r = radius * k / SPILL_RINGS;
            var t = 1.0 - k.toFloat() / SPILL_RINGS;
            var share = Math.pow(t, 2.2).toFloat() * SPILL_SHARE;
            ink(dc, scale(SPILL, share));
            dc.fillCircle(cx, cy, r);
        }
    }

    // Standby: the lamp turned down. The digits as edges, the hour leaves'
    // brighter (and their upper flaps filled, eroded, where the budget allows:
    // the original view and zoomed Roboto), the hinge across the face,
    // shifted each minute (Lib.Aod.offset), the captions off
    private function drawStandby(dc as Dc) as Void {
        var off = Lib.Aod.offset(System.getClockTime().min, AOD_STEP * _w / 454);
        var dx = off[0];
        var dy = off[1];
        var col = _night ? AOD_NIGHT : AOD_DAY;
        var dim = scale(col, 0.8);
        var fill = _t[Layout.AOD_FILL] == 1;
        var standby = _standbyFont;
        var digits = Roll.digits(nowMinute(), _is24);     // the clock's, not the leaves': those roll to it on the wake
        for (var i = 0; i < 4; i++) {
            var digit = digits[i];
            if (digit.equals("")) {
                continue;
            }
            var x = _cx[i] + dx;
            var y = _hinge + dy;
            var hours = i < 2;
            if (standby != null) {
                var text = digit;
                if (hours && fill) {
                    var n = digit.toNumber();
                    text = (65 + ((n != null) ? n : 0)).toChar().toString();   // 'A' to 'J': the filled upper flap
                }
                ink(dc, hours ? col : dim);
                dc.drawText(x, y, standby, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                continue;
            }
            // the original view: Roboto, the vector font
            var face = _face;
            var left = Lib.Ink.left(face, digit, _em);
            var ink = dc.getTextWidthInPixels(digit, _digitFont) - left - Lib.Ink.right(face, digit, _em);
            var tx = x - ink / 2 - left;
            var ty = Lib.Ink.top(face, _digitFont, y.toFloat(), _em);
            if (hours) {
                dc.setClip(0, 0, _w, y);
                dc.setColor(col, Graphics.COLOR_TRANSPARENT);
                dc.drawText(tx, ty, _digitFont, digit, Graphics.TEXT_JUSTIFY_LEFT);
                dc.setClip(0, y, _w, _h - y);
                Lib.Aod.drawHollowText(dc, tx, ty, _digitFont, digit, dim, Graphics.TEXT_JUSTIFY_LEFT);
                dc.clearClip();
            } else {
                Lib.Aod.drawHollowText(dc, tx, ty, _digitFont, digit, dim, Graphics.TEXT_JUSTIFY_LEFT);
            }
        }
        dc.setColor(scale(col, 0.5), Graphics.COLOR_TRANSPARENT);
        dc.drawLine(0, _hinge + dy + 1, _w, _hinge + dy + 1);
    }

    // ------------------------------------------------------------ colours

    // c0 toward c1 by t
    private function mix(c0 as Number, c1 as Number, t as Float) as Number {
        var r = (((c0 >> 16) & 0xFF) + (((c1 >> 16) & 0xFF) - ((c0 >> 16) & 0xFF)) * t).toNumber();
        var g = (((c0 >> 8) & 0xFF) + (((c1 >> 8) & 0xFF) - ((c0 >> 8) & 0xFF)) * t).toNumber();
        var b = ((c0 & 0xFF) + ((c1 & 0xFF) - (c0 & 0xFF)) * t).toNumber();
        return (clamp(r) << 16) | (clamp(g) << 8) | clamp(b);
    }

    private function scale(color as Number, f as Float) as Number {
        return mix(0x000000, color, f);
    }

    private function clamp(v as Number) as Number {
        return (v < 0) ? 0 : ((v > 255) ? 255 : v);
    }
}
