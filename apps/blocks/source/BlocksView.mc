import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
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
    private var _minute as Number = -1;
    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;
    private var _dirty as Boolean = true;
    private var _titled as Boolean = false;
    private var _pieces as Array<Lib.Numbers.Piece> = [] as Array<Lib.Numbers.Piece>;
    private var _targets as Array<Lib.Numbers.Target> = [] as Array<Lib.Numbers.Target>;

    function initialize() {
        WatchFace.initialize();
        _burnIn = Lib.Aod.required();
        reloadSettings();
    }

    function reloadSettings() as Void {
        _look = Lib.Look.mode();
        _colors = Lib.Numbers.colors(_look);
        _minute = -1;
        _dirty = true;
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
        var minute = System.getClockTime().min;
        if (minute != _minute) {
            _minute = minute;
            _values = Lib.Numbers.read();
            sample();
            _dirty = true;
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
    }

    function setAwake(awake as Boolean) as Void {
        _awake = awake;
        _burnIn = true;
        _dirty = true;
    }

    function onEnterSleep() as Void {
        _awake = false;
        _dirty = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _awake = true;
        _minute = -1;
        _dirty = true;
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------ drawing

    function onUpdate(dc as Dc) as Void {
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
        if (_dirty) {
            layout(dc, thin);
            _dirty = false;
        }
        var off = thin ? Lib.Aod.offset(_minute, (dc.getWidth() * 0.006).toNumber()) : [0, 0];
        for (var i = 0; i < _pieces.size(); i++) {
            _pieces[i].draw(dc, off[0], off[1], thin);
        }
        if (titled) {
            dc.setColor(_colors.neutral, Graphics.COLOR_TRANSPARENT);
            dc.drawText(dc.getWidth() / 2, dc.getHeight() * 0.13,
                        Lib.Fmt.vectorFont("RobotoCondensedBold", (dc.getWidth() * TITLE * 1.173).toNumber(), Graphics.FONT_XTINY),
                        Lib.Look.title(_look, Lib.Numbers.NAMES), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
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

    // Where each number goes, once a change of a reading or a mode asks for it
    private function layout(dc as Dc, thin as Boolean) as Void {
        var bold = Lib.Ink.BIONIC_BOLD;
        var medium = Lib.Ink.BIONIC_MEDIUM;
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
        _pieces = pieces;
        _targets = targets;
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
