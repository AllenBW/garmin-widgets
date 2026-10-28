import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.WatchUi;

// The full app (designs/svg/app-sun.svg): the sun on its arc between
// sunrise and sunset, then golden hour, blue hour and the moon.
class SunView extends WatchUi.View {

    private const AMBER = 0xFFB020;
    private const ORANGE = 0xFF7A3D;
    private const CYAN = 0x3EC6E0;
    private const WHITE = 0xF2F2F2;
    private const GRAY = 0x8A8A8A;
    private const DIM = 0x5A5A5A;

    private var _status as SunStatus?;
    private var _now as Number = 0;
    private var _textFont as FontType = Graphics.FONT_XTINY;
    private var _rowFont as FontType = Graphics.FONT_XTINY;
    private var _rowBoldFont as FontType = Graphics.FONT_XTINY;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        var h = dc.getHeight();
        _textFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.044).toNumber(), Graphics.FONT_XTINY);
        _rowFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.048).toNumber(), Graphics.FONT_XTINY);
        _rowBoldFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.048).toNumber(), Graphics.FONT_XTINY);
    }

    function onShow() as Void {
        _now = Time.now().value();
        _status = SunModel.status(_now);
    }

    function onUpdate(dc as Dc) as Void {
        if (_status == null) {
            onShow();
        }
        var s = _status as SunStatus;
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(AMBER, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.154).toNumber(), _textFont, "SUN & MOON", center);

        drawArc(dc, s, w, h);

        // Rows: golden hour, blue hour, moon
        var today = s.today;
        var rowY = (h * 0.696).toNumber();
        var rowStep = (h * 0.075).toNumber();
        var labelX = (w * 0.242).toNumber();
        var valueX = (w * 0.758).toNumber();
        var golden = s.goldenAt;
        var blue = s.blueAt;
        var rows = [
            [s.goldenNow ? "Golden hour ends" : "Golden hour", (golden != null) ? Lib.Fmt.clockAt(golden) : "--", ORANGE],
            [s.blueNow ? "Blue hour ends" : "Blue hour", (blue != null) ? Lib.Fmt.clockAt(blue) : "--", CYAN],
            ["Moon", moonText(), WHITE]
        ];
        if (today == null) {
            rows[0] = ["Location", "none yet", GRAY];
            rows[1] = ["Sync the phone", "or use GPS", GRAY];
        }
        for (var i = 0; i < rows.size(); i++) {
            var y = rowY + i * rowStep;
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(labelX, y, _rowFont, rows[i][0] as String, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(rows[i][2] as Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(valueX, y, _rowBoldFont, rows[i][1] as String, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        var moonR = (w * 0.024).toNumber();
        Lib.Moon.draw(dc, valueX + moonR + (w * 0.02).toNumber(), rowY + 2 * rowStep, moonR, Lib.Moon.phase(), WHITE, DIM);
    }

    // The horizon, a dotted half-ellipse from sunrise to sunset, the sun on
    // it (below the line when it is down), and the two times at the ends
    private function drawArc(dc as Dc, s as SunStatus, w as Number, h as Number) as Void {
        var cx = w / 2;
        var horizonY = (h * 0.55).toNumber();
        var rx = w * 0.346;
        var ry = h * 0.286;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setPenWidth(2);
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawLine((w * 0.088).toNumber(), horizonY, (w * 0.912).toNumber(), horizonY);

        dc.setColor(AMBER, Graphics.COLOR_TRANSPARENT);
        for (var deg = 0; deg <= 180; deg += 5) {
            var a = Math.toRadians(deg);
            dc.fillCircle(cx + (rx * Math.cos(a)).toNumber(), horizonY - (ry * Math.sin(a)).toNumber(), 2);
        }

        var today = s.today;
        var rise = (today != null) ? today.rise : null;
        var set = (today != null) ? today.set : null;
        var sunR = (w * 0.035).toNumber();
        if (rise != null && set != null && set > rise) {
            var t = (_now - rise).toFloat() / (set - rise);
            if (t >= 0.0 && t <= 1.0) {
                var a = Math.PI * (1.0 - t);
                dc.setColor(AMBER, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(cx + (rx * Math.cos(a)).toNumber(), horizonY - (ry * Math.sin(a)).toNumber(), sunR);
            } else {
                // Night: a dim sun under the horizon, on the side it went down or will come up
                var x = (t < 0.0) ? cx - rx.toNumber() : cx + rx.toNumber();
                dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, horizonY + (h * 0.05).toNumber(), sunR / 2);
            }
        }

        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        var timesY = horizonY + (h * 0.053).toNumber();
        dc.drawText(cx - rx.toNumber(), timesY, _textFont, (rise != null) ? Lib.Fmt.clockAt(rise) : "--", center);
        dc.drawText(cx + rx.toNumber(), timesY, _textFont, (set != null) ? Lib.Fmt.clockAt(set) : "--", center);
    }

    // "Waxing 78%", "Full", "New"
    private function moonText() as String {
        var phase = Lib.Moon.phase();
        var lit = (Lib.Moon.illumination(phase) * 100 + 0.5).toNumber();
        if (lit >= 99) {
            return "Full";
        }
        if (lit <= 1) {
            return "New";
        }
        return (phase < 0.5 ? "Waxing " : "Waning ") + lit.toString() + "%";
    }
}
