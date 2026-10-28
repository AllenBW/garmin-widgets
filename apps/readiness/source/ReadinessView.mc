import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

// The face (designs/svg/face-readiness-active.svg): a Body Battery gauge
// up the left side and a stress gauge up the right, date and time in the
// middle, three tiles (sleep score, recovery, resting HR) and the training
// status along the bottom. Always-on keeps the hollow time and one summary
// line, shifted each minute.
class ReadinessView extends WatchUi.WatchFace {

    // Palette (designs/mockups.py)
    private const WHITE = 0xF2F2F2;
    private const GRAY = 0x8A8A8A;
    private const DIM = 0x5A5A5A;
    private const TRACK = 0x262626;
    private const GREEN = 0x46D18A;
    private const ORANGE = 0xFF7A3D;
    private const CYAN = 0x3EC6E0;

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

    function initialize() {
        WatchFace.initialize();
        _burnIn = Lib.Aod.required();
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
        refresh();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (!_awake && _burnIn) {
            drawAlwaysOn(dc, _readings as Readings);
        } else {
            drawActive(dc, _readings as Readings);
        }
    }

    function onEnterSleep() as Void {
        _awake = false;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _awake = true;
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
        Lib.Arcs.drawGauge(dc, cx, cy, gaugeR, BODY_START, GAUGE_SPAN, (body != null) ? body / 100.0 : 0.0, gaugeW, TRACK, GREEN);
        dc.setColor(TRACK, Graphics.COLOR_TRANSPARENT);
        Lib.Arcs.drawClockwise(dc, cx, cy, gaugeR, STRESS_START, GAUGE_SPAN, gaugeW);
        var stress = r.stress;
        if (stress != null && stress > 0) {
            var sweep = GAUGE_SPAN * (stress > 100 ? 1.0 : stress / 100.0);
            dc.setColor(ORANGE, Graphics.COLOR_TRANSPARENT);
            Lib.Arcs.drawClockwise(dc, cx, cy, gaugeR, STRESS_START + GAUGE_SPAN - sweep, sweep, gaugeW);
        }

        // The gauge numbers beside them
        var sideX = (w * 0.379).toNumber();
        var valueY = cy - (h * 0.035).toNumber();
        var labelY = cy + (h * 0.031).toNumber();
        drawSideValue(dc, cx - sideX, valueY, labelY, ReadinessText.score(body), "BODY", GREEN, center);
        drawSideValue(dc, cx + sideX, valueY, labelY, ReadinessText.score(stress), "STRESS", ORANGE, center);
        targets.add([Complications.COMPLICATION_TYPE_BODY_BATTERY, cx - sideX, cy, (w * 0.1).toNumber(), (h * 0.12).toNumber()]);
        targets.add([Complications.COMPLICATION_TYPE_STRESS, cx + sideX, cy, (w * 0.1).toNumber(), (h * 0.12).toNumber()]);

        // Date and time
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var date = Lang.format("$1$ $2$ $3$", [info.day_of_week, info.day, info.month]).toUpper();
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.255).toNumber(), Graphics.FONT_TINY, date, center);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.44).toNumber(), Graphics.FONT_NUMBER_MEDIUM, timeString(), center);

        // Tiles: value over label
        var tiles = [
            [Complications.COMPLICATION_TYPE_SLEEP_SCORE, ReadinessText.score(r.sleepScore), "SLEEP"],
            [Complications.COMPLICATION_TYPE_RECOVERY_TIME, ReadinessText.recovery(r.recoveryMinutes), "RECOVERY"],
            [Complications.COMPLICATION_TYPE_HEART_RATE, ReadinessText.score(r.restingHr), "RHR"]
        ];
        var xs = [w * 0.302, w * 0.5, w * 0.698];
        var tileValueY = (h * 0.643).toNumber();
        var tileLabelY = (h * 0.709).toNumber();
        for (var i = 0; i < 3; i++) {
            var x = xs[i].toNumber();
            dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, tileValueY, _valueFont, tiles[i][1] as String, center);
            dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, tileLabelY, _labelFont, tiles[i][2] as String, center);
            targets.add([tiles[i][0] as Number, x, (tileValueY + tileLabelY) / 2, (w * 0.1).toNumber(), (h * 0.07).toNumber()]);
        }

        // Footer: the training status
        var footer = ReadinessText.training(r.trainingStatus);
        if (footer.length() > 0) {
            dc.setColor(CYAN, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.833).toNumber(), _footerFont, footer, center);
            targets.add([Complications.COMPLICATION_TYPE_TRAINING_STATUS, cx, (h * 0.833).toNumber(), (w * 0.25).toNumber(), (h * 0.04).toNumber()]);
        }
        _targets = targets;
    }

    private function drawSideValue(dc as Dc, x as Number, valueY as Number, labelY as Number,
                                   value as String, label as String, color as ColorType, justification as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, valueY, _valueFont, value, justification);
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, labelY, _labelFont, label, justification);
    }

    // Always-on (designs/svg/face-readiness-aod.svg): hollow time and one
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
    }

    private function timeString() as String {
        var clock = System.getClockTime();
        return Lib.Fmt.clock(clock.hour * 3600 + clock.min * 60);
    }
}
