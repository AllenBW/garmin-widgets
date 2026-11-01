import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.UserProfile;
import Toybox.WatchUi;

// Vessel: the digits are the gauges. The hours (in the data colour) stand
// over the minutes (in the accent), set left of the axis, each pair drawn
// as a glass that fills from the bottom to a reading: the hours to the
// first slot (the weather by default: the temperature between today's low
// and high), the minutes to the second (the heart rate, from resting to
// the maximum). Each reading's number sits on its waterline, to the right
// of the glass, marked by a small triangle pointing at it. The date in
// spaced capitals over the time, a third reading under it in words
// ("SUNSET 19:22" by default), nothing else; the accent is the minutes'
// alone. A reading with no range fills its glass, unmarked.
//
// Everything is set in the watch face editor or the phone app's settings
// (Lib.Config): the typeface, the accent (any colour), the data colour,
// the three readings (any complication), and the bedside clock. After
// sunset the colours soften.
//
// Standby (always-on): the glasses empty to a single waterline drawn
// across each digit, the outlines and the readings dim, shifted each
// minute; about 7 % of the screen lit (designs/preview_vessel.py). During
// the watch's sleep hours, a bedside clock: the outlined time alone in a
// dim ember red, and a bell while an alarm is set.
class VesselView extends WatchUi.WatchFace {

    // The layout, as fractions of the screen: the same numbers as
    // designs/preview_vessel.py
    private const DIGITS = 0.285;                // each row's digit height
    private const AOD_DIGITS = 0.270;
    private const ROW_GAP = 0.040;               // between the hours' and the minutes' ink
    private const INK_RIGHT = 0.639;             // the time's ink right edge
    private const MID = 0.485;                   // the stack's centre, a touch over the screen's
    private const AXIS = 0.430;                  // the date's and the foot's centre: the glasses' axis
    private const MARK_GAP = 0.026;              // from the glass to its waterline mark's tip
    private const MARK_W = 0.018;                // the mark: a small triangle pointing at the glass
    private const MARK_H = 0.022;
    private const VALUE_X = 0.036;               // from the mark's tip to the reading
    private const VALUE_EM = 0.070;
    private const AOD_VALUE_EM = 0.060;
    private const UNIT = 0.70;                   // a unit's size, of the value's
    private const ICON = 0.040;
    private const FULL = 0.96;                   // a glass this full is full
    private const DATE_Y = 0.112;
    private const DATE_EM = 0.050;               // the date's and the foot's
    private const DATE = 0.85;                   // their share of the data colour
    private const AOD_DATE = 0.55;
    private const TRACK = 0.007;                 // the spaced capitals' letter spacing
    private const FOOT_Y = 0.870;
    private const BELL_GAP = 0.048;              // from the date's end to the alarm bell's centre
    private const EM_HEIGHT = 1.173;             // Roboto Condensed's height per em (Lib.Ink.HEIGHT)
    private const NIGHT = 0.85;                  // the colours after sunset

    enum Style { BIONIC, CONDENSED, RAJDHANI }
    private const FACES = [Lib.Ink.BIONIC_BOLD, Lib.Ink.CONDENSED_BOLD, Lib.Ink.BIONIC_MEDIUM] as Array<Number>;
    private const DEFAULTS = [
        Complications.COMPLICATION_TYPE_CURRENT_WEATHER, Complications.COMPLICATION_TYPE_HEART_RATE,
        Complications.COMPLICATION_TYPE_SUNRISE      // the next sunrise or sunset
    ] as Array<Complications.Type>;
    const SLOTS = 3;

    // Settings
    private var _style as Number = BIONIC;
    private var _accent as Number = 0xFFB020;
    private var _data as Number = 0xF2ECE2;
    private var _ids as Array<Complications.Id> = [] as Array<Complications.Id>;
    private var _kinds as Array<Number> = [] as Array<Number>;
    private var _bedside as Boolean = true;

    // Fonts
    private var _w as Number = 454;
    private var _em as Float = 0.0;
    private var _aodEm as Float = 0.0;
    private var _timeFont as FontType = Graphics.FONT_NUMBER_HOT;
    private var _aodTimeFont as FontType = Graphics.FONT_NUMBER_MEDIUM;
    private var _valueFont as FontType = Graphics.FONT_SMALL;
    private var _aodValueFont as FontType = Graphics.FONT_TINY;
    private var _unitFont as FontType = Graphics.FONT_XTINY;
    private var _dateFont as FontType = Graphics.FONT_XTINY;

    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;

    // The once-a-minute state
    private var _minute as Number = -1;
    private var _hours as String = "";
    private var _minutes as String = "";
    private var _date as String = "";
    private var _readings as Array<Lib.Slots.Reading> = [] as Array<Lib.Slots.Reading>;
    private var _alarms as Number = 0;
    private var _night as Boolean = false;
    private var _asleep as Boolean = false;      // within the watch's sleep hours

    // Press targets, [slot (0-based, SLOTS for the date), x, y, half width, half height]
    private var _targets as Array<Array<Number>> = [] as Array<Array<Number>>;

    function initialize() {
        WatchFace.initialize();
        _burnIn = Lib.Aod.required();
        reloadSettings();
    }

    // ------------------------------------------------------------ settings

    function reloadSettings() as Void {
        var s = Lib.Config.read(FACES.size(), DEFAULTS);
        var restyled = s[0] != _style;
        _style = s[0];
        _accent = s[1];
        _data = s[2];
        _ids = s[3];
        _bedside = s[4];
        var kinds = [] as Array<Number>;
        for (var n = 0; n < _ids.size(); n++) {
            kinds.add(Lib.Slots.kindOf(_ids[n].getType()));
        }
        _kinds = kinds;
        subscribe();
        if (restyled && _em > 0) {
            makeFonts();
        }
        _minute = -1;
    }

    // Follow the readings, so other apps' keep coming
    private function subscribe() as Void {
        if (!(Toybox has :Complications)) {
            return;
        }
        try {
            Complications.unsubscribeFromAllUpdates();
            for (var n = 0; n < _ids.size(); n++) {
                Complications.subscribeToUpdates(_ids[n]);
            }
            Complications.registerComplicationChangeCallback(method(:onComplicationChanged));
        } catch (e) {
            // a complication this watch doesn't have: it shows "--"
        }
    }

    function onComplicationChanged(id as Complications.Id) as Void {
        _minute = -1;
    }

    // The reading slot (1 to 3) at (x, y), for the editor's taps, or null
    function slotAt(x as Number, y as Number) as Number? {
        for (var i = 0; i < _targets.size(); i++) {
            var t = _targets[i];
            if (t[0] < SLOTS && (x - t[1]).abs() <= t[3] && (y - t[2]).abs() <= t[4]) {
                return t[0] + 1;
            }
        }
        return null;
    }

    // The complication a press and hold at (x, y) opens: a glass's or the
    // foot's reading (the weather for the temperature), or the calendar
    // from the date
    function targetAt(x as Number, y as Number) as Complications.Id? {
        for (var i = 0; i < _targets.size(); i++) {
            var t = _targets[i];
            if ((x - t[1]).abs() <= t[3] && (y - t[2]).abs() <= t[4]) {
                return (t[0] < SLOTS) ? Lib.Slots.opens(_kinds[t[0]], _ids[t[0]]) : new Complications.Id(Complications.COMPLICATION_TYPE_CALENDAR_EVENTS);
            }
        }
        return null;
    }

    // ------------------------------------------------------------ layout

    function onLayout(dc as Dc) as Void {
        _w = dc.getWidth();
        Lib.Icons.setWidth(_w);
        makeFonts();
    }

    private function makeFonts() as Void {
        var face = FACES[_style];
        _em = Lib.Ink.em(face, _w * DIGITS);
        _aodEm = Lib.Ink.em(face, _w * AOD_DIGITS);
        _timeFont = Lib.Ink.font(face, _em, Graphics.FONT_NUMBER_HOT);
        _aodTimeFont = Lib.Ink.font(face, _aodEm, Graphics.FONT_NUMBER_MEDIUM);
        _valueFont = font("RobotoCondensedBold", VALUE_EM, Graphics.FONT_SMALL);
        _aodValueFont = font("RobotoCondensedBold", AOD_VALUE_EM, Graphics.FONT_TINY);
        _unitFont = font("RobotoCondensedBold", VALUE_EM * UNIT, Graphics.FONT_XTINY);
        _dateFont = font("RobotoCondensedBold", DATE_EM, Graphics.FONT_XTINY);
    }

    private function font(face as String, em as Float, fallback as FontType) as FontType {
        return Lib.Fmt.vectorFont(face, (_w * em * EM_HEIGHT).toNumber(), fallback);
    }

    // ------------------------------------------------------------ state

    function refresh() as Void {
        var clock = System.getClockTime();
        if (clock.min == _minute) {
            return;
        }
        _minute = clock.min;
        var hour = clock.hour;
        var settings = System.getDeviceSettings();
        if (!settings.is24Hour) {
            hour = hour % 12;
            hour = (hour == 0) ? 12 : hour;
        }
        _hours = settings.is24Hour ? hour.format("%02d") : hour.toString();
        _minutes = clock.min.format("%02d");
        var info = Time.Gregorian.info(Time.now(), Time.FORMAT_LONG);
        _date = (info.day_of_week + " " + info.day).toUpper();
        var readings = [] as Array<Lib.Slots.Reading>;
        for (var n = 0; n < _ids.size(); n++) {
            readings.add(Lib.Slots.read(_kinds[n], _ids[n]));
        }
        _readings = readings;
        _alarms = Lib.Daily.alarms();
        var next = Lib.Sun.next(Lib.Sun.today());
        _night = next != null && next[0];
        _asleep = sleeping(clock.hour * 3600 + clock.min * 60);
        sample();
    }

    // Within the sleep hours set on the watch (and the bedside clock on)
    private function sleeping(now as Number) as Boolean {
        if (!_bedside || !(Toybox has :UserProfile)) {
            return false;
        }
        var profile = UserProfile.getProfile();
        var sleep = profile.sleepTime;
        var wake = profile.wakeTime;
        if (sleep == null || wake == null) {
            return false;
        }
        var from = sleep.value() % 86400;
        var to = wake.value() % 86400;
        return (from <= to) ? (now >= from && now < to) : (now >= from || now < to);
    }

    (:live)
    private function sample() as Void {
    }

    // The screenshots' readings (sample.jungle)
    (:sample)
    private function sample() as Void {
        _hours = "14";
        _minutes = "38";
        _date = "SATURDAY 31";
        _alarms = 1;
        _night = false;
        var samples = {
            Lib.Slots.HEART => ["72", "", 0.32, null, 0], Lib.Slots.STEPS => ["8412", "", 0.84, null, 0],
            Lib.Slots.BATTERY => ["81", "%", 0.81, null, 0], Lib.Slots.BODY => ["64", "", 0.64, null, 0],
            Lib.Slots.STRESS => ["28", "", 0.28, null, 0], Lib.Slots.TEMPERATURE => ["46°", "", 0.55, null, 0],
            Lib.Slots.SUN => ["19:22", "", 0.62, null, -1], Lib.Slots.PRESSURE => ["1013", "HPA", null, null, 1],
            Lib.Slots.OTHER => ["112", "", 0.45, "GLU", 0]
        } as Dictionary<Number, Lib.Slots.Reading>;
        var readings = [] as Array<Lib.Slots.Reading>;
        for (var n = 0; n < _kinds.size(); n++) {
            var r = samples[_kinds[n]];
            readings.add((r != null) ? r : ["--", "", null, null, 0] as Lib.Slots.Reading);
        }
        _readings = readings;
    }

    // For the tests: a fixed time, readings and status
    function setState(hours as String, minutes as String, readings as Array<Lib.Slots.Reading>, alarms as Number,
                      night as Boolean, asleep as Boolean) as Void {
        refresh();
        _hours = hours;
        _minutes = minutes;
        _readings = readings;
        _alarms = alarms;
        _night = night;
        _asleep = asleep;
    }

    function setAwake(awake as Boolean) as Void {
        _awake = awake;
        _burnIn = true;
    }

    function onEnterSleep() as Void {
        _awake = false;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _awake = true;
        _minute = -1;
        WatchUi.requestUpdate();
    }

    // ------------------------------------------------------------ drawing

    function onUpdate(dc as Dc) as Void {
        refresh();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        _targets = [] as Array<Array<Number>>;
        if (!_awake && _burnIn) {
            var off = Lib.Aod.offset(System.getClockTime().min, (_w * 0.012).toNumber());
            if (_asleep) {
                drawBedside(dc, off[0], off[1]);
            } else {
                draw(dc, off[0], off[1], true);
            }
        } else {
            draw(dc, 0, 0, false);
        }
    }

    // Awake (thin false) or standby (thin true), shifted by (ox, oy)
    private function draw(dc as Dc, ox as Number, oy as Number, thin as Boolean) as Void {
        var w = _w;
        var h = dc.getHeight();
        var dim = _night ? NIGHT : 1.0;
        var data = Lib.Config.scale(_data, dim);
        var accent = Lib.Config.scale(_accent, dim);
        var face = FACES[_style];
        var em = thin ? _aodEm : _em;
        var font = thin ? _aodTimeFont : _timeFont;
        var digits = Lib.Ink.height(face, em);
        var gap = h * ROW_GAP;
        var right = w * INK_RIGHT + ox;
        var mids = [h * MID - digits / 2 - gap / 2 + oy, h * MID + digits / 2 + gap / 2 + oy] as Array<Float>;
        var texts = [_hours, _minutes] as Array<String>;
        var colors = [data, accent] as Array<Number>;
        var quiet = Lib.Config.scale(data, Lib.Config.QUIET);
        for (var row = 0; row < 2; row++) {
            var text = texts[row];
            var color = colors[row];
            var x = right + Lib.Ink.right(face, text, em) - dc.getTextWidthInPixels(text, font);
            var y = Lib.Ink.top(face, font, mids[row], em);
            var bottom = mids[row] + digits / 2;
            var reading = (row < _readings.size()) ? _readings[row] : null;
            var frac = (reading != null) ? reading[2] : null;
            var gauge = frac != null;            // a reading with no range fills its glass, unmarked
            var level = bottom - digits * ((frac == null || frac >= FULL) ? 1.0 : frac);
            var ink = dc.getTextWidthInPixels(text, font) - Lib.Ink.left(face, text, em) - Lib.Ink.right(face, text, em);
            if (thin) {
                outline(dc, x, y, font, text, Lib.Config.scale(color, 0.8), 1, Graphics.COLOR_BLACK);
                // the waterline across the glass
                dc.setClip(0, level.toNumber() - 1, w, 3);
                dc.setColor(Lib.Config.scale(color, 0.8), Graphics.COLOR_TRANSPARENT);
                dc.drawText(x, y, font, text, Graphics.TEXT_JUSTIFY_LEFT);
                dc.clearClip();
            } else {
                // the empty part an outline, the filled part the same strokes
                // filled in (no black between them for the fill's edge to show)
                var line = (_style == RAJDHANI || w < 440) ? 2 : 3;
                var cut = level.toNumber();
                dc.setClip(0, 0, w, cut);
                outline(dc, x, y, font, text, color, line, Graphics.COLOR_BLACK);
                dc.setClip(0, cut, w, h - cut);
                outline(dc, x, y, font, text, color, line, color);
                dc.clearClip();
                _targets.add([row, (right - ink / 2).toNumber(), mids[row].toNumber(), (ink / 2).toNumber(), (digits / 2).toNumber()]);
            }
            if (reading != null) {
                // keep the number inside its glass's band, clear of the other one;
                // with no range it sits at the glass's middle
                var at = gauge ? level : mids[row];
                var room = w * 0.024;
                at = (at < mids[row] - digits / 2 + room) ? mids[row] - digits / 2 + room : at;
                at = (at > bottom - room) ? bottom - room : at;
                drawWaterline(dc, row, right + w * MARK_GAP, at, gauge, reading, _kinds[row], color, quiet, thin);
            }
        }
        // the date and the foot in the data colour, a little quieter: the accent is the minutes'
        var dateColor = Lib.Config.scale(data, thin ? AOD_DATE : DATE);
        var dateWidth = spaced(dc, w * AXIS + ox, h * DATE_Y + oy, _dateFont, _date, dateColor);
        if (_alarms > 0) {
            Lib.Icons.bell(dc, w * AXIS + ox + dateWidth / 2 + w * BELL_GAP, h * DATE_Y + oy, w * 0.036, dateColor);
        }
        if (!thin) {
            _targets.add([SLOTS, (w * AXIS).toNumber(), (h * DATE_Y).toNumber(), (dateWidth / 2).toNumber(), (w * 0.04).toNumber()]);
            if (_readings.size() > 2) {
                drawFoot(dc, w * AXIS, h * FOOT_Y, _readings[2], _kinds[2], dateColor);
            }
        }
    }

    // A glass's reading: a small triangle pointing at the glass from its
    // waterline (kept inside the glass's band, `at`; left out when the
    // reading has no range), then the number and its icon
    private function drawWaterline(dc as Dc, row as Number, x as Float, at as Float, gauge as Boolean,
                                   reading as Lib.Slots.Reading, kind as Number, color as Number, quiet as Number,
                                   thin as Boolean) as Void {
        var w = _w;
        var c = thin ? Lib.Config.scale(color, 0.55) : color;
        if (gauge) {
            dc.setColor(Lib.Config.scale(c, 0.7), Graphics.COLOR_TRANSPARENT);
            dc.fillPolygon([[x, at], [x + w * MARK_W, at - w * MARK_H / 2], [x + w * MARK_W, at + w * MARK_H / 2]]
                           as Array<Graphics.Point2D>);
        }
        var font = thin ? _aodValueFont : _valueFont;
        var vx = x + w * VALUE_X;
        var top = at - Graphics.getFontAscent(font) + Lib.Ink.TOP[Lib.Ink.CONDENSED_BOLD] * w * (thin ? AOD_VALUE_EM : VALUE_EM) / 2000.0;
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.drawText(vx, top, font, reading[0], Graphics.TEXT_JUSTIFY_LEFT);
        var end = vx + dc.getTextWidthInPixels(reading[0], font);
        if (!reading[1].equals("")) {
            dc.drawText(end + 1, top + Graphics.getFontAscent(font) - Graphics.getFontAscent(_unitFont), _unitFont, reading[1],
                        Graphics.TEXT_JUSTIFY_LEFT);
            end += dc.getTextWidthInPixels(reading[1], _unitFont) + 1;
        }
        var label = reading[3];
        var s = w * ICON * (thin ? 0.85 : 1.0);
        var ic = thin ? Lib.Config.scale(quiet, 0.7) : quiet;
        if (label != null) {
            dc.setColor(ic, Graphics.COLOR_TRANSPARENT);
            dc.drawText(end + w * 0.012, at, _unitFont, label, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            Lib.Icons.draw(dc, kind, end + w * 0.012 + s / 2, at, s, ic, _night, reading[4], Lib.Daily.watchBattery());
        }
        if (!thin) {
            _targets.add([row, (x + w * 0.09).toNumber(), at.toNumber(), (w * 0.09).toNumber(), (w * 0.035).toNumber()]);
        }
    }

    // The third reading in spaced capitals with its word, no icon: "SUNSET
    // 19:22", "81% BATTERY", another app's label before its value
    private function drawFoot(dc as Dc, cx as Float, y as Float, reading as Lib.Slots.Reading, kind as Number,
                              color as Number) as Void {
        var w = _w;
        var value = reading[0] + reading[1];
        var word = Lib.Slots.word(kind, reading, false);
        var text = value;
        if (kind == Lib.Slots.SUN || kind == Lib.Slots.OTHER || kind == Lib.Slots.VO2) {
            text = word.equals("") ? value : word + " " + value;
        } else if (!word.equals("")) {
            text = value + " " + word;
        }
        var width = spaced(dc, cx, y, _dateFont, text, color);
        _targets.add([2, cx.toNumber(), y.toNumber(), (width / 2 + w * 0.02).toNumber(), (w * 0.035).toNumber()]);
    }

    // The bedside clock: the outlined time alone in ember red, a bell while
    // an alarm is set
    private function drawBedside(dc as Dc, ox as Number, oy as Number) as Void {
        var w = _w;
        var h = dc.getHeight();
        var face = FACES[_style];
        var digits = Lib.Ink.height(face, _aodEm);
        var gap = h * ROW_GAP;
        var right = w * INK_RIGHT + ox;
        var mids = [h * MID - digits / 2 - gap / 2 + oy, h * MID + digits / 2 + gap / 2 + oy] as Array<Float>;
        var texts = [_hours, _minutes] as Array<String>;
        for (var row = 0; row < 2; row++) {
            var text = texts[row];
            var x = right + Lib.Ink.right(face, text, _aodEm) - dc.getTextWidthInPixels(text, _aodTimeFont);
            outline(dc, x, Lib.Ink.top(face, _aodTimeFont, mids[row], _aodEm), _aodTimeFont, text, Lib.Config.BEDSIDE, 1,
                    Graphics.COLOR_BLACK);
        }
        if (_alarms > 0) {
            Lib.Icons.bell(dc, w * AXIS + ox, h * DATE_Y + oy, w * 0.036, Lib.Config.BEDSIDE);
        }
    }

    // Text in capitals with letter spacing, centred on (cx, y); returns its width
    private function spaced(dc as Dc, cx as Float, y as Float, font as FontType, text as String, color as Number) as Float {
        var width = spacedWidth(dc, font, text);
        var x = cx - width / 2;
        var track = _w * TRACK;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var chars = text.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var ch = chars[i].toString();
            dc.drawText(x, y, font, ch, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            x += dc.getTextWidthInPixels(ch, font) + track;
        }
        return width;
    }

    private function spacedWidth(dc as Dc, font as FontType, text as String) as Float {
        var n = text.length();
        return dc.getTextWidthInPixels(text, font) + _w * TRACK * ((n > 1) ? n - 1 : 0);
    }

    // `text` as an outline `line` px wide: the text drawn round its own
    // position in the colour, then in `inside` (black, or the colour for a
    // filled glass) over the middle
    private function outline(dc as Dc, x as Float, y as Float, font as FontType, text as String, color as Number,
                             line as Number, inside as Number) as Void {
        var left = Graphics.TEXT_JUSTIFY_LEFT;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x - line, y, font, text, left);
        dc.drawText(x + line, y, font, text, left);
        dc.drawText(x, y - line, font, text, left);
        dc.drawText(x, y + line, font, text, left);
        if (line > 1) {
            var d = (line * 0.7).toNumber();
            dc.drawText(x - d, y - d, font, text, left);
            dc.drawText(x + d, y - d, font, text, left);
            dc.drawText(x - d, y + d, font, text, left);
            dc.drawText(x + d, y + d, font, text, left);
        }
        dc.setColor(inside, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text, left);
    }
}
