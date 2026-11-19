import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// One tube of a strike: its two pictures and where they go, whose colour it
// takes, and its clock (Lib.Strike)
class SignTube {
    var halo as WatchUi.BitmapResource;
    var core as WatchUi.BitmapResource;
    var haloX as Number;
    var haloY as Number;
    var coreX as Number;
    var coreY as Number;
    var color as Number;       // 0 the hours', 1 the minutes', 2 the details'
    var seed as Number;
    var from as Number;        // the motion clock when it is struck, or began to die
    var dying as Boolean;
    var corePercent as Number = 0;
    var haloPercent as Number = 0;

    function initialize(halo_ as WatchUi.BitmapResource, core_ as WatchUi.BitmapResource, haloX_ as Number, haloY_ as Number,
                        coreX_ as Number, coreY_ as Number, color_ as Number, seed_ as Number, from_ as Number, dying_ as Boolean) {
        halo = halo_;
        core = core_;
        haloX = haloX_;
        haloY = haloY_;
        coreX = coreX_;
        coreY = coreY_;
        color = color_;
        seed = seed_;
        from = from_;
        dying = dying_;
    }
}

// Sign: the time as a neon sign. The numerals are bent from one tube each,
// the hours over the minutes, set left of centre against open black; the
// date sits to the right in thin tube. Nothing is drawn that is not a tube.
//
// A lit tube is a pale core and a halo in the tube's colour. The watch
// cannot blur, so each numeral and letter is a picture of two grey masks,
// its halo and its core (designs/gen_sign.py), which drawBitmap2 tints: the
// halo with the tube's colour, the core with Lib.Neon.core of it. Every
// colour comes from Lib.Neon, so all sixteen tubes, the seven sets and the
// looks work with the one set of pictures. The lit face is drawn into a
// bitmap when the minute or the look changes, and each update is one blit.
//
// The strike (Lib.Strike): on a wake, a numeral that changed since the face
// was last seen comes on as a neon tube does, a stutter or two and a glow
// that spreads, in under a second; the others stay steady, and so does the
// date unless the day changed. When the minute turns while the face is
// awake the old numeral dies with a short flicker and the new one is struck
// in its place. While a strike runs the steady tubes stay in the bitmap and
// the struck ones are drawn each frame from the same pictures with their
// tints dimmed; the frames come from Lib.Motion's pacer, which starts a
// timer only once the face is known to be awake and stops it the moment
// everything has settled.
//
// Holding the screen steps through the looks (Lib.Look), the look's name
// standing where the date is for a moment, bent from the same tube.
//
// Standby (always-on): the numerals alone as thin tubes with no halo
// (a font, designs/gen_sign.py), shifted each minute; under 4 % of the
// screen lit (designs/preview_sign.py prints it). It never animates.
class SignView extends WatchUi.WatchFace {

    private const FRAME = 50;          // ms between a strike's frames
    private const MOST_FRAMES = 4;     // a stall moves the strike on by this many at most
    private const DATE = 4;            // the date's place among the tubes: after the four numerals

    private var _row as Number = 0;                   // Layout's row for this screen
    private var _colors as Array<Number> = [0, 0, 0] as Array<Number>;   // the hours', the minutes', the details'
    private var _look as Number = Lib.Look.YOURS;
    private var _day as Number = 0;                   // the daily look's day
    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;
    private var _dirty as Boolean = true;
    private var _titled as Boolean = false;
    private var _stamp as Number = -1;                // the moment the bitmap shows
    private var _bitmap as Graphics.BufferedBitmap?;  // held itself: the pool purges a bitmap nothing holds
    private var _thin as WatchUi.FontResource?;
    private var _fixed as Array<Number>?;             // the tests' moment
    private var _fixed24 as Boolean = true;

    // The strike
    private var _pacer as Lib.Motion.Pacer;
    private var _motion as Number = 0;                // ms of drawn frames: the strike's clock
    private var _step as Number?;                     // the tests' frame, in ms
    private var _shown as Array<String>?;             // the hours, the minutes and the date as last drawn lit
    private var _seen as Array<String>?;              // and as they stood when the face last slept
    private var _waking as Boolean = false;
    private var _tubes as Array<SignTube> = [] as Array<SignTube>;   // the tubes being struck or dying
    private var _hidden as Array<Boolean> = [false, false, false, false, false] as Array<Boolean>;   // left out of the bitmap
    private var _until as Number = 0;                 // the motion clock when the last of them settles
    private var _frames as Number = 0;                // the strike's frames so far, their drawing time and the slowest
    private var _drawn as Number = 0;
    private var _slowest as Number = 0;
    private var _since as Number = 0;

    function initialize() {
        WatchFace.initialize();
        _burnIn = Lib.Aod.required();
        _pacer = new Lib.Motion.Pacer(FRAME, MOST_FRAMES);
        reloadSettings();
    }

    function reloadSettings() as Void {
        _look = Lib.Look.mode();
        _colors = Lib.Neon.colors(_look);
        _day = Lib.Look.today();
        _dirty = true;
    }

    function onLayout(dc as Dc) as Void {
        _row = Layout.row(dc.getWidth());
        _thin = WatchUi.loadResource(Rez.Fonts.Thin) as WatchUi.FontResource;
        _bitmap = null;
        try {
            _bitmap = Graphics.createBufferedBitmap({:width => dc.getWidth(), :height => dc.getHeight()}).get() as Graphics.BufferedBitmap;
        } catch (e) {
            _bitmap = null;     // no room in the graphics pool: the face is drawn straight to the screen, and nothing strikes
        }
        _dirty = true;
    }

    // ------------------------------------------------------------ state

    // The moment: hour, minute, weekday (1 is Sunday), day of the month
    (:live)
    private function now() as Array<Number> {
        var clock = System.getClockTime();
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        return [clock.hour, clock.min, info.day_of_week as Number, info.day as Number] as Array<Number>;
    }

    // The screenshots' moment (sample.jungle): 10:37 on Tuesday the 15th
    (:sample)
    private function now() as Array<Number> {
        return [10, 37, 3, 15] as Array<Number>;
    }

    // Whether the face is held in standby (sample-standby.jungle: low power
    // mode can't be driven from a script)
    (:free)
    private function held() as Boolean {
        return false;
    }

    (:held)
    private function held() as Boolean {
        return true;
    }

    // A strike held at one moment for a capture (sample-strike-1.jungle to
    // -4): the ms since the face woke having last shown 09:26, so all four
    // numerals are struck. -1 in every other build.
    (:still)
    private function strikeAt() as Number {
        return -1;
    }

    (:strike1)
    private function strikeAt() as Number {
        return 100;
    }

    (:strike2)
    private function strikeAt() as Number {
        return 250;
    }

    (:strike3)
    private function strikeAt() as Number {
        return 420;
    }

    (:strike4)
    private function strikeAt() as Number {
        return 600;
    }

    // For the tests: a fixed moment, three tubes of any colour, the power
    // mode, and frames of a set length in place of the timer's
    function setMoment(moment as Array<Number>, is24 as Boolean) as Void {
        _fixed = moment;
        _fixed24 = is24;
    }

    function setColors(colors as Array<Number>) as Void {
        _colors = colors;
        _dirty = true;
    }

    function setAwake(awake as Boolean) as Void {
        _burnIn = true;
        if (awake) {
            onExitSleep();
        } else {
            onEnterSleep();
        }
    }

    function setFrame(ms as Number) as Void {
        _pacer.setStill();
        _step = ms;
    }

    // The tubes being struck or dying now
    function striking() as Number {
        return _tubes.size();
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
        _seen = _shown;         // what was last seen lit: what differs on the next wake is struck
        settle();
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _awake = true;
        _waking = true;
        _pacer.onExitSleep();
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------ drawing

    function onUpdate(dc as Dc) as Void {
        if (_look == Lib.Look.DAILY && Lib.Look.today() != _day) {
            reloadSettings();     // a new day, a new set
        }
        var started = System.getTimer();
        var step = _pacer.step(started);
        var frame = _step;
        _motion += (frame != null) ? frame : step;
        var fixed = _fixed;
        var moment = (fixed != null) ? fixed : now();
        var is24 = (fixed != null) ? _fixed24 : System.getDeviceSettings().is24Hour;
        var hours = SignText.hours(moment[0], is24);
        var minutes = SignText.minutes(moment[1]);
        if (held() || (!_awake && _burnIn)) {
            standby(dc, hours, minutes, moment[1]);
            _pacer.want(false);
            return;
        }
        var texts = [hours, minutes, SignText.date(moment[2], moment[3])] as Array<String>;
        var titled = _awake && Lib.Look.shown();
        var stamp = (((moment[3] * 8 + moment[2]) * 24 + moment[0]) * 60 + moment[1]) * 2 + (is24 ? 1 : 0);
        var bitmap = _bitmap;
        if (bitmap == null) {
            lit(dc, texts, titled);
            _pacer.want(false);
            return;
        }

        // What changed: since the face was last seen, on a wake; since the
        // last frame, while awake. A strike needs frames, so nothing is
        // struck until the face is known to be awake.
        var hold = strikeAt();
        if (hold >= 0) {
            _motion = 0;
            begin(["09", "26", texts[2]] as Array<String>, texts, false, titled);
            _motion = hold;       // struck at 0, seen at `hold`, and never settling
        } else if (_waking) {
            _waking = false;
            var seen = _seen;
            _seen = null;
            if (seen != null && _pacer.proven()) {
                begin(seen, texts, false, titled);
            }
        } else {
            var shown = _shown;
            if (shown != null && _awake && _pacer.proven()
                && !(shown[0].equals(hours) && shown[1].equals(minutes) && shown[2].equals(texts[2]))) {
                begin(shown, texts, true, titled);
            }
        }
        _shown = texts;
        if (_tubes.size() > 0 && (_motion >= _until || titled != _titled)) {
            settle();
        }
        if (_dirty || stamp != _stamp || titled != _titled) {
            lit(bitmap.getDc(), texts, titled);
            _stamp = stamp;
            _titled = titled;
            _dirty = false;
        }
        dc.drawBitmap(0, 0, bitmap);
        strike(dc);
        if (_tubes.size() > 0) {
            var took = System.getTimer() - started;
            if (_frames == 0) {
                _since = started;
            }
            _frames++;
            _drawn += took;
            _slowest = (took > _slowest) ? took : _slowest;
        }
        _pacer.want(_tubes.size() > 0 && hold < 0);
    }

    // Where each numeral of a row goes: the row's ink centred on the time's
    // centre line (designs/preview_sign.py, row_boxes)
    private function places(text as String) as Array<Array<Number>> {
        var size = Layout.SIZES[_row];
        var advance = Layout.ADVANCE[_row];
        var left = Layout.LEFT[_row];
        var right = Layout.RIGHT[_row];
        var chars = text.toCharArray();
        var out = [] as Array<Array<Number>>;
        var x = 0;
        for (var i = 0; i < chars.size(); i++) {
            var d = chars[i].toString().toNumber() as Number;
            if (i > 0) {
                x += size[Layout.GAP] + left[d];
            }
            out.add([d, x] as Array<Number>);
            x += advance[d] + ((i < chars.size() - 1) ? right[d] : 0);
        }
        var x0 = size[Layout.X] - x / 2;
        for (var i = 0; i < out.size(); i++) {
            out[i][1] += x0;
        }
        return out;
    }

    // Where each letter of the date, or of a look's name in one line or two,
    // goes: [letter, x, y], each line centred on the date's centre
    private function letters(lines as Array<String>) as Array<Array<Number>> {
        var size = Layout.SIZES[_row];
        var advance = Layout.SMALL_ADVANCE[_row];
        var h = size[Layout.SMALL_H];
        var top = size[Layout.DATE_Y] - ((lines.size() == 1) ? h / 2 : (2 * h + size[Layout.LINE]) / 2);
        var at = [] as Array<Array<Number>>;
        for (var l = 0; l < lines.size(); l++) {
            var chars = lines[l].toCharArray();
            var x = 0;
            var first = at.size();
            for (var i = 0; i < chars.size(); i++) {
                if (i > 0) {
                    x += size[Layout.SMALL_GAP];
                }
                var c = Layout.LETTERS.find(chars[i].toString());
                if (c == null) {
                    x += size[Layout.SPACE];      // a space, or a character no tube is bent for
                } else {
                    at.add([c, x, top + l * (h + size[Layout.LINE])] as Array<Number>);
                    x += advance[c];
                }
            }
            for (var i = first; i < at.size(); i++) {
                at[i][1] += size[Layout.DATE_X] - x / 2;
            }
        }
        return at;
    }

    // The lit face: every numeral's halo and core, then the date or the
    // look's name; all but the tubes a strike is drawing
    private function lit(dc as Dc, texts as Array<String>, titled as Boolean) as Void {
        var size = Layout.SIZES[_row];
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var halos = Layout.halos();
        var cores = Layout.cores();
        var pad = size[Layout.PAD];
        var m = size[Layout.MARGIN];
        for (var r = 0; r < 2; r++) {
            var y = size[(r == 0) ? Layout.Y_HOURS : Layout.Y_MINUTES];
            var at = places(texts[r]);
            for (var i = 0; i < at.size(); i++) {      // a numeral at a time: its halo, then its core
                if (_hidden[r * 2 + i]) {
                    continue;
                }
                var d = at[i][0];
                tube(dc, halos[d], at[i][1] - pad, y - pad, _colors[r]);
                tube(dc, cores[d], at[i][1] - m, y - m, Lib.Neon.core(_colors[r]));
            }
        }
        if (titled || !_hidden[DATE]) {
            small(dc, titled ? SignText.lines(Lib.Neon.title(_look)) : [texts[2]] as Array<String>);
        }
    }

    // A grey mask from the resources, tinted
    private function tube(dc as Dc, picture as ResourceId, x as Number, y as Number, color as Number) as Void {
        dc.drawBitmap2(x, y, WatchUi.loadResource(picture) as WatchUi.BitmapResource, {:tintColor => color});
    }

    // The date, or a look's name, in the details' tube. The letters sit
    // close, so every halo is drawn before any core.
    private function small(dc as Dc, lines as Array<String>) as Void {
        var size = Layout.SIZES[_row];
        var at = letters(lines);
        var pictures = Layout.smallHalos();
        var inset = size[Layout.SMALL_PAD];
        var color = _colors[2];
        for (var part = 0; part < 2; part++) {
            for (var i = 0; i < at.size(); i++) {
                tube(dc, pictures[at[i][0]], at[i][1] - inset, at[i][2] - inset, color);
            }
            pictures = Layout.smallCores();
            inset = size[Layout.SMALL_MARGIN];
            color = Lib.Neon.core(_colors[2]);
        }
    }

    // ------------------------------------------------------------ the strike

    // The face changed from `old` to `fresh` (hours, minutes, date): every
    // numeral that differs is struck, and the date if it does. With `death`
    // (the face was awake) the old tubes die first. The tubes keep their
    // pictures until they settle, so a frame loads nothing.
    private function begin(old as Array<String>, fresh as Array<String>, death as Boolean, titled as Boolean) as Void {
        var size = Layout.SIZES[_row];
        var tubes = [] as Array<SignTube>;
        var hide = [false, false, false, false, false] as Array<Boolean>;
        var born = _motion + (death ? Lib.Strike.DEATH : 0);
        var halos = Layout.halos();
        var cores = Layout.cores();
        var pad = size[Layout.PAD];
        var m = size[Layout.MARGIN];
        for (var r = 0; r < 2; r++) {
            var which = SignText.changed(old[r], fresh[r]);
            if (which.size() == 0) {
                continue;
            }
            var y = size[(r == 0) ? Layout.Y_HOURS : Layout.Y_MINUTES];
            var was = places(old[r]);
            var at = places(fresh[r]);
            for (var k = 0; k < which.size(); k++) {
                var i = which[k];
                hide[r * 2 + i] = true;
                if (death) {
                    // the tube that stood here, or the whole old row when the count of numerals changed
                    for (var j = 0; j < was.size(); j++) {
                        if ((was.size() == at.size()) ? j == i : k == 0) {
                            var d = was[j][0];
                            tubes.add(new SignTube(picture(halos[d]), picture(cores[d]), was[j][1] - pad, y - pad, was[j][1] - m, y - m,
                                                   r, 0, _motion, true));
                        }
                    }
                }
                var d = at[i][0];
                tubes.add(new SignTube(picture(halos[d]), picture(cores[d]), at[i][1] - pad, y - pad, at[i][1] - m, y - m,
                                       r, r * 2 + i, born, false));
            }
        }
        if (!titled && !old[2].equals(fresh[2])) {
            hide[DATE] = true;
            halos = Layout.smallHalos();
            cores = Layout.smallCores();
            pad = size[Layout.SMALL_PAD];
            m = size[Layout.SMALL_MARGIN];
            for (var pass = death ? 0 : 1; pass < 2; pass++) {
                var at = letters([(pass == 0) ? old[2] : fresh[2]] as Array<String>);
                for (var i = 0; i < at.size(); i++) {
                    var c = at[i][0];
                    tubes.add(new SignTube(picture(halos[c]), picture(cores[c]), at[i][1] - pad, at[i][2] - pad, at[i][1] - m, at[i][2] - m,
                                           2, DATE, (pass == 0) ? _motion : born, pass == 0));
                }
            }
        }
        if (tubes.size() == 0) {
            return;
        }
        _tubes = tubes;
        _hidden = hide;
        _until = born + Lib.Strike.LONGEST;
        _dirty = true;
    }

    private function picture(id as ResourceId) as WatchUi.BitmapResource {
        return WatchUi.loadResource(id) as WatchUi.BitmapResource;
    }

    // Every tube steady again, and back in the bitmap
    private function settle() as Void {
        if (_tubes.size() > 0) {
            if (_frames > 1) {
                // the watch's log (GARMIN/Apps/LOGS): what a strike cost there
                System.println("Sign: a strike of " + _tubes.size() + " tubes, " + _frames + " frames in " + (System.getTimer() - _since)
                               + " ms, drawing " + (_drawn / _frames) + " ms a frame, " + _slowest + " at most");
            }
            _frames = 0;
            _drawn = 0;
            _slowest = 0;
            _tubes = [] as Array<SignTube>;
            _hidden = [false, false, false, false, false] as Array<Boolean>;
            _dirty = true;
        }
    }

    // A frame of the strike, over the bitmap: each tube's halo, then each
    // tube's core, their tints dimmed to the strike's brightness now
    private function strike(dc as Dc) as Void {
        var tubes = _tubes;
        var n = tubes.size();
        if (n == 0) {
            return;
        }
        var last = null as SignTube?;
        for (var i = 0; i < n; i++) {
            var t = tubes[i];
            if (last != null && last.seed == t.seed && last.from == t.from && last.dying == t.dying) {
                t.corePercent = last.corePercent;      // the date's letters are one tube
                t.haloPercent = last.haloPercent;
            } else {
                var level = t.dying ? Lib.Strike.dying(_motion - t.from) : Lib.Strike.lit(_motion - t.from, t.seed);
                t.corePercent = level[0];
                t.haloPercent = level[1];
            }
            last = t;
            if (t.haloPercent > 0) {
                dc.drawBitmap2(t.haloX, t.haloY, t.halo, {:tintColor => Lib.Neon.wash(_colors[t.color], 0, t.haloPercent)});
            }
        }
        for (var i = 0; i < n; i++) {
            var t = tubes[i];
            if (t.corePercent > 0) {
                dc.drawBitmap2(t.coreX, t.coreY, t.core, {:tintColor => Lib.Neon.wash(Lib.Neon.core(_colors[t.color]), 0, t.corePercent)});
            }
        }
    }

    // ------------------------------------------------------------ standby

    // Standby: the numerals as thin tubes, no halo and no date, shifted each
    // minute (Lib.Aod.offset)
    private function standby(dc as Dc, hours as String, minutes as String, minute as Number) as Void {
        var size = Layout.SIZES[_row];
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var font = _thin;
        if (font == null) {
            return;
        }
        var off = Lib.Aod.offset(minute, size[Layout.AOD_STEP]);
        var rows = [hours, minutes] as Array<String>;
        var margin = size[Layout.THIN_MARGIN];
        for (var r = 0; r < 2; r++) {
            var y = size[(r == 0) ? Layout.Y_HOURS : Layout.Y_MINUTES];
            var at = places(rows[r]);
            dc.setColor(Lib.Neon.standby(_colors[r]), Graphics.COLOR_TRANSPARENT);
            for (var i = 0; i < at.size(); i++) {
                dc.drawText(at[i][1] - margin + off[0], y - margin + off[1], font, at[i][0].toString(), Graphics.TEXT_JUSTIFY_LEFT);
            }
        }
    }
}
