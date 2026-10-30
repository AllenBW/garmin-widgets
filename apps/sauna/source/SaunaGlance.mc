import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// The glance row: SAUNA · STEAM, the last visit, and this week against
// that kind's plan. Nothing is read from the sensors here.
(:glance)
class SaunaGlance extends WatchUi.GlanceView {

    private const EMBER = 0xFF7A3D;
    private const WHITE = 0xF2F2F2;
    private const GRAY = 0x8A8A8A;

    private var _bigFont as FontType = Graphics.FONT_MEDIUM;

    function initialize() {
        GlanceView.initialize();
    }

    function onLayout(dc as Dc) as Void {
        _bigFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (dc.getHeight() * 0.34).toNumber(), Graphics.FONT_MEDIUM);
    }

    function onUpdate(dc as Dc) as Void {
        SaunaSettings.applyUnit();
        var row = SaunaHistory.last();
        var kind = row == null ? KIND_SAUNA : row[SaunaHistory.KIND];
        var h = dc.getHeight();
        var left = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(EMBER, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.15).toNumber(), Graphics.FONT_GLANCE, "SAUNA · STEAM", left);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.5).toNumber(), _bigFont, SaunaText.headline(row), left);
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.85).toNumber(), Graphics.FONT_GLANCE, SaunaText.week(SaunaSettings.plan(kind)), left);
    }
}
