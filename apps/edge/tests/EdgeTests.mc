import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Run No Evil tests for Edge: scripts/test.sh edge [device]. Lib.Neon is
// tested here (Sign and Noir use it too).

(:test)
module EdgeTesting {
    function dc() as Dc {
        var settings = System.getDeviceSettings();
        // 16 bits a pixel, as the screen: the graphics pool is 3 MB on the fenix 8 and a strike needs room in it
        return (Graphics.createBufferedBitmap({:width => settings.screenWidth, :height => settings.screenHeight, :colorDepth => 16}).get()
                as Graphics.BufferedBitmap).getDc();
    }
}

// Every digit in both rows, one and two digit hours, awake and in standby
(:test)
function testEdgeDrawsEveryMode(logger as Logger) as Boolean {
    var dc = EdgeTesting.dc();
    var view = new EdgeView();
    view.onLayout(dc);

    // Whatever the simulator provides
    var started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake, the bitmap made and drawn: " + (System.getTimer() - started) + " ms");
    started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake, the blit alone: " + (System.getTimer() - started) + " ms");

    var times = [["10", "37"], ["00", "00"], ["11", "11"], ["23", "59"], ["9", "41"], ["1", "08"], ["12", "34"],
                 ["20", "56"], ["4", "27"]] as Array<Array<String>>;
    for (var i = 0; i < times.size(); i++) {
        view.setTime(times[i][0], times[i][1], "WED 30");
        view.onUpdate(dc);
        view.setAwake(false);
        started = System.getTimer();
        view.onUpdate(dc);
        if (i == 0) {
            logger.debug("standby: " + (System.getTimer() - started) + " ms");
        }
        view.setAwake(true);
    }
    // and across a strike: asleep at one time, awake at each of the others,
    // every frame drawn until the tubes settle
    view.setFrame(50);
    for (var i = 0; i < times.size(); i++) {
        view.setAwake(false);
        view.onUpdate(dc);
        view.setTime(times[i][0], times[i][1], (i % 2 == 0) ? "WED 30" : "THU 31");
        view.setAwake(true);
        view.onUpdate(dc);
        Test.assertMessage(view.striking() > 0, "something changed, so something is struck");
        var frames = 0;
        while (view.striking() > 0 && frames < 60) {
            view.onUpdate(dc);
            frames++;
        }
        Test.assertMessage(frames <= Lib.Strike.LONGEST / 50 + 1, "a strike settles: " + frames + " frames");
    }
    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}

// A wake after the time moved on: the changed numerals are struck, frame by
// frame, and settle; the minute turning while awake: the old one dies first;
// nothing moves in standby, and a look or sleep ends a strike
(:test)
function testEdgeStrike(logger as Logger) as Boolean {
    var dc = EdgeTesting.dc();
    var view = new EdgeView();
    view.onLayout(dc);
    view.setFrame(50);
    view.setTime("10", "29", "TUE 15");
    view.setAwake(true);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.striking(), 0, "nothing is struck on the first sight of the face");
    view.setAwake(false);
    view.onUpdate(dc);
    view.setTime("10", "37", "TUE 15");
    view.onUpdate(dc);
    Test.assertEqualMessage(view.striking(), 0, "standby never animates");
    view.setAwake(true);
    var started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("the frame a strike of two numerals begins on: " + (System.getTimer() - started) + " ms");
    Test.assertEqualMessage(view.striking(), 2, "10:29 to 10:37: the two minutes' numerals");
    var frames = 0;
    var most = 0;
    var sum = 0;
    while (view.striking() > 0 && frames < 60) {
        started = System.getTimer();
        view.onUpdate(dc);
        var took = System.getTimer() - started;
        most = (took > most) ? took : most;
        sum += took;
        frames++;
    }
    logger.debug("two numerals: " + frames + " frames of 50 ms, " + (sum / frames) + " ms a frame, " + most
                 + " ms the slowest (the last, which draws the bitmap whole again)");
    Test.assertMessage(frames >= Lib.Strike.LONGEST / 50 - 3 && frames <= Lib.Strike.LONGEST / 50 + 1, "settled in under a second: " + frames + " frames");

    // the minute turns while awake: one dies, one is struck
    view.setTime("10", "38", "TUE 15");
    view.onUpdate(dc);
    Test.assertEqualMessage(view.striking(), 2, "the old 7 dying and the new 8");
    frames = 0;
    while (view.striking() > 0 && frames < 60) {
        view.onUpdate(dc);
        frames++;
    }
    Test.assertMessage(frames <= (Lib.Strike.DEATH + Lib.Strike.LONGEST) / 50 + 1, "a death and a strike: " + frames + " frames");

    // an hour and a day on, on a 12-hour clock: 9 to 10 moves the row, and the date
    view.setTime("9", "59", "TUE 15");
    view.onUpdate(dc);
    while (view.striking() > 0) {
        view.onUpdate(dc);
    }
    view.setAwake(false);
    view.onUpdate(dc);
    view.setTime("10", "00", "WED 16");
    view.setAwake(true);
    started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("the frame a strike of four numerals and the date begins on: " + (System.getTimer() - started) + " ms");
    Test.assertEqualMessage(view.striking(), 4 + 1, "every numeral, and the date as one tube");
    frames = 0;
    most = 0;
    sum = 0;
    while (view.striking() > 1 && frames < 60) {
        started = System.getTimer();
        view.onUpdate(dc);
        var took = System.getTimer() - started;
        if (view.striking() > 0) {
            most = (took > most) ? took : most;
            sum += took;
            frames++;
        }
    }
    logger.debug("four numerals and the date: " + frames + " frames, " + (sum / (frames > 0 ? frames : 1)) + " ms a frame, " + most + " ms the slowest");
    while (view.striking() > 0) {
        view.onUpdate(dc);
    }

    // midnight while awake, the worst frame: four die, four are struck, the date both
    view.setTime("23", "59", "WED 16");
    view.onUpdate(dc);
    while (view.striking() > 0) {
        view.onUpdate(dc);
    }
    view.setTime("00", "00", "THU 17");
    started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("midnight awake, the frame it begins on: " + (System.getTimer() - started) + " ms");
    // (ten tubes, or five where the graphics pool has no room for the dying ones' pictures too)
    Test.assertMessage(view.striking() == 8 + 2 || view.striking() == 4 + 1, "everything dies and is struck: " + view.striking());
    most = 0;
    for (var i = 0; i < 4; i++) {
        started = System.getTimer();
        view.onUpdate(dc);
        var took = System.getTimer() - started;
        most = (took > most) ? took : most;
    }
    logger.debug("midnight awake, " + view.striking() + " tubes: " + most + " ms the slowest frame");
    view.setAwake(false);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.striking(), 0, "sleep ends a strike");
    view.setAwake(true);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.striking(), 0, "and nothing changed while it slept");

    // a new look ends a strike: its pictures are in the old colours
    view.setAwake(false);
    view.onUpdate(dc);
    view.setTime("00", "07", "THU 17");
    view.setAwake(true);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.striking(), 1, "one numeral");
    view.reloadSettings();
    view.onUpdate(dc);
    Test.assertEqualMessage(view.striking(), 0, "a look ends a strike");
    return true;
}

// What a strike takes for changed: the places whose numeral differs
(:test)
function testEdgeChanged(logger as Logger) as Boolean {
    var view = new EdgeView();
    Test.assertEqualMessage(view.changed("10", "10").toString(), [].toString(), "nothing");
    Test.assertEqualMessage(view.changed("37", "38").toString(), [1].toString(), "the units");
    Test.assertEqualMessage(view.changed("29", "37").toString(), [0, 1].toString(), "both");
    Test.assertEqualMessage(view.changed("19", "10").toString(), [1].toString(), "the tens stay");
    Test.assertEqualMessage(view.changed("9", "10").toString(), [0, 1].toString(), "9 to 10: the row moves, so both");
    Test.assertEqualMessage(view.changed("12", "1").toString(), [0].toString(), "12 to 1: the one numeral");
    Test.assertEqualMessage(view.changed("1", "1").toString(), [].toString(), "one numeral, the same");
    // a numeral's two lights share a seed, neighbours differ: the waits and patterns of places 0 to 3 and the date
    var seen = {} as Dictionary<String, Boolean>;
    for (var seed = 0; seed < 5; seed++) {
        seen[Lib.Strike.wait(seed) + "/" + (seed % Lib.Strike.PATTERNS.size())] = true;
    }
    Test.assertEqualMessage(seen.size(), 5, "no two tubes on the face flicker in step");
    return true;
}

// Every look draws, awake and in standby, the look's name for a moment
(:test)
function testEdgeLooks(logger as Logger) as Boolean {
    var dc = EdgeTesting.dc();
    var view = new EdgeView();
    view.onLayout(dc);
    Application.Storage.setValue(Lib.Look.KEY, Lib.Look.LOW);
    for (var m = 0; m < Lib.Look.MODES; m++) {
        Test.assertEqualMessage(Lib.Look.next(), Lib.Look.ORDER[(Lib.Look.ORDER.indexOf(Lib.Look.LOW) + m + 1) % Lib.Look.MODES], "the next look");
        view.reloadSettings();
        view.onUpdate(dc);      // titled: the hold was just now
        view.setAwake(false);
        view.onUpdate(dc);
        view.setAwake(true);
    }
    Application.Storage.deleteValue(Lib.Look.KEY);
    return true;
}

// Every set of the daily look and every tube of the chart draws
(:test)
function testEdgeSetsAndTubes(logger as Logger) as Boolean {
    var dc = EdgeTesting.dc();
    var view = new EdgeView();
    view.onLayout(dc);
    for (var d = 0; d < Lib.Neon.SETS.size(); d++) {
        view.setTubes(Lib.Neon.tubes(Lib.Look.DAILY, Lib.Neon.FIRST, d));
        view.onUpdate(dc);
        view.setAwake(false);
        view.onUpdate(dc);
        view.setAwake(true);
    }
    var n = Lib.Neon.TUBES.size();
    for (var i = 0; i < n; i++) {
        view.setTubes([i, (i + 5) % n, (i + 10) % n] as Array<Number>);
        view.onUpdate(dc);
    }
    return true;
}

// The date is in the lettering's capitals, and every title has its letters
(:test)
function testEdgeLettering(logger as Logger) as Boolean {
    var view = new EdgeView();
    Test.assertEqual(view.dateText(1, 6), "SUN 6");
    Test.assertEqual(view.dateText(3, 15), "TUE 15");
    Test.assertEqual(view.dateText(7, 31), "SAT 31");
    Test.assertEqualMessage(view.lines("HI-VIS GREEN").toString(), ["HI-VIS", "GREEN"].toString(), "two lines");
    Test.assertEqualMessage(view.lines("DOWNTOWN").toString(), ["DOWNTOWN"].toString(), "one line");
    Test.assertEqual(view.letter('A'), 0);
    Test.assertEqual(view.letter('Z'), 25);
    Test.assertEqual(view.letter('0'), 26);
    Test.assertEqual(view.letter('9'), 35);
    Test.assertEqual(view.letter('-'), 36);
    Test.assertEqual(view.letter(' '), -1);
    var titles = ["YOUR LOOK", "HI-VIS RED", "HI-VIS BLUE", "HI-VIS GREEN", "LOW LIGHT"] as Array<String>;
    titles.addAll(Lib.Neon.NAMES);
    for (var i = 0; i < titles.size(); i++) {
        var chars = titles[i].toCharArray();
        for (var k = 0; k < chars.size(); k++) {
            Test.assertMessage(chars[k] == ' ' || view.letter(chars[k]) >= 0, "no glyph in " + titles[i]);
        }
    }
    Test.assertEqualMessage(Lib.Neon.title(Lib.Look.BRIGHT), "HI-VIS RED", "red, not orange");
    Test.assertEqual(Lib.Neon.title(Lib.Look.YOURS), "YOUR LOOK");
    return true;
}

// The layout's tables: one for every width the fonts are made for
(:test)
function testEdgeLayout(logger as Logger) as Boolean {
    Test.assertEqual(Layout.pick(466), 0);
    Test.assertEqual(Layout.pick(454), 1);
    Test.assertEqual(Layout.pick(416), 2);
    Test.assertEqual(Layout.pick(390), 3);
    Test.assertEqual(Layout.pick(360), 4);
    Test.assertEqualMessage(Layout.pick(300), 4, "the narrowest for anything smaller");
    for (var i = 0; i < Layout.WIDTHS.size(); i++) {
        var w = Layout.WIDTHS[i];
        var t = Layout.table(w);
        Test.assertEqual(Layout.advances(w).size(), 10);
        Test.assertEqual(Layout.letters(w).size(), 37);
        // the rows are centred on the screen, and the widest pair and the standby shift stay on it
        Test.assertMessage((t[Layout.Y0] + t[Layout.Y1] + t[Layout.H] - w).abs() <= 1, "rows centred at " + w);
        Test.assertMessage(t[Layout.CX] - Layout.advances(w)[0] - 2 * t[Layout.SHIFT] > 0, "the widest pair at " + w);
    }
    return true;
}

// Lib.Neon: the look's tubes
(:test)
function testNeonTubes(logger as Logger) as Boolean {
    var yours = [Lib.Neon.RUBY, Lib.Neon.COBALT, Lib.Neon.LEMON] as Array<Number>;
    Test.assertEqualMessage(Lib.Neon.tubes(Lib.Look.YOURS, yours, 3).toString(), yours.toString(), "your tubes");
    Test.assertEqualMessage(Lib.Neon.tubes(Lib.Look.BRIGHT, yours, 0).toString(),
                            [Lib.Neon.SNOW, Lib.Neon.RED, Lib.Neon.SNOW].toString(), "high visibility: a white sign and red");
    Test.assertEqualMessage(Lib.Neon.tubes(Lib.Look.BRIGHT_BLUE, yours, 0).toString(),
                            [Lib.Neon.SNOW, Lib.Neon.HORIZON, Lib.Neon.SNOW].toString(), "and blue");
    Test.assertEqualMessage(Lib.Neon.tubes(Lib.Look.BRIGHT_GREEN, yours, 0).toString(),
                            [Lib.Neon.SNOW, Lib.Neon.GREEN, Lib.Neon.SNOW].toString(), "and green");
    Test.assertEqualMessage(Lib.Neon.tubes(Lib.Look.LOW, yours, 0).toString(),
                            [Lib.Neon.WARM_WHITE, Lib.Neon.AMBER, Lib.Neon.AMBER].toString(), "low light: the warm end");
    Test.assertEqual(Lib.Neon.SETS.size(), Lib.Neon.NAMES.size());
    for (var d = 0; d < Lib.Neon.SETS.size() * 2; d++) {
        var t = Lib.Neon.tubes(Lib.Look.DAILY, yours, d);
        Test.assertEqualMessage(t.toString(), Lib.Neon.SETS[d % Lib.Neon.SETS.size()].toString(), "the day's set");
        Test.assertMessage(t[0] != t[1], "a set's hours and minutes differ");
        for (var i = 0; i < 3; i++) {
            Test.assertMessage(t[i] >= 0 && t[i] < Lib.Neon.TUBES.size(), "a tube of the chart");
        }
    }
    Test.assertEqualMessage(Lib.Neon.FIRST.toString(), Lib.Neon.SETS[0].toString(), "the first set until one is chosen");
    Test.assertEqualMessage(Lib.Neon.colors(Lib.Look.LOW).toString(),
                            [Lib.Neon.TUBES[Lib.Neon.WARM_WHITE], Lib.Neon.TUBES[Lib.Neon.AMBER], Lib.Neon.TUBES[Lib.Neon.AMBER]].toString(),
                            "the look's colours");
    return true;
}

// Lib.Neon: a tube's core and standby colours
(:test)
function testNeonWash(logger as Logger) as Boolean {
    Test.assertEqualMessage(Lib.Neon.wash(0x000000, 0, 100), 0x000000, "nothing");
    Test.assertEqualMessage(Lib.Neon.wash(0x000000, 100, 100), 0xFFFFFF, "all the way to white");
    Test.assertEqualMessage(Lib.Neon.wash(0xFFFFFF, 0, 50), 0x7F7F7F, "half the level");
    Test.assertEqualMessage(Lib.Neon.wash(0xE83E6C, 0, 100), 0xE83E6C, "itself");
    // designs/colors.py: a core is washed 45 % to white; standby 25 %, at 62 %
    Test.assertEqualMessage(Lib.Neon.core(0xE83E6C), 0xF294AE, "rose's core");
    Test.assertEqualMessage(Lib.Neon.core(0x18B0AA), 0x7FD3D0, "turquoise's core");
    Test.assertEqualMessage(Lib.Neon.standby(0xE83E6C), 0x924459, "rose in standby");
    Test.assertEqualMessage(Lib.Neon.standby(0x18B0AA), 0x327876, "turquoise in standby");
    for (var i = 0; i < Lib.Neon.TUBES.size(); i++) {
        var c = Lib.Neon.TUBES[i];
        var core = Lib.Neon.core(c);
        var dim = Lib.Neon.standby(c);
        for (var s = 0; s <= 16; s += 8) {
            Test.assertMessage(((core >> s) & 0xFF) >= ((c >> s) & 0xFF), "a core is never darker than its tube");
            Test.assertMessage(((dim >> s) & 0xFF) > 0x20, "standby keeps every channel alight");
        }
    }
    return true;
}
