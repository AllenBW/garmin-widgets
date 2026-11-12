import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

// The glance row: BATTERY, the time left, the charge-by date, and a
// sparkline of the level over the week on the right. On the charger:
// CHARGING and the level, the time until it is full, and when that is. Laid out from the
// glance area the system hands us (349x130 on the 454 px watches).
(:glance)
class BatteryGlance extends WatchUi.GlanceView {

    private const CYAN = 0x3EC6E0;
    private const GREEN = 0x5BD96A;
    private const WHITE = 0xF2F2F2;
    private const GRAY = 0x8A8A8A;

    private var _summary as BatterySummary?;
    private var _bigFonts as Array<FontType> = [Graphics.FONT_MEDIUM] as Array<FontType>;

    function initialize() {
        GlanceView.initialize();
    }

    function onLayout(dc as Dc) as Void {
        // As large as the headline fits beside the sparkline
        var h = dc.getHeight();
        _bigFonts = [
            Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.42).toNumber(), Graphics.FONT_MEDIUM),
            Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.38).toNumber(), Graphics.FONT_MEDIUM),
            Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.34).toNumber(), Graphics.FONT_MEDIUM)
        ] as Array<FontType>;
    }

    function onShow() as Void {
        refresh();
    }

    function refresh() as Void {
        BatteryCharge.check();
        _summary = BatteryModel.current();
    }

    // Draw this summary (the tests' way to every state)
    function show(s as BatterySummary) as Void {
        _summary = s;
    }

    function onUpdate(dc as Dc) as Void {
        var s = _summary;
        if (s == null) {
            refresh();
            s = _summary as BatterySummary;
        }
        var w = dc.getWidth();
        var h = dc.getHeight();
        var left = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        var sparkX = (w * 0.74).toNumber();
        var headline = BatteryText.headline(s);
        dc.setColor(s.charging ? GREEN : CYAN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.15).toNumber(), Graphics.FONT_GLANCE, BatteryText.title(s, "BATTERY"), left);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.5).toNumber(), Lib.Fmt.fitFont(dc, headline, _bigFonts, sparkX - (w * 0.03).toNumber()), headline, left);
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.85).toNumber(), Graphics.FONT_GLANCE, BatteryText.chargeLine(s), left);

        drawSparkline(dc, s.levels, sparkX, (h * 0.28).toNumber(), w - sparkX - 2, (h * 0.44).toNumber());
    }

    // Battery level over the log, 0 % at the bottom of the box, 100 % at the top
    private function drawSparkline(dc as Dc, levels as Array<Number>, x as Number, y as Number, w as Number, h as Number) as Void {
        var n = levels.size();
        if (n < 2) {
            return;
        }
        dc.setPenWidth(2);
        dc.setColor(CYAN, Graphics.COLOR_TRANSPARENT);
        var px = x;
        var py = y + h - levels[0] * h / 100;
        for (var i = 1; i < n; i++) {
            var nx = x + i * w / (n - 1);
            var ny = y + h - levels[i] * h / 100;
            dc.drawLine(px, py, nx, ny);
            px = nx;
            py = ny;
        }
    }
}
