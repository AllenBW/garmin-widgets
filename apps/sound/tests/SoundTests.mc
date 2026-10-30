import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Test;
import Toybox.Time;

// Run No Evil tests for Sound Level: scripts/test.sh sound [device]. The
// meter is fed synthetic windows; nothing here touches the microphone.

// A window of 16-bit little-endian samples: a sine of the given peak, or silence
function sineWindow(samples as Number, peak as Number, header as Boolean) as ByteArray {
    var head = header ? 44 : 0;
    var bytes = new [head + samples * 2]b;
    if (header) {
        bytes[0] = 0x52; bytes[1] = 0x49; bytes[2] = 0x46; bytes[3] = 0x46;   // "RIFF"
    }
    for (var i = 0; i < samples; i++) {
        var v = (peak * Math.sin(i * 0.3)).toNumber();
        bytes.encodeNumber(v, Lang.NUMBER_FORMAT_SINT16, {:offset => head + 2 * i, :endianness => Lang.ENDIAN_LITTLE});
    }
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

    // decimation: every fourth sample gives the same level within a fraction of a decibel
    var every = SoundMeter.dbfs(SoundMeter.rms(half, 0, 1));
    var fourth = SoundMeter.dbfs(SoundMeter.rms(half, 0, 4));
    logger.debug("stride 1: " + every + " dBFS, stride 4: " + fourth);
    Test.assertMessage((every - fourth).abs() < 0.3, "stride 4 is within 0.3 dB");
    Test.assertEqualMessage(SoundMeter.rms(new [1]b, 0, 1), 0.0, "an odd byte is no sample");
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
    // a quarter-second window at -30 dBFS is 60 dB; the first one sets the level outright
    Test.assertEqualMessage(s.addWindow(-30.0, 0.25), EVENT_NONE, "quiet: no event");
    Test.assertMessage(((s.level as Float) - 60.0).abs() < 0.01, "first window sets the level");
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
    Test.assertEqualMessage(view.upCue(), "TREND", "so does UP, there are two");

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
