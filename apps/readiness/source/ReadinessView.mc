import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// The face: a Body Battery gauge
// up the left side and a stress gauge up the right, date and time in the
// middle, three tiles (sleep score, recovery, resting HR) and the training
// status along the bottom. Always-on keeps the hollow time and one summary
// line, shifted each minute.
//
// The colours: the Body Battery gauge in the accent (Accent: green, mint,
// lime, blue or violet, the energy cool), the stress gauge in the data
// colour (DataColor: orange, amber, red, rose or gold, the strain warm),
// the time white. Holding the time steps through the looks (Lib.Look): your
// colours, high visibility (the Body Battery gauge and the training status
// fluorescent, the rest white), low light (ember and cream), and a pair of
// gauge colours a day; the date shows the look's name for a moment.
class ReadinessView extends WatchUi.WatchFace {

    // Palette
    private const WHITE = 0xF2F2F2;
    private const GRAY = 0x8A8A8A;
    private const DIM = 0x5A5A5A;
    private const TRACK = 0x262626;
    private const CYAN = 0x3EC6E0;
    // The daily look's pairs, [Body Battery, stress], the next each day
    private const DAYS = [
        [0x38A8FF, 0xFFB020], [0x8CE03C, 0xE8D44A], [0x2EE6B0, 0xFF5C9E], [0xA77BFF, 0xFF7A3D],
        [Lib.Look.VOLT, Lib.Look.BLAZE]
    ] as Array<[Number, Number]>;
    private const DAY_NAMES = ["ALPINE", "MEADOW", "REEF", "DUSK", "VOLT"] as Array<String>;

    // The colours as set and as the look has them
    private var _look as Number = Lib.Look.YOURS;
    private var _body as Number = 0x46D18A;      // the Body Battery gauge and its number
    private var _stress as Number = 0xFF7A3D;    // the stress gauge and its number
    private var _white as Number = WHITE;        // the time and the tiles' numbers
    private var _gray as Number = GRAY;          // the date
    private var _dim as Number = DIM;            // the labels
    private var _status as Number = CYAN;        // the training status
    private var _timeBox as Array<Number> = [] as Array<Number>;   // [x, y, half width, half height], awake

    // The gauges: 130 degrees up each side, clockwise from 12 o'clock
    private const BODY_START = 205;
    private const STRESS_START = 25;
    private const GAUGE_SPAN = 130;

    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;
    private var _readings as Readings?;
    private var _readAt as Number = -1;      // minute of the day the readings were taken
    private const SLEEP_REFRESH = 5;         // minutes between reads while always-on
    private var _labelFont as FontType = Graphics.FONT_XTINY;
    private var _valueFont as FontType = Graphics.FONT_SMALL;
    private var _footerFont as FontType = Graphics.FONT_XTINY;

    // Press targets, [complication type, x, y, half width, half height]
    private var _targets as Array<Array<Number>> = [] as Array<Array<Number>>;

    // How quickly the face lights, for the watch's log
    private var _log as Lib.Timing.Log;

    function initialize() {
        WatchFace.initialize();
        _log = new Lib.Timing.Log("Readiness");
        _burnIn = Lib.Aod.required();
        reloadSettings();
    }

    // The gauges' colours from the phone app, the watch's menu or the watch
    // face editor, whichever was changed last (Choices.editor), then the look
    function reloadSettings() as Void {
        var editor = Choices.editor();
        var body = Choices.number(editor, "Accent", 0);
        var stress = Choices.number(editor, "DataColor", 0);
        _body = Choices.ACCENT[(body >= 0 && body < Choices.ACCENT.size()) ? body : 0];
        _stress = Choices.DATA_COLOR[(stress >= 0 && stress < Choices.DATA_COLOR.size()) ? stress : 0];
        _white = WHITE;
        _gray = GRAY;
        _dim = DIM;
        _status = CYAN;
        _look = Lib.Look.mode();
        if (Lib.Look.bright(_look)) {
            _body = Lib.Look.blaze(_look);
            _stress = Lib.Look.WHITE;
            _white = Lib.Look.WHITE;
            _gray = Lib.Look.WHITE;
            _dim = GRAY;
            _status = Lib.Look.blaze(_look);
        } else if (_look == Lib.Look.LOW) {
            _body = Lib.Look.GLOW;
            _stress = 0xC8703E;
            _white = Lib.Look.CREAM;
            _gray = Lib.Look.CREAM;
            _dim = 0x8A7A62;
            _status = 0xE0B050;
        } else if (_look == Lib.Look.DAILY) {
            var p = DAYS[Lib.Look.day(DAYS.size())];
            _body = p[0];
            _stress = p[1];
        }
    }

    // The gauges' colours as drawn, [Body Battery, stress] (the tests)
    function colors() as [Number, Number] {
        return [_body, _stress];
    }

    // Whether (x, y) is on the time, where a hold steps to the next look
    function timeAt(x as Number, y as Number) as Boolean {
        var b = _timeBox;
        return b.size() == 4 && (x - b[0]).abs() <= b[2] && (y - b[1]).abs() <= b[3];
    }

    function onLayout(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        _labelFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (w * 0.040).toNumber(), Graphics.FONT_XTINY);
        _valueFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.078).toNumber(), Graphics.FONT_SMALL);
        _footerFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.044).toNumber(), Graphics.FONT_XTINY);
    }

    // The metrics are re-read once a minute while awake, and every five
    // minutes always-on, where each update has a power budget
    function refresh() as Void {
        var now = minuteOfDay();
        var age = now - _readAt;
        if (age < 0) {
            age += 1440;
        }
        if (_readings == null || (_awake && age >= 1) || age >= SLEEP_REFRESH) {
            _readAt = now;
            _readings = Metrics.read();
        }
    }

    // For the tests: show these readings until the next read is due
    function setReadings(readings as Readings) as Void {
        _readings = readings;
        _readAt = minuteOfDay();
    }

    private function minuteOfDay() as Number {
        var clock = System.getClockTime();
        return clock.hour * 60 + clock.min;
    }

    function onUpdate(dc as Dc) as Void {
        var started = System.getTimer();
        refresh();
        _log.part = System.getTimer() - started;   // the readings: the face's costly part
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (!_awake && _burnIn) {
            drawAlwaysOn(dc, _readings as Readings);
        } else {
            drawActive(dc, _readings as Readings);
            _log.frame(started, true);
        }
    }

    function onEnterSleep() as Void {
        _awake = false;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _awake = true;
        _log.wake();
        WatchUi.requestUpdate();
    }

    // The native widget to open for a press at (x, y), or null
    function metricAt(x as Number, y as Number) as Complications.Type? {
        for (var i = 0; i < _targets.size(); i++) {
            var t = _targets[i];
            if ((x - t[1]).abs() <= t[3] && (y - t[2]).abs() <= t[4]) {
                return t[0] as Complications.Type;
            }
        }
        return null;
    }

    private function drawActive(dc as Dc, r as Readings) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var targets = [] as Array<Array<Number>>;

        // Gauges: Body Battery fills upward on the left, stress upward on the right
        var gaugeR = w * 0.454;
        var gaugeW = (w * 0.031).toNumber();
        var body = r.bodyBattery;
        Lib.Arcs.drawGauge(dc, cx, cy, gaugeR, BODY_START, GAUGE_SPAN, (body != null) ? body / 100.0 : 0.0, gaugeW, TRACK, _body);
        dc.setColor(TRACK, Graphics.COLOR_TRANSPARENT);
        Lib.Arcs.drawClockwise(dc, cx, cy, gaugeR, STRESS_START, GAUGE_SPAN, gaugeW);
        var stress = r.stress;
        if (stress != null && stress > 0) {
            var sweep = GAUGE_SPAN * (stress > 100 ? 1.0 : stress / 100.0);
            dc.setColor(_stress, Graphics.COLOR_TRANSPARENT);
            Lib.Arcs.drawClockwise(dc, cx, cy, gaugeR, STRESS_START + GAUGE_SPAN - sweep, sweep, gaugeW);
        }

        // The gauge numbers beside them
        var sideX = (w * 0.379).toNumber();
        var valueY = cy - (h * 0.035).toNumber();
        var labelY = cy + (h * 0.031).toNumber();
        drawSideValue(dc, cx - sideX, valueY, labelY, ReadinessText.score(body), "BODY", _body, center);
        drawSideValue(dc, cx + sideX, valueY, labelY, ReadinessText.score(stress), "STRESS", _stress, center);
        targets.add([Complications.COMPLICATION_TYPE_BODY_BATTERY, cx - sideX, cy, (w * 0.1).toNumber(), (h * 0.12).toNumber()]);
        targets.add([Complications.COMPLICATION_TYPE_STRESS, cx + sideX, cy, (w * 0.1).toNumber(), (h * 0.12).toNumber()]);

        // Date and time
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var date = dateText(Lang.format("$1$ $2$ $3$", [info.day_of_week, info.day, info.month]).toUpper());
        dc.setColor(_gray, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.255).toNumber(), Graphics.FONT_TINY, Lib.Look.shown() ? Lib.Look.title(_look, DAY_NAMES) : date, center);
        dc.setColor(_white, Graphics.COLOR_TRANSPARENT);
        var timeY = (h * 0.44).toNumber();
        dc.drawText(cx, timeY, Graphics.FONT_NUMBER_MEDIUM, timeString(), center);
        _timeBox = [cx, timeY, (w * 0.26).toNumber(), (h * 0.085).toNumber()];

        // Tiles: value over label
        var tiles = [
            [Metrics.sleepType(), ReadinessText.score(r.sleepScore), "SLEEP"],
            [Complications.COMPLICATION_TYPE_RECOVERY_TIME, ReadinessText.recovery(r.recoveryMinutes), "RECOVERY"],
            [Complications.COMPLICATION_TYPE_HEART_RATE, ReadinessText.score(r.restingHr), "RHR"]
        ];
        var xs = [w * 0.302, w * 0.5, w * 0.698];
        var tileValueY = (h * 0.643).toNumber();
        var tileLabelY = (h * 0.709).toNumber();
        for (var i = 0; i < 3; i++) {
            var x = xs[i].toNumber();
            dc.setColor(_white, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, tileValueY, _valueFont, tiles[i][1] as String, center);
            dc.setColor(_dim, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, tileLabelY, _labelFont, tiles[i][2] as String, center);
            if (tiles[i][0] != null) {   // no sleep score complication on the API 5 watches
                targets.add([tiles[i][0] as Number, x, (tileValueY + tileLabelY) / 2, (w * 0.1).toNumber(), (h * 0.07).toNumber()]);
            }
        }

        // Footer: the training status
        var footer = ReadinessText.training(r.trainingStatus);
        if (footer.length() > 0) {
            dc.setColor(_status, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.833).toNumber(), _footerFont, footer, center);
            targets.add([Complications.COMPLICATION_TYPE_TRAINING_STATUS, cx, (h * 0.833).toNumber(), (w * 0.25).toNumber(), (h * 0.04).toNumber()]);
        }
        _targets = targets;
    }

    private function drawSideValue(dc as Dc, x as Number, valueY as Number, labelY as Number,
                                   value as String, label as String, color as ColorType, justification as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, valueY, _valueFont, value, justification);
        dc.setColor(_dim, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, labelY, _labelFont, label, justification);
    }

    // Always-on: hollow time and one
    // dim summary line, walked round a 5x5 grid of offsets each minute
    private function drawAlwaysOn(dc as Dc, r as Readings) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var off = Lib.Aod.offset(System.getClockTime().min, (w * 0.013).toNumber());
        var cx = w / 2 + off[0];

        Lib.Aod.drawHollowText(dc, cx, (h * 0.485).toNumber() + off[1], Graphics.FONT_NUMBER_MEDIUM, timeString(), GRAY, center);
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.64).toNumber() + off[1], Graphics.FONT_XTINY, ReadinessText.summary(r), center);
        _targets = [] as Array<Array<Number>>;
        _timeBox = [] as Array<Number>;
    }

    private function timeString() as String {
        return Lib.Fmt.clock(clockSeconds());
    }

    // The clock and the date, or in a sample build (sample.jungle) 14:38 on Friday 31 October
    (:live)
    private function clockSeconds() as Number {
        var clock = System.getClockTime();
        return clock.hour * 3600 + clock.min * 60;
    }

    (:sample)
    private function clockSeconds() as Number {
        return 14 * 3600 + 38 * 60;
    }

    (:live)
    private function dateText(live as String) as String {
        return live;
    }

    (:sample)
    private function dateText(live as String) as String {
        return "FRI 31 OCT";
    }
}
