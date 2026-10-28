import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

// The glance row: BATTERY, the time left, the charge-by date, and a
// sparkline of the level over the week on the right. Laid out from the
// glance area the system hands us (349x130 on the 454 px watches).
(:glance)
class BatteryGlance extends WatchUi.GlanceView {

    private const CYAN = 0x3EC6E0;
    private const WHITE = 0xF2F2F2;
    private const GRAY = 0x8A8A8A;

    private var _summary as BatterySummary?;
    private var _bigFont as FontType = Graphics.FONT_MEDIUM;

    function initialize() {
        GlanceView.initialize();
    }

    function onLayout(dc as Dc) as Void {
        _bigFont = Graphics.FONT_MEDIUM;
        // Lib.Fmt.vectorFont is not available in glance scope (see BatteryText)
        if (Graphics has :getVectorFont) {
            try {
                var font = Graphics.getVectorFont({:face => "RobotoCondensedBold", :size => (dc.getHeight() * 0.34).toNumber()});
                if (font != null) {
                    _bigFont = font;
                }
            } catch (e) {
                // keep the system font
            }
        }
    }

    function onShow() as Void {
        refresh();
    }

    function refresh() as Void {
        _summary = BatteryModel.summarize(BatteryLog.samples(), Time.now().value(), BatteryLog.currentLevel());
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

        dc.setColor(CYAN, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.15).toNumber(), Graphics.FONT_GLANCE, "BATTERY", left);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.5).toNumber(), _bigFont, BatteryText.headline(s), left);
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.85).toNumber(), Graphics.FONT_GLANCE, BatteryText.chargeLine(s), left);

        drawSparkline(dc, s.levels, (w * 0.70).toNumber(), (h * 0.28).toNumber(), (w * 0.28).toNumber(), (h * 0.44).toNumber());
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
