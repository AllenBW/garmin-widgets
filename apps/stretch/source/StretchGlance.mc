import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

// The glance row: the routine that suits now and why, then the streak
(:glance)
class StretchGlance extends WatchUi.GlanceView {

    private const ACCENT = 0xFF8A4C;
    private const WHITE = 0xF2F2F2;
    private const GRAY = 0x9E9E9E;

    private var _bigFont as FontType = Graphics.FONT_MEDIUM;
    private var _plan as Array<Number>? = null;   // read once a minute: it walks the activity history
    private var _planAt as Number = 0;

    function initialize() {
        GlanceView.initialize();
    }

    function onLayout(dc as Dc) as Void {
        _bigFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (dc.getHeight() * 0.34).toNumber(), Graphics.FONT_MEDIUM);
    }

    function onUpdate(dc as Dc) as Void {
        var now = Time.now().value();
        var s = _plan;
        if (s == null || now - _planAt >= 60 || now < _planAt) {
            s = StretchPlan.now();
            _plan = s;
            _planAt = now;
        }
        var h = dc.getHeight();
        var left = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        // the top line inside the row: its top on the row's top edge, all three rows from the same x
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, Graphics.getFontHeight(Graphics.FONT_GLANCE) / 2 + 1, Graphics.FONT_GLANCE, StretchPlan.why(s), left);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.5).toNumber(), _bigFont,
                    StretchRoutines.NAMES[s[0]] + " · " + StretchPlan.minutes(s[0]), left);
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.85).toNumber(), Graphics.FONT_GLANCE, StretchText.streakLine(now), left);
    }
}
