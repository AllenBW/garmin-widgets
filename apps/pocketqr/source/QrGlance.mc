import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// The glance row: POCKET QR, the first code's name, then how many codes
// there are and what kinds. Laid out from the glance area the system hands
// us (349x130 on the 454 px watches).
(:glance)
class QrGlance extends WatchUi.GlanceView {

    private const AMBER = 0xFFB020;
    private const WHITE = 0xF2F2F2;
    private const GRAY = 0x8A8A8A;

    private var _codes as Array<QrCode> = [] as Array<QrCode>;
    private var _bigFont as FontType = Graphics.FONT_MEDIUM;

    function initialize() {
        GlanceView.initialize();
    }

    function onLayout(dc as Dc) as Void {
        _bigFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (dc.getHeight() * 0.34).toNumber(), Graphics.FONT_MEDIUM);
    }

    function onShow() as Void {
        _codes = QrCodes.load();
    }

    function onUpdate(dc as Dc) as Void {
        var h = dc.getHeight();
        var left = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(AMBER, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.15).toNumber(), Graphics.FONT_GLANCE, "POCKET QR", left);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.5).toNumber(), _bigFont, _codes.size() == 0 ? "No codes yet" : _codes[0].name, left);
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.85).toNumber(), Graphics.FONT_GLANCE, QrCodes.summary(_codes), left);
    }
}
