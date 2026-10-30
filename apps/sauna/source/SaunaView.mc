import Toybox.ActivityMonitor;
import Toybox.Application.Properties;
import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

enum {
    SCREEN_LIVE,
    SCREEN_ROUNDS,
    SCREEN_RECOVERY,
    SCREEN_HISTORY,
    SCREEN_COUNT
}

// The app: four screens turned with UP and DOWN. START begins a visit and
// later opens the pause menu; LAP (BACK) marks the door by hand when the
// thermometer has not noticed. The live screen is a phase band, the phase
// timer in big digits, and the heart rate, breathing and watch temperature
// along the bottom; the others are the rounds, the recovery chart of the
// last round, and earlier visits.
class SaunaView extends WatchUi.View {

    private const EMBER = 0xFF7A3D;
    private const AMBER = 0xFFB020;
    private const BLUE = 0x2F8FD6;
    private const RED = 0xD0021B;
    private const WHITE = 0xF2F2F2;
    private const GRAY = 0x8A8A8A;
    private const DIM = 0x4A4A4A;
    private const HISTORY_FALLBACK_EVERY = 10;   // seconds between SensorHistory reads for the temperature

    private var _tracker as SaunaTracker? = null;
    private var _recorder as SaunaRecorder = new SaunaRecorder();
    private var _timer as Timer.Timer? = null;
    private var _screen as Number = SCREEN_LIVE;
    private var _paused as Boolean = false;
    private var _startUnix as Number = 0;
    private var _hr as Number? = null;          // the latest readings, recording or not
    private var _temp as Float? = null;
    private var _breath as Number? = null;
    private var _sinceHistory as Number = HISTORY_FALLBACK_EVERY;
    private var _message as String? = null;     // "Saved", shown for a few seconds
    private var _messageTicks as Number = 0;
    private var _meditation as Boolean = true;
    private var _settingsLoaded as Boolean = false;

    private var _bandFont as FontType = Graphics.FONT_XTINY;
    private var _bigFont as FontType = Graphics.FONT_NUMBER_HOT;
    private var _mediumFont as FontType = Graphics.FONT_MEDIUM;
    private var _smallFont as FontType = Graphics.FONT_XTINY;
    private var _tinyFont as FontType = Graphics.FONT_XTINY;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        var h = dc.getHeight();
        _bandFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.05).toNumber(), Graphics.FONT_XTINY);
        _bigFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.24).toNumber(), Graphics.FONT_NUMBER_HOT);
        _mediumFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.085).toNumber(), Graphics.FONT_MEDIUM);
        _smallFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.048).toNumber(), Graphics.FONT_XTINY);
        _tinyFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.04).toNumber(), Graphics.FONT_XTINY);
    }

    function onShow() as Void {
        if (!_settingsLoaded) {
            reloadSettings();
        }
        if (Toybox has :Sensor) {
            Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE] as Array<Sensor.SensorType>);
            Sensor.enableSensorEvents(method(:onSensor));
        }
        if (_tracker != null && !_paused) {
            startTimer();
        }
    }

    function onHide() as Void {
        stopTimer();
        if (Toybox has :Sensor) {
            Sensor.enableSensorEvents(null);
        }
    }

    private function startTimer() as Void {
        if (_timer == null) {
            var timer = new Timer.Timer();
            timer.start(method(:onTick), 1000, true);
            _timer = timer;
        }
    }

    private function stopTimer() as Void {
        var timer = _timer;
        if (timer != null) {
            timer.stop();
            _timer = null;
        }
    }

    // Settings from the phone, with the defaults when a value is missing or odd
    function reloadSettings() as Void {
        _settingsLoaded = true;
        var t = _tracker;
        _meditation = numberSetting("ActivityType", 0) == 0;
        if (t == null) {
            return;
        }
        applySettings(t);
    }

    function applySettings(t as SaunaTracker) as Void {
        t.auto = boolSetting("AutoRounds", true);
        t.enterRate = clampF(floatSetting("EnterRate", 1.5), 0.2, 10.0);
        t.leaveRate = clampF(floatSetting("LeaveRate", 1.0), 0.2, 10.0);
        t.roundTarget = clamp(numberSetting("RoundTarget", 15), 0, 60) * 60;
        t.breakTarget = clamp(numberSetting("BreakTarget", 10), 0, 60) * 60;
        t.goal = clamp(numberSetting("RoundsGoal", 3), 1, 12);
        t.hotTemp = clamp(numberSetting("HotWatch", 50), 40, 80).toFloat();
    }

    private function numberSetting(key as String, fallback as Number) as Number {
        try {
            var v = Properties.getValue(key);
            if (v instanceof Number) {
                return v;
            }
            if (v instanceof Float) {
                return v.toNumber();
            }
        } catch (e) {
        }
        return fallback;
    }

    private function floatSetting(key as String, fallback as Float) as Float {
        try {
            var v = Properties.getValue(key);
            if (v instanceof Float) {
                return v;
            }
            if (v instanceof Number) {
                return v.toFloat();
            }
        } catch (e) {
        }
        return fallback;
    }

    private function boolSetting(key as String, fallback as Boolean) as Boolean {
        try {
            var v = Properties.getValue(key);
            if (v instanceof Boolean) {
                return v;
            }
        } catch (e) {
        }
        return fallback;
    }

    private function clamp(v as Number, lo as Number, hi as Number) as Number {
        return v < lo ? lo : (v > hi ? hi : v);
    }

    private function clampF(v as Float, lo as Float, hi as Float) as Float {
        return v < lo ? lo : (v > hi ? hi : v);
    }

    // ---- readings ----

    // Once a second from the watch while the view is on screen
    function onSensor(info as Sensor.Info) as Void {
        var hr = info.heartRate;
        if (hr != null && hr > 0) {
            _hr = hr;
        } else if (hr == 0) {
            _hr = null;
        }
        var temp = info.temperature;
        if (temp != null) {
            _temp = temp;
            _sinceHistory = 0;
        }
        if (_tracker == null) {
            WatchUi.requestUpdate();
        }
    }

    // The thermometer's last stored reading, when the live one stays away
    private function pollTemperature() as Void {
        _sinceHistory += 1;
        if (_sinceHistory < HISTORY_FALLBACK_EVERY) {
            return;
        }
        _sinceHistory = 0;
        if (!(Toybox has :SensorHistory) || !(SensorHistory has :getTemperatureHistory)) {
            return;
        }
        try {
            var it = SensorHistory.getTemperatureHistory({:period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST});
            var sample = it.next();
            if (sample != null) {
                var v = sample.data;
                if (v instanceof Float) {
                    _temp = v;
                } else if (v instanceof Number) {
                    _temp = v.toFloat();
                }
            }
        } catch (e) {
        }
    }

    private function pollBreathing() as Void {
        if (!(Toybox has :ActivityMonitor)) {
            return;
        }
        var info = ActivityMonitor.getInfo();
        if (info has :respirationRate) {
            var r = info.respirationRate;
            _breath = (r != null && r > 0) ? r : null;
        }
    }

    // ---- the visit ----

    function recording() as Boolean {
        return _tracker != null;
    }

    function paused() as Boolean {
        return _paused;
    }

    function tracker() as SaunaTracker? {
        return _tracker;
    }

    // Begin a visit; `record` false keeps the FIT file out of it (tests)
    function start(record as Boolean) as Void {
        if (_tracker != null) {
            return;
        }
        var t = new SaunaTracker();
        applySettings(t);
        _tracker = t;
        _paused = false;
        _startUnix = Time.now().value();
        _message = null;
        _screen = SCREEN_LIVE;
        if (record) {
            if (!_recorder.start(_meditation)) {
                say("Not recording a FIT file");
            }
        }
        startTimer();
        buzz([new Attention.VibeProfile(80, 300)] as Array<Attention.VibeProfile>);
    }

    // Once a second while recording and not paused
    function onTick() as Void {
        var t = _tracker;
        if (t == null || _paused) {
            return;
        }
        pollTemperature();
        pollBreathing();
        var event = t.tick(_hr, _temp);
        _recorder.record(t.temp, t.phase);
        if (event == EVENT_ENTER) {
            _recorder.lap(t.previous());
            buzz([new Attention.VibeProfile(100, 250), new Attention.VibeProfile(0, 150), new Attention.VibeProfile(100, 250)] as Array<Attention.VibeProfile>);
            _screen = SCREEN_LIVE;
        } else if (event == EVENT_LEAVE) {
            _recorder.lap(null);
            buzz([new Attention.VibeProfile(100, 500)] as Array<Attention.VibeProfile>);
            _screen = SCREEN_LIVE;
        } else if (event == EVENT_ROUND_TARGET) {
            buzz([new Attention.VibeProfile(100, 900)] as Array<Attention.VibeProfile>);
        } else if (event == EVENT_BREAK_TARGET) {
            buzz([new Attention.VibeProfile(100, 300), new Attention.VibeProfile(0, 200), new Attention.VibeProfile(100, 300)] as Array<Attention.VibeProfile>);
        } else if (event == EVENT_HOT) {
            buzz([new Attention.VibeProfile(100, 150), new Attention.VibeProfile(0, 100), new Attention.VibeProfile(100, 150), new Attention.VibeProfile(0, 100), new Attention.VibeProfile(100, 150)] as Array<Attention.VibeProfile>);
        }
        if (_message != null) {
            _messageTicks -= 1;
            if (_messageTicks <= 0) {
                _message = null;
            }
        }
        WatchUi.requestUpdate();
    }

    // LAP: the door, by hand
    function mark() as Void {
        var t = _tracker;
        if (t == null || _paused) {
            return;
        }
        var event = t.mark();
        if (event == EVENT_ENTER) {
            _recorder.lap(t.previous());
            buzz([new Attention.VibeProfile(100, 250), new Attention.VibeProfile(0, 150), new Attention.VibeProfile(100, 250)] as Array<Attention.VibeProfile>);
        } else {
            _recorder.lap(null);
            buzz([new Attention.VibeProfile(100, 500)] as Array<Attention.VibeProfile>);
        }
        _screen = SCREEN_LIVE;
        WatchUi.requestUpdate();
    }

    function pause() as Void {
        if (_tracker == null || _paused) {
            return;
        }
        _paused = true;
        stopTimer();
        _recorder.pause();
    }

    function resume() as Void {
        if (_tracker == null || !_paused) {
            return;
        }
        _paused = false;
        _recorder.resume();
        startTimer();
        WatchUi.requestUpdate();
    }

    // Keep the visit: the FIT file and the history row
    function save() as Void {
        var t = _tracker;
        if (t == null) {
            return;
        }
        var saved = _recorder.save(t);
        if (t.roundCount() > 0 || t.now >= 60) {
            SaunaHistory.add(t.historyRow(_startUnix));
        }
        finish(saved ? "Saved to Garmin Connect" : "Saved on the watch");
    }

    function discard() as Void {
        if (_tracker == null) {
            return;
        }
        _recorder.discard();
        finish("Discarded");
    }

    private function finish(message as String) as Void {
        stopTimer();
        _tracker = null;
        _paused = false;
        _screen = SCREEN_LIVE;
        say(message);
        WatchUi.requestUpdate();
    }

    private function say(message as String) as Void {
        _message = message;
        _messageTicks = 4;
    }

    // The app is closing: keep a visit in progress rather than lose it
    function shutdown() as Void {
        if (_tracker != null) {
            save();
        }
        stopTimer();
    }

    private function buzz(pattern as Array<Attention.VibeProfile>) as Void {
        if ((Toybox has :Attention) && (Attention has :vibrate)) {
            Attention.vibrate(pattern);
        }
    }

    // ---- screens ----

    function screen() as Number {
        return _screen;
    }

    function nextScreen() as Void {
        _screen = (_screen + 1) % SCREEN_COUNT;
    }

    function previousScreen() as Void {
        _screen = (_screen + SCREEN_COUNT - 1) % SCREEN_COUNT;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (_screen == SCREEN_ROUNDS) {
            drawRounds(dc);
        } else if (_screen == SCREEN_RECOVERY) {
            drawRecovery(dc);
        } else if (_screen == SCREEN_HISTORY) {
            drawHistory(dc);
        } else {
            drawLive(dc);
        }
        drawCues(dc);
    }

    // ---- button cues ----

    // What each button does right now, as a short arc on the bezel beside
    // the button and a word inside it. The angles (clockwise from twelve)
    // are where Garmin's own button hints sit on the fenix 8 family, from
    // the device personality files: START 58, BACK 123, DOWN 237, UP 270.
    private const CUE_START = 58;
    private const CUE_BACK = 123;
    private const CUE_DOWN = 237;
    private const CUE_UP = 270;
    private const CUE_SPAN = 11;   // half the arc, in degrees

    private const SCREEN_NAMES = ["LIVE", "ROUNDS", "CHART", "VISITS"] as Array<String>;

    // The word by the START button
    function startCue() as String {
        return _tracker == null ? "START" : "MENU";
    }

    // The word by the BACK button
    function backCue() as String {
        var t = _tracker;
        if (t == null) {
            return "EXIT";
        }
        return t.phase == PHASE_SAUNA ? "OUT" : "IN";
    }

    private function drawCues(dc as Dc) as Void {
        var t = _tracker;
        var backColour = t == null ? GRAY : (t.phase == PHASE_SAUNA ? BLUE : EMBER);
        drawCue(dc, CUE_START, startCue(), WHITE, WHITE);
        drawCue(dc, CUE_BACK, backCue(), backColour, backColour);
        drawCue(dc, CUE_UP, SCREEN_NAMES[(_screen + SCREEN_COUNT - 1) % SCREEN_COUNT], DIM, GRAY);
        drawCue(dc, CUE_DOWN, SCREEN_NAMES[(_screen + 1) % SCREEN_COUNT], DIM, GRAY);
    }

    private function drawCue(dc as Dc, angle as Number, label as String, arcColour as Number, textColour as Number) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var r = (w < h ? w : h) / 2;
        // drawArc counts degrees anticlockwise from three o'clock
        var from = 90 - angle - CUE_SPAN;
        dc.setColor(arcColour, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth((h * 0.014).toNumber() + 2);
        dc.drawArc(cx, cy, r - 3, Graphics.ARC_COUNTER_CLOCKWISE, from, from + 2 * CUE_SPAN);
        dc.setPenWidth(1);
        // the word sits just inside the arc; the left ones a little further in, the screen is narrower there
        var inset = angle > 180 ? 0.085 : 0.065;
        var radius = r - (h * inset).toNumber();
        var rad = Math.toRadians(angle);
        var x = cx + (radius * Math.sin(rad)).toNumber();
        var y = cy - (radius * Math.cos(rad)).toNumber();
        dc.setColor(textColour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, _tinyFont, label, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawLive(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var centre = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var t = _tracker;

        if (t == null) {
            dc.setColor(EMBER, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.14).toNumber(), _bandFont, "SAUNA", centre);
            var message = _message;
            dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
            if (message != null) {
                dc.drawText(cx, (h * 0.40).toNumber(), _mediumFont, message, centre);
            } else {
                dc.drawText(cx, (h * 0.40).toNumber(), _mediumFont, "Press START", centre);
            }
            var row = SaunaHistory.last();
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.52).toNumber(), _smallFont, row == null ? "No visits yet" : "Last: " + SaunaText.headline(row), centre);
            dc.drawText(cx, (h * 0.59).toNumber(), _tinyFont, row == null ? "LAP marks the door, or let the watch notice" : SaunaText.detail(row), centre);
            drawReadings(dc, _hr, _temp, _breath, (h * 0.78).toNumber());
            return;
        }

        // the band
        var bandH = (h * 0.2).toNumber();
        var bandColour = DIM;
        var bandText = "READY · LAP OR WALK IN";
        var textColour = WHITE;
        if (t.hot) {
            bandColour = RED;
            var temp = t.temp;
            bandText = "WATCH HOT" + (temp == null ? "" : " · " + Lib.Fmt.temperature(temp));
        } else if (t.phase == PHASE_SAUNA) {
            bandColour = EMBER;
            bandText = "SAUNA · ROUND " + t.roundCount() + " OF " + t.goal;
            textColour = Graphics.COLOR_BLACK;
        } else if (t.phase == PHASE_BREAK) {
            bandColour = BLUE;
            bandText = "BREAK · AFTER ROUND " + t.roundCount();
            textColour = Graphics.COLOR_BLACK;
        }
        dc.setColor(bandColour, bandColour);
        dc.fillRectangle(0, 0, w, bandH);
        dc.setColor(textColour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (bandH * 0.62).toNumber(), _bandFont, bandText, centre);
        if (_paused) {
            dc.setColor(AMBER, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.26).toNumber(), _smallFont, "PAUSED", centre);
        }

        // the phase timer
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.43).toNumber(), _bigFont, SaunaText.clock(t.phaseSeconds()), centre);
        var target = t.phase == PHASE_SAUNA ? t.roundTarget : (t.phase == PHASE_BREAK ? t.breakTarget : 0);
        var line = "total " + SaunaText.clock(t.now);
        if (target > 0 && t.phase != PHASE_ARRIVAL) {
            line = "of " + SaunaText.clock(target) + " · " + line;
        }
        if (t.phase == PHASE_BREAK) {
            var last = t.lastDone();
            if (last != null && last.drop1 != null) {
                line = SaunaText.drop(last.drop1) + " in 1 min · " + line;
            }
        }
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.585).toNumber(), _smallFont, line, centre);

        drawReadings(dc, _hr, t.temp, _breath, (h * 0.78).toNumber());
    }

    // Heart rate, breathing and the watch temperature in three columns
    private function drawReadings(dc as Dc, hr as Number?, temp as Float?, breath as Number?, y as Number) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var centre = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var columns = [(w * 0.26).toNumber(), (w * 0.5).toNumber(), (w * 0.74).toNumber()] as Array<Number>;
        var values = [hr == null ? "--" : hr.toString(),
                      breath == null ? "--" : breath.toString(),
                      temp == null ? "--" : Lib.Fmt.temperature(temp)] as Array<String>;
        var labels = ["bpm", "breaths", "watch"] as Array<String>;
        var colours = [RED, GRAY, (temp != null && _tracker != null && (_tracker as SaunaTracker).hot) ? RED : AMBER] as Array<Number>;
        for (var i = 0; i < 3; i++) {
            dc.setColor(colours[i], Graphics.COLOR_TRANSPARENT);
            dc.drawText(columns[i], y, _mediumFont, values[i], centre);
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(columns[i], y + (h * 0.07).toNumber(), _tinyFont, labels[i], centre);
        }
    }

    private function drawRounds(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var centre = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var t = _tracker;
        dc.setColor(EMBER, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.12).toNumber(), _bandFont, "ROUNDS", centre);
        if (t == null || t.roundCount() == 0) {
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.45).toNumber(), _smallFont, t == null ? "No visit in progress" : "No round yet", centre);
            return;
        }
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.21).toNumber(), _smallFont,
            SaunaText.clock(t.saunaSeconds()) + " in heat · " + SaunaText.clock(t.breakSeconds()) + " out", centre);
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.29).toNumber(), _tinyFont, "round    time    max bpm    1 min", centre);
        var first = t.roundCount() > 7 ? t.roundCount() - 7 : 0;
        var y = (h * 0.36).toNumber();
        var step = (h * 0.065).toNumber();
        var cols = [(w * 0.22).toNumber(), (w * 0.40).toNumber(), (w * 0.60).toNumber(), (w * 0.78).toNumber()] as Array<Number>;
        for (var i = first; i < t.roundCount(); i++) {
            var r = t.rounds[i];
            var live = !r.done();
            dc.setColor(live ? EMBER : WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cols[0], y, _smallFont, (i + 1).toString(), centre);
            dc.drawText(cols[1], y, _smallFont, SaunaText.clock(r.seconds(t.now)), centre);
            dc.drawText(cols[2], y, _smallFont, r.maxHr > 0 ? r.maxHr.toString() : "--", centre);
            dc.drawText(cols[3], y, _smallFont, live ? "" : SaunaText.drop(r.drop1), centre);
            y += step;
        }
        var mt = t.maxTemp;
        if (mt != null) {
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.86).toNumber(), _tinyFont, "watch up to " + Lib.Fmt.temperature(mt), centre);
        }
    }

    // The heart rate through the last finished round and the minutes after it
    private function drawRecovery(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var centre = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var t = _tracker;
        dc.setColor(EMBER, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.12).toNumber(), _bandFont, "RECOVERY", centre);
        var round = t == null ? null : t.lastDone();
        if (t == null || round == null) {
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.45).toNumber(), _smallFont, t == null ? "No visit in progress" : "After the first round", centre);
            return;
        }
        // the trace belongs to the latest entry; it is this round's only while no newer round began
        var trace = t.trace;
        var traceIsThis = t.traceStart == round.start;
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.21).toNumber(), _smallFont,
            "round " + t.roundCount() + " · peak " + (round.peakHr > 0 ? round.peakHr.toString() : "--") + " bpm", centre);
        dc.drawText(cx, (h * 0.29).toNumber(), _smallFont,
            SaunaText.drop(round.drop1) + " in 1 min · " + SaunaText.drop(round.drop2) + " in 2 min", centre);
        if (!traceIsThis || trace.size() < 2) {
            return;
        }
        var left = (w * 0.12).toNumber();
        var right = (w * 0.88).toNumber();
        var top = (h * 0.38).toNumber();
        var bottom = (h * 0.80).toNumber();
        var lo = 1000;
        var hi = 0;
        for (var i = 0; i < trace.size(); i++) {
            var v = trace[i];
            if (v != null) {
                if (v < lo) { lo = v; }
                if (v > hi) { hi = v; }
            }
        }
        if (hi <= lo) {
            return;
        }
        lo -= 5;
        hi += 5;
        var exitX = left + ((right - left) * (round.end as Number - round.start)) / trace.size();
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(exitX, top, exitX, bottom);
        dc.drawText(exitX, bottom + (h * 0.04).toNumber(), _tinyFont, "out", centre);
        dc.setPenWidth(3);
        var px = -1;
        var py = -1;
        var stride = trace.size() / 120 + 1;   // about a hundred segments is plenty
        for (var i = 0; i < trace.size(); i += stride) {
            var v = trace[i];
            if (v == null) {
                px = -1;
                continue;
            }
            var x = left + ((right - left) * i) / trace.size();
            var y = bottom - ((bottom - top) * (v - lo)) / (hi - lo);
            dc.setColor(x < exitX ? EMBER : BLUE, Graphics.COLOR_TRANSPARENT);
            if (px >= 0) {
                dc.drawLine(px, py, x, y);
            }
            px = x;
            py = y;
        }
        dc.setPenWidth(1);
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, top - (h * 0.03).toNumber(), _tinyFont, hi.toString(), Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(left, bottom + (h * 0.03).toNumber(), _tinyFont, lo.toString(), Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawHistory(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var centre = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(EMBER, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.12).toNumber(), _bandFont, "VISITS", centre);
        var n = SaunaHistory.count();
        if (n == 0) {
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.45).toNumber(), _smallFont, "No visits yet", centre);
            return;
        }
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.21).toNumber(), _tinyFont, "date      rounds    in heat    max bpm", centre);
        var y = (h * 0.29).toNumber();
        var step = (h * 0.075).toNumber();
        var cols = [(w * 0.24).toNumber(), (w * 0.47).toNumber(), (w * 0.63).toNumber(), (w * 0.80).toNumber()] as Array<Number>;
        var shown = n < 8 ? n : 8;
        for (var i = 0; i < shown; i++) {
            var row = SaunaHistory.visit(i) as Array<Number>;
            dc.setColor(i == 0 ? WHITE : GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cols[0], y, _smallFont, Lib.Fmt.shortDate(new Time.Moment(row[SaunaHistory.START])), centre);
            dc.drawText(cols[1], y, _smallFont, row[SaunaHistory.ROUNDS].toString(), centre);
            dc.drawText(cols[2], y, _smallFont, SaunaText.minutes(row[SaunaHistory.SAUNA_SEC]), centre);
            dc.drawText(cols[3], y, _smallFont, row[SaunaHistory.MAX_HR] > 0 ? row[SaunaHistory.MAX_HR].toString() : "--", centre);
            y += step;
        }
    }
}

// Buttons: UP and DOWN turn the screens, START starts or opens the menu,
// LAP (BACK) marks the door while recording and leaves the app otherwise.
// Taps do nothing on purpose: wet fingers.
class SaunaDelegate extends WatchUi.BehaviorDelegate {

    private var _view as SaunaView;

    function initialize(view as SaunaView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean {
        _view.nextScreen();
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.previousScreen();
        WatchUi.requestUpdate();
        return true;
    }

    // The behaviours (onSelect, onBack, ...) are offered first; a behaviour
    // that returns false is then delivered raw, as onKey for a button or
    // onTap for a touch. So onSelect declines, onKey acts on the button
    // and onTap swallows the touch: a wet finger starts nothing.
    function onKey(evt as WatchUi.KeyEvent) as Boolean {
        var key = evt.getKey();
        if (key == WatchUi.KEY_ENTER || key == WatchUi.KEY_START) {
            pressStart();
            return true;
        }
        if (key == WatchUi.KEY_LAP) {
            if (_view.recording()) {
                _view.mark();
                return true;
            }
        }
        return false;
    }

    function onSelect() as Boolean {
        return false;
    }

    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    // The START button: a visit, or the menu once one is running
    function pressStart() as Void {
        if (_view.recording()) {
            openMenu();
        } else {
            _view.start(true);
            WatchUi.requestUpdate();
        }
    }

    function onMenu() as Boolean {
        openMenu();
        return true;
    }

    function onBack() as Boolean {
        if (_view.recording()) {
            _view.mark();
            return true;
        }
        return false;
    }

    function openMenu() as Void {
        var menu = new WatchUi.Menu2({:title => "Sauna"});
        if (_view.recording()) {
            _view.pause();
            menu.addItem(new WatchUi.MenuItem("Resume", null, :resume, null));
            menu.addItem(new WatchUi.MenuItem("Save", "keep the visit", :save, null));
            menu.addItem(new WatchUi.MenuItem("Discard", "throw it away", :discard, null));
        } else {
            menu.addItem(new WatchUi.MenuItem("Start", "a new visit", :start, null));
            menu.addItem(new WatchUi.MenuItem("Clear visits", "forget the history", :clear, null));
        }
        WatchUi.pushView(menu, new SaunaMenuDelegate(_view), WatchUi.SLIDE_UP);
    }
}

class SaunaMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as SaunaView;

    function initialize(view as SaunaView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :save) {
            _view.save();
        } else if (id == :discard) {
            _view.discard();
        } else if (id == :start) {
            _view.start(true);
        } else if (id == :clear) {
            SaunaHistory.clear();
        } else {
            _view.resume();
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    function onBack() as Void {
        _view.resume();
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
