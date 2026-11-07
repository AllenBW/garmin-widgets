import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

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
// that and draws the band. The digits are placed one by one: a string has
// no letter spacing, and a digit is narrower than its cell.
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
    private const BATCH = 6;                   // rows of the wall per frame
    private const DIGITS = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] as Array<String>;

    private var _w as Float = 454.0;
    private var _ox as Float = 0.0;            // where column and row 0 are, in px
    private var _oy as Float = 0.0;
    private var _cellW as Float = 0.0;
    private var _cellH as Float = 0.0;
    private var _dimFont as FontType = Graphics.FONT_XTINY;
    private var _litFont as FontType = Graphics.FONT_XTINY;
    private var _bigFont as FontType = Graphics.FONT_NUMBER_HOT;
    private var _dimEm as Float = 0.0;
    private var _litEm as Float = 0.0;
    private var _bigEm as Float = 0.0;
    private var _dimAdvance as Float = 0.0;
    private var _litAdvance as Float = 0.0;

    private var _values as Array<String> = [] as Array<String>;
    private var _stream as Array<Number> = [0] as Array<Number>;
    private var _colors as Lib.Numbers.Colors = Lib.Numbers.colors(Lib.Look.YOURS);
    private var _look as Number = Lib.Look.YOURS;
    private var _minute as Number = -1;
    private var _hour as Number = -1;
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
    private var _frameShown as Boolean = false;

    function initialize() {
        WatchFace.initialize();
        _burnIn = Lib.Aod.required();
        reloadSettings();
    }

    function reloadSettings() as Void {
        _look = Lib.Look.mode();
        _colors = Lib.Numbers.colors(_look);
        _minute = -1;
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
        var dim = Lib.Ink.CONDENSED_REGULAR;
        var lit = Lib.Ink.CONDENSED_BOLD;
        var big = Lib.Ink.BIONIC_BOLD;
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
        if (clock.min != _minute) {
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

    function onEnterSleep() as Void {
        _awake = false;
        _bandDirty = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _awake = true;
        _minute = -1;
        _bandDirty = true;
        _frameDirty = true;
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------ drawing

    function onUpdate(dc as Dc) as Void {
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
        if (_bandDirty) {
            layoutBand(dc, thin);
            _bandDirty = false;
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var off = [0, 0];
        if (thin) {
            off = Lib.Aod.offset(_minute, (_w * 0.006).toNumber());
            drawNumerals(dc, Numerals.EDGE, off[0], off[1], _dimFont, _dimEm, _dimAdvance,
                         Lib.Numbers.scale(_colors.neutral, STANDBY));
        } else {
            drawAwake(dc);
        }
        for (var i = 0; i < _pieces.size(); i++) {
            _pieces[i].draw(dc, off[0], off[1], false);
        }
        if (titled) {
            dc.setColor(_colors.neutral, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_w / 2.0, _w / 2.0,
                        Lib.Fmt.vectorFont("RobotoCondensedBold", (_w * TITLE * 1.173).toNumber(), Graphics.FONT_XTINY),
                        Lib.Look.title(_look, Lib.Numbers.NAMES), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // The wall and the time, from the bitmaps; without them, the time alone
    private function drawAwake(dc as Dc) as Void {
        var frame = bitmaps(dc);
        if (frame == null) {
            drawTime(dc);
            return;
        }
        var base = _base as Graphics.BufferedBitmap;
        var built = false;
        if (_baseRow < ROWS) {
            drawWall(base.getDc());
            built = true;
            if (_baseRow < ROWS) {
                WatchUi.requestUpdate();   // keep going
            }
        }
        // The frame while the wall is first filling, then only for news
        if (_frameDirty || (built && (!_frameShown || _baseRow >= ROWS))) {
            var fdc = frame.getDc();
            if (fdc has :setAntiAlias) {
                fdc.setAntiAlias(true);
            }
            fdc.drawBitmap(0, 0, base);
            drawTime(fdc);
            _frameDirty = false;
            _frameShown = _baseRow >= ROWS;
        }
        dc.drawBitmap(0, 0, frame);
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
            _frameDirty = true;
            _frameShown = false;
        }
        return _frame;
    }

    // The next few rows of the dim wall, each wiped first so a new wall
    // replaces the old one without a flash
    private function drawWall(dc as Dc) as Void {
        var color = Lib.Numbers.scale(_colors.neutral, _colors.fluorescent ? WALL_BRIGHT : WALL);
        var end = (_baseRow + BATCH < ROWS) ? _baseRow + BATCH : ROWS;
        var left = Graphics.TEXT_JUSTIFY_LEFT;
        var radius = _w / 2.0 + _cellW;
        var centre = _w / 2.0;
        var stream = _stream;
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
            var top = Lib.Ink.top(Lib.Ink.CONDENSED_REGULAR, _dimFont, mid, _dimEm);
            var dy = (mid - centre) * (mid - centre);
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            for (var col = 0; col < COLS; col++) {
                var cx = _ox + col * _cellW + _cellW / 2.0;
                if ((cx - centre) * (cx - centre) + dy > radius * radius) {
                    continue;
                }
                dc.drawText(cx - _dimAdvance / 2.0, top, _dimFont, DIGITS[stream[(row * COLS + col) % length]], left);
            }
        }
        _baseRow = end;
    }

    // The numerals' mass, then their lit digits
    private function drawTime(dc as Dc) as Void {
        var solid = _colors.fluorescent;
        var mass = solid ? _colors.sun : Lib.Numbers.scale(_colors.neutral, MASS);
        dc.setColor(mass, Graphics.COLOR_TRANSPARENT);
        var face = Lib.Ink.BIONIC_BOLD;
        var hours = _values[Lib.Numbers.HOURS];
        var minutes = _values[Lib.Numbers.MINUTES];
        var pen = _w / 2.0 - dc.getTextWidthInPixels(hours, _bigFont) / 2.0;
        var mid = TALL / 2.0;
        dc.drawText(pen, Lib.Ink.top(face, _bigFont, (TOPS[0] + mid) * _w, _bigEm), _bigFont, hours, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(pen, Lib.Ink.top(face, _bigFont, (TOPS[1] + mid) * _w, _bigEm), _bigFont, minutes, Graphics.TEXT_JUSTIFY_LEFT);
        drawNumerals(dc, Numerals.LIT, 0, 0, _litFont, _litEm, _litAdvance, solid ? Graphics.COLOR_BLACK : _colors.neutral);
    }

    // The digits a table says light up, for the time on the clock now
    private function drawNumerals(dc as Dc, table as Array<Array<Array<Number>>>, ox as Number, oy as Number, font as FontType,
                                  em as Float, advance as Float, color as Number) as Void {
        var face = (font == _litFont) ? Lib.Ink.CONDENSED_BOLD : Lib.Ink.CONDENSED_REGULAR;
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
                    while (bits != 0) {
                        if ((bits & 1) != 0) {
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
        var medium = Lib.Ink.BIONIC_MEDIUM;
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
