import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.UserProfile;
import Toybox.WatchUi;

// Overlap: the hours as landscape, the minutes as the subject. The hours
// are enormous and quiet (the data colour at under a third of its
// brightness, warmed by a little of the accent), high and left of centre
// so the bezel crops both digits; the minutes stand bright in the accent,
// low right, in front of them, the hours knocked out round them. Low
// left, the date in spaced capitals and two small readings under it.
// Nothing else. The hours always have two digits (12-hour time too):
// they are the backdrop, and a lone 9's tail would read as a minus.
//
// Everything is set in the watch face editor or the phone app's settings
// (Lib.Config): the typeface, the accent (any colour), the data colour,
// the two readings (any complication), and the bedside clock. After
// sunset the minutes and the text soften; the hours stay as they are.
//
// Standby (always-on): the same composition in thin outlines, the
// knock-out kept, the date dim, no readings, shifted each minute; about 7 % of the
// screen lit (designs/preview_overlap.py). During the watch's sleep
// hours, a bedside clock: the outlines alone in a dim ember red, and a
// bell while an alarm is set.
class OverlapView extends WatchUi.WatchFace {

    // The layout, as fractions of the screen: the same numbers as
    // designs/preview_overlap.py
    private const HOURS_DIGITS = 0.70;           // the hours' digit height
    private const HOURS_X = 0.47;                // the hours' ink centre
    private const HOURS_Y = 0.40;
    private const MINUTES_DIGITS = 0.26;
    private const MINUTES_RIGHT = 0.857;         // the minutes' ink right edge
    private const MINUTES_Y = 0.700;
    private const GAP = 0.016;                   // the hours knocked out this far above and left of the minutes' ink
    private const WINDOW = 0.458;                // and from here rightward at most, so no hour leaves a sliver
                                                 // (designs/preview_overlap.py --check)
    private const HOURS_DATA = 0.30;             // the hours: this much of the data colour
    private const HOURS_ACCENT = 0.12;           // plus this much of the accent
    private const AOD_HOURS = 0.45;              // their outline's share of the data colour, in standby
    private const AOD_MINUTES = 0.85;
    private const LEFT = 0.215;                  // the date's and the readings' left edge
    private const DATE_Y = 0.790;
    private const DATE_EM = 0.046;
    private const TRACK = 0.008;                 // the date's letter spacing
    private const BELL_X = 0.185;                // the alarm bell's centre, left of the date
    private const BELL = 0.030;
    private const READING_Y = 0.855;
    private const READING_EM = 0.040;
    private const SMALL_EM = 0.036;              // a lone reading that still doesn't fit
    private const READING_DIM = 0.70;            // the readings' share of the data colour
    private const READING_RIGHT = 0.455;         // the readings never run past this,
    private const READING_CLEAR = 0.020;         // nor closer than this to the minutes' ink
    private const ICON = 0.030;
    private const ICON_GAP = 0.012;              // from an icon to its value
    private const READING_GAP = 0.032;           // between the two readings (heart rate and steps fit with icons)
    private const EM_HEIGHT = 1.173;             // Roboto Condensed's height per em (Lib.Ink.HEIGHT)
    private const NIGHT = 0.85;                  // the colours after sunset (not the hours)

    enum Style { BIONIC, CONDENSED, RAJDHANI }
    private const FACES = [Lib.Ink.BIONIC_BOLD, Lib.Ink.CONDENSED_BOLD, Lib.Ink.BIONIC_MEDIUM] as Array<Number>;
    // How much higher the knock-out's top sits (thousandths of the width)
    // for the hours' second digit, 0 to 9, per style: a 3's or 5's lower
    // stroke would otherwise be cut into a loose dash, and a 0 into an
    // arch that reads "n" (designs/preview_overlap.py --check)
    private const RAISE = [
        [20, 0, 0, 37, 0, 30, 0, 0, 0, 0] as Array<Number>,
        [20, 0, 0, 4, 0, 6, 0, 0, 0, 0] as Array<Number>,
        [20, 0, 0, 25, 0, 18, 0, 0, 0, 0] as Array<Number>
    ] as Array<Array<Number>>;
    // The top-left corner kept clear of the hours (x then y, thousandths of
    // the width) for their first digit, 0 to 2, per style: Bionic's 2
    // leaves its top terminal cut loose by the bezel
    private const CORNER = [
        [0, 0, 0, 0, 92, 295] as Array<Number>,
        [0, 0, 0, 0, 0, 0] as Array<Number>,
        [0, 0, 0, 0, 0, 0] as Array<Number>
    ] as Array<Array<Number>>;
    private const DEFAULTS = [
        Complications.COMPLICATION_TYPE_HEART_RATE, Complications.COMPLICATION_TYPE_STEPS
    ] as Array<Complications.Type>;
    const SLOTS = 2;

    // Settings
    private var _style as Number = BIONIC;
    private var _accent as Number = 0xFFB020;
    private var _data as Number = 0xF2ECE2;
    private var _ids as Array<Complications.Id> = [] as Array<Complications.Id>;
    private var _kinds as Array<Number> = [] as Array<Number>;
    private var _bedside as Boolean = true;

    // Fonts
    private var _w as Number = 454;
    private var _hoursEm as Float = 0.0;
    private var _minutesEm as Float = 0.0;
    private var _hoursFont as FontType = Graphics.FONT_NUMBER_HOT;
    private var _minutesFont as FontType = Graphics.FONT_NUMBER_HOT;
    private var _dateFont as FontType = Graphics.FONT_XTINY;
    private var _readingFont as FontType = Graphics.FONT_XTINY;
    private var _smallFont as FontType = Graphics.FONT_XTINY;
    private var _unitFont as FontType = Graphics.FONT_XTINY;
    private var _labelFont as FontType = Graphics.FONT_XTINY;      // another app's short label (3 characters or fewer)
    private var _smallLabelFont as FontType = Graphics.FONT_XTINY;

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
        if (restyled && _hoursEm > 0) {
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

    // The reading slot (1 or 2) at (x, y), for the editor's taps, or null
    function slotAt(x as Number, y as Number) as Number? {
        for (var i = 0; i < _targets.size(); i++) {
            var t = _targets[i];
            if (t[0] < SLOTS && (x - t[1]).abs() <= t[3] && (y - t[2]).abs() <= t[4]) {
                return t[0] + 1;
            }
        }
        return null;
    }

    // The complication a press and hold at (x, y) opens: a reading's, or
    // the calendar from the date
    function targetAt(x as Number, y as Number) as Complications.Id? {
        for (var i = 0; i < _targets.size(); i++) {
            var t = _targets[i];
            if ((x - t[1]).abs() <= t[3] && (y - t[2]).abs() <= t[4]) {
                return (t[0] < SLOTS) ? _ids[t[0]] : new Complications.Id(Complications.COMPLICATION_TYPE_CALENDAR_EVENTS);
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
        _hoursEm = Lib.Ink.em(face, _w * HOURS_DIGITS);
        _minutesEm = Lib.Ink.em(face, _w * MINUTES_DIGITS);
        _hoursFont = Lib.Ink.font(face, _hoursEm, Graphics.FONT_NUMBER_HOT);
        _minutesFont = Lib.Ink.font(face, _minutesEm, Graphics.FONT_NUMBER_HOT);
        _dateFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (_w * DATE_EM * EM_HEIGHT).toNumber(), Graphics.FONT_XTINY);
        _readingFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (_w * READING_EM * EM_HEIGHT).toNumber(), Graphics.FONT_XTINY);
        _smallFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (_w * SMALL_EM * EM_HEIGHT).toNumber(), Graphics.FONT_XTINY);
        _unitFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (_w * READING_EM * 0.62 * EM_HEIGHT).toNumber(), Graphics.FONT_XTINY);
        _labelFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (_w * READING_EM * 0.75 * EM_HEIGHT).toNumber(), Graphics.FONT_XTINY);
        _smallLabelFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (_w * SMALL_EM * 0.75 * EM_HEIGHT).toNumber(),
                                             Graphics.FONT_XTINY);
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
        _hours = hour.format("%02d");      // two digits always: the hours are the backdrop
        _minutes = clock.min.format("%02d");
        var info = Time.Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
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
        _date = "SAT 31";
        _alarms = 0;
        _night = false;
        var samples = {
            Lib.Slots.HEART => ["72", "", 0.32, null, false], Lib.Slots.STEPS => ["8412", "", 0.84, null, false],
            Lib.Slots.BATTERY => ["81", "%", 0.81, null, false], Lib.Slots.BODY => ["64", "", 0.64, null, false],
            Lib.Slots.STRESS => ["28", "", 0.28, null, false], Lib.Slots.TEMPERATURE => ["46°", "", 0.55, null, false],
            Lib.Slots.OTHER => ["112", "", 0.45, "GLU", false]
        } as Dictionary<Number, Lib.Slots.Reading>;
        var readings = [] as Array<Lib.Slots.Reading>;
        for (var n = 0; n < _kinds.size(); n++) {
            var r = samples[_kinds[n]];
            readings.add((r != null) ? r : ["--", "", null, null, false] as Lib.Slots.Reading);
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
            draw(dc, off[0], off[1], true);
        } else {
            draw(dc, 0, 0, false);
        }
    }

    // Awake (thin false) or standby and the bedside clock (thin true),
    // shifted by (ox, oy)
    private function draw(dc as Dc, ox as Number, oy as Number, thin as Boolean) as Void {
        var w = _w;
        var h = dc.getHeight();
        var face = FACES[_style];
        var dim = _night ? NIGHT : 1.0;
        var bedside = thin && _asleep;
        var hoursColor = mix(_data, thin ? AOD_HOURS : HOURS_DATA, _accent, HOURS_ACCENT);
        var minutesColor = Lib.Config.scale(_accent, (thin ? AOD_MINUTES : 1.0) * dim);
        if (bedside) {
            hoursColor = Lib.Config.scale(Lib.Config.BEDSIDE, 0.85);
            minutesColor = Lib.Config.BEDSIDE;
        }

        // Where the minutes' ink sits
        var mw = dc.getTextWidthInPixels(_minutes, _minutesFont);
        var ml = Lib.Ink.left(face, _minutes, _minutesEm);
        var mr = Lib.Ink.right(face, _minutes, _minutesEm);
        var mx = w * MINUTES_RIGHT + ox + mr - mw;
        var my = Lib.Ink.top(face, _minutesFont, h * MINUTES_Y + oy, _minutesEm);
        var inkLeft = mx + ml;
        var inkTop = h * MINUTES_Y + oy - Lib.Ink.height(face, _minutesEm) / 2;

        // The hours, centred on their ink, knocked out round the minutes:
        // drawn only above the minutes and left of them, a gap away
        var hw = dc.getTextWidthInPixels(_hours, _hoursFont);
        var hl = Lib.Ink.left(face, _hours, _hoursEm);
        var hr = Lib.Ink.right(face, _hours, _hoursEm);
        var hx = w * HOURS_X + ox - (hw - hl - hr) / 2 - hl;
        var hy = Lib.Ink.top(face, _hoursFont, h * HOURS_Y + oy, _hoursEm);
        var second = Lib.Ink.digit(_hours, 1);
        var clipY = (inkTop - w * GAP - ((second != null) ? RAISE[_style][second] * w / 1000.0 : 0.0)).toNumber();
        var clipX = ((inkLeft - w * GAP < w * WINDOW + ox) ? inkLeft - w * GAP : w * WINDOW + ox).toNumber();
        // less a corner where the bezel would cut a piece loose
        var first = Lib.Ink.digit(_hours, 0);
        var cornerX = (first != null && first <= 2) ? (CORNER[_style][first * 2] * w / 1000.0).toNumber() : 0;
        var cornerY = (first != null && first <= 2) ? (CORNER[_style][first * 2 + 1] * w / 1000.0).toNumber() : 0;
        for (var pass = 0; pass < 3; pass++) {
            if (pass == 0) {
                if (cornerY <= 0) {
                    continue;
                }
                dc.setClip(cornerX, 0, w - cornerX, (cornerY < clipY) ? cornerY : clipY);
            } else if (pass == 1) {
                if (cornerY >= clipY) {
                    continue;
                }
                dc.setClip(0, cornerY, w, clipY - cornerY);
            } else {
                dc.setClip(0, clipY, clipX, h - clipY);
            }
            if (thin) {
                outline(dc, hx, hy, _hoursFont, _hours, hoursColor, 1);
            } else {
                dc.setColor(hoursColor, Graphics.COLOR_TRANSPARENT);
                dc.drawText(hx, hy, _hoursFont, _hours, Graphics.TEXT_JUSTIFY_LEFT);
            }
        }
        dc.clearClip();

        // The minutes in front
        if (thin) {
            outline(dc, mx, my, _minutesFont, _minutes, minutesColor, 1);
        } else {
            dc.setColor(minutesColor, Graphics.COLOR_TRANSPARENT);
            dc.drawText(mx, my, _minutesFont, _minutes, Graphics.TEXT_JUSTIFY_LEFT);
        }

        // The date, the alarm bell left of it, and the readings, low left
        var dateColor = Lib.Config.scale(_accent, (thin ? 0.6 : 1.0) * dim);
        var dateWidth = 0.0;
        if (!bedside) {
            dateWidth = spaced(dc, w * LEFT + ox, h * DATE_Y + oy, _dateFont, _date, dateColor);
        }
        if (_alarms > 0 && bedside) {
            // no date: the bell just outside the minutes' top-left corner
            Lib.Icons.bell(dc, inkLeft - w * BELL * 0.75, inkTop - w * BELL * 0.75, w * BELL, Lib.Config.BEDSIDE);
        } else if (_alarms > 0) {
            Lib.Icons.bell(dc, w * BELL_X + ox, h * DATE_Y + oy, w * BELL, Lib.Config.scale(dateColor, 0.7));
        }
        if (thin) {
            return;
        }
        _targets.add([SLOTS, (w * LEFT + dateWidth / 2).toNumber(), (h * DATE_Y).toNumber(),
                      (dateWidth / 2 + w * 0.02).toNumber(), (w * 0.035).toNumber()]);
        var cap = (inkLeft - w * READING_CLEAR < w * READING_RIGHT) ? inkLeft - w * READING_CLEAR : w * READING_RIGHT;
        drawReadings(dc, w * LEFT, h * READING_Y, cap, dim);
    }

    // The readings in a row from x, never past `cap` (READING_RIGHT, or
    // nearer the minutes when they are wide): without units if they don't fit, then the first alone,
    // then in a smaller font. Never without their icons (or another app's
    // label): they are a reading's only cue.
    private function drawReadings(dc as Dc, x as Float, y as Float, cap as Float, dim as Float) as Void {
        var w = _w;
        var room = cap - x;
        var count = (_readings.size() < SLOTS) ? _readings.size() : SLOTS;
        var units = true;
        var small = false;
        for (var fit = 0; fit < 4; fit++) {
            units = fit == 0;
            count = (fit < 2) ? count : 1;
            small = fit == 3;
            var font = small ? _smallFont : _readingFont;
            var total = 0.0;
            for (var n = 0; n < count; n++) {
                total += readingWidth(dc, _readings[n], units, font, small) + ((n > 0) ? w * READING_GAP : 0);
            }
            if (total <= room) {
                break;
            }
        }
        for (var n = 0; n < count; n++) {
            var end = drawReading(dc, x, y, _readings[n], _kinds[n], dim, units, small);
            _targets.add([n, ((x + end) / 2).toNumber(), y.toNumber(), ((end - x) / 2 + w * 0.015).toNumber(),
                          (w * 0.035).toNumber()]);
            x = end + w * READING_GAP;
        }
    }

    private function readingWidth(dc as Dc, reading as Lib.Slots.Reading, units as Boolean, font as FontType,
                                  small as Boolean) as Float {
        var w = _w;
        var width = dc.getTextWidthInPixels(reading[0], font).toFloat();
        if (units && !reading[1].equals("")) {
            width += dc.getTextWidthInPixels(reading[1], _unitFont) + 1;
        }
        var label = reading[3];
        return width + ((label != null) ? dc.getTextWidthInPixels(label, labelFont(label, small)) : w * ICON) + w * ICON_GAP;
    }

    // Another app's label: three characters or fewer at 0.75 of the value's
    // em, longer ones at the unit's size
    private function labelFont(label as String, small as Boolean) as FontType {
        if (label.length() > 3) {
            return _unitFont;
        }
        return small ? _smallLabelFont : _labelFont;
    }

    // A reading: its icon (or its app's label) then its value, from x;
    // returns where it ends
    private function drawReading(dc as Dc, x as Float, y as Float, reading as Lib.Slots.Reading, kind as Number,
                                 dim as Float, units as Boolean, small as Boolean) as Float {
        var w = _w;
        var s = w * ICON;
        var label = reading[3];
        var quiet = Lib.Config.scale(_data, Lib.Config.QUIET * dim);
        var vx = x;
        if (label != null) {
            dc.setColor(quiet, Graphics.COLOR_TRANSPARENT);
            var lf = labelFont(label, small);
            dc.drawText(x, y, lf, label, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            vx += dc.getTextWidthInPixels(label, lf) + w * ICON_GAP;
        } else {
            Lib.Icons.draw(dc, kind, x + s / 2, y, s, quiet, _night, reading[4], Lib.Daily.watchBattery());
            vx += s + w * ICON_GAP;
        }
        // the value's digits centred on y
        var font = small ? _smallFont : _readingFont;
        var em = small ? SMALL_EM : READING_EM;
        var top = y - Graphics.getFontAscent(font) + Lib.Ink.TOP[Lib.Ink.CONDENSED_BOLD] * w * em / 2000.0;
        dc.setColor(Lib.Config.scale(_data, READING_DIM * dim), Graphics.COLOR_TRANSPARENT);
        dc.drawText(vx, top, font, reading[0], Graphics.TEXT_JUSTIFY_LEFT);
        var end = vx + dc.getTextWidthInPixels(reading[0], font);
        if (units && !reading[1].equals("")) {
            dc.drawText(end + 1, top + Graphics.getFontAscent(font) - Graphics.getFontAscent(_unitFont), _unitFont,
                        reading[1], Graphics.TEXT_JUSTIFY_LEFT);
            end += dc.getTextWidthInPixels(reading[1], _unitFont) + 1;
        }
        return end;
    }

    // a × fa + b × fb, channel by channel, capped at 255
    private function mix(a as Number, fa as Float, b as Number, fb as Float) as Number {
        var out = 0;
        for (var shift = 16; shift >= 0; shift -= 8) {
            var c = (((a >> shift) & 0xFF) * fa + ((b >> shift) & 0xFF) * fb).toNumber();
            out = out | (((c > 255) ? 255 : c) << shift);
        }
        return out;
    }

    // Text in capitals with letter spacing from (x, y), y its middle; returns its width
    private function spaced(dc as Dc, x as Float, y as Float, font as FontType, text as String, color as Number) as Float {
        var track = _w * TRACK;
        var start = x;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        var chars = text.toCharArray();
        for (var i = 0; i < chars.size(); i++) {
            var ch = chars[i].toString();
            dc.drawText(x, y, font, ch, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            x += dc.getTextWidthInPixels(ch, font) + ((i < chars.size() - 1) ? track : 0);
        }
        return x - start;
    }

    // `text` as an outline `line` px wide: the text drawn round its own
    // position in the colour, then in black over the middle
    private function outline(dc as Dc, x as Float, y as Float, font as FontType, text as String, color as Number,
                             line as Number) as Void {
        var left = Graphics.TEXT_JUSTIFY_LEFT;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x - line, y, font, text, left);
        dc.drawText(x + line, y, font, text, left);
        dc.drawText(x, y - line, font, text, left);
        dc.drawText(x, y + line, font, text, left);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text, left);
    }
}
