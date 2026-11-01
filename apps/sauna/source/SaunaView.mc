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

// The app: four screens turned with UP and DOWN, each with a title band
// across the top and page dots at the foot so a change is obvious. START
// picks a sauna or a steam room and begins; later it opens the pause menu.
// LAP (BACK) marks the door by hand when the thermometer has not noticed.
// Everything is sized for a hot room and steamed-up eyes: the live screen
// is the phase timer in big digits, the coach's line, and the heart rate,
// breathing and watch temperature in large figures along the bottom.
// Every screen cues what each button does.
class SaunaView extends WatchUi.View {

    private const EMBER = 0xFF7A3D;    // sauna
    private const STEAM = 0x3FA9F5;    // steam room
    private const AMBER = 0xFFB020;
    private const BLUE = 0x6C8EA8;     // a break: cool steel
    private const RED = 0xD0021B;
    private const WHITE = 0xF2F2F2;
    private const GRAY = 0x9A9A9A;
    private const DIM = 0x4A4A4A;
    private const BAND = 0x2A2A2A;     // the title band of the quieter screens
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
    private var _stress as Number? = null;
    private var _sinceHistory as Number = HISTORY_FALLBACK_EVERY;
    private var _message as String? = null;     // "Saved", shown for a few seconds
    private var _messageTicks as Number = 0;
    private var _meditation as Boolean = true;
    private var _settingsLoaded as Boolean = false;
    private var _hrvWindow as HrvWindow = new HrvWindow();
    private var _hrvListening as Boolean = false;
    private var _logHrv as Boolean = true;
    private var _bbStart as Number? = null;     // Body Battery when the visit began
    private var _demo as Boolean = false;       // a made-up visit, for looking at the screens

    private var _w as Number = 454;
    private var _h as Number = 454;
    private var _bandFont as FontType = Graphics.FONT_SMALL;        // the title bands
    private var _bigFont as FontType = Graphics.FONT_NUMBER_HOT;    // the phase timer
    private var _valueFont as FontType = Graphics.FONT_NUMBER_MEDIUM;  // the readings
    private var _lineFont as FontType = Graphics.FONT_SMALL;        // the coach, table rows
    private var _labelFont as FontType = Graphics.FONT_XTINY;       // labels, headers, cues

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        var h = dc.getHeight();
        _w = dc.getWidth();
        _h = h;
        _bandFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.062).toNumber(), Graphics.FONT_SMALL);
        _bigFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.27).toNumber(), Graphics.FONT_NUMBER_HOT);
        _valueFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.125).toNumber(), Graphics.FONT_NUMBER_MEDIUM);
        _lineFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.064).toNumber(), Graphics.FONT_SMALL);
        _labelFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.046).toNumber(), Graphics.FONT_XTINY);
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

    // A menu pushed over a running visit hides the view: the visit's clock,
    // the sensors and the beat listener keep going, or the menu's time would
    // be missing from the rounds, the cues and the FIT laps
    function onHide() as Void {
        if (_tracker != null && !_paused) {
            return;
        }
        stopTimer();
        stopListening();
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

    // A made-up visit with made-up history, so every screen can be looked at
    // without a sauna. Nothing is recorded or stored; End demo clears it.
    function startDemo() as Void {
        if (_tracker != null) {
            return;
        }
        SaunaHistory.demoRows = SaunaHistory.demoData();
        var t = new SaunaTracker();
        applySettings(t);
        t.seedDemo();
        _tracker = t;
        _demo = true;
        _paused = false;
        _startUnix = Time.now().value() - t.now;
        _message = null;
        _screen = SCREEN_LIVE;
        _bbStart = 71;
        _hr = 96;
        _temp = 44.6;
        _breath = 14;
        _stress = 48;
        startTimer();
    }

    function demo() as Boolean {
        return _demo;
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
        if (_demo) {
            _hr = 94 + (t.now % 5);
            _temp = 44.6;
            _breath = 14;
            _stress = 48;
        } else {
            pollTemperature();
            pollBreathing();
        }
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
        if (_demo) {
            finish("Demo ended");
            return;
        }
        var bbEnd = _recorder.active() ? bodyBattery() : null;
        var saved = _recorder.save(t, _bbStart, bbEnd);
        if (t.roundCount() > 0 || t.now >= 60) {
            SaunaHistory.add(t.historyRow(_startUnix, _bbStart, bbEnd));
        }
        finish(saved ? "Saved to Connect" : "Saved on the watch");
    }

    function discard() as Void {
        if (_tracker == null) {
            return;
        }
        if (_demo) {
            finish("Demo ended");
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
        _demo = false;
        SaunaHistory.demoRows = null;
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
        drawDots(dc);
        drawCues(dc);
    }

    private function kindColour(kind as Number) as Number {
        return kind == KIND_STEAM ? STEAM : EMBER;
    }

    // The band across the top of every screen: the page's name, or the phase
    private function drawBand(dc as Dc, colour as Number, text as String, textColour as Number) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var bandH = (h * 0.2).toNumber();
        dc.setColor(colour, colour);
        dc.fillRectangle(0, 0, w, bandH);
        dc.setColor(textColour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, (bandH * 0.62).toNumber(), _bandFont, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Four dots at the foot, the current page bright
    private function drawDots(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var gap = (w * 0.04).toNumber();
        var x = w / 2 - gap * (SCREEN_COUNT - 1) / 2;
        var y = (h * 0.945).toNumber();
        for (var i = 0; i < SCREEN_COUNT; i++) {
            dc.setColor(i == _screen ? WHITE : DIM, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(x + i * gap, y, i == _screen ? 5 : 3);
        }
    }

    // A line that must fit: trimmed with an ellipsis rather than running off the round edge
    private function fit(dc as Dc, text as String, font as FontType, width as Number) as String {
        var fitted = Graphics.fitTextToArea(text, font, width, dc.getHeight(), true);
        return fitted == null ? text : fitted;
    }

    private function drawLive(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var centre = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var t = _tracker;

        if (t == null) {
            drawBand(dc, BAND, "SAUNA · STEAM", EMBER);
            var message = _message;
            dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.37).toNumber(), _valueFont, message == null ? "Press START" : fit(dc, message, _valueFont, (w * 0.9).toNumber()), centre);
            var row = SaunaHistory.last();
            var kind = row == null ? KIND_SAUNA : row[SaunaHistory.KIND];
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.52).toNumber(), _lineFont, fit(dc, row == null ? "sauna or steam room" : "Last: " + SaunaText.headline(row), _lineFont, (w * 0.9).toNumber()), centre);
            dc.drawText(cx, (h * 0.60).toNumber(), _labelFont, fit(dc, SaunaText.week(SaunaSettings.plan(kind)), _labelFont, (w * 0.86).toNumber()), centre);
            drawReadings(dc, _hr, _temp, _breath);
            return;
        }

        // the band tells the phase
        if (t.hot) {
            var temp = t.temp;
            drawBand(dc, RED, "WATCH HOT" + (temp == null ? "" : " · " + SaunaText.temp(temp)), WHITE);
        } else if (t.phase == PHASE_SAUNA) {
            drawBand(dc, kindColour(t.plan.kind),
                SaunaText.kindUpper(t.plan.kind) + " · ROUND " + t.roundCount() + (t.guided ? " OF " + t.plan.rounds : ""), Graphics.COLOR_BLACK);
        } else if (t.phase == PHASE_BREAK) {
            drawBand(dc, BLUE, "BREAK · AFTER ROUND " + t.roundCount(), Graphics.COLOR_BLACK);
        } else {
            drawBand(dc, DIM, "READY · " + SaunaText.kindUpper(t.plan.kind), WHITE);
        }
        if (_paused) {
            dc.setColor(AMBER, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.25).toNumber(), _labelFont, "PAUSED", centre);
        }

        // the phase timer and the coach
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.40).toNumber(), _bigFont, SaunaText.clock(t.phaseSeconds()), centre);
        dc.setColor(t.hot || t.hrHigh() ? RED : WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.565).toNumber(), _lineFont, fit(dc, t.coach(), _lineFont, (w * 0.9).toNumber()), centre);

        drawReadings(dc, _hr, t.temp, _breath);
    }

    // Heart rate, breathing and the watch temperature in three big columns
    private function drawReadings(dc as Dc, hr as Number?, temp as Float?, breath as Number?) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var centre = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var t = _tracker;
        var y = (h * 0.735).toNumber();
        var columns = [(w * 0.29).toNumber(), (w * 0.5).toNumber(), (w * 0.71).toNumber()] as Array<Number>;
        var values = [hr == null ? "--" : hr.toString(),
                      breath == null ? "--" : breath.toString(),
                      temp == null ? "--" : SaunaText.temp(temp)] as Array<String>;
        var labels = ["bpm", "breaths", "watch " + SaunaText.unit()] as Array<String>;
        var colours = [RED, GRAY, (t != null && t.hot) ? RED : AMBER] as Array<Number>;
        for (var i = 0; i < 3; i++) {
            dc.setColor(colours[i], Graphics.COLOR_TRANSPARENT);
            dc.drawText(columns[i], y, _valueFont, values[i], centre);
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(columns[i], y + (h * 0.095).toNumber(), _labelFont, labels[i], centre);
        }
    }

    private function drawRounds(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var centre = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var t = _tracker;
        drawBand(dc, BAND, t == null ? "ROUNDS" : "ROUNDS · " + SaunaText.kindUpper(t.plan.kind), t == null ? WHITE : kindColour(t.plan.kind));
        if (t == null || t.roundCount() == 0) {
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.5).toNumber(), _lineFont, t == null ? "No visit yet" : "No round yet", centre);
            return;
        }
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.29).toNumber(), _lineFont, SaunaText.clock(t.saunaSeconds()) + " in · " + SaunaText.clock(t.breakSeconds()) + " out", centre);
        // the table keeps clear of the cues at nine, eight and four o'clock
        var cols = [(w * 0.28).toNumber(), (w * 0.46).toNumber(), (w * 0.63).toNumber(), (w * 0.79).toNumber()] as Array<Number>;
        var heads = ["round", "time", "max", "fall"] as Array<String>;
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        for (var c = 0; c < 4; c++) {
            dc.drawText(cols[c], (h * 0.38).toNumber(), _labelFont, heads[c], centre);
        }
        var first = t.roundCount() > 4 ? t.roundCount() - 4 : 0;
        var y = (h * 0.46).toNumber();
        var step = (h * 0.08).toNumber();
        for (var i = first; i < t.roundCount(); i++) {
            var r = t.rounds[i];
            var live = !r.done();
            dc.setColor(live ? kindColour(t.plan.kind) : WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cols[0], y, _lineFont, (i + 1).toString(), centre);
            dc.drawText(cols[1], y, _lineFont, SaunaText.clock(r.seconds(t.now)), centre);
            dc.drawText(cols[2], y, _lineFont, r.maxHr > 0 ? r.maxHr.toString() : "--", centre);
            dc.drawText(cols[3], y, _lineFont, live ? "" : SaunaText.drop(r.drop1), centre);
            y += step;
        }
        var mt = t.maxTemp;
        var foot = mt == null ? "" : "watch up to " + SaunaText.temp(mt);
        var bb = _bbStart;
        if (bb != null) {
            foot += (foot.length() > 0 ? " · " : "") + "Body Battery " + bb;
        }
        if (foot.length() > 0) {
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.87).toNumber(), _labelFont, fit(dc, foot, _labelFont, (w * 0.8).toNumber()), centre);
        }
    }

    // The heart rate through the last finished round and the minutes after it
    private function drawRecovery(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var centre = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var t = _tracker;
        drawBand(dc, BAND, "RECOVERY", WHITE);
        var round = t == null ? null : t.lastDone();
        if (t == null || round == null) {
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.5).toNumber(), _lineFont, t == null ? "No visit yet" : "After the first round", centre);
            return;
        }
        var heat = kindColour(t.plan.kind);
        // the trace belongs to the latest entry; it is this round's only while no newer round began
        var trace = t.trace;
        var traceIsThis = t.traceStart == round.start;
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.29).toNumber(), _lineFont,
            "Peak " + (round.peakHr > 0 ? round.peakHr.toString() : "--") + " · " + SaunaText.drop(round.drop1) + " in 1 min", centre);
        var line = SaunaText.drop(round.drop2) + " in 2 min";
        var base = t.baselineDrop;
        if (base != null && base > 0) {
            line += " · usual " + base;
        }
        var hrv = t.hrv;
        if (hrv != null) {
            line += " · HRV " + hrv;
        }
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.37).toNumber(), _labelFont, fit(dc, line, _labelFont, (w * 0.86).toNumber()), centre);
        if (!traceIsThis || trace.size() < 2) {
            return;
        }
        // the chart keeps clear of the cues at nine, eight and four o'clock
        var left = (w * 0.23).toNumber();
        var right = (w * 0.77).toNumber();
        var top = (h * 0.46).toNumber();
        var bottom = (h * 0.78).toNumber();
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
        dc.setPenWidth(4);
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
        dc.drawText(left, top, _labelFont, hi.toString(), Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(left, bottom, _labelFont, lo.toString(), Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(exitX, bottom + (h * 0.045).toNumber(), _labelFont, "out", centre);
    }

    private function drawHistory(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var centre = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        drawBand(dc, BAND, "VISITS", WHITE);
        var n = SaunaHistory.count();
        if (n == 0) {
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.5).toNumber(), _lineFont, "No visits yet", centre);
            return;
        }
        // the legend: the date is coloured by the kind
        dc.setColor(EMBER, Graphics.COLOR_TRANSPARENT);
        dc.drawText((w * 0.38).toNumber(), (h * 0.285).toNumber(), _labelFont, "sauna", centre);
        dc.setColor(STEAM, Graphics.COLOR_TRANSPARENT);
        dc.drawText((w * 0.62).toNumber(), (h * 0.285).toNumber(), _labelFont, "steam", centre);
        // the table keeps clear of the cues at nine, eight and four o'clock
        var cols = [(w * 0.30).toNumber(), (w * 0.50).toNumber(), (w * 0.66).toNumber(), (w * 0.80).toNumber()] as Array<Number>;
        var heads = ["date", "rounds", "heat", "max"] as Array<String>;
        dc.setColor(DIM, Graphics.COLOR_TRANSPARENT);
        for (var c = 0; c < 4; c++) {
            dc.drawText(cols[c], (h * 0.36).toNumber(), _labelFont, heads[c], centre);
        }
        var y = (h * 0.44).toNumber();
        var step = (h * 0.085).toNumber();
        var shown = n < 4 ? n : 4;
        for (var i = 0; i < shown; i++) {
            var row = SaunaHistory.visit(i) as Array<Number>;
            dc.setColor(kindColour(row[SaunaHistory.KIND]), Graphics.COLOR_TRANSPARENT);
            dc.drawText(cols[0], y, _lineFont, SaunaText.date(row[SaunaHistory.START]), centre);
            dc.setColor(i == 0 ? WHITE : GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cols[1], y, _lineFont, row[SaunaHistory.ROUNDS].toString(), centre);
            dc.drawText(cols[2], y, _lineFont, SaunaText.minutes(row[SaunaHistory.SAUNA_SEC]), centre);
            dc.drawText(cols[3], y, _lineFont, row[SaunaHistory.MAX_HR] > 0 ? row[SaunaHistory.MAX_HR].toString() : "--", centre);
            y += step;
        }
    }

    // ---- button cues ----

    // What each button does right now, drawn by Lib.Cues beside the
    // button at Garmin's own hint angles for the fenix 8 family.
    private const SCREEN_NAMES = ["LIVE", "ROUNDS", "CHART", "VISITS"] as Array<String>;

    // The word by the START button: a visit, or the menu that ends one
    function startCue() as String {
        return _tracker == null ? "START" : "END";
    }

    // The word by the BACK button
    function backCue() as String {
        var t = _tracker;
        if (t == null) {
            return "EXIT";
        }
        return t.phase == PHASE_SAUNA ? "OUT" : "IN";
    }

    // Which cue a touch at (x, y) landed on: near the bezel and within
    // thirty degrees of a cue's angle, so the corners act as the buttons
    // (TAP_* here match Lib.Cues.TAP_*)
    function cueAt(x as Number, y as Number) as Number {
        return Lib.Cues.at(x, y, _w, _h);
    }

    private function drawCues(dc as Dc) as Void {
        var t = _tracker;
        var backColour = t == null ? GRAY : (t.phase == PHASE_SAUNA ? BLUE : kindColour(t.plan.kind));
        Lib.Cues.draw(dc, Lib.Cues.START, startCue(), _labelFont, WHITE, WHITE);
        Lib.Cues.draw(dc, Lib.Cues.BACK, backCue(), _labelFont, backColour, backColour);
        Lib.Cues.draw(dc, Lib.Cues.UP, SCREEN_NAMES[(_screen + SCREEN_COUNT - 1) % SCREEN_COUNT], _labelFont, DIM, GRAY);
        Lib.Cues.draw(dc, Lib.Cues.DOWN, SCREEN_NAMES[(_screen + 1) % SCREEN_COUNT], _labelFont, DIM, GRAY);
    }
}

// Buttons: UP and DOWN turn the screens, START picks a kind and starts
// or opens the menu, LAP (BACK) marks the door while recording and
// leaves the app otherwise. A touch near a cue does what that button
// does; taps elsewhere do nothing on purpose: wet fingers.
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
    // and onTap maps the touch to a cue.
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
            menu = new WatchUi.Menu2({:title => _view.demo() ? "Demo" : "Paused"});
            if (_view.demo()) {
                menu.addItem(new WatchUi.MenuItem("End demo", "made-up numbers, nothing kept", :discard, null));
                menu.addItem(new WatchUi.MenuItem("Resume", null, :resume, null));
            } else {
                menu.addItem(new WatchUi.MenuItem("Save", "end and keep the visit", :save, null));
                menu.addItem(new WatchUi.MenuItem("Resume", null, :resume, null));
                if (_view.guided()) {
                    menu.addItem(new WatchUi.MenuItem("Switch to free", "no targets, just in and out", :free, null));
                } else {
                    menu.addItem(new WatchUi.MenuItem("Switch to guided", "follow the plan from here", :guided, null));
                }
                menu.addItem(new WatchUi.MenuItem("Discard", "throw it away", :discard, null));
            }
        } else {
            menu = new WatchUi.Menu2({:title => "Start"});
            menu.addItem(new WatchUi.MenuItem("Guided sauna", planLine(KIND_SAUNA), :gsauna, null));
            menu.addItem(new WatchUi.MenuItem("Guided steam", planLine(KIND_STEAM), :gsteam, null));
            menu.addItem(new WatchUi.MenuItem("Free sauna", "in and out as you like", :fsauna, null));
            menu.addItem(new WatchUi.MenuItem("Free steam", "in and out as you like", :fsteam, null));
            menu.addItem(new WatchUi.MenuItem("Demo", "every screen, made-up numbers", :demo, null));
            menu.addItem(new WatchUi.MenuItem("Clear visits", "forget the history", :clear, null));
        }
        WatchUi.pushView(menu, new SaunaMenuDelegate(_view), WatchUi.SLIDE_UP);
    }

    // "3 × 15 min, rest 15": short, the menu cuts long sublabels
    private function planLine(kind as Number) as String {
        var p = SaunaSettings.plan(kind);
        return p.rounds + " × " + (p.roundTarget / 60) + " min, rest " + (p.breakTarget / 60);
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
        } else if (id == :demo) {
            _view.startDemo();
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
