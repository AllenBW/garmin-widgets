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
// The roll: after a wake the face draws at twenty frames a second (a timer)
// and the leaves flip as the mechanism does (Roll, Drops): the push off the
// stop, the fall, the bounce; the next leaf in view behind the falling flap
// from the moment it lifts, the flap's back bringing the new lower half
// down. A wake rolls every missed minute up to four. Standby cannot animate:
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
    private const TRACK = 0.10;                  // the captions' letter spacing, of their em
    private const PERIOD = 1000 / Roll.FPS;      // ms between frames

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

    // Fonts
    private var _digitFont as FontType = Graphics.FONT_NUMBER_HOT;
    private var _bitmapDigits as Boolean = false;
    private var _standbyFont as FontType? = null;
    private var _small as FontType = Graphics.FONT_XTINY;
    private var _em as Float = 0.0;              // Roboto's em, when the digits are the vector font
    private var _laidOut as Boolean = false;

    private var _awake as Boolean = true;
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
    private var _lastSec as Number = -1;
    private var _secStart as Number = 0;

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
        makeFonts();
        _dirty = true;
    }

    private function makeFonts() as Void {
        var t = _t;
        var font = t[Layout.FONT];
        if (font == Layout.ROBOTO) {
            _em = Lib.Ink.em(Lib.Ink.CONDENSED_BOLD, t[Layout.DIGIT].toFloat());
            _digitFont = Lib.Ink.font(Lib.Ink.CONDENSED_BOLD, _em, Graphics.FONT_NUMBER_HOT);
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
            schedule();
            advance();
            frames++;
        }
        return frames;
    }

    function shows() as Array<String> {
        return _leaves;
    }

    function setAwake(awake as Boolean) as Void {
        _awake = awake;
        _burnIn = true;
    }

    // ------------------------------------------------------------ the roll

    function onShow() as Void {
        start();
    }

    function onHide() as Void {
        stop();
    }

    function onExitSleep() as Void {
        _awake = true;
        _minute = -1;
        start();
    }

    function onEnterSleep() as Void {
        _awake = false;
        stop();
        WatchUi.requestUpdate();
    }

    private function start() as Void {
        if (_running) {
            return;
        }
        var timer = _timer;
        if (timer == null) {
            timer = new Timer.Timer();
            _timer = timer;
        }
        timer.start(method(:tick), PERIOD, true);
        _running = true;
        WatchUi.requestUpdate();
    }

    private function stop() as Void {
        var timer = _timer;
        if (timer != null && _running) {
            timer.stop();
        }
        _running = false;
        // a leaf caught mid-flip lands
        for (var i = 0; i < 4; i++) {
            var flip = _flips[i];
            if (flip != null) {
                land(i, flip);
            }
        }
        _hold = 0;
    }

    // A frame: the clock, the schedule, the flips a step on, then a redraw
    function tick() as Void {
        refresh();
        var m = nowMinute();
        if (_shownMinute < 0) {
            _shownMinute = m;                  // the first frame ever: show now, no roll
            _leaves = Roll.digits(m, _is24);
            _dirty = true;
        }
        enqueue(m);
        schedule();
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
        advance();
        WatchUi.requestUpdate();
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
    private function schedule() as Void {
        if (busy()) {
            return;
        }
        if (_hold > 0) {
            _hold--;
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

    // The flips a frame on; a flip that is over lands
    private function advance() as Void {
        for (var i = 0; i < 4; i++) {
            var f = _flips[i];
            if (f == null) {
                continue;
            }
            f.k++;
            if (f.k >= 0 && _nextTop[i] == null) {
                _nextTop[i] = half(i, f.to, true);
                _nextBot[i] = half(i, f.to, false);
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
    private function half(i as Number, digit as String, top as Boolean) as BufferedBitmapReference {
        var w = _leafW;
        var hh = top ? _hinge - _y0 : _y0 + _leafH - _hinge;
        var ref = Graphics.createBufferedBitmap({:width => w, :height => hh, :colorDepth => DEPTH});
        var b = ref.get() as BufferedBitmap;
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
        for (var y = y0; y < y1; y += 2) {
            var t = (y - y0).toFloat() / n;
            if (!top) {
                t = Math.pow(t, 0.6).toFloat();
            }
            var dy = (y < y0 + r) ? (y0 + r - y) : ((y >= y1 - r) ? (y + 1 - (y1 - r)) : 0);
            var inset = (dy > 0) ? (r - Math.sqrt((r * r - dy * dy).toFloat())).toNumber() : 0;
            d.setColor(mix(c0, c1, t), Graphics.COLOR_TRANSPARENT);
            d.fillRectangle(inset, y, w - 2 * inset, 2);
        }
        var ink = _night ? mix(pal[INK], pal[INK_LIT], f) : pal[INK];
        drawDigit(d, digit, w / 2, top ? hh : 0, ink);
        d.setColor(pal[EDGE], Graphics.COLOR_TRANSPARENT);
        d.fillRectangle(r / 2, (top ? hh - slot : hh) - 1, w - r, 1);
        if (!top && _zoomed) {
            var text = leafCaption(i);
            if (text != null) {
                spaced(d, text, (w / 2).toFloat(), (_t[Layout.CAPTION_Y] - _hinge).toFloat(), pal[DATE]);
            }
        }
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
        d.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (_bitmapDigits) {
            d.drawText(cx, hingeY, _digitFont, digit, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }
        var face = Lib.Ink.CONDENSED_BOLD;
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
        d.setColor(color, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < chars.size(); i++) {
            var ch = chars[i].toString();
            d.drawText(x, y, _small, ch, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            x += d.getTextWidthInPixels(ch, _small) + track;
        }
    }

    // ------------------------------------------------------------ drawing

    function onUpdate(dc as Dc) as Void {
        var started = System.getTimer();
        refresh();
        if (_shownMinute < 0) {
            _shownMinute = nowMinute();
            _leaves = Roll.digits(_shownMinute, _is24);
            _dirty = true;
        }
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (!_awake && _burnIn) {
            drawStandby(dc);
        } else {
            drawAwake(dc);
        }
        measure(started);
    }

    (:live)
    private function measure(started as Number) as Void {
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
            var spill = _spill;
            if (spill == null) {
                spill = Graphics.createBufferedBitmap({:width => _w, :height => _h, :colorDepth => DEPTH});
                spill((spill.get() as BufferedBitmap).getDc());
                _spill = spill;
            }
            dc.drawBitmap(0, 0, spill.get() as BufferedBitmap);
        }
        for (var i = 0; i < 4; i++) {
            stack(dc, i, pal);
            var f = _flips[i];
            var topRef = _top[i];
            var botRef = _bot[i];
            if (topRef == null || botRef == null) {
                continue;
            }
            var top = topRef.get() as BufferedBitmap;
            var bot = botRef.get() as BufferedBitmap;
            if (f == null || f.angle() <= 0.0) {
                dc.drawBitmap(_x[i], _y0, top);
                dc.drawBitmap(_x[i], _hinge, bot);
            } else {
                flapFrame(dc, i, f, top, bot, pal);
            }
            pins(dc, i, pal);
        }
        if (!_zoomed) {
            var y = _t[Layout.CAPTION_Y].toFloat();
            if (_date) {
                spaced(dc, _dateText, ((_cx[2] + _cx[3]) / 2).toFloat(), y, pal[DATE]);
            }
            if (!_is24) {
                spaced(dc, Roll.flag(_shownMinute, false), ((_cx[0] + _cx[1]) / 2).toFloat(), y, pal[DATE]);
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
        var nextBotRef = _nextBot[i];
        if (nextTopRef == null || nextBotRef == null) {
            dc.drawBitmap(_x[i], _y0, top);
            dc.drawBitmap(_x[i], _hinge, bot);
            return;
        }
        var nextTop = nextTopRef.get() as BufferedBitmap;
        var nextBot = nextBotRef.get() as BufferedBitmap;
        var x = _x[i];
        var w = _leafW;
        var theta = f.angle();
        var rad = Math.toRadians(theta);
        var c = Math.cos(rad);
        var s = Math.sin(rad);
        var hT = _hinge - _y0;
        var hB = _y0 + _leafH - _hinge;
        dc.drawBitmap(x, _y0, nextTop);
        dc.drawBitmap(x, _hinge, nextBot);
        dc.drawBitmap(x, _hinge, bot);
        if (theta < 90.0) {
            var fh = (hT * c).toNumber();
            if (fh < 1) {
                fh = 1;
            }
            dc.drawScaledBitmap(x, _hinge - fh, w, fh, top);
            var alpha = ((_night ? DARK_NIGHT : DARK_DAY) * s * 255).toNumber();
            dc.setColor(Graphics.createColor(alpha, 0, 0, 0), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x, _hinge - fh, w, fh);
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
            dc.drawScaledBitmap(x, _hinge, w, fh, nextBot);
            if (_hinge + fh + 1 < _y0 + _leafH) {
                var sh = (0.12 * _leafH * (1.0 - t) + 0.01 * _leafH).toNumber();
                var a0 = 0.7 * (1.0 - t) + 0.1;
                var bands = 4;
                var band = sh / bands;
                if (band < 1) {
                    band = 1;
                }
                for (var k = 0; k < bands; k++) {
                    var alpha = (a0 * (1.0 - k.toFloat() / bands) * 255).toNumber();
                    dc.setColor(Graphics.createColor(alpha, 0, 0, 0), Graphics.COLOR_TRANSPARENT);
                    dc.fillRectangle(x, _hinge + fh + k * band, w, band);
                }
            }
            dc.setColor(pal[EDGE], Graphics.COLOR_TRANSPARENT);
            dc.drawLine(x, _hinge + fh, x + w, _hinge + fh);
        } else {
            dc.setColor(pal[EDGE], Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(x, _hinge - 1, w, 2);
        }
    }

    // The pivot pins at the slot's ends, with a highlight
    private function pins(dc as Dc, i as Number, pal as Array<Number>) as Void {
        var r = _t[Layout.PIN];
        var y = _hinge;
        var xs = [_x[i] + r * 6 / 5, _x[i] + _leafW - r * 6 / 5] as Array<Number>;
        for (var k = 0; k < 2; k++) {
            dc.setColor(pal[PIN], Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(xs[k], y, r);
            dc.setColor(pal[PIN_HL], Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(xs[k] - r * 15 / 100, y - r * 40 / 100, r * 40 / 100);
        }
    }

    // The leaves yet to fall and the fallen ones: their edges above and
    // below the leaf (off the screen in the zoomed view)
    private function stack(dc as Dc, i as Number, pal as Array<Number>) as Void {
        var step = _t[Layout.STEP];
        var inset = _w * 4 / 1000;
        var r = _t[Layout.CORNER];
        dc.setColor(pal[STACK], Graphics.COLOR_TRANSPARENT);
        for (var k = 1; k <= 3; k++) {
            var x0 = _x[i] + inset * k + r * 2 / 5;
            var x1 = _x[i] + _leafW - inset * k - r * 2 / 5;
            var below = _y0 + _leafH + step * k;
            if (below < _h) {
                dc.drawLine(x0, below, x1, below);
            }
            var above = _y0 - step * k;
            if (k <= 2 && above >= 0) {
                dc.drawLine(x0, above, x1, above);
            }
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
            dc.setColor(scale(SPILL, share), Graphics.COLOR_TRANSPARENT);
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
        for (var i = 0; i < 4; i++) {
            var digit = _leaves[i];
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
                dc.setColor(hours ? col : dim, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x, y, standby, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
                continue;
            }
            // the original view: Roboto, the vector font
            var face = Lib.Ink.CONDENSED_BOLD;
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
