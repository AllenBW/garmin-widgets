import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// One tube of a strike (Lib.Strike): a numeral, both its lights as one, or
// the date. Where the watch tints bitmaps it carries its own two pictures,
// its halo and its core in their colours on nothing, made once when the
// strike begins; where it draws from fonts (:plain), the digit or the text
// and where it stands.
class EdgeTube {
    var halo as BufferedBitmap? = null;
    var core as BufferedBitmap? = null;
    var haloRef as BufferedBitmapReference? = null;
    var coreRef as BufferedBitmapReference? = null;
    var digit as Number;       // 0 to 9, or -1 for the date
    var text as String;        // the date's text
    var x as Number;           // the digit's box, or the date's line
    var y as Number;
    var seed as Number;
    var from as Number;        // the motion clock when it is struck, or began to die
    var dying as Boolean;
    var corePercent as Number = 0;
    var haloPercent as Number = 0;

    function initialize(digit_ as Number, text_ as String, x_ as Number, y_ as Number, seed_ as Number, from_ as Number, dying_ as Boolean) {
        digit = digit_;
        text = text_;
        x = x_;
        y = y_;
        seed = seed_;
        from = from_;
        dying = dying_;
    }
}

// Edge: enormous numerals that are not drawn at all. Only their edges
// catch the light, as a figure does between two signs: the hours' tube on
// the edges facing the upper left, the minutes' on those facing the lower
// right, the hours over the minutes, left of centre; the date to their
// right in thin tube in the details' colour.
//
// Everything lit is a tube of one width with round ends, and a lit tube is
// a halo in its colour under a core washed toward white (Lib.Neon). The
// watch cannot blur, so the halos are baked: designs/gen_edge.py draws each
// digit's tubes (designs/edge_runs.py), their halos and the date's
// lettering as white bitmaps whose alpha is the mask, at this screen's
// size, and drawBitmap2's tint colours them, so any tube of the chart
// works. (A bitmap font's mask has four levels at most: steps in a halo.)
// The lit face is laid into a bitmap when the minute, the look or the
// title changes (ten bitmaps loaded and let go, about fifty draws) and an
// update is one blit.
//
// The Forerunner 165 and 70 cannot tint a bitmap, and their bitmaps keep
// one bit of alpha. For them (the functions marked :plain; monkey.jungle)
// everything is a font: a halo is three layers of four levels each, drawn
// in the tube's colour at Layout.LAYERS percent, dithered offline so the
// three make one smooth halo (designs/preview_edge.py, layered).
//
// The strike (Lib.Strike): on a wake, a numeral that changed since the face
// was last seen lit flickers on as a tube lights, and the date if the day
// changed; when the minute turns while the face is awake the old numeral
// dies first and the new one is struck in its place. A numeral's two
// lights share one seed, so it comes on as one, and neighbours differ.
// While a strike runs the steady tubes stay in the bitmap and each struck
// numeral is two pictures of its own (its halo and its core, both lights,
// composed once as the strike begins), drawn each frame with a grey tint
// at the strike's brightness: two blits a numeral, nothing loaded. The
// frames come from Lib.Motion's pacer, which starts a timer only once the
// face is known to be awake. Standby never animates.
//
// Holding the face steps through the looks (Lib.Look), the look's name
// standing in for the date for a moment, bent from the same tube.
//
// Standby (always-on): the thin tubes alone, no halo and no date, in
// Lib.Neon.standby's colours, shifted each minute (Lib.Aod); 4 to 6 % of
// the screen lit (designs/preview_edge.py prints it).
class EdgeView extends WatchUi.WatchFace {

    private const DAYS = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"] as Array<String>;
    // A digit's glyphs in the fonts: its tubes facing the upper left, and the lower right
    private const UPPER = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] as Array<String>;
    private const LOWER = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"] as Array<String>;
    private const LEFT = Graphics.TEXT_JUSTIFY_LEFT;
    private const FRAME = 50;          // ms between a strike's frames
    private const MOST_FRAMES = 4;     // a stall moves the strike on by this many at most
    private const DATE = 4;            // the date's place among the hidden, and its seed

    private var _w as Number;
    private var _t as Array<Number>;              // Layout's table for this screen
    private var _adv as Array<Number>;            // the digits' advances
    private var _letterAdv as Array<Number>;      // the lettering's
    private var _hours as String = "";
    private var _minutes as String = "";
    private var _date as String = "";
    private var _minute as Number = -1;           // the clock's minute when last read
    private var _fixed as Boolean = false;        // the tests' time: the clock is not read
    private var _colors as Array<Number> = [0, 0, 0] as Array<Number>;   // the hours', the minutes', the details' tube
    private var _look as Number = Lib.Look.YOURS;
    private var _day as Number = 0;               // the daily look's day
    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;
    private var _titled as Boolean = false;
    private var _dirty as Boolean = true;         // the lit face's bitmap is out of date
    private var _ref as BufferedBitmapReference? = null;
    private var _lit as BufferedBitmap? = null;   // held itself: the pool purges a bitmap nothing holds
    private var _noBitmap as Boolean = false;     // the pool had no room: draw the lit face each update, and nothing strikes
    private var _thin as FontType? = null;

    // The strike
    private var _pacer as Lib.Motion.Pacer;
    private var _motion as Number = 0;            // ms of drawn frames: the strike's clock
    private var _step as Number? = null;          // the tests' frame, in ms
    private var _shown as Array<String>? = null;  // the hours, the minutes and the date as last drawn lit
    private var _seen as Array<String>? = null;   // and as they stood when the face last slept
    private var _waking as Boolean = false;
    private var _tubes as Array<EdgeTube> = [] as Array<EdgeTube>;    // struck or dying now
    private var _hidden as Array<Boolean> = [false, false, false, false, false] as Array<Boolean>;   // left out of the bitmap: they are _tubes
    private var _until as Number = 0;             // the motion clock when the strike is over
    (:plain)
    private var _fonts as Array<FontType> = [] as Array<FontType>;    // a :plain watch's fonts, held while a strike runs
    private var _frames as Number = 0;            // the strike's frames so far, their drawing time and the slowest
    private var _since as Number = 0;
    private var _drawn as Number = 0;
    private var _slowest as Number = 0;

    function initialize() {
        WatchFace.initialize();
        _burnIn = Lib.Aod.required();
        _pacer = new Lib.Motion.Pacer(FRAME, MOST_FRAMES);
        _w = System.getDeviceSettings().screenWidth;
        _t = Layout.table(_w);
        _adv = Layout.advances(_w);
        _letterAdv = Layout.letters(_w);
        reloadSettings();
    }

    function reloadSettings() as Void {
        _look = Lib.Look.mode();
        _colors = Lib.Neon.colors(_look);
        _day = Lib.Look.today();
        settle();       // a strike's pictures are in the old colours
        _dirty = true;
    }

    function onLayout(dc as Dc) as Void {
        _dirty = true;
    }

    // ------------------------------------------------------------ state

    private function refresh() as Void {
        var clock = System.getClockTime();
        if (clock.min == _minute || _fixed) {
            return;
        }
        _minute = clock.min;
        var hour = clock.hour;
        if (System.getDeviceSettings().is24Hour) {
            _hours = hour.format("%02d");
        } else {
            hour = hour % 12;
            _hours = ((hour == 0) ? 12 : hour).toString();
        }
        _minutes = clock.min.format("%02d");
        var info = Time.Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        _date = dateText(info.day_of_week as Number, info.day as Number);
        sample();
        _dirty = true;
    }

    // "TUE 15": the lettering has A to Z only, so the weekday is not the
    // system's word (1 is Sunday)
    function dateText(weekday as Number, day as Number) as String {
        return DAYS[(weekday + 6) % 7] + " " + day;
    }

    // The places of `fresh` whose numeral differs from `old`'s: all of them
    // when the count of numerals changed (9 to 10 on a 12-hour clock), since
    // every numeral of the row then moves
    function changed(old as String, fresh as String) as Array<Number> {
        var out = [] as Array<Number>;
        var a = old.toCharArray();
        var b = fresh.toCharArray();
        for (var i = 0; i < b.size(); i++) {
            if (a.size() != b.size() || a[i] != b[i]) {
                out.add(i);
            }
        }
        return out;
    }

    (:live)
    private function sample() as Void {
    }

    // The screenshots' moment (sample.jungle): 10:37 on Tuesday the 15th
    (:sample)
    private function sample() as Void {
        _hours = "10";
        _minutes = "37";
        _date = "TUE 15";
        hold();
    }

    // The standby screenshot (sample-standby.jungle): low power mode held,
    // since it can't be driven from a script
    (:sample, :standby)
    private function hold() as Void {
        _awake = false;
        _burnIn = true;
    }

    (:sample, :lit)
    private function hold() as Void {
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

    // For the tests: a time and a date, whatever the clock says, from now on
    function setTime(hours as String, minutes as String, date as String) as Void {
        _fixed = true;
        _hours = hours;
        _minutes = minutes;
        _date = date;
        _dirty = true;
    }

    // For the tests: three tubes by number (Lib.Neon.TUBES)
    function setTubes(tubes as Array<Number>) as Void {
        settle();
        _colors = [Lib.Neon.TUBES[tubes[0]], Lib.Neon.TUBES[tubes[1]], Lib.Neon.TUBES[tubes[2]]] as Array<Number>;
        _dirty = true;
    }

    // For the tests: the power mode, and frames of a set length in place of
    // the timer's
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
        _minute = -1;
        _pacer.onExitSleep();
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------ drawing

    function onUpdate(dc as Dc) as Void {
        if (_look == Lib.Look.DAILY && Lib.Look.today() != _day) {
            reloadSettings();     // a new day: the next set
        }
        var started = System.getTimer();
        var step = _pacer.step(started);
        var frame = _step;
        _motion += (frame != null) ? frame : step;
        refresh();
        if (!_awake && _burnIn) {
            drawThin(dc);
            _pacer.want(false);
            return;
        }
        var titled = _awake && Lib.Look.shown();
        var lit = bitmap();
        if (lit == null) {
            _titled = titled;
            drawLit(dc);
            _pacer.want(false);
            return;
        }

        // What changed: since the face was last seen, on a wake; since the
        // last frame, while awake. A strike needs frames, so nothing is
        // struck until the face is known to be awake.
        var texts = [_hours, _minutes, _date] as Array<String>;
        var hold = strikeAt();
        if (hold >= 0) {
            if (_tubes.size() == 0) {
                _motion = 0;
                begin(["09", "26", _date] as Array<String>, texts, false, titled);
            }
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
                && !(shown[0].equals(_hours) && shown[1].equals(_minutes) && shown[2].equals(_date))) {
                settle();
                begin(shown, texts, true, titled);
            }
        }
        _shown = texts;
        if (_tubes.size() > 0 && (_motion >= _until || titled != _titled)) {
            settle();
        }
        if (_dirty || titled != _titled) {
            _titled = titled;
            drawLit(lit.getDc());
            _dirty = false;
        }
        dc.drawBitmap(0, 0, lit);
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

    // The lit face's bitmap; null when the graphics pool has no room for one
    private function bitmap() as BufferedBitmap? {
        if (_noBitmap) {
            return null;
        }
        var lit = _lit;
        if (lit == null || _ref == null) {
            lit = null;
            try {
                // 16 bits a pixel, as the screen shows: half the room of the default in the graphics pool
                var ref = Graphics.createBufferedBitmap({:width => _w, :height => _w, :colorDepth => 16});
                var b = ref.get();
                if (b instanceof BufferedBitmap) {
                    _ref = ref;
                    lit = b;
                }
            } catch (e instanceof Lang.Exception) {
                System.println("Edge: graphics pool: " + e.getErrorMessage());
            }
            if (lit == null) {
                _noBitmap = true;
                return null;
            }
            _lit = lit;
            _dirty = true;
        }
        return lit;
    }

    // The face awake, all but the tubes a strike is drawing: every halo
    // first, then the cores over them, as the preview lays them
    // (designs/preview_edge.py, face). Each sheet is loaded for its numeral
    // and let go: the halos are the largest thing the face has, and the
    // graphics pool need hold only one at a time
    (:tinted)
    private function drawLit(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var hours = _colors[0];
        var minutes = _colors[1];
        var detail = _colors[2];
        var text = _titled ? lines(Lib.Neon.title(_look)) : [_date] as Array<String>;
        var words = _titled || !_hidden[DATE];
        tubes(dc, true, hours, minutes);
        if (words) {
            letters(dc, WatchUi.loadResource(Rez.Drawables.LettersGlow) as BitmapResource, text, detail, 0, 0);
        }
        tubes(dc, false, Lib.Neon.core(hours), Lib.Neon.core(minutes));
        if (words) {
            letters(dc, WatchUi.loadResource(Rez.Drawables.LettersCore) as BitmapResource, text, Lib.Neon.core(detail), 0, 0);
        }
    }

    // The same on a watch that cannot tint a bitmap: each halo as three
    // font layers, the faintest first, then the cores from a font
    (:plain)
    private function drawLit(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var hours = _colors[0];
        var minutes = _colors[1];
        var detail = _colors[2];
        var text = _titled ? lines(Lib.Neon.title(_look)) : [_date] as Array<String>;
        var words = _titled || !_hidden[DATE];
        var fonts = (_fonts.size() > 0) ? _fonts : plainFonts();
        for (var n = 0; n < Layout.LAYERS.size(); n++) {
            var level = Layout.LAYERS[n];
            digits(dc, fonts[n], _t[Layout.PAD], 0, 0, Lib.Neon.wash(hours, 0, level), Lib.Neon.wash(minutes, 0, level), false);
            if (words) {
                words(dc, fonts[4 + n], text, Lib.Neon.wash(detail, 0, level));
            }
        }
        digits(dc, fonts[3], _t[Layout.CORE_PAD], 0, 0, Lib.Neon.core(hours), Lib.Neon.core(minutes), false);
        if (words) {
            words(dc, fonts[7], text, Lib.Neon.core(detail));
        }
    }

    // A :plain watch's lit fonts: the digits' three halo layers and their
    // cores, then the lettering's
    (:plain)
    private function plainFonts() as Array<FontType> {
        return [WatchUi.loadResource(Rez.Fonts.EdgeLayer0) as FontResource, WatchUi.loadResource(Rez.Fonts.EdgeLayer1) as FontResource,
                WatchUi.loadResource(Rez.Fonts.EdgeLayer2) as FontResource, WatchUi.loadResource(Rez.Fonts.EdgeCore) as FontResource,
                WatchUi.loadResource(Rez.Fonts.LettersLayer0) as FontResource, WatchUi.loadResource(Rez.Fonts.LettersLayer1) as FontResource,
                WatchUi.loadResource(Rez.Fonts.LettersLayer2) as FontResource,
                WatchUi.loadResource(Rez.Fonts.LettersCore) as FontResource] as Array<FontType>;
    }

    // The hours over the minutes from the digits' sheets, halos or cores,
    // leaving out the numerals a strike is drawing
    (:tinted)
    private function tubes(dc as Dc, halos as Boolean, upper as Number, lower as Number) as Void {
        var rows = [_hours, _minutes] as Array<String>;
        var pad = _t[halos ? Layout.PAD : Layout.CORE_PAD];
        for (var r = 0; r < 2; r++) {
            var chars = rows[r].toCharArray();
            var x = _t[Layout.CX] - rowWidth(chars) / 2 - pad;
            var y = _t[Layout.Y0 + r] - pad;
            for (var i = 0; i < chars.size(); i++) {
                var d = digit(chars[i]);
                if (!_hidden[r * 2 + i]) {
                    numeral(dc, halos, d, x, y, upper, lower);
                }
                x += _adv[d];
            }
        }
    }

    // One numeral from its sheet of halos or of cores, the cell's corner at
    // x, y: the sheet's left cell is the tubes facing the upper left, its
    // right cell those facing the lower right; a cell is the digit's box
    // with the pad all round. The tint colours the white mask. (drawBitmap2
    // draws the chosen part where it lies in the whole bitmap set at x, y,
    // so a cell goes at x less its place in the sheet.)
    (:tinted)
    private function numeral(dc as Dc, halos as Boolean, d as Number, x as Number, y as Number, upper as Number, lower as Number) as Void {
        var ids = halos
            ? [Rez.Drawables.Glow0, Rez.Drawables.Glow1, Rez.Drawables.Glow2, Rez.Drawables.Glow3, Rez.Drawables.Glow4,
               Rez.Drawables.Glow5, Rez.Drawables.Glow6, Rez.Drawables.Glow7, Rez.Drawables.Glow8, Rez.Drawables.Glow9]
            : [Rez.Drawables.Core0, Rez.Drawables.Core1, Rez.Drawables.Core2, Rez.Drawables.Core3, Rez.Drawables.Core4,
               Rez.Drawables.Core5, Rez.Drawables.Core6, Rez.Drawables.Core7, Rez.Drawables.Core8, Rez.Drawables.Core9];
        var sheet = WatchUi.loadResource(ids[d]) as BitmapResource;
        var cell = _adv[d] + 2 * _t[halos ? Layout.PAD : Layout.CORE_PAD];
        dc.drawBitmap2(x, y, sheet, {:bitmapX => 0, :bitmapWidth => cell, :tintColor => upper});
        dc.drawBitmap2(x - cell, y, sheet, {:bitmapX => cell, :bitmapWidth => cell, :tintColor => lower});
    }

    // Standby: the thin tubes alone, shifted each minute
    private function drawThin(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var thin = _thin;
        if (thin == null) {
            thin = WatchUi.loadResource(Rez.Fonts.EdgeThin) as FontResource;
            _thin = thin;
        }
        var minute = _minutes.toNumber();
        var off = Lib.Aod.offset((minute != null) ? minute : 0, _t[Layout.SHIFT]);
        digits(dc, thin, _t[Layout.CORE_PAD], off[0], off[1], Lib.Neon.standby(_colors[0]), Lib.Neon.standby(_colors[1]), true);
    }

    // The hours over the minutes from a font (standby's thin tubes; a
    // :plain watch's layers and cores): each digit's glyph of the upper
    // left tubes in one colour and of the lower right in the other. A
    // glyph's cell is the digit's box with `pad` all round. Unless `all`,
    // the numerals a strike is drawing are left out.
    private function digits(dc as Dc, font as FontType, pad as Number, dx as Number, dy as Number,
                            upper as Number, lower as Number, all as Boolean) as Void {
        var rows = [_hours, _minutes] as Array<String>;
        for (var r = 0; r < 2; r++) {
            var chars = rows[r].toCharArray();
            var x = _t[Layout.CX] - rowWidth(chars) / 2 + dx - pad;
            var y = _t[Layout.Y0 + r] + dy - pad;
            for (var i = 0; i < chars.size(); i++) {
                var d = digit(chars[i]);
                if (all || !_hidden[r * 2 + i]) {
                    glyphs(dc, font, d, x, y, upper, lower);
                }
                x += _adv[d];
            }
        }
    }

    // One digit's two glyphs, the cell's corner at x, y
    private function glyphs(dc as Dc, font as FontType, d as Number, x as Number, y as Number, upper as Number, lower as Number) as Void {
        dc.setColor(upper, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, UPPER[d], LEFT);
        dc.setColor(lower, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, LOWER[d], LEFT);
    }

    // A row's width: its digits' advances
    private function rowWidth(chars as Array<Char>) as Number {
        var sum = 0;
        for (var i = 0; i < chars.size(); i++) {
            sum += _adv[digit(chars[i])];
        }
        return sum;
    }

    private function digit(c as Char) as Number {
        var d = c.toNumber() - 48;
        return (d >= 0 && d <= 9) ? d : 0;
    }

    // A title's lines: two where it has a space (HI-VIS / GREEN)
    function lines(s as String) as Array<String> {
        var at = s.find(" ");
        if (at == null) {
            return [s] as Array<String>;
        }
        return [s.substring(0, at) as String, s.substring(at + 1, s.length()) as String] as Array<String>;
    }

    // The lettering's glyph for a character (A to Z, 0 to 9, hyphen), or -1
    // for a space or anything else
    function letter(c as Char) as Number {
        var n = c.toNumber();
        if (n >= 65 && n <= 90) {
            return n - 65;
        }
        if (n >= 48 && n <= 57) {
            return n - 48 + 26;
        }
        return (n == 45) ? 36 : -1;
    }

    // A line of lettering's width
    private function lineWidth(chars as Array<Char>) as Number {
        var width = _t[Layout.LETTER_GAP] * (chars.size() - 1);
        for (var i = 0; i < chars.size(); i++) {
            var g = letter(chars[i]);
            width += (g < 0) ? _t[Layout.SPACE] : _letterAdv[g];
        }
        return width;
    }

    // The date, or a title's lines, centred on the date's place and moved
    // by dx, dy, from a sheet of the lettering (halos or cores): a grid of
    // cells, each the widest letter by the letters' height with the pad
    // all round
    (:tinted)
    private function letters(dc as Dc, sheet as BitmapResource, text as Array<String>, color as Number, dx as Number, dy as Number) as Void {
        var h = _t[Layout.LETTER];
        var pad = _t[Layout.LETTER_PAD];
        var gap = _t[Layout.LETTER_GAP];
        var step = h + _t[Layout.LINE_GAP];
        var cw = _t[Layout.LETTER_CELL] + 2 * pad;
        var ch = h + 2 * pad;
        var y = (_w - text.size() * step + _t[Layout.LINE_GAP]) / 2 - pad + dy;
        for (var k = 0; k < text.size(); k++) {
            var chars = text[k].toCharArray();
            var x = _t[Layout.DATE_X] - lineWidth(chars) / 2 - pad + dx;
            for (var i = 0; i < chars.size(); i++) {
                var g = letter(chars[i]);
                if (g >= 0) {
                    var bx = (g % Layout.LETTER_COLS) * cw;
                    var by = (g / Layout.LETTER_COLS) * ch;
                    dc.drawBitmap2(x - bx, y + k * step - by, sheet, {
                        :bitmapX => bx, :bitmapY => by, :bitmapWidth => _letterAdv[g] + 2 * pad, :bitmapHeight => ch,
                        :tintColor => color});
                }
                x += ((g < 0) ? _t[Layout.SPACE] : _letterAdv[g]) + gap;
            }
        }
    }

    // The same from a font of the lettering: a glyph's cell is the letter's
    // box with the pad all round
    (:plain)
    private function words(dc as Dc, font as FontType, text as Array<String>, color as Number) as Void {
        var pad = _t[Layout.LETTER_PAD];
        var gap = _t[Layout.LETTER_GAP];
        var step = _t[Layout.LETTER] + _t[Layout.LINE_GAP];
        var y = (_w - text.size() * step + _t[Layout.LINE_GAP]) / 2 - pad;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        for (var k = 0; k < text.size(); k++) {
            var chars = text[k].toCharArray();
            var x = _t[Layout.DATE_X] - lineWidth(chars) / 2 - pad;
            for (var i = 0; i < chars.size(); i++) {
                var g = letter(chars[i]);
                if (g >= 0) {
                    dc.drawText(x, y + k * step, font, chars[i].toString(), LEFT);
                }
                x += ((g < 0) ? _t[Layout.SPACE] : _letterAdv[g]) + gap;
            }
        }
    }

    // ------------------------------------------------------------ the strike

    // The face changed from `old` to `fresh` (hours, minutes, date): every
    // numeral that differs is struck, and the date if it does. With `death`
    // (the face was awake) the old tubes die first. A tube is made with all
    // it needs, so a frame loads nothing; if the graphics pool has no room
    // for the struck ones, nothing is struck and the face simply changes.
    private function begin(old as Array<String>, fresh as Array<String>, death as Boolean, titled as Boolean) as Void {
        var lit = _lit;
        if (lit == null) {
            return;
        }
        var dying = [] as Array<EdgeTube>;
        var struck = [] as Array<EdgeTube>;
        var hide = [false, false, false, false, false] as Array<Boolean>;
        var born = _motion + (death ? Lib.Strike.DEATH : 0);
        // the date first: its sheets are the largest thing loaded, and are let go before the numerals' pictures are made
        if (!titled && !old[2].equals(fresh[2])) {
            hide[DATE] = true;
            if (death) {
                dying.add(new EdgeTube(-1, old[2], 0, 0, DATE, _motion, true));
            }
            struck.add(new EdgeTube(-1, fresh[2], 0, 0, DATE, born, false));
        }
        for (var r = 0; r < 2; r++) {
            var which = changed(old[r], fresh[r]);
            if (which.size() == 0) {
                continue;
            }
            var y = _t[Layout.Y0 + r];
            var was = places(old[r]);
            var at = places(fresh[r]);
            for (var k = 0; k < which.size(); k++) {
                var i = which[k];
                hide[r * 2 + i] = true;
                if (death) {
                    // the numeral that stood here, or the whole old row when the count of numerals changed
                    for (var j = 0; j < was.size(); j++) {
                        if ((was.size() == at.size()) ? j == i : k == 0) {
                            dying.add(new EdgeTube(was[j][0], "", was[j][1], y, 0, _motion, true));
                        }
                    }
                }
                struck.add(new EdgeTube(at[i][0], "", at[i][1], y, r * 2 + i, born, false));
            }
        }
        if (struck.size() == 0) {
            return;
        }
        // The steady tubes into the bitmap first, while the pool is free
        // of the strike's pictures; then the pictures. If there is no room
        // for the dying ones' too (four numerals dying and four struck is
        // 2.2 MB at 454 px), the old numerals simply go out.
        _hidden = hide;
        _titled = titled;
        drawLit(lit.getDc());
        _dirty = false;
        var tubes = [] as Array<EdgeTube>;
        if (ready(struck)) {
            tubes.addAll(struck);
            if (dying.size() > 0 && ready(dying)) {
                tubes.addAll(dying);
            }
        }
        dying = [] as Array<EdgeTube>;
        struck = [] as Array<EdgeTube>;
        if (tubes.size() == 0) {
            _hidden = [false, false, false, false, false] as Array<Boolean>;
            _dirty = true;
            return;
        }
        _tubes = tubes;
        _until = born + Lib.Strike.LONGEST;
    }

    // Each numeral of a row and its box's left edge: [digit, x]
    private function places(text as String) as Array<Array<Number>> {
        var chars = text.toCharArray();
        var out = [] as Array<Array<Number>>;
        var x = _t[Layout.CX] - rowWidth(chars) / 2;
        for (var i = 0; i < chars.size(); i++) {
            var d = digit(chars[i]);
            out.add([d, x] as Array<Number>);
            x += _adv[d];
        }
        return out;
    }

    // What the tubes need before the first frame: each its two pictures,
    // the halo and the core of both its lights in their colours on nothing,
    // which a frame then draws with a grey tint. False if the graphics pool
    // has no room. A sheet that cannot be loaded for want of room ends the
    // app (it cannot be caught), where a bitmap that cannot be made only
    // throws: so every picture is made first, with a bitmap the size of the
    // largest sheet held beside them, and only then, that one let go, are
    // the sheets loaded, one at a time, into the room it kept.
    (:tinted)
    private function ready(tubes as Array<EdgeTube>) as Boolean {
        var hours = _colors[0];
        var minutes = _colors[1];
        var detail = _colors[2];
        var n = tubes.size();
        var kept = null;
        try {
            var pad = _t[Layout.LETTER_PAD];
            var wideMost = Layout.LETTER_COLS * (_t[Layout.LETTER_CELL] + 2 * pad);      // the lettering's sheet
            var highMost = 4 * (_t[Layout.LETTER] + 2 * pad);
            var glowWide = 2 * (_adv[0] + 2 * _t[Layout.PAD]);                             // the widest digit's
            var glowHigh = _t[Layout.H] + 2 * _t[Layout.PAD];
            if (glowWide * glowHigh > wideMost * highMost) {
                wideMost = glowWide;
                highMost = glowHigh;
            }
            kept = Graphics.createBufferedBitmap({:width => wideMost, :height => highMost}).get();
            for (var i = 0; i < n; i++) {
                var t = tubes[i];
                for (var pass = 0; pass < 2; pass++) {
                    pad = (t.digit < 0) ? _t[Layout.LETTER_PAD] : _t[(pass == 0) ? Layout.PAD : Layout.CORE_PAD];
                    var wide = ((t.digit < 0) ? lineWidth(t.text.toCharArray()) : _adv[t.digit]) + 2 * pad;
                    var high = ((t.digit < 0) ? _t[Layout.LETTER] : _t[Layout.H]) + 2 * pad;
                    var ref = Graphics.createBufferedBitmap({:width => wide, :height => high});
                    var b = ref.get();
                    if (!(b instanceof BufferedBitmap)) {
                        throw new Lang.InvalidValueException("no bitmap");
                    }
                    if (pass == 0) {
                        t.halo = b;
                        t.haloRef = ref;
                    } else {
                        t.core = b;
                        t.coreRef = ref;
                    }
                }
            }
            if (kept == null) {
                throw new Lang.InvalidValueException("no bitmap");
            }
        } catch (e) {
            System.println("Edge: no room for a strike's pictures");
            for (var i = 0; i < n; i++) {
                tubes[i].halo = null;
                tubes[i].haloRef = null;
                tubes[i].core = null;
                tubes[i].coreRef = null;
            }
            return false;
        }
        kept = null;        // the room the sheets are loaded into
        for (var i = 0; i < n; i++) {
            var t = tubes[i];
            for (var pass = 0; pass < 2; pass++) {
                var halos = pass == 0;
                var b = halos ? t.halo : t.core;
                if (b == null) {
                    continue;
                }
                var dc = b.getDc();
                dc.setColor(Graphics.COLOR_TRANSPARENT, Graphics.COLOR_TRANSPARENT);
                dc.clear();
                if (t.digit < 0) {
                    // the date's line stands at the date's place: move it to the picture's corner
                    var pad = _t[Layout.LETTER_PAD];
                    t.x = _t[Layout.DATE_X] - lineWidth(t.text.toCharArray()) / 2 - pad;
                    t.y = (_w - _t[Layout.LETTER]) / 2 - pad;
                    letters(dc, WatchUi.loadResource(halos ? Rez.Drawables.LettersGlow : Rez.Drawables.LettersCore) as BitmapResource,
                            [t.text] as Array<String>, halos ? detail : Lib.Neon.core(detail), -t.x, -t.y);
                } else {
                    numeral(dc, halos, t.digit, 0, 0, halos ? hours : Lib.Neon.core(hours), halos ? minutes : Lib.Neon.core(minutes));
                }
            }
        }
        return true;
    }

    // A :plain watch draws a struck tube from its fonts each frame: they are
    // held while the strike runs
    (:plain)
    private function ready(tubes as Array<EdgeTube>) as Boolean {
        if (_fonts.size() == 0) {
            _fonts = plainFonts();
        }
        return true;
    }

    // Every tube steady again, and back in the bitmap
    private function settle() as Void {
        if (_tubes.size() > 0) {
            if (_frames > 1) {
                // the watch's log (GARMIN/Apps/LOGS): what a strike cost there
                System.println("Edge: a strike of " + _tubes.size() + " tubes, " + _frames + " frames in " + (System.getTimer() - _since)
                               + " ms, drawing " + (_drawn / _frames) + " ms a frame, " + _slowest + " at most");
            }
            _frames = 0;
            _drawn = 0;
            _slowest = 0;
            _tubes = [] as Array<EdgeTube>;
            _hidden = [false, false, false, false, false] as Array<Boolean>;
            release();
            _dirty = true;
        }
    }

    // Let a strike's fonts go (the tubes hold a tinting watch's pictures)
    (:tinted)
    private function release() as Void {
    }

    (:plain)
    private function release() as Void {
        _fonts = [] as Array<FontType>;
    }

    // Each tube's brightness now (Lib.Strike): a numeral's two lights are one
    // tube, so they share it
    private function levels() as Void {
        for (var i = 0; i < _tubes.size(); i++) {
            var t = _tubes[i];
            var level = t.dying ? Lib.Strike.dying(_motion - t.from) : Lib.Strike.lit(_motion - t.from, t.seed);
            t.corePercent = level[0];
            t.haloPercent = level[1];
        }
    }

    // A frame of the strike, over the bitmap: each tube's halo, then each
    // tube's core, dimmed to the strike's brightness by a grey tint
    (:tinted)
    private function strike(dc as Dc) as Void {
        var tubes = _tubes;
        var n = tubes.size();
        if (n == 0) {
            return;
        }
        levels();
        for (var i = 0; i < n; i++) {
            var t = tubes[i];
            var halo = t.halo;
            if (t.haloPercent > 0 && halo != null) {
                var pad = (t.digit < 0) ? 0 : _t[Layout.PAD];
                dc.drawBitmap2(t.x - pad, t.y - pad, halo, {:tintColor => Lib.Neon.wash(Graphics.COLOR_WHITE, 0, t.haloPercent)});
            }
        }
        for (var i = 0; i < n; i++) {
            var t = tubes[i];
            var core = t.core;
            if (t.corePercent > 0 && core != null) {
                var pad = (t.digit < 0) ? 0 : _t[Layout.CORE_PAD];
                dc.drawBitmap2(t.x - pad, t.y - pad, core, {:tintColor => Lib.Neon.wash(Graphics.COLOR_WHITE, 0, t.corePercent)});
            }
        }
    }

    // The same from the fonts: each halo layer's colour dimmed by the halo's
    // brightness, each core's by the core's
    (:plain)
    private function strike(dc as Dc) as Void {
        var tubes = _tubes;
        var n = tubes.size();
        if (n == 0 || _fonts.size() == 0) {
            return;
        }
        levels();
        var hours = _colors[0];
        var minutes = _colors[1];
        var detail = _colors[2];
        for (var i = 0; i < n; i++) {
            var t = tubes[i];
            if (t.haloPercent <= 0) {
                continue;
            }
            for (var k = 0; k < Layout.LAYERS.size(); k++) {
                var level = Layout.LAYERS[k] * t.haloPercent / 100;
                if (t.digit < 0) {
                    words(dc, _fonts[4 + k], [t.text] as Array<String>, Lib.Neon.wash(detail, 0, level));
                } else {
                    glyphs(dc, _fonts[k], t.digit, t.x - _t[Layout.PAD], t.y - _t[Layout.PAD],
                           Lib.Neon.wash(hours, 0, level), Lib.Neon.wash(minutes, 0, level));
                }
            }
        }
        for (var i = 0; i < n; i++) {
            var t = tubes[i];
            if (t.corePercent <= 0) {
                continue;
            }
            if (t.digit < 0) {
                words(dc, _fonts[7], [t.text] as Array<String>, Lib.Neon.wash(Lib.Neon.core(detail), 0, t.corePercent));
            } else {
                glyphs(dc, _fonts[3], t.digit, t.x - _t[Layout.CORE_PAD], t.y - _t[Layout.CORE_PAD],
                       Lib.Neon.wash(Lib.Neon.core(hours), 0, t.corePercent), Lib.Neon.wash(Lib.Neon.core(minutes), 0, t.corePercent));
            }
        }
    }
}
