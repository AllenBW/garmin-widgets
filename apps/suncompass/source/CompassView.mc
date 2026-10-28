import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// The full app: a compass rose that turns so the direction you face is at
// the top, and inside it the sky seen from above: the horizon is the ring,
// straight up is the centre, and the sun's hourly positions run across it
// from the sunrise mark to the sunset mark. The heading is read four times
// a second while the view is on screen and smoothed so the rose glides.
class CompassView extends WatchUi.View {

    private const AMBER = 0xFFB020;
    private const ORANGE = 0xFF7A3D;
    private const PATH = 0x9A6A14;       // the hourly dots: amber, dimmed
    private const WHITE = 0xF2F2F2;
    private const GRAY = 0x8A8A8A;
    private const DIM = 0x5A5A5A;
    private const TICK = 0x3A3A3A;

    private const POLL_MS = 250;
    private const SMOOTHING = 0.5;       // how far towards each new reading per poll
    private const SETTLED = 0.3;         // degrees: smaller moves are not worth a redraw

    private var _sky as SunSky?;
    private var _now as Number = 0;
    private var _heading as Float? = null;   // degrees clockwise from true north, smoothed; null: no compass
    private var _timer as Timer.Timer?;
    private var _headingFont as FontType = Graphics.FONT_NUMBER_MEDIUM;
    private var _lineFont as FontType = Graphics.FONT_XTINY;
    private var _letterFont as FontType = Graphics.FONT_SMALL;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        var h = dc.getHeight();
        _headingFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.10).toNumber(), Graphics.FONT_NUMBER_MEDIUM);
        _lineFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.042).toNumber(), Graphics.FONT_XTINY);
        _letterFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.06).toNumber(), Graphics.FONT_SMALL);
    }

    function onShow() as Void {
        refresh();
        if (Toybox has :Sensor) {
            Sensor.enableSensorEvents(method(:onSensor));
        }
        var timer = new Timer.Timer();
        timer.start(method(:onTick), POLL_MS, true);
        _timer = timer;
    }

    function onHide() as Void {
        var timer = _timer;
        if (timer != null) {
            timer.stop();
            _timer = null;
        }
        if (Toybox has :Sensor) {
            Sensor.enableSensorEvents(null);
        }
    }

    // The 1 Hz sensor event, and the faster poll in between
    function onSensor(info as Sensor.Info) as Void {
        if (setHeading(info.heading)) {
            WatchUi.requestUpdate();
        }
    }

    function onTick() as Void {
        var moved = false;
        if (Toybox has :Sensor) {
            moved = setHeading(Sensor.getInfo().heading);
        }
        if (moved || refresh()) {
            WatchUi.requestUpdate();
        }
    }

    // Take a compass reading in radians (null when the watch has none).
    // True when the rose needs redrawing.
    function setHeading(radians as Float?) as Boolean {
        var current = _heading;
        if (radians == null) {
            _heading = null;
            return current != null;
        }
        var target = CompassModel.headingDegrees(radians);
        if (current == null) {
            _heading = target;
            return true;
        }
        if (CompassModel.angleDiff(current, target).abs() < SETTLED) {
            return false;
        }
        _heading = CompassModel.smooth(current, target, SMOOTHING);
        return true;
    }

    // The sun maths once a minute; true when it was redone
    function refresh() as Boolean {
        var now = Time.now().value();
        if (_sky != null && now - _now < 60) {
            return false;
        }
        _now = now;
        _sky = CompassModel.status(now);
        return true;
    }

    function onUpdate(dc as Dc) as Void {
        if (_sky == null) {
            refresh();
        }
        var s = _sky as SunSky;
        var w = dc.getWidth();
        var h = dc.getHeight();
        var heading = _heading;
        var turn = (heading != null) ? heading : 0.0;   // no compass: north up

        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        drawRose(dc, w, h, turn);
        drawSky(dc, s, w, h, turn);
        drawCentre(dc, s, w, h, heading);
        drawIndex(dc, w, h);
    }

    // Ticks every 10 degrees round the rim, longer every 30, and the four
    // letters inside them, all turned so `turn` degrees is at the top
    private function drawRose(dc as Dc, w as Number, h as Number, turn as Float) as Void {
        var cx = w / 2;
        var cy = h / 2;
        var outer = w * 0.49;
        for (var deg = 0; deg < 360; deg += 10) {
            var major = (deg % 30 == 0);
            var a = Math.toRadians(deg - turn);
            var inner = major ? w * 0.43 : w * 0.455;
            dc.setPenWidth(major ? 3 : 2);
            dc.setColor(major ? GRAY : TICK, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(cx + (inner * Math.sin(a)).toNumber(), cy - (inner * Math.cos(a)).toNumber(),
                        cx + (outer * Math.sin(a)).toNumber(), cy - (outer * Math.cos(a)).toNumber());
        }
        var letters = ["N", "E", "S", "W"];
        var r = w * 0.385;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        for (var i = 0; i < 4; i++) {
            var a = Math.toRadians(i * 90 - turn);
            dc.setColor((i == 0) ? AMBER : WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + (r * Math.sin(a)).toNumber(), cy - (r * Math.cos(a)).toNumber(), _letterFont, letters[i], center);
        }
    }

    // The horizon ring, the hourly sun positions, the sunrise and sunset
    // marks, and the sun itself: in the dome when it is up, hollow on the
    // ring at its bearing when it is down
    private function drawSky(dc as Dc, s as SunSky, w as Number, h as Number, turn as Float) as Void {
        var cx = w / 2;
        var cy = h / 2;
        var ring = (w * 0.32).toNumber();
        dc.setPenWidth(1);
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, ring);
        if (!s.located) {
            return;
        }

        var dotR = (w * 0.009).toNumber();
        dc.setColor(PATH, Graphics.COLOR_TRANSPARENT);
        var hours = s.hours;
        for (var i = 0; i < hours.size(); i++) {
            var p = project(hours[i][0], hours[i][1], turn, cx, cy, ring);
            dc.fillCircle(p[0], p[1], dotR);
        }

        var mark = (w * 0.024).toNumber();
        var riseAz = s.riseAz;
        if (riseAz != null) {
            var p = project(0.0, riseAz, turn, cx, cy, ring);
            drawTriangle(dc, p[0], p[1], mark, true, AMBER);
        }
        var setAz = s.setAz;
        if (setAz != null) {
            var p = project(0.0, setAz, turn, cx, cy, ring);
            drawTriangle(dc, p[0], p[1], mark, false, ORANGE);
        }

        var sun = project(s.up ? s.alt : 0.0, s.az, turn, cx, cy, ring);
        if (s.up) {
            // A hairline out to the horizon makes the bearing easy to read off the ticks
            var edge = project(0.0, s.az, turn, cx, cy, ring);
            dc.setPenWidth(1);
            dc.setColor(PATH, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(sun[0], sun[1], edge[0], edge[1]);
            dc.setColor(AMBER, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(sun[0], sun[1], (w * 0.035).toNumber());
        } else {
            dc.setPenWidth(2);
            dc.setColor(PATH, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(sun[0], sun[1], (w * 0.025).toNumber());
        }
    }

    // The heading, and the next sun event under it
    private function drawCentre(dc as Dc, s as SunSky, w as Number, h as Number, heading as Float?) as Void {
        var cx = w / 2;
        var cy = h / 2;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        if (heading != null) {
            dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - (h * 0.035).toNumber(), _headingFont,
                        CompassText.degrees(heading) + " " + CompassModel.cardinal(heading), center);
        } else {
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - (h * 0.035).toNumber(), _lineFont, "no compass", center);
        }
        dc.setColor(AMBER, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + (h * 0.055).toNumber(), _lineFont, CompassText.nextLine(s), center);
    }

    // The fixed mark at the top of the screen: the direction you face
    private function drawIndex(dc as Dc, w as Number, h as Number) as Void {
        var cx = w / 2;
        var cy = h / 2;
        var top = cy - (w * 0.49).toNumber();
        var tip = cy - (w * 0.44).toNumber();
        var half = (w * 0.025).toNumber();
        dc.setColor(AMBER, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[cx, tip], [cx - half, top], [cx + half, top]] as Array<Graphics.Point2D>);
    }

    // The sky seen from above: the horizon at `ring` pixels from the
    // centre, straight up at the centre, bearings clockwise from the top
    // once the rose has turned by `turn` degrees. Below the horizon lands
    // on the ring.
    function project(alt as Float, az as Float, turn as Float, cx as Number, cy as Number, ring as Number) as [Number, Number] {
        var d = (alt > 0.0) ? (90.0 - alt) / 90.0 * ring : ring.toFloat();
        var a = Math.toRadians(az - turn);
        return [cx + (d * Math.sin(a)).toNumber(), cy - (d * Math.cos(a)).toNumber()];
    }

    // An up or down triangle `size` wide, centred on (x, y)
    private function drawTriangle(dc as Dc, x as Number, y as Number, size as Number, up as Boolean, color as ColorType) as Void {
        var half = size / 2;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        if (up) {
            dc.fillPolygon([[x, y - half], [x - half, y + half], [x + half, y + half]] as Array<Graphics.Point2D>);
        } else {
            dc.fillPolygon([[x, y + half], [x - half, y - half], [x + half, y - half]] as Array<Graphics.Point2D>);
        }
    }
}
