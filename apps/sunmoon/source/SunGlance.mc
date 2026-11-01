import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

// The glance row: SUN, the next sunrise or sunset, and the golden hour
// countdown. Laid out from the glance area the system hands us.
(:glance)
class SunGlance extends WatchUi.GlanceView {

    private const AMBER = 0xFFB020;
    private const WHITE = 0xF2F2F2;
    private const GRAY = 0x8A8A8A;

    private var _status as SunStatus?;
    private var _now as Number = 0;
    private var _bigFont as FontType = Graphics.FONT_MEDIUM;

    function initialize() {
        GlanceView.initialize();
    }

    function onLayout(dc as Dc) as Void {
        _bigFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (dc.getHeight() * 0.34).toNumber(), Graphics.FONT_MEDIUM);
    }

    function onShow() as Void {
        refresh();
    }

    // The sun maths is cheap but not free: recompute once a minute
    function refresh() as Void {
        var now = Time.now().value();
        if (_status == null || now - _now >= 60) {
            _now = now;
            _status = SunModel.status(now);
        }
    }

    function onUpdate(dc as Dc) as Void {
        refresh();
        var s = _status as SunStatus;
        var h = dc.getHeight();
        var left = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(AMBER, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.15).toNumber(), Graphics.FONT_GLANCE, "SUN", left);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.5).toNumber(), _bigFont, SunText.headline(s), left);
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        var line = SunText.goldenLine(s, _now);
        var font = Lib.Fmt.fitFont(dc, line, [Graphics.FONT_GLANCE, Graphics.FONT_XTINY] as Array<FontType>, dc.getWidth());
        dc.drawText(0, (h * 0.85).toNumber(), font, line, left);
    }
}
