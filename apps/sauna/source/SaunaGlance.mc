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

    // What the row shows, read from Storage and Properties once a showing
    // and again when the settings change,
    // not on every update; null until read
    private var _headline as String? = null;
    private var _week as String = "";
    var reads as Number = 0;            // how often it read them (the tests)

    function initialize() {
        GlanceView.initialize();
    }

    function onShow() as Void {
        reload();
    }

    // Read again on the next update: a showing, a settings change
    function reload() as Void {
        _headline = null;
    }

    private function read() as Void {
        SaunaSettings.applyUnit();
        var row = SaunaHistory.last();
        var kind = row == null ? KIND_SAUNA : row[SaunaHistory.KIND];
        _headline = SaunaText.headline(row);
        _week = SaunaText.weekShort(SaunaSettings.plan(kind));
        reads++;
    }

    function onLayout(dc as Dc) as Void {
        _bigFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (dc.getHeight() * 0.34).toNumber(), Graphics.FONT_MEDIUM);
    }

    function onUpdate(dc as Dc) as Void {
        if (_headline == null) {
            read();
        }
        var w = dc.getWidth();
        var h = dc.getHeight();
        var left = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        // the top line sits where the round screen is narrowest: start it a little in
        dc.setColor(EMBER, Graphics.COLOR_TRANSPARENT);
        // the small lines drop to the smaller system font where the row is narrow (274 px on the Venu 4 41 mm)
        var small = [Graphics.FONT_GLANCE, Graphics.FONT_XTINY] as Array<FontType>;
        var inset = (w * 0.06).toNumber();
        dc.drawText(inset, (h * 0.17).toNumber(), Lib.Fmt.fitFont(dc, "SAUNA · STEAM", small, w - inset), "SAUNA · STEAM", left);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.5).toNumber(), _bigFont, _headline as String, left);
        // one line only: given the row's height the fit would wrap into the headline
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        var text = _week;
        var font = Lib.Fmt.fitFont(dc, text, small, w);
        var week = Graphics.fitTextToArea(text, font, w, Graphics.getFontHeight(font), true);
        dc.drawText(0, (h * 0.85).toNumber(), font, week == null ? "" : week, left);
    }
}
