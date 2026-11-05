import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

enum {
    STATE_IDLE,     // the routine that suits now, START to go
    STATE_RUN,      // a routine playing
    STATE_DONE,     // the summary
    STATE_GUIDE     // what the buzzes mean, each played in turn
}

// One view for the whole app. Idle: why, the routine, its length and its
// first stretch. Running: the stretch's name across the top, the figure
// easing in, breathing and easing out, the time left in big digits, the
// coach's line, what comes next, and the hold as an arc round the bezel.
// Done: how long, the streak, and whether it went to Garmin Connect.
// Every screen cues what each button does.
class StretchView extends WatchUi.View {

    private const ACCENT = 0xFF8A4C;   // the muscle being stretched, the hold
    private const SWITCH = 0x6EAAE6;   // other side
    private const WHITE = 0xEBEBE6;
    private const GRAY = 0x9E9E9E;     // 7.8:1 on black, readable in sunlight
    private const FAR = 0x7A7A7A;      // the far limbs, and quiet cue arcs
    private const GHOST = 0x505050;    // where the stretch is going, drawn thin
    private const THROB = 0xE85A1C;    // the push's beat: darker, so it never merges with white
    private const TRACK = 0x1E1E1E;
    private const FRAME_MS = 100;

    private var _state as Number = STATE_IDLE;
    private var _session as StretchSession? = null;
    private var _recorder as StretchRecorder = new StretchRecorder();
    private var _timer as Timer.Timer? = null;
    private var _paused as Boolean = false;
    private var _last as Number = 0;          // System.getTimer() at the last frame
    private var _step as Number = -1;         // for a lap at each new stretch
    private var _suggest as Array<Number> = [0, 0, -1] as Array<Number>;
    private var _routine as Number = 0;
    private var _startUnix as Number = 0;
    private var _saved as Boolean = false;
    private var _complete as Boolean = false;
    private var _stepsDone as Number = 0;
    private var _playedMs as Number = 0;

    private var _ringR as Number = 213;
    private var _ringPen as Number = 10;
    private var _w as Number = 454;
    private var _h as Number = 454;
    private var _bandFont as FontType = Graphics.FONT_SMALL;
    private var _bigFont as FontType = Graphics.FONT_NUMBER_MEDIUM;
    private var _nameFont as FontType = Graphics.FONT_MEDIUM;
    private var _lineFont as FontType = Graphics.FONT_SMALL;
    private var _labelFont as FontType = Graphics.FONT_XTINY;
    private var _wrapped as String = "";                  // the coach line last wrapped,
    private var _lines as Array<String> = [] as Array<String>;   // and its lines

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        var h = dc.getHeight();
        _w = dc.getWidth();
        _h = h;
        // nothing smaller than the watch's own smallest font (37 px on 454)
        var small = (h * 0.083).toNumber();
        var floor = Graphics.getFontHeight(Graphics.FONT_XTINY);
        if (small < floor) {
            small = floor;
        }
        _bandFont = Lib.Fmt.vectorFont("RobotoCondensedBold", small, Graphics.FONT_SMALL);
        _bigFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.13).toNumber(), Graphics.FONT_NUMBER_MEDIUM);
        _nameFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.10).toNumber(), Graphics.FONT_MEDIUM);
        _lineFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", small, Graphics.FONT_SMALL);
        _labelFont = Lib.Fmt.vectorFont("RobotoCondensedBold", small, Graphics.FONT_XTINY);
    }

    function onShow() as Void {
        if (_state == STATE_IDLE) {
            _suggest = StretchPlan.now();
            _routine = _suggest[0];
            var shot = StretchShot.start();
            if (shot != null && _startUnix == 0) {
                // a sample build opens part-way through a routine
                begin(shot[0], false, shot[1] == 1);
                var s = _session;
                var seen = -1;
                var was = -1;
                // a phase at a time: ticking through minutes would trip the watchdog
                while (s != null && !s.done() && seen < shot[3]) {
                    s.tick(s.remaining());
                    var p = s.phase();
                    if (p == shot[2] && was != p) {
                        seen++;
                    }
                    was = p;
                }
                if (s != null) {
                    s.tick(shot[4]);
                    _step = s.stepIndex();
                    if (s.done()) {
                        finish(true);
                    }
                }
            }
        }
        if (_state == STATE_RUN && !_paused) {
            startTimer();
        }
    }

    function onHide() as Void {
        stopTimer();
    }

    private function startTimer() as Void {
        if (_timer == null) {
            var t = new Timer.Timer();
            t.start(method(:onFrame), FRAME_MS, true);
            _timer = t;
            _last = System.getTimer();
        }
    }

    private function stopTimer() as Void {
        var t = _timer;
        if (t != null) {
            t.stop();
            _timer = null;
        }
    }

    function state() as Number {
        return _state;
    }

    function routine() as Number {
        return _routine;
    }

    function running() as Boolean {
        return _state == STATE_RUN;
    }

    // Begin a routine now
    function start(routine as Number) as Void {
        begin(routine, StretchSettings.record(), StretchSettings.contractRelax());
    }

    private function begin(routine as Number, record as Boolean, pnf as Boolean) as Void {
        _routine = routine;
        _session = new StretchSession(routine, StretchSettings.level(), pnf);
        _state = STATE_RUN;
        _paused = false;
        _step = 0;
        _startUnix = Time.now().value();
        if (record) {
            _recorder.start(StretchRoutines.NAMES[routine]);
        }
        startTimer();
        WatchUi.requestUpdate();
    }

    function onFrame() as Void {
        var s = _session;
        if (s == null || _paused) {
            return;
        }
        var now = System.getTimer();
        var dt = now - _last;
        _last = now;
        if (dt < 0 || dt > 2000) {
            dt = FRAME_MS;   // a stall (or the counter wrapping) is not stretching time
        }
        played(s, s.tick(dt));
    }

    // After the session moved: a lap at a new stretch, the buzz, the end
    private function played(s as StretchSession, buzz as Number) as Void {
        if (s.stepIndex() != _step) {
            _step = s.stepIndex();
            _recorder.lap();
        }
        signal(buzz);
        if (s.done()) {
            finish(true);
        }
        WatchUi.requestUpdate();
    }

    private function signal(buzz as Number) as Void {
        if (buzz == BUZZ_NONE) {
            return;
        }
        if (Attention has :vibrate) {
            var pat = StretchBuzz.pattern(buzz);
            var p = [] as Array<Attention.VibeProfile>;
            for (var i = 0; i + 1 < pat.size(); i += 2) {
                p.add(new Attention.VibeProfile(pat[i], pat[i + 1]));
            }
            Attention.vibrate(p);
        }
        if (StretchSettings.tones() && (Attention has :playTone)) {
            Attention.playTone(buzz == BUZZ_DONE ? Attention.TONE_SUCCESS
                               : (buzz == BUZZ_GO || buzz == BUZZ_PUSH ? Attention.TONE_START : Attention.TONE_KEY));
        }
    }

    // The buzz guide: each buzz with its name, three seconds apart
    private var _guide as Number = 0;

    function guide() as Void {
        _state = STATE_GUIDE;
        _guide = 0;
        stopTimer();
        var t = new Timer.Timer();
        t.start(method(:onGuide), 3000, true);
        _timer = t;
        signal(StretchBuzz.GUIDE[0]);
        WatchUi.requestUpdate();
    }

    function onGuide() as Void {
        _guide++;
        if (_guide >= StretchBuzz.GUIDE.size()) {
            stopTimer();
            toIdle();
            return;
        }
        signal(StretchBuzz.GUIDE[_guide]);
        WatchUi.requestUpdate();
    }

    private function drawGuide(dc as Dc) as Void {
        _ringPen = 0;
        var b = StretchBuzz.GUIDE[_guide];
        text(dc, 0.18, _bandFont, GRAY, "THE BUZZES · " + (_guide + 1) + " OF " + StretchBuzz.GUIDE.size());
        text(dc, 0.42, _nameFont, b == BUZZ_SWITCH ? SWITCH : ACCENT, StretchBuzz.name(b));
        var lines = wrap(dc, StretchBuzz.meaning(b), _lineFont, (_w * 0.78).toNumber());
        text(dc, 0.58, _lineFont, WHITE, lines[0]);
        if (lines.size() > 1) {
            text(dc, 0.66, _lineFont, WHITE, lines[1]);
        }
        cue(dc, Lib.Cues.BACK, "STOP", FAR, GRAY);
    }

    // BACK while running: "go now" in a setup, else on to the next side or stretch
    function skip() as Void {
        var s = _session;
        if (s == null) {
            return;
        }
        played(s, s.phase() == PH_SETUP ? s.advance() : s.skip());
    }

    function skipStretch() as Void {
        var s = _session;
        if (s != null) {
            played(s, s.skipStretch());
        }
    }

    // UP while holding: ten seconds more
    function extend() as Void {
        var s = _session;
        if (s != null && s.extend(10000)) {
            WatchUi.requestUpdate();
        }
    }

    // DOWN while stretching: it hurts, so out now, gently
    function easeOff() as Void {
        var s = _session;
        if (s != null) {
            played(s, s.easeOff());
        }
    }

    function pause() as Void {
        if (_state == STATE_RUN && !_paused) {
            _paused = true;
            stopTimer();
            _recorder.pause();
        }
    }

    function resume() as Void {
        if (_state == STATE_RUN && _paused) {
            _paused = false;
            _recorder.resume();
            startTimer();
        }
        WatchUi.requestUpdate();
    }

    // Saved and kept in the history; complete when the routine played to the end
    function finish(complete as Boolean) as Void {
        var s = _session;
        if (s == null) {
            return;
        }
        stopTimer();
        _complete = complete;
        _playedMs = s.elapsed;
        _stepsDone = complete ? s.steps : s.stepIndex();
        _saved = _recorder.save();
        if (complete || _playedMs >= 60000) {
            StretchHistory.add(_startUnix, _routine, _playedMs / 1000, complete);
        }
        _session = null;
        _paused = false;
        _state = STATE_DONE;
        WatchUi.requestUpdate();
    }

    function discard() as Void {
        stopTimer();
        _recorder.discard();
        _session = null;
        _paused = false;
        toIdle();
    }

    function endGuide() as Void {
        stopTimer();
        toIdle();
    }

    function toIdle() as Void {
        _state = STATE_IDLE;
        _suggest = StretchPlan.now();
        _routine = _suggest[0];
        WatchUi.requestUpdate();
    }

    // The app is closing: keep what was done
    function shutdown() as Void {
        if (_state == STATE_RUN) {
            finish(false);
        }
        stopTimer();
    }

    function cueAt(x as Number, y as Number) as Number {
        return Lib.Cues.at(x, y, _w, _h);
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        var s = _session;
        if (_state == STATE_RUN && s != null) {
            drawRun(dc, s);
        } else if (_state == STATE_DONE) {
            drawDone(dc);
        } else if (_state == STATE_GUIDE) {
            drawGuide(dc);
        } else {
            drawIdle(dc);
        }
    }

    private function text(dc as Dc, y as Float, font as FontType, colour as Number, t as String) as Void {
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_w / 2, (_h * y).toNumber(), font, t, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // A line too wide for one row, split at the space that balances it best
    // (a "·" at the split goes); kept for the next frame
    private function wrap(dc as Dc, t as String, font as FontType, max as Number) as Array<String> {
        if (t.equals(_wrapped)) {
            return _lines;
        }
        _wrapped = t;
        _lines = [t] as Array<String>;
        if (dc.getTextWidthInPixels(t, font) <= max) {
            return _lines;
        }
        var chars = t.toCharArray();
        var best = 99999;
        for (var i = 1; i < chars.size() - 1; i++) {
            if (chars[i] != ' ') {
                continue;
            }
            var a = t.substring(0, i) as String;
            var b = t.substring(i + 1, chars.size()) as String;
            if (a.length() > 2 && (a.substring(a.length() - 2, a.length()) as String).equals(" ·")) {
                a = a.substring(0, a.length() - 2) as String;
            }
            if (b.length() > 2 && (b.substring(0, 2) as String).equals("· ")) {
                b = b.substring(2, b.length()) as String;
            }
            var wa = dc.getTextWidthInPixels(a, font);
            var wb = dc.getTextWidthInPixels(b, font);
            var wide = wa > wb ? wa : wb;
            if (wide < best) {
                best = wide;
                _lines = [a, b] as Array<String>;
            }
        }
        return _lines;
    }

    // A button cue: its arc at Garmin's hint angle (with a black gap in the
    // bezel ring under it, so it never reads as progress) and its word,
    // large, running inwards from the edge
    private function cue(dc as Dc, angle as Number, label as String, arc as Number, word as Number) as Void {
        if (_ringPen > 0) {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            Lib.Arcs.drawClockwise(dc, _w / 2, _h / 2, _ringR, angle - Lib.Cues.SPAN - 3, 2 * Lib.Cues.SPAN + 6, _ringPen + 4);
        }
        Lib.Cues.draw(dc, angle, "", _labelFont, arc, word);
        var r = _w / 2 - (_h * 0.06).toNumber();
        var rad = Math.toRadians(angle);
        var x = _w / 2 + (r * Math.sin(rad)).toNumber();
        var y = _h / 2 - (r * Math.cos(rad)).toNumber();
        dc.setColor(word, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, _labelFont, label,
                    (angle < 180 ? Graphics.TEXT_JUSTIFY_RIGHT : Graphics.TEXT_JUSTIFY_LEFT) | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // The opening card: why, the routine, its length, its first stretch, what it is for, the streak
    private function drawIdle(dc as Dc) as Void {
        _ringPen = 0;
        var r = _routine;
        var why = r == _suggest[0] ? StretchPlan.why(_suggest) : "YOUR PICK";
        text(dc, 0.13, _bandFont, ACCENT, why);
        text(dc, 0.235, _nameFont, WHITE, StretchRoutines.NAMES[r]);
        var steps = StretchData.STEPS[r].size() / 3;
        text(dc, 0.33, _lineFont, GRAY, StretchPlan.minutes(r) + " · " + StretchText.stretches(steps));
        var first = StretchData.STEPS[r][0];
        StretchFigure.draw(dc, first, 1.0, false, _w / 2, (_h * 0.635).toNumber(),
                           (_w * 0.40).toNumber(), (_h * 0.25).toNumber(), WHITE, FAR, ACCENT);
        text(dc, 0.72, _lineFont, WHITE, StretchRoutines.ABOUT[r]);
        text(dc, 0.81, _lineFont, GRAY, StretchText.streakLine(Time.now().value()));
        cue(dc, Lib.Cues.START, "GO", ACCENT, WHITE);
        cue(dc, Lib.Cues.UP, "MORE", FAR, GRAY);
    }

    // Running: the stretch's name and the side across the top, the figure,
    // the coach (two lines at most), the time left at the foot, the hold
    // round the bezel
    private function drawRun(dc as Dc, s as StretchSession) as Void {
        var p = s.phase();
        var st = s.stretch();
        var sideWord = s.sided() ? (s.side() == 0 ? "LEFT" : "RIGHT") : "";

        // the bezel: the hold (ease-in included), the reps or the push in
        // the accent, a setup in grey; the slow breath fills and empties it
        var pen = (_h * 0.022).toNumber();
        _ringR = _w / 2 - pen / 2 - 2;
        _ringPen = pen;
        var ringColour = p == PH_SETUP ? GRAY : (p == PH_RELEASE || p == PH_RELAX ? FAR : ACCENT);
        var fill = p == PH_RELEASE ? 0.0 : (p == PH_BREATHE ? s.blend() : s.holdDone());
        Lib.Arcs.drawGauge(dc, _w / 2, _h / 2, _ringR, 0, 360, fill, pen, TRACK, ringColour);

        // the top: the name, then the side (or what the setup leads to, or the breath)
        var set = s.setKind();
        var nameColour = p == PH_SETUP ? WHITE : ACCENT;
        var sub = sideWord;
        var subColour = ACCENT;
        if (p == PH_SETUP) {
            if (set == SET_SIDE) {
                sub = "SWITCH · " + sideWord;
                subColour = SWITCH;
            } else if (set == SET_ROUND) {
                sub = sideWord.equals("") ? "AGAIN" : "AGAIN · " + sideWord;
                subColour = SWITCH;
            } else {
                sub = sideWord.equals("") ? "NEXT" : "NEXT · " + sideWord;
                subColour = GRAY;
            }
        } else if (p == PH_BREATHE) {
            sub = s.breathingIn() ? "BREATHE IN" : "BREATHE OUT";
        } else if (s.rounds() > 1 && p != PH_REPS) {
            sub = (sideWord.equals("") ? "ROUND " : sideWord + " · ") + (s.round() + 1) + " OF " + s.rounds();
        }
        text(dc, 0.12, Lib.Fmt.fitFont(dc, StretchData.NAMES[st].toUpper(), [_bandFont] as Array<FontType>, _w),
             nameColour, StretchData.NAMES[st].toUpper());
        if (!sub.equals("")) {
            text(dc, 0.20, _bandFont, subColour, sub);
        }

        // the figure: the start pose with the stretch as a thin ghost while setting up
        var cx = _w / 2;
        var ground = (_h * 0.515).toNumber();
        var bw = (_w * 0.48).toNumber();
        var bh = (_h * 0.27).toNumber();
        var mirror = s.side() == 1;
        if (p == PH_SETUP && !s.demoing()) {
            // the last seconds before the start: where the stretch is going
            StretchFigure.draw(dc, st, 1.0, mirror, cx, ground, bw, bh, GHOST, GHOST, null);
        }
        var accent = ACCENT;
        if (p == PH_PUSH && (s.phaseMs() / 500) % 2 == 1) {
            accent = THROB;   // the push throbs
        }
        StretchFigure.draw(dc, st, s.blend(), mirror, cx, ground, bw, bh, WHITE, FAR, accent);

        // the coach
        var lines = wrap(dc, s.line(), _lineFont, (_w * 0.80).toNumber());
        if (lines.size() == 1) {
            text(dc, 0.62, _lineFont, WHITE, lines[0]);
        } else {
            text(dc, 0.585, _lineFont, WHITE, lines[0]);
            text(dc, 0.66, _lineFont, WHITE, lines[1]);
        }

        // the time left (or the rep), below the button words
        var big = p == PH_REPS ? s.rep() + "/" + s.repCount()
                               : StretchText.clock(p == PH_EASE || p == PH_HOLD ? s.holdLeft() : s.remaining());
        text(dc, 0.85, _bigFont, p == PH_SETUP || p == PH_RELEASE ? GRAY : WHITE, big);

        cue(dc, Lib.Cues.START, "PAUSE", WHITE, WHITE);
        cue(dc, Lib.Cues.BACK, p == PH_SETUP ? "GO" : "SKIP", FAR, GRAY);
        if (p == PH_HOLD || p == PH_DEEPEN || p == PH_REPS || p == PH_BREATHE) {
            cue(dc, Lib.Cues.UP, "+10", FAR, GRAY);
        }
        if (p == PH_EASE || p == PH_HOLD || p == PH_PUSH || p == PH_RELAX || p == PH_DEEPEN) {
            // it hurts: out of the stretch, gently
            cue(dc, Lib.Cues.DOWN, "EASE OFF", GRAY, WHITE);
        }
    }

    // For the pause menu: "5:03 left · 4 of 8"
    function progress() as String {
        var s = _session;
        if (s == null) {
            return "";
        }
        return StretchText.clock(s.left()) + " left · " + (s.stepIndex() + 1) + " of " + s.steps;
    }

    private function drawDone(dc as Dc) as Void {
        _ringPen = 0;
        text(dc, 0.15, _bandFont, ACCENT, _complete ? "WELL STRETCHED" : "STOPPED");
        text(dc, 0.255, _nameFont, WHITE, StretchRoutines.NAMES[_routine]);
        var steps = StretchData.STEPS[_routine].size() / 3;
        var what = _complete ? StretchText.stretches(steps) : _stepsDone + " of " + steps;
        text(dc, 0.35, _lineFont, GRAY, StretchText.clock(_playedMs) + " · " + what);
        var r = StretchHistory.rows();
        var now = Time.now().value();
        var streak = StretchHistory.streak(now, r);
        text(dc, 0.49, _bigFont, ACCENT, streak.toString());
        text(dc, 0.60, _lineFont, WHITE, streak == 1 ? "day of stretching" : "days in a row");
        text(dc, 0.69, _lineFont, GRAY, StretchHistory.week(now, r) + " this week");
        var note = _saved ? "Saved to Connect" : "Not recorded";
        if (_complete && (StretchRoutines.FLAGS[_routine] & StretchSession.RF_PRE) != 0) {
            note = "Start easy, then build";
        } else if (_complete && StretchHistory.readyForMore(now, r, StretchSettings.levelIndex())) {
            note = "Try Deep holds next";
        }
        text(dc, 0.82, _lineFont, WHITE, note);
        cue(dc, Lib.Cues.START, "OK", ACCENT, WHITE);
        cue(dc, Lib.Cues.BACK, "EXIT", FAR, GRAY);
    }
}

// Buttons. Idle: START goes, UP or DOWN lists every routine, BACK leaves.
// Running: START pauses (the menu), BACK goes now or skips, UP adds ten
// seconds to a hold. Done: START back to the start, BACK leaves. A touch
// near a cue does what that button does.
class StretchDelegate extends WatchUi.BehaviorDelegate {

    private var _view as StretchView;

    function initialize(view as StretchView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();
        if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START) {
            pressStart();
            return true;
        }
        return false;
    }

    function onSelect() as Boolean {
        return false;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var c = evt.getCoordinates();
        var tap = _view.cueAt(c[0], c[1]);
        if (tap == Lib.Cues.TAP_START) {
            pressStart();
        } else if (tap == Lib.Cues.TAP_BACK) {
            if (!onBack()) {
                System.exit();
            }
        } else if (tap == Lib.Cues.TAP_UP) {
            onPreviousPage();
        } else if (tap == Lib.Cues.TAP_DOWN) {
            onNextPage();
        }
        return true;
    }

    function onBack() as Boolean {
        if (_view.running()) {
            _view.skip();
            return true;
        }
        if (_view.state() == STATE_GUIDE) {
            _view.endGuide();
            return true;
        }
        return false;
    }

    function onPreviousPage() as Boolean {
        if (_view.running()) {
            _view.extend();
        } else if (_view.state() == STATE_IDLE) {
            routines();
        }
        return true;
    }

    function onNextPage() as Boolean {
        if (_view.running()) {
            _view.easeOff();
        } else if (_view.state() == STATE_IDLE) {
            routines();
        }
        return true;
    }

    function onMenu() as Boolean {
        if (_view.running()) {
            pressStart();
        } else {
            routines();
        }
        return true;
    }

    function pressStart() as Void {
        var st = _view.state();
        if (st == STATE_IDLE) {
            _view.start(_view.routine());
        } else if (st == STATE_DONE) {
            _view.toIdle();
        } else {
            _view.pause();
            var menu = new WatchUi.Menu2({:title => "Paused"});
            menu.addItem(new WatchUi.MenuItem("Resume", _view.progress(), :resume, null));
            menu.addItem(new WatchUi.MenuItem("Skip stretch", "on to the next one", :skip, null));
            menu.addItem(new WatchUi.MenuItem("Finish", "save what you did", :finish, null));
            menu.addItem(new WatchUi.MenuItem("Discard", "keep nothing", :discard, null));
            WatchUi.pushView(menu, new StretchMenuDelegate(_view), WatchUi.SLIDE_UP);
        }
    }

    // Every routine with its length, then clearing the history
    function routines() as Void {
        var menu = new WatchUi.Menu2({:title => "Routines"});
        for (var i = 0; i < StretchRoutines.COUNT; i++) {
            menu.addItem(new WatchUi.MenuItem(StretchRoutines.NAMES[i],
                         StretchPlan.minutes(i) + " · " + StretchRoutines.ABOUT[i], i, null));
        }
        menu.addItem(new WatchUi.MenuItem("The buzzes", "feel what each one means", :buzzes, null));
        menu.addItem(new WatchUi.MenuItem("Clear history", "forget past sessions", :clear, null));
        WatchUi.pushView(menu, new StretchMenuDelegate(_view), WatchUi.SLIDE_UP);
    }
}

class StretchMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as StretchView;

    function initialize(view as StretchView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        if (id instanceof Number) {
            _view.start(id);
        } else if (id == :skip) {
            _view.skipStretch();
            _view.resume();
        } else if (id == :finish) {
            _view.finish(false);
        } else if (id == :discard) {
            _view.discard();
        } else if (id == :buzzes) {
            _view.guide();
        } else if (id == :clear) {
            StretchHistory.clear();
            WatchUi.requestUpdate();
        } else {
            _view.resume();
        }
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
        _view.resume();
    }
}
