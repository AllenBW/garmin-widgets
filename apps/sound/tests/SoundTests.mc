import Toybox.Application.Properties;
import Toybox.Audio;
import Toybox.Audio.Capture;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Test;
import Toybox.Time;

// Run No Evil tests for Sound Level: scripts/test.sh sound [device]. The
// meter is fed synthetic windows; nothing here touches the microphone.

// A window of 16-bit little-endian samples: a sine of the given peak, or
// silence, behind a plain 44-byte WAV header when asked
function sineWindow(samples as Number, peak as Number, header as Boolean) as ByteArray {
    return sineAfter(header ? wavHeader(-1) : new [0]b, samples, peak);
}

function sineAfter(head as ByteArray, samples as Number, peak as Number) as ByteArray {
    var bytes = new [head.size() + samples * 2]b;
    for (var i = 0; i < head.size(); i++) {
        bytes[i] = head[i];
    }
    for (var i = 0; i < samples; i++) {
        var v = (peak * Math.sin(i * 0.3)).toNumber();
        bytes.encodeNumber(v, Lang.NUMBER_FORMAT_SINT16, {:offset => head.size() + 2 * i, :endianness => Lang.ENDIAN_LITTLE});
    }
    return bytes;
}

function putTag(bytes as ByteArray, at as Number, tag as String) as Void {
    var chars = tag.toCharArray();
    for (var i = 0; i < 4; i++) {
        bytes[at + i] = chars[i].toNumber();
    }
}

function putSize(bytes as ByteArray, at as Number, size as Number) as Void {
    bytes.encodeNumber(size, Lang.NUMBER_FORMAT_UINT32, {:offset => at, :endianness => Lang.ENDIAN_LITTLE});
}

// A WAV header: "RIFF", "WAVE", a 16-byte "fmt " chunk, then a "LIST"
// chunk of `list` bytes when list >= 0, then "data". Plain is 44 bytes.
function wavHeader(list as Number) as ByteArray {
    var extra = list < 0 ? 0 : 8 + list + (list % 2);
    var bytes = new [44 + extra]b;
    putTag(bytes, 0, "RIFF");
    putSize(bytes, 4, 36 + extra + 4000);
    putTag(bytes, 8, "WAVE");
    putTag(bytes, 12, "fmt ");
    putSize(bytes, 16, 16);
    bytes.encodeNumber(1, Lang.NUMBER_FORMAT_UINT16, {:offset => 20, :endianness => Lang.ENDIAN_LITTLE});   // PCM
    bytes.encodeNumber(1, Lang.NUMBER_FORMAT_UINT16, {:offset => 22, :endianness => Lang.ENDIAN_LITTLE});   // mono
    putSize(bytes, 24, 8000);
    putSize(bytes, 28, 16000);
    bytes.encodeNumber(2, Lang.NUMBER_FORMAT_UINT16, {:offset => 32, :endianness => Lang.ENDIAN_LITTLE});
    bytes.encodeNumber(16, Lang.NUMBER_FORMAT_UINT16, {:offset => 34, :endianness => Lang.ENDIAN_LITTLE});
    var at = 36;
    if (list >= 0) {
        putTag(bytes, at, "LIST");
        putSize(bytes, at + 4, list);
        for (var i = 0; i < list; i++) {
            bytes[at + 8 + i] = 0x49;   // "I": loud if read as samples
        }
        at += extra;
    }
    putTag(bytes, at, "data");
    putSize(bytes, at + 4, 4000);
    return bytes;
}

(:test)
function testLevels(logger as Logger) as Boolean {
    // a sine's RMS is its peak over root two
    var full = sineWindow(2048, 32767, false);
    var r = SoundMeter.rms(full, 0, 1);
    logger.debug("full-scale sine rms " + r);
    Test.assertMessage((r - 23170).abs() < 300, "rms of a full-scale sine is about 23170: " + r);
    Test.assertMessage((SoundMeter.dbfs(r) + 3.0).abs() < 0.2, "which is -3 dBFS: " + SoundMeter.dbfs(r));
    var half = sineWindow(2048, 16384, false);
    Test.assertMessage((SoundMeter.dbfs(SoundMeter.rms(half, 0, 1)) + 9.0).abs() < 0.2, "half scale is -9 dBFS");

    // silence sits on the floor, never below it
    var silence = new [4096]b;
    Test.assertEqualMessage(SoundMeter.rms(silence, 0, 1), 0.0, "silence has no rms");
    Test.assertEqualMessage(SoundMeter.dbfs(0.0), SoundMeter.FLOOR, "silence is the floor");
    Test.assertEqualMessage(SoundMeter.dbfs(0.001), SoundMeter.FLOOR, "a whisper of nothing is the floor too");

    // a WAV header at the start of a window is skipped
    var headed = sineWindow(2000, 16384, true);
    Test.assertEqualMessage(SoundMeter.headerOffset(headed), 44, "RIFF header seen");
    Test.assertEqualMessage(SoundMeter.headerOffset(half), 0, "no header");
    Test.assertMessage((SoundMeter.rms(headed, 44, 1) - SoundMeter.rms(half, 0, 1)).abs() < 100, "the samples after the header match");
    // a header with a LIST chunk before the data: the samples start later,
    // and reading the chunk as sound would be a spike
    var listed = sineAfter(wavHeader(26), 2048, 16384);
    Test.assertEqualMessage(SoundMeter.headerOffset(listed), 78, "data after a 26-byte LIST chunk");
    Test.assertMessage((SoundMeter.rms(listed, 78, 1) - SoundMeter.rms(half, 0, 1)).abs() < 100, "the samples after it match");
    var quiet = sineWindow(2048, 1024, false);
    var quietListed = sineAfter(wavHeader(26), 2048, 1024);
    Test.assertMessage(SoundMeter.rms(quietListed, 0, 1) > SoundMeter.rms(quiet, 0, 1) + 500, "read from the top, the header drowns a quiet room");
    var noData = new [60]b;
    putTag(noData, 0, "RIFF"); putTag(noData, 8, "WAVE"); putTag(noData, 12, "fmt "); putSize(noData, 16, 16);
    Test.assertEqualMessage(SoundMeter.headerOffset(noData), 44, "no data chunk in reach: the plain 44");
    var notWave = new [60]b;
    putTag(notWave, 0, "RIFF");
    Test.assertEqualMessage(SoundMeter.headerOffset(notWave), 0, "RIFF without WAVE is sound");
    Test.assertEqualMessage(SoundMeter.headerOffset(new [8]b), 0, "too short to be a header");

    // decimation: every fourth sample gives the same level within a fraction of a decibel
    var every = SoundMeter.dbfs(SoundMeter.rms(half, 0, 1));
    var fourth = SoundMeter.dbfs(SoundMeter.rms(half, 0, 4));
    logger.debug("stride 1: " + every + " dBFS, stride 4: " + fourth);
    Test.assertMessage((every - fourth).abs() < 0.3, "stride 4 is within 0.3 dB");
    Test.assertEqualMessage(SoundMeter.rms(new [1]b, 0, 1), 0.0, "an odd byte is no sample");
    // a bias on the line is not sound: a sine riding on 5000 reads as the sine alone
    var biased = sineWindow(2048, 8192, false);
    for (var i = 0; i < 2048; i++) {
        var v = biased.decodeNumber(Lang.NUMBER_FORMAT_SINT16, {:offset => 2 * i, :endianness => Lang.ENDIAN_LITTLE}) as Number;
        biased.encodeNumber(v + 5000, Lang.NUMBER_FORMAT_SINT16, {:offset => 2 * i, :endianness => Lang.ENDIAN_LITTLE});
    }
    var plain = SoundMeter.rms(sineWindow(2048, 8192, false), 0, 1);
    Test.assertMessage((SoundMeter.rms(biased, 0, 1) - plain).abs() < 30, "bias removed: " + SoundMeter.rms(biased, 0, 1) + " vs " + plain);
    var flat = new [4096]b;
    for (var i = 0; i < 2048; i++) {
        flat.encodeNumber(5000, Lang.NUMBER_FORMAT_SINT16, {:offset => 2 * i, :endianness => Lang.ENDIAN_LITTLE});
    }
    Test.assertEqualMessage(SoundMeter.rms(flat, 0, 1), 0.0, "a flat line is silence");
    // a range: the first half loud, the second quiet
    var halves = sineAfter(new [0]b, 2048, 16384);
    for (var i = 1024; i < 2048; i++) {
        halves.encodeNumber(0, Lang.NUMBER_FORMAT_SINT16, {:offset => 2 * i, :endianness => Lang.ENDIAN_LITTLE});
    }
    Test.assertMessage(SoundMeter.rmsOf(halves, 0, 2048, 1) > 11000, "the first half is loud");
    Test.assertEqualMessage(SoundMeter.rmsOf(halves, 2048, 0, 1), 0.0, "the second half is silent");
    return true;
}

(:test)
function testDangerRange(logger as Logger) as Boolean {
    // NIOSH: 85 dB for 8 h, half the time for every 3 dB
    Test.assertEqualMessage(SoundMeter.allowedSeconds(85.0), 28800, "85 dB: 8 h");
    Test.assertEqualMessage(SoundMeter.allowedSeconds(88.0), 14400, "88 dB: 4 h");
    Test.assertEqualMessage(SoundMeter.allowedSeconds(91.0), 7200, "91 dB: 2 h");
    Test.assertEqualMessage(SoundMeter.allowedSeconds(94.0), 3600, "94 dB: 1 h");
    Test.assertEqualMessage(SoundMeter.allowedSeconds(97.0), 1800, "97 dB: 30 min");
    Test.assertEqualMessage(SoundMeter.allowedSeconds(100.0), 900, "100 dB: 15 min");
    Test.assertEqualMessage(SoundMeter.allowedSeconds(103.0), 450, "103 dB: 7.5 min");
    Test.assertEqualMessage(SoundMeter.allowedSeconds(110.0), 89, "110 dB: a minute and a half");
    Test.assertMessage(SoundMeter.allowedSeconds(115.0) < 30, "115 dB: under 30 s");
    Test.assertEqualMessage(SoundMeter.allowedSeconds(79.9), -1, "under 80 is not counted");
    Test.assertMessage(SoundMeter.allowedSeconds(82.0) > 57000, "82 dB: about 16 h");

    // the dose: fifteen minutes at 100 dB is the whole day's
    Test.assertMessage((SoundMeter.dose(100.0, 900.0) - 100.0).abs() < 0.1, "900 s at 100 dB is 100%");
    Test.assertMessage((SoundMeter.dose(85.0, 3600.0) - 12.5).abs() < 0.1, "an hour at 85 dB is 12.5%");
    Test.assertEqualMessage(SoundMeter.dose(60.0, 3600.0), 0.0, "quiet adds nothing");

    // bands and their words
    Test.assertEqualMessage(SoundMeter.band(35.0), 0, "quiet");
    Test.assertEqualMessage(SoundMeter.band(40.0), 1, "calm from 40");
    Test.assertEqualMessage(SoundMeter.band(60.0), 2, "conversation");
    Test.assertEqualMessage(SoundMeter.band(78.0), 3, "busy traffic");
    Test.assertEqualMessage(SoundMeter.band(85.0), 4, "risk from 85");
    Test.assertEqualMessage(SoundMeter.band(99.9), 4, "still risk");
    Test.assertEqualMessage(SoundMeter.band(100.0), 5, "loud venue from 100");
    Test.assertEqualMessage(SoundMeter.band(120.0), 6, "pain from 120");
    Test.assertEqualMessage(SoundMeter.name(62.0), "Conversation", "name");
    Test.assertEqualMessage(SoundMeter.describe(62.0), "Conversation", "no verdict under 85");
    Test.assertEqualMessage(SoundMeter.describe(90.0), "Too loud · hearing risk", "too loud");
    Test.assertEqualMessage(SoundMeter.describe(105.0), "Dangerous · loud venue", "dangerous");
    Test.assertEqualMessage(SoundMeter.describe(125.0), "Pain · leave now", "pain");

    // the safe-for line
    Test.assertEqualMessage(SoundMeter.safeFor(60.0), "Safe all day", "quiet is safe all day");
    Test.assertEqualMessage(SoundMeter.safeFor(80.0), "Safe all day", "80 dB allows over a day");
    Test.assertEqualMessage(SoundMeter.safeFor(85.0), "Safe for 8 h", "85");
    Test.assertEqualMessage(SoundMeter.safeFor(97.0), "Safe for 30 min", "97");
    Test.assertEqualMessage(SoundMeter.safeFor(103.0), "Safe for 8 min", "103 rounds to 8 min");
    Test.assertEqualMessage(SoundMeter.safeFor(115.0), "Under 30 s", "115");
    Test.assertEqualMessage(SoundMeter.safeFor(121.0), "Leave now", "pain");
    Test.assertEqualMessage(SoundMeter.spell(5400), "1 h 30", "an hour and a half");
    Test.assertEqualMessage(SoundMeter.spell(45), "45 s", "seconds");
    Test.assertEqualMessage(SoundMeter.whole(-3.2), 0, "never below zero");
    Test.assertEqualMessage(SoundMeter.whole(71.6), 72, "rounded");

    // energy averaging: 80 and 100 average to 97, not 90
    var e = (SoundMeter.energy(80.0) + SoundMeter.energy(100.0)) / 2;
    Test.assertMessage((SoundMeter.fromEnergy(e) - 97.0).abs() < 0.1, "energy average of 80 and 100 is 97: " + SoundMeter.fromEnergy(e));
    return true;
}

(:test)
function testSession(logger as Logger) as Boolean {
    var s = new SoundSession();
    s.offset = 90.0;
    // the microphone's first half second is thrown away, spike and all
    Test.assertEqualMessage(s.addWindow(20.0, 0.25), EVENT_NONE, "a start spike: no event");
    Test.assertEqualMessage(s.addWindow(0.0, 0.25), EVENT_NONE, "still warming up");
    Test.assertMessage(s.level == null && s.peak == null && s.seconds == 0.0, "nothing of the warm-up is kept");
    // then a quarter-second window at -30 dBFS is 60 dB; a second of them seeds the level
    for (var i = 0; i < 3; i++) {
        Test.assertEqualMessage(s.addWindow(-30.0, 0.25), EVENT_NONE, "quiet: no event");
        Test.assertMessage(s.level == null, "no level until a second is in");
    }
    s.addWindow(-30.0, 0.25);
    Test.assertMessage(((s.level as Float) - 60.0).abs() < 0.01, "a second of 60 dB opens at 60: " + s.level);
    Test.assertMessage(((s.peak as Float) - 60.0).abs() < 0.01, "the peak counts from the warm-up's end");
    Test.assertMessage((s.seconds - 1.0).abs() < 0.01, "a second measured");
    // a jump to 102 dB settles over a second: a quarter of the way per window
    s.addWindow(12.0, 0.25);
    Test.assertMessage(((s.level as Float) - 70.5).abs() < 0.01, "a quarter of the way: " + s.level);
    Test.assertMessage(((s.peak as Float) - 102.0).abs() < 0.01, "the peak is the raw window");
    Test.assertMessage(((s.raw as Float) - 102.0).abs() < 0.01, "raw");
    // keep it there: the smoothed level crosses 85 then 100, each line once
    var events = [] as Array<Number>;
    for (var i = 0; i < 40; i++) {
        var e = s.addWindow(12.0, 0.25);
        if (e != EVENT_NONE) {
            events.add(e);
        }
        s.tick();
    }
    logger.debug("events " + events + " level " + s.level);
    Test.assertMessage(events.size() == 2 && events[0] == EVENT_RISK && events[1] == EVENT_LOUD, "85 then 100, once each: " + events);
    Test.assertMessage(((s.level as Float) - 102.0).abs() < 0.5, "settled at 102");
    // hovering about the line does not buzz again; falling well below and rising does, after the hold
    s.addWindow(9.0, 1.0);
    s.addWindow(10.5, 1.0);
    Test.assertEqualMessage(s.addWindow(10.5, 1.0), EVENT_NONE, "no buzz while hovering");
    s.addWindow(0.0, 1.0);    // 90: below 100 by the hysteresis, still above 85
    for (var i = 0; i < 20; i++) {
        s.tick();
    }
    Test.assertEqualMessage(s.addWindow(10.0, 1.0), EVENT_LOUD, "back over 100 after the hold");
    Test.assertEqualMessage(s.addWindow(10.0, 1.0), EVENT_NONE, "and once only");

    // the energy average sits between, nearer the loud part; the dose grows
    var avg = s.average() as Float;
    Test.assertMessage(avg > 100.0 && avg < 102.0, "average by energy, near the loud part: " + avg);
    Test.assertMessage(s.dosePercent > 1.0, "the dose counts the loud seconds: " + s.dosePercent);
    Test.assertMessage(s.seconds > 10.0, "seconds measured: " + s.seconds);

    // the trend holds the last two minutes, oldest first
    Test.assertEqualMessage(s.trendCount(), 60, "one point a tick");
    for (var i = 0; i < 100; i++) {
        s.tick();
    }
    Test.assertEqualMessage(s.trendCount(), SoundMeter.TREND_POINTS, "capped at two minutes");
    var first = s.trendAt(0) as Float;
    var last = s.trendAt(SoundMeter.TREND_POINTS - 1) as Float;
    Test.assertMessage((first - 90.0).abs() < 0.5 && (last - 100.0).abs() < 0.5, "oldest first: " + first + " .. " + last);

    s.reset();
    Test.assertMessage(s.level == null && s.peak == null && s.trendCount() == 0 && s.dosePercent == 0.0, "reset forgets the sitting");
    Test.assertEqualMessage(s.offset, 90.0, "but keeps the calibration");
    Test.assertMessage(s.warmupLeft > 0.0, "and warms up again");

    // the seed is an energy average, so a loud moment in the first second shows in it
    for (var i = 0; i < 2; i++) { s.addWindow(-50.0, 0.25); }
    s.addWindow(-20.0, 0.25); s.addWindow(-20.0, 0.25); s.addWindow(-20.0, 0.25); s.addWindow(-50.0, 0.25);
    Test.assertMessage(((s.level as Float) - 68.8).abs() < 0.2, "three 70s and a 40 seed near 69: " + s.level);

    // a restart (the menu, say) discards the next half second but keeps the level
    s.restarted();
    s.addWindow(20.0, 0.25);
    s.addWindow(20.0, 0.25);
    Test.assertMessage(((s.level as Float) - 68.8).abs() < 0.2, "the restart's spike changes nothing: " + s.level);
    Test.assertMessage(((s.peak as Float) - 70.0).abs() < 0.01, "nor the peak: " + s.peak);
    s.addWindow(-20.0, 0.25);
    Test.assertMessage(((s.level as Float) - 69.1).abs() < 0.2, "then it moves again: " + s.level);
    return true;
}

(:test)
function testWaiting(logger as Logger) as Boolean {
    Test.assertEqualMessage(SoundMeter.waiting(0, 0, null), "starting the microphone", "just started");
    Test.assertEqualMessage(SoundMeter.waiting(1, 0, null), "starting the microphone", "a second in");
    Test.assertEqualMessage(SoundMeter.waiting(2, 0, null), "waiting for sound", "two seconds, nothing yet");
    Test.assertEqualMessage(SoundMeter.waiting(0, 1, null), "restarting the microphone", "first restart");
    Test.assertEqualMessage(SoundMeter.waiting(5, 2, null), "restarting the microphone", "second");
    Test.assertEqualMessage(SoundMeter.waiting(0, 3, null), "no sound from the microphone · BACK, then open again", "give up advice after three");
    Test.assertEqualMessage(SoundMeter.waiting(0, 0, "Microphone unavailable (3)"), "Microphone unavailable (3) · retrying", "an error says so");
    return true;
}

(:test)
function testDemo(logger as Logger) as Boolean {
    var s = new SoundSession();
    s.seedDemo();
    Test.assertEqualMessage(s.trendCount(), SoundMeter.TREND_POINTS, "two minutes of demo");
    var seen = [false, false, false, false, false, false, false] as Array<Boolean>;
    for (var i = 0; i < s.trendCount(); i++) {
        var v = s.trendAt(i) as Float;
        Test.assertMessage(v > 30.0 && v < 125.0, "demo levels stay on the scale: " + v);
        seen[SoundMeter.band(v)] = true;
    }
    logger.debug("bands seen " + seen);
    Test.assertMessage(seen[0] && seen[2] && seen[3] && seen[4] && seen[5], "the demo walks the quiet, talk, traffic, risk and loud bands");
    Test.assertMessage((s.peak as Float) > 110.0, "with a peak over 110: " + s.peak);
    Test.assertMessage(s.dosePercent > 5.0, "and a dose worth showing: " + s.dosePercent);
    Test.assertMessage(s.demoLevel(5) < 45.0 && s.demoLevel(125) < 45.0, "the demo cycles");
    return true;
}

// How long decoding costs, for choosing the stride (HANDOFF.md)
(:test)
function testDecodeBudget(logger as Logger) as Boolean {
    var window = sineWindow(2048, 16384, false);
    var t0 = System.getTimer();
    var r1 = SoundMeter.rms(window, 0, 1);
    var t1 = System.getTimer();
    var r4 = SoundMeter.rms(window, 0, 4);
    var t2 = System.getTimer();
    logger.debug("2048 decodes: " + (t1 - t0) + " ms, 512 decodes: " + (t2 - t1) + " ms (" + r1 + " vs " + r4 + ")");
    Test.assertMessage(r1 > 0.0 && r4 > 0.0, "both decoded");
    return true;
}

(:test)
function testCues(logger as Logger) as Boolean {
    var w = 454;
    var h = 454;
    var r = w / 2;
    Test.assertEqualMessage(Lib.Cues.at(w / 2, h / 2, w, h), Lib.Cues.TAP_NONE, "the centre is not a button");
    Test.assertEqualMessage(Lib.Cues.at(w / 2 + (r * 0.8).toNumber(), h / 2 - (r * 0.5).toNumber(), w, h), Lib.Cues.TAP_START, "two o'clock is START");
    Test.assertEqualMessage(Lib.Cues.at(w / 2 + (r * 0.75).toNumber(), h / 2 + (r * 0.5).toNumber(), w, h), Lib.Cues.TAP_BACK, "four o'clock is BACK");
    Test.assertEqualMessage(Lib.Cues.at(w / 2 - (r * 0.9).toNumber(), h / 2, w, h), Lib.Cues.TAP_UP, "nine o'clock is UP");
    Test.assertEqualMessage(Lib.Cues.at(w / 2 - (r * 0.7).toNumber(), h / 2 + (r * 0.5).toNumber(), w, h), Lib.Cues.TAP_DOWN, "eight o'clock is DOWN");
    Test.assertEqualMessage(Lib.Cues.at(w / 2, h - 5, w, h), Lib.Cues.TAP_NONE, "six o'clock is nothing");
    Test.assertEqualMessage(Lib.Cues.at(w / 2, 5, w, h), Lib.Cues.TAP_NONE, "twelve o'clock is nothing");
    // the 416 screen maps the same way
    Test.assertEqualMessage(Lib.Cues.at(208 + 166, 208 - 104, 416, 416), Lib.Cues.TAP_START, "START on the small screen");
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();
    Lib.Cues.draw(dc, Lib.Cues.START, "MENU", Graphics.FONT_XTINY, 0xFFFFFF, 0xFFFFFF);
    Lib.Cues.draw(dc, Lib.Cues.UP, "+1", Graphics.FONT_XTINY, 0x4A4A4A, 0x9A9A9A);
    return true;
}

(:test)
function testGlanceAndAppDraw(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var screen = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();
    var glanceDc = (Graphics.createBufferedBitmap({:width => (w * 0.77).toNumber(), :height => (h * 0.29).toNumber()}).get() as Graphics.BufferedBitmap).getDc();

    SoundStore.clear();
    Test.assertMessage(SoundStore.last() == null, "nothing stored");
    var glance = new SoundGlance();
    glance.onLayout(glanceDc);
    glance.onUpdate(glanceDc);
    SoundStore.save(72, Time.now().value() - 240, "Busy traffic");
    var last = SoundStore.last() as Array;
    Test.assertEqualMessage(last[SoundStore.DB] as Number, 72, "stored");
    Test.assertEqualMessage(SoundStore.ago(Time.now().value() - 240), "4 min ago", "ago");
    Test.assertEqualMessage(SoundStore.ago(Time.now().value() - 10), "just now", "just now");
    Test.assertEqualMessage(SoundStore.ago(Time.now().value() - 7200), "2 h ago", "hours");
    glance.onUpdate(glanceDc);

    var view = new SoundView();
    view.onLayout(screen);
    Properties.setValue("Calibration", 90);   // the simulator keeps the last sitting's offset
    view.reloadSettings();
    Test.assertEqualMessage(view.offset(), 90, "the default calibration");
    // nothing heard yet: both pages
    view.onUpdate(screen);
    view.nextScreen();
    Test.assertEqualMessage(view.screen(), SCREEN_TREND, "DOWN turns to the trend");
    view.onUpdate(screen);
    view.nextScreen();
    Test.assertEqualMessage(view.screen(), SCREEN_LIVE, "and round");
    Test.assertEqualMessage(view.startCue(), "MENU", "START opens the menu");
    Test.assertEqualMessage(view.backCue(), "EXIT", "BACK leaves");
    Test.assertEqualMessage(view.downCue(), "TREND", "DOWN names the next page");
    Test.assertEqualMessage(view.upCue(), "", "UP has no page before the first, so no word");

    // the demo: every band through both pages, and the number's colour follows
    view.startDemo();
    Test.assertMessage(view.demo(), "demo on");
    var s = view.session();
    Test.assertEqualMessage(s.trendCount(), SoundMeter.TREND_POINTS, "seeded");
    for (var i = 0; i < 130; i++) {
        view.onTick();
        if (i % 10 == 0) {
            view.onUpdate(screen);
            view.nextScreen();
            view.onUpdate(screen);
            view.nextScreen();
        }
    }
    Test.assertEqualMessage(view.colour(50.0), 0x34C759, "green under 70");
    Test.assertEqualMessage(view.colour(75.0), 0xFFB020, "amber to 85");
    Test.assertEqualMessage(view.colour(90.0), 0xFF6A1F, "orange to 100");
    Test.assertEqualMessage(view.colour(110.0), 0xD0021B, "red past 100");
    var kept = SoundStore.last();
    Test.assertMessage(kept != null && (kept[SoundStore.DB] as Number) == 72, "the demo never overwrites the glance's reading");

    // the buttons and the touches
    var delegate = new SoundDelegate(view);
    Test.assertMessage(!delegate.onSelect(), "select is not swallowed");
    Test.assertMessage(!delegate.onBack(), "BACK leaves the app when not calibrating");
    Test.assertMessage(delegate.onNextPage() && view.screen() == SCREEN_TREND, "DOWN turns the page");
    Test.assertEqualMessage(view.upCue(), "LIVE", "UP names the page before");
    Test.assertEqualMessage(view.downCue(), "", "DOWN has no page after the last");
    view.onUpdate(screen);
    Test.assertMessage(delegate.onPreviousPage() && view.screen() == SCREEN_LIVE, "UP turns it back");
    var r = (w < h ? w : h) / 2;
    Test.assertEqualMessage(view.cueAt(w / 2 - (r * 0.9).toNumber(), h / 2), Lib.Cues.TAP_UP, "nine o'clock is UP");

    // calibrate: UP and DOWN move the offset, START resets it, BACK keeps it
    view.calibrate();
    Test.assertMessage(view.calibrating(), "calibrating");
    Test.assertEqualMessage(view.startCue(), "RESET", "START resets");
    Test.assertEqualMessage(view.backCue(), "DONE", "BACK is done");
    Test.assertEqualMessage(view.upCue(), "+1", "UP adds");
    Test.assertEqualMessage(view.downCue(), "-1", "DOWN takes");
    view.onUpdate(screen);
    delegate.onPreviousPage();
    delegate.onPreviousPage();
    Test.assertEqualMessage(view.offset(), 92, "two up");
    Test.assertMessage(((view.session().offset) - 92.0).abs() < 0.01, "the session uses it at once");
    delegate.onNextPage();
    Test.assertEqualMessage(view.offset(), 91, "one down");
    view.onUpdate(screen);
    delegate.pressStart();
    Test.assertEqualMessage(view.offset(), 90, "reset");
    for (var i = 0; i < 50; i++) {
        delegate.onNextPage();
    }
    Test.assertEqualMessage(view.offset(), 50, "floor at 50");
    for (var i = 0; i < 100; i++) {
        delegate.onPreviousPage();
    }
    Test.assertEqualMessage(view.offset(), 130, "ceiling at 130");
    delegate.pressStart();
    Test.assertMessage(delegate.onBack() && !view.calibrating(), "BACK ends calibrating");
    view.reloadSettings();
    Test.assertEqualMessage(view.offset(), 90, "the reset was written to the property");

    // a cleared session draws too; the microphone itself is not opened here
    // (endDemo would, and capture never returns inside a unit test)
    view.clearSession();
    Test.assertMessage(view.demo() && view.session().level == null, "cleared, still the demo");
    view.onUpdate(screen);
    view.nextScreen();
    view.onUpdate(screen);
    view.shutdown();
    Test.assertMessage(!view.listening(), "nothing to stop");
    return true;
}

// ---- The microphone driver against a fake microphone ----------------
// The fake records every call and the tick it came in, delivers a window
// every tick while capturing (as continuous capture does), sends a
// stop's last callbacks one tick late, and flags each thing that crashed
// the watch or that the review warned of: touching the microphone inside
// a callback, initialising over a running capture, before a stop's
// callbacks have come, or within two ticks of a stop or an end.

class FakeFailure extends Lang.Exception {
    function initialize() {
        Exception.initialize();
    }
}

class FakePort extends MicPort {
    var st as Number = Capture.CAPTURE_UNINITIALIZED;
    var tick as Number = 0;
    var inits as Number = 0;
    var stops as Number = 0;
    var calls as Number = 0;
    var lastInit as Number = -100;
    var lastStop as Number = -100;
    var lastEnd as Number = -100;
    var stopWorks as Boolean = true;
    var initFails as Boolean = false;
    var flushDue as Boolean = false;   // a stop's flush and onComplete still to come
    var inCallback as Boolean = false;
    var violations as Array<String> = [] as Array<String>;

    function initialize() {
        MicPort.initialize();
    }

    function state() as Number {
        return st;
    }

    function supported(format as Audio.AudioFormat) as Boolean {
        return format[:frequency] == Audio.FREQ_8_KHZ;
    }

    function touch(what as String) as Void {
        calls++;
        if (inCallback) {
            violations.add(what + " inside a callback at tick " + tick);
        }
    }

    function initCapture(callbacks as Capture.Callbacks, settings as Capture.Settings) as Capture.Settings {
        touch("init");
        if (st == Capture.CAPTURE_CAPTURING) {
            violations.add("init over a running capture at tick " + tick);
        }
        if (flushDue) {
            violations.add("init before a stop's callbacks came, tick " + tick);
        }
        if (tick - lastStop < 2) {
            violations.add("init " + (tick - lastStop) + " tick after a stop, tick " + tick);
        }
        if (tick - lastEnd < 2) {
            violations.add("init " + (tick - lastEnd) + " tick after an end, tick " + tick);
        }
        lastInit = tick;
        inits++;
        if (initFails) {
            throw new FakeFailure();
        }
        st = Capture.CAPTURE_STOPPED;
        return settings;
    }

    function start() as Void {
        touch("start");
        if (tick != lastInit) {
            violations.add("start without an init in tick " + tick);
        }
        st = Capture.CAPTURE_CAPTURING;
    }

    function stop() as Void {
        touch("stop");
        stops++;
        lastStop = tick;
        if (stopWorks && st == Capture.CAPTURE_CAPTURING) {
            st = Capture.CAPTURE_STOPPED;
            flushDue = true;
        }
    }
}

class FakeSink {
    var windows as Number = 0;
    var throws as Boolean = false;

    function initialize() {
    }

    function take(bytes as ByteArray, hertz as Number) as Void {
        windows++;
        if (throws) {
            throw new FakeFailure();
        }
    }
}

// Between two ticks: a stop's late flush, or a window while capturing
function fakeBetween(mic as SoundMic, port as FakePort, deliver as Boolean) as Void {
    port.inCallback = true;
    if (port.flushDue) {
        mic.onData(new [2048]b);
        mic.onComplete();
        port.flushDue = false;
        port.lastEnd = port.tick;
    } else if (deliver && port.st == Capture.CAPTURE_CAPTURING) {
        mic.onData(new [2048]b);
    }
    port.inCallback = false;
}

function fakeTicks(mic as SoundMic, port as FakePort, n as Number, deliver as Boolean) as Void {
    for (var i = 0; i < n; i++) {
        port.tick++;
        mic.tick();
        fakeBetween(mic, port, deliver);
    }
}

function newMic(port as FakePort, sink as FakeSink) as SoundMic {
    var mic = new SoundMic(port, sink.method(:take));
    mic.show();
    return mic;
}

(:test)
function testMicContinuous(logger as Logger) as Boolean {
    var port = new FakePort();
    var sink = new FakeSink();
    var mic = new SoundMic(port, sink.method(:take));
    mic.tick();
    Test.assertEqualMessage(port.calls, 0, "nothing before the app is shown");
    mic.show();
    fakeTicks(mic, port, 60, true);
    logger.debug("60 s: " + port.inits + " inits, " + port.stops + " stops, " + sink.windows + " windows");
    Test.assertMessage(port.violations.size() == 0, "no rule broken: " + port.violations);
    Test.assertEqualMessage(port.inits, 1, "started once");
    Test.assertEqualMessage(port.stops, 0, "never stopped while it works");
    Test.assertMessage(sink.windows >= 58, "a window every tick: " + sink.windows);
    Test.assertEqualMessage(mic.hertz, 8000, "8 kHz as the tuner uses");
    // a menu: the data is ignored, the microphone is not touched
    var calls = port.calls;
    var windows = sink.windows;
    mic.hide();
    fakeTicks(mic, port, 20, true);
    Test.assertEqualMessage(port.calls, calls, "a menu never touches the microphone");
    Test.assertEqualMessage(sink.windows, windows, "and its data is ignored");
    mic.show();
    fakeTicks(mic, port, 5, true);
    Test.assertMessage(sink.windows > windows, "data again after the menu");
    Test.assertEqualMessage(port.inits, 1, "still the one start");
    // leaving the app stops it, once, and nothing follows
    mic.exit();
    Test.assertEqualMessage(port.stops, 1, "exit stops it");
    fakeBetween(mic, port, false);   // its flush comes after exit
    calls = port.calls;
    windows = sink.windows;
    fakeTicks(mic, port, 10, true);
    Test.assertEqualMessage(port.calls, calls, "nothing after exit");
    Test.assertEqualMessage(sink.windows, windows, "and no data used");
    Test.assertMessage(port.violations.size() == 0, "no rule broken: " + port.violations);
    return true;
}

(:test)
function testMicStalls(logger as Logger) as Boolean {
    // the sound stops once: one careful restart, and it works again
    var port = new FakePort();
    var sink = new FakeSink();
    var mic = newMic(port, sink);
    fakeTicks(mic, port, 10, true);
    fakeTicks(mic, port, 6, false);
    Test.assertEqualMessage(port.stops, 1, "a stall is stopped");
    fakeTicks(mic, port, 10, true);
    logger.debug("one stall: " + port.inits + " inits, " + port.stops + " stops, " + port.violations);
    Test.assertMessage(port.violations.size() == 0, "no rule broken: " + port.violations);
    Test.assertEqualMessage(port.inits, 2, "started once more");
    Test.assertEqualMessage(mic.phase, MIC_RUNNING, "and running");
    // it stops again: left alone
    fakeTicks(mic, port, 8, false);
    Test.assertEqualMessage(mic.phase, MIC_DONE, "a second stall and it is left alone");
    Test.assertEqualMessage(mic.error as String, "The microphone stopped sending sound", "and it says why");
    Test.assertEqualMessage(port.inits, 2, "no third start");
    var calls = port.calls;
    fakeBetween(mic, port, false);
    fakeTicks(mic, port, 20, true);
    Test.assertEqualMessage(port.calls, calls, "nothing more once left alone");
    mic.exit();
    Test.assertEqualMessage(port.calls, calls, "exit has nothing to stop");
    Test.assertMessage(port.violations.size() == 0, "no rule broken: " + port.violations);
    // the capture ends by itself (an error): a careful restart, after a gap
    port = new FakePort();
    mic = newMic(port, sink);
    fakeTicks(mic, port, 5, true);
    port.inCallback = true;
    mic.onError(Capture.CAPTURE_ERR_INTERNAL);
    port.inCallback = false;
    port.st = Capture.CAPTURE_UNINITIALIZED;
    port.lastEnd = port.tick;
    fakeTicks(mic, port, 10, true);
    Test.assertMessage(port.violations.size() == 0, "no rule broken after an error: " + port.violations);
    Test.assertEqualMessage(port.inits, 2, "restarted once after the error");
    Test.assertEqualMessage(port.stops, 0, "nothing to stop, it had ended");
    return true;
}

(:test)
function testMicStuck(logger as Logger) as Boolean {
    // a stop that never takes: never initialise over it; exit tries once more
    var port = new FakePort();
    port.stopWorks = false;
    var sink = new FakeSink();
    var mic = newMic(port, sink);
    fakeTicks(mic, port, 3, true);
    fakeTicks(mic, port, 20, false);
    logger.debug("stuck: " + port.inits + " inits, " + port.stops + " stops, " + mic.error);
    Test.assertMessage(port.violations.size() == 0, "no rule broken: " + port.violations);
    Test.assertEqualMessage(port.inits, 1, "no second start while it will not stop");
    Test.assertEqualMessage(mic.error as String, "The microphone would not stop", "left alone, and it says why");
    var stops = port.stops;
    mic.exit();
    Test.assertEqualMessage(port.stops, stops + 1, "leaving the app still stops a capture left running");
    return true;
}

(:test)
function testMicFailures(logger as Logger) as Boolean {
    var port = new FakePort();
    port.initFails = true;
    var sink = new FakeSink();
    var mic = newMic(port, sink);
    fakeTicks(mic, port, 20, true);
    Test.assertMessage(port.violations.size() == 0, "no rule broken: " + port.violations);
    Test.assertEqualMessage(port.inits, 1, "one try");
    Test.assertEqualMessage(mic.error as String, "The microphone would not start", "then left alone");
    // the window handler throws: caught inside onData, the microphone keeps going
    port = new FakePort();
    sink = new FakeSink();
    sink.throws = true;
    mic = newMic(port, sink);
    fakeTicks(mic, port, 10, true);
    Test.assertMessage(port.violations.size() == 0, "no rule broken: " + port.violations);
    Test.assertMessage(mic.faults >= 8, "errors caught: " + mic.faults);
    Test.assertEqualMessage(mic.phase, MIC_RUNNING, "still running");
    Test.assertEqualMessage(port.inits, 1, "and not restarted for it");
    return true;
}
