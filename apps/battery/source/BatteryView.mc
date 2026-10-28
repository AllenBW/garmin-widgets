import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

// The full app (designs/svg/app-battery.svg): the projection in large type,
// the charge-by date, a bar per day for the last week with heavy days in
// orange, and the pace underneath. Positions are fractions of the screen.
class BatteryView extends WatchUi.View {

    private const CYAN = 0x3EC6E0;
    private const ORANGE = 0xFF7A3D;
    private const WHITE = 0xF2F2F2;
    private const GRAY = 0x8A8A8A;
    private const DIM = 0x5A5A5A;
    private const TRACK = 0x262626;

    private var _summary as BatterySummary?;
    private var _heavy as Number? = null;
    private var _heavyHours as Float = 0.0;
    private var _bigFont as FontType = Graphics.FONT_LARGE;
    private var _textFont as FontType = Graphics.FONT_XTINY;
    private var _labelFont as FontType = Graphics.FONT_XTINY;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        var h = dc.getHeight();
        _bigFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.17).toNumber(), Graphics.FONT_LARGE);
        _textFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.048).toNumber(), Graphics.FONT_XTINY);
        _labelFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.04).toNumber(), Graphics.FONT_XTINY);
    }

    function onShow() as Void {
        refresh();
    }

    function refresh() as Void {
        var s = BatteryModel.summarize(BatteryLog.samples(), Time.now().value(), BatteryLog.currentLevel());
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

        dc.setColor(CYAN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.167).toNumber(), _textFont, "BATTERY PLANNER", center);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.31).toNumber(), _bigFont, BatteryText.headline(s), center);
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.43).toNumber(), _textFont, BatteryText.chargeLine(s), center);

        drawBars(dc, s, w, h);

        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.824).toNumber(), _textFont, BatteryText.paceLine(s, _heavy, _heavyHours), center);
    }

    // One bar per day, oldest on the left; 4 px per percent at 454, capped
    private function drawBars(dc as Dc, s as BatterySummary, w as Number, h as Number) as Void {
        var days = BatteryModel.DAYS;
        var step = (w * 0.075).toNumber();
        var barW = (w * 0.048).toNumber();
        var x0 = w / 2 - (step * (days - 1)) / 2 - barW / 2;
        var base = (h * 0.727).toNumber();
        var maxH = (h * 0.25).toNumber();
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
            dc.drawText(x + barW / 2, base + (h * 0.04).toNumber(), _labelFont, s.labels[i], center);
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
