import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;
import Toybox.Weather;

// Forage: the date, the time in 24-hour form, what the bees are doing now
// with the temperature, when to open the hive, the next twelve hours as a
// strip of comb (capped: open the hive; honey: flying; empty: home; a drop:
// rain), and the beekeeper's year along the bottom of the bezel.
//
// Always-on: the hollow time and the verdict, dim, shifted each minute.
class ForageView extends WatchUi.WatchFace {

    private const CREAM = 0xF2ECE2;
    private const GRAY = 0x8A8A8A;
    private const DIM = 0x5A5A5A;
    private const TRACK = 0x262626;
    private const CELL = 0x3A3A3A;
    private const HONEY = 0xB8730F;
    private const WAX = 0xFFC94A;
    private const WAX_RIM = 0xFFE3A0;
    private const CYAN = 0x3EC6E0;
    private const WING = 0xB9B4AC;

    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;
    private var _minute as Number = -1;
    private var _outlook as ForageOutlook = new ForageOutlook();
    private var _now as Number = BEES_UNKNOWN;
    private var _temp as String = "";
    private var _windText as String = "";
    private var _date as String = "";
    private var _dayOfYear as Number = 1;
    private var _timeFont as FontType = Graphics.FONT_NUMBER_MEDIUM;
    private var _verdictFont as FontType = Graphics.FONT_TINY;
    private var _smallFont as FontType = Graphics.FONT_XTINY;
    private var _labelFont as FontType = Graphics.FONT_XTINY;
    private var _cellFont as FontType = Graphics.FONT_XTINY;

    function initialize() {
        WatchFace.initialize();
        _burnIn = Lib.Aod.required();
    }

    function onLayout(dc as Dc) as Void {
        var h = dc.getHeight();
        // getVectorFont sizes a font by its whole height, about 1.17 ems
        _timeFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.33).toNumber(), Graphics.FONT_NUMBER_HOT);
        _verdictFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.072).toNumber(), Graphics.FONT_TINY);
        _smallFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.057).toNumber(), Graphics.FONT_XTINY);
        _labelFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.054).toNumber(), Graphics.FONT_XTINY);
        _cellFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.036).toNumber(), Graphics.FONT_XTINY);
    }

    function onUpdate(dc as Dc) as Void {
        refresh();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (!_awake && _burnIn) {
            drawAlwaysOn(dc);
        } else {
            drawActive(dc);
        }
    }

    function onEnterSleep() as Void {
        _awake = false;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _awake = true;
        WatchUi.requestUpdate();
    }

    // What a press and hold at (x, y) opens: the weather widget below the time
    function targetAt(x as Number, y as Number) as Complications.Type? {
        var h = System.getDeviceSettings().screenHeight;
        return (y > h * 0.45) ? Complications.COMPLICATION_TYPE_CURRENT_WEATHER : null;
    }

    // ----------------------------------------------------------------- data

    // Once a minute: the weather now and the forecast into the outlook
    function refresh() as Void {
        var clock = System.getClockTime();
        if (clock.min == _minute) {
            return;
        }
        _minute = clock.min;
        var nowSecs = clock.hour * 3600 + clock.min * 60;
        var now = Time.now();
        var dayStart = now.value() - (nowSecs + clock.sec);

        var info = Gregorian.info(now, Time.FORMAT_MEDIUM);
        _date = Lang.format("$1$ $2$ $3$", [info.day_of_week, info.month, info.day]).toUpper();
        var short = Gregorian.info(now, Time.FORMAT_SHORT);
        _dayOfYear = ForageModel.dayOfYear(short.month as Number, short.day);

        // Sunrise and sunset: the sun maths from the last known location,
        // else the watch's own figures
        var rise = null;
        var set = null;
        var tomorrowRise = null;
        var where = Lib.Location.get();
        if (where != null) {
            var today = Lib.Solar.day(where[0], where[1], dayStart);
            var tomorrow = Lib.Solar.day(where[0], where[1], dayStart + 86400);
            var r = today.rise;
            var s = today.set;
            var tr = tomorrow.rise;
            rise = (r != null) ? r - dayStart : null;
            set = (s != null) ? s - dayStart : null;
            tomorrowRise = (tr != null) ? tr - dayStart : null;
        } else {
            var times = Lib.Sun.today();
            rise = times[0];
            set = times[1];
            tomorrowRise = (rise != null) ? rise + 86400 : null;
        }

        var hours = [] as Array<ForageHour>;
        _now = BEES_UNKNOWN;
        _temp = "";
        _windText = "";
        if (Toybox has :Weather) {
            if (Weather has :getHourlyForecast) {
                var forecast = Weather.getHourlyForecast();
                if (forecast != null) {
                    for (var i = 0; i < forecast.size(); i++) {
                        var f = forecast[i];
                        var when = f.forecastTime;
                        if (when != null) {
                            hours.add(new ForageHour(when.value() - dayStart, f.temperature, f.precipitationChance,
                                f.windSpeed, (f has :cloudCover) ? f.cloudCover : null, f.condition));
                        }
                    }
                }
            }
            var cc = Weather.getCurrentConditions();
            if (cc != null) {
                var current = new ForageHour(nowSecs, cc.temperature, cc.precipitationChance, cc.windSpeed,
                    (cc has :cloudCover) ? cc.cloudCover : null, cc.condition);
                _now = ForageModel.kind(current, ForageModel.isDay(nowSecs, rise, set, tomorrowRise), clock.hour);
                hours.add(current);   // the current hour, when the forecast starts at the next one
                var celsius = cc.temperature;
                if (celsius != null) {
                    _temp = Lib.Fmt.temperature(celsius) + (metricTemp() ? "C" : "F");
                }
                var wind = cc.windSpeed;
                if (wind != null) {
                    _windText = metricDistance()
                        ? Math.round(wind * 3.6).toNumber().toString() + " KM/H"
                        : Math.round(wind * 2.237).toNumber().toString() + " MPH";
                }
            }
        }
        _outlook = ForageModel.build(nowSecs, hours, rise, set, tomorrowRise);
    }

    private function metricTemp() as Boolean {
        return System.getDeviceSettings().temperatureUnits == System.UNIT_METRIC;
    }

    private function metricDistance() as Boolean {
        return System.getDeviceSettings().distanceUnits == System.UNIT_METRIC;
    }

    // --------------------------------------------------------------- active

    private function drawActive(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var clock = System.getClockTime();

        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.176).toNumber(), _labelFont, _date, center);
        dc.setColor(CREAM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.335).toNumber(), _timeFont, ForageModel.clock24(clock.hour * 3600 + clock.min * 60), center);

        drawVerdict(dc, cx, (h * 0.496).toNumber(), w);
        var window = ForageModel.windowText(_outlook);
        if (window.length() > 0) {
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.577).toNumber(), _smallFont, window, center);
        }
        drawComb(dc, cx, (h * 0.709).toNumber(), w * 0.044);
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.85).toNumber(), _labelFont, ForageModel.season(_dayOfYear), center);
        drawYear(dc, w, h);
    }

    // A bee, the verdict, then the temperature (or the wind when that is the reason), centred
    private function drawVerdict(dc as Dc, cx as Number, y as Number, w as Number) as Void {
        var words = ForageModel.verdict(_now);
        var flying = _now == BEES_FLY || _now == BEES_OPEN || _now == BEES_CLEANSE;
        var extra = (_now == BEES_WIND) ? _windText : _temp;
        var bee = (w * 0.058).toNumber();
        var gap = (w * 0.022).toNumber();
        var total = dc.getTextWidthInPixels(words, _verdictFont);
        if (flying) {
            total += bee + gap;
        }
        if (extra.length() > 0) {
            total += gap + dc.getTextWidthInPixels(extra, _verdictFont);
        }
        var x = cx - total / 2;
        var left = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        if (flying) {
            drawBee(dc, x + bee / 2, y, bee);
            x += bee + gap;
        }
        dc.setColor(flying ? WAX : GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, _verdictFont, words, left);
        x += dc.getTextWidthInPixels(words, _verdictFont) + gap;
        if (extra.length() > 0) {
            dc.setColor(CREAM, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, _verdictFont, extra, left);
        }
    }

    // A bee seen from above, `size` wide: two pale wings, a striped body
    private function drawBee(dc as Dc, x as Number, y as Number, size as Number) as Void {
        var wing = size * 0.22;
        dc.setColor(WING, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - size * 0.18, y - size * 0.3, wing);
        dc.fillCircle(x + size * 0.18, y - size * 0.3, wing);
        dc.setColor(WAX, Graphics.COLOR_TRANSPARENT);
        dc.fillEllipse(x, y, size * 0.45, size * 0.3);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        var stripe = (size * 0.09).toNumber() + 1;
        dc.fillRectangle(x - size * 0.1, y - size * 0.3, stripe, size * 0.6);
        dc.fillRectangle(x + size * 0.14, y - size * 0.27, stripe, size * 0.54);
    }

    // Twelve cells zig-zagging like comb, the current hour outlined
    private function drawComb(dc as Dc, cx as Number, cy as Number, r as Numeric) as Void {
        var o = _outlook;
        var pitch = 1.5 * r;
        var x0 = cx - pitch * 5.5;
        var dy = Math.sqrt(3) / 4 * r;
        var inner = r - 2;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        for (var k = 0; k < 12; k++) {
            var x = x0 + k * pitch;
            var y = cy + ((k % 2 == 0) ? -dy : dy);
            var kind = o.kinds[k];
            if (k == 0) {
                fillHex(dc, x, y, r + 1, CREAM);
                fillHex(dc, x, y, r - 1, Graphics.COLOR_BLACK);
            }
            var label = DIM;
            if (kind == BEES_OPEN) {
                fillHex(dc, x, y, inner, WAX);
                fillHex(dc, x, y, inner - 4, WAX_RIM);
                fillHex(dc, x, y, inner - 5.5, WAX);
                label = Graphics.COLOR_BLACK;
            } else if (kind == BEES_FLY) {
                fillHex(dc, x, y, inner, HONEY);
                label = Graphics.COLOR_BLACK;
            } else {
                fillHex(dc, x, y, inner, (kind == BEES_CLEANSE) ? HONEY : CELL);
                fillHex(dc, x, y, inner - 2, Graphics.COLOR_BLACK);
            }
            if (kind == BEES_RAIN) {
                drawDrop(dc, x, y, r * 0.75);
            } else if (kind != BEES_UNKNOWN) {
                dc.setColor(label, Graphics.COLOR_TRANSPARENT);
                dc.drawText(x, y, _cellFont, ((o.hourStart / 3600 + k) % 24).format("%02d"), center);
            }
        }
    }

    // A flat-topped hexagon of radius r
    private function fillHex(dc as Dc, x as Numeric, y as Numeric, r as Numeric, color as ColorType) as Void {
        var pts = new [6] as Array<Graphics.Point2D>;
        for (var i = 0; i < 6; i++) {
            var a = Math.PI / 3 * i;
            pts[i] = [x + r * Math.cos(a), y + r * Math.sin(a)];
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(pts);
    }

    private function drawDrop(dc as Dc, x as Numeric, y as Numeric, size as Numeric) as Void {
        var r = size * 0.3;
        var cy = y + size * 0.18;
        dc.setColor(CYAN, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, cy, r);
        dc.fillPolygon([[x, y - size / 2], [x - r, cy - 1], [x + r, cy - 1]] as Array<Graphics.Point2D>);
    }

    // The year along the bottom of the bezel, January at the left, with the
    // nectar flows on it and a dot at today
    private function drawYear(dc as Dc, w as Number, h as Number) as Void {
        var cx = w / 2;
        var cy = h / 2;
        var r = w * 0.476;
        var pen = (w * 0.011).toNumber() + 1;
        dc.setPenWidth(pen);
        dc.setColor(TRACK, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, yearAngle(1), yearAngle(365));
        var flows = ForageModel.flows();
        for (var i = 0; i < flows.size(); i++) {
            dc.setColor(flows[i][2] ? WAX : HONEY, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, r, Graphics.ARC_COUNTER_CLOCKWISE, yearAngle(flows[i][0]), yearAngle(flows[i][1]));
        }
        var a = Math.toRadians(yearAngle(_dayOfYear));
        var x = cx + r * Math.cos(a);
        var y = cy - r * Math.sin(a);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, w * 0.013 + 2);
        dc.setColor(CREAM, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, w * 0.013);
        dc.setPenWidth(1);
    }

    // Day of the year -> drawArc degrees (counter-clockwise from 3 o'clock):
    // 1 January at the lower left (224°), 31 December at the lower right (316°)
    private function yearAngle(day as Number) as Float {
        return 224.0 + 92.0 * (day - 1) / 364.0;
    }

    // ------------------------------------------------------------ always-on

    private function drawAlwaysOn(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var clock = System.getClockTime();
        var off = Lib.Aod.offset(clock.min, (w * 0.013).toNumber());
        var cx = w / 2 + off[0];
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        Lib.Aod.drawHollowText(dc, cx, (h * 0.375).toNumber() + off[1], _timeFont,
            ForageModel.clock24(clock.hour * 3600 + clock.min * 60), GRAY, center);
        var line = ForageModel.verdict(_now);
        if (_temp.length() > 0) {
            line += " · " + _temp;
        }
        var flying = _now == BEES_FLY || _now == BEES_OPEN || _now == BEES_CLEANSE;
        dc.setColor(flying ? 0x7A5A20 : DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.542).toNumber() + off[1], _smallFont, line, center);
    }
}
