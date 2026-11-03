import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

// The glance row: TALLY, the newest entry and its time, and how many days
// running it has been logged (or when it was).
(:glance)
class TallyGlance extends WatchUi.GlanceView {

    private const CORAL = 0xFF6B5A;
    private const WHITE = 0xF2ECE2;
    private const GRAY = 0x8A8A8A;

    private var _bigFont as FontType = Graphics.FONT_MEDIUM;

    function initialize() {
        GlanceView.initialize();
    }

    function onLayout(dc as Dc) as Void {
        _bigFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (dc.getHeight() * 0.34).toNumber(), Graphics.FONT_MEDIUM);
    }

    function onUpdate(dc as Dc) as Void {
        var h = dc.getHeight();
        var left = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(CORAL, Graphics.COLOR_TRANSPARENT);
        dc.drawText((dc.getWidth() * 0.10).toNumber(), (h * 0.17).toNumber(), Graphics.FONT_GLANCE, "TALLY", left);

        var last = Storage.getValue(TallyLog.LAST);
        if (!(last instanceof Array) || last.size() < 4) {
            dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(0, (h * 0.5).toNumber(), _bigFont, "Nothing yet", left);
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(0, (h * 0.85).toNumber(), Graphics.FONT_GLANCE, "open to log", left);
            return;
        }
        var t = last[0] as Number;
        dc.setColor(last[2] as Number, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.5).toNumber(), _bigFont, (last[1] as String) + " " + Lib.Fmt.clockAt(t), left);
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, (h * 0.85).toNumber(), Graphics.FONT_GLANCE, when(dc, t, last[3] as Number), left);
    }

    // "2h 10m ago · 4 days running" (or without the run when it won't
    // fit), "yesterday" or "Tue 3 Nov"
    private function when(dc as Dc, t as Number, run as Number) as String {
        var now = Time.now().value();
        var ago = day(now) - day(t);
        var running = (run >= 2 && ago <= 1) ? run + " days running" : null;
        if (now - t < 86400) {
            var since = (now - t < 60) ? "just now" : Lib.Fmt.countdown(now - t) + " ago";
            if (running == null) {
                return since;
            }
            var both = since + " · " + running;
            return (dc.getTextWidthInPixels(both, Graphics.FONT_GLANCE) <= dc.getWidth()) ? both : since;
        }
        if (running != null) {
            return running;
        }
        if (ago == 1) {
            return "yesterday";
        }
        return Lib.Fmt.shortDate(new Time.Moment(t));
    }

    private function day(unix as Number) as Number {
        return (unix - Lib.Fmt.localSeconds(unix) + 43200) / 86400;
    }
}
