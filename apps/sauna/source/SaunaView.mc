import Toybox.ActivityMonitor;
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

// Which cue a touch landed on
enum {
    TAP_NONE,
    TAP_START,
    TAP_BACK,
    TAP_UP,
    TAP_DOWN
}

// The app: four screens turned with UP and DOWN. START picks a sauna or a
// steam room and begins; later it opens the pause menu. LAP (BACK) marks
// the door by hand when the thermometer has not noticed. The live screen
// is a phase band, the phase timer in big digits, the coach's line, and
// the heart rate, breathing and watch temperature along the bottom; the
// others are the rounds, the recovery chart of the last round, and
// earlier visits. Every screen cues what each button does.
class SaunaView extends WatchUi.View {

    private const EMBER = 0xFF7A3D;    // sauna
    private const STEAM = 0x3FA9F5;    // steam room
    private const AMBER = 0xFFB020;
    private const BLUE = 0x6C8EA8;     // a break: cool steel
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
    private var _hrvWindow as HrvWindow = new HrvWindow();
    private var _hrvListening as Boolean = false;
    private var _logHrv as Boolean = true;
    private var _bbStart as Number? = null;     // Body Battery when the visit began

    private var _w as Number = 454;
    private var _h as Number = 454;
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
        _w = dc.getWidth();
        _h = h;
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
            listenForBeats();
        }
    }

    function onHide() as Void {
        stopTimer();
        stopListening();
        if (Toybox has :Sensor) {
            Sensor.enableSensorEvents(null);
        }
    }

    // Beat-to-beat intervals from the wrist, once a second, for the HRV log
    private function listenForBeats() as Void {
        if (_hrvListening || !_logHrv || !(Toybox has :Sensor) || !(Sensor has :registerSensorDataListener)) {
            return;
        }
        try {
            Sensor.registerSensorDataListener(method(:onBeats), {:period => 1, :heartBeatIntervals => {:enabled => true}});
            _hrvListening = true;
        } catch (e) {
            _hrvListening = false;
        }
    }

    private function stopListening() as Void {
        if (_hrvListening && (Toybox has :Sensor)) {
            try {
                Sensor.unregisterSensorDataListener();
            } catch (e) {
            }
        }
        _hrvListening = false;
    }

    function onBeats(data as Sensor.SensorData) as Void {
        var hr = data.heartRateData;
        if (hr != null) {
            var intervals = hr.heartBeatIntervals;
            if (intervals != null) {
                _hrvWindow.add(intervals);
            }
        }
    }

    // Body Battery's latest value from the watch's history; null without one
    private function bodyBattery() as Number? {
        if (!(Toybox has :SensorHistory) || !(SensorHistory has :getBodyBatteryHistory)) {
            return null;
        }
        try {
            var it = SensorHistory.getBodyBatteryHistory({:period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST});
            var sample = it.next();
            if (sample != null) {
                var v = sample.data;
                if (v instanceof Number) {
                    return v;
                }
                if (v instanceof Float) {
                    return v.toNumber();
                }
            }
        } catch (e) {
        }
        return null;
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

    // Settings from the phone
    function reloadSettings() as Void {
        _settingsLoaded = true;
        SaunaSettings.applyUnit();
        _meditation = SaunaSettings.meditation();
        _logHrv = SaunaSettings.logHrv();
        var t = _tracker;
        if (t != null) {
            applySettings(t);
        }
    }

    function applySettings(t as SaunaTracker) as Void {
        t.auto = SaunaSettings.autoRounds();
        t.sensitivity = SaunaSettings.sensitivity();
        t.hotTemp = SaunaSettings.hotTemp();
        t.plan = SaunaSettings.plan(t.plan.kind);
        t.coachHrHigh = SaunaSettings.coachHrHigh();
        t.hrCeiling = SaunaSettings.ceiling();
        t.coachRecovery = SaunaSettings.coachRecovery();
        t.recoveryHr = SaunaSettings.recoveryHr();
        t.coachStand = SaunaSettings.coachStand();
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

    private var _stress as Number? = null;

    private function pollBreathing() as Void {
        if (!(Toybox has :ActivityMonitor)) {
            return;
        }
        var info = ActivityMonitor.getInfo();
        if (info has :respirationRate) {
            var r = info.respirationRate;
            _breath = (r != null && r > 0) ? r : null;
        }
        if (info has :stressScore) {
            var s = info.stressScore;
            _stress = (s != null && s >= 0) ? s : null;
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

    // Begin a visit of one kind, guided by its plan or free; `record` false
    // keeps the FIT file out of it (tests)
    function start(kind as Number, guided as Boolean, record as Boolean) as Void {
        if (_tracker != null) {
            return;
        }
        var t = new SaunaTracker();
        t.plan = new SaunaPlan(kind);
        t.guided = guided;
        applySettings(t);
        t.baselineDrop = SaunaHistory.avgDrop(kind);
        _tracker = t;
        _paused = false;
        _startUnix = Time.now().value();
        _message = null;
        _screen = SCREEN_LIVE;
        _bbStart = record ? bodyBattery() : null;
        _hrvWindow = new HrvWindow();
        if (record) {
            if (!_recorder.start(_meditation, kind, guided)) {
                say("Not recording a FIT file");
            }
            listenForBeats();
        }
        startTimer();
        buzz([new Attention.VibeProfile(80, 300)] as Array<Attention.VibeProfile>);
    }

    function bodyBatteryAtStart() as Number? {
        return _bbStart;
    }

    // Switch between guided and free in the middle of a visit
    function setGuided(guided as Boolean) as Void {
        var t = _tracker;
        if (t != null) {
            t.guided = guided;
        }
    }

    function guided() as Boolean {
        var t = _tracker;
        return t != null && t.guided;
    }

    // Once a second while recording and not paused
    function onTick() as Void {
        var t = _tracker;
        if (t == null || _paused) {
            return;
        }
        pollTemperature();
        pollBreathing();
        var event = t.tickAll(_hr, _temp, _breath, _stress);
        if (t.now % 60 == 0 && _hrvListening) {
            t.hrv = _hrvWindow.value();
            _hrvWindow.reset();
        }
        _recorder.record(t.temp, t.phase, t.breath, t.stress, t.now % 60 == 0 ? t.hrv : null);
        if (event == EVENT_ENTER) {
            _recorder.lap(t.previous());
            buzz(pattern([250, 150, 250]));
            _screen = SCREEN_LIVE;
        } else if (event == EVENT_LEAVE) {
            _recorder.lap(null);
            buzz(pattern([500]));
            _screen = SCREEN_LIVE;
        } else if (event == EVENT_ROUND_TARGET) {
            buzz(pattern([900]));
        } else if (event == EVENT_ROUND_OVER) {
            buzz(pattern([600, 200, 600]));
        } else if (event == EVENT_HEAT_CAP) {
            buzz(pattern([500, 200, 500, 200, 500]));
        } else if (event == EVENT_BREAK_TARGET) {
            buzz(pattern([250, 150, 250]));
        } else if (event == EVENT_PLAN_DONE) {
            buzz(pattern([200, 150, 200, 150, 200]));
        } else if (event == EVENT_RECOVERY) {
            buzz(pattern([120]));
        } else if (event == EVENT_HOT) {
            buzz(pattern([150, 100, 150, 100, 150]));
        } else if (event == EVENT_HR_HIGH) {
            buzz(pattern([300, 150, 300, 150, 300]));
        } else if (event == EVENT_NOT_RECOVERED) {
            buzz(pattern([400, 200, 400]));
        }
        if (_message != null) {
            _messageTicks -= 1;
            if (_messageTicks <= 0) {
                _message = null;
            }
        }
        WatchUi.requestUpdate();
    }

    // Buzz lengths in milliseconds, on and off alternately
    private function pattern(ms as Array<Number>) as Array<Attention.VibeProfile> {
        var out = [] as Array<Attention.VibeProfile>;
        for (var i = 0; i < ms.size(); i++) {
            out.add(new Attention.VibeProfile(i % 2 == 0 ? 100 : 0, ms[i]));
        }
        return out;
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
            buzz(pattern([250, 150, 250]));
        } else {
            _recorder.lap(null);
            buzz(pattern([500]));
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
        var bbEnd = _recorder.active() ? bodyBattery() : null;
        var saved = _recorder.save(t, _bbStart, bbEnd);
        if (t.roundCount() > 0 || t.now >= 60) {
            SaunaHistory.add(t.historyRow(_startUnix, _bbStart, bbEnd));
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
        stopListening();
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

    private function buzz(vibes as Array<Attention.VibeProfile>) as Void {
        if ((Toybox has :Attention) && (Attention has :vibrate)) {
            Attention.vibrate(vibes);
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

    private function kindColour(kind as Number) as Number {
        return kind == KIND_STEAM ? STEAM : EMBER;
    }

    private function drawLive(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var centre = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var t = _tracker;

        if (t == null) {
            dc.setColor(EMBER, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.14).toNumber(), _bandFont, "SAUNA · STEAM", centre);
            var message = _message;
            dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.40).toNumber(), _mediumFont, message == null ? "Press START" : message, centre);
            var row = SaunaHistory.last();
            var kind = row == null ? KIND_SAUNA : row[SaunaHistory.KIND];
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.52).toNumber(), _smallFont, row == null ? "sauna or steam room" : "Last: " + SaunaText.headline(row), centre);
            dc.drawText(cx, (h * 0.59).toNumber(), _tinyFont, SaunaText.week(SaunaSettings.plan(kind)), centre);
            drawReadings(dc, _hr, _temp, _breath, (h * 0.78).toNumber());
            return;
        }

        // the band
        var bandH = (h * 0.2).toNumber();
        var bandColour = DIM;
        var bandText = "READY · " + SaunaText.kindUpper(t.plan.kind);
        var textColour = WHITE;
        if (t.hot) {
            bandColour = RED;
            var temp = t.temp;
            bandText = "WATCH HOT" + (temp == null ? "" : " · " + SaunaText.temp(temp));
        } else if (t.phase == PHASE_SAUNA) {
            bandColour = kindColour(t.plan.kind);
            bandText = SaunaText.kindUpper(t.plan.kind) + " · ROUND " + t.roundCount() + (t.guided ? " OF " + t.plan.rounds : "");
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

        // the phase timer, the coach, the sums
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.43).toNumber(), _bigFont, SaunaText.clock(t.phaseSeconds()), centre);
        dc.setColor(t.hot ? RED : WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.585).toNumber(), _smallFont, t.coach(), centre);
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.655).toNumber(), _tinyFont,
            "total " + SaunaText.clock(t.now) + " · heat " + SaunaText.clock(t.saunaSeconds()) + " · out " + SaunaText.clock(t.breakSeconds()), centre);

        drawReadings(dc, _hr, t.temp, _breath, (h * 0.78).toNumber());
    }

    // Heart rate, breathing and the watch temperature in three columns
    private function drawReadings(dc as Dc, hr as Number?, temp as Float?, breath as Number?, y as Number) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var centre = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var t = _tracker;
        var columns = [(w * 0.26).toNumber(), (w * 0.5).toNumber(), (w * 0.74).toNumber()] as Array<Number>;
        var values = [hr == null ? "--" : hr.toString(),
                      breath == null ? "--" : breath.toString(),
                      temp == null ? "--" : SaunaText.temp(temp)] as Array<String>;
        var labels = ["bpm", "breaths", "watch " + SaunaText.unit()] as Array<String>;
        var colours = [RED, GRAY, (t != null && t.hot) ? RED : AMBER] as Array<Number>;
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
        dc.setColor(t == null ? EMBER : kindColour(t.plan.kind), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.12).toNumber(), _bandFont, t == null ? "ROUNDS" : "ROUNDS · " + SaunaText.kindUpper(t.plan.kind), centre);
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
            dc.setColor(live ? kindColour(t.plan.kind) : WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cols[0], y, _smallFont, (i + 1).toString(), centre);
            dc.drawText(cols[1], y, _smallFont, SaunaText.clock(r.seconds(t.now)), centre);
            dc.drawText(cols[2], y, _smallFont, r.maxHr > 0 ? r.maxHr.toString() : "--", centre);
            dc.drawText(cols[3], y, _smallFont, live ? "" : SaunaText.drop(r.drop1), centre);
            y += step;
        }
        var mt = t.maxTemp;
        var foot = mt == null ? "" : "watch up to " + SaunaText.temp(mt);
        var bb = _bbStart;
        if (bb != null) {
            foot += (foot.length() > 0 ? " · " : "") + "Body Battery " + bb + " at start";
        }
        if (foot.length() > 0) {
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.86).toNumber(), _tinyFont, foot, centre);
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
        var heat = kindColour(t.plan.kind);
        // the trace belongs to the latest entry; it is this round's only while no newer round began
        var trace = t.trace;
        var traceIsThis = t.traceStart == round.start;
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.21).toNumber(), _smallFont,
            "round " + t.roundCount() + " · peak " + (round.peakHr > 0 ? round.peakHr.toString() : "--") + " bpm", centre);
        var line = SaunaText.drop(round.drop1) + " in 1 min · " + SaunaText.drop(round.drop2) + " in 2 min";
        var base = t.baselineDrop;
        if (base != null && base > 0) {
            line += " · usual " + base;
        }
        var hrv = t.hrv;
        if (hrv != null) {
            line += " · HRV " + hrv + " ms";
        }
        dc.drawText(cx, (h * 0.29).toNumber(), _smallFont, line, centre);
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
            dc.setColor(x < exitX ? heat : BLUE, Graphics.COLOR_TRANSPARENT);
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
        // the legend: the date is coloured by the kind
        dc.setColor(EMBER, Graphics.COLOR_TRANSPARENT);
        dc.drawText((w * 0.40).toNumber(), (h * 0.20).toNumber(), _tinyFont, "sauna", centre);
        dc.setColor(STEAM, Graphics.COLOR_TRANSPARENT);
        dc.drawText((w * 0.60).toNumber(), (h * 0.20).toNumber(), _tinyFont, "steam", centre);
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.27).toNumber(), _tinyFont, "date      rounds    in heat    max bpm", centre);
        var y = (h * 0.34).toNumber();
        var step = (h * 0.07).toNumber();
        var cols = [(w * 0.24).toNumber(), (w * 0.47).toNumber(), (w * 0.63).toNumber(), (w * 0.80).toNumber()] as Array<Number>;
        var shown = n < 7 ? n : 7;
        for (var i = 0; i < shown; i++) {
            var row = SaunaHistory.visit(i) as Array<Number>;
            dc.setColor(kindColour(row[SaunaHistory.KIND]), Graphics.COLOR_TRANSPARENT);
            dc.drawText(cols[0], y, _smallFont, Lib.Fmt.shortDate(new Time.Moment(row[SaunaHistory.START])), centre);
            dc.setColor(i == 0 ? WHITE : GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cols[1], y, _smallFont, row[SaunaHistory.ROUNDS].toString(), centre);
            dc.drawText(cols[2], y, _smallFont, SaunaText.minutes(row[SaunaHistory.SAUNA_SEC]), centre);
            dc.drawText(cols[3], y, _smallFont, row[SaunaHistory.MAX_HR] > 0 ? row[SaunaHistory.MAX_HR].toString() : "--", centre);
            y += step;
        }
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

    // The word by the START button: a visit, or the menu that ends one
    function startCue() as String {
        return _tracker == null ? "START" : "END";
    }

    // Which cue a touch at (x, y) landed on: near the bezel and within
    // thirty degrees of a cue's angle, so the corners act as the buttons
    function cueAt(x as Number, y as Number) as Number {
        var cx = _w / 2;
        var cy = _h / 2;
        var r = (_w < _h ? _w : _h) / 2;
        var dx = (x - cx).toFloat();
        var dy = (y - cy).toFloat();
        if (Math.sqrt(dx * dx + dy * dy) < r * 0.55) {
            return TAP_NONE;
        }
        var angle = Math.toDegrees(Math.atan2(dx, -dy)).toFloat();
        if (angle < 0) {
            angle += 360.0;
        }
        var cues = [CUE_START, CUE_BACK, CUE_UP, CUE_DOWN] as Array<Number>;
        var taps = [TAP_START, TAP_BACK, TAP_UP, TAP_DOWN] as Array<Number>;
        var best = TAP_NONE;
        var bestDiff = 30.0;
        for (var i = 0; i < cues.size(); i++) {
            var diff = (angle - cues[i]).abs();
            if (diff > 180.0) {
                diff = 360.0 - diff;
            }
            if (diff < bestDiff) {
                bestDiff = diff;
                best = taps[i];
            }
        }
        return best;
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
        var backColour = t == null ? GRAY : (t.phase == PHASE_SAUNA ? BLUE : kindColour(t.plan.kind));
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
}

// Buttons: UP and DOWN turn the screens, START picks a kind and starts
// or opens the menu, LAP (BACK) marks the door while recording and
// leaves the app otherwise. Taps do nothing on purpose: wet fingers.
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

    // A touch near a cue does what that button does; anywhere else, nothing
    function onTap(evt as WatchUi.ClickEvent) as Boolean {
        var c = evt.getCoordinates();
        var tap = _view.cueAt(c[0], c[1]);
        if (tap == TAP_START) {
            pressStart();
        } else if (tap == TAP_BACK) {
            if (_view.recording()) {
                _view.mark();
            } else {
                System.exit();
            }
        } else if (tap == TAP_UP) {
            onPreviousPage();
        } else if (tap == TAP_DOWN) {
            onNextPage();
        }
        return true;
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

    // The START button: the kind picker, or the menu once a visit is running
    function pressStart() as Void {
        openMenu();
    }

    // The pause menu while recording, Save first since that is how a visit
    // ends; otherwise the selector: guided or free, sauna or steam
    function openMenu() as Void {
        var menu;
        if (_view.recording()) {
            _view.pause();
            menu = new WatchUi.Menu2({:title => "Paused"});
            menu.addItem(new WatchUi.MenuItem("Save", "end and keep the visit", :save, null));
            menu.addItem(new WatchUi.MenuItem("Resume", null, :resume, null));
            if (_view.guided()) {
                menu.addItem(new WatchUi.MenuItem("Switch to free", "no targets, just in and out", :free, null));
            } else {
                menu.addItem(new WatchUi.MenuItem("Switch to guided", "follow the plan from here", :guided, null));
            }
            menu.addItem(new WatchUi.MenuItem("Discard", "throw it away", :discard, null));
        } else {
            menu = new WatchUi.Menu2({:title => "Start"});
            menu.addItem(new WatchUi.MenuItem("Guided sauna", planLine(KIND_SAUNA), :gsauna, null));
            menu.addItem(new WatchUi.MenuItem("Guided steam", planLine(KIND_STEAM), :gsteam, null));
            menu.addItem(new WatchUi.MenuItem("Free sauna", "in and out as you like", :fsauna, null));
            menu.addItem(new WatchUi.MenuItem("Free steam", "in and out as you like", :fsteam, null));
            menu.addItem(new WatchUi.MenuItem("Clear visits", "forget the history", :clear, null));
        }
        WatchUi.pushView(menu, new SaunaMenuDelegate(_view), WatchUi.SLIDE_UP);
    }

    // "15 min × 3 · cool down 15"
    private function planLine(kind as Number) as String {
        var p = SaunaSettings.plan(kind);
        return (p.roundTarget / 60) + " min × " + p.rounds + " · cool down " + (p.breakTarget / 60);
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
        } else if (id == :gsauna) {
            _view.start(KIND_SAUNA, true, true);
        } else if (id == :gsteam) {
            _view.start(KIND_STEAM, true, true);
        } else if (id == :fsauna) {
            _view.start(KIND_SAUNA, false, true);
        } else if (id == :fsteam) {
            _view.start(KIND_STEAM, false, true);
        } else if (id == :free) {
            _view.setGuided(false);
            _view.resume();
        } else if (id == :guided) {
            _view.setGuided(true);
            _view.resume();
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
