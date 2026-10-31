import Toybox.Audio;
import Toybox.Audio.Capture;
import Toybox.Lang;
import Toybox.System;

// Where the microphone driver is
enum {
    MIC_OFF,        // not started yet
    MIC_IDLE,       // between windows: nothing is capturing
    MIC_RUNNING,    // one window initialised and started, waiting for it
    MIC_STOPPING,   // we asked it to stop, waiting for it to have stopped
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

// The microphone, made safe for the fēnix 8 (firmware 23.40). Two
// patterns crashed the whole watch on 2026-10-31 (a firmware "RTL Trap",
// nothing in CIQ_LOG): initialising capture again from inside its own
// onComplete callback, and stopping it and initialising it again in the
// same moment, every few seconds. So this driver keeps strict rules:
//
// 1. The capture callbacks (onData, onComplete, onError) only note what
//    happened. Nothing in them touches the microphone.
// 2. The microphone is touched only from tick(), once a second, and at
//    most once per tick (plus the stop on hide and on exit).
// 3. A window is initialised only when nothing is capturing, never over
//    a capture still running or still stopping.
// 4. A whole tick passes between the end of a window and the next
//    initialisation, and two after a stop of ours.
// 5. Three silent or failed windows in a row, a stop that does not
//    finish within five seconds, or ten minutes of windows, and the
//    microphone is left alone until the app is opened again.
//
// The watch delivers sound one window per initialisation
// (WINDOW_FILLED_STOP); continuous capture gave three windows and then
// nothing. So the meter reads one window about every two seconds.
class SoundMic {

    const WINDOW_BYTES = 12288;   // about half a second at 11 kHz; the view skips the first 4096
    const NO_DATA = 3;            // seconds a window may run before it is stopped
    const STOP_LIMIT = 5;         // seconds a stop may take before the microphone is left alone
    const GIVE_UP = 3;            // silent or failed windows in a row before it is left alone
    const MAX_WINDOWS = 300;      // windows per opening (about ten minutes), then it rests

    var phase as Number = MIC_OFF;
    var error as String? = null;  // why it was left alone
    var hertz as Number = 11025;
    var windows as Number = 0;    // windows started since the app opened
    var silent as Number = 0;     // silent or failed windows in a row

    private var _port as MicPort;
    private var _onWindow as Method(bytes as ByteArray, hertz as Number) as Void;
    private var _format as Audio.AudioFormat? = null;
    private var _formatChecked as Boolean = false;
    private var _wait as Number = 0;       // ticks since the phase began
    private var _cool as Number = 1;       // ticks to stay idle before the next window
    private var _hidden as Boolean = true;
    private var _got as Boolean = false;   // the running window delivered sound
    private var _ended as Boolean = false; // onComplete or onError since it started
    private var _failed as Boolean = false;

    function initialize(port as MicPort, onWindow as Method(bytes as ByteArray, hertz as Number) as Void) {
        _port = port;
        _onWindow = onWindow;
    }

    // The app is on screen: windows may start from the next tick
    function show() as Void {
        _hidden = false;
        if (phase == MIC_OFF) {
            enter(MIC_IDLE, 1);
        }
    }

    // Off screen, the menu, or the demo: stop the running window, start no more
    function hide() as Void {
        _hidden = true;
        if (phase == MIC_RUNNING) {
            stopNow();
        }
    }

    // Leaving the app: stop if anything is capturing, and touch nothing after
    function exit() as Void {
        _hidden = true;
        if (phase != MIC_DONE && phase != MIC_OFF) {
            if (state() == Capture.CAPTURE_CAPTURING) {
                try {
                    _port.stop();
                } catch (e) {
                }
            }
        }
        phase = MIC_DONE;
    }

    function isHidden() as Boolean {
        return _hidden;
    }

    // Once a second, from the view's timer: the one place a window starts
    function tick() as Void {
        _wait++;
        if (phase == MIC_OFF || phase == MIC_DONE) {
            return;
        }
        var st = state();
        if (phase == MIC_STOPPING) {
            if (st != Capture.CAPTURE_CAPTURING) {
                enter(MIC_IDLE, 2);
            } else if (_wait > STOP_LIMIT) {
                leave("The microphone would not stop");
            }
            return;
        }
        if (phase == MIC_RUNNING) {
            if (_ended || st != Capture.CAPTURE_CAPTURING) {
                if (_failed || !_got) {
                    silent++;
                }
                if (silent >= GIVE_UP) {
                    leave("The microphone sent no sound");
                } else {
                    enter(MIC_IDLE, (_failed || !_ended) ? 2 : 1);   // two ticks when its callbacks have not all come
                }
            } else if (_wait > NO_DATA) {
                silent++;
                stopNow();
                if (silent >= GIVE_UP) {
                    leave("The microphone sent no sound");
                }
            }
            return;
        }
        // idle
        if (_hidden || _wait < _cool) {
            return;
        }
        if (st == Capture.CAPTURE_CAPTURING) {
            stopNow();   // something is capturing that we did not start: never initialise over it
            return;
        }
        if (windows >= MAX_WINDOWS) {
            leave("Resting after ten minutes · BACK, then open again");
            return;
        }
        begin();
    }

    // Capture callbacks: note what happened, touch nothing
    function onData(audioData as ByteArray) as Void {
        if (phase != MIC_RUNNING || _ended) {
            return;   // flushed by our own stop, or late
        }
        _got = true;
        silent = 0;
        _onWindow.invoke(audioData, hertz);
    }

    function onComplete() as Void {
        _ended = true;
    }

    function onError(error as Capture.Error) as Void {
        _ended = true;
        _failed = true;
        System.println("sound: capture error " + error);
    }

    private function begin() as Void {
        if (!_formatChecked) {
            _formatChecked = true;
            _format = pickFormat();
        }
        var format = _format;
        if (format == null) {
            leave("Microphone format not supported");
            return;
        }
        _got = false;
        _ended = false;
        _failed = false;
        windows++;
        try {
            var settings = _port.initCapture(self, {
                :format => format,
                :windowSize => WINDOW_BYTES,
                :windowFilledBehavior => Capture.WINDOW_FILLED_STOP,
                :filters => [] as Array<Capture.Filter>
            });
            var used = settings[:format];
            if (used != null) {
                hertz = rate(used[:frequency] as Number);
            }
            _port.start();
            enter(MIC_RUNNING, 0);
            if (windows <= 3) {
                System.println("sound: window " + windows + " started at " + hertz + " Hz");
            }
        } catch (e) {
            silent++;
            System.println("sound: window " + windows + " would not start");
            if (silent >= GIVE_UP) {
                leave("The microphone would not start");
            } else {
                enter(MIC_IDLE, 2);
            }
        }
    }

    private function stopNow() as Void {
        if (state() == Capture.CAPTURE_CAPTURING) {
            try {
                _port.stop();
            } catch (e) {
            }
        }
        enter(MIC_STOPPING, 0);
    }

    private function leave(why as String) as Void {
        if (phase == MIC_RUNNING && state() == Capture.CAPTURE_CAPTURING) {
            try {
                _port.stop();
            } catch (e) {
            }
        }
        error = why;
        phase = MIC_DONE;
        System.println("sound: leaving the microphone alone: " + why);
    }

    private function enter(p as Number, cool as Number) as Void {
        phase = p;
        _wait = 0;
        _cool = cool;
    }

    private function state() as Number {
        try {
            return _port.state();
        } catch (e) {
            return -1;
        }
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
        return (frequency >= 0 && frequency < table.size()) ? table[frequency] : 11025;
    }
}
