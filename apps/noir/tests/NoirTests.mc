import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Run No Evil tests for Noir: scripts/test.sh noir [device]. Lib.Neon is
// tested here too (Sign and Edge have the same tests of it).

(:test)
module NoirTest {
    function screen() as Dc {
        var settings = System.getDeviceSettings();
        return (Graphics.createBufferedBitmap({:width => settings.screenWidth, :height => settings.screenHeight}).get()
                as Graphics.BufferedBitmap).getDc();
    }

    // The times of designs/preview_noir.py's sheet: the hands apart, nested,
    // crossing, and at each of the date's places
    function times() as Array<Array<Number> > {
        return [[10, 37], [12, 0], [1, 5], [2, 50], [3, 15], [4, 22], [6, 0], [6, 30], [7, 37], [9, 15], [9, 47], [23, 58]]
               as Array<Array<Number> >;
    }
}

// Every mode draws: the clock as it is, the first frame that fills the
// bitmap, twelve times awake and in standby, the look's name above and
// below, the widest date, and straight to the screen without the bitmap
(:test)
function testNoirDrawsEveryMode(logger as Logger) as Boolean {
    var dc = NoirTest.screen();
    var view = new NoirView();
    view.onLayout(dc);

    // a start's first frame: the hands and the marks straight to the screen,
    // nothing of standby's or the date's loaded
    var started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake, the first frame (the hands and the marks, straight to the screen): " + (System.getTimer() - started) + " ms");
    Test.assertMessage(!view.bitmapped(), "the first frame makes no bitmap");
    Test.assertEqualMessage(view.loaded().toString(), "[false, false]", "nor loads standby's tubes or the date's sheets");
    started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake, the next (the face into its bitmap, the date's sheets loaded): " + (System.getTimer() - started) + " ms");
    Test.assertMessage(view.bitmapped(), "the bitmap the frame after");
    Test.assertEqualMessage(view.loaded().toString(), "[false, true]", "and the date's sheets");
    started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake, from the bitmap: " + (System.getTimer() - started) + " ms");

    var times = NoirTest.times();
    for (var i = 0; i < times.size(); i++) {
        view.setTime(times[i][0], times[i][1], (i % 2 == 0) ? 15 : 28);
        view.setAwake(true);
        started = System.getTimer();
        view.onUpdate(dc);
        if (i == 1) {
            logger.debug("awake, a new minute with the loops crossing: " + (System.getTimer() - started) + " ms");
        }
        view.setTitled(true);
        view.onUpdate(dc);
        view.setTitled(false);
        view.setAwake(false);
        started = System.getTimer();
        view.onUpdate(dc);
        if (i == 1) {
            logger.debug("standby: " + (System.getTimer() - started) + " ms");
        }
    }

    view.setAwake(true);
    view.dropBitmap();
    started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake, no bitmap: " + (System.getTimer() - started) + " ms");
    view.setTitled(true);
    view.onUpdate(dc);

    Test.assertEqualMessage(view.loaded().toString(), "[true, true]", "standby's tubes loaded at the first standby");
    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}

// Every look draws, awake, in standby and with its name up; then every
// set of the daily look, and every tube of the chart in each place
(:test)
function testNoirLooks(logger as Logger) as Boolean {
    var dc = NoirTest.screen();
    var view = new NoirView();
    view.onLayout(dc);
    view.setTime(10, 37, 15);
    Application.Storage.setValue(Lib.Look.KEY, Lib.Look.LOW);
    for (var m = 0; m < Lib.Look.MODES; m++) {
        Test.assertEqualMessage(Lib.Look.next(), Lib.Look.ORDER[(Lib.Look.ORDER.indexOf(Lib.Look.LOW) + m + 1) % Lib.Look.MODES], "the next look");
        view.reloadSettings();
        view.setAwake(true);
        view.onUpdate(dc);              // its name is up: the hold was a moment ago
        view.setAwake(false);
        view.onUpdate(dc);
    }
    Application.Storage.deleteValue(Lib.Look.KEY);
    view.reloadSettings();
    view.setAwake(true);
    for (var set = 0; set < Lib.Neon.SETS.size(); set++) {
        view.setTubes(Lib.Neon.tubes(Lib.Look.DAILY, Lib.Neon.FIRST, set));
        view.onUpdate(dc);
    }
    for (var t = 0; t < Lib.Neon.TUBES.size(); t++) {
        view.setTubes([t, (t + 5) % Lib.Neon.TUBES.size(), (t + 11) % Lib.Neon.TUBES.size()] as Array<Number>);
        view.setAwake(true);
        view.onUpdate(dc);
        view.setAwake(false);
        view.onUpdate(dc);
    }
    return true;
}

// Every name a look can show is in the lettering
(:test)
function testNoirLettering(logger as Logger) as Boolean {
    var names = ["YOUR LOOK", "LOW LIGHT", "0123456789-"] as Array<String>;
    names.addAll(Lib.Neon.NAMES);
    var modes = [Lib.Look.YOURS, Lib.Look.BRIGHT, Lib.Look.BRIGHT_BLUE, Lib.Look.BRIGHT_GREEN, Lib.Look.LOW, Lib.Look.DAILY] as Array<Number>;
    for (var i = 0; i < modes.size(); i++) {
        names.add(Lib.Neon.title(modes[i]));
    }
    for (var i = 0; i < names.size(); i++) {
        var chars = names[i].toCharArray();
        for (var k = 0; k < chars.size(); k++) {
            var s = chars[k].toString();
            Test.assertMessage(s.equals(" ") || Layout.DIGITS.find(s) != null || Layout.LETTERS.find(s) != null,
                               "'" + s + "' of " + names[i] + " is in the lettering");
        }
    }
    Test.assertEqualMessage(Layout.WIDTHS.size(), Layout.DIGITS.length() + Layout.LETTERS.length(), "a width for every letter");
    return true;
}

// The hands' angles, and the date takes the first place the hands leave
(:test)
function testDialPlaces(logger as Logger) as Boolean {
    var a = Dial.angles(10, 37);
    Test.assertMessage((a[0] - 318.5).abs() < 0.01 && (a[1] - 222.0).abs() < 0.01, "10:37 is 318.5 and 222 degrees");
    a = Dial.angles(22, 37);
    Test.assertMessage((a[0] - 318.5).abs() < 0.01, "22:37 reads as 10:37");
    Test.assertMessage((Dial.apart(350.0, 10.0) - 20.0).abs() < 0.01, "across twelve");
    Test.assertMessage((Dial.apart(90.0, 270.0) - 180.0).abs() < 0.01, "opposite");

    Test.assertEqualMessage(Dial.datePlace(318.5, 222.0), 0, "10:37: at three");
    a = Dial.angles(3, 15);
    Test.assertEqualMessage(Dial.datePlace(a[0], a[1]), 1, "3:15: both hands at three, the date at nine");
    a = Dial.angles(2, 50);
    Test.assertEqualMessage(Dial.datePlace(a[0], a[1]), 1, "2:50: the hour hand at three");
    a = Dial.angles(9, 15);
    Test.assertEqualMessage(Dial.datePlace(a[0], a[1]), 2, "9:15: a hand at three and one at nine, the date at six");
    a = Dial.angles(6, 10);
    Test.assertEqualMessage(Dial.datePlace(a[0], a[1]), 0, "6:10: six is taken, three is free and comes first");
    a = Dial.angles(4, 10);
    Test.assertEqualMessage(Dial.datePlace(a[0], a[1]), 0, "4:10: the minute hand still 30 degrees short of three");
    a = Dial.angles(4, 11);
    Test.assertEqualMessage(Dial.datePlace(a[0], a[1]), 1, "4:11: within 25 degrees, the date steps aside");
    // no time takes all three places
    for (var t = 0; t < 720; t++) {
        a = Dial.angles(t / 60, t % 60);
        var place = Dial.datePlace(a[0], a[1]);
        var at = [90.0, 270.0, 180.0][place];
        Test.assertMessage(Dial.apart(a[0], at) > Layout.BLOCK && Dial.apart(a[1], at) > Layout.BLOCK,
                           "the date's place is clear at " + (t / 60) + ":" + (t % 60));
    }
    Test.assertMessage(Dial.titleBelow(0.0), "the name below at the hour");
    Test.assertMessage(!Dial.titleBelow(222.0), "and above at 37 minutes");
    return true;
}

// The sweep's arithmetic: the shorter way round, a hand that hasn't moved
// stays where it is, the end is the angle itself, and no sweep is long
(:test)
function testDialSweep(logger as Logger) as Boolean {
    Test.assertMessage((Dial.turn(350.0, 10.0) - 20.0).abs() < 0.001, "across twelve, clockwise");
    Test.assertMessage((Dial.turn(10.0, 350.0) + 20.0).abs() < 0.001, "and back, anticlockwise");
    Test.assertMessage((Dial.turn(90.0, 300.0) + 150.0).abs() < 0.001, "210 degrees on is 150 back");
    Test.assertMessage((Dial.turn(0.0, 180.0) - 180.0).abs() < 0.001, "half a turn goes clockwise");
    Test.assertEqualMessage(Dial.turn(222.0, 222.0), 0.0, "a hand that hasn't moved");
    Test.assertEqualMessage(Dial.turn(0.0, 360.0), 0.0, "nor one that is a whole turn on");

    // every sweep is over in well under a second, and longer the further
    Test.assertEqualMessage(Dial.sweepMs(0.0), Layout.SWEEP, "the shortest sweep");
    Test.assertMessage(Dial.sweepMs(48.0) > Dial.sweepMs(4.0), "eight minutes: the minute hand takes longer than the hour hand");
    Test.assertMessage(Dial.sweepMs(-180.0) + Lib.Motion.PUSH <= 700, "half a turn in 0.7 s at the most");
    Test.assertMessage(Layout.TICK + Lib.Motion.PUSH <= 400, "a minute in a few hundred ms");

    // 10:29 to 10:37: the minute hand from 174 to 222 degrees
    var dur = Dial.sweepMs(Dial.turn(174.0, 222.0));
    Test.assertEqualMessage(Dial.swept(174.0, 222.0, 0, dur), 174.0, "it starts where it stood");
    var last = 174.0;
    var least = 174.0;
    for (var t = 0; t <= dur + Lib.Motion.PUSH + 100; t += 10) {
        var a = Dial.swept(174.0, 222.0, t, dur);
        Test.assertMessage(a > 172.0 && a <= 222.0, "between where it stood (less the push) and where it is");
        if (t > Lib.Motion.PUSH) {
            Test.assertMessage(a >= last, "always on, never back");
        }
        least = (a < least) ? a : least;
        last = a;
    }
    Test.assertMessage(least < 174.0 && least > 172.5, "the push: a little back first, " + least);
    Test.assertEqualMessage(Dial.swept(174.0, 222.0, dur + Lib.Motion.PUSH, dur), 222.0, "the end is the angle itself");
    Test.assertEqualMessage(Dial.swept(174.0, 222.0, 5000, dur), 222.0, "and stays");
    var half = Dial.swept(174.0, 222.0, Lib.Motion.PUSH + dur / 2, dur);
    Test.assertMessage((half - 198.0).abs() < 0.5, "half way at half time: slow out, slow in, " + half);
    Test.assertMessage(Dial.swept(174.0, 222.0, Lib.Motion.PUSH + dur / 4, dur) < 180.0, "slow out");
    Test.assertMessage(Dial.swept(174.0, 222.0, Lib.Motion.PUSH + dur * 3 / 4, dur) > 216.0, "slow in");

    // the shorter way round: 11:58 to 12:02 goes on through twelve
    var a = Dial.swept(348.0, 12.0, Lib.Motion.PUSH + Dial.sweepMs(24.0) / 2, Dial.sweepMs(24.0));
    Test.assertMessage((a - 360.0).abs() < 0.5, "through twelve, not back round the dial: " + a);
    // a hand that hasn't moved stays still at every moment
    for (var t = 0; t < 600; t += 50) {
        Test.assertEqualMessage(Dial.swept(318.5, 318.5, t, 300), 318.5, "still");
    }
    return true;
}

(:test)
module NoirSweep {
    // Draw frames until nothing moves; the number of frames
    function run(view as NoirView, dc as Dc) as Number {
        var frames = 0;
        do {
            view.onUpdate(dc);
            frames++;
        } while (view.moving() && frames < 60);
        return frames;
    }
}

// Every mode draws across a transition: a wake after eight minutes, a
// wake after hours with the day changed and the date moved, the minute
// turning, the date dying at three and struck at nine, a wake with nothing
// changed, and a sleep in the middle of a sweep
(:test)
function testNoirSweeps(logger as Logger) as Boolean {
    var dc = NoirTest.screen();
    var view = new NoirView();
    view.onLayout(dc);
    view.setFrame(50);
    view.setTime(10, 29, 15);
    view.setAwake(true);
    view.onUpdate(dc);
    Test.assertMessage(!view.moving(), "the first sight of the face: nothing to sweep from");

    // asleep at 10:29, awake at 10:37
    view.setAwake(false);
    view.onUpdate(dc);
    view.setTime(10, 37, 15);
    view.setAwake(true);
    view.onUpdate(dc);
    Test.assertMessage(view.moving(), "a wake eight minutes on: the hands sweep");
    var at = view.hands();
    Test.assertMessage(at[1] < 180.0 && at[1] > 172.0, "the minute hand sets off from 10:29, " + at[1]);
    var frames = NoirSweep.run(view, dc);
    logger.debug("a wake after eight minutes: " + view.frameLog());
    Test.assertMessage(frames >= 4 && frames <= 16, "over in well under a second: " + frames + " frames of 50 ms");
    at = view.hands();
    Test.assertMessage(at[0] == 318.5 && at[1] == 222.0, "and the hands are at 10:37 exactly");

    // the minute turns while awake
    view.setTime(10, 38, 15);
    view.onUpdate(dc);
    Test.assertMessage(view.moving(), "the minute turned: the hands ease on");
    frames = NoirSweep.run(view, dc);
    logger.debug("the minute turning: " + view.frameLog());
    Test.assertMessage(frames <= 9, "in a few hundred ms: " + frames + " frames");
    Test.assertEqualMessage(view.hands()[1], 228.0, "to 38 minutes");

    // a wake with nothing changed: nothing moves
    view.setAwake(false);
    view.onUpdate(dc);
    view.setAwake(true);
    view.onUpdate(dc);
    Test.assertMessage(!view.moving(), "a wake in the same minute: still");

    // asleep at 6:15 on the 14th, awake at 10:37 on the 15th: both hands
    // go a long way, the date dies at nine and is struck at three
    view.setTime(6, 15, 14);
    NoirSweep.run(view, dc);
    view.frameLog();
    view.setAwake(false);
    view.onUpdate(dc);
    view.setTime(10, 37, 15);
    view.setAwake(true);
    frames = NoirSweep.run(view, dc);
    logger.debug("a wake after hours, the date struck in a new place: " + view.frameLog());
    Test.assertMessage(frames > 12 && frames <= 28, "the hands in 0.6 s, the date's strike after its death: " + frames + " frames");
    Test.assertEqualMessage(view.hands()[0], 318.5, "the hour hand at 10:37");

    // 4:10 to 4:11 awake: the minute hand comes within 25 degrees of three
    view.setTime(4, 10, 15);
    NoirSweep.run(view, dc);
    view.frameLog();
    view.setTime(4, 11, 15);
    frames = NoirSweep.run(view, dc);
    logger.debug("the date moving from three to nine: " + view.frameLog());
    Test.assertMessage(frames > 12, "the date dies and is struck: " + frames + " frames");

    // a hold in the middle of a strike, the look's name up; then standby
    // in the middle of a sweep: nothing moves in standby, or after it
    view.setTime(4, 30, 15);
    view.onUpdate(dc);
    view.setTitled(true);
    view.onUpdate(dc);
    view.setTitled(false);
    view.onUpdate(dc);
    view.setTime(4, 50, 15);
    view.onUpdate(dc);
    Test.assertMessage(view.moving(), "sweeping");
    view.setAwake(false);
    view.onUpdate(dc);
    Test.assertMessage(!view.moving(), "standby never animates");
    view.onUpdate(dc);
    view.setAwake(true);
    NoirSweep.run(view, dc);
    Test.assertMessage(!view.moving(), "at rest");

    // without the bitmap nothing moves: the face is drawn whole
    view.dropBitmap();
    view.setTime(5, 20, 15);
    view.onUpdate(dc);
    Test.assertMessage(!view.moving(), "no bitmap, no transition");
    return true;
}

// Lib.Neon: every look's tubes
(:test)
function testNeonTubes(logger as Logger) as Boolean {
    var yours = [3, 10, 13] as Array<Number>;
    Test.assertEqualMessage(Lib.Neon.tubes(Lib.Look.YOURS, yours, 0).toString(), "[3, 10, 13]", "your tubes");
    Test.assertEqualMessage(Lib.Neon.tubes(Lib.Look.BRIGHT, yours, 0).toString(), [Lib.Neon.SNOW, Lib.Neon.RED, Lib.Neon.SNOW].toString(), "high visibility: a white sign and red");
    Test.assertEqualMessage(Lib.Neon.tubes(Lib.Look.BRIGHT_BLUE, yours, 0).toString(), [Lib.Neon.SNOW, Lib.Neon.HORIZON, Lib.Neon.SNOW].toString(), "and blue");
    Test.assertEqualMessage(Lib.Neon.tubes(Lib.Look.BRIGHT_GREEN, yours, 0).toString(), [Lib.Neon.SNOW, Lib.Neon.GREEN, Lib.Neon.SNOW].toString(), "and green");
    Test.assertEqualMessage(Lib.Neon.tubes(Lib.Look.LOW, yours, 0).toString(), [Lib.Neon.WARM_WHITE, Lib.Neon.AMBER, Lib.Neon.AMBER].toString(), "low light: the warm end");
    Test.assertEqualMessage(Lib.Neon.SETS.size(), Lib.Neon.NAMES.size(), "a name per set");
    for (var day = 0; day < Lib.Neon.SETS.size(); day++) {
        var set = Lib.Neon.tubes(Lib.Look.DAILY, yours, day);
        Test.assertEqualMessage(set.toString(), Lib.Neon.SETS[day].toString(), "the day's set");
        Test.assertEqualMessage(set.size(), 3, "hours, minutes, details");
        for (var i = 0; i < 3; i++) {
            Test.assertMessage(set[i] >= 0 && set[i] < Lib.Neon.TUBES.size(), "a tube of the chart");
        }
    }
    Test.assertEqualMessage(Lib.Neon.tubes(Lib.Look.DAILY, yours, Lib.Neon.SETS.size() + 2).toString(), Lib.Neon.SETS[2].toString(), "the sets come round again");
    Test.assertEqualMessage(Lib.Neon.SETS[0].toString(), [Lib.Neon.ROSE, Lib.Neon.TURQUOISE, Lib.Neon.AMBER].toString(), "Downtown is the mockup's");
    Test.assertEqualMessage(Lib.Neon.TUBES.size(), 16, "sixteen tubes");
    Test.assertEqualMessage(Lib.Neon.title(Lib.Look.BRIGHT), "HI-VIS RED", "high visibility is red here, not orange");
    Test.assertEqualMessage(Lib.Neon.title(Lib.Look.YOURS), "YOUR LOOK", "your look");
    Test.assertEqualMessage(Lib.Neon.colors(Lib.Look.LOW).toString(), [Lib.Neon.TUBES[Lib.Neon.WARM_WHITE], Lib.Neon.TUBES[Lib.Neon.AMBER], Lib.Neon.TUBES[Lib.Neon.AMBER]].toString(), "the look's colours");
    return true;
}

// Lib.Neon: a tube's core, its standby colour, and the wash under both
(:test)
function testNeonWash(logger as Logger) as Boolean {
    Test.assertEqualMessage(Lib.Neon.wash(0xE83E6C, 0, 100), 0xE83E6C, "no wash, full level: the colour");
    Test.assertEqualMessage(Lib.Neon.wash(0x000000, 100, 100), 0xFFFFFF, "all the way to white");
    Test.assertEqualMessage(Lib.Neon.wash(0xFFFFFF, 0, 50), 0x7F7F7F, "half level");
    Test.assertEqualMessage(Lib.Neon.wash(0x102030, 50, 100), 0x878F97, "half way to white");
    Test.assertEqualMessage(Lib.Neon.core(0xE83E6C), 0xF294AE, "Rose's core, as designs/colors.py core()");
    Test.assertEqualMessage(Lib.Neon.standby(0xE83E6C), 0x924459, "Rose in standby, as designs/colors.py standby()");
    for (var t = 0; t < Lib.Neon.TUBES.size(); t++) {
        var c = Lib.Neon.TUBES[t];
        var core = Lib.Neon.core(c);
        var dim = Lib.Neon.standby(c);
        for (var shift = 0; shift <= 16; shift += 8) {
            var v = (c >> shift) & 0xFF;
            Test.assertMessage(((core >> shift) & 0xFF) >= v, "a core is paler than its tube");
            Test.assertMessage(((dim >> shift) & 0xFF) <= ((core >> shift) & 0xFF), "standby is dimmer than the core");
        }
        Test.assertMessage(dim != 0, "standby still shows");
    }
    return true;
}
