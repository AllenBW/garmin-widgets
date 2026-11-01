import Toybox.Audio;
import Toybox.Audio.Capture;
import Toybox.Lang;
import Toybox.System;

// Where the microphone driver is
enum {
    MIC_OFF,        // not started yet
    MIC_IDLE,       // waiting to start
    MIC_RUNNING,    // capturing continuously
    MIC_DONE        // left alone until the app is opened again
}

// Everything the driver asks of the microphone. The real one is
// Audio.Capture; the tests give the driver a fake that records each call.
class MicPort {

    function initialize() {
    }

    function state() as Number {
        return Capture.getState();
    }

    function supported(format as Audio.AudioFormat) as Boolean {
        return Capture.isFormatSupported(format);
    }

    function initCapture(callbacks as Capture.Callbacks, settings as Capture.Settings) as Capture.Settings {
        return Capture.initializeAudioCapture(callbacks, settings);
    }

    function start() as Void {
        Capture.start();
    }

    function stop() as Void {
        Capture.stop();
    }
}

// The microphone, made safe for the fēnix 8 (firmware 23.40).
//
// What the watch taught us (2026-10-31): every build that stopped and
// started capture again and again rebooted the whole watch (a firmware
// "RTL Trap", nothing in CIQ_LOG): initialising from inside onComplete,
// and stopping then initialising in the same moment. A restart after a
// stall never brought the sound back either, while closing the app and
// opening it again always did. So:
//
// 1. Capture is initialised and started once when the app opens, and
//    stopped once when it closes. Menus, the demo and calibrating only
//    ignore the data; they never stop the microphone.
// 2. The capture callbacks only note what happened and hand the window
//    on; nothing in them touches the microphone, prints, or may throw
//    out of them. What they noted is logged from tick().
// 3. The microphone is touched only from tick(), once a second, and its
//    state is asked only when the sound seems to have stopped.
// 4. If the sound stops coming, the microphone is stopped and left alone,
//    and the screen says to press BACK and open the app again.
class SoundMic {

    const WINDOW_BYTES = 2048;    // 1024 samples a window
    const NO_DATA = 4;            // seconds without a window before it counts as a stall

    var phase as Number = MIC_OFF;
    var error as String? = null;  // why it was left alone
    var hertz as Number = 8000;
    var starts as Number = 0;     // initialisations since the app opened (one at most)
    var windows as Number = 0;    // windows handed on since the app opened
    var faults as Number = 0;     // errors caught inside onData

    private var _port as MicPort;
    private var _onWindow as Method(bytes as ByteArray, hertz as Number) as Void;
    private var _wait as Number = 0;       // ticks since the phase began
    private var _paused as Boolean = true; // off screen, menu, demo: data is ignored
    private var _since as Number = 0;      // ticks since the last window
    private var _ended as Boolean = false; // onComplete or onError since the start
    private var _stopAsked as Boolean = false;
    private var _captureError as Number? = null;   // from onError, logged by tick()
    private var _fault as String? = null;          // the first error inside onData, logged by tick()

    function initialize(port as MicPort, onWindow as Method(bytes as ByteArray, hertz as Number) as Void) {
        _port = port;
        _onWindow = onWindow;
    }

    // On screen: data is used again; the first start comes on the next tick
    function show() as Void {
        _paused = false;
        _since = 0;
        if (phase == MIC_OFF) {
            enter(MIC_IDLE);
        }
    }

    // A menu, the demo, or calibrating: ignore the data, keep the microphone as it is
    function hide() as Void {
        _paused = true;
    }

    function paused() as Boolean {
        return _paused;
    }

    // Leaving the app: stop the capture, unless that was asked already, then touch nothing
    function exit() as Void {
        _paused = true;
        if (phase == MIC_RUNNING) {
            stop();
        }
        phase = MIC_DONE;
    }

    // Once a second, from the view's timer: the only place the microphone is touched
    function tick() as Void {
        _wait++;
        log();
        if (phase == MIC_RUNNING) {
            if (_paused) {
                _since = 0;   // a menu is not a stall
                return;
            }
            _since++;
            if (_ended || _since > NO_DATA) {
                System.println("sound: no window for " + _since + " s after " + windows + " (ended " + _ended + ", state " + state() + ")");
                leave("The microphone stopped sending sound");
            }
            return;
        }
        // idle: start once, a tick after the app came on screen
        if (phase != MIC_IDLE || _paused || _wait < 1) {
            return;
        }
        if (state() == Capture.CAPTURE_CAPTURING) {
            leave("The microphone is busy");   // never initialise over a capture
            return;
        }
        begin();
    }

    // Capture callbacks: note what happened and hand the window on
    function onData(audioData as ByteArray) as Void {
        if (phase != MIC_RUNNING || _paused) {
            return;
        }
        _since = 0;
        windows++;
        try {
            _onWindow.invoke(audioData, hertz);
        } catch (e) {
            faults++;
            if (_fault == null) {
                var m = e.getErrorMessage();
                _fault = (m == null) ? "?" : m;
            }
        }
    }

    function onComplete() as Void {
        _ended = true;
    }

    function onError(error as Capture.Error) as Void {
        _ended = true;
        _captureError = error;
    }

    // What the callbacks noted, printed outside them
    private function log() as Void {
        var code = _captureError;
        if (code != null) {
            System.println("sound: capture error " + code);
            _captureError = null;
        }
        var fault = _fault;
        if (fault != null && faults > 0) {
            System.println("sound: error reading a window (" + faults + " so far): " + fault);
            _fault = "";
        }
    }

    private function begin() as Void {
        var format = pickFormat();
        if (format == null) {
            leave("Microphone format not supported");
            return;
        }
        starts++;
        _ended = false;
        _since = 0;
        try {
            var settings = _port.initCapture(self, {
                :format => format,
                :windowSize => WINDOW_BYTES,
                :windowFilledBehavior => Capture.WINDOW_FILLED_CONTINUE,
                :filters => [] as Array<Capture.Filter>
            });
            var used = settings[:format];
            if (used != null) {
                hertz = rate(used[:frequency] as Number);
            }
            _port.start();
            enter(MIC_RUNNING);
            System.println("sound: capturing at " + hertz + " Hz, window " + settings[:windowSize] + " B");
        } catch (e) {
            var m = e.getErrorMessage();
            System.println("sound: start failed: " + (m == null ? "?" : m));
            leave("The microphone would not start");
        }
    }

    // Left alone until the app is opened again; a capture still running is stopped once
    private function leave(why as String) as Void {
        if (phase == MIC_RUNNING && state() == Capture.CAPTURE_CAPTURING) {
            stop();
        }
        error = why;
        phase = MIC_DONE;
        System.println("sound: leaving the microphone alone: " + why);
    }

    private function stop() as Void {
        if (_stopAsked) {
            return;
        }
        _stopAsked = true;
        try {
            _port.stop();
        } catch (e) {
        }
    }

    private function enter(p as Number) as Void {
        phase = p;
        _wait = 0;
    }

    private function state() as Number {
        try {
            return _port.state();
        } catch (e) {
            return -1;
        }
    }

    // The lowest rate the watch will take: the fēnix 8 refuses 8 kHz
    private function pickFormat() as Audio.AudioFormat? {
        var rates = [Audio.FREQ_8_KHZ, Audio.FREQ_11_025_KHZ, Audio.FREQ_16_KHZ, Audio.FREQ_22_05_KHZ, Audio.FREQ_44_1_KHZ] as Array<Number>;
        for (var i = 0; i < rates.size(); i++) {
            var format = {
                :containerFormat => Audio.CONTAINER_WAV,
                :codec => Audio.CODEC_LPCM,
                :frequency => rates[i],
                :channels => Audio.CHANNEL_MONO
            } as Audio.AudioFormat;
            try {
                if (_port.supported(format)) {
                    return format;
                }
            } catch (e) {
            }
        }
        return null;
    }

    private function rate(frequency as Number) as Number {
        var table = [8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100] as Array<Number>;
        return (frequency >= 0 && frequency < table.size()) ? table[frequency] : 8000;
    }
}
