import Toybox.Activity;
import Toybox.Application.Properties;
import Toybox.Application.Storage;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Test;
import Toybox.Time;
import Toybox.WatchUi;

// Trying to break it: random presses in every state, every word against the
// round screen and the button words, every figure against what's around it.

(:test)
class Adversary {
    static function next(seed as Number) as Number {
        return (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    }

    static function checkSession(s as StretchSession, what as String) as Void {
    var b = s.blend();
    Test.assertMessage(b >= 0.0 && b <= 1.0, what + " blend " + b);
    Test.assertMessage(s.remaining() >= 0, what + " remaining " + s.remaining());
    Test.assertMessage(s.holdLeft() >= 0, what + " holdLeft " + s.holdLeft());
    var d = s.holdDone();
    Test.assertMessage(d >= 0.0 && d <= 1.0, what + " holdDone " + d);
    Test.assertMessage(s.left() >= 0, what + " left " + s.left());
    Test.assertMessage(s.line().length() > 0, what + " no line");
    Test.assertMessage(s.stepIndex() >= 0 && s.stepIndex() <= s.steps, what + " step " + s.stepIndex());
    Test.assertMessage(s.stretch() >= 0 && s.stretch() < StretchData.COUNT, what + " stretch " + s.stretch());
    Test.assertMessage(s.side() == 0 || s.side() == 1, what + " side");
        if (s.phase() == PH_REPS) {
            Test.assertMessage(s.rep() >= 1 && s.rep() <= s.repCount(), what + " rep " + s.rep() + "/" + s.repCount());
        }
    }
}

// Any control, at any moment, in every routine at every level: nothing
// goes out of range, time only goes forward, and it always ends
(:test)
function testFuzzSession(logger as Logger) as Boolean {
    var seed = 12345;
    for (var r = 0; r < StretchRoutines.COUNT; r++) {
        for (var li = 0; li < 3; li++) {
            for (var pnf = 0; pnf < 2; pnf++) {
                var s = new StretchSession(r, StretchSettings.LEVELS[li], pnf == 1);
                var what = StretchRoutines.NAMES[r] + " L" + li + " P" + pnf;
                var was = 0;
                for (var k = 0; k < 150 && !s.done(); k++) {
                    seed = Adversary.next(seed);
                    var op = (seed >> 8) % 7;
                    seed = Adversary.next(seed);
                    var ms = (seed >> 8) % 6000;
                    var buzz = BUZZ_NONE;
                    if (op == 0 || op == 1) {
                        buzz = s.tick(ms);
                    } else if (op == 2) {
                        buzz = s.advance();
                    } else if (op == 3) {
                        buzz = s.skip();
                    } else if (op == 4) {
                        buzz = s.skipStretch();
                    } else if (op == 5) {
                        buzz = s.easeOff();
                    } else {
                        s.extend(10000);
                    }
                    Test.assertMessage(buzz >= 0 && buzz < BUZZ_COUNT, what + " buzz " + buzz);
                    Test.assertMessage(s.elapsed >= was, what + " time went back");
                    was = s.elapsed;
                    Adversary.checkSession(s, what + " op" + op);
                }
                var guard = 0;
                while (!s.done() && guard < 500) {
                    s.skipStretch();
                    guard++;
                }
                Test.assertMessage(s.done(), what + " never ended");
                Adversary.checkSession(s, what + " at the end");
                Test.assertEqualMessage(s.tick(1000), BUZZ_NONE, what + " no buzz after the end");
                Test.assertEqualMessage(s.skip(), BUZZ_NONE, what + " no skip after the end");
                Test.assertEqualMessage(s.skipStretch(), BUZZ_NONE, what + " no skip stretch after the end");
                Test.assertEqualMessage(s.easeOff(), BUZZ_NONE, what + " no ease off after the end");
                Test.assertMessage(!s.extend(1000), what + " no extending after the end");
            }
        }
    }
    return true;
}

// Every button the watch has, in any order, with the menus' choices
// simulated (a test can't press a Menu2), recording on and off
(:test)
function testFuzzButtons(logger as Logger) as Boolean {
    var dc = (Graphics.createBufferedBitmap({:width => 454, :height => 454}).get() as Graphics.BufferedBitmap).getDc();
    var seed = 777;
    for (var run = 0; run < 2; run++) {
        Properties.setValue("Record", run == 1);
        Storage.deleteValue(StretchBuzz.SEEN);
        Storage.deleteValue(StretchText.SAFETY_SEEN);
        var view = new StretchView();
        var keys = new StretchDelegate(view);
        view.onLayout(dc);
        for (var k = 0; k < 1500; k++) {
            seed = Adversary.next(seed);
            var op = (seed >> 8) % 8;
            seed = Adversary.next(seed);
            var pick = (seed >> 8) % StretchRoutines.COUNT;
            var st = view.state();
            if (op == 0) {
                // START: the pause menu's choices are simulated below
                if (view.running()) {
                    view.pause();
                    var choice = pick % 5;
                    if (choice == 0) {
                        view.resume();
                    } else if (choice == 1) {
                        view.resume();
                        view.skipStretch();
                    } else if (choice == 2) {
                        view.finish(false);
                    } else if (choice == 3) {
                        view.discard();
                    } else {
                        view.resume();   // BACK out of the menu
                    }
                } else {
                    keys.pressStart();
                }
            } else if (op == 1) {
                // a behaviour declined goes on to the raw key, as on the watch
                if (!keys.onBack() && !keys.press(WatchUi.KEY_ESC)) {
                    view.toIdle();   // the app would close; start again
                }
            } else if (op == 2 || op == 3) {
                if (st == STATE_IDLE) {
                    // the routines list
                    if (pick == 0) {
                        view.guide(-1, 0);
                    } else {
                        view.go(pick);
                    }
                } else if (op == 2) {
                    if (!keys.onPreviousPage()) {
                        keys.press(WatchUi.KEY_UP);
                    }
                } else if (!keys.onNextPage()) {
                    keys.press(WatchUi.KEY_DOWN);
                }
            } else if (op == 4 && !view.running() && st != STATE_IDLE) {
                keys.onMenu();   // running or idle it opens a real menu, simulated above
            } else if (op == 5 && st == STATE_RUN) {
                view.onFrame();
            } else if (op == 6 && st == STATE_GUIDE) {
                view.onGuide();
            }
            view.onUpdate(dc);
            Test.assertMessage(view.state() >= STATE_IDLE && view.state() <= STATE_SAFETY, "a known state");
            Test.assertMessage(view.routine() >= 0 && view.routine() < StretchRoutines.COUNT, "a known routine");
        }
        view.shutdown();
    }
    Properties.setValue("Record", true);
    Storage.deleteValue(StretchBuzz.SEEN);
    Storage.deleteValue(StretchText.SAFETY_SEEN);
    StretchHistory.clear();
    return true;
}

// Skipping isn't stretching: no credit for it, and nothing saved
(:test)
function testCredit(logger as Logger) as Boolean {
    Properties.setValue("Record", false);
    StretchHistory.clear();
    var view = new StretchView();
    view.start(StretchRoutines.R_QUICK);
    for (var k = 0; k < 200 && view.state() == STATE_RUN; k++) {
        view.skipStretch();
    }
    Test.assertEqualMessage(view.state(), STATE_DONE, "skipped to the end");
    Test.assertMessage(!view.complete(), "not a completed routine");
    Test.assertEqualMessage(StretchHistory.rows().size(), 0, "not in the history, no streak");

    // GO through every setup counts nothing either
    var s = new StretchSession(StretchRoutines.R_QUICK, 100, false);
    s.advance();
    Test.assertEqualMessage(s.elapsed, 0, "a setup skipped isn't time played");

    // played through, with GO on the setups: the real thing
    view = new StretchView();
    view.start(StretchRoutines.R_QUICK);
    var guard = 0;
    while (view.state() == STATE_RUN && guard < 500) {
        var was = view.session();
        if (was != null && was.phase() == PH_SETUP) {
            view.skip();
        } else if (was != null) {
            view.played(was, was.tick(was.remaining()));
        }
        guard++;
    }
    Test.assertMessage(view.complete(), "a completed routine");
    Test.assertEqualMessage(StretchHistory.rows().size(), 1, "in the history");
    StretchHistory.clear();
    Properties.setValue("Record", true);
    return true;
}

// Ease off works in reps, and takes the rest of the stretch with it
(:test)
function testEaseOffReps(logger as Logger) as Boolean {
    var s = new StretchSession(StretchRoutines.R_BEFORE_RUN, 100, false);
    while (s.phase() != PH_REPS || !s.sided()) {
        s.advance();
    }
    var step = s.stepIndex();
    s.tick(1000);
    Test.assertEqualMessage(s.easeOff(), BUZZ_RELEASE, "out of the reps");
    Test.assertEqualMessage(s.phase(), PH_RELEASE, "a release");
    s.tick(StretchSession.EASED);
    Test.assertEqualMessage(s.stepIndex(), step + 1, "on to the next stretch");

    // on the last stretch, ease off ends the routine cleanly
    s = new StretchSession(StretchRoutines.R_AFTER_LIFT, 100, true);
    while (s.stepIndex() < s.steps - 1) {
        s.skipStretch();
    }
    while (s.phase() == PH_SETUP) {
        s.advance();
    }
    s.easeOff();
    s.tick(StretchSession.EASED);
    Test.assertMessage(s.done(), "the last one ends it");
    Test.assertEqualMessage(s.left(), 0, "with nothing left");
    return true;
}

// LEFT names the side drawn, and says what it means
(:test)
function testSides(logger as Logger) as Boolean {
    for (var i = 0; i < StretchData.COUNT; i++) {
        var flags = StretchData.META[i * StretchFigure.META + 1];
        var sided = (flags & StretchFigure.F_SIDED) != 0;
        var form = StretchData.META[i * StretchFigure.META + 13];
        Test.assertEqualMessage(form != 0, sided, StretchData.NAMES[i] + " says what a side means");
        if (!sided) {
            Test.assertMessage(!StretchFigure.mirrored(i, 0), "no sides, never mirrored");
            continue;
        }
        Test.assertMessage(StretchFigure.mirrored(i, 0) != StretchFigure.mirrored(i, 1), "the sides are opposites");
        // seen from the side LEFT faces left; from the front its left is on the screen's right
        Test.assertEqualMessage(StretchFigure.mirrored(i, 0), (flags & StretchFigure.F_FRONT) == 0, StretchData.NAMES[i]);
    }
    return true;
}

// A routine saved as Training isn't an activity to cool down from
(:test)
function testOwnActivity(logger as Logger) as Boolean {
    var rows = [[1000000, 0, 300, 1]] as Array<Array<Number> >;
    Test.assertMessage(StretchPlan.own(1000030, Activity.SPORT_TRAINING, rows), "our own");
    Test.assertMessage(!StretchPlan.own(1000030, Activity.SPORT_RUNNING, rows), "a run at that time is a run");
    Test.assertMessage(!StretchPlan.own(1009000, Activity.SPORT_TRAINING, rows), "a gym session later is real");
    Test.assertEqualMessage(StretchPlan.why([StretchRoutines.R_AFTER_LIFT, StretchPlan.WHY_AFTER, Activity.SPORT_TRAINING] as Array<Number>),
                            "AFTER TRAINING", "says what the watch knows");
    return true;
}

// Settings and stored rows no version of the app wrote
(:test)
function testBadData(logger as Logger) as Boolean {
    var dc = (Graphics.createBufferedBitmap({:width => 454, :height => 454}).get() as Graphics.BufferedBitmap).getDc();
    var now = Time.now().value();
    var bad = 0;
    var rows = [
        "junk", 7, [] as Array<Number>, [1, 2, 3] as Array<Number>, [["a", "b"]] as Array<Array<String> >,
        [[now]] as Array<Array<Number> >, [[null, 0, 0, 1]] as Array<Array<Null or Number> >,
        [[now, 99, 10, 1]] as Array<Array<Number> >, [[-5, 0, 0, 0]] as Array<Array<Number> >
    ] as Array<Object>;
    for (var i = 0; i < rows.size(); i++) {
        Storage.setValue(StretchHistory.KEY, rows[i] as Storage.ValueType);
        try {
            var view = new StretchView();
            view.onLayout(dc);
            view.onShow();
            view.onUpdate(dc);
            view.start(0);
            view.finish(true);
            view.onUpdate(dc);
            view.toIdle();
            view.shutdown();
            new StretchGlance().onUpdate(dc);
        } catch (e) {
            bad++;
            System.println("BADROW " + i + ": " + e.getErrorMessage());
        }
    }
    StretchHistory.clear();
    // odd settings, including a phone sending the wrong type
    var keys = ["Level", "ContractRelax", "Record", "Tones"] as Array<String>;
    var vals = [99, -1, "x", 2.5, true] as Array<Object>;
    for (var k = 0; k < keys.size(); k++) {
        var keep = Properties.getValue(keys[k]);
        for (var v = 0; v < vals.size(); v++) {
            try {
                Properties.setValue(keys[k], vals[v] as Properties.ValueType);
            } catch (e) {
                continue;   // the watch refused it, which is fine
            }
            try {
                var s = new StretchSession(0, StretchSettings.level(), StretchSettings.contractRelax());
                s.tick(1000);
                StretchSettings.record();
                StretchSettings.tones();
            } catch (e) {
                bad++;
                System.println("BADSETTING " + keys[k] + ": " + e.getErrorMessage());
            }
        }
        Properties.setValue(keys[k], keep as Properties.ValueType);
    }
    // the plan at every quarter hour, with any wake and sleep times
    var wakes = [0, 3600, 7 * 3600, 23 * 3600, 86399] as Array<Number>;
    var sports = [-1, 0, 1, 2, 10, 17, 255] as Array<Number>;
    for (var w = 0; w < wakes.size(); w++) {
        for (var z = 0; z < wakes.size(); z++) {
            for (var c = 0; c < 86400; c += 900) {
                var sport = sports[c / 900 % sports.size()];
                var p = StretchPlan.suggest(c, wakes[w], wakes[z], sport, c % 7200 - 600, c / 900 % 7, c / 900 % 4, c % 2 == 0);
                Test.assertMessage(p[0] >= 0 && p[0] < StretchRoutines.COUNT, "a real routine");
                Test.assertMessage(StretchPlan.why([p[0], p[1], sport] as Array<Number>).length() > 0, "a reason");
            }
        }
    }
    System.println("BAD DATA failures: " + bad);
    return true;
}

// Measuring: the width the round screen leaves at a line's top and bottom,
// and whether a line runs into a button word
(:test)
class Fit {
    var w as Number;
    var h as Number;
    var dc as Dc;
    var ink as Number;
    var label as FontType;
    var cap as Number;
    var ringed as Boolean = true;   // the running screen has the bezel ring to stay inside
    var problems as Number = 0;

    function initialize(context as Dc, labelFont as FontType, small as Number) {
        dc = context;
        w = context.getWidth();
        h = context.getHeight();
        ink = (small * 0.38).toNumber();
        cap = (small * 0.33).toNumber();
        label = labelFont;
    }

    function chord(y as Number) as Number {
        var d = (y - h / 2).abs() + cap;
        var r = ringed ? w / 2 - (h * 0.022).toNumber() - 4 : w / 2 - 4;
        return d >= r ? 0 : (2 * Math.sqrt(r * r - d * d)).toNumber();
    }

    // a word at a cue: [left, right, y]
    function cue(angle as Number, word as String) as Array<Number> {
        var r = w / 2 - (h * 0.06).toNumber();
        var rad = Math.toRadians(angle);
        var x = w / 2 + (r * Math.sin(rad)).toNumber();
        var y = h / 2 - (r * Math.cos(rad)).toNumber();
        var wd = dc.getTextWidthInPixels(word, label);
        return angle < 180 ? [x - wd, x, y] as Array<Number> : [x, x + wd, y] as Array<Number>;
    }

    function line(what as String, t as String, font as FontType, yf as Float, cues as Array<Array<Number> >) as Void {
        var y = (h * yf).toNumber();
        var wd = dc.getTextWidthInPixels(t, font);
        var room = chord(y);
        if (wd > room) {
            problems++;
            System.println("CLIPPED " + what + " '" + t + "' " + wd + " > " + room + " at " + yf);
        }
        for (var i = 0; i < cues.size(); i++) {
            var c = cues[i];
            if ((c[2] - y).abs() < 2 * ink && w / 2 + wd / 2 > c[0] && w / 2 - wd / 2 < c[1]) {
                problems++;
                System.println("CUE HIT " + what + " '" + t + "' at " + yf);
            }
        }
    }
}

(:test)
function testEveryWordFits(logger as Logger) as Boolean {
    var set = System.getDeviceSettings();
    var w = set.screenWidth;
    var h = set.screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();
    var small = (h * 0.083).toNumber();
    var floor = Graphics.getFontHeight(Graphics.FONT_XTINY);
    small = small < floor ? floor : small;
    var band = Lib.Fmt.vectorFont("RobotoCondensedBold", small, Graphics.FONT_SMALL);
    var name = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.10).toNumber(), Graphics.FONT_MEDIUM);
    var reg = Lib.Fmt.vectorFont("RobotoCondensedRegular", small, Graphics.FONT_SMALL);
    var fit = new Fit(dc, band, small);
    var view = new StretchView();
    view.onLayout(dc);

    var pause = fit.cue(Lib.Cues.START, "PAUSE");
    var skip = fit.cue(Lib.Cues.BACK, "SKIP");
    var up = fit.cue(Lib.Cues.UP, "+10");
    var ease = fit.cue(Lib.Cues.DOWN, "EASE OFF");
    var running = [pause, skip, up, ease] as Array<Array<Number> >;

    // running: each name, each side line, each thing the coach says
    for (var i = 0; i < StretchData.COUNT; i++) {
        fit.line("name", StretchData.NAMES[i].toUpper(), band, 0.135, running);
    }
    var subs = ["ROUND 2 OF 3", "BREATHE OUT", "BREATHE IN", "AGAIN", "NEXT"] as Array<String>;
    for (var i = 0; i < subs.size(); i++) {
        fit.line("sub", subs[i], band, 0.205, running);
    }
    for (var f = 0; f < StretchData.SIDE_PRE.size(); f++) {
        var word = StretchData.SIDE_PRE[f] + "RIGHT" + StretchData.SIDE_POST[f];
        fit.line("side", view.sideLine(dc, "SWITCH · ", word, ""), band, 0.205, running);
        fit.line("side", view.sideLine(dc, "AGAIN · ", word, ""), band, 0.205, running);
        fit.line("side", view.sideLine(dc, "NEXT · ", word, ""), band, 0.205, running);
        fit.line("side", view.sideLine(dc, "", word, " · 2 OF 3"), band, 0.205, running);
    }
    fit.line("coach", "Not saving to Connect", reg, 0.62, running);
    var said = {} as Dictionary<String, Boolean>;
    for (var r = 0; r < StretchRoutines.COUNT; r++) {
        for (var p = 0; p < 2; p++) {
            var s = new StretchSession(r, 100, p == 1);
            var guard = 0;
            while (!s.done() && guard < 20000) {
                s.tick(1000);
                said[s.line()] = true;
                guard++;
            }
        }
    }
    var lines = said.keys();
    var count = 0;
    for (var i = 0; i < lines.size(); i++) {
        var t = lines[i] as String;
        var parts = view.wrap(dc, t, reg, (w * 0.80).toNumber());
        count++;
        if (parts.size() == 1) {
            fit.line("coach", parts[0], reg, 0.62, running);
        } else {
            fit.line("coach1", parts[0], reg, 0.585, running);
            fit.line("coach2", parts[1], reg, 0.66, running);
        }
    }

    // the opening card, and every screen after it, have no ring
    fit.ringed = false;
    var go = fit.cue(Lib.Cues.START, "GO");
    var more = fit.cue(Lib.Cues.UP, "MORE");
    var idle = [go, more] as Array<Array<Number> >;
    var whys = ["GOOD MORNING", "WIND DOWN", "TIME TO MOVE", "REST DAY", "QUICK STRETCH",
                "AFTER YOUR RUN", "AFTER YOUR HIKE", "AFTER YOUR RIDE", "AFTER TRAINING"] as Array<String>;
    for (var i = 0; i < whys.size(); i++) {
        fit.line("why", whys[i], band, 0.13, idle);
    }
    for (var r = 0; r < StretchRoutines.COUNT; r++) {
        var steps = StretchData.STEPS[r].size() / 3;
        fit.line("idle name", StretchRoutines.NAMES[r], name, 0.235, idle);
        fit.line("idle minutes", StretchPlan.minutes(r) + " · " + StretchText.stretches(steps), reg, 0.34, idle);
        fit.line("idle about", StretchRoutines.ABOUT[r], reg, 0.72, idle);
    }
    var streaks = ["None yet this week", "12-day streak", "14 this week"] as Array<String>;
    for (var i = 0; i < streaks.size(); i++) {
        fit.line("idle streak", streaks[i], reg, 0.81, idle);
    }

    // the done screen
    var done = [fit.cue(Lib.Cues.START, "OK"), fit.cue(Lib.Cues.BACK, "EXIT")] as Array<Array<Number> >;
    fit.line("done", "WELL STRETCHED", band, 0.15, done);
    for (var r = 0; r < StretchRoutines.COUNT; r++) {
        fit.line("done name", StretchRoutines.NAMES[r], name, 0.255, done);
    }
    fit.line("done count", "59:59 · 12 stretches", reg, 0.35, done);
    fit.line("done count", "59:59 · skipped ahead", reg, 0.35, done);
    fit.line("done days", "days of stretching", reg, 0.60, done);
    var notes = ["Saved to Connect", "Not saved to Connect", "Too short to save", "Not recorded",
                 "Start easy, then build", "Try Deep holds next"] as Array<String>;
    for (var i = 0; i < notes.size(); i++) {
        fit.line("done note", notes[i], reg, 0.82, done);
    }

    // the tutorial
    var guide = [fit.cue(Lib.Cues.START, "NEXT"), fit.cue(Lib.Cues.BACK, "SKIP"), fit.cue(Lib.Cues.DOWN, "AGAIN")] as Array<Array<Number> >;
    for (var i = 0; i < StretchBuzz.GUIDE.size(); i++) {
        var b = StretchBuzz.GUIDE[i];
        fit.line("buzz name", StretchBuzz.name(b), name, 0.355, guide);
        var parts = view.wrap(dc, StretchBuzz.meaning(b), reg, (w * 0.80).toNumber());
        Test.assertEqualMessage(parts.size(), 1, StretchBuzz.meaning(b) + " on one line");
        fit.line("buzz says", parts[0], reg, 0.605, guide);
    }
    for (var r = 0; r < StretchRoutines.COUNT; r++) {
        fit.line("guide end", StretchRoutines.NAMES[r], name, 0.355, guide);
    }

    // the safety pages and the tutorial's own words
    var read = [fit.cue(Lib.Cues.START, "NEXT"), fit.cue(Lib.Cues.BACK, "EXIT")] as Array<Array<Number> >;
    var titles = ["Never into pain", "Ask first", "Learn the buzzes", "That's all of them"] as Array<String>;
    for (var i = 0; i < titles.size(); i++) {
        fit.line("page title", titles[i], name, 0.355, read);
    }
    fit.line("page", "STRETCH SAFELY", band, 0.14, read);
    fit.line("page", "BEFORE YOU START", band, 0.14, read);
    var pageLines = [["Mild tension only. Stop", 0.475], ["for sharp pain, dizziness,", 0.55], ["numbness or tingling", 0.625],
                     ["Injured, pregnant or", 0.475], ["after surgery? Check", 0.55], ["with a clinician", 0.625],
                     ["Each buzz means", 0.475], ["one thing, so you can", 0.55], ["stretch without looking", 0.625],
                     ["Feel them again", 0.49], ["any time under MORE", 0.565]] as Array<Array>;
    for (var i = 0; i < pageLines.size(); i++) {
        fit.line("page", pageLines[i][0] as String, reg, pageLines[i][1] as Float, read);
    }

    // the figures against the words round them
    var bw = (w * 0.48).toNumber();
    var bh = (h * 0.27).toNumber();
    var ground = (h * 0.525).toNumber();
    var cx = w / 2;
    var hits = 0;
    for (var i = 0; i < StretchData.COUNT; i++) {
        var m = StretchData.META;
        var b = i * StretchFigure.META;
        var x0 = (m[b + 6] - 128) / 100.0;
        var x1 = (m[b + 7] - 128) / 100.0;
        var top = m[b + 8] / 100.0;
        var lift = m[b + 9] / 100.0;
        var sc = bw / (x1 - x0);
        if (bh / top < sc) {
            sc = bh / top;
        }
        var mid = (x0 + x1) / 2.0;
        var sided = (m[b + 1] & StretchFigure.F_SIDED) != 0;
        var pad = (0.06 * sc).toNumber();
        var hitPause = false;
        var hitSub = false;
        for (var side = 0; side < (sided ? 2 : 1); side++) {
            var dir = side == 1 ? -sc : sc;
            for (var t = 0; t <= 8; t++) {
                var pts = StretchFigure.placed(i, t / 8.0);
                for (var k = 0; k < StretchFigure.JOINTS; k++) {
                    var px = (cx + (pts[2 * k] - mid) * dir).toNumber();
                    var py = (ground - (pts[2 * k + 1] - lift) * sc).toNumber();
                    if (px + pad > pause[0] && (py - pause[2]).abs() < fit.ink + pad) {
                        hitPause = true;
                    }
                    // the side line, sided or a round, is at most this wide
                    if (sided && px.abs() >= 0 && (px - cx).abs() < w / 5 && py - pad < (h * 0.205).toNumber() + fit.ink) {
                        hitSub = true;
                    }
                }
            }
        }
        if (hitPause) {
            hits++;
            System.println("FIGURE HITS PAUSE " + StretchData.NAMES[i]);
        }
        if (hitSub) {
            hits++;
            System.println("FIGURE HITS SIDE LINE " + StretchData.NAMES[i]);
        }
    }
    Test.assertEqualMessage(fit.problems, 0, "every word fits, clear of the button words");
    System.println("FIT " + w + ": " + fit.problems + " word problems, " + hits + " figure problems, " + count + " coach lines");
    return true;
}
