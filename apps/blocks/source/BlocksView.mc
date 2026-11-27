import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Blocks: the screen filled with numbers, no labels. The hours upper left
// and the minutes lower right sit on a diagonal, the bezel crops nothing,
// and the other readings fill the two free corners, each row as large as
// the curve allows. Colour tells the families apart (Lib.Numbers): the sun
// beside the hours (the next sunset or sunrise, then the countdown to it),
// heart rate, temperature, high and low beside the minutes, the date and
// the wind on top, steps, Body Battery and altitude below.
//
// Holding the time steps through the looks (Lib.Look), the look's name
// standing in for the top row for a moment.
//
// Standby (always-on): the time, the date, the sun, heart rate and the
// temperature in thin outlines, shifted each minute; about 9 % of the screen
// lit on the simulator (designs/preview_blocks.py says a little less: its
// outlines are thinner).
//
// How quickly it lights: a start's first frame is the
// hours and minutes alone, the readings the frame after. Awake, the numbers
// are drawn once into a bitmap and copied from it until a reading or the
// look changes; a wake within the minute copies it again, drawing nothing.
// A frame that lays them out draws them straight to the screen, and the
// next one into the bitmap, so no frame does both.
class BlocksView extends WatchUi.WatchFace {

    // The layout, as fractions of the screen: the same numbers as
    // designs/preview_blocks.py
    private const MARGIN = 0.022;         // from the bezel
    private const ROW_GAP = 0.015;        // between rows
    private const ITEM_GAP = 0.020;       // the least between readings in a row
    private const MIDDLE = 0.500;
    private const TIME = 0.300;           // the hours' and minutes' digit height
    private const CLEAR = 0.006;          // from the time's corner to the bezel
    private const TITLE = 0.050;          // the look's name, for a moment

    private var _values as Array<String> = [] as Array<String>;
    private var _colors as Lib.Numbers.Colors = Lib.Numbers.colors(Lib.Look.YOURS);
    private var _look as Number = Lib.Look.YOURS;
    private var _day as Number = 0;           // the daily look's day
    private var _minute as Number = -1;
    private var _stamp as Number = -1;        // the minute read last, since 1970 (a long sleep can end on the same minute)
    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;
    private var _dirty as Boolean = true;     // the awake numbers to lay out and draw again
    private var _thinDirty as Boolean = true; // standby's to lay out again
    private var _titled as Boolean = false;
    private var _late as Boolean = true;      // a start's first frame: the time alone
    private var _pieces as Array<Lib.Numbers.Piece> = [] as Array<Lib.Numbers.Piece>;
    private var _thinPieces as Array<Lib.Numbers.Piece> = [] as Array<Lib.Numbers.Piece>;
    private var _targets as Array<Lib.Numbers.Target> = [] as Array<Lib.Numbers.Target>;
    private var _failed as Boolean = false;   // no room in the graphics pool: drawn straight to the screen
    private var _faceRef as Graphics.BufferedBitmapReference? = null;
    private var _face as Graphics.BufferedBitmap? = null;   // the awake numbers, drawn once
    private var _drawn as Boolean = false;    // the bitmap holds them as they are
    private var _titleFont as FontType? = null;
    var composed as Number = 0;               // for the tests: how often the numbers were drawn into the bitmap
    private var _log as Lib.Timing.Log;        // how quickly it lights

    function initialize() {
        WatchFace.initialize();
        _log = new Lib.Timing.Log("Blocks");
        _burnIn = Lib.Aod.required();
        reloadSettings();
    }

    function reloadSettings() as Void {
        _look = Lib.Look.mode();
        _colors = colors(_look);
        _day = Lib.Look.today();
        _stamp = -1;
        _dirty = true;
        _thinDirty = true;
    }

    // The look's colours: your look's as chosen in the phone app, the
    // watch's settings menu or the watch face editor, whichever was changed
    // last (Lib.Config.read): the set of the families' colours (Style) and
    // the time and date's (DataColor)
    private function colors(look as Number) as Lib.Numbers.Colors {
        if (look != Lib.Look.YOURS) {
            return Lib.Numbers.colors(look);
        }
        var s = Lib.Config.read(Lib.Numbers.PALETTES.size(), [] as Array<Complications.Type>);
        return Lib.Numbers.yours(s[0], s[2]);
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
        _dirty = true;
    }

    // ------------------------------------------------------------ state

    private function refresh() as Void {
        var stamp = Time.now().value() / 60;
        if (stamp != _stamp) {
            _stamp = stamp;
            _minute = System.getClockTime().min;
            _values = Lib.Numbers.read();
            sample();
            _dirty = true;
            _thinDirty = true;
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
            _dirty = true;
            _thinDirty = true;
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
        _dirty = true;
        _thinDirty = true;
    }

    function setAwake(awake as Boolean) as Void {
        _awake = awake;
        _burnIn = true;
        _dirty = true;
        _thinDirty = true;
    }

    // Nothing left to show over later frames (the bitmap may still be
    // drawn at the next update: what it shows is on screen already)
    function settled() as Boolean {
        return !_late && !_dirty;
    }

    function onEnterSleep() as Void {
        _awake = false;
        WatchUi.requestUpdate();
    }

    // The bitmap keeps the numbers as they were last drawn awake; a minute
    // that turned in standby has already marked them to be drawn again
    function onExitSleep() as Void {
        _log.wake();
        _awake = true;
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------ drawing

    function onUpdate(dc as Dc) as Void {
        var started = System.getTimer();
        if (_look == Lib.Look.DAILY && Lib.Look.today() != _day) {
            reloadSettings();     // a new day, and on a Monday perhaps a muted week
        }
        refresh();
        var titled = _awake && Lib.Look.shown();
        if (titled != _titled) {
            _titled = titled;
            _dirty = true;
        }
        var thin = !_awake && _burnIn;
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(!thin);    // hard outlines: no faint pixels to count against the 10 %
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (thin) {
            if (_thinDirty) {
                _thinPieces = layout(dc, true, false);
                _thinDirty = false;
            }
            var off = Lib.Aod.offset(_minute, (dc.getWidth() * 0.006).toNumber());
            for (var i = 0; i < _thinPieces.size(); i++) {
                _thinPieces[i].draw(dc, off[0], off[1], true);
            }
            return;
        }
        var late = _late;
        _late = false;
        if (late) {
            var time = layout(dc, false, true);
            for (var i = 0; i < time.size(); i++) {
                time[i].draw(dc, 0, 0, false);
            }
            WatchUi.requestUpdate();     // the readings next
        } else {
            drawAwake(dc);
        }
        if (titled) {
            if (_titleFont == null) {
                _titleFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (dc.getWidth() * TITLE * 1.173).toNumber(), Graphics.FONT_XTINY);
            }
            dc.setColor(_colors.neutral, Graphics.COLOR_TRANSPARENT);
            dc.drawText(dc.getWidth() / 2, dc.getHeight() * 0.13, _titleFont as FontType,
                        Lib.Look.title(_look, Lib.Numbers.names()), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        _log.frame(started, settled());
    }

    // The awake numbers: laid out and drawn straight to the screen when
    // something changed, drawn into the bitmap the frame after, and copied
    // from it from then on; without the bitmap, drawn every time
    private function drawAwake(dc as Dc) as Void {
        var fresh = _dirty;
        if (fresh) {
            _pieces = layout(dc, false, false);
            _dirty = false;
            _drawn = false;
        }
        var face = fresh ? null : bitmap(dc);
        if (face == null) {
            for (var i = 0; i < _pieces.size(); i++) {
                _pieces[i].draw(dc, 0, 0, false);
            }
            return;
        }
        if (!_drawn) {
            var fdc = face.getDc();
            if (fdc has :setAntiAlias) {
                fdc.setAntiAlias(true);
            }
            fdc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            fdc.clear();
            for (var i = 0; i < _pieces.size(); i++) {
                _pieces[i].draw(fdc, 0, 0, false);
            }
            _drawn = true;
            composed++;
        }
        dc.drawBitmap(0, 0, face);
    }

    // The bitmap, made once; null when the pool has no room for it
    private function bitmap(dc as Dc) as Graphics.BufferedBitmap? {
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
                _faceRef = null;      // reclaimed by the pool; make it again next time
                return null;
            }
            _drawn = false;
        }
        return _face;
    }

    // A reading, with the complication it opens
    private function item(value as Number, face as Number, color as Number, type as Complications.Type?) as Lib.Numbers.Item {
        return Lib.Numbers.reading(_values, value, face, color, type);
    }

    // The row's width per digit height, and its gaps
    private function perHeight(items as Array<Lib.Numbers.Item>) as Float {
        var sum = 0.0;
        for (var i = 0; i < items.size(); i++) {
            sum += Lib.Numbers.ratio(items[i].room, items[i].face);
        }
        return sum;
    }

    private function gaps(items as Array<Lib.Numbers.Item>) as Float {
        return ITEM_GAP * (items.size() - 1);
    }

    // Where each number goes, once a change of a reading or a mode asks for
    // it: the pieces to draw (awake, the targets too). `timeOnly`: the hours
    // and minutes alone, a start's first frame.
    private function layout(dc as Dc, thin as Boolean, timeOnly as Boolean) as Array<Lib.Numbers.Piece> {
        var bold = Lib.Ink.BIONIC_BOLD;
        var medium = Lib.Ink.usable(Lib.Ink.BIONIC_MEDIUM);    // Bold where a watch lacks it
        var c = _colors;
        var neutral = c.neutral;
        var sun = c.sun;
        var weather = c.weather;
        var body = c.body;
        var second = c.second;
        var third = c.third;
        var pieces = [] as Array<Lib.Numbers.Piece>;
        var targets = [] as Array<Lib.Numbers.Target>;

        // The time, hours and minutes on a diagonal, their outer corners at the bezel
        var hw = Lib.Numbers.ratio(_values[Lib.Numbers.HOURS], bold) * TIME;
        var hy = MIDDLE - ROW_GAP / 2.0 - TIME;
        var my = MIDDLE + ROW_GAP / 2.0;
        var hx = 0.5 - Lib.Numbers.half(hy, MARGIN) + CLEAR;
        var mx = 0.5 + Lib.Numbers.half(my + TIME, MARGIN) - hw - CLEAR;
        Lib.Numbers.place(dc, pieces, targets, [item(Lib.Numbers.HOURS, bold, neutral, null)] as Array<Lib.Numbers.Item>,
                          TIME, hx, hx + hw, hy);
        Lib.Numbers.place(dc, pieces, targets, [item(Lib.Numbers.MINUTES, bold, neutral, null)] as Array<Lib.Numbers.Item>,
                          TIME, mx, mx + hw, my);
        if (timeOnly) {
            return pieces;
        }

        // The corner right of the hours, up from the middle: the sun
        var xr = hx + hw + ROW_GAP;
        var y = MIDDLE - ROW_GAP / 2.0;
        var top = hy;
        var rows = [
            [item(Lib.Numbers.COUNTDOWN, medium, Lib.Numbers.scale(sun, second), Complications.COMPLICATION_TYPE_SUNRISE)],
            [item(Lib.Numbers.SUN_TIME, bold, sun, Complications.COMPLICATION_TYPE_SUNRISE)]
        ] as Array<Array<Lib.Numbers.Item>>;
        for (var i = 0; i < rows.size(); i++) {
            var row = rows[i];
            var h = Lib.Numbers.fit(perHeight(row), gaps(row), y - 0.5, xr - 0.5, MARGIN);
            Lib.Numbers.place(dc, pieces, targets, row, h, xr, 0.5 + Lib.Numbers.half(y - h, MARGIN), y - h);
            y -= h + ROW_GAP;
            top = (y + ROW_GAP < top) ? y + ROW_GAP : top;
        }

        // The corner left of the minutes, down from the middle: heart rate and the weather
        var xl = mx - ROW_GAP;
        y = MIDDLE + ROW_GAP / 2.0;
        var bottom = my + TIME;
        rows = [
            [item(Lib.Numbers.HEART, bold, body, Complications.COMPLICATION_TYPE_HEART_RATE),
             item(Lib.Numbers.TEMP, medium, weather, Complications.COMPLICATION_TYPE_CURRENT_WEATHER)],
            [item(Lib.Numbers.HIGH, medium, Lib.Numbers.scale(weather, second), Complications.COMPLICATION_TYPE_CURRENT_WEATHER),
             item(Lib.Numbers.LOW, medium, Lib.Numbers.scale(weather, third), Complications.COMPLICATION_TYPE_CURRENT_WEATHER)]
        ] as Array<Array<Lib.Numbers.Item>>;
        // (not the high and low in standby: the outlines would pass 9 % lit on the 43 mm)
        for (var i = 0; i < (thin ? 1 : rows.size()); i++) {
            var row = rows[i];
            var h = Lib.Numbers.fit(perHeight(row), gaps(row), y - 0.5, 0.5 - xl, MARGIN);
            Lib.Numbers.place(dc, pieces, targets, row, h, 0.5 - Lib.Numbers.half(y + h, MARGIN), xl, y);
            y += h + ROW_GAP;
            bottom = (y - ROW_GAP > bottom) ? y - ROW_GAP : bottom;
        }

        // Across the whole chord: the date and wind above, the body's rest below
        if (thin) {
            stack(dc, pieces, targets, [[item(Lib.Numbers.DATE, medium, Lib.Numbers.scale(neutral, 0.8), null)]] as Array<Array<Lib.Numbers.Item>>,
                  top, -1.0);
        } else {
            if (!_titled) {
                stack(dc, pieces, targets, [
                    [item(Lib.Numbers.DATE, bold, neutral, Complications.COMPLICATION_TYPE_CALENDAR_EVENTS),
                     item(Lib.Numbers.WIND, medium, Lib.Numbers.scale(weather, second), Complications.COMPLICATION_TYPE_CURRENT_WEATHER)]
                ] as Array<Array<Lib.Numbers.Item>>, top, -1.0);
            }
            stack(dc, pieces, targets, [
                [item(Lib.Numbers.STEPS, medium, Lib.Numbers.scale(body, second), Complications.COMPLICATION_TYPE_STEPS),
                 item(Lib.Numbers.BODY, medium, Lib.Numbers.scale(body, third), Complications.COMPLICATION_TYPE_BODY_BATTERY)],
                [item(Lib.Numbers.ALTITUDE, medium, Lib.Numbers.scale(neutral, third), Complications.COMPLICATION_TYPE_ALTITUDE)]
            ] as Array<Array<Lib.Numbers.Item>>, bottom, 1.0);
        }
        if (!thin) {
            _targets = targets;
        }
        return pieces;
    }

    // Rows outward from y, each as large as its chord allows
    private function stack(dc as Dc, pieces as Array<Lib.Numbers.Piece>, targets as Array<Lib.Numbers.Target>,
                           rows as Array<Array<Lib.Numbers.Item>>, y as Float, sign as Float) as Void {
        for (var i = 0; i < rows.size(); i++) {
            var row = rows[i];
            var edge = y + sign * ROW_GAP;
            var h = Lib.Numbers.fit(perHeight(row), gaps(row), edge - 0.5, null, MARGIN);
            if (h < 0.012) {
                return;
            }
            var half = Lib.Numbers.half(edge + sign * h, MARGIN);
            Lib.Numbers.place(dc, pieces, targets, row, h, 0.5 - half, 0.5 + half, (sign < 0.0) ? edge - h : edge);
            y = edge + sign * h;
        }
    }
}
