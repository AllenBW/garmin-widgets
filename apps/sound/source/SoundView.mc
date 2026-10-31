import Toybox.Application.Properties;
import Toybox.Attention;
import Toybox.Audio;
import Toybox.Audio.Capture;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

// The pages, turned with UP and DOWN
enum {
    SCREEN_LIVE,
    SCREEN_TREND,
    SCREEN_COUNT
}

// The app: the microphone runs while the app is on screen and every
// window of sound becomes a level; nothing is kept. LIVE is the number,
// big, in the colour of its band, with the danger range under it; TREND
// is the last two minutes; Calibrate (from the menu) adjusts the offset
// with UP and DOWN while showing the live number, for matching a phone
// meter. Every screen cues what each button does.
class SoundView extends WatchUi.View {

    private const GREEN = 0x34C759;
    private const AMBER = 0xFFB020;
    private const ORANGE = 0xFF6A1F;
    private const RED = 0xD0021B;
    private const ACCENT = 0x5AC8FA;
    private const WHITE = 0xF2F2F2;
    private const GRAY = 0x9A9A9A;
    private const DIM = 0x4A4A4A;
    private const BAND = 0x2A2A2A;

    private const WINDOW_BYTES = 12288;  // one shot: 4096 bytes of start-up junk, then about a third of a second at 11 kHz
    private const SKIP_BYTES = 4096;     // what the fēnix 8 hands over first after every initialisation, whatever the room
    private const STRIDE = 4;            // every fourth sample is decoded (HANDOFF.md has the budget)
    private const STALE_AFTER = 3;       // seconds without a window before the number dims
    private const NO_DATA_AFTER = 2;     // seconds without a window before the microphone is restarted
    private const SAVE_EVERY = 10;       // seconds between writes of the last reading for the glance
    private const SCALE_LO = 30;         // the bar and the chart run from here
    private const SCALE_HI = 130;        // to here

    private const SCREEN_NAMES = ["LIVE", "TREND"] as Array<String>;

    private var _session as SoundSession = new SoundSession();
    private var _timer as Timer.Timer? = null;
    private var _screen as Number = SCREEN_LIVE;
    private var _calibrating as Boolean = false;
    private var _demo as Boolean = false;
    private var _demoTicks as Number = 0;
    private var _listening as Boolean = false;
    private var _captureError as String? = null;   // for good: no microphone, no format
    private var _lastError as String? = null;      // the last failed start; retried
    private var _restarts as Number = 0;           // starts in a row that gave no sound
    private var _failures as Number = 0;           // starts in a row that threw
    private const GIVE_UP = 5;                     // silent or failed starts before the microphone is left alone
    private var _sinceStart as Number = 0;         // seconds since the microphone was started
    private var _seen as Number = 0;               // windows received since the app opened
    private var _stopping as Boolean = false;      // a stop is in progress: its flushed window is not a reading
    private var _fresh as Boolean = true;          // the microphone is cold: discard its first moments
    private var _hertz as Number = 8000;
    private var _sinceData as Number = 0;
    private var _sinceSave as Number = 0;
    private var _buzz as Boolean = true;
    private var _settingsLoaded as Boolean = false;

    private var _w as Number = 454;
    private var _h as Number = 454;
    private var _bandFont as FontType = Graphics.FONT_SMALL;
    private var _bigFont as FontType = Graphics.FONT_NUMBER_HOT;
    private var _valueFont as FontType = Graphics.FONT_NUMBER_MEDIUM;
    private var _lineFont as FontType = Graphics.FONT_SMALL;
    private var _statFont as FontType = Graphics.FONT_TINY;
    private var _labelFont as FontType = Graphics.FONT_XTINY;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        var h = dc.getHeight();
        _w = dc.getWidth();
        _h = h;
        _bandFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.062).toNumber(), Graphics.FONT_SMALL);
        _bigFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.25).toNumber(), Graphics.FONT_NUMBER_HOT);
        _valueFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.125).toNumber(), Graphics.FONT_NUMBER_MEDIUM);
        _lineFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.072).toNumber(), Graphics.FONT_SMALL);
        _statFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.056).toNumber(), Graphics.FONT_TINY);
        _labelFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.046).toNumber(), Graphics.FONT_XTINY);
    }

    function onShow() as Void {
        if (!_settingsLoaded) {
            reloadSettings();
        }
        startTimer();
        if (!_demo) {
            listen();
        }
    }

    function onHide() as Void {
        stopTimer();
        hush();
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

    // The settings from the phone: the calibration offset and the buzz
    function reloadSettings() as Void {
        _settingsLoaded = true;
        _session.offset = offsetSetting().toFloat();
        _buzz = true;
        try {
            var v = Properties.getValue("Buzz");
            if (v instanceof Boolean) {
                _buzz = v;
            }
        } catch (e) {
        }
    }

    private function offsetSetting() as Number {
        try {
            var v = Properties.getValue("Calibration");
            if (v instanceof Number && v >= 50 && v <= 130) {
                return v;
            }
            if (v instanceof Float && v >= 50 && v <= 130) {
                return v.toNumber();
            }
        } catch (e) {
        }
        return 90;
    }

    // The lowest rate the watch will capture 16-bit mono at: the fēnix 8
    // refuses 8 kHz and answers a 16 kHz request with 11.025 kHz
    private function pickFormat() as Audio.AudioFormat? {
        var rates = [Audio.FREQ_8_KHZ, Audio.FREQ_11_025_KHZ, Audio.FREQ_16_KHZ, Audio.FREQ_22_05_KHZ, Audio.FREQ_44_1_KHZ] as Array<Number>;
        for (var i = 0; i < rates.size(); i++) {
            var format = {
                :containerFormat => Audio.CONTAINER_WAV,
                :codec => Audio.CODEC_LPCM,
                :frequency => rates[i],
                :channels => Audio.CHANNEL_MONO
            } as Audio.AudioFormat;
            if (Capture.isFormatSupported(format)) {
                return format;
            }
        }
        return null;
    }

    // The microphone, one window at a time: the watch fills a window,
    // stops, hands it to onData, and onComplete starts the next. The
    // fēnix 8 (firmware 23.40) does not deliver windows while capturing
    // continuously: the first log from the watch showed three windows
    // after a start, then nothing, and data only on stop. A start that
    // fails, or that delivers nothing, is retried from the tick; the
    // session discards the first moments after every fresh start.
    private function listen() as Void {
        if (_listening || _captureError != null) {
            return;
        }
        if (!(Toybox has :Audio) || !(Audio has :Capture)) {
            _captureError = "No microphone on this watch";
            return;
        }
        _sinceStart = 0;
        _sinceData = 0;
        if (open("start " + (_restarts + 1))) {
            _listening = true;
            if (_fresh) {
                _session.restarted();
            }
        }
    }

    // Initialise capture for one window and start it; true when it runs.
    // Called for every window on a watch that refuses a plain start()
    // after a one-shot stop, so it logs only the first few times.
    private function open(reason as String) as Boolean {
        try {
            var format = pickFormat();
            if (format == null) {
                _captureError = "Microphone format not supported";
                return false;
            }
            var settings = Capture.initializeAudioCapture(self, {
                :format => format,
                :windowSize => WINDOW_BYTES,
                :windowFilledBehavior => Capture.WINDOW_FILLED_STOP,
                :filters => [] as Array<Capture.Filter>
            });
            var used = settings[:format];
            if (used != null) {
                _hertz = hertz(used[:frequency] as Number);
            }
            _stopping = false;
            Capture.start();
            _lastError = null;
            _failures = 0;
            if (_seen <= 6) {
                System.println("sound: " + reason + ": " + _hertz + " Hz, window " + settings[:windowSize] + " B one shot, state " + Capture.getState());
            }
            return true;
        } catch (e instanceof Capture.InitializationFailedException) {
            _lastError = "Microphone unavailable (" + e.getError() + ")";
            System.println("sound: " + reason + ": " + _lastError);
            failed();
        } catch (e instanceof Lang.Exception) {
            var m = e.getErrorMessage();
            _lastError = "Microphone error" + (m == null ? "" : " (" + m + ")");
            System.println("sound: " + reason + ": " + _lastError);
            failed();
        }
        return false;
    }

    private function failed() as Void {
        _failures++;
        if (_failures >= GIVE_UP) {
            giveUp(_lastError == null ? "Microphone error" : _lastError as String);
        }
    }

    private function hush() as Void {
        if (_listening) {
            _stopping = true;
            try {
                if (Capture.getState() == Capture.CAPTURE_CAPTURING) {
                    Capture.stop();
                }
            } catch (e) {
            }
            _listening = false;
        }
    }

    // No window for a while though the microphone is on: start it again
    private function restart() as Void {
        var state = -1;
        try {
            state = Capture.getState();
        } catch (e) {
        }
        System.println("sound: no window for " + _sinceData + " s, state " + state + ", restarting (" + (_restarts + 1) + ")");
        hush();
        _restarts++;
        _fresh = true;
        if (_restarts >= GIVE_UP) {
            giveUp("The microphone sent no sound");
            return;
        }
        listen();
    }

    // Stop asking the microphone for anything until the app is opened again
    private function giveUp(why as String) as Void {
        hush();
        _captureError = why;
        System.println("sound: giving up: " + why);
        WatchUi.requestUpdate();
    }

    private function hertz(frequency as Number) as Number {
        var table = [8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100] as Array<Number>;
        return (frequency >= 0 && frequency < table.size()) ? table[frequency] : 8000;
    }

    // Capture callbacks (Audio.Capture.Callbacks)
    function onData(audioData as ByteArray) as Void {
        if (_demo || _stopping) {
            return;
        }
        var header = SoundMeter.headerOffset(audioData);
        // the first bytes after every initialisation are not the room:
        // on the watch they read about -13 dBFS whatever the room, and
        // what follows reads like the room, so they are left out
        var offset = header + SKIP_BYTES;
        if (offset >= audioData.size()) {
            offset = header;
        }
        var samples = (audioData.size() - offset) / 2;
        if (samples < 1) {
            return;
        }
        var level = SoundMeter.dbfs(SoundMeter.rms(audioData, offset, STRIDE));
        var gap = _sinceData;
        _sinceData = 0;
        _restarts = 0;
        _fresh = false;
        _seen++;
        if (_seen <= 6 || _seen % 1000 == 0) {
            var skipped = offset > header ? SoundMeter.dbfs(SoundMeter.rmsOf(audioData, header, offset, STRIDE)) : 0.0;
            System.println("sound: window " + _seen + ": " + audioData.size() + " B, header " + header + ", first " + (offset - header) + " B " + skipped.format("%.1f") + " dBFS, rest " + level.format("%.1f") + " dBFS, " + gap + " s since the last");
        }
        var event = _session.addWindow(level, samples.toFloat() / _hertz);
        react(event);
        WatchUi.requestUpdate();
    }

    // An error ends the capture; the tick starts it again. Backgrounded
    // means the watch did not count the app as on screen yet.
    function onError(error as Capture.Error) as Void {
        _listening = false;
        _fresh = true;
        _lastError = error == Capture.CAPTURE_ERR_BACKGROUNDED ? "Microphone not ready" : "Microphone error " + error;
        System.println("sound: " + _lastError);
        WatchUi.requestUpdate();
    }

    // The window has filled and capture stopped on its own. The next
    // window is started by the one-second tick, never from here: opening
    // the microphone several times a second is what took the whole watch
    // down on 2026-10-31, so the meter reads once a second instead.
    function onComplete() as Void {
        _listening = false;
    }

    // Once a second: the chart, the staleness, the demo's own sound, the glance's reading
    function onTick() as Void {
        if (_demo) {
            var db = _session.demoLevel(_demoTicks);
            _demoTicks++;
            for (var i = 0; i < 4; i++) {
                react(_session.addWindow(db - _session.offset, 0.25));
            }
            _sinceData = 0;
        } else {
            _sinceData++;
            _sinceStart++;
            if (_captureError == null) {
                if (!_listening) {
                    listen();
                } else if (_sinceData > NO_DATA_AFTER) {
                    restart();
                }
            }
        }
        _session.tick();
        _sinceSave++;
        if (_sinceSave >= SAVE_EVERY) {
            _sinceSave = 0;
            remember();
        }
        WatchUi.requestUpdate();
    }

    // The buzz as a line is crossed: short for 85, long for 100
    private function react(event as Number) as Void {
        if (!_buzz || event == EVENT_NONE) {
            return;
        }
        if (event == EVENT_LOUD) {
            buzz(pattern([600, 200, 600, 200, 600]));
        } else {
            buzz(pattern([250, 150, 250]));
        }
    }

    private function pattern(ms as Array<Number>) as Array<Attention.VibeProfile> {
        var out = [] as Array<Attention.VibeProfile>;
        for (var i = 0; i < ms.size(); i++) {
            out.add(new Attention.VibeProfile(i % 2 == 0 ? 100 : 0, ms[i]));
        }
        return out;
    }

    private function buzz(vibes as Array<Attention.VibeProfile>) as Void {
        if ((Toybox has :Attention) && (Attention has :vibrate)) {
            Attention.vibrate(vibes);
        }
    }

    // The last reading, for the glance (not the demo's)
    private function remember() as Void {
        var l = _session.level;
        if (l != null && !_demo) {
            SoundStore.save(SoundMeter.whole(l), Time.now().value(), SoundMeter.name(l));
        }
    }

    function shutdown() as Void {
        hush();
        stopTimer();
        remember();
    }

    // The demo: the microphone off, a made-up two minutes behind, and a level that walks the bands
    function startDemo() as Void {
        hush();
        _demo = true;
        _demoTicks = 0;
        _session.seedDemo();
        _captureError = null;
        _screen = SCREEN_LIVE;
        _calibrating = false;
    }

    function endDemo() as Void {
        _demo = false;
        _session.reset();
        listen();
    }

    function demo() as Boolean {
        return _demo;
    }

    function listening() as Boolean {
        return _listening;
    }

    function session() as SoundSession {
        return _session;
    }

    function clearSession() as Void {
        _session.reset();
    }

    // Calibrate: UP and DOWN move the offset a decibel, BACK keeps it
    function calibrate() as Void {
        _calibrating = true;
    }

    function calibrating() as Boolean {
        return _calibrating;
    }

    function adjust(delta as Number) as Void {
        var v = SoundMeter.whole(_session.offset) + delta;
        if (v < 50) { v = 50; }
        if (v > 130) { v = 130; }
        setOffset(v);
    }

    function resetOffset() as Void {
        setOffset(90);
    }

    private function setOffset(v as Number) as Void {
        _session.offset = v.toFloat();
        try {
            Properties.setValue("Calibration", v);
        } catch (e) {
        }
    }

    function finishCalibrate() as Void {
        _calibrating = false;
    }

    function offset() as Number {
        return SoundMeter.whole(_session.offset);
    }

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
        if (_calibrating) {
            drawCalibrate(dc);
        } else if (_screen == SCREEN_TREND) {
            drawTrend(dc);
            drawDots(dc);
        } else {
            drawLive(dc);
            drawDots(dc);
        }
        drawCues(dc);
    }

    // Green under 70, amber to 85, orange to 100, red past it
    function colour(db as Float) as Number {
        if (db < SoundMeter.BUSY) { return GREEN; }
        if (db < SoundMeter.RISK) { return AMBER; }
        if (db < SoundMeter.LOUD) { return ORANGE; }
        return RED;
    }

    // The band across the top of every screen
    private function drawBand(dc as Dc, text as String, textColour as Number) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var bandH = (h * 0.2).toNumber();
        dc.setColor(BAND, BAND);
        dc.fillRectangle(0, 0, w, bandH);
        dc.setColor(textColour, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, (bandH * 0.62).toNumber(), _bandFont, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Two dots at the foot, the current page bright
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

    private function fit(dc as Dc, text as String, font as FontType, width as Number) as String {
        var fitted = Graphics.fitTextToArea(text, font, width, Graphics.getFontHeight(font), true);
        return fitted == null ? text : fitted;
    }

    // Is the number worth believing right now
    private function stale() as Boolean {
        return !_demo && (_sinceData > STALE_AFTER || !_listening);
    }

    // What is going on with the microphone, for under "Listening" or a dim number
    private function waitingText() as String {
        return SoundMeter.waiting(_sinceStart, _restarts, _lastError);
    }

    private function drawLive(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var centre = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        drawBand(dc, _demo ? "DEMO" : "SOUND LEVEL", ACCENT);
        var level = _session.level;
        var error = _captureError;
        if (error != null && !_demo) {
            dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.45).toNumber(), _lineFont, fit(dc, error, _lineFont, (w * 0.8).toNumber()), centre);
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.58).toNumber(), _labelFont, "Demo is in the menu", centre);
            return;
        }
        if (level == null) {
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.39).toNumber(), _valueFont, "Listening", centre);
            dc.drawText(cx, (h * 0.52).toNumber(), _statFont, fit(dc, waitingText(), _statFont, (w * 0.8).toNumber()), centre);
            drawScale(dc, null);
            return;
        }
        var dim = stale();
        var tone = dim ? DIM : colour(level);
        dc.setColor(tone, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.37).toNumber(), _bigFont, SoundMeter.whole(level).toString(), centre);
        dc.setColor(dim ? GRAY : tone, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.52).toNumber(), _lineFont, fit(dc, dim ? waitingText() : SoundMeter.describe(level), _lineFont, (w * 0.84).toNumber()), centre);
        drawScale(dc, level);
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.75).toNumber(), _lineFont, SoundMeter.safeFor(level), centre);
        drawStats(dc, (h * 0.825).toNumber(), (h * 0.885).toNumber());
    }

    // "peak 94 · avg 71 · 4 min" and "dose 12% while open"
    private function drawStats(dc as Dc, y1 as Number, y2 as Number) as Void {
        var cx = dc.getWidth() / 2;
        var centre = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var peak = _session.peak;
        var avg = _session.average();
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y1, _statFont,
            "peak " + (peak == null ? "--" : SoundMeter.whole(peak).toString()) + " · avg " + (avg == null ? "--" : SoundMeter.whole(avg).toString())
            + " · " + SoundMeter.spell(_session.seconds.toNumber()), centre);
        dc.drawText(cx, y2, _statFont, "dose " + doseText() + " while open", centre);
    }

    // The day's dose used so far, to a tenth under one percent
    private function doseText() as String {
        var d = _session.dosePercent;
        if (d < 0.05) {
            return "0%";
        }
        if (d < 10.0) {
            return d.format("%.1f") + "%";
        }
        return SoundMeter.whole(d) + "%";
    }

    // The bar: 30 to 130 dB in the bands' colours up to the level, dim past
    // it, a white mark at the level, the lines at 70, 85, 100 and 120 labelled
    private function drawScale(dc as Dc, level as Float?) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var x0 = (w * 0.17).toNumber();
        var x1 = (w * 0.83).toNumber();
        var y = (h * 0.615).toNumber();
        var thick = (h * 0.045).toNumber();
        var edges = [SCALE_LO, SoundMeter.BUSY, SoundMeter.RISK, SoundMeter.LOUD, SCALE_HI] as Array<Number>;
        var colours = [GREEN, AMBER, ORANGE, RED] as Array<Number>;
        var at = level == null ? SCALE_LO : SoundMeter.whole(level);
        if (at > SCALE_HI) { at = SCALE_HI; }
        if (at < SCALE_LO) { at = SCALE_LO; }
        var fillTo = scaleX(at, x0, x1);
        for (var i = 0; i < colours.size(); i++) {
            var a = scaleX(edges[i], x0, x1);
            var b = scaleX(edges[i + 1], x0, x1);
            dc.setColor(DIM, DIM);
            dc.fillRectangle(a, y - thick / 2, b - a, thick);
            if (fillTo > a) {
                dc.setColor(colours[i], colours[i]);
                dc.fillRectangle(a, y - thick / 2, (fillTo < b ? fillTo : b) - a, thick);
            }
        }
        var marks = [SoundMeter.BUSY, SoundMeter.RISK, SoundMeter.LOUD, SoundMeter.PAIN] as Array<Number>;
        var centre = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        for (var i = 0; i < marks.size(); i++) {
            var x = scaleX(marks[i], x0, x1);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
            dc.fillRectangle(x - 1, y - thick / 2, 2, thick);
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y + thick / 2 + (h * 0.035).toNumber(), _labelFont, marks[i].toString(), centre);
        }
        if (level != null) {
            dc.setColor(WHITE, WHITE);
            dc.fillRectangle(fillTo - 2, y - thick, 4, thick * 2);
        }
    }

    private function scaleX(db as Number, x0 as Number, x1 as Number) as Number {
        return x0 + ((x1 - x0) * (db - SCALE_LO)) / (SCALE_HI - SCALE_LO);
    }

    // The last two minutes, with the 70, 85 and 100 lines across it
    private function drawTrend(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var centre = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        drawBand(dc, "LAST 2 MIN", WHITE);
        var n = _session.trendCount();
        // the chart keeps clear of the cues at nine, eight and four o'clock
        var left = (w * 0.24).toNumber();
        var right = (w * 0.76).toNumber();
        var top = (h * 0.3).toNumber();
        var bottom = (h * 0.76).toNumber();
        var lo = SCALE_LO;
        var hi = SoundMeter.PAIN;
        var guides = [SoundMeter.BUSY, SoundMeter.RISK, SoundMeter.LOUD] as Array<Number>;
        var guideColours = [AMBER, ORANGE, RED] as Array<Number>;
        dc.setPenWidth(1);
        for (var i = 0; i < guides.size(); i++) {
            var y = bottom - ((bottom - top) * (guides[i] - lo)) / (hi - lo);
            dc.setColor(guideColours[i], Graphics.COLOR_TRANSPARENT);
            dc.drawLine(left, y, right, y);
            dc.drawText(left - (w * 0.01).toNumber(), y, _labelFont, guides[i].toString(), Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        }
        var have = 0;
        for (var i = 0; i < n; i++) {
            if (_session.trendAt(i) != null) {
                have++;
            }
        }
        if (have < 2) {
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.53).toNumber(), _lineFont, "Nothing yet", centre);
        } else {
            dc.setPenWidth(3);
            var px = -1;
            var py = -1;
            for (var i = 0; i < n; i++) {
                var v = _session.trendAt(i);
                if (v == null) {
                    px = -1;
                    continue;
                }
                var f = v as Float;
                var clamped = f < lo ? lo.toFloat() : (f > hi ? hi.toFloat() : f);
                var x = right - ((right - left) * (n - 1 - i)) / (SoundMeter.TREND_POINTS - 1);
                var y = bottom - (((bottom - top) * (clamped - lo)) / (hi - lo)).toNumber();
                dc.setColor(colour(f), Graphics.COLOR_TRANSPARENT);
                if (px >= 0) {
                    dc.drawLine(px, py, x, y);
                }
                px = x;
                py = y;
            }
            dc.setPenWidth(1);
        }
        drawStats(dc, (h * 0.825).toNumber(), (h * 0.885).toNumber());
    }

    // The live number again, and the offset under it, for matching a phone meter
    private function drawCalibrate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var centre = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        drawBand(dc, "CALIBRATE", WHITE);
        var level = _session.level;
        if (level == null) {
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.40).toNumber(), _valueFont, "Listening", centre);
            dc.drawText(cx, (h * 0.49).toNumber(), _labelFont, fit(dc, waitingText(), _labelFont, (w * 0.8).toNumber()), centre);
        } else {
            dc.setColor(stale() ? DIM : colour(level), Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, (h * 0.40).toNumber(), _bigFont, SoundMeter.whole(level).toString(), centre);
        }
        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.575).toNumber(), _lineFont, "offset " + offset() + " dB", centre);
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, (h * 0.665).toNumber(), _labelFont, "Match a phone sound meter", centre);
        dc.drawText(cx, (h * 0.715).toNumber(), _labelFont, "UP and DOWN move it a decibel", centre);
        dc.drawText(cx, (h * 0.80).toNumber(), _labelFont, "Not A-weighted, not a certified meter", centre);
    }

    // What each button does right now
    function startCue() as String {
        return _calibrating ? "RESET" : "MENU";
    }

    function backCue() as String {
        return _calibrating ? "DONE" : "EXIT";
    }

    // UP names the page before, DOWN the page after; the first and last
    // pages leave the other side blank (the buttons still wrap round)
    function upCue() as String {
        if (_calibrating) {
            return "+1";
        }
        return _screen > 0 ? SCREEN_NAMES[_screen - 1] : "";
    }

    function downCue() as String {
        if (_calibrating) {
            return "-1";
        }
        return _screen < SCREEN_COUNT - 1 ? SCREEN_NAMES[_screen + 1] : "";
    }

    function cueAt(x as Number, y as Number) as Number {
        return Lib.Cues.at(x, y, _w, _h);
    }

    private function drawCues(dc as Dc) as Void {
        var side = _calibrating ? WHITE : GRAY;
        var sideArc = _calibrating ? WHITE : DIM;
        Lib.Cues.draw(dc, Lib.Cues.START, startCue(), _labelFont, _calibrating ? ACCENT : WHITE, _calibrating ? ACCENT : WHITE);
        Lib.Cues.draw(dc, Lib.Cues.BACK, backCue(), _labelFont, _calibrating ? GREEN : GRAY, _calibrating ? GREEN : GRAY);
        if (!upCue().equals("")) {
            Lib.Cues.draw(dc, Lib.Cues.UP, upCue(), _labelFont, sideArc, side);
        }
        if (!downCue().equals("")) {
            Lib.Cues.draw(dc, Lib.Cues.DOWN, downCue(), _labelFont, sideArc, side);
        }
    }
}

// Buttons: UP and DOWN turn the pages (or move the offset while
// calibrating), START opens the menu (or resets the offset), BACK leaves
// the app (or ends calibrating). A touch near a cue does what that
// button does; taps elsewhere do nothing.
class SoundDelegate extends WatchUi.BehaviorDelegate {

    private var _view as SoundView;

    function initialize(view as SoundView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean {
        if (_view.calibrating()) {
            _view.adjust(-1);
        } else {
            _view.nextScreen();
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        if (_view.calibrating()) {
            _view.adjust(1);
        } else {
            _view.previousScreen();
        }
        WatchUi.requestUpdate();
        return true;
    }

    // The behaviours are offered first; onSelect declines so the raw key
    // reaches onKey, and a touch reaches onTap, where it maps to a cue
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

    function onMenu() as Boolean {
        openMenu();
        return true;
    }

    function onBack() as Boolean {
        if (_view.calibrating()) {
            _view.finishCalibrate();
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }

    function pressStart() as Void {
        if (_view.calibrating()) {
            _view.resetOffset();
            WatchUi.requestUpdate();
        } else {
            openMenu();
        }
    }

    function openMenu() as Void {
        var menu = new WatchUi.Menu2({:title => "Sound Level"});
        if (_view.demo()) {
            menu.addItem(new WatchUi.MenuItem("End demo", "back to the microphone", :enddemo, null));
        } else {
            menu.addItem(new WatchUi.MenuItem("Demo", "every band, made-up numbers", :demo, null));
        }
        menu.addItem(new WatchUi.MenuItem("Calibrate", "match a phone meter", :calibrate, null));
        menu.addItem(new WatchUi.MenuItem("Clear session", "peak, average and dose", :clear, null));
        WatchUi.pushView(menu, new SoundMenuDelegate(_view), WatchUi.SLIDE_UP);
    }
}

class SoundMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as SoundView;

    function initialize(view as SoundView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :demo) {
            _view.startDemo();
        } else if (id == :enddemo) {
            _view.endDemo();
        } else if (id == :calibrate) {
            _view.calibrate();
        } else if (id == :clear) {
            _view.clearSession();
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
