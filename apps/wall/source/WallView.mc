import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// The most lit cells in a row of a numeral (the tests hold Numerals to it):
// how far the lit digits' strip reaches past the readings' end
const LIT_RUN = 13;

// Wall: the whole screen a wall of small digits, every one from your
// readings, and the time is where they light up: the hours above and the
// minutes below, the size of the screen, bright digits on a dim mass. A
// band across the middle holds what you read: the date, the next sunset or
// sunrise and the countdown to it, the temperature and your heart rate,
// each in its family's colour (Lib.Numbers). The small digits are texture.
//
// In high visibility the numerals turn solid colour with black digits in them.
// Holding the time steps through the looks (Lib.Look), the look's name
// standing in for the band for a moment.
//
// About 800 digits are too many to draw in one update (the watchdog), so the
// dim wall goes into a full-screen bitmap a few rows per frame, a second
// bitmap holds that with the time on it for the minute, and each update copies
// that and draws the band. The digits are placed one to a cell: a string has
// no letter spacing, and a digit is narrower than its cell. A row's digits
// are the readings' in turn, so a run of them is copied from a strip of the
// readings' digits made once for them (Strip), not set one by one.
//
// How quickly it lights: a start's first frame is the
// time alone, on black; the band comes the frame after, and the wall fills
// in behind over the next two and comes in with the time drawn again on it
// once it is whole. A wake draws the time again only if the minute turned
// while asleep.
//
// Standby (always-on): only the digits on the numerals' edges, an outline
// made of digits, with the date and the next sun event; shifted each minute,
// about 8 % of the screen lit (designs/preview_wall.py).
class WallView extends WatchUi.WatchFace {

    // The layout, as fractions of the screen: the same numbers as
    // designs/preview_wall.py and designs/gen_wall.py
    private const CELL_W = 0.0250;
    private const CELL_H = 0.0375;
    private const DIGIT = 0.0290;              // the small digits' height
    private const TALL = 0.405;                // the numerals' digit height
    private const TOPS = [0.046, 0.549] as Array<Float>;    // their tops, hours then minutes
    private const BAND_TOP = 0.462;            // no cells between these
    private const BAND_BOTTOM = 0.538;
    private const BAND_MARGIN = 0.026;         // the band from the bezel
    private const BAND_GAP = 0.012;            // the least between its readings
    private const STANDBY_BAND = 0.052;        // standby's band: its height
    private const STANDBY_LEFT = 0.25;         // and its ends
    private const STANDBY_RIGHT = 0.75;
    private const MASS = 0.13;                 // the numerals' dim mass
    private const WALL = 0.15;                 // the wall's share of the neutral colour
    private const WALL_BRIGHT = 0.22;          // and in the fluorescent looks
    private const STANDBY = 0.80;              // the digits' share in standby
    private const TITLE = 0.050;               // the look's name, for a moment
    private const COLS = 41;
    private const ROWS = 27;
    private const BATCH = 14;                  // rows of the wall per frame: it fills in two
    private const DIGITS = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] as Array<String>;

    private var _w as Float = 454.0;
    private var _ox as Float = 0.0;            // where column and row 0 are, in px
    private var _oy as Float = 0.0;
    private var _cellW as Float = 0.0;
    private var _cellH as Float = 0.0;
    private var _dimFont as FontType = Graphics.FONT_XTINY;
    private var _litFont as FontType = Graphics.FONT_XTINY;
    private var _bigFont as FontType = Graphics.FONT_NUMBER_HOT;
    // The faces drawn with: Roboto Condensed and Bionic Bold, or where a watch
    // has none of them (the Venu 3, the Forerunner 570) the nearest it has
    private var _dimFace as Number = Lib.Ink.CONDENSED_REGULAR;
    private var _litFace as Number = Lib.Ink.CONDENSED_BOLD;
    private var _bigFace as Number = Lib.Ink.BIONIC_BOLD;
    private var _dimEm as Float = 0.0;
    private var _litEm as Float = 0.0;
    private var _bigEm as Float = 0.0;
    private var _dimAdvance as Float = 0.0;
    private var _litAdvance as Float = 0.0;

    private var _values as Array<String> = [] as Array<String>;
    private var _stream as Array<Number> = [0] as Array<Number>;
    private var _colors as Lib.Numbers.Colors = Lib.Numbers.colors(Lib.Look.YOURS);
    private var _look as Number = Lib.Look.YOURS;
    private var _day as Number = 0;           // the daily look's day
    private var _minute as Number = -1;
    private var _hour as Number = -1;
    private var _stamp as Number = -1;         // the minute read last, since 1970 (a long sleep can end on the same minute)
    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;
    private var _titled as Boolean = false;
    private var _bandDirty as Boolean = true;
    private var _frameDirty as Boolean = true;
    private var _pieces as Array<Lib.Numbers.Piece> = [] as Array<Lib.Numbers.Piece>;
    private var _targets as Array<Lib.Numbers.Target> = [] as Array<Lib.Numbers.Target>;

    private var _failed as Boolean = false;    // no room in the graphics pool
    private var _baseRef as Graphics.BufferedBitmapReference? = null;
    private var _frameRef as Graphics.BufferedBitmapReference? = null;
    private var _base as Graphics.BufferedBitmap? = null;
    private var _frame as Graphics.BufferedBitmap? = null;
    private var _baseRow as Number = 0;        // the next row of the wall to draw
    private var _blank as Boolean = true;      // the wall's bitmap is black: no wall drawn in it yet
    private var _late as Boolean = true;       // a start's first frame: the time alone
    var composed as Number = 0;                // for the tests: how often the time was drawn into the frame
    private var _lit as Strip? = null;         // the readings' digits in a row, lit and dim
    private var _dim as Strip? = null;
    private var _titleFont as FontType? = null;  // the look's name's
    private var _log as Lib.Timing.Log;        // how quickly it lights

    function initialize() {
        WatchFace.initialize();
        _log = new Lib.Timing.Log("Wall");
        _burnIn = Lib.Aod.required();
        reloadSettings();
    }

    function reloadSettings() as Void {
        _look = Lib.Look.mode();
        _colors = Lib.Numbers.colors(_look);
        _day = Lib.Look.today();
        _stamp = -1;
        _hour = -1;
        _baseRow = 0;
        _bandDirty = true;
        _frameDirty = true;
    }

    // The complication a press and hold at (x, y) opens, or null on the time
    function targetAt(x as Number, y as Number) as Complications.Type? {
        for (var i = 0; i < _targets.size(); i++) {
            if (_targets[i].contains(x, y)) {
                return _targets[i].type;
            }
        }
        return null;
    }

    function onLayout(dc as Dc) as Void {
        _w = dc.getWidth().toFloat();
        _cellW = CELL_W * _w;
        _cellH = CELL_H * _w;
        _ox = (1.0 - COLS * CELL_W) / 2.0 * _w;
        _oy = (1.0 - ROWS * CELL_H) / 2.0 * _w;
        _dimFace = Lib.Ink.resolve(Lib.Ink.CONDENSED_REGULAR);
        _litFace = Lib.Ink.resolve(Lib.Ink.CONDENSED_BOLD);
        _bigFace = Lib.Ink.resolve(Lib.Ink.BIONIC_BOLD);
        var dim = _dimFace;
        var lit = _litFace;
        var big = _bigFace;
        var dimSize = Lib.Numbers.fontSize(dim, DIGIT * _w);
        var litSize = Lib.Numbers.fontSize(lit, DIGIT * _w);
        var bigSize = Lib.Numbers.fontSize(big, TALL * _w);
        _dimFont = Lib.Numbers.font(dim, dimSize);
        _litFont = Lib.Numbers.font(lit, litSize);
        _bigFont = Lib.Numbers.font(big, bigSize);
        _dimEm = dimSize * 1000.0 / Lib.Ink.HEIGHT[dim];
        _litEm = litSize * 1000.0 / Lib.Ink.HEIGHT[lit];
        _bigEm = bigSize * 1000.0 / Lib.Ink.HEIGHT[big];
        _dimAdvance = dc.getTextWidthInPixels("0", _dimFont).toFloat();
        _litAdvance = dc.getTextWidthInPixels("0", _litFont).toFloat();
        _baseRow = 0;
        _bandDirty = true;
        _frameDirty = true;
    }

    // ------------------------------------------------------------ state

    private function refresh() as Void {
        var clock = System.getClockTime();
        var stamp = Time.now().value() / 60;
        if (stamp != _stamp) {
            _stamp = stamp;
            _minute = clock.min;
            _values = Lib.Numbers.read();
            sample();
            _stream = Lib.Numbers.stream(_values);
            _bandDirty = true;
            _frameDirty = true;
            if (clock.hour != _hour) {
                _hour = clock.hour;
                _baseRow = 0;          // the wall takes in the readings as they are, once an hour
            }
        } else if (_awake) {
            live();
        }
    }

    // While awake the heart rate moves on its own time
    (:live)
    private function live() as Void {
        var heart = Lib.Daily.heartRate();
        if (!heart.equals(_values[Lib.Numbers.HEART])) {
            _values[Lib.Numbers.HEART] = heart;
            _bandDirty = true;
        }
    }

    (:sample)
    private function live() as Void {
    }

    (:live)
    private function sample() as Void {
    }

    // The screenshots' readings (sample.jungle)
    (:sample)
    private function sample() as Void {
        _values = ["10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "72", "6214", "82", "1240", "12"] as Array<String>;
    }

    // For the tests: fixed readings, in the order of Lib.Numbers.Value
    function setValues(values as Array<String>) as Void {
        refresh();
        _values = values;
        _stream = Lib.Numbers.stream(values);
        _baseRow = 0;
        _bandDirty = true;
        _frameDirty = true;
    }

    function setAwake(awake as Boolean) as Void {
        _awake = awake;
        _burnIn = true;
        _bandDirty = true;
        _frameDirty = true;
    }

    // For the tests: whether the wall is all drawn
    function built() as Boolean {
        return _baseRow >= ROWS;
    }

    // Nothing left to draw over later frames: the wall whole and the time on it
    function settled() as Boolean {
        return !_late && !_bandDirty && (_failed || _base == null || (_baseRow >= ROWS && !_frameDirty));
    }

    function onEnterSleep() as Void {
        _awake = false;
        _bandDirty = true;
        WatchUi.requestUpdate();
    }

    // The frame keeps the time as it was last drawn awake; a minute that
    // turned in standby has already marked it to be drawn again
    function onExitSleep() as Void {
        _log.wake();
        _awake = true;
        _bandDirty = true;
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------ drawing

    function onUpdate(dc as Dc) as Void {
        var started = System.getTimer();
        if (_look == Lib.Look.DAILY && Lib.Look.today() != _day) {
            reloadSettings();     // a new day, and on a Monday perhaps a muted week
        }
        refresh();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        var thin = !_awake && _burnIn;
        var titled = !thin && Lib.Look.shown();
        if (titled != _titled) {
            _titled = titled;
            _bandDirty = true;
        }
        var late = _late && !thin;             // the band the frame after
        _late = false;
        if (_bandDirty && !late) {
            layoutBand(dc, thin);
            _bandDirty = false;
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var off = [0, 0];
        if (thin) {
            off = Lib.Aod.offset(_minute, (_w * 0.006).toNumber());
            drawNumerals(dc, Numerals.EDGE, off[0], off[1], _dimFont, _dimEm, _dimAdvance,
                         Lib.Numbers.scale(_colors.neutral, STANDBY), null);
        } else {
            drawAwake(dc);
        }
        for (var i = 0; i < _pieces.size() && !late; i++) {
            _pieces[i].draw(dc, off[0], off[1], false);
        }
        if (late) {
            WatchUi.requestUpdate();
        }
        if (titled) {
            if (_titleFont == null) {
                _titleFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (_w * TITLE * 1.173).toNumber(), Graphics.FONT_XTINY);
            }
            dc.setColor(_colors.neutral, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_w / 2.0, _w / 2.0, _titleFont as FontType,
                        Lib.Look.title(_look, Lib.Numbers.names()), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        if (!thin) {
            _log.frame(started, settled());
        }
    }

    // The wall and the time, from the bitmaps; without them, the time alone.
    // A frame does one of two things: the time drawn again on the wall as
    // it is (a new minute, or a start's first frame, on black), or the next
    // rows of the wall, and the time on it once it is whole. So a new time
    // is never late for the wall, and the time is drawn twice on a start.
    private function drawAwake(dc as Dc) as Void {
        var frame = bitmaps(dc);
        if (frame == null) {
            drawTime(dc);
            return;
        }
        if (_frameDirty) {
            compose(frame);
        } else if (_baseRow < ROWS) {
            drawWall((_base as Graphics.BufferedBitmap).getDc());
            if (_baseRow >= ROWS) {
                compose(frame);
            }
        }
        if (_baseRow < ROWS) {
            WatchUi.requestUpdate();   // keep going
        }
        dc.drawBitmap(0, 0, frame);
    }

    // The frame: the wall, with the time on it
    private function compose(frame as Graphics.BufferedBitmap) as Void {
        var fdc = frame.getDc();
        if (fdc has :setAntiAlias) {
            fdc.setAntiAlias(true);
        }
        if (_blank) {
            fdc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            fdc.clear();
        } else {
            fdc.drawBitmap(0, 0, _base as Graphics.BufferedBitmap);
        }
        drawTime(fdc);
        _frameDirty = false;
        composed++;
    }

    // The readings' digits in a strip `cells` past their end, made again
    // only when the readings or the look's colour change; null when the pool
    // has no room (then drawText)
    private function strip(held as Strip?, font as FontType, color as Number, background as Number, advance as Float,
                           cells as Number) as Strip? {
        if (held != null && held.stream == _stream && held.color == color && held.font == font) {
            return held;
        }
        return Strip.make(font, color, background, _stream, _stream.size() + cells, _cellW, _cellW / 2.0 - advance / 2.0);
    }

    // The bitmaps, made once; null when the pool has no room for them
    private function bitmaps(dc as Dc) as Graphics.BufferedBitmap? {
        if (_failed || !(Graphics has :createBufferedBitmap)) {
            return null;
        }
        if (_base == null || _frame == null) {
            try {
                var options = {:width => dc.getWidth(), :height => dc.getHeight()};
                if (_baseRef == null) {
                    _baseRef = Graphics.createBufferedBitmap(options);
                }
                if (_frameRef == null) {
                    _frameRef = Graphics.createBufferedBitmap(options);
                }
                _base = (_baseRef as Graphics.BufferedBitmapReference).get() as Graphics.BufferedBitmap?;
                _frame = (_frameRef as Graphics.BufferedBitmapReference).get() as Graphics.BufferedBitmap?;
            } catch (e) {
                _failed = true;
                return null;
            }
            if (_base == null || _frame == null) {
                _baseRef = null;   // reclaimed by the pool; make them again next time
                _frameRef = null;
                _base = null;
                _frame = null;
                return null;
            }
            var bdc = (_base as Graphics.BufferedBitmap).getDc();
            bdc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            bdc.clear();
            if (bdc has :setAntiAlias) {
                bdc.setAntiAlias(true);
            }
            _baseRow = 0;
            _blank = true;
            _frameDirty = true;
        }
        return _frame;
    }

    // The next few rows of the dim wall, each wiped first so a new wall
    // replaces the old one without a flash. The readings are those of the
    // wall's first row (a minute turning while it fills changes nothing).
    private function drawWall(dc as Dc) as Void {
        var color = Lib.Numbers.scale(_colors.neutral, _colors.fluorescent ? WALL_BRIGHT : WALL);
        var end = (_baseRow + BATCH < ROWS) ? _baseRow + BATCH : ROWS;
        var radius = _w / 2.0 + _cellW;
        var centre = _w / 2.0;
        if (_baseRow == 0 || _dim == null) {
            _dim = strip(_dim, _dimFont, color, Graphics.COLOR_BLACK, _dimAdvance, COLS);
        }
        var tiles = _dim;
        var stream = (tiles != null) ? tiles.stream : _stream;
        var length = stream.size();
        for (var row = _baseRow; row < end; row++) {
            var y = _oy + row * _cellH;
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.fillRectangle(0, y.toNumber() - 1, _w.toNumber(), _cellH.toNumber() + 2);
            var frac = (y / _w).toFloat();
            if (frac + CELL_H > BAND_TOP && frac < BAND_BOTTOM) {
                continue;
            }
            var mid = y + _cellH / 2.0;
            var top = Lib.Ink.top(_dimFace, _dimFont, mid, _dimEm);
            var dy = (mid - centre) * (mid - centre);
            if (dy > radius * radius) {
                continue;
            }
            // the cells whose middles are within the circle: a run from c0 to c1
            var reach = Math.sqrt(radius * radius - dy);
            var c0 = Math.ceil((centre - reach - _ox) / _cellW - 0.5).toNumber();
            var c1 = Math.floor((centre + reach - _ox) / _cellW - 0.5).toNumber();
            c0 = (c0 < 0) ? 0 : c0;
            c1 = (c1 > COLS - 1) ? COLS - 1 : c1;
            if (c1 < c0) {
                continue;
            }
            if (tiles != null) {
                tiles.draw(dc, (row * COLS + c0) % length, _ox + c0 * _cellW, _ox + (c1 + 1) * _cellW, top, y, y + _cellH);
                continue;
            }
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            for (var col = c0; col <= c1; col++) {
                dc.drawText(_ox + col * _cellW + _cellW / 2.0 - _dimAdvance / 2.0, top, _dimFont,
                            DIGITS[stream[(row * COLS + col) % length]], Graphics.TEXT_JUSTIFY_LEFT);
            }
        }
        dc.clearClip();
        _baseRow = end;
        _blank = false;
    }

    // The numerals' mass, then their lit digits
    private function drawTime(dc as Dc) as Void {
        var solid = _colors.fluorescent;
        var mass = solid ? _colors.sun : Lib.Numbers.scale(_colors.neutral, MASS);
        dc.setColor(mass, Graphics.COLOR_TRANSPARENT);
        var face = _bigFace;
        var hours = _values[Lib.Numbers.HOURS];
        var minutes = _values[Lib.Numbers.MINUTES];
        var pen = _w / 2.0 - dc.getTextWidthInPixels(hours, _bigFont) / 2.0;
        var mid = TALL / 2.0;
        dc.drawText(pen, Lib.Ink.top(face, _bigFont, (TOPS[0] + mid) * _w, _bigEm), _bigFont, hours, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(pen, Lib.Ink.top(face, _bigFont, (TOPS[1] + mid) * _w, _bigEm), _bigFont, minutes, Graphics.TEXT_JUSTIFY_LEFT);
        var color = solid ? Graphics.COLOR_BLACK : _colors.neutral;
        _lit = strip(_lit, _litFont, color, Graphics.COLOR_TRANSPARENT, _litAdvance, LIT_RUN);
        drawNumerals(dc, Numerals.LIT, 0, 0, _litFont, _litEm, _litAdvance, color, _lit);
        dc.clearClip();
    }

    // The digits a table says light up, for the time on the clock now:
    // each run of lit cells in a row copied from `tiles`, or without it each
    // digit set as text
    private function drawNumerals(dc as Dc, table as Array<Array<Array<Number>>>, ox as Number, oy as Number, font as FontType,
                                  em as Float, advance as Float, color as Number, tiles as Strip?) as Void {
        var face = (font == _litFont) ? _litFace : _dimFace;
        var stream = _stream;
        var length = stream.size();
        var left = Graphics.TEXT_JUSTIFY_LEFT;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var blocks = [_values[Lib.Numbers.HOURS], _values[Lib.Numbers.MINUTES]] as Array<String>;
        for (var b = 0; b < 2; b++) {
            var chars = blocks[b].toCharArray();
            for (var place = 0; place < 2 && place < chars.size(); place++) {
                var d = chars[place].toNumber() - 48;
                if (d < 0 || d > 9) {
                    continue;
                }
                var rows = table[b][d];
                var first = (place == 0) ? Numerals.FIRST : Numerals.SECOND;
                var start = Numerals.START[b];
                for (var r = 0; r < rows.size(); r++) {
                    var bits = rows[r];
                    if (bits == 0) {
                        continue;
                    }
                    var row = start + r;
                    var mid = _oy + row * _cellH + _cellH / 2.0;
                    var top = Lib.Ink.top(face, font, mid, em) + oy;
                    var j = 0;
                    var run = -1;                  // where the run of lit cells began
                    while (bits != 0 || run >= 0) {
                        var on = (bits & 1) != 0;
                        if (tiles != null) {
                            if (on && run < 0) {
                                run = j;
                            } else if (!on && run >= 0) {
                                var a = first + run;
                                var y = _oy + row * _cellH + oy;
                                tiles.draw(dc, (row * COLS + a) % length, _ox + a * _cellW + ox, _ox + (first + j) * _cellW + ox, top, y, y + _cellH);
                                run = -1;
                            }
                        } else if (on) {
                            var col = first + j;
                            dc.drawText(_ox + col * _cellW + _cellW / 2.0 - advance / 2.0 + ox, top, font,
                                        DIGITS[stream[(row * COLS + col) % length]], left);
                        }
                        bits = bits >> 1;
                        j++;
                    }
                }
            }
        }
    }

    // Where the band's readings go
    private function layoutBand(dc as Dc, thin as Boolean) as Void {
        var bold = Lib.Ink.BIONIC_BOLD;
        var medium = Lib.Ink.usable(Lib.Ink.BIONIC_MEDIUM);    // Bold where a watch lacks it
        var c = _colors;
        var pieces = [] as Array<Lib.Numbers.Piece>;
        var targets = [] as Array<Lib.Numbers.Target>;
        if (thin) {
            var items = [
                Lib.Numbers.reading(_values, Lib.Numbers.DATE, medium, Lib.Numbers.scale(c.neutral, STANDBY), null),
                Lib.Numbers.reading(_values, Lib.Numbers.SUN_TIME, bold, Lib.Numbers.scale(c.sun, STANDBY), null)
            ] as Array<Lib.Numbers.Item>;
            Lib.Numbers.place(dc, pieces, targets, items, STANDBY_BAND, STANDBY_LEFT, STANDBY_RIGHT, 0.5 - STANDBY_BAND / 2.0);
        } else if (!_titled) {
            var items = [
                Lib.Numbers.reading(_values, Lib.Numbers.DATE, bold, c.neutral, Complications.COMPLICATION_TYPE_CALENDAR_EVENTS),
                Lib.Numbers.reading(_values, Lib.Numbers.SUN_TIME, bold, c.sun, Complications.COMPLICATION_TYPE_SUNRISE),
                Lib.Numbers.reading(_values, Lib.Numbers.COUNTDOWN, medium, Lib.Numbers.scale(c.sun, c.second), Complications.COMPLICATION_TYPE_SUNRISE),
                Lib.Numbers.reading(_values, Lib.Numbers.TEMP, medium, c.weather, Complications.COMPLICATION_TYPE_CURRENT_WEATHER),
                Lib.Numbers.reading(_values, Lib.Numbers.HEART, bold, c.body, Complications.COMPLICATION_TYPE_HEART_RATE)
            ] as Array<Lib.Numbers.Item>;
            var sum = 0.0;
            for (var i = 0; i < items.size(); i++) {
                sum += Lib.Numbers.ratio(items[i].room, items[i].face);
            }
            // from the middle outward both ways: half the height in the formula
            var h = 2.0 * Lib.Numbers.fit(2.0 * sum, BAND_GAP * (items.size() - 1), 0.0, null, BAND_MARGIN);
            var half = Lib.Numbers.half(0.5 - h / 2.0, BAND_MARGIN);
            Lib.Numbers.place(dc, pieces, targets, items, h, 0.5 - half, 0.5 + half, 0.5 - h / 2.0);
        }
        _pieces = pieces;
        _targets = targets;
    }
}
