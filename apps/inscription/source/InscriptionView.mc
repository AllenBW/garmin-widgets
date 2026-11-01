import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.UserProfile;
import Toybox.WatchUi;

// Inscription: a coin. The time struck large in the middle, the hours (in
// the data colour) over the minutes (in the accent), and round the rim, in
// small spaced capitals like a coin's legend, the date across the top in
// the accent and the five readings in the data colour, softened: one at
// nine o'clock, one at three, three along the bottom reading left to
// right, each its value and the word that names it ("72 BPM", "8412
// STEPS"), the value brighter than its word. A beaded rim sets the field
// off from the legend. No icons, no gauges. With the Pridi typeface the
// legend is set in Pridi too.
//
// Everything is set in the watch face editor or the phone app's settings
// (Lib.Config): the typeface, the accent (any colour), the data colour,
// the five readings (any complication), and the bedside clock. After
// sunset the colours soften.
//
// Standby (always-on): the time outlined, the date and the bottom legend
// dim, shifted each minute (designs/preview_inscription.py). During the
// watch's sleep hours, a bedside clock: the outlined time alone in a dim
// ember red, and a bell while an alarm is set.
class InscriptionView extends WatchUi.WatchFace {

    // A run of legend text: [text, colour, letter spacing, gap before it,
    // the gap a space inside it makes (0 for the font's own)] (px)
    typedef Run as [String, Number, Float, Float, Float];

    // The layout, as fractions of the screen: the same numbers as
    // designs/preview_inscription.py
    private const DIGITS = 0.250;                // each row's digit height
    private const AOD_DIGITS = 0.235;
    private const ROW_GAP = 0.035;               // between the hours' and the minutes' ink
    private const LEGEND_EM = 0.038;
    private const RADIUS = 0.425;                // the legend's middle, from the centre
    private const VALUE_TRACK = 0.008;           // letter spacing in a value
    private const WORD_TRACK = 0.010;            // in a word and the date
    private const TIGHT_TRACK = 0.006;           // in a word, when the legend would not fit
    private const WORD_GAP = 0.012;              // between a value and its word
    private const WORD_SPACE = 0.013;            // between the words of a name ("BODY BATT")
    private const SEPARATOR_GAP = 0.024;         // either side of the dot between bottom readings
    private const TIGHT_GAP = 0.0145;            // and when the bottom would not fit
    private const BEADS = 72;                    // the beaded rim: a dot every 5°
    private const BEAD_RADIUS = 0.372;
    private const BEAD_SIZE = 0.9;               // px, on the 454 px screen
    private const BEAD = 0.30;                   // the beads' share of the data colour
    private const VALUE = 0.85;                  // the values' share of the data colour
    private const WORD = 0.60;                   // the words'
    private const AOD_VALUE = 0.50;
    private const AOD_WORD = 0.36;
    private const AOD_DATE = 0.6;
    private const BELL_Y = 0.165;                // the alarm bell, at twelve inside the beads
    private const BELL = 0.026;
    private const NIGHT = 0.85;                  // the colours after sunset
    // The arcs the legend may fill, in degrees, so its items never run into
    // each other: the date 100° round twelve (else its short form), each
    // side 32° round three or nine o'clock, the bottom 112° round six. Too
    // long, the words and dots close up first; then, longest item first,
    // a long word gives way to its short one and a short one to none. The
    // sides start at the short word.
    private const DATE_SPAN = 100.0;
    private const SIDE_SPAN = 32.0;
    private const BOTTOM_SPAN = 112.0;
    enum Level { LONG, SHORT, BARE }

    enum Style { PRIDI, BIONIC, CONDENSED, RAJDHANI }
    private const FACES = [Lib.Ink.PRIDI, Lib.Ink.BIONIC_BOLD, Lib.Ink.CONDENSED_BOLD, Lib.Ink.BIONIC_MEDIUM] as Array<Number>;
    private const DEFAULTS = [
        Complications.COMPLICATION_TYPE_CURRENT_TEMPERATURE, Complications.COMPLICATION_TYPE_BATTERY,
        Complications.COMPLICATION_TYPE_HEART_RATE, Complications.COMPLICATION_TYPE_STEPS,
        Complications.COMPLICATION_TYPE_BODY_BATTERY
    ] as Array<Complications.Type>;
    const SLOTS = 5;

    // Settings
    private var _style as Number = PRIDI;
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
    private var _legendFont as FontType = Graphics.FONT_XTINY;

    private var _awake as Boolean = true;
    private var _burnIn as Boolean = false;

    // The once-a-minute state
    private var _minute as Number = -1;
    private var _hours as String = "";
    private var _minutes as String = "";
    private var _date as String = "";
    private var _shortDate as String = "";
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

    // The reading slot (1 to 5) at (x, y), for the editor's taps, or null
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
        makeFonts();
    }

    private function makeFonts() as Void {
        var face = FACES[_style];
        _em = Lib.Ink.em(face, _w * DIGITS);
        _aodEm = Lib.Ink.em(face, _w * AOD_DIGITS);
        _timeFont = Lib.Ink.font(face, _em, Graphics.FONT_NUMBER_HOT);
        _aodTimeFont = Lib.Ink.font(face, _aodEm, Graphics.FONT_NUMBER_MEDIUM);
        _legendFont = Lib.Ink.font((_style == PRIDI) ? Lib.Ink.PRIDI : Lib.Ink.CONDENSED_REGULAR, _w * LEGEND_EM, Graphics.FONT_XTINY);
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
        _date = (info.day_of_week + " · " + info.day + " " + info.month).toUpper();
        info = Time.Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        _shortDate = (info.day_of_week + " · " + info.day + " " + info.month).toUpper();
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
        _date = "SATURDAY · 31 OCTOBER";
        _shortDate = "SAT · 31 OCT";
        _alarms = 1;
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
        var cx = w / 2.0 + ox;
        var cy = h / 2.0 + oy;
        var r = w * RADIUS;
        var dim = _night ? NIGHT : 1.0;
        var data = Lib.Config.scale(_data, dim);
        var accent = Lib.Config.scale(_accent, dim);
        if (!thin) {
            drawBeads(dc, cx, cy, Lib.Config.scale(data, BEAD));
        }
        drawTime(dc, cx, cy, thin, thin ? Lib.Config.scale(data, 0.8) : data, thin ? Lib.Config.scale(accent, 0.8) : accent);

        // The date across the top (its short form if the long one is too
        // long), the alarm bell inside the beads at twelve
        var dateColor = thin ? Lib.Config.scale(accent, AOD_DATE) : accent;
        var date = [[_date, dateColor, w * WORD_TRACK, 0.0, 0.0]] as Array<Run>;
        if (runsLength(dc, date) > Math.toRadians(DATE_SPAN) * r) {
            date = [[_shortDate, dateColor, w * WORD_TRACK, 0.0, 0.0]] as Array<Run>;
        }
        var length = legend(dc, cx, cy, date, 0.0, false);
        if (_alarms > 0) {
            Lib.Icons.bell(dc, cx, h * BELL_Y + oy, w * BELL, Lib.Config.scale(accent, 0.7));
        }
        if (!thin) {
            target(SLOTS, cx, cy, 0.0, length);
        }

        // The readings: one at nine o'clock, one at three, three along the bottom
        var value = Lib.Config.scale(data, thin ? AOD_VALUE : VALUE);
        var word = Lib.Config.scale(data, thin ? AOD_WORD : WORD);
        if (!thin) {
            var side = (Math.toRadians(SIDE_SPAN) * r).toFloat();
            var angles = [270.0, 90.0] as Array<Float>;
            for (var n = 0; n < 2 && n < _readings.size(); n++) {
                var runs = item(n, SHORT, false, value, word);
                if (runsLength(dc, runs) > side) {
                    runs = item(n, SHORT, true, value, word);
                }
                if (runsLength(dc, runs) > side) {
                    runs = item(n, BARE, true, value, word);
                }
                target(n, cx, cy, angles[n], legend(dc, cx, cy, runs, angles[n], false));
            }
        }
        // Along the bottom: closed up, then the longest item steps down
        // first, until the three fit
        var levels = [LONG, LONG, LONG] as Array<Number>;
        var tight = false;
        var items = bottomItems(dc, levels, tight, value, word);
        var room = Math.toRadians(BOTTOM_SPAN) * r;
        if (bottomLength(dc, items, tight) > room) {
            tight = true;
            items = bottomItems(dc, levels, tight, value, word);
        }
        while (bottomLength(dc, items, tight) > room) {
            var longest = -1;
            var most = 0.0;
            for (var k = 0; k < items.size(); k++) {
                var size = runsLength(dc, items[k]);
                if (levels[k] < BARE && size > most) {
                    longest = k;
                    most = size;
                }
            }
            if (longest < 0) {
                break;
            }
            levels[longest] += 1;
            items = bottomItems(dc, levels, tight, value, word);
        }
        var runs = [] as Array<Run>;
        var gap = w * (tight ? TIGHT_GAP : SEPARATOR_GAP);
        for (var k = 0; k < items.size(); k++) {
            var first = items[k][0];
            if (k > 0) {
                runs.add(["·", word, 0.0, gap, 0.0]);
                runs.add([first[0], first[1], first[2], gap, first[4]]);
            } else {
                runs.add(first);
            }
            for (var i = 1; i < items[k].size(); i++) {
                runs.add(items[k][i]);
            }
        }
        var total = legend(dc, cx, cy, runs, 180.0, true);
        if (!thin) {
            // each bottom reading's press target, where it falls along the rim
            var dot = dc.getTextWidthInPixels("·", _legendFont) + 2 * gap;
            var start = 0.0;
            for (var k = 0; k < items.size(); k++) {
                var size = runsLength(dc, items[k]);
                var middle = start + size / 2 - total / 2;
                target(k + 2, cx, cy, (180.0 - Math.toDegrees(middle / r)).toFloat(), size);
                start += size + dot;
            }
        }
    }

    // The beaded rim: a dot every 5°
    private function drawBeads(dc as Dc, cx as Float, cy as Float, color as Number) as Void {
        var r = _w * BEAD_RADIUS;
        var size = BEAD_SIZE * _w / 454.0;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < BEADS; i++) {
            var a = Math.PI * 2 * i / BEADS;
            dc.fillCircle(cx + r * Math.sin(a), cy - r * Math.cos(a), size);
        }
    }

    // The time, centred on its ink: the hours over the minutes, solid awake
    // and outlined in standby
    private function drawTime(dc as Dc, cx as Float, cy as Float, thin as Boolean, hourColor as Number, minuteColor as Number) as Void {
        var face = FACES[_style];
        var em = thin ? _aodEm : _em;
        var font = thin ? _aodTimeFont : _timeFont;
        var digits = Lib.Ink.height(face, em);
        var gap = dc.getHeight() * ROW_GAP;
        var texts = [_hours, _minutes] as Array<String>;
        var colors = [hourColor, minuteColor] as Array<Number>;
        for (var row = 0; row < 2; row++) {
            var text = texts[row];
            var mid = (row == 0) ? cy - digits / 2 - gap / 2 : cy + digits / 2 + gap / 2;
            var width = dc.getTextWidthInPixels(text, font);
            var left = Lib.Ink.left(face, text, em);
            var ink = width - left - Lib.Ink.right(face, text, em);
            var x = cx - ink / 2 - left;
            var y = Lib.Ink.top(face, font, mid, em);
            if (thin) {
                outline(dc, x, y, font, text, colors[row]);
            } else {
                dc.setColor(colors[row], Graphics.COLOR_TRANSPARENT);
                dc.drawText(x, y, font, text, Graphics.TEXT_JUSTIFY_LEFT);
            }
        }
    }

    // The bedside clock: the outlined time alone in ember red, a bell at
    // twelve while an alarm is set
    private function drawBedside(dc as Dc, ox as Number, oy as Number) as Void {
        var w = _w;
        var h = dc.getHeight();
        drawTime(dc, w / 2.0 + ox, h / 2.0 + oy, true, Lib.Config.BEDSIDE, Lib.Config.BEDSIDE);
        if (_alarms > 0) {
            Lib.Icons.bell(dc, w / 2.0 + ox, h * BELL_Y + oy, w * BELL, Lib.Config.BEDSIDE);
        }
    }

    // A reading as it is inscribed, as runs: its value, its unit set tight
    // against it, and (by `level`) the word that names it, closed up when
    // `tight`
    private function item(n as Number, level as Number, tight as Boolean, value as Number, word as Number) as Array<Run> {
        var r = _readings[n];
        var text = r[0].toUpper();
        var unit = r[1].toUpper();
        var last = (text.length() > 1) ? text.substring(text.length() - 1, text.length()) : null;
        if (unit.equals("") && last != null && last.equals("°")) {
            unit = "°";
            text = text.substring(0, text.length() - 1) as String;
        }
        var runs = [[text, value, _w * VALUE_TRACK, 0.0, 0.0]] as Array<Run>;
        if (!unit.equals("")) {
            runs.add([unit, value, _w * VALUE_TRACK, 0.0, 0.0]);
        }
        if (level < BARE) {
            var name = Lib.Slots.word(_kinds[n], r, level != LONG).toUpper();
            if (!name.equals("")) {
                runs.add([name, word, _w * (tight ? TIGHT_TRACK : WORD_TRACK), _w * WORD_GAP, _w * WORD_SPACE]);
            }
        }
        return runs;
    }

    // The bottom three readings, left to right, each at its level
    private function bottomItems(dc as Dc, levels as Array<Number>, tight as Boolean, value as Number, word as Number) as Array<Array<Run>> {
        var items = [] as Array<Array<Run>>;
        for (var n = 2; n < _readings.size(); n++) {
            items.add(item(n, levels[n - 2], tight, value, word));
        }
        return items;
    }

    // Their length along the rim, with the dots between them
    private function bottomLength(dc as Dc, items as Array<Array<Run>>, tight as Boolean) as Float {
        var total = 0.0;
        for (var k = 0; k < items.size(); k++) {
            total += runsLength(dc, items[k]);
        }
        if (items.size() > 1) {
            total += (items.size() - 1) * (dc.getTextWidthInPixels("·", _legendFont) + 2 * _w * (tight ? TIGHT_GAP : SEPARATOR_GAP));
        }
        return total;
    }

    // A character's width in a run; a space set to make the run's own gap
    // between its neighbours, letter spacing included
    private function width(dc as Dc, ch as String, run as Run) as Float {
        if (run[4] > 0.0 && ch.equals(" ")) {
            return run[4] - 2 * run[2];
        }
        return dc.getTextWidthInPixels(ch, _legendFont).toFloat();
    }

    // The length along the rim of runs as legend() sets them
    private function runsLength(dc as Dc, runs as Array<Run>) as Float {
        var total = 0.0;
        for (var i = 0; i < runs.size(); i++) {
            var run = runs[i];
            var chars = run[0].toCharArray();
            total += (i > 0) ? run[3] : 0.0;
            for (var j = 0; j < chars.size(); j++) {
                total += width(dc, chars[j].toString(), run);
            }
            total += (chars.size() > 1) ? run[2] * (chars.size() - 1) : 0.0;
        }
        return total;
    }

    // Runs of text round the rim, centred on `angle` (degrees clockwise
    // from twelve o'clock, as on a dial). Along the top and sides they read
    // clockwise with their tops outward; along the bottom (bottom true) left
    // to right with their tops toward the centre. Drawn a character at a
    // time, since drawRadialText has no letter spacing. Returns the length
    // along the rim, in px.
    private function legend(dc as Dc, cx as Float, cy as Float, runs as Array<Run>, angle as Float, bottom as Boolean) as Float {
        var font = _legendFont;
        var r = _w * RADIUS;
        var total = runsLength(dc, runs);
        var sign = bottom ? -1.0 : 1.0;
        var radial = (dc has :drawRadialText) && (font instanceof Graphics.VectorFont);
        var justify = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var pos = -total / 2;
        for (var i = 0; i < runs.size(); i++) {
            var run = runs[i];
            var chars = run[0].toCharArray();
            pos += (i > 0) ? run[3] : 0.0;
            dc.setColor(run[1], Graphics.COLOR_TRANSPARENT);
            for (var j = 0; j < chars.size(); j++) {
                var ch = chars[j].toString();
                var cw = width(dc, ch, run);
                var a = angle + sign * Math.toDegrees((pos + cw / 2.0) / r);
                pos += cw + ((j < chars.size() - 1) ? run[2] : 0.0);
                if (ch.equals(" ")) {
                    continue;
                }
                if (radial) {
                    // From the character's start, left-justified: centring
                    // uses drawRadialText's own glyph widths, narrower than
                    // getTextWidthInPixels'. And it draws at whole degrees
                    // only (3.4 px apart on the 454 px rim), so draw at the
                    // nearest whole degree round a centre moved by the
                    // difference.
                    var start = 90 - (a - sign * Math.toDegrees(cw / 2.0 / r));
                    var exact = Math.toRadians(start);
                    var whole = Math.round(start);
                    var q = Math.toRadians(whole);
                    dc.drawRadialText(cx + r * (Math.cos(exact) - Math.cos(q)), cy - r * (Math.sin(exact) - Math.sin(q)),
                                      font as Graphics.VectorFont, ch, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER,
                                      whole.toNumber(), r,
                                      bottom ? Graphics.RADIAL_TEXT_DIRECTION_COUNTER_CLOCKWISE : Graphics.RADIAL_TEXT_DIRECTION_CLOCKWISE);
                } else {
                    var rad = Math.toRadians(a);
                    dc.drawText(cx + r * Math.sin(rad), cy - r * Math.cos(rad), font, ch, justify);
                }
            }
        }
        return total;
    }

    // A press target round a legend item `length` px long centred on
    // `angle`: the box round its ends and middle, padded
    private function target(slot as Number, cx as Float, cy as Float, angle as Float, length as Float) as Void {
        var r = _w * RADIUS;
        var half = Math.toDegrees(length / 2 / r);
        var x0 = 9999.0;
        var y0 = 9999.0;
        var x1 = -9999.0;
        var y1 = -9999.0;
        var angles = [angle - half, angle, angle + half] as Array<Float>;
        for (var i = 0; i < angles.size(); i++) {
            var rad = Math.toRadians(angles[i]);
            var x = cx + r * Math.sin(rad);
            var y = cy - r * Math.cos(rad);
            x0 = (x < x0) ? x : x0;
            x1 = (x > x1) ? x : x1;
            y0 = (y < y0) ? y : y0;
            y1 = (y > y1) ? y : y1;
        }
        var pad = _w * 0.035;
        _targets.add([slot, ((x0 + x1) / 2).toNumber(), ((y0 + y1) / 2).toNumber(), ((x1 - x0) / 2 + pad).toNumber(),
                      ((y1 - y0) / 2 + pad).toNumber()]);
    }

    // `text` as a 1 px outline: the text drawn round its own position in
    // the colour, then in black over the middle
    private function outline(dc as Dc, x as Float, y as Float, font as FontType, text as String, color as Number) as Void {
        var left = Graphics.TEXT_JUSTIFY_LEFT;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x - 1, y, font, text, left);
        dc.drawText(x + 1, y, font, text, left);
        dc.drawText(x, y - 1, font, text, left);
        dc.drawText(x, y + 1, font, text, left);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text, left);
    }
}
