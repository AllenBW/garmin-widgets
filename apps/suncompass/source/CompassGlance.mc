import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

// The glance row: COMPASS, where the sun is, and the next sunrise or sunset
// with its bearing. No compass heading here: the sensor stays off until
// the app opens.
(:glance)
class CompassGlance extends WatchUi.GlanceView {

    private const AMBER = 0xFFB020;
    private const WHITE = 0xF2F2F2;
    private const GRAY = 0x8A8A8A;

    private var _sky as SunSky?;
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

    // The sun moves a quarter of a degree a minute: recompute once a minute
    function refresh() as Void {
        var now = Time.now().value();
        if (_sky == null || now - _now >= 60) {
            _now = now;
            _sky = CompassModel.status(now);
        }
    }

    function onUpdate(dc as Dc) as Void {
        refresh();
        var s = _sky as SunSky;
        var h = dc.getHeight();
        var left = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(AMBER, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.15).toNumber(), Graphics.FONT_GLANCE, "COMPASS", left);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.5).toNumber(), _bigFont, CompassText.headline(s), left);
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.85).toNumber(), Graphics.FONT_GLANCE, CompassText.detail(s), left);
    }
}
