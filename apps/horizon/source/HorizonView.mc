import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;
import Toybox.Weather;

// Horizon: a normal 12-hour dial, but the bezel shows what is coming in the
// next twelve hours. Each hour is a segment: dark grey by day, navy after
// sunset, and blue when rain is likely, brighter as the odds rise. A sun
// marker sits where the sun sets or rises, a diamond where the next
// calendar event is, and a hand at now. Centre: date, time, the rain
// outlook in words, then temperature, the sun event and the event time.
//
// The colours are the sky's (Skies: the sky and the time colour chosen, or
// the look's), the first sky the face's own.
//
// Always-on: a 2 px hairline with the rain hours in dim blue, a hollow hand,
// hollow time; everything shifted a few pixels each minute.
class HorizonView extends WatchUi.WatchFace {

    private var _awake as Boolean = true;
    private var _look as Number = Lib.Look.YOURS;
    private var _day as Number = 0;                // the day the daily look's sky is for
    private var _c as Array<Number> = Skies.SETS[0];   // the palette, a colour a place (Skies)
    private var _burnIn as Boolean = false;
    private var _minute as Number = -1;
    private var _sunKey as String = "";            // the day and place the sun times are for
    private var _sun as [Number?, Number?, Number?] = [null, null, null];
    private var _outlook as HorizonOutlook = new HorizonOutlook();
    private var _temp as String = "";
    private var _smallFont as FontType = Graphics.FONT_XTINY;

    // How quickly the face lights, for the watch's log
    private var _log as Lib.Timing.Log;

    function initialize() {
        WatchFace.initialize();
        _log = new Lib.Timing.Log("Horizon");
        _burnIn = Lib.Aod.required();
        reloadSettings();
    }

    // The look and its colours, at a start and when a setting or the look changes
    function reloadSettings() as Void {
        _look = Lib.Look.mode();
        _day = Lib.Look.today();
        _c = Skies.colors(_look);
    }

    // The tests: a palette drawn as it is, every sky, look and time colour
    function setColors(colors as Array<Number>) as Void {
        _c = colors;
    }

    function setAwake(awake as Boolean) as Void {
        _awake = awake;
    }

    function onLayout(dc as Dc) as Void {
        _smallFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (dc.getHeight() * 0.048).toNumber(), Graphics.FONT_XTINY);
    }

    function onUpdate(dc as Dc) as Void {
        var started = System.getTimer();
        if (_look == Lib.Look.DAILY && Lib.Look.today() != _day) {
            reloadSettings();     // a new day, a new sky
        }
        refresh();
        _log.part = System.getTimer() - started;   // the readings: the face's costly part
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (!_awake && _burnIn) {
            drawAlwaysOn(dc);
        } else {
            drawActive(dc);
            _log.frame(started, true);
        }
    }

    function onEnterSleep() as Void {
        _awake = false;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _awake = true;
        _log.wake();
        WatchUi.requestUpdate();
    }

    // ----------------------------------------------------------------- data

    // Once a minute: the forecast, the sun and the calendar into the outlook
    function refresh() as Void {
        var clock = System.getClockTime();
        var now = Time.now().value();
        if (now / 60 == _minute) {
            return;
        }
        _minute = now / 60;
        var nowSecs = clock.hour * 3600 + clock.min * 60;
        var dayStart = now - (nowSecs + clock.sec);

        // Hourly forecast as [wall-clock seconds since midnight, chance], and
        // the chance now for this hour, unless the phone has been away for hours
        var hours = [] as Array<[Number, Number]>;
        if ((Toybox has :Weather) && (Weather has :getHourlyForecast)) {
            var forecast = Weather.getHourlyForecast();
            if (forecast != null) {
                for (var i = 0; i < forecast.size(); i++) {
                    var when = forecast[i].forecastTime;
                    var chance = forecast[i].precipitationChance;
                    if (when != null && chance != null) {
                        hours.add([Lib.Fmt.wallSeconds(when.value(), dayStart), chance]);
                    }
                }
            }
        }
        // the current conditions read once a minute, for the chance now and the temperature
        var cc = (Toybox has :Weather) ? Weather.getCurrentConditions() : null;
        if (cc != null) {
            var seen = cc.observationTime;
            var chance = cc.precipitationChance;
            if (chance != null && (seen == null || now - seen.value() < 3 * 3600)) {
                hours.add([nowSecs, chance]);
            }
        }

        var sun = sunTimes(dayStart);
        _outlook = HorizonModel.build(nowSecs, hours, sun[0], sun[1], sun[2], calendarText());

        _temp = "";
        var celsius = (cc != null) ? cc.temperature : null;
        if (celsius != null) {
            _temp = Lib.Fmt.temperature(celsius);
        }
        sample();
    }

    // The outlook of the store screenshot: 14:38 on a late-October day,
    // rain building from 17:00 (40 %) to 18:00 (60 %), sunset 19:22, an
    // event at 15:30, 46°; the sample build (sample.jungle) swaps it in
    (:live)
    private function sample() as Void {
    }

    (:sample)
    private function sample() as Void {
        var now = 14 * 3600 + 38 * 60;
        var chances = [20, 10, 20, 40, 60, 30, 10, 0, 0, 0, 0, 0] as Array<Number>;
        var hours = [] as Array<[Number, Number]>;
        for (var k = 0; k < chances.size(); k++) {
            hours.add([14 * 3600 + k * 3600, chances[k]]);
        }
        _outlook = HorizonModel.build(now, hours, 7 * 3600 + 12 * 60, 19 * 3600 + 22 * 60, 86400 + 7 * 3600 + 13 * 60, "15:30");
        _temp = "46°";
    }

    // The time of day and the date, read at draw time
    (:live)
    private function nowSeconds() as Number {
        var clock = System.getClockTime();
        return clock.hour * 3600 + clock.min * 60;
    }

    (:sample)
    private function nowSeconds() as Number {
        return 14 * 3600 + 38 * 60;
    }

    (:live)
    private function dateText() as String {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        return Lang.format("$1$ $2$ $3$", [info.day_of_week, info.day, info.month]).toUpper();
    }

    (:sample)
    private function dateText() as String {
        return "FRI 31 OCT";
    }

    // Sunrise, sunset and tomorrow's sunrise as seconds after today's
    // midnight, worked out once a day (and again when the place changes):
    // the sun maths from the last known location, else the watch's own figures
    private function sunTimes(dayStart as Number) as [Number?, Number?, Number?] {
        var where = Lib.Location.get();
        var key = dayStart.toString() + ((where != null) ? where[0].format("%.2f") + where[1].format("%.2f") : "");
        if (!key.equals(_sunKey)) {
            _sunKey = key;
            if (where != null) {
                _sun = Lib.Solar.riseSet(where[0], where[1], dayStart);
            } else {
                var times = Lib.Sun.today();
                var rise = times[0];
                _sun = [rise, times[1], (rise != null) ? rise + 86400 : null];
            }
        }
        return _sun;
    }

    // The next calendar event's time as the complication gives it, or null
    private function calendarText() as String? {
        if (!(Toybox has :Complications)) {
            return null;
        }
        try {
            var c = Complications.getComplication(new Complications.Id(Complications.COMPLICATION_TYPE_CALENDAR_EVENTS));
            var value = c.value;
            return (value instanceof String) ? value : null;
        } catch (e) {
            return null;
        }
    }

    // --------------------------------------------------------------- active

    private function drawActive(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var o = _outlook;
        var c = _c;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var ringR = w * 0.46;
        var ringW = (w * 0.05).toNumber();

        // Twelve segments from the current hour, clockwise, with a small gap
        for (var k = 0; k < 12; k++) {
            var start = HorizonModel.dialDegrees(o.hourStart + k * 3600) + 1.5;
            var color = o.night[k] ? c[Skies.NIGHT] : c[Skies.TRACK];
            var chance = o.rain[k];
            if (chance < 0) {
                // No forecast for this hour: a hairline, so it never reads as dry
                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                Lib.Arcs.drawClockwise(dc, cx, cy, ringR, start, 27, 2);
                continue;
            }
            if (chance >= 60) {
                color = c[Skies.RAIN];
            } else if (chance >= 40) {
                color = c[Skies.RAIN_MID];
            } else if (chance >= 20) {
                color = c[Skies.RAIN_LOW];
            }
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            Lib.Arcs.drawClockwise(dc, cx, cy, ringR, start, 27, ringW);
        }

        // The sun event and the calendar event on the ring
        var sun = o.sunSecs;
        if (sun != null) {
            var p = Lib.Arcs.point(cx, cy, w * 0.405, HorizonModel.dialDegrees(sun));
            drawTriangle(dc, p[0].toNumber(), p[1].toNumber(), (w * 0.03).toNumber(), o.sunIsRise, o.sunIsRise ? c[Skies.RISE] : c[Skies.SET]);
        }
        var cal = o.calendarSecs;
        if (cal != null) {
            var p = Lib.Arcs.point(cx, cy, w * 0.405, HorizonModel.dialDegrees(cal));
            drawDiamond(dc, p[0].toNumber(), p[1].toNumber(), (w * 0.016).toNumber(), c[Skies.TIME]);
        }

        // The hand: a dot on the ring at now
        var nowSecs = nowSeconds();
        var tip = Lib.Arcs.point(cx, cy, ringR, HorizonModel.dialDegrees(nowSecs));
        var dotR = (w * 0.03).toNumber();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(tip[0], tip[1], dotR + 3);
        dc.setColor(c[Skies.TIME], Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(tip[0], tip[1], dotR);

        // Centre: date (for a moment after a hold, the look's name), time,
        // rain, then temperature / sun / event
        dc.setColor(c[Skies.TEXT], Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.30).toNumber(), Graphics.FONT_TINY, Lib.Look.shown() ? Skies.title(_look) : dateText(), center);
        dc.setColor(c[Skies.TIME], Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.47).toNumber(), Graphics.FONT_NUMBER_MEDIUM, Lib.Fmt.clock(nowSecs), center);
        dc.setColor((o.rainFrom != null) ? c[Skies.RAIN] : c[Skies.TEXT], Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.635).toNumber(), _smallFont, HorizonModel.rainText(o), center);
        drawDetails(dc, cx, (h * 0.715).toNumber(), w, o);
    }

    // "61°   ▼ 17:41   ◆ 16:00", centred, with the glyphs drawn
    private function drawDetails(dc as Dc, cx as Number, y as Number, w as Number, o as HorizonOutlook) as Void {
        var font = _smallFont;
        var c = _c;
        var glyph = (w * 0.024).toNumber();
        var gap = (w * 0.014).toNumber();
        var between = (w * 0.05).toNumber();
        var sun = o.sunSecs;
        var cal = o.calendarSecs;
        var sunText = (sun != null) ? Lib.Fmt.clock(sun) : "";
        var calText = (cal != null) ? Lib.Fmt.clock(cal) : "";

        var total = 0;
        if (_temp.length() > 0) {
            total += dc.getTextWidthInPixels(_temp, font) + between;
        }
        if (sun != null) {
            total += glyph + gap + dc.getTextWidthInPixels(sunText, font) + between;
        }
        if (cal != null) {
            total += glyph + gap + dc.getTextWidthInPixels(calText, font) + between;
        }
        if (total == 0) {
            return;
        }
        total -= between;
        var x = cx - total / 2;
        var left = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(c[Skies.TEXT], Graphics.COLOR_TRANSPARENT);
        if (_temp.length() > 0) {
            dc.drawText(x, y, font, _temp, left);
            x += dc.getTextWidthInPixels(_temp, font) + between;
        }
        if (sun != null) {
            drawTriangle(dc, x + glyph / 2, y, glyph, o.sunIsRise, o.sunIsRise ? c[Skies.RISE] : c[Skies.SET]);
            dc.setColor(c[Skies.TEXT], Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + glyph + gap, y, font, sunText, left);
            x += glyph + gap + dc.getTextWidthInPixels(sunText, font) + between;
        }
        if (cal != null) {
            drawDiamond(dc, x + glyph / 2, y, glyph / 2, c[Skies.TIME]);
            dc.setColor(c[Skies.TEXT], Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + glyph + gap, y, font, calText, left);
        }
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

    private function drawDiamond(dc as Dc, x as Number, y as Number, r as Number, color as ColorType) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[x, y - r], [x + r, y], [x, y + r], [x - r, y]] as Array<Graphics.Point2D>);
    }

    // ------------------------------------------------------------ always-on

    private function drawAlwaysOn(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var o = _outlook;
        var clock = System.getClockTime();
        var off = Lib.Aod.offset(clock.min, (w * 0.013).toNumber());
        var cx = w / 2 + off[0];
        var cy = h / 2 + off[1];
        var ringR = w * 0.454;
        var faint = _c[Skies.FAINT];

        // Hairline: only the rain hours, in the rain's colour at a quarter
        dc.setColor(Lib.Aod.dim(_c[Skies.RAIN]), Graphics.COLOR_TRANSPARENT);
        for (var k = 0; k < 12; k++) {
            if (o.rain[k] >= 40) {
                Lib.Arcs.drawClockwise(dc, cx, cy, ringR, HorizonModel.dialDegrees(o.hourStart + k * 3600) + 1.5, 27, 2);
            }
        }

        // Hollow hand
        var nowSecs = nowSeconds();
        var tip = Lib.Arcs.point(cx, cy, ringR, HorizonModel.dialDegrees(nowSecs));
        dc.setPenWidth(2);
        dc.setColor(faint, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(tip[0], tip[1], (w * 0.016).toNumber());

        Lib.Aod.drawHollowText(dc, cx, (h * 0.485).toNumber() + off[1], Graphics.FONT_NUMBER_MEDIUM, Lib.Fmt.clock(nowSecs), Skies.standby(_c[Skies.TIME]),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var sun = o.sunSecs;
        if (sun != null) {
            dc.setColor(faint, Graphics.COLOR_TRANSPARENT);
            var text = Lib.Fmt.clock(sun);
            var tri = (w * 0.02).toNumber();
            var gap = (w * 0.015).toNumber();
            var x = cx - (tri + gap + dc.getTextWidthInPixels(text, Graphics.FONT_XTINY)) / 2;
            var y = (h * 0.70).toNumber() + off[1];
            drawTriangle(dc, x + tri / 2, y, tri, o.sunIsRise, faint);
            dc.setColor(faint, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + tri + gap, y, Graphics.FONT_XTINY, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }
}
