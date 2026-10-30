import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;
import Toybox.Time;

// Run No Evil tests for Sauna & Steam: scripts/test.sh sauna [device]. The
// tracker is fed synthetic visits second by second; nothing needs the sensors.

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

    // Fahrenheit unless told otherwise
    SaunaText.fahrenheit = true;
    Test.assertEqualMessage(SaunaText.temp(50.0), "122°", "50 C is 122 F");
    Test.assertEqualMessage(SaunaText.temp(48.1), "119°", "rounded");
    Test.assertEqualMessage(SaunaText.unit(), "°F", "unit");
    Test.assertEqualMessage(SaunaText.tenths(481), "119°", "tenths in F");
    SaunaText.fahrenheit = false;
    Test.assertEqualMessage(SaunaText.temp(50.0), "50°", "Celsius when asked");
    Test.assertEqualMessage(SaunaText.unit(), "°C", "unit C");
    SaunaText.fahrenheit = true;
    Test.assertMessage(SaunaText.tenths(-1000).equals(""), "no reading");

    Test.assertEqualMessage(SaunaText.kindName(KIND_SAUNA), "Sauna", "sauna name");
    Test.assertEqualMessage(SaunaText.kindName(KIND_STEAM), "Steam room", "steam name");
    Test.assertEqualMessage(SaunaText.kindUpper(KIND_STEAM), "STEAM", "steam band");
    Test.assertEqualMessage(SaunaText.kindCount(KIND_SAUNA, 2, 4), "2/4 saunas", "sauna count");
    Test.assertEqualMessage(SaunaText.kindCount(KIND_STEAM, 1, 3), "1/3 steams", "steam count");
    Test.assertEqualMessage(SaunaText.headline(null), "No visits yet", "empty headline");
    var row = [1730000000, KIND_STEAM, 2, 1450, 1200, 131, 24, 441, -1, -1] as Array<Number>;
    Test.assertEqualMessage(SaunaText.headline(row), "Steam room · 2 rounds · 24 min", "headline");
    var detail = SaunaText.detail(row);
    logger.debug(detail);
    Test.assertMessage(detail.find(" · max 131 bpm · -24 in 1 min") != null, "detail: " + detail);

    // the plans carry the guidance
    var sauna = new SaunaPlan(KIND_SAUNA);
    var steam = new SaunaPlan(KIND_STEAM);
    Test.assertMessage(sauna.roundTarget == 900 && sauna.rounds == 3 && sauna.heatCap == 2700, "sauna plan");
    Test.assertMessage(steam.roundTarget == 720 && steam.rounds == 2 && steam.heatCap == 1800, "steam plan");
    Test.assertMessage(steam.enterRate < sauna.enterRate, "steam needs less warming to count");
    return true;
}

// A synthetic sauna: arrive cool, warm 0.05 degrees a second in the heat,
// cool 0.04 a second outside; the heart rate climbs in the heat, peaks a
// few seconds after leaving, then falls a beat a second.
(:test)
function testTrackerAuto(logger as Logger) as Boolean {
    var t = new SaunaTracker();
    var doors = [] as Array<Number>;
    var at = [] as Array<Number>;
    var recoveries = [] as Array<Number>;
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
        if (e == EVENT_ENTER || e == EVENT_LEAVE) {
            doors.add(e);
            at.add(s);
        } else if (e == EVENT_RECOVERY) {
            recoveries.add(s);
        } else if (e != EVENT_NONE) {
            Test.assertMessage(false, "unexpected event " + e + " at " + s);
        }
    }
    logger.debug("doors " + doors + " at " + at + ", recoveries at " + recoveries);
    // A degree and a half above the coolest reading of the last minute: 30 s of heating, 60 + 30
    Test.assertEqualMessage(doors.size(), 4, "in, out, in, out");
    Test.assertEqualMessage(doors[0], EVENT_ENTER, "first: in");
    Test.assertMessage((at[0] - 90).abs() <= 1, "noticed 30 s after the door: " + at[0]);
    // A degree below the hottest reading: 25 s of cooling, 300 + 25
    Test.assertEqualMessage(doors[1], EVENT_LEAVE, "then out");
    Test.assertMessage((at[1] - 325).abs() <= 1, "noticed 25 s after leaving: " + at[1]);
    Test.assertEqualMessage(doors[2], EVENT_ENTER, "in again");
    Test.assertMessage((at[2] - 630).abs() <= 1, "second round noticed: " + at[2]);
    Test.assertEqualMessage(doors[3], EVENT_LEAVE, "out again");
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
    Test.assertMessage(recoveries.size() == 2 && recoveries[0] == peakAt + 60, "the recovery event a minute after the peak: " + recoveries);
    Test.assertEqualMessage(t.saunaSeconds(), (at[1] - at[0]) + (at[3] - at[2]), "time in heat");
    Test.assertEqualMessage(t.breakSeconds(), (at[2] - at[1]) + (1200 - at[3]), "time out");
    Test.assertEqualMessage(t.maxHr(), 140, "visit max");
    var avg = t.avgDrop1() as Number;
    Test.assertMessage(avg >= 40 && avg <= 45, "average drop: " + avg);
    // the second heating runs five minutes from 33: 33 + 300 x 0.05
    var mt = t.maxTemp as Float;
    Test.assertMessage((mt - 48.0).abs() < 0.2, "watch peaked at 48: " + mt);
    var row = t.historyRow(1730000000, null, null);
    Test.assertEqualMessage(row.size(), SaunaHistory.STRIDE, "a history row");
    Test.assertEqualMessage(row[SaunaHistory.KIND], KIND_SAUNA, "row kind");
    Test.assertEqualMessage(row[SaunaHistory.ROUNDS], 2, "row rounds");
    Test.assertEqualMessage(row[SaunaHistory.MAX_TEMP], 480, "row temperature in tenths");
    Test.assertMessage(t.trace.size() > 0 && t.traceStart == at[2], "the chart holds the last round");
    Test.assertMessage(t.lastDone() == t.rounds[1] && t.previous() == t.rounds[0], "last and previous");

    // the same visit in a steam room, with its lower rates, notices the door sooner
    var u = new SaunaTracker();
    u.plan = new SaunaPlan(KIND_STEAM);
    temp = 33.0;
    var first = 0;
    for (var s = 1; s <= 200 && first == 0; s++) {
        if (s >= 60) { temp += 0.05; }
        if (u.tick(90, temp) == EVENT_ENTER) { first = s; }
    }
    Test.assertMessage((first - 76).abs() <= 1, "steam: in after 16 s of warming (0.8 degrees): " + first);
    return true;
}

(:test)
function testTrackerPlan(logger as Logger) as Boolean {
    var t = new SaunaTracker();
    t.plan.roundTarget = 120;
    t.plan.roundMax = 180;
    t.plan.breakTarget = 60;
    t.plan.rounds = 2;
    t.plan.heatCap = 0;
    t.hotTemp = 50.0;
    // no readings at all: nothing happens on its own
    for (var s = 0; s < 200; s++) {
        Test.assertEqualMessage(t.tick(null, null), EVENT_NONE, "quiet without readings");
    }
    Test.assertEqualMessage(t.phase, PHASE_ARRIVAL, "still arriving");
    Test.assertEqualMessage(t.phaseSeconds(), 200, "arrival clock");
    Test.assertEqualMessage(t.coach(), "Walk in when ready", "arrival coaching after the first minute and a half");
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
    Test.assertEqualMessage(t.coach(), "0:01 left", "counting down to the round target");
    Test.assertEqualMessage(t.tick(120, temp), EVENT_ROUND_TARGET, "the round target at exactly two minutes");
    Test.assertEqualMessage(t.coach(), "Time to cool down", "told to come out");
    for (var s = 0; s < 59; s++) {
        Test.assertEqualMessage(t.tick(120, temp), EVENT_NONE, "nothing until the longest round");
    }
    Test.assertEqualMessage(t.tick(120, temp), EVENT_ROUND_OVER, "nagged at three minutes");
    Test.assertEqualMessage(t.coach(), "Over 3 min · come out", "and told so");
    for (var s = 0; s < 59; s++) {
        Test.assertEqualMessage(t.tick(120, temp), EVENT_NONE, "then quiet for a minute");
    }
    Test.assertEqualMessage(t.tick(120, temp), EVENT_ROUND_OVER, "nagged again a minute later");
    Test.assertEqualMessage(t.mark(), EVENT_LEAVE, "LAP goes out");
    Test.assertEqualMessage(t.roundCount(), 1, "one round");
    Test.assertEqualMessage(t.rounds[0].seconds(t.now), 240, "four minutes long");
    // the break must be at least as long as the round, not just the plan's minute
    Test.assertEqualMessage(t.breakGoal(), 240, "break goal follows the round");
    Test.assertEqualMessage(t.tick(100, temp), EVENT_NONE, "break ticking");
    Test.assertEqualMessage(t.coach(), "Stand up slowly", "stand up slowly first");
    for (var s = 0; s < 19; s++) {
        Test.assertEqualMessage(t.tick(100, temp), EVENT_NONE, "break ticking");
    }
    Test.assertEqualMessage(t.coach(), "Drink some water", "then water");
    for (var s = 0; s < 25; s++) {
        Test.assertEqualMessage(t.tick(100, temp), EVENT_NONE, "break ticking");
    }
    Test.assertEqualMessage(t.coach(), "Cool down 3:15 more", "then the cool-down countdown");
    var recoveredAt = 0;
    for (var s = 0; s < 194; s++) {
        var e = t.tick(100, temp);
        if (e == EVENT_RECOVERY) {
            recoveredAt = t.phaseSeconds();
        } else {
            Test.assertEqualMessage(e, EVENT_NONE, "still cooling");
        }
    }
    Test.assertEqualMessage(recoveredAt, 61, "the fall was reported a minute after the peak");
    Test.assertEqualMessage(t.rounds[0].drop1 as Number, 0, "no fall with a flat heart rate");
    Test.assertEqualMessage(t.tick(100, temp), EVENT_BREAK_TARGET, "ready after four minutes");
    Test.assertEqualMessage(t.coach(), "Ready for round 2", "invited back in");
    Test.assertEqualMessage(t.mark(), EVENT_ENTER, "LAP goes in again");
    Test.assertEqualMessage(t.breakSeconds(), 240, "four minutes out");
    for (var s = 0; s < 10; s++) {
        t.tick(120, temp);
    }
    Test.assertEqualMessage(t.mark(), EVENT_LEAVE, "a short second round");
    // a ten-second round: the break goal is the plan's minute
    Test.assertEqualMessage(t.breakGoal(), 60, "break goal back to the plan's");
    for (var s = 0; s < 59; s++) {
        t.tick(100, temp);
    }
    Test.assertEqualMessage(t.tick(100, temp), EVENT_PLAN_DONE, "the plan's two rounds are done");
    Test.assertEqualMessage(t.coach(), "Plan done · START to save", "told how to end");

    // a free session: the same door and recovery, none of the plan's events
    var free = new SaunaTracker();
    free.guided = false;
    free.plan.roundTarget = 60;
    free.plan.roundMax = 90;
    free.plan.breakTarget = 30;
    free.plan.heatCap = 100;
    free.tick(90, 35.0);
    Test.assertEqualMessage(free.coach(), "Walk in when ready", "free arrival");
    free.mark();
    var freeEvents = 0;
    for (var s = 0; s < 200; s++) {
        if (free.tick(120, 40.0) != EVENT_NONE) { freeEvents += 1; }
    }
    Test.assertEqualMessage(freeEvents, 0, "no targets, nags or caps when free");
    Test.assertEqualMessage(free.coach(), "Free session · out when you like", "free heat line");
    free.mark();
    for (var s = 0; s < 100; s++) {
        free.tick(100, 40.0);
    }
    Test.assertEqualMessage(free.coach(), "Cooling down · in again when ready", "free break line");
    Test.assertMessage(free.rounds[0].drop1 != null, "the recovery is still measured");

    // the heat cap ends a round early
    var c = new SaunaTracker();
    c.plan.heatCap = 100;
    c.plan.roundTarget = 0;
    c.plan.roundMax = 0;
    c.mark();
    var cap = EVENT_NONE;
    var capAt = 0;
    for (var s = 1; s <= 120; s++) {
        var e = c.tick(110, 40.0);
        if (e != EVENT_NONE) { cap = e; capAt = s; }
    }
    Test.assertMessage(cap == EVENT_HEAT_CAP && capAt == 100, "cap at 100 s of heat: " + cap + " at " + capAt);
    Test.assertEqualMessage(c.coach(), "That's 1 min of heat · come out", "cap coaching");

    // the heat guard: a buzz the first second at 50 and every minute after, off two degrees below
    var g = new SaunaTracker();
    g.hotTemp = 50.0;
    Test.assertEqualMessage(g.tick(120, 50.0), EVENT_HOT, "hot");
    Test.assertMessage(g.hot, "flagged");
    Test.assertEqualMessage(g.coach(), "Watch hot, take it off", "hot coaching beats everything");
    var hots = 0;
    for (var s = 0; s < 120; s++) {
        if (g.tick(120, 51.0) == EVENT_HOT) { hots += 1; }
    }
    Test.assertEqualMessage(hots, 2, "once a minute");
    g.tick(120, 49.0);
    Test.assertMessage(g.hot, "still flagged just under");
    g.tick(120, 47.9);
    Test.assertMessage(!g.hot, "clear two degrees under");
    var off = new SaunaTracker();
    off.hotTemp = 0.0;
    Test.assertEqualMessage(off.tick(120, 60.0), EVENT_NONE, "guard off");

    // the heart-rate ceiling: a minute over it in the heat, then once a minute
    var hi = new SaunaTracker();
    hi.hrCeiling = 150;
    hi.plan.roundTarget = 0;
    hi.plan.roundMax = 0;
    hi.plan.heatCap = 0;
    hi.mark();
    for (var s = 0; s < 59; s++) {
        Test.assertEqualMessage(hi.tick(160, 40.0), EVENT_NONE, "not yet a minute over");
    }
    Test.assertMessage(!hi.hrHigh(), "not flagged at 59 s");
    Test.assertEqualMessage(hi.tick(160, 40.0), EVENT_HR_HIGH, "a minute over the ceiling");
    Test.assertMessage(hi.hrHigh(), "flagged");
    Test.assertEqualMessage(hi.coach(), "Heart rate 160 · come out", "told to come out");
    var highs = 0;
    for (var s = 0; s < 120; s++) {
        if (hi.tick(155, 40.0) == EVENT_HR_HIGH) { highs += 1; }
    }
    Test.assertEqualMessage(highs, 2, "once a minute while it lasts");
    hi.tick(140, 40.0);
    Test.assertMessage(!hi.hrHigh(), "clears as soon as the rate dips under");
    hi.coachHrHigh = false;
    for (var s = 0; s < 120; s++) {
        Test.assertEqualMessage(hi.tick(170, 40.0), EVENT_NONE, "switched off");
    }

    // the recovery rule: a minute after leaving the rate is still high, so the break grows
    var rec = new SaunaTracker();
    rec.plan.roundTarget = 0;
    rec.plan.roundMax = 0;
    rec.plan.heatCap = 0;
    rec.plan.breakTarget = 60;
    rec.recoveryHr = 110;
    rec.mark();
    for (var s = 0; s < 30; s++) {
        rec.tick(140, 40.0);
    }
    rec.mark();
    Test.assertEqualMessage(rec.breakGoal(), 60, "a minute's break for a half-minute round");
    Test.assertEqualMessage(rec.coach(), "Stand up slowly", "first words on leaving");
    var notRecoveredAt = 0;
    for (var s = 1; s <= 70; s++) {
        var e = rec.tick(125, 40.0);
        if (e == EVENT_NOT_RECOVERED) { notRecoveredAt = s; }
        else if (e == EVENT_BREAK_TARGET && s == 60) { }   // the plan's minute, as expected
        else if (e != EVENT_NONE) { Test.assertMessage(false, "unexpected " + e + " at " + s); }
    }
    Test.assertEqualMessage(notRecoveredAt, 61, "judged a minute after the peak");
    Test.assertEqualMessage(rec.breakGoal(), 360, "five minutes added");
    Test.assertMessage(rec.breakExtended(), "extended");
    Test.assertEqualMessage(rec.coach(), "Not recovered · 125 bpm, cool down longer", "told why");
    rec.mark();
    Test.assertMessage(!rec.breakExtended(), "the next round starts clean");
    var quiet = new SaunaTracker();
    quiet.coachRecovery = false;
    quiet.coachStand = false;
    quiet.plan.roundTarget = 0;
    quiet.plan.roundMax = 0;
    quiet.plan.heatCap = 0;
    quiet.mark();
    quiet.tick(140, 40.0);
    quiet.mark();
    Test.assertEqualMessage(quiet.coach(), "Drink some water", "no stand-up line when off");
    var plain = EVENT_NONE;
    for (var s = 1; s <= 70; s++) {
        var e = quiet.tick(125, 40.0);
        if (e != EVENT_NONE) { plain = e; }
    }
    Test.assertMessage(plain == EVENT_RECOVERY && !quiet.breakExtended(), "just the plain recovery report when off");

    // the readings ride along
    quiet.tickAll(100, 40.0, 14, 37);
    Test.assertMessage(quiet.breath == 14 && quiet.stress == 37, "breathing and stress kept");
    var row = quiet.historyRow(1, 62, 51);
    Test.assertMessage(row.size() == SaunaHistory.STRIDE && row[SaunaHistory.BB_START] == 62 && row[SaunaHistory.BB_END] == 51, "Body Battery in the row");
    Test.assertEqualMessage(quiet.historyRow(1, null, null)[SaunaHistory.BB_END], -1, "unknown Body Battery");

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
    Test.assertEqualMessage(u.coach(), "LAP when you go in", "told to use LAP");
    Test.assertEqualMessage(u.historyRow(5, null, null)[SaunaHistory.DROP], -1, "no drop recorded");
    return true;
}

(:test)
function testHrv(logger as Logger) as Boolean {
    // successive differences 20, -30, 20 ... over twelve beats
    var beats = [800, 820, 790, 810, 790, 810, 790, 810, 790, 810, 790, 810] as Array<Number>;
    var v = SaunaHrv.rmssd(beats) as Number;
    logger.debug("rmssd " + v);
    Test.assertMessage(v >= 21 && v <= 23, "about 22 ms: " + v);
    Test.assertMessage(SaunaHrv.rmssd([800, 820, 790] as Array<Number>) == null, "too few beats");
    var w = new HrvWindow();
    w.add([800, 820] as Array<Number>);
    w.add([3000, 790, 810] as Array<Number>);   // an artefact breaks the chain
    Test.assertEqualMessage(w.beats(), 2, "two differences, the artefact and its neighbour dropped");
    w.add(beats);
    Test.assertMessage(w.value() != null, "enough now");
    w.reset();
    Test.assertMessage(w.value() == null && w.beats() == 0, "a fresh minute");
    w.add([800] as Array<Number>);
    Test.assertEqualMessage(w.beats(), 1, "the chain carried across the reset");
    return true;
}

(:test)
function testHistory(logger as Logger) as Boolean {
    SaunaHistory.clear();
    Test.assertEqualMessage(SaunaHistory.count(), 0, "empty");
    Test.assertMessage(SaunaHistory.last() == null && SaunaHistory.visit(0) == null, "nothing to show");
    var now = Time.now().value();
    SaunaHistory.add([now - 20 * 86400, KIND_SAUNA, 2, 1500, 900, 130, 25, 440, 70, 60] as Array<Number>);
    SaunaHistory.add([now - 60, KIND_STEAM, 3, 2290, 1200, 142, 31, 481, 62, 51] as Array<Number>);
    var detail = SaunaText.detail(SaunaHistory.last());
    Test.assertMessage(detail.find("Body Battery 62→51") != null, "Body Battery in the detail: " + detail);
    Test.assertEqualMessage(SaunaHistory.count(), 2, "two visits");
    var last = SaunaHistory.last() as Array<Number>;
    Test.assertEqualMessage(last[SaunaHistory.KIND], KIND_STEAM, "newest first");
    var older = SaunaHistory.visit(1) as Array<Number>;
    Test.assertEqualMessage(older[SaunaHistory.ROUNDS], 2, "then the older one");
    Test.assertMessage(SaunaHistory.visit(2) == null, "past the end");
    var sauna = SaunaHistory.lastOf(KIND_SAUNA) as Array<Number>;
    Test.assertEqualMessage(sauna[SaunaHistory.ROUNDS], 2, "last sauna");
    Test.assertEqualMessage(SaunaHistory.avgDrop(KIND_STEAM) as Number, 31, "steam's usual drop");
    Test.assertEqualMessage(SaunaHistory.avgDrop(KIND_SAUNA) as Number, 25, "sauna's usual drop");
    // this week: the steam visit a minute ago counts, the sauna three weeks ago does not
    var start = SaunaHistory.weekStart();
    Test.assertMessage(start <= now && now - start < 7 * 86400, "the week began within the last seven days");
    var week = SaunaHistory.thisWeek(KIND_STEAM);
    Test.assertMessage(week[0] == 1 && week[1] == 2290, "one steam this week: " + week);
    Test.assertEqualMessage(SaunaHistory.thisWeek(KIND_SAUNA)[0], 0, "no sauna this week");
    Test.assertEqualMessage(SaunaHistory.thisWeek(-1)[0], 1, "one visit of any kind");
    var line = SaunaText.week(new SaunaPlan(KIND_STEAM));
    Test.assertEqualMessage(line, "Week 1/3 steams · 38/40 min", "week line: " + line);
    for (var i = 0; i < SaunaHistory.MAX; i++) {
        SaunaHistory.add([1730200000 + i, KIND_SAUNA, 1, 600, 0, 0, -1, -1000, -1, -1] as Array<Number>);
    }
    Test.assertEqualMessage(SaunaHistory.count(), SaunaHistory.MAX, "capped");
    var oldest = SaunaHistory.visit(SaunaHistory.MAX - 1) as Array<Number>;
    Test.assertEqualMessage(oldest[SaunaHistory.START], 1730200000, "the first two fell off");
    // rows from the seven-column days are ignored rather than misread
    Toybox.Application.Storage.setValue(SaunaHistory.KEY, [1, 2, 3, 4, 5, 6, 7] as Array<Toybox.Application.Storage.ValueType>);
    Test.assertEqualMessage(SaunaHistory.count(), 0, "old layout ignored");
    SaunaHistory.clear();
    return true;
}

(:test)
function testRecorder(logger as Logger) as Boolean {
    var t = new SaunaTracker();
    t.plan = new SaunaPlan(KIND_STEAM);
    var rec = new SaunaRecorder();
    var started = rec.start(true, KIND_STEAM, true);
    logger.debug("session started: " + started);
    if (!started) {
        logger.debug("the simulator refused a session; skipping");
        return true;
    }
    Test.assertMessage(rec.recording(), "recording");
    for (var s = 0; s < 5; s++) {
        t.tickAll(100, 40.0 + s, 14, 40);
        rec.record(t.temp, t.phase, t.breath, t.stress, s == 0 ? 35 : null);
    }
    t.mark();
    rec.lap(null);
    rec.pause();
    Test.assertMessage(!rec.recording() && rec.active(), "paused");
    rec.resume();
    Test.assertMessage(rec.recording(), "resumed");
    rec.discard();
    Test.assertMessage(!rec.active(), "gone");
    Test.assertMessage(!rec.save(t, 62, 51), "nothing to save after a discard");
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
    SaunaHistory.add([Time.now().value() - 3600, KIND_STEAM, 2, 1450, 1200, 131, 24, 441, 62, 51] as Array<Number>);
    glance.onUpdate(glanceDc);
    Test.assertMessage(SaunaText.fahrenheit, "the glance applied the default unit, Fahrenheit");

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

    // touches: the corners by the cues act as the buttons, the middle does nothing
    var r = (w < h ? w : h) / 2;
    Test.assertEqualMessage(view.cueAt(w / 2, h / 2), TAP_NONE, "the centre is not a button");
    Test.assertEqualMessage(view.cueAt(w / 2 + (r * 0.8).toNumber(), h / 2 - (r * 0.5).toNumber()), TAP_START, "two o'clock is START");
    Test.assertEqualMessage(view.cueAt(w / 2 + (r * 0.75).toNumber(), h / 2 + (r * 0.5).toNumber()), TAP_BACK, "four o'clock is BACK");
    Test.assertEqualMessage(view.cueAt(w / 2 - (r * 0.9).toNumber(), h / 2), TAP_UP, "nine o'clock is UP");
    Test.assertEqualMessage(view.cueAt(w / 2 - (r * 0.7).toNumber(), h / 2 + (r * 0.5).toNumber()), TAP_DOWN, "eight o'clock is DOWN");
    Test.assertEqualMessage(view.cueAt(w / 2, h - 5), TAP_NONE, "six o'clock is nothing");

    // a guided steam visit without a FIT file: arrival, a round, a break with a recovery
    view.start(KIND_STEAM, true, false);
    Test.assertMessage(view.recording() && view.guided(), "recording, guided");
    var t = view.tracker() as SaunaTracker;
    Test.assertEqualMessage(t.plan.kind, KIND_STEAM, "the steam plan");
    Test.assertEqualMessage(t.baselineDrop as Number, 24, "the usual steam drop came from the history");
    logger.debug("heart-rate ceiling from the simulator's profile: " + t.hrCeiling + " bpm; coaching switches " + t.coachHrHigh + " " + t.coachRecovery + " " + t.coachStand);
    Test.assertMessage(t.coachHrHigh && t.coachRecovery && t.coachStand && t.recoveryHr == 110, "the coaching defaults are on");
    t.auto = false;   // the door is marked by hand here; the thermometer logic has its own test
    view.onUpdate(screen);
    Test.assertEqualMessage(view.startCue(), "END", "recording START cue");
    Test.assertEqualMessage(view.backCue(), "IN", "BACK goes in");
    Test.assertMessage(delegate.onBack() && t.phase == PHASE_SAUNA, "BACK marks the door while recording");
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
    Test.assertMessage(row[SaunaHistory.KIND] == KIND_STEAM && row[SaunaHistory.ROUNDS] == 1, "one steam round saved");
    view.onUpdate(screen);
    // a free sauna: same recording, no targets, and the switch mid-visit
    view.start(KIND_SAUNA, false, false);
    var f = view.tracker() as SaunaTracker;
    Test.assertMessage(f.plan.rounds == 3 && !f.guided, "a free sauna this time");
    f.auto = false;
    view.mark();
    view.onUpdate(screen);
    Test.assertEqualMessage(f.coach(), "Free session · out when you like", "free coaching");
    view.setGuided(true);
    Test.assertMessage(view.guided() && f.coach().find(" left") != null, "guided from here: " + f.coach());
    view.discard();
    Test.assertMessage(!view.recording() && SaunaHistory.count() == 2, "discarded");
    SaunaHistory.clear();

    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}
