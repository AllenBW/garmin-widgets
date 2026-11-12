import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// The full app: the level, the projection in large type, the charge-by
// date, a bar per day for the last week with the heavy day in orange, and
// the pace underneath. On the charger: the time until it is full and when
// that is, the battery as a bar, the charger's speed and what the charge so
// far is good for. Positions are fractions of the screen.
class BatteryView extends WatchUi.View {

    private const CYAN = 0x3EC6E0;
    private const GREEN = 0x5BD96A;
    private const ORANGE = 0xFF7A3D;
    private const WHITE = 0xF2F2F2;
    private const GRAY = 0xA8A8A8;
    private const DIM = 0x7A7A7A;
    private const TRACK = 0x262626;

    private const TICK_MS = 10000;   // how often the charger is looked at while the app is open

    private var _summary as BatterySummary?;
    private var _heavy as Number? = null;
    private var _heavyHours as Float = 0.0;
    private var _bigFont as FontType = Graphics.FONT_LARGE;
    private var _textFont as FontType = Graphics.FONT_SMALL;
    private var _noteFont as FontType = Graphics.FONT_TINY;
    private var _labelFont as FontType = Graphics.FONT_XTINY;
    private var _timer as Timer.Timer?;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        var h = dc.getHeight();
        _bigFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.19).toNumber(), Graphics.FONT_LARGE);
        _textFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.075).toNumber(), Graphics.FONT_SMALL);
        _noteFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.062).toNumber(), Graphics.FONT_TINY);
        _labelFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.055).toNumber(), Graphics.FONT_XTINY);
    }

    function onShow() as Void {
        refresh();
        var timer = new Timer.Timer();
        timer.start(method(:onTick), TICK_MS, true);
        _timer = timer;
    }

    function onHide() as Void {
        var timer = _timer;
        if (timer != null) {
            timer.stop();
        }
        _timer = null;
    }

    // On the charger the screen counts down, and the charge is timed more
    // finely than the background can; plugging in or out changes the screen
    function onTick() as Void {
        var s = _summary;
        if (BatteryCharge.reading()[1] || (s != null && s.charging)) {
            refresh();
            WatchUi.requestUpdate();
        }
    }

    function refresh() as Void {
        BatteryCharge.check();
        show(BatteryModel.current());
    }

    // Draw this summary (the tests' way to every state)
    function show(s as BatterySummary) as Void {
        _summary = s;
        _heavy = BatteryModel.heavyDay(s);
        var heavy = _heavy;
        _heavyHours = (heavy != null) ? BatteryActivity.hoursOn(s.dayStarts[heavy]) : 0.0;
    }

    function onUpdate(dc as Dc) as Void {
        var s = _summary;
        if (s == null) {
            refresh();
            s = _summary as BatterySummary;
        }
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(s.charging ? GREEN : CYAN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.135).toNumber(), _textFont, BatteryText.title(s, s.level.toString() + "%"), center);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.275).toNumber(), _bigFont, BatteryText.headline(s), center);
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.405).toNumber(), _textFont, BatteryText.chargeLine(s), center);

        if (s.charging) {
            drawCharge(dc, s, w, h);
            dc.setColor(GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.745).toNumber(), _textFont, BatteryText.speedLine(s), center);
            if (!s.full) {
                dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, (h * 0.845).toNumber(), _noteFont, BatteryText.lastsLine(s) + " now", center);
            }
            return;
        }

        drawBars(dc, s, w, h);

        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.815).toNumber(), _textFont, BatteryText.paceLine(s), center);
        dc.setColor(ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.895).toNumber(), _noteFont, BatteryText.heavyLine(s, _heavy, _heavyHours), center);
    }

    // The battery as a bar, filled to the level
    private function drawCharge(dc as Dc, s as BatterySummary, w as Number, h as Number) as Void {
        var barW = (w * 0.62).toNumber();
        var barH = (h * 0.11).toNumber();
        var x = (w - barW) / 2;
        var y = (h * 0.52).toNumber();
        var r = barH / 4;
        dc.setColor(TRACK, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, barW, barH, r);
        var fill = barW * s.level / 100;
        if (fill < 2 * r) {
            fill = 2 * r;
        }
        dc.setColor(GREEN, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, fill, barH, r);
    }

    // One bar per day, oldest on the left; 4 px per percent at 454, capped
    private function drawBars(dc as Dc, s as BatterySummary, w as Number, h as Number) as Void {
        var days = BatteryModel.DAYS;
        var step = (w * 0.085).toNumber();
        var barW = (w * 0.056).toNumber();
        var x0 = w / 2 - (step * (days - 1)) / 2 - barW / 2;
        var base = (h * 0.675).toNumber();
        var maxH = (h * 0.19).toNumber();
        var perPercent = h * 0.0088;
        var heavy = _heavy;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        for (var i = 0; i < days; i++) {
            var x = x0 + i * step;
            var drain = s.drains[i];
            if (drain == null) {
                dc.setColor(TRACK, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x, base - 3, barW, 3);
            } else {
                var barH = (drain * perPercent).toNumber();
                if (barH > maxH) {
                    barH = maxH;
                }
                if (barH < 3) {
                    barH = 3;
                }
                dc.setColor((heavy != null && heavy == i) ? ORANGE : CYAN, Graphics.COLOR_TRANSPARENT);
                dc.fillRoundedRectangle(x, base - barH, barW, barH, 3);
            }
            dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + barW / 2, base + (h * 0.05).toNumber(), _labelFont, s.labels[i], center);
        }
    }
}

// Select (or tap) logs a sample right away: handy on the first day, and for
// checking the service on a watch.
class BatteryDelegate extends WatchUi.BehaviorDelegate {

    private var _view as BatteryView;

    function initialize(view as BatteryView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() as Boolean {
        BatteryLog.recordNow();
        _view.refresh();
        WatchUi.requestUpdate();
        return true;
    }
}
