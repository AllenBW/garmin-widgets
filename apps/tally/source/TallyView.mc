import Toybox.Application;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Timer;
import Toybox.WatchUi;

enum TallyPage {
    PAGE_LOG,       // the buttons in a ring round the last entry
    PAGE_RINGS,     // a day per ring, each entry a dot at its time
    PAGE_STRIP,     // a day per row, with what came before
    PAGE_BEFORE     // which names tend to come before the picked one
}

// The app: four pages, up and down between them. The first is the
// buttons shown at this hour, as wedges round a centre holding the last
// entry; a tap logs one, and for UNDO seconds a tap on the centre takes it
// back. A tap on the centre otherwise (or START) opens every button.
class TallyView extends WatchUi.View {

    const DAYS = 14;
    const UNDO = 6;                 // seconds

    // the log page, as fractions of the width
    const R_OUT = 0.480;
    const R_IN = 0.250;
    const GAP = 3;                  // degrees between wedges
    const WEDGE_DIM = 0.22;         // a wedge's fill against its name's colour

    // the rings page
    const RING_IN = 0.240;
    const RING_OUT = 0.355;
    const DIAL = 0.366;
    const DIAL_LABEL = 0.428;

    // the strip page
    const STRIP_X0 = 0.15;
    const STRIP_X1 = 0.85;
    const STRIP_Y0 = 0.30;
    const STRIP_Y1 = 0.65;
    const STRIP_HOURS = 9;

    const WHITE = 0xF2ECE2;
    const GRAY = 0x8A8A8A;
    const FAINT = 0x262626;

    var page as Number = PAGE_LOG;

    private var _buttons as Array<TallyButton> = [] as Array<TallyButton>;
    private var _shown as Array<TallyButton> = [] as Array<TallyButton>;
    private var _days as TallyDays?;
    const PICKED = "picked";                    // the name the pattern pages show (stored)
    private var _undoUntil as Number = 0;
    private var _timer as Timer.Timer?;
    private var _flash as Number = -1;          // the wedge just tapped
    private var _sender as TallySender?;

    private var _w as Number = 454;
    private var _cx as Number = 227;
    private var _names as Array<FontType> = [] as Array<FontType>;
    private var _big as FontType = Graphics.FONT_MEDIUM;
    private var _mid as FontType = Graphics.FONT_SMALL;
    private var _small as FontType = Graphics.FONT_XTINY;
    private var _tiny as FontType = Graphics.FONT_XTINY;

    function initialize() {
        View.initialize();
        TallySample.load();
        page = TallySample.page();
        reload();
    }

    function onLayout(dc as Dc) as Void {
        _w = dc.getWidth();
        _cx = _w / 2;
        // The smallest is the watch's own smallest (FONT_XTINY, 37 px tall
        // on the 454 px screens); the first builds' 22 px was unreadable
        // on the wrist. Condensed, so the words still fit.
        _names = [font("RobotoCondensedBold", 0.090), font("RobotoCondensedBold", 0.078),
                  font("RobotoCondensedBold", 0.068), font("RobotoCondensedBold", 0.060)] as Array<FontType>;
        _big = font("RobotoCondensedBold", 0.130);
        _mid = font("RobotoCondensedBold", 0.090);
        _small = font("RobotoCondensedBold", 0.078);
        _tiny = font("RobotoCondensedRegular", 0.068);
    }

    // A font whose capitals' em is `em` of the width (a vector font's size
    // is its full height, about 1.17 em)
    private function font(face as String, em as Float) as FontType {
        return Lib.Fmt.vectorFont(face, (_w * em * 1.17).toNumber(), Graphics.FONT_SMALL);
    }

    function onShow() as Void {
        reload();
        sync();
    }

    function onHide() as Void {
        stopTimer();
    }

    // The buttons and the log, read again (settings changed, a tap, a page)
    function reload() as Void {
        _buttons = TallyButtons.all();
        var now = Time.now().value();
        _days = new TallyDays(DAYS, now);
        var hour = Lib.Fmt.localSeconds(now) / 3600;
        _shown = TallyButtons.onScreen(_buttons, hour, usualCounts(hour));
        writeLast();
    }

    // Per button, how often it was logged within an hour of this hour
    private function usualCounts(hour as Number) as Array<Number> {
        var d = _days as TallyDays;
        var out = [] as Array<Number>;
        for (var b = 0; b < _buttons.size(); b++) {
            var secs = d.of(_buttons[b].name)[1];
            var n = 0;
            for (var i = 0; i < secs.size(); i++) {
                var off = (secs[i] / 3600 - hour + 24) % 24;
                if (off <= 1 || off == 23) {
                    n++;
                }
            }
            out.add(n);
        }
        return out;
    }

    function buttons() as Array<TallyButton> {
        return _buttons;
    }

    function days() as TallyDays {
        return _days as TallyDays;
    }

    // ---------------------------------------------------------------- logging

    function log(name as String) as Void {
        TallyLog.add(Time.now().value(), name);
        reload();
        _undoUntil = Time.now().value() + UNDO;
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(60, 70)] as Array<Attention.VibeProfile>);
        }
        startTimer();
        TallySender.schedule();
        WatchUi.requestUpdate();
    }

    function undoing() as Boolean {
        return Time.now().value() < _undoUntil;
    }

    function undo() as Void {
        _undoUntil = 0;
        _flash = -1;
        if (TallyLog.undo()) {
            reload();
            if (Attention has :vibrate) {
                Attention.vibrate([new Attention.VibeProfile(40, 40), new Attention.VibeProfile(0, 60),
                                   new Attention.VibeProfile(40, 40)] as Array<Attention.VibeProfile>);
            }
        }
        TallySender.schedule();
        WatchUi.requestUpdate();
    }

    // The glance's line: the newest entry of the button the phone's
    // "Glance shows" names (else of anything), its colour, its days in a row
    private function writeLast() as Void {
        var d = _days as TallyDays;
        var name = null;
        var slot = TallyButtons.number(Properties.getValue("GlanceButton"), 0);
        if (slot > 0) {
            var b = TallyButtons.parse({"name" => Properties.getValue("B" + slot + "Name")});
            if (b != null && d.of(b.name)[0].size() > 0) {
                name = b.name;
            }
        }
        var n = d.which.size();
        if (name == null) {
            if (n == 0) {
                if (TallyLog.count() == 0) {
                    Storage.deleteValue(TallyLog.LAST);
                }
                return;
            }
            name = d.names[d.which[n - 1]];
        }
        var index = d.names.indexOf(name);
        var log = TallyLog.since(Time.now().value() - DAYS * 86400);
        var t = 0;
        for (var i = log[0].size() - 1; i >= 0; i--) {
            if (log[1][i] == index) {
                t = log[0][i];
                break;
            }
        }
        Storage.setValue(TallyLog.LAST, [t, name, TallyButtons.colourOf(name, _buttons), TallyStats.streak(d.of(name)[0])]);
    }

    private function startTimer() as Void {
        if (_timer == null) {
            _timer = new Timer.Timer();
            (_timer as Timer.Timer).start(method(:onTick), 250, true);
        }
    }

    private function stopTimer() as Void {
        if (_timer != null) {
            (_timer as Timer.Timer).stop();
            _timer = null;
        }
    }

    function onTick() as Void {
        if (!undoing()) {
            stopTimer();
            _flash = -1;
            sync();
        }
        WatchUi.requestUpdate();
    }

    // Send what the sheet hasn't confirmed (after the undo window)
    function sync() as Void {
        if (_sender == null && !undoing()) {
            var sender = new TallySender(method(:onSynced));
            if (sender.send()) {
                _sender = sender;
            }
        }
    }

    function onSynced(ok as Boolean) as Void {
        _sender = null;
        TallySender.schedule();
        if (ok && (TallyLog.sent() < TallyLog.count() || TallyLog.edits().size() > 0)) {
            sync();     // more than one batch waiting
        }
    }

    // ---------------------------------------------------------------- input

    // A tap on the log page: a wedge logs, the centre undoes or opens every
    // button. True when the tap opened the list (the delegate pushes it).
    function tap(x as Number, y as Number) as Boolean {
        var dx = x - _cx;
        var dy = y - _cx;
        var r = Math.sqrt(dx * dx + dy * dy);
        if (r < _w * R_IN) {
            if (undoing()) {
                undo();
                return false;
            }
            return true;
        }
        var n = _shown.size();
        if (n == 0 || r > _w * 0.5) {
            return false;
        }
        var i = TallyButtons.wedgeAt(_shown, Math.toDegrees(Math.atan2(dx, -dy)).toFloat());
        _flash = i;
        log(_shown[i].name);
        return false;
    }

    // The pattern pages show the next name with entries, the busiest first
    function nextName() as Void {
        var r = ranked();
        if (r.size() > 0) {
            var names = (_days as TallyDays).names;
            var current = pickedName();
            var k = (current != null) ? r.indexOf(names.indexOf(current)) : -1;
            Storage.setValue(PICKED, names[r[(k + 1) % r.size()]]);
        }
        WatchUi.requestUpdate();
    }

    function nextPage(step as Number) as Void {
        page = (page + step + 4) % 4;
        WatchUi.requestUpdate();
    }

    // Names with entries in the last DAYS days, the most entries first
    private function ranked() as Array<Number> {
        var d = _days as TallyDays;
        var counts = d.counts();
        var out = [] as Array<Number>;
        for (var i = 0; i < counts.size(); i++) {
            if (counts[i] > 0) {
                var k = out.size();
                while (k > 0 && counts[out[k - 1]] < counts[i]) {
                    k--;
                }
                out = out.slice(0, k).addAll([i]).addAll(out.slice(k, null));
            }
        }
        return out;
    }

    // The name last picked, while it has entries; else the newest entry's
    private function pickedName() as String? {
        var d = _days as TallyDays;
        var n = d.which.size();
        if (n == 0) {
            return null;
        }
        var picked = Storage.getValue(PICKED);
        var i = (picked instanceof String) ? d.names.indexOf(picked) : -1;
        if (i >= 0 && d.counts()[i] > 0) {
            return d.names[i];
        }
        return d.names[d.which[n - 1]];
    }

    // ---------------------------------------------------------------- drawing

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        if (page == PAGE_LOG) {
            drawLog(dc);
        } else if (page == PAGE_RINGS) {
            drawRings(dc);
        } else if (page == PAGE_STRIP) {
            drawStrip(dc);
        } else {
            drawBefore(dc);
        }
    }

    private function text(dc as Dc, x as Numeric, y as Numeric, f as FontType, s as String, c as Number) as Void {
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, f, s, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function px(f as Float) as Number {
        return (_w * f).toNumber();
    }

    private function drawLog(dc as Dc) as Void {
        var n = _shown.size();
        var mid = _w * (R_OUT + R_IN) / 2;
        var s = TallyButtons.starts(_shown);
        var place = (s[1] > 0) ? 360.0 / s[1] : 360.0;
        // the first wedge centred at the top; the screen's degrees run
        // anticlockwise from 3 o'clock
        var offset = (n > 0) ? _shown[0].size * place / 2 : 0.0;
        dc.setPenWidth(px(R_OUT - R_IN));
        for (var i = 0; i < n; i++) {
            var b = _shown[i];
            var share = b.size * place;
            var centre = 90 - (s[0][i] * place - offset + share / 2);
            dc.setColor(scale(b.colour, (i == _flash && undoing()) ? 0.55 : WEDGE_DIM), Graphics.COLOR_TRANSPARENT);
            if (n == 1) {
                dc.drawCircle(_cx, _cx, mid);
            } else {
                dc.drawArc(_cx, _cx, mid, Graphics.ARC_CLOCKWISE, centre + share / 2 - GAP / 2.0, centre - share / 2 + GAP / 2.0);
            }
            var a = Math.toRadians(centre);
            var x = _cx + mid * Math.cos(a);
            var y = _cx - mid * Math.sin(a);
            var label = b.name.toUpper();
            var room = (share >= 180) ? _w * 0.40 : 2 * mid * Math.sin(Math.toRadians(share / 2)) - _w * 0.025;
            // a label reads across, so on the side wedges it must also stay
            // between the middle circle and the screen's edge at its height
            var dx = (x - _cx).abs();
            var far = (y - _cx).abs() + _w * 0.03;     // the text's row furthest out
            var near = (y - _cx).abs() - _w * 0.03;    // and nearest the middle
            var edge = _w * 0.485;
            var inner = _w * R_IN;
            var outside = (edge > far) ? Math.sqrt(edge * edge - far * far) - dx : 0.0;
            var inside = (inner > near) ? dx - Math.sqrt(inner * inner - near * near) : _w * 1.0;
            var across = 2 * ((outside < inside) ? outside : inside) - _w * 0.02;
            if (across < room) {
                room = across;
            }
            var f = Lib.Fmt.fitFont(dc, label, _names, room.toNumber());
            var today = todayCount(b.name);
            text(dc, x, (today > 0) ? y - _w * 0.030 : y, f, label, b.colour);
            if (today > 0) {
                text(dc, x, y + _w * 0.048, _tiny, today + " TODAY", scale(b.colour, 0.75));
            }
        }
        drawCentre(dc);
    }

    private function todayCount(name as String) as Number {
        var days = (_days as TallyDays).of(name)[0];
        var n = 0;
        for (var i = 0; i < days.size(); i++) {
            if (days[i] == 0) {
                n++;
            }
        }
        return n;
    }

    private function drawCentre(dc as Dc) as Void {
        var c = _cx;
        var r = _w * (R_IN - 0.015);
        if (_buttons.size() == 0) {
            text(dc, c, c - _w * 0.045, _tiny, "ADD BUTTONS", GRAY);
            text(dc, c, c + _w * 0.045, _tiny, "ON THE PHONE", GRAY);
            return;
        }
        var d = _days as TallyDays;
        var n = d.which.size();
        if (undoing() && n > 0) {
            var name = d.names[d.which[n - 1]];
            var colour = TallyButtons.colourOf(name, _buttons);
            text(dc, c, c - _w * 0.085, _tiny, "LOGGED", GRAY);
            fitted(dc, c, c, [_mid, _small, _tiny] as Array<FontType>, name.toUpper(), colour, chord(r, 0.0));
            text(dc, c, c + _w * 0.085, _tiny, "TAP: UNDO", GRAY);
            // the time left to undo, as a shrinking ring
            var left = (_undoUntil * 1000 - (Time.now().value() * 1000 + System.getTimer() % 1000)).toFloat() / (UNDO * 1000);
            if (left > 0) {
                dc.setPenWidth(px(0.010));
                dc.setColor(scale(colour, 0.6), Graphics.COLOR_TRANSPARENT);
                dc.drawArc(c, c, _w * (R_IN - 0.014), Graphics.ARC_CLOCKWISE, 90, 90 - 360 * (left > 0.999 ? 0.999 : left));
            }
            return;
        }
        if (n == 0) {
            text(dc, c, c - _w * 0.045, _tiny, "TAP A BUTTON", GRAY);
            text(dc, c, c + _w * 0.045, _tiny, "TO LOG IT", GRAY);
            return;
        }
        var name = d.names[d.which[n - 1]];
        var colour = TallyButtons.colourOf(name, _buttons);
        var label = (d.day[n - 1] == 0) ? ago(Lib.Fmt.localSeconds(Time.now().value()) - d.sec[n - 1])
                  : (d.day[n - 1] == 1) ? "YESTERDAY" : weekday(d.day[n - 1]);
        fitted(dc, c, c - _w * 0.115, [_tiny] as Array<FontType>, label, GRAY, chord(r, 0.115 + 0.03));
        text(dc, c, c - _w * 0.005, _big, Lib.Fmt.clock(d.sec[n - 1]), colour);
        fitted(dc, c, c + _w * 0.110, [_small, _tiny] as Array<FontType>, name.toUpper(), scale(colour, 0.85), chord(r, 0.110 + 0.035));
    }

    // The width of a circle of radius r at `offset` (a fraction of the
    // width) from its centre
    private function chord(r as Float, offset as Float) as Number {
        var o = _w * offset;
        return (o >= r) ? 0 : (2 * Math.sqrt(r * r - o * o)).toNumber();
    }

    // Text in the first font that fits `room`
    private function fitted(dc as Dc, x as Numeric, y as Numeric, fonts as Array<FontType>, s as String, c as Number, room as Number) as Void {
        text(dc, x, y, Lib.Fmt.fitFont(dc, s, fonts, room), s, c);
    }

    // "2H 10M AGO", "JUST NOW"
    private function ago(seconds as Number) as String {
        return (seconds < 60) ? "JUST NOW" : Lib.Fmt.countdown(seconds).toUpper() + " AGO";
    }

    private function weekday(ago as Number) as String {
        var info = Gregorian.info(Time.now().subtract(new Time.Duration(ago * 86400)) as Time.Moment, Time.FORMAT_MEDIUM);
        return (info.day_of_week as String).toUpper();
    }

    // A point on a 24-hour dial: midnight at the top, clockwise
    private function dial(r as Float, sec as Number) as [Numeric, Numeric] {
        var a = 2 * Math.PI * sec / 86400.0;
        return [_cx + r * Math.sin(a), _cx - r * Math.cos(a)];
    }

    private function drawRings(dc as Dc) as Void {
        var c = _cx;
        var r0 = _w * RING_IN;
        var r1 = _w * RING_OUT;
        dc.setPenWidth(1);
        dc.setColor(0x1E1E1E, Graphics.COLOR_TRANSPARENT);
        for (var k = 0; k < DAYS; k++) {
            dc.drawCircle(c, c, r0 + (r1 - r0) * k / (DAYS - 1));
        }
        drawDialMarks(dc);
        var name = pickedName();
        if (name == null) {
            text(dc, c, c - _w * 0.045, _tiny, "NOTHING", GRAY);
            text(dc, c, c + _w * 0.045, _tiny, "LOGGED YET", GRAY);
            return;
        }
        var colour = TallyButtons.colourOf(name, _buttons);
        var mine = (_days as TallyDays).of(name);
        var usual = TallyStats.usual(mine[1]);
        if (usual != null && usual[1] >= 3) {
            // the usual two hours, as an arc just outside the rings
            dc.setPenWidth(px(0.010));
            dc.setColor(scale(colour, 0.45), Graphics.COLOR_TRANSPARENT);
            var a0 = 90 - usual[2] * 360.0 / 86400;
            dc.drawArc(c, c, _w * (RING_OUT + 0.006), Graphics.ARC_CLOCKWISE, a0, a0 - TallyStats.WINDOW * 360.0 / 86400);
        }
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < mine[0].size(); i++) {
            var p = dial(r0 + (r1 - r0) * (DAYS - 1 - mine[0][i]) / (DAYS - 1), mine[1][i]);
            dc.fillCircle(p[0], p[1], _w * 0.0085);
        }
        var r = _w * (RING_IN - 0.012);
        fitted(dc, c, c - _w * 0.110, [_small, _tiny] as Array<FontType>, name.toUpper(), colour, chord(r, 0.110 + 0.03));
        if (usual != null && usual[1] >= 3) {
            text(dc, c, c, _big, Lib.Fmt.clock(usual[0]), colour);
            var within = TallyStats.daysWithin(mine[0], mine[1], usual[2], TallyStats.WINDOW);
            fitted(dc, c, c + _w * 0.110, [_tiny] as Array<FontType>, within + "/" + DAYS + " DAYS", GRAY, chord(r, 0.110 + 0.03));
        } else {
            text(dc, c, c, _big, mine[0].size().toString(), colour);
            fitted(dc, c, c + _w * 0.110, [_tiny] as Array<FontType>, "IN " + DAYS + " DAYS", GRAY, chord(r, 0.110 + 0.03));
        }
    }

    private function drawDialMarks(dc as Dc) as Void {
        var r = _w * DIAL;
        dc.setPenWidth(px(0.004) > 1 ? px(0.004) : 1);
        dc.setColor(0x3A3A3A, Graphics.COLOR_TRANSPARENT);
        for (var h = 0; h < 24; h++) {
            var p = dial(r, h * 3600);
            var q = dial(r + _w * ((h % 6 == 0) ? 0.022 : 0.012), h * 3600);
            dc.drawLine(p[0], p[1], q[0], q[1]);
        }
        var labels = ["MIDNIGHT", hourLabel(6), "NOON", hourLabel(18)] as Array<String>;
        for (var k = 0; k < 4; k++) {
            var p = dial(_w * DIAL_LABEL, k * 6 * 3600);
            text(dc, p[0], p[1], _tiny, labels[k], GRAY);
        }
    }

    // "6 AM" or "06", following the 12/24 h setting
    private function hourLabel(h as Number) as String {
        h = h % 24;
        if (System.getDeviceSettings().is24Hour) {
            return h.format("%02d");
        }
        var t = h % 12;
        return ((t == 0) ? 12 : t) + ((h < 12) ? " AM" : " PM");
    }

    private function drawStrip(dc as Dc) as Void {
        var c = _cx;
        var name = pickedName();
        if (name == null) {
            text(dc, c, c - _w * 0.045, _tiny, "NOTHING", GRAY);
            text(dc, c, c + _w * 0.045, _tiny, "LOGGED YET", GRAY);
            return;
        }
        var d = _days as TallyDays;
        var colour = TallyButtons.colourOf(name, _buttons);
        var mine = d.of(name);
        var usual = TallyStats.usual(mine[1]);
        var start = TallyStats.stripStart((usual != null && usual[1] >= 3) ? usual[0] : null,
                                          Lib.Fmt.localSeconds(Time.now().value())) * 3600;
        var span = STRIP_HOURS * 3600;
        var x0 = _w * STRIP_X0;
        var x1 = _w * STRIP_X1;
        var y0 = _w * STRIP_Y0;
        var y1 = _w * STRIP_Y1;

        fitted(dc, c, _w * 0.130, [_mid, _small] as Array<FontType>, name.toUpper(), colour, px(0.56));
        fitted(dc, c, _w * 0.215, [_tiny] as Array<FontType>, "AND WHAT CAME BEFORE", GRAY, px(0.80));

        dc.setPenWidth(1);
        dc.setColor(0x1A1A1A, Graphics.COLOR_TRANSPARENT);
        for (var k = 0; k < DAYS; k++) {
            var y = y0 + (y1 - y0) * k / (DAYS - 1);
            dc.drawLine(x0, y, x1, y);
        }
        for (var h = 0; h <= STRIP_HOURS; h += 3) {
            var x = x0 + (x1 - x0) * h / STRIP_HOURS;
            dc.setColor(FAINT, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(x, y0 - _w * 0.02, x, y1 + _w * 0.01);
            text(dc, x, y1 + _w * 0.060, _tiny, shortHour(start / 3600 + h), GRAY);
        }

        // the others first, small and dim, then the picked name on top
        var picked = d.names.indexOf(name);
        var seen = new [d.names.size()] as Array<Number>;
        for (var i = 0; i < seen.size(); i++) {
            seen[i] = 0;
        }
        for (var pass = 0; pass < 2; pass++) {
            for (var i = 0; i < d.which.size(); i++) {
                var mineToo = d.which[i] == picked;
                if (mineToo != (pass == 1)) {
                    continue;
                }
                var off = (d.sec[i] - start) % 86400;
                if (off < 0) {
                    off += 86400;
                }
                if (off >= span) {
                    continue;
                }
                var x = x0 + (x1 - x0) * off / span;
                var y = y0 + (y1 - y0) * (DAYS - 1 - d.day[i]) / (DAYS - 1);
                var col = TallyButtons.colourOf(d.names[d.which[i]], _buttons);
                dc.setColor(mineToo ? col : scale(col, 0.65), Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, _w * (mineToo ? 0.010 : 0.007));
                if (!mineToo) {
                    seen[d.which[i]] += 1;
                }
            }
        }
        drawLegend(dc, seen);
    }

    // Which names tend to come before the picked one, against the days it
    // didn't happen: a row per name, the clearest first
    private function drawBefore(dc as Dc) as Void {
        var c = _cx;
        var name = pickedName();
        if (name == null) {
            text(dc, c, c - _w * 0.045, _tiny, "NOTHING", GRAY);
            text(dc, c, c + _w * 0.045, _tiny, "LOGGED YET", GRAY);
            return;
        }
        var d = _days as TallyDays;
        var colour = TallyButtons.colourOf(name, _buttons);
        text(dc, c, _w * 0.105, _tiny, "BEFORE", GRAY);
        fitted(dc, c, _w * 0.185, [_mid, _small] as Array<FontType>, name.toUpper(), colour, px(0.60));
        var rows = beforeRows(name);
        if (rows.size() == 0) {
            var mine = d.of(name)[0].size();
            text(dc, c, c - _w * 0.045, _tiny, (mine < 3) ? "LOG IT A FEW" : "NOTHING CAME", GRAY);
            text(dc, c, c + _w * 0.045, _tiny, (mine < 3) ? "MORE TIMES" : "BEFORE IT OFTEN", GRAY);
        }
        for (var k = 0; k < rows.size(); k++) {
            var r = rows[k];
            var y = _w * (0.345 + 0.275 * k);
            var label = (r[0] as String).toUpper();
            var count = "  " + (r[1] as Number) + "/" + (r[2] as Number);
            var f = Lib.Fmt.fitFont(dc, label + count, [_mid, _small, _tiny] as Array<FontType>, px(0.80));
            var wl = dc.getTextWidthInPixels(label, f);
            var wc = dc.getTextWidthInPixels(count, f);
            var x = c - (wl + wc) / 2;
            var left = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
            dc.setColor(TallyButtons.colourOf(r[0] as String, _buttons), Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, f, label, left);
            dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + wl, y, f, count, left);
            text(dc, c, y + _w * 0.080, _tiny, "USUALLY " + gap(r[3] as Number) + " BEFORE", GRAY);
            if ((r[5] as Number) >= 2) {
                fitted(dc, c, y + _w * 0.150, [_tiny] as Array<FontType>, (r[4] as Number) + "/" + (r[5] as Number) + " DAYS WITHOUT IT",
                       scale(GRAY, 0.8), chord(_w * 0.49, 0.345 + 0.275 * k + 0.150 - 0.5 + 0.03));
            }
        }
    }

    // "45 MIN", "2 H"; the half hours too, past an hour ("2½ H")
    private function gap(seconds as Number) as String {
        var m = seconds / 60;
        if (m < 60) {
            return m + " MIN";
        }
        var halves = (m + 15) / 30;
        return (halves / 2) + ((halves % 2 == 1) ? "½" : "") + " H";
    }

    // [name, hits, of, median gap, control hits, controls] for up to two
    // names that came before `name` at least twice, the clearest first
    private function beforeRows(name as String) as Array<Array> {
        var d = _days as TallyDays;
        var mine = d.of(name);
        var rows = [] as Array<Array>;
        var scores = [] as Array<Float>;
        if (mine[0].size() < 3) {
            return rows;
        }
        var usual = TallyStats.usual(mine[1]);
        var controls = TallyStats.without(d.day, mine[0]);
        var at = (usual != null) ? usual[0] : TallyStats.sorted(mine[1])[mine[1].size() / 2];
        for (var i = 0; i < d.names.size(); i++) {
            var other = d.names[i];
            if (other.equals(name)) {
                continue;
            }
            var theirs = d.of(other);
            if (theirs[0].size() == 0) {
                continue;
            }
            var r = TallyStats.before(mine[0], mine[1], theirs[0], theirs[1], controls, at);
            if (r[0] < 2) {
                continue;
            }
            var score = r[0].toFloat() / r[1] - ((r[4] >= 2) ? r[3].toFloat() / r[4] : 0.0);
            var k = rows.size();
            while (k > 0 && scores[k - 1] < score) {
                k--;
            }
            rows = rows.slice(0, k).addAll([[other, r[0], r[1], r[2], r[3], r[4]]]).addAll(rows.slice(k, null));
            scores = scores.slice(0, k).addAll([score]).addAll(scores.slice(k, null));
        }
        return (rows.size() > 2) ? rows.slice(0, 2) : rows;
    }

    // The three names seen most often in the strip besides the picked one
    private function drawLegend(dc as Dc, seen as Array<Number>) as Void {
        var d = _days as TallyDays;
        var top = [] as Array<Number>;
        for (var k = 0; k < 3; k++) {
            var best = -1;
            for (var i = 0; i < seen.size(); i++) {
                if (seen[i] > 0 && top.indexOf(i) < 0 && (best < 0 || seen[i] > seen[best])) {
                    best = i;
                }
            }
            if (best >= 0) {
                top.add(best);
            }
        }
        var dotGap = _w * 0.026;
        var space = _w * 0.040;
        var total = 0;
        for (var k = 0; k < top.size(); k++) {
            total += dotGap + dc.getTextWidthInPixels(d.names[top[k]].toUpper(), _tiny) + ((k > 0) ? space : 0);
        }
        while (total > _w * 0.62 && top.size() > 1) {
            var last = d.names[top[top.size() - 1]].toUpper();
            total -= dotGap + dc.getTextWidthInPixels(last, _tiny) + space;
            top = top.slice(0, top.size() - 1);
        }
        var x = _cx - total / 2;
        var y = _w * 0.825;
        for (var k = 0; k < top.size(); k++) {
            var label = d.names[top[k]].toUpper();
            var col = TallyButtons.colourOf(d.names[top[k]], _buttons);
            dc.setColor(col, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x + _w * 0.008, y, _w * 0.009);
            dc.setColor(scale(col, 0.85), Graphics.COLOR_TRANSPARENT);
            dc.drawText(x + dotGap, y, _tiny, label, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
            x += dotGap + dc.getTextWidthInPixels(label, _tiny) + space;
        }
    }

    // "3P" or "15", for the strip's hour marks
    private function shortHour(h as Number) as String {
        h = h % 24;
        if (System.getDeviceSettings().is24Hour) {
            return h.format("%02d");
        }
        var t = h % 12;
        return ((t == 0) ? 12 : t) + ((h < 12) ? "A" : "P");
    }

    private function scale(colour as Number, f as Float) as Number {
        var r = ((colour >> 16) & 0xFF) * f;
        var g = ((colour >> 8) & 0xFF) * f;
        var b = (colour & 0xFF) * f;
        return (r.toNumber() << 16) | (g.toNumber() << 8) | b.toNumber();
    }
}

class TallyDelegate extends WatchUi.BehaviorDelegate {

    private var _view as TallyView;

    function initialize(view as TallyView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean {
        _view.nextPage(1);
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.nextPage(-1);
        return true;
    }

    // The watch offers a touch to the behaviours first (a tap is "select",
    // like START) and only delivers it raw as onTap when they decline. So
    // onSelect declines, onTap acts on where the tap landed, and onKey on
    // the START button. (The simulator calls onTap first, which hid this.)
    function onSelect() as Boolean {
        return false;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        if (_view.page != PAGE_LOG) {
            _view.nextName();
            return true;
        }
        var c = evt.getCoordinates();
        if (_view.tap(c[0], c[1])) {
            TallyAll.open(_view);
        }
        return true;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();
        if (key != WatchUi.KEY_ENTER && key != WatchUi.KEY_START) {
            return false;
        }
        if (_view.page != PAGE_LOG) {
            _view.nextName();
        } else if (_view.undoing()) {
            _view.undo();
        } else {
            TallyAll.open(_view);
        }
        return true;
    }

    function onBack() as Boolean {
        if (_view.page != PAGE_LOG) {
            _view.page = PAGE_LOG;
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }
}
