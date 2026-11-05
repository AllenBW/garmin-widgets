import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

enum {
    STATE_IDLE,     // the routine that suits now, START to go
    STATE_RUN,      // a routine playing
    STATE_DONE      // the summary
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
    private const GRAY = 0x8A8A8A;
    private const FAR = 0x6E6E6E;      // the far limbs
    private const GHOST = 0x343434;    // where the stretch is going
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

    private var _w as Number = 454;
    private var _h as Number = 454;
    private var _bandFont as FontType = Graphics.FONT_SMALL;
    private var _bigFont as FontType = Graphics.FONT_NUMBER_MEDIUM;
    private var _nameFont as FontType = Graphics.FONT_MEDIUM;
    private var _lineFont as FontType = Graphics.FONT_SMALL;
    private var _lineSmall as FontType = Graphics.FONT_XTINY;
    private var _labelFont as FontType = Graphics.FONT_XTINY;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        var h = dc.getHeight();
        _w = dc.getWidth();
        _h = h;
        _bandFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.058).toNumber(), Graphics.FONT_SMALL);
        _bigFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.15).toNumber(), Graphics.FONT_NUMBER_MEDIUM);
        _nameFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.10).toNumber(), Graphics.FONT_MEDIUM);
        _lineFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.062).toNumber(), Graphics.FONT_SMALL);
        _lineSmall = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.052).toNumber(), Graphics.FONT_XTINY);
        _labelFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.046).toNumber(), Graphics.FONT_XTINY);
    }

    function onShow() as Void {
        if (_state == STATE_IDLE) {
            _suggest = StretchPlan.now();
            _routine = _suggest[0];
            var shot = StretchShot.start();
            if (shot != null && _startUnix == 0) {
                // a sample build opens part-way through a routine
                begin(shot[0], false);
                var s = _session;
                if (s != null) {
                    s.tick(shot[1]);
                    _step = s.stepIndex();
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
        begin(routine, StretchSettings.record());
    }

    private function begin(routine as Number, record as Boolean) as Void {
        _routine = routine;
        _session = new StretchSession(routine, StretchSettings.level(), StretchSettings.contractRelax());
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
            var p;
            if (buzz == BUZZ_GO) {
                p = [new Attention.VibeProfile(50, 150)];
            } else if (buzz == BUZZ_RELEASE) {
                p = [new Attention.VibeProfile(35, 450)];
            } else if (buzz == BUZZ_SWITCH) {
                p = [new Attention.VibeProfile(70, 120), new Attention.VibeProfile(0, 120), new Attention.VibeProfile(70, 120)];
            } else if (buzz == BUZZ_NEXT) {
                p = [new Attention.VibeProfile(70, 110), new Attention.VibeProfile(0, 100), new Attention.VibeProfile(70, 110),
                     new Attention.VibeProfile(0, 100), new Attention.VibeProfile(70, 110)];
            } else {
                p = [new Attention.VibeProfile(80, 300), new Attention.VibeProfile(0, 150), new Attention.VibeProfile(80, 600)];
            }
            Attention.vibrate(p as Array<Attention.VibeProfile>);
        }
        if (StretchSettings.tones() && (Attention has :playTone)) {
            Attention.playTone(buzz == BUZZ_DONE ? Attention.TONE_SUCCESS : Attention.TONE_KEY);
        }
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
        } else {
            drawIdle(dc);
        }
    }

    private function text(dc as Dc, y as Float, font as FontType, colour as Number, t as String) as Void {
        dc.setColor(colour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_w / 2, (_h * y).toNumber(), font, t, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawIdle(dc as Dc) as Void {
        var r = _routine;
        var why = r == _suggest[0] ? StretchPlan.why(_suggest) : "YOUR PICK";
        text(dc, 0.13, _bandFont, ACCENT, why);
        text(dc, 0.235, _nameFont, WHITE, StretchRoutines.NAMES[r]);
        var steps = StretchData.STEPS[r].size() / 3;
        text(dc, 0.32, _lineSmall, GRAY, StretchPlan.minutes(r) + " · " + StretchText.stretches(steps));
        var first = StretchData.STEPS[r][0];
        StretchFigure.draw(dc, first, 1.0, false, _w / 2, (_h * 0.66).toNumber(),
                           (_w * 0.42).toNumber(), (_h * 0.27).toNumber(), WHITE, FAR, ACCENT);
        text(dc, 0.75, _lineSmall, GRAY, StretchRoutines.ABOUT[r]);
        text(dc, 0.83, _labelFont, GRAY, StretchText.streakLine(Time.now().value()));
        Lib.Cues.draw(dc, Lib.Cues.START, "GO", _labelFont, ACCENT, WHITE);
        Lib.Cues.draw(dc, Lib.Cues.DOWN, "MORE", _labelFont, FAR, GRAY);
    }

    private function drawRun(dc as Dc, s as StretchSession) as Void {
        var p = s.phase();
        var st = s.stretch();
        var side = s.side();
        var name = StretchData.NAMES[st].toUpper();
        if (s.sided()) {
            name += side == 0 ? " · LEFT" : " · RIGHT";
        }

        // the bezel: the hold (ease-in included), the reps or the push filling in the accent, a setup in grey
        var pen = (_h * 0.022).toNumber();
        var ringColour = p == PH_SETUP ? GHOST : (p == PH_RELEASE || p == PH_RELAX ? FAR : ACCENT);
        Lib.Arcs.drawGauge(dc, _w / 2, _h / 2, _w / 2 - pen / 2 - 2, 0, 360,
                           p == PH_RELEASE ? 0.0 : s.holdDone(), pen, TRACK, ringColour);

        // the band: what, which side, and the round
        var band = name;
        var bandColour = ACCENT;
        var sub = "";
        var set = s.setKind();
        if (p == PH_SETUP) {
            if (set == SET_SIDE) {
                band = "SWITCH SIDES";
                bandColour = SWITCH;
                sub = name;
            } else if (set == SET_ROUND) {
                band = "AGAIN · " + name;
                sub = "round " + (s.round() + 1) + " of " + s.rounds();
            } else {
                band = (set == SET_FIRST ? "FIRST · " : "NEXT · ") + name;
                bandColour = WHITE;
                sub = (s.stepIndex() + 1) + " of " + s.steps + doseWords(s);
            }
        } else if (p == PH_REPS) {
            sub = "rep " + s.rep() + " of " + s.repCount();
        } else if (p == PH_BREATHE) {
            sub = "six slow breaths a minute";
        } else if (p == PH_PUSH || p == PH_RELAX || p == PH_DEEPEN) {
            sub = "contract-relax";
        } else if (s.rounds() > 1) {
            sub = "round " + (s.round() + 1) + " of " + s.rounds();
        }
        text(dc, 0.13, _bandFont, bandColour, band);
        if (!sub.equals("")) {
            text(dc, 0.19, _labelFont, GRAY, sub);
        }

        // the figure: the start pose with the stretch as a ghost while setting up
        var cx = _w / 2;
        var ground = (_h * 0.60).toNumber();
        var bw = (_w * 0.50).toNumber();
        var bh = (_h * 0.34).toNumber();
        var mirror = side == 1;
        if (p == PH_SETUP) {
            StretchFigure.draw(dc, st, 1.0, mirror, cx, ground, bw, bh, GHOST, GHOST, null);
        }
        var accent = ACCENT;
        if (p == PH_PUSH && (s.phaseMs() / 500) % 2 == 1) {
            accent = 0xFFC2A0;   // the push throbs
        }
        StretchFigure.draw(dc, st, s.blend(), mirror, cx, ground, bw, bh, WHITE, FAR, accent);

        // the time left, the coach, what is next
        var big = p == PH_REPS ? s.rep() + "/" + s.repCount()
                               : StretchText.clock(p == PH_EASE || p == PH_HOLD ? s.holdLeft() : s.remaining());
        text(dc, 0.70, _bigFont, p == PH_SETUP || p == PH_RELEASE ? GRAY : WHITE, big);
        var line = s.line();
        text(dc, 0.80, Lib.Fmt.fitFont(dc, line, [_lineFont, _lineSmall] as Array<FontType>, (_w * 0.78).toNumber()), WHITE, line);
        var next = s.nextStretch();
        var foot = next < 0 ? "last stretch · " + StretchText.clock(s.left()) + " left"
                            : "next " + StretchData.NAMES[next] + " · " + StretchText.clock(s.left()) + " left";
        text(dc, 0.875, _labelFont, GRAY, foot);

        Lib.Cues.draw(dc, Lib.Cues.START, "PAUSE", _labelFont, WHITE, WHITE);
        Lib.Cues.draw(dc, Lib.Cues.BACK, p == PH_SETUP ? "GO NOW" : "SKIP", _labelFont, FAR, GRAY);
        if (p == PH_HOLD || p == PH_DEEPEN || p == PH_REPS || p == PH_BREATHE) {
            Lib.Cues.draw(dc, Lib.Cues.UP, "+10 s", _labelFont, FAR, GRAY);
        }
        if (p == PH_EASE || p == PH_HOLD || p == PH_PUSH || p == PH_RELAX || p == PH_DEEPEN) {
            // it hurts: out of the stretch, gently
            Lib.Cues.draw(dc, Lib.Cues.DOWN, "EASE OFF", _labelFont, FAR, GRAY);
        }
    }

    // " · hold 30 s" or " · 10 reps"
    private function doseWords(s as StretchSession) as String {
        var kind = s.kind();
        if (kind == StretchSession.KIND_REPS) {
            return " · " + s.repCount() + " reps";
        }
        if (kind == StretchSession.KIND_BREATH) {
            return " · breathe " + s.holdMs() / 1000 + " s";
        }
        return " · hold " + s.holdMs() / 1000 + " s";
    }

    private function drawDone(dc as Dc) as Void {
        text(dc, 0.15, _bandFont, ACCENT, _complete ? "WELL STRETCHED" : "STOPPED");
        text(dc, 0.27, _nameFont, WHITE, StretchRoutines.NAMES[_routine]);
        var steps = StretchData.STEPS[_routine].size() / 3;
        var what = _complete ? StretchText.stretches(steps) : _stepsDone + " of " + steps + " stretches";
        text(dc, 0.36, _lineSmall, GRAY, StretchText.clock(_playedMs) + " · " + what);
        var r = StretchHistory.rows();
        var now = Time.now().value();
        var streak = StretchHistory.streak(now, r);
        text(dc, 0.52, _bigFont, ACCENT, streak.toString());
        text(dc, 0.63, _lineSmall, WHITE, streak == 1 ? "day of stretching" : "days in a row");
        text(dc, 0.72, _labelFont, GRAY, StretchHistory.week(now, r) + " this week");
        var note = _saved ? "Saved to Garmin Connect" : "Not recorded";
        if (_complete && (StretchRoutines.FLAGS[_routine] & StretchSession.RF_PRE) != 0) {
            note = "Now start easy, then build";
        } else if (_complete && StretchHistory.readyForMore(now, r, StretchSettings.levelIndex())) {
            note = "Ready for longer holds: try Deep";
        }
        text(dc, 0.81, _labelFont, GRAY, note);
        Lib.Cues.draw(dc, Lib.Cues.START, "OK", _labelFont, ACCENT, WHITE);
        Lib.Cues.draw(dc, Lib.Cues.BACK, "EXIT", _labelFont, FAR, GRAY);
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
            menu.addItem(new WatchUi.MenuItem("Resume", null, :resume, null));
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
