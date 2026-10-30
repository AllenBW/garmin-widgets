import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Run No Evil tests for Sauna: scripts/test.sh sauna [device]. The tracker
// is fed synthetic visits second by second; nothing needs the sensors.

(:test)
function testText(logger as Logger) as Boolean {
    Test.assertEqualMessage(SaunaText.clock(754), "12:34", "minutes and seconds");
    Test.assertEqualMessage(SaunaText.clock(3754), "1:02:34", "past an hour");
    Test.assertEqualMessage(SaunaText.clock(-5), "0:00", "never negative");
    Test.assertEqualMessage(SaunaText.minutes(2290), "38 min", "rounded minutes");
    Test.assertEqualMessage(SaunaText.minutes(3900), "1 h 05", "hours");
    Test.assertEqualMessage(SaunaText.rounds(1), "1 round", "singular");
    Test.assertEqualMessage(SaunaText.rounds(3), "3 rounds", "plural");
    Test.assertEqualMessage(SaunaText.drop(null), "--", "no drop");
    Test.assertEqualMessage(SaunaText.drop(28), "-28", "a fall");
    Test.assertEqualMessage(SaunaText.drop(-4), "+4", "a rise");
    Test.assertEqualMessage(SaunaText.headline(null), "No visits yet", "empty headline");
    var row = [1730000000, 3, 2290, 1200, 142, 31, 481] as Array<Number>;
    Test.assertEqualMessage(SaunaText.headline(row), "3 rounds · 38 min", "headline");
    var detail = SaunaText.detail(row);
    logger.debug(detail);
    Test.assertMessage(detail.find(" · max 142 bpm · -31 in 1 min") != null, "detail: " + detail);
    Test.assertMessage(SaunaText.tenths(481).length() > 0 && SaunaText.tenths(-1000).equals(""), "tenths");
    return true;
}

// A synthetic visit: arrive cool, warm 0.05 degrees a second in the heat,
// cool 0.04 a second outside; the heart rate climbs in the heat, peaks a
// few seconds after leaving, then falls a beat a second.
(:test)
function testTrackerAuto(logger as Logger) as Boolean {
    var t = new SaunaTracker();
    var events = [] as Array<Number>;
    var at = [] as Array<Number>;
    var temp = 33.0;
    var hr = 70;
    // 0-59 arrival; 60-299 heating (sauna); 300-599 cooling (break); 600-899 heating; 900-1199 cooling
    for (var s = 1; s <= 1200; s++) {
        var heating = (s >= 60 && s < 300) || (s >= 600 && s < 900);
        if (heating) {
            temp += 0.05;
            if (hr < 130) { hr += 1; }
        } else if (s >= 300) {
            temp -= 0.04;
            if (temp < 33.0) { temp = 33.0; }
            // the heart keeps climbing a few seconds after the door, then settles
            if ((s >= 300 && s < 310) || (s >= 900 && s < 910)) { hr += 1; }
            else if (hr > 80) { hr -= 1; }
        }
        var e = t.tick(hr, temp);
        if (e != EVENT_NONE) {
            events.add(e);
            at.add(s);
        }
    }
    logger.debug("events " + events + " at " + at);
    // A degree and a half above the coolest reading of the last minute: 30 s of heating, 60 + 30
    Test.assertEqualMessage(events.size(), 4, "in, out, in, out and nothing else (the breaks are shorter than the target)");
    Test.assertEqualMessage(events[0], EVENT_ENTER, "first: in");
    Test.assertMessage((at[0] - 90).abs() <= 1, "noticed 30 s after the door: " + at[0]);
    // A degree below the hottest reading: 25 s of cooling, 300 + 25
    Test.assertEqualMessage(events[1], EVENT_LEAVE, "then out");
    Test.assertMessage((at[1] - 325).abs() <= 1, "noticed 25 s after leaving: " + at[1]);
    Test.assertEqualMessage(events[2], EVENT_ENTER, "in again");
    Test.assertMessage((at[2] - 630).abs() <= 1, "second round noticed: " + at[2]);
    Test.assertEqualMessage(events[3], EVENT_LEAVE, "out again");
    Test.assertMessage((at[3] - 925).abs() <= 1, "second round over: " + at[3]);

    Test.assertEqualMessage(t.roundCount(), 2, "two rounds");
    Test.assertEqualMessage(t.phase, PHASE_BREAK, "ends on a break");
    var r1 = t.rounds[0];
    Test.assertEqualMessage(r1.seconds(t.now), at[1] - at[0], "round one runs from notice to notice");
    // the heart kept climbing ten seconds past the door, before the watch noticed
    Test.assertEqualMessage(r1.maxHr, 140, "round one max");
    var peakAt = r1.peakAt as Number;
    Test.assertMessage(peakAt == at[1] + 1 && r1.peakHr >= 120 && r1.peakHr <= 124, "the peak is the first reading after: " + r1.peakHr + " at " + peakAt);
    var d1 = r1.drop1 as Number;
    var d2 = r1.drop2 as Number;
    logger.debug("round 1 peak " + r1.peakHr + " at " + peakAt + " drops " + d1 + " / " + d2);
    Test.assertMessage(d1 == r1.peakHr - 80, "a minute later the rate had settled at 80: " + d1);
    Test.assertMessage(d2 == d1, "and two minutes later still: " + d2);
    Test.assertEqualMessage(t.saunaSeconds(), (at[1] - at[0]) + (at[3] - at[2]), "time in heat");
    Test.assertEqualMessage(t.breakSeconds(), (at[2] - at[1]) + (1200 - at[3]), "time out");
    Test.assertEqualMessage(t.maxHr(), 140, "visit max");
    var avg = t.avgDrop1() as Number;
    Test.assertMessage(avg >= 40 && avg <= 45, "average drop: " + avg);
    // the second heating runs five minutes from 33: 33 + 300 x 0.05
    var mt = t.maxTemp as Float;
    Test.assertMessage((mt - 48.0).abs() < 0.2, "watch peaked at 48: " + mt);
    var row = t.historyRow(1730000000);
    Test.assertEqualMessage(row.size(), SaunaHistory.STRIDE, "a history row");
    Test.assertEqualMessage(row[SaunaHistory.ROUNDS], 2, "row rounds");
    Test.assertEqualMessage(row[SaunaHistory.MAX_TEMP], 480, "row temperature in tenths");
    Test.assertMessage(t.trace.size() > 0 && t.traceStart == at[2], "the chart holds the last round");
    Test.assertMessage(t.lastDone() == t.rounds[1] && t.previous() == t.rounds[0], "last and previous");
    return true;
}

(:test)
function testTrackerManual(logger as Logger) as Boolean {
    var t = new SaunaTracker();
    t.roundTarget = 120;
    t.breakTarget = 60;
    t.hotTemp = 50.0;
    // no readings at all: nothing happens on its own
    for (var s = 0; s < 200; s++) {
        Test.assertEqualMessage(t.tick(null, null), EVENT_NONE, "quiet without readings");
    }
    Test.assertEqualMessage(t.phase, PHASE_ARRIVAL, "still arriving");
    Test.assertEqualMessage(t.phaseSeconds(), 200, "arrival clock");
    Test.assertEqualMessage(t.mark(), EVENT_ENTER, "LAP goes in");
    Test.assertEqualMessage(t.phase, PHASE_SAUNA, "in");
    // a steep cooling right after a manual mark is ignored for MANUAL_HOLD seconds
    var temp = 40.0;
    var got = EVENT_NONE;
    for (var s = 0; s < 119; s++) {
        temp -= 0.1;
        var e = t.tick(120, temp);
        if (e != EVENT_NONE) { got = e; }
    }
    Test.assertEqualMessage(got, EVENT_NONE, "no automatic change during the hold, no target yet");
    Test.assertEqualMessage(t.tick(120, temp), EVENT_ROUND_TARGET, "the round target at exactly two minutes");
    Test.assertEqualMessage(t.mark(), EVENT_LEAVE, "LAP goes out");
    Test.assertEqualMessage(t.roundCount(), 1, "one round");
    Test.assertEqualMessage(t.rounds[0].seconds(t.now), 120, "two minutes long");
    for (var s = 0; s < 59; s++) {
        Test.assertEqualMessage(t.tick(100, temp), EVENT_NONE, "break ticking");
    }
    Test.assertEqualMessage(t.tick(100, temp), EVENT_BREAK_TARGET, "the break target at a minute");
    Test.assertEqualMessage(t.mark(), EVENT_ENTER, "LAP goes in again");
    Test.assertEqualMessage(t.breakSeconds(), 60, "one minute out");

    // the heat guard: a buzz the first second at 50 and every minute after, off two degrees below
    Test.assertEqualMessage(t.tick(120, 50.0), EVENT_HOT, "hot");
    Test.assertMessage(t.hot, "flagged");
    var hots = 0;
    for (var s = 0; s < 120; s++) {
        if (t.tick(120, 51.0) == EVENT_HOT) { hots += 1; }
    }
    Test.assertEqualMessage(hots, 2, "once a minute");
    t.tick(120, 49.0);
    Test.assertMessage(t.hot, "still flagged just under");
    t.tick(120, 47.9);
    Test.assertMessage(!t.hot, "clear two degrees under");

    // auto off: a sauna's worth of warming (staying under the hot warning) does nothing
    var u = new SaunaTracker();
    u.auto = false;
    var any = false;
    temp = 30.0;
    for (var s = 0; s < 300; s++) {
        temp += 0.05;
        if (u.tick(90, temp) != EVENT_NONE) { any = true; }
    }
    Test.assertMessage(!any && u.phase == PHASE_ARRIVAL, "nothing automatic when off");
    Test.assertEqualMessage(u.historyRow(5)[SaunaHistory.DROP], -1, "no drop recorded");
    return true;
}

(:test)
function testHistory(logger as Logger) as Boolean {
    SaunaHistory.clear();
    Test.assertEqualMessage(SaunaHistory.count(), 0, "empty");
    Test.assertMessage(SaunaHistory.last() == null && SaunaHistory.visit(0) == null, "nothing to show");
    SaunaHistory.add([1730000000, 2, 1500, 900, 130, 25, 440] as Array<Number>);
    SaunaHistory.add([1730100000, 3, 2290, 1200, 142, 31, 481] as Array<Number>);
    Test.assertEqualMessage(SaunaHistory.count(), 2, "two visits");
    var last = SaunaHistory.last() as Array<Number>;
    Test.assertEqualMessage(last[SaunaHistory.START], 1730100000, "newest first");
    var older = SaunaHistory.visit(1) as Array<Number>;
    Test.assertEqualMessage(older[SaunaHistory.ROUNDS], 2, "then the older one");
    Test.assertMessage(SaunaHistory.visit(2) == null, "past the end");
    for (var i = 0; i < SaunaHistory.MAX; i++) {
        SaunaHistory.add([1730200000 + i, 1, 600, 0, 0, -1, -1000] as Array<Number>);
    }
    Test.assertEqualMessage(SaunaHistory.count(), SaunaHistory.MAX, "capped");
    var oldest = SaunaHistory.visit(SaunaHistory.MAX - 1) as Array<Number>;
    Test.assertEqualMessage(oldest[SaunaHistory.START], 1730200000, "the first two fell off");
    SaunaHistory.clear();
    return true;
}

(:test)
function testRecorder(logger as Logger) as Boolean {
    var t = new SaunaTracker();
    var rec = new SaunaRecorder();
    var started = rec.start(true);
    logger.debug("session started: " + started);
    if (!started) {
        logger.debug("the simulator refused a session; skipping");
        return true;
    }
    Test.assertMessage(rec.recording(), "recording");
    for (var s = 0; s < 5; s++) {
        t.tick(100, 40.0 + s);
        rec.record(t.temp, t.phase);
    }
    t.mark();
    rec.lap(null);
    rec.pause();
    Test.assertMessage(!rec.recording() && rec.active(), "paused");
    rec.resume();
    Test.assertMessage(rec.recording(), "resumed");
    rec.discard();
    Test.assertMessage(!rec.active(), "gone");
    Test.assertMessage(!rec.save(t), "nothing to save after a discard");
    return true;
}

(:test)
function testGlanceAndAppDraw(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var screen = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();
    var glanceDc = (Graphics.createBufferedBitmap({:width => (w * 0.77).toNumber(), :height => (h * 0.29).toNumber()}).get() as Graphics.BufferedBitmap).getDc();

    SaunaHistory.clear();
    var glance = new SaunaGlance();
    glance.onLayout(glanceDc);
    glance.onUpdate(glanceDc);
    SaunaHistory.add([1730100000, 3, 2290, 1200, 142, 31, 481] as Array<Number>);
    glance.onUpdate(glanceDc);

    var view = new SaunaView();
    view.onLayout(screen);
    view.reloadSettings();
    // idle, all four screens
    for (var i = 0; i < SCREEN_COUNT; i++) {
        view.onUpdate(screen);
        view.nextScreen();
    }
    Test.assertEqualMessage(view.screen(), SCREEN_LIVE, "round the screens");
    view.previousScreen();
    Test.assertEqualMessage(view.screen(), SCREEN_HISTORY, "and back");
    view.nextScreen();

    // the cues follow the state: START / EXIT when idle, MENU and the door while recording
    Test.assertEqualMessage(view.startCue(), "START", "idle START cue");
    Test.assertEqualMessage(view.backCue(), "EXIT", "idle BACK cue");

    // the buttons: select must decline so the raw key reaches onKey; BACK exits when idle
    var delegate = new SaunaDelegate(view);
    Test.assertMessage(!delegate.onSelect(), "select is not swallowed");
    Test.assertMessage(!delegate.onBack(), "BACK leaves the app when idle");
    Test.assertMessage(delegate.onNextPage() && view.screen() == SCREEN_ROUNDS, "DOWN turns the screen");
    Test.assertMessage(delegate.onPreviousPage() && view.screen() == SCREEN_LIVE, "UP turns it back");
    // pressing START while recording would push the menu, so the key path is checked up to the start
    view.start(false);
    Test.assertMessage(view.recording() && delegate.onBack() && (view.tracker() as SaunaTracker).phase == PHASE_SAUNA, "BACK marks the door while recording");
    view.discard();
    Test.assertMessage(!view.recording(), "discarded again");

    // a visit without a FIT file: arrival, a round, a break with a recovery
    view.start(false);
    Test.assertMessage(view.recording(), "recording");
    var t = view.tracker() as SaunaTracker;
    t.auto = false;   // the door is marked by hand here; the thermometer logic has its own test
    view.onUpdate(screen);
    Test.assertEqualMessage(view.startCue(), "MENU", "recording START cue");
    Test.assertEqualMessage(view.backCue(), "IN", "BACK goes in");
    view.mark();
    Test.assertEqualMessage(t.phase, PHASE_SAUNA, "in");
    Test.assertEqualMessage(view.backCue(), "OUT", "BACK goes out");
    var temp = 36.0;
    for (var s = 0; s < 400; s++) {
        temp += 0.03;
        t.tick(110 + (s % 20), temp);
    }
    view.onUpdate(screen);
    view.mark();
    for (var s = 0; s < 150; s++) {
        t.tick(130 - (s / 2), temp);
    }
    var times = "";
    for (var i = 0; i < SCREEN_COUNT; i++) {
        var started = System.getTimer();
        view.onUpdate(screen);
        times += " " + (System.getTimer() - started);
        view.nextScreen();
    }
    logger.debug("screens live/rounds/chart/visits ms:" + times);
    // the heat guard
    for (var s = 0; s < 70; s++) {
        t.tick(120, 52.0);
    }
    Test.assertMessage(t.hot, "hot");
    view.onUpdate(screen);
    view.pause();
    Test.assertMessage(view.paused(), "paused");
    view.onUpdate(screen);
    view.resume();
    view.save();
    Test.assertMessage(!view.recording(), "saved and idle");
    Test.assertEqualMessage(SaunaHistory.count(), 2, "the visit joined the history");
    var row = SaunaHistory.last() as Array<Number>;
    logger.debug("saved row: " + row);
    Test.assertEqualMessage(row[SaunaHistory.ROUNDS], 1, "one round saved");
    view.onUpdate(screen);
    view.start(false);
    view.discard();
    Test.assertMessage(!view.recording() && SaunaHistory.count() == 2, "discarded");
    SaunaHistory.clear();

    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}
