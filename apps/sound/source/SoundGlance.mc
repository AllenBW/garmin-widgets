import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

// The glance row: SOUND LEVEL, the last reading with its band, and how
// long ago that was. The microphone is never touched here.
(:glance)
class SoundGlance extends WatchUi.GlanceView {

    private const ACCENT = 0x5AC8FA;
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
        var w = dc.getWidth();
        var h = dc.getHeight();
        var left = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        var last = SoundStore.last();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        // the top line sits where the round screen is narrowest: start it a little in
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawText((w * 0.06).toNumber(), (h * 0.17).toNumber(), Graphics.FONT_GLANCE, "SOUND LEVEL", left);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        var headline = last == null ? "Open to measure" : (last[SoundStore.DB] as Number) + " dB · " + (last[SoundStore.NAME] as String);
        var fitted = Graphics.fitTextToArea(headline, _bigFont, w, Graphics.getFontHeight(_bigFont), true);
        dc.drawText(0, (h * 0.5).toNumber(), _bigFont, fitted == null ? headline : fitted, left);
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        var detail = last == null ? "the watch microphone, while open" : SoundStore.ago(last[SoundStore.AT] as Number);
        var line = Graphics.fitTextToArea(detail, Graphics.FONT_GLANCE, w, Graphics.getFontHeight(Graphics.FONT_GLANCE), true);
        dc.drawText(0, (h * 0.85).toNumber(), Graphics.FONT_GLANCE, line == null ? "" : line, left);
    }
}
