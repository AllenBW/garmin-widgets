import Toybox.Application.Properties;
import Toybox.Application.Storage;
import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Test;
import Toybox.Time;

// Run No Evil tests for Stretching God: scripts/test.sh stretch [device].
// Sessions are played by feeding milliseconds; nothing needs the sensors.

// The watch's timeline and the generator's lengths agree, every routine, every level
(:test)
function testLengths(logger as Logger) as Boolean {
    for (var r = 0; r < StretchRoutines.COUNT; r++) {
        for (var li = 0; li < 3; li++) {
            var s = new StretchSession(r, StretchSettings.LEVELS[li], false);
            var sec = (s.total + 500) / 1000;
            Test.assertEqualMessage(sec, StretchRoutines.SECONDS[r][li], StretchRoutines.NAMES[r] + " at level " + li);
        }
    }
    return true;
}

// Playing a routine through: phases in order, both sides, the buzzes, the end
(:test)
function testPlay(logger as Logger) as Boolean {
    var s = new StretchSession(StretchRoutines.R_MORNING, 100, false);
    Test.assertEqualMessage(s.phase(), PH_SETUP, "starts setting up");
    Test.assertEqualMessage(s.setKind(), SET_FIRST, "the first stretch");
    Test.assertEqualMessage(s.blend(), 0.0, "in the start pose");
    var buzzes = new Array<Number>[BUZZ_COUNT];
    for (var b = 0; b < BUZZ_COUNT; b++) {
        buzzes[b] = 0;
    }
    var sawRight = false;
    var sawHold = false;
    var steps = 0;
    var lastStep = -1;
    var guard = 0;
    while (!s.done() && guard < 100000) {
        var b = s.tick(100);
        buzzes[b] += 1;
        var t = s.blend();
        Test.assertMessage(t >= 0.0 && t <= 1.0, "blend in range: " + t);
        Test.assertMessage(s.line().length() > 0, "always a line");
        if (s.side() == 1) {
            sawRight = true;
        }
        if (s.phase() == PH_HOLD) {
            sawHold = true;
        }
        if (s.stepIndex() != lastStep) {
            lastStep = s.stepIndex();
            steps++;
        }
        guard++;
    }
    Test.assertMessage(s.done(), "plays to the end");
    Test.assertEqualMessage(guard * 100, s.total + (s.total % 100 == 0 ? 0 : 100 - s.total % 100), "takes the planned time");
    Test.assertEqualMessage(steps, s.steps, "every stretch");
    Test.assertMessage(sawRight && sawHold, "both sides, and holds");
    Test.assertEqualMessage(buzzes[BUZZ_DONE], 1, "one done buzz");
    Test.assertEqualMessage(buzzes[BUZZ_NEXT], s.steps - 1, "a next buzz per new stretch");
    Test.assertMessage(buzzes[BUZZ_SWITCH] > 0 && buzzes[BUZZ_GO] > 0 && buzzes[BUZZ_RELEASE] > 0, "switch, go, release");
    Test.assertMessage(buzzes[BUZZ_TICK] >= 3 * s.steps, "3, 2, 1 before every stretch: " + buzzes[BUZZ_TICK]);
    Test.assertMessage(buzzes[BUZZ_TEN] > 0, "ten seconds left in the long holds");
    Test.assertEqualMessage(s.line(), "Done · nice work", "the last word");
    return true;
}

// Every buzz has a pattern the watch can play, a name and a meaning, and
// the setup shows the stretch before settling in the start pose
(:test)
function testBuzzes(logger as Logger) as Boolean {
    for (var i = 0; i < StretchBuzz.GUIDE.size(); i++) {
        var b = StretchBuzz.GUIDE[i];
        var pat = StretchBuzz.pattern(b);
        Test.assertMessage(pat.size() >= 2 && pat.size() % 2 == 0 && pat.size() <= 16, StretchBuzz.name(b) + " pattern");
        for (var k = 1; k < pat.size(); k += 2) {
            Test.assertMessage(pat[k] > 0 && pat[k - 1] >= 0 && pat[k - 1] <= 100, StretchBuzz.name(b) + " step");
        }
        Test.assertMessage(StretchBuzz.meaning(b).length() > 0, "meaning");
    }
    Test.assertEqualMessage(StretchBuzz.GUIDE.size(), BUZZ_COUNT - 1, "the guide plays every buzz");
    Test.assertEqualMessage(StretchBuzz.BASIC.size(), BUZZ_COUNT - 3, "without contract-relax, all but push and relax");
    Test.assertEqualMessage(StretchBuzz.length(BUZZ_DONE), 1040, "the longest buzz sets the tutorial's scale");
    var s = new StretchSession(StretchRoutines.R_AFTER_RUN, 100, false);
    Test.assertMessage(s.demoing(), "a setup shows the stretch");
    s.tick(2500);
    Test.assertMessage(s.blend() > 0.99, "at full stretch in the demo");
    s.tick(s.remaining() - 2500);
    Test.assertMessage(!s.demoing(), "then the start pose");
    Test.assertEqualMessage(s.blend(), 0.0, "for the last seconds");
    return true;
}

// Go now, skip, skip a stretch, ten seconds more
(:test)
function testControls(logger as Logger) as Boolean {
    var s = new StretchSession(StretchRoutines.R_AFTER_RUN, 100, false);
    s.advance();
    Test.assertEqualMessage(s.phase(), PH_EASE, "go now ends the setup");
    s.tick(StretchSession.EASE);
    Test.assertEqualMessage(s.phase(), PH_HOLD, "then the hold");
    var len = s.phaseLength();
    Test.assertMessage(s.extend(10000), "a hold takes ten seconds more");
    Test.assertEqualMessage(s.phaseLength(), len + 10000, "longer");
    Test.assertEqualMessage(s.skip(), BUZZ_SWITCH, "skip goes to the other side");
    Test.assertEqualMessage(s.side(), 1, "right side");
    Test.assertEqualMessage(s.phase(), PH_SETUP, "setting up");
    Test.assertMessage(!s.extend(10000), "no more time in a setup");
    var step = s.stepIndex();
    Test.assertEqualMessage(s.skipStretch(), BUZZ_NEXT, "skip the stretch");
    Test.assertEqualMessage(s.stepIndex(), step + 1, "the next one");
    Test.assertEqualMessage(s.side(), 0, "from the left");
    s.advance();
    s.tick(1000);
    Test.assertEqualMessage(s.easeOff(), BUZZ_RELEASE, "ease off releases");
    Test.assertEqualMessage(s.phase(), PH_RELEASE, "out of the stretch");
    Test.assertEqualMessage(s.line(), "Ease off · smaller range", "and says why");
    Test.assertEqualMessage(s.easeOff(), BUZZ_NONE, "nothing to ease off in a release");
    s.tick(StretchSession.RELEASE);
    Test.assertEqualMessage(s.phase(), PH_SETUP, "then on as usual");
    while (!s.done()) {
        s.skipStretch();
    }
    Test.assertMessage(s.done(), "skipping everything ends it");
    return true;
}

// Contract-relax only where the routine and the stretch allow it
(:test)
function testContractRelax(logger as Logger) as Boolean {
    var plain = new StretchSession(StretchRoutines.R_AFTER_RUN, 100, false);
    var pnf = new StretchSession(StretchRoutines.R_AFTER_RUN, 100, true);
    Test.assertMessage(pnf.total > plain.total, "contract-relax adds the push");
    var sawPush = false;
    while (!pnf.done()) {
        pnf.tick(250);
        if (pnf.phase() == PH_PUSH) {
            sawPush = true;
            Test.assertEqualMessage(pnf.line(), StretchData.CUES[pnf.stretch()][4], "the stretch's own push");
        }
    }
    Test.assertMessage(sawPush, "pushes");
    var bed = new StretchSession(StretchRoutines.R_BEDTIME, 100, true);
    var bedPlain = new StretchSession(StretchRoutines.R_BEDTIME, 100, false);
    Test.assertEqualMessage(bed.total, bedPlain.total, "never at bedtime");
    var run = new StretchSession(StretchRoutines.R_BEFORE_RUN, 150, true);
    var runPlain = new StretchSession(StretchRoutines.R_BEFORE_RUN, 100, false);
    Test.assertEqualMessage(run.total, runPlain.total, "nor before a run, nor longer holds");
    return true;
}

// The breath: back a touch on the in-breath, deeper on the out
(:test)
function testBreath(logger as Logger) as Boolean {
    var s = new StretchSession(StretchRoutines.R_AFTER_RUN, 100, false);
    s.advance();
    s.tick(StretchSession.EASE);
    Test.assertEqualMessage(s.phase(), PH_HOLD, "holding");
    Test.assertEqualMessage(s.blend(), 1.0, "full stretch as the hold begins");
    Test.assertMessage(s.breathingIn(), "breathing in first");
    s.tick(5000);
    Test.assertMessage(!s.breathingIn(), "then out");
    Test.assertMessage(s.blend() < 0.95, "eased back on the in-breath");
    s.tick(4900);
    Test.assertMessage(s.blend() > 0.99, "deep again by the end of the out-breath");

    // the slow breath at bedtime: the figure fills and empties with it
    var bed = new StretchSession(StretchRoutines.R_BEDTIME, 100, false);
    bed.advance();
    Test.assertEqualMessage(bed.phase(), PH_BREATHE, "breathing");
    Test.assertEqualMessage(bed.line(), "Breathe in slowly", "in");
    bed.tick(5000);
    Test.assertMessage(bed.blend() > 0.99, "full at the top of the breath");
    Test.assertEqualMessage(bed.line(), "And out, slowly", "out");
    bed.tick(5000);
    Test.assertMessage(bed.blend() < 0.01, "empty at the bottom");
    // then up off the floor to the wall
    bed.skip();
    Test.assertEqualMessage(bed.move(), MOVE_UP, "getting up");
    Test.assertEqualMessage(bed.line(), "Stand up slowly", "said so");
    Test.assertEqualMessage(bed.phaseLength(), StretchSession.SETUP_GET_UP, "time to get up");
    bed.tick(3000);
    Test.assertEqualMessage(bed.line(), StretchData.CUES[bed.stretch()][0], "then the setup");
    return true;
}

// Which routine suits now
(:test)
function testPlan(logger as Logger) as Boolean {
    var h = 3600;
    var wake = 7 * h;
    var sleep = 23 * h;
    var s = StretchPlan.suggest(7 * h + 600, wake, sleep, -1, -1, 0, 99, false);
    Test.assertEqualMessage(s[0], StretchRoutines.R_MORNING, "just up");
    s = StretchPlan.suggest(22 * h, wake, sleep, -1, -1, 0, 99, false);
    Test.assertEqualMessage(s[0], StretchRoutines.R_BEDTIME, "an hour before bed");
    s = StretchPlan.suggest(15 * 60, wake, 23 * h + 1800, -1, -1, 0, 99, false);
    Test.assertEqualMessage(s[0], StretchRoutines.R_BEDTIME, "past midnight, still wind-down");
    s = StretchPlan.suggest(22 * h, wake, sleep, Activity.SPORT_RUNNING, 1800, 0, 99, true);
    Test.assertEqualMessage(s[0], StretchRoutines.R_AFTER_RUN, "after a run, even late");
    Test.assertEqualMessage(StretchPlan.why([s[0], s[1], Activity.SPORT_RUNNING] as Array<Number>), "AFTER YOUR RUN", "why");
    s = StretchPlan.suggest(18 * h, wake, sleep, Activity.SPORT_CYCLING, 600, 0, 0, true);
    Test.assertEqualMessage(s[0], StretchRoutines.R_AFTER_RIDE, "after a ride");
    s = StretchPlan.suggest(18 * h, wake, sleep, Activity.SPORT_CYCLING, 3 * h, 0, 0, true);
    Test.assertEqualMessage(s[0], StretchRoutines.R_QUICK, "a ride hours ago is forgotten");
    s = StretchPlan.suggest(11 * h, wake, sleep, -1, -1, 4, 0, false);
    Test.assertEqualMessage(s[0], StretchRoutines.R_DESK, "sitting too long");
    s = StretchPlan.suggest(15 * h, wake, sleep, -1, -1, 0, 3, false);
    Test.assertEqualMessage(s[0], StretchRoutines.R_FULL, "a rest day afternoon");
    s = StretchPlan.suggest(15 * h, wake, sleep, -1, -1, 0, 1, false);
    Test.assertEqualMessage(s[0], StretchRoutines.R_QUICK, "full body only every other day");
    s = StretchPlan.suggest(15 * h, wake, sleep, -1, -1, 0, 3, true);
    Test.assertEqualMessage(s[0], StretchRoutines.R_QUICK, "not after an active day");
    return true;
}

// Days in a row and the week
(:test)
function testStreak(logger as Logger) as Boolean {
    var now = Time.now().value();
    var day = 86400;
    var rows = [[now - 3 * day, 0, 400, 1], [now - 2 * day, 0, 400, 1], [now - day, 1, 500, 1]] as Array<Array<Number> >;
    Test.assertEqualMessage(StretchHistory.streak(now, rows), 3, "three days up to yesterday");
    rows.add([now, 0, 300, 1] as Array<Number>);
    Test.assertEqualMessage(StretchHistory.streak(now, rows), 4, "and today");
    Test.assertEqualMessage(StretchHistory.week(now, rows), 4, "four this week");
    Test.assertEqualMessage(StretchHistory.streak(now + 3 * day, rows), 0, "broken");
    Test.assertEqualMessage(StretchText.clock(462000), "7:42", "clock");
    Test.assertEqualMessage(StretchText.clock(-5), "0:00", "never negative");
    var two = [[now - 9 * day, 0, 400, 1], [now - 8 * day, 0, 400, 1], [now - 10 * day, 0, 400, 1],
               [now - 2 * day, 0, 400, 1], [now - day, 0, 400, 1], [now, 0, 400, 1]] as Array<Array<Number> >;
    Test.assertMessage(StretchHistory.readyForMore(now, two, 1), "three a week for two weeks");
    Test.assertMessage(!StretchHistory.readyForMore(now, two, 2), "already deep");
    Test.assertMessage(!StretchHistory.readyForMore(now, rows, 1), "not yet");
    return true;
}

// Every stretch stands on the ground and fits its box, at every blend
(:test)
function testFigures(logger as Logger) as Boolean {
    for (var i = 0; i < StretchData.COUNT; i++) {
        for (var k = 0; k <= 4; k++) {
            var pts = StretchFigure.placed(i, k / 4.0);
            var lo = 9.0;
            for (var j = 1; j < 2 * StretchFigure.JOINTS; j += 2) {
                if (pts[j] < lo) {
                    lo = pts[j];
                }
            }
            Test.assertMessage(lo >= -0.001, StretchData.NAMES[i] + " not below the ground");
            Test.assertMessage(lo < 0.07, StretchData.NAMES[i] + " standing on something");
        }
        var pnf = (StretchData.META[i * StretchFigure.META + 1] & StretchFigure.F_PNF) != 0;
        Test.assertMessage(StretchData.CUES[i].size() == (pnf ? 5 : 4), StretchData.NAMES[i] + " has its cues");
    }
    return true;
}

// Draw every stretch and every screen
(:test)
function testDrawEveryMode(logger as Logger) as Boolean {
    Properties.setValue("Record", false);
    var w = 454;
    var h = 454;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();
    for (var i = 0; i < StretchData.COUNT; i++) {
        StretchFigure.draw(dc, i, 0.5, i % 2 == 1, w / 2, 280, 220, 150, 0xFFFFFF, 0x777777, 0xFF8A4C);
        StretchFigure.draw(dc, i, 1.0, false, w / 2, 280, 220, 150, 0x333333, 0x333333, null);
    }
    var view = new StretchView();
    view.onLayout(dc);
    view.onUpdate(dc);
    for (var r = 0; r < StretchRoutines.COUNT; r++) {
        view.start(r);
        for (var k = 0; k < 40; k++) {
            view.onUpdate(dc);
            view.skip();
        }
        view.finish(false);
        view.onUpdate(dc);
        view.toIdle();
    }
    // the tutorial: before the first routine, every page, then the routine
    Storage.deleteValue(StretchBuzz.SEEN);
    view.go(0);
    Test.assertEqualMessage(view.state(), STATE_GUIDE, "the first GO teaches the buzzes");
    for (var k = 0; k < 20 && view.state() == STATE_GUIDE; k++) {
        view.onUpdate(dc);
        view.guideAgain();
        view.onUpdate(dc);
        view.guideBack();
        view.guideNext();
        view.guideNext();
    }
    Test.assertEqualMessage(view.state(), STATE_RUN, "then the routine");
    view.discard();
    view.go(0);
    Test.assertEqualMessage(view.state(), STATE_RUN, "once only");
    view.discard();
    view.guide(-1, 0);
    view.leaveGuide();
    Test.assertEqualMessage(view.state(), STATE_IDLE, "from the list, BACK goes home");
    Storage.deleteValue(StretchBuzz.SEEN);
    Properties.setValue("Record", true);
    StretchHistory.clear();   // the routines skipped to the end counted as done
    return true;
}
