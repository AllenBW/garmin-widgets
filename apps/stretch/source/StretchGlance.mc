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
        // the small lines drop to the smaller system font where the row is narrow (274 px on the Venu 4 41 mm)
        var w = dc.getWidth();
        var small = [Graphics.FONT_GLANCE, Graphics.FONT_XTINY] as Array<FontType>;
        // the top line inside the row: its top on the row's top edge, all three rows from the same x
        var why = StretchPlan.why(s);
        var font = Lib.Fmt.fitFont(dc, why, small, w);
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, Graphics.getFontHeight(font) / 2 + 1, font, why, left);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.5).toNumber(), _bigFont,
                    StretchRoutines.NAMES[s[0]] + " · " + StretchPlan.minutes(s[0]), left);
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        var streak = StretchText.streakLine(now);
        dc.drawText(0, (h * 0.85).toNumber(), Lib.Fmt.fitFont(dc, streak, small, w), streak, left);
    }
}
