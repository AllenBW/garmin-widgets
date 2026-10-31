import Toybox.Lang;
import Toybox.Math;

// What the session can tell the view after a window of sound
enum {
    EVENT_NONE,
    EVENT_RISK,    // the level rose past the hearing-risk line (85 dB)
    EVENT_LOUD     // the level rose past the loud-venue line (100 dB)
}

// The meter's arithmetic and the danger range. Pure: the view feeds it
// the microphone's windows, the tests feed it synthetic ones, and
// nothing here touches the microphone or the screen.
//
// A window is 16-bit little-endian LPCM; its RMS gives decibels below
// full scale (dBFS), and the calibration offset turns that into an
// approximate sound level in dB. The watch microphone is not A-weighted
// and not a calibrated meter, so the number is a guide, not a reading.
//
// The danger range follows NIOSH's recommended exposure limit: 85 dB
// for 8 hours a day, and half the time for every 3 dB more (the 3 dB
// exchange rate), so 88 dB is 4 h, 91 dB 2 h, 94 dB 1 h, 97 dB 30 min,
// 100 dB 15 min, 103 dB 7.5 min, 110 dB 1.5 min, 115 dB under 30 s.
// Levels under 80 dB are not counted towards the dose. WHO calls 70 dB
// safe for the whole day; about 120 dB is the threshold of pain.
module SoundMeter {

    const FLOOR = -96.0;           // dBFS of digital silence
    const FULL_SCALE = 32768.0;
    const HEADER = 44;             // a WAV header, when a window opens with one
    const DAY = 28800;             // 8 h, the allowed time at 85 dB
    const REL = 85.0;              // NIOSH's recommended exposure limit
    const COUNT_FROM = 80.0;       // levels below this add nothing to the dose
    const TREND_POINTS = 120;      // the chart: one point a second, two minutes

    // The bands, by their lower edge
    const CALM = 40;
    const TALK = 55;
    const BUSY = 70;
    const RISK = 85;
    const LOUD = 100;
    const PAIN = 120;

    const NAMES = ["Quiet", "Calm", "Conversation", "Busy traffic", "Hearing risk", "Loud venue", "Pain"] as Array<String>;

    // Where the samples start in a window: after a WAV header if one
    // opens it. A header is "RIFF", a size, "WAVE", then chunks of an id,
    // a size and that many bytes; the samples follow the "data" chunk's
    // id and size, 44 bytes in when a plain "fmt " is the only chunk
    // before it. Anything else before "data" (a "LIST" chunk, say) is
    // skipped too, because read as samples it is a loud spike. A header
    // whose "data" chunk is out of reach is taken as the plain 44 bytes.
    function headerOffset(bytes as ByteArray) as Number {
        var size = bytes.size();
        if (size < 12 || !tagAt(bytes, 0, 0x52, 0x49, 0x46, 0x46) || !tagAt(bytes, 8, 0x57, 0x41, 0x56, 0x45)) {
            return 0;
        }
        var at = 12;
        while (at + 8 <= size) {
            if (tagAt(bytes, at, 0x64, 0x61, 0x74, 0x61)) {
                return at + 8;
            }
            var len = bytes.decodeNumber(Lang.NUMBER_FORMAT_UINT32, {:offset => at + 4, :endianness => Lang.ENDIAN_LITTLE}) as Long;
            if (len > size) {
                break;
            }
            var n = len.toNumber();
            at += 8 + n + (n % 2);
        }
        return size >= HEADER ? HEADER : 0;
    }

    function tagAt(bytes as ByteArray, at as Number, a as Number, b as Number, c as Number, d as Number) as Boolean {
        return bytes[at] == a && bytes[at + 1] == b && bytes[at + 2] == c && bytes[at + 3] == d;
    }

    // What the screen says under "Listening" while no level can be shown:
    // `seconds` since the microphone was last started, `restarts` the
    // starts in a row that gave no sound, `error` what the last one said
    function waiting(seconds as Number, restarts as Number, error as String?) as String {
        if (error != null) {
            return error + " · retrying";
        }
        if (restarts >= 3) {
            return "no sound from the microphone · BACK, then open again";
        }
        if (restarts > 0) {
            return "restarting the microphone";
        }
        return seconds < 2 ? "starting the microphone" : "waiting for sound";
    }

    // RMS of the 16-bit little-endian samples from `offset`, taking every
    // `stride`-th one: decoding is the dear part, and a quarter of the
    // samples give the same level within a fraction of a decibel
    function rms(bytes as ByteArray, offset as Number, stride as Number) as Float {
        var step = 2 * (stride < 1 ? 1 : stride);
        var sum = 0.0;
        var n = 0;
        var size = bytes.size();
        var options = {:offset => offset, :endianness => Lang.ENDIAN_LITTLE};
        for (var i = offset; i + 1 < size; i += step) {
            options[:offset] = i;
            var v = bytes.decodeNumber(Lang.NUMBER_FORMAT_SINT16, options) as Number;
            sum += v * v;
            n++;
        }
        return n == 0 ? 0.0 : Math.sqrt(sum / n).toFloat();
    }

    // Decibels below full scale: a full-scale sine is -3, silence the floor
    function dbfs(rms as Float) as Float {
        if (rms < 0.5) {
            return FLOOR;
        }
        var v = (20.0 * Math.log(rms / FULL_SCALE, 10)).toFloat();
        return v < FLOOR ? FLOOR : v;
    }

    // Seconds a day NIOSH allows at this level; -1 when it is not counted
    function allowedSeconds(db as Float) as Number {
        if (db < COUNT_FROM) {
            return -1;
        }
        return (DAY / Math.pow(2.0, (db - REL) / 3.0)).toNumber();
    }

    // The share of a day's dose, in percent, that `seconds` at `db` uses
    function dose(db as Float, seconds as Float) as Float {
        var t = allowedSeconds(db);
        return t <= 0 ? 0.0 : (100.0 * seconds / t).toFloat();
    }

    // Levels are averaged by energy, not by decibel
    function energy(db as Float) as Float {
        return Math.pow(10.0, db / 10.0).toFloat();
    }

    function fromEnergy(e as Float) as Float {
        return e <= 0.0 ? FLOOR : (10.0 * Math.log(e, 10)).toFloat();
    }

    // 0 quiet, 1 calm, 2 conversation, 3 busy traffic, 4 hearing risk, 5 loud venue, 6 pain
    function band(db as Float) as Number {
        if (db < CALM) { return 0; }
        if (db < TALK) { return 1; }
        if (db < BUSY) { return 2; }
        if (db < RISK) { return 3; }
        if (db < LOUD) { return 4; }
        if (db < PAIN) { return 5; }
        return 6;
    }

    function name(db as Float) as String {
        return NAMES[band(db)];
    }

    // The band's name, with the verdict in front once it matters
    function describe(db as Float) as String {
        var b = band(db);
        if (b == 4) {
            return "Too loud · hearing risk";
        }
        if (b == 5) {
            return "Dangerous · loud venue";
        }
        if (b == 6) {
            return "Pain · leave now";
        }
        return NAMES[b];
    }

    // "Safe all day", "Safe for 15 min", "Under 30 s", "Leave now"
    function safeFor(db as Float) as String {
        if (db >= PAIN) {
            return "Leave now";
        }
        var t = allowedSeconds(db);
        if (t < 0 || t >= 86400) {
            return "Safe all day";
        }
        if (t < 30) {
            return "Under 30 s";
        }
        return "Safe for " + spell(t);
    }

    // Seconds -> "8 h", "1 h 30", "15 min", "45 s"
    function spell(seconds as Number) as String {
        if (seconds < 60) {
            return seconds + " s";
        }
        var minutes = (seconds + 30) / 60;
        if (minutes < 60) {
            return minutes + " min";
        }
        var h = minutes / 60;
        var m = minutes % 60;
        return m == 0 ? h + " h" : h + " h " + m.format("%02d");
    }

    // A rounded level for the screen, never below 0
    function whole(db as Float) as Number {
        var n = Math.round(db).toNumber();
        return n < 0 ? 0 : n;
    }
}

// One sitting with the meter: the smoothed level, the peak, the energy
// average and the NIOSH dose, plus the last two minutes for the chart.
// Ticked once a second by the view; fed a window at a time.
//
// The microphone's first moments are not the room: a start transient,
// the gain settling. So the first WARMUP seconds after every start are
// thrown away, and when there is no level yet the next SEED seconds are
// averaged before one is shown, so the number opens on what the level
// is rather than on a spike that then falls.
class SoundSession {

    const SMOOTH = 1.0;       // seconds the shown level settles over
    const WARMUP = 0.5;       // seconds discarded after the microphone starts
    const SEED = 1.0;         // seconds averaged before the first level shows
    const HOLD = 15;          // seconds between buzzes for one line
    const HYSTERESIS = 2.0;   // dB the level must fall before a line can fire again

    var offset as Float = 90.0;   // the calibration: dBFS + offset = dB
    var level as Float? = null;   // the smoothed level
    var raw as Float? = null;     // the last window on its own
    var peak as Float? = null;
    var seconds as Float = 0.0;   // audio measured
    var dosePercent as Float = 0.0;
    var warmupLeft as Float = WARMUP;   // seconds still to discard

    private var _seedEnergy as Float = 0.0;
    private var _seedSeconds as Float = 0.0;
    private var _energy as Float = 0.0;
    private var _windows as Number = 0;
    private var _trend as Array<Float?> = new [SoundMeter.TREND_POINTS] as Array<Float?>;
    private var _next as Number = 0;      // where the next point goes
    private var _count as Number = 0;
    private var _since85 as Number = HOLD;
    private var _since100 as Number = HOLD;
    private var _above85 as Boolean = false;
    private var _above100 as Boolean = false;

    function initialize() {
    }

    // Forget the sitting, keep the calibration
    function reset() as Void {
        level = null;
        raw = null;
        peak = null;
        seconds = 0.0;
        dosePercent = 0.0;
        warmupLeft = WARMUP;
        _seedEnergy = 0.0;
        _seedSeconds = 0.0;
        _energy = 0.0;
        _windows = 0;
        _trend = new [SoundMeter.TREND_POINTS] as Array<Float?>;
        _next = 0;
        _count = 0;
        _since85 = HOLD;
        _since100 = HOLD;
        _above85 = false;
        _above100 = false;
    }

    // The microphone has (re)started: its first moments are discarded
    function restarted() as Void {
        warmupLeft = WARMUP;
    }

    // One window of sound: its dBFS and its length in seconds. Returns
    // the event the window caused, EVENT_NONE while warming up or seeding.
    function addWindow(dbfs as Float, windowSeconds as Float) as Number {
        if (warmupLeft > 0.0) {
            warmupLeft -= windowSeconds;
            return EVENT_NONE;
        }
        var db = dbfs + offset;
        raw = db;
        var p = peak;
        if (p == null || db > p) {
            peak = db;
        }
        _energy += SoundMeter.energy(db);
        _windows++;
        seconds += windowSeconds;
        dosePercent += SoundMeter.dose(db, windowSeconds);
        var l = level;
        if (l == null) {
            _seedEnergy += SoundMeter.energy(db) * windowSeconds;
            _seedSeconds += windowSeconds;
            if (_seedSeconds < SEED) {
                return EVENT_NONE;
            }
            level = SoundMeter.fromEnergy(_seedEnergy / _seedSeconds);
            _seedEnergy = 0.0;
            _seedSeconds = 0.0;
        } else {
            var a = windowSeconds / SMOOTH;
            if (a > 1.0) {
                a = 1.0;
            }
            level = l + (db - l) * a;
        }
        return crossings();
    }

    // The lines are crossed by the smoothed level, upwards, with a little
    // hysteresis so a level hovering on a line does not buzz on every window
    private function crossings() as Number {
        var s = level as Float;
        var event = EVENT_NONE;
        if (!_above100 && s >= SoundMeter.LOUD) {
            _above100 = true;
            if (_since100 >= HOLD) {
                event = EVENT_LOUD;
                _since100 = 0;
            }
        } else if (_above100 && s < SoundMeter.LOUD - HYSTERESIS) {
            _above100 = false;
        }
        if (!_above85 && s >= SoundMeter.RISK) {
            _above85 = true;
            if (event == EVENT_NONE && _since85 >= HOLD) {
                event = EVENT_RISK;
                _since85 = 0;
            }
        } else if (_above85 && s < SoundMeter.RISK - HYSTERESIS) {
            _above85 = false;
        }
        return event;
    }

    // Once a second: the chart takes the level, the buzz timers advance
    function tick() as Void {
        _trend[_next] = level;
        _next = (_next + 1) % SoundMeter.TREND_POINTS;
        if (_count < SoundMeter.TREND_POINTS) {
            _count++;
        }
        _since85++;
        _since100++;
    }

    function average() as Float? {
        return _windows == 0 ? null : SoundMeter.fromEnergy(_energy / _windows);
    }

    function windows() as Number {
        return _windows;
    }

    // The chart's points, oldest first
    function trendCount() as Number {
        return _count;
    }

    function trendAt(i as Number) as Float? {
        return _trend[(_next + SoundMeter.TREND_POINTS - _count + i) % SoundMeter.TREND_POINTS];
    }

    // A made-up two minutes that walks through every band, for looking at
    // the screens: a quiet room, a conversation, traffic, a workshop, a
    // concert with a peak, then the walk home
    function seedDemo() as Void {
        reset();
        warmupLeft = 0.0;   // made-up sound has no start transient
        for (var t = 0; t < SoundMeter.TREND_POINTS; t++) {
            var db = demoLevel(t);
            addWindow(db - offset, 1.0);
            tick();
        }
    }

    // The demo's level at second t, cycling every two minutes
    function demoLevel(t as Number) as Float {
        var s = t % SoundMeter.TREND_POINTS;
        var wobble = ((t * 7) % 5 - 2).toFloat();
        if (s < 20) { return 36.0 + wobble; }
        if (s < 40) { return 61.0 + wobble; }
        if (s < 60) { return 76.0 + wobble; }
        if (s < 80) { return 90.0 + wobble; }
        if (s < 100) { return (s == 88 ? 112.0 : 104.0) + wobble; }
        return 58.0 + wobble;
    }
}
