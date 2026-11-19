import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Run No Evil tests for Sign: scripts/test.sh sign [device]. Lib.Neon is
// tested here.

(:test)
module SignTesting {
    function screen() as Dc {
        var settings = System.getDeviceSettings();
        return (Graphics.createBufferedBitmap({:width => settings.screenWidth, :height => settings.screenHeight}).get()
                as Graphics.BufferedBitmap).getDc();
    }

    // A strike's brightness as designs/preview_sign.py --strike-values prints it: "core/halo"
    function lit(t as Number, seed as Number) as String {
        var level = Lib.Strike.lit(t, seed);
        return level[0] + "/" + level[1];
    }

    function dying(t as Number) as String {
        var level = Lib.Strike.dying(t);
        return level[0] + "/" + level[1];
    }

    function joined(a as Array<Number>) as String {
        var s = "";
        for (var i = 0; i < a.size(); i++) {
            s += ((i > 0) ? " " : "") + a[i];
        }
        return s;
    }
}

// Every numeral in both rows, both clocks, every weekday, lit and in standby
(:test)
function testSignDrawsEveryMode(logger as Logger) as Boolean {
    var dc = SignTesting.screen();
    var view = new SignView();
    view.onLayout(dc);
    view.setFrame(50);

    // Whatever the simulator provides
    var started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake, the first frame: " + (System.getTimer() - started) + " ms");
    started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake, the next: " + (System.getTimer() - started) + " ms");

    var moments = [[0, 0, 1, 1], [1, 11, 2, 9], [12, 34, 3, 15], [20, 56, 4, 28], [23, 59, 5, 31],
                   [7, 8, 6, 20], [19, 47, 7, 13]] as Array<Array<Number>>;
    for (var i = 0; i < moments.size(); i++) {
        for (var clock = 0; clock < 2; clock++) {
            view.setMoment(moments[i], clock == 0);
            view.setAwake(true);
            view.onUpdate(dc);
            view.setAwake(false);
            started = System.getTimer();
            view.onUpdate(dc);
            if (i == 0 && clock == 0) {
                logger.debug("standby: " + (System.getTimer() - started) + " ms");
            }
        }
    }
    view.setAwake(true);
    view.onUpdate(dc);
    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}

// Every look draws, lit with its name for a moment and in standby; then
// every set and every tube of the chart in each of the three places
(:test)
function testSignLooksAndSets(logger as Logger) as Boolean {
    var dc = SignTesting.screen();
    var view = new SignView();
    view.onLayout(dc);
    view.setFrame(50);
    view.setMoment([10, 37, 3, 15] as Array<Number>, true);
    Application.Storage.setValue(Lib.Look.KEY, Lib.Look.LOW);
    for (var m = 0; m < Lib.Look.MODES; m++) {
        Test.assertEqualMessage(Lib.Look.next(), Lib.Look.ORDER[(Lib.Look.ORDER.indexOf(Lib.Look.LOW) + m + 1) % Lib.Look.MODES], "the next look");
        view.reloadSettings();
        view.onUpdate(dc);          // its name where the date is
        view.setAwake(false);
        view.onUpdate(dc);
        view.setAwake(true);
    }
    Application.Storage.deleteValue(Lib.Look.KEY);
    Lib.Look.changedAt = null;
    for (var s = 0; s < Lib.Neon.SETS.size(); s++) {
        var t = Lib.Neon.tubes(Lib.Look.DAILY, Lib.Neon.FIRST, s);
        view.setColors([Lib.Neon.TUBES[t[0]], Lib.Neon.TUBES[t[1]], Lib.Neon.TUBES[t[2]]] as Array<Number>);
        view.onUpdate(dc);
        view.setAwake(false);
        view.onUpdate(dc);
        view.setAwake(true);
    }
    var n = Lib.Neon.TUBES.size();
    for (var i = 0; i < n; i++) {
        view.setColors([Lib.Neon.TUBES[i], Lib.Neon.TUBES[(i + 5) % n], Lib.Neon.TUBES[(i + 11) % n]] as Array<Number>);
        view.onUpdate(dc);
    }
    return true;
}

// A wake after the time moved on: the changed numerals are struck, frame by
// frame, and settle; the minute turning while awake: the old one dies first;
// nothing moves in standby, and a look's name or sleep ends a strike
(:test)
function testSignStrike(logger as Logger) as Boolean {
    var dc = SignTesting.screen();
    var view = new SignView();
    view.onLayout(dc);
    view.setFrame(50);
    view.setMoment([10, 29, 3, 15] as Array<Number>, true);
    view.setAwake(true);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.striking(), 0, "nothing is struck on the first sight of the face");
    view.setAwake(false);
    view.onUpdate(dc);
    view.setMoment([10, 37, 3, 15] as Array<Number>, true);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.striking(), 0, "standby never animates");
    view.setAwake(true);
    var started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("the frame a strike begins on: " + (System.getTimer() - started) + " ms");
    Test.assertEqualMessage(view.striking(), 2, "10:29 to 10:37: the two minutes' numerals");
    var frames = 0;
    var most = 0;
    while (view.striking() > 0 && frames < 60) {
        started = System.getTimer();
        view.onUpdate(dc);
        var took = System.getTimer() - started;
        most = (took > most) ? took : most;
        frames++;
    }
    logger.debug("two numerals: " + frames + " frames of 50 ms, " + most + " ms the slowest");
    Test.assertMessage(frames >= Lib.Strike.LONGEST / 50 - 3 && frames <= Lib.Strike.LONGEST / 50 + 1, "settled in under a second: " + frames + " frames");

    // the minute turns while awake: one dies, one is struck
    view.setMoment([10, 38, 3, 15] as Array<Number>, true);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.striking(), 2, "the old 7 dying and the new 8");
    frames = 0;
    while (view.striking() > 0 && frames < 60) {
        view.onUpdate(dc);
        frames++;
    }
    Test.assertMessage(frames <= (Lib.Strike.DEATH + Lib.Strike.LONGEST) / 50 + 1, "a death and a strike: " + frames + " frames");

    // an hour and a day on, on a 12-hour clock: 9 to 10 moves the row, and the date
    view.setMoment([9, 59, 3, 15] as Array<Number>, false);
    view.onUpdate(dc);
    while (view.striking() > 0) {
        view.onUpdate(dc);
    }
    view.setAwake(false);
    view.onUpdate(dc);
    view.setMoment([10, 0, 4, 16] as Array<Number>, false);
    view.setAwake(true);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.striking(), 4 + 5, "every numeral and the date's five letters");
    frames = 0;
    most = 0;
    while (view.striking() > 0 && frames < 60) {
        started = System.getTimer();
        view.onUpdate(dc);
        var took = System.getTimer() - started;
        most = (took > most) ? took : most;
        frames++;
    }
    logger.debug("four numerals and the date: " + frames + " frames, " + most + " ms the slowest");

    // midnight while awake, the worst frame: four die, four are struck, the date both
    view.setMoment([23, 59, 4, 16] as Array<Number>, true);
    view.onUpdate(dc);
    while (view.striking() > 0) {
        view.onUpdate(dc);
    }
    view.setMoment([0, 0, 5, 17] as Array<Number>, true);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.striking(), 8 + 5 + 5, "everything dies and is struck");
    most = 0;
    for (var i = 0; i < 4; i++) {
        started = System.getTimer();
        view.onUpdate(dc);
        var took = System.getTimer() - started;
        most = (took > most) ? took : most;
    }
    logger.debug("midnight awake, 18 tubes: " + most + " ms the slowest frame");
    view.setAwake(false);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.striking(), 0, "sleep ends a strike");
    view.setAwake(true);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.striking(), 0, "and nothing changed while it slept");
    return true;
}

// Which numerals changed
(:test)
function testSignChanged(logger as Logger) as Boolean {
    Test.assertEqualMessage(SignTesting.joined(SignText.changed("29", "37")), "0 1", "both");
    Test.assertEqualMessage(SignTesting.joined(SignText.changed("37", "38")), "1", "the ones");
    Test.assertEqualMessage(SignTesting.joined(SignText.changed("39", "40")), "0 1", "the tens turn too");
    Test.assertEqualMessage(SignTesting.joined(SignText.changed("10", "10")), "", "nothing");
    Test.assertEqualMessage(SignTesting.joined(SignText.changed("9", "10")), "0 1", "a numeral more: the row moves");
    Test.assertEqualMessage(SignTesting.joined(SignText.changed("12", "1")), "0", "a numeral fewer");
    Test.assertEqualMessage(SignTesting.joined(SignText.changed("1", "2")), "0", "one numeral");
    return true;
}

// Lib.Strike: the tables' values, as designs/preview_sign.py --strike-values
// prints them from its copy
(:test)
function testStrikeLevels(logger as Logger) as Boolean {
    var times = [0, 40, 100, 150, 250, 333, 420, 600, 777, 900, 965] as Array<Number>;
    var expected = [
        "55/18 55/18 27/10 12/5 70/28 12/5 60/27 86/60 96/88 100/100 100/100",
        "0/0 45/14 45/14 12/5 75/30 75/30 12/5 83/53 95/85 100/100 100/100",
        "0/0 0/0 60/20 60/20 12/5 50/18 62/27 82/50 94/79 99/98 100/100",
        "0/0 0/0 0/0 55/18 12/5 70/28 12/5 76/41 92/73 97/90 100/100",
        "45/14 45/14 12/5 12/5 75/30 63/25 58/25 86/60 97/89 100/100 100/100"
    ] as Array<String>;
    for (var seed = 0; seed < expected.size(); seed++) {
        var row = "";
        for (var i = 0; i < times.size(); i++) {
            row += ((i > 0) ? " " : "") + SignTesting.lit(times[i], seed);
        }
        Test.assertEqualMessage(row, expected[seed], "seed " + seed);
    }
    times = [0, 25, 60, 100, 130, 160, 240, 279, 280] as Array<Number>;
    var row = "";
    for (var i = 0; i < times.size(); i++) {
        row += ((i > 0) ? " " : "") + SignTesting.dying(times[i]);
    }
    Test.assertEqualMessage(row, "100/100 93/80 53/34 20/8 40/19 54/26 20/8 1/1 0/0", "a death");
    return true;
}

// Lib.Strike: what any face may rely on
(:test)
function testStrikeShape(logger as Logger) as Boolean {
    Test.assertEqualMessage(SignTesting.lit(-5, 0), "0/0", "dark before the strike");
    Test.assertEqualMessage(SignTesting.dying(-5), "100/100", "full before the death");
    Test.assertEqualMessage(SignTesting.dying(5000), "0/0", "and out after it");
    Test.assertMessage(Lib.Strike.dead(Lib.Strike.DEATH) && !Lib.Strike.dead(Lib.Strike.DEATH - 1), "dead at DEATH");
    Test.assertMessage(Lib.Strike.LONGEST < 1000, "under a second");
    var waits = "";
    for (var seed = 0; seed < 12; seed++) {
        waits += Lib.Strike.wait(seed) + " ";
        var settledAt = -1;
        var stutters = 0;
        var up = false;
        for (var t = 0; t <= Lib.Strike.LONGEST; t += 5) {
            var level = Lib.Strike.lit(t, seed);
            Test.assertMessage(level[0] >= 0 && level[0] <= 100 && level[1] >= 0 && level[1] <= 100, "a percent");
            Test.assertMessage(level[1] <= level[0], "the halo never leads the core");
            if (t - Lib.Strike.wait(seed) < 360) {
                Test.assertMessage(level[0] <= 75 && level[1] <= 30, "a stutter is not a flash");
            }
            var on = level[0] > 2 * Lib.Strike.EMBER_CORE;
            if (on && !up) {
                stutters++;
            }
            up = on;
            if (settledAt < 0 && Lib.Strike.settled(t, seed)) {
                settledAt = t;
                Test.assertEqualMessage(level[0] + level[1], 200, "settled means full");
            }
        }
        Test.assertMessage(stutters >= 2 && stutters <= 3, "one or two stutters, then it catches: " + stutters);
        Test.assertMessage(settledAt > 700 && settledAt <= Lib.Strike.LONGEST, "every strike settles by LONGEST: " + settledAt);
        Test.assertMessage(Lib.Strike.settled(5000, seed) && !Lib.Strike.settled(0, seed), "settled");
        Test.assertEqualMessage(SignTesting.lit(5000, seed), "100/100", "and stays full");
    }
    Test.assertEqualMessage(waits, "0 35 70 105 0 35 70 105 0 35 70 105 ", "the tubes' waits");
    Test.assertMessage(!SignTesting.lit(150, 0).equals(SignTesting.lit(150, 1)) || !SignTesting.lit(250, 0).equals(SignTesting.lit(250, 1)),
                       "two tubes are not in step");
    // every corner's time is in order, and no stutter is shorter than a frame on the watch
    for (var p = 0; p < Lib.Strike.PATTERNS.size(); p++) {
        var table = Lib.Strike.PATTERNS[p];
        Test.assertEqualMessage(table.size() % 3, 0, "corners of three");
        for (var i = 3; i < table.size(); i += 3) {
            Test.assertMessage(table[i] > table[i - 3], "time runs on");
            if (table[i + 1] == table[i - 2] && table[i] <= 360) {
                Test.assertMessage(table[i] - table[i - 3] + Lib.Strike.RAMP >= 70, "a stutter outlasts a frame");
            }
        }
        Test.assertEqualMessage(table[table.size() - 2] + table[table.size() - 1], 200, "ends at full");
    }
    return true;
}

(:test)
function testSignText(logger as Logger) as Boolean {
    Test.assertEqual(SignText.hours(0, true), "00");
    Test.assertEqual(SignText.hours(9, true), "09");
    Test.assertEqual(SignText.hours(20, true), "20");
    Test.assertEqualMessage(SignText.hours(0, false), "12", "midnight on a 12-hour clock");
    Test.assertEqualMessage(SignText.hours(13, false), "1", "one numeral, no zero before it");
    Test.assertEqual(SignText.hours(12, false), "12");
    Test.assertEqual(SignText.minutes(5), "05");
    Test.assertEqualMessage(SignText.date(3, 15), "TUE 15", "Gregorian's third day is Tuesday");
    Test.assertEqual(SignText.date(1, 1), "SUN 1");
    Test.assertEqual(SignText.date(7, 31), "SAT 31");
    Test.assertEqualMessage(SignText.lines("DOWNTOWN").size(), 1, "one word, one line");
    var two = SignText.lines("HI-VIS GREEN");
    Test.assertEqualMessage(two[0] + "/" + two[1], "HI-VIS/GREEN", "two words, two lines");
    two = SignText.lines("LAST CALL");
    Test.assertEqual(two[0] + "/" + two[1], "LAST/CALL");
    return true;
}

// A tube is bent for every character a date or a look's name can hold
(:test)
function testSignLettering(logger as Logger) as Boolean {
    var titles = [] as Array<String>;
    titles.addAll(Lib.Neon.NAMES);
    titles.addAll(SignText.DAYS);
    Application.Storage.setValue(Lib.Look.KEY, Lib.Look.YOURS);
    for (var m = 0; m < Lib.Look.MODES; m++) {
        titles.add(Lib.Neon.title(Lib.Look.next()));
    }
    Application.Storage.deleteValue(Lib.Look.KEY);
    Lib.Look.changedAt = null;
    for (var i = 0; i < titles.size(); i++) {
        var chars = titles[i].toCharArray();
        for (var j = 0; j < chars.size(); j++) {
            var c = chars[j].toString();
            Test.assertMessage(c.equals(" ") || Layout.LETTERS.find(c) != null, "no tube for '" + c + "' in " + titles[i]);
        }
    }
    Test.assertEqualMessage(Layout.smallHalos().size(), Layout.LETTERS.length(), "a halo per letter");
    Test.assertEqualMessage(Layout.smallCores().size(), Layout.LETTERS.length(), "and a core");
    Test.assertEqualMessage(Layout.halos().size() + Layout.cores().size(), 20, "a halo and a core per numeral");
    for (var r = 0; r < Layout.WIDTHS.size(); r++) {
        Test.assertEqualMessage(Layout.row(Layout.WIDTHS[r]), r, "each width has its row");
        Test.assertEqualMessage(Layout.SIZES[r].size(), Layout.AOD_STEP + 1, "every size");
        Test.assertEqual(Layout.ADVANCE[r].size(), 10);
        Test.assertEqual(Layout.SMALL_ADVANCE[r].size(), Layout.LETTERS.length());
    }
    Test.assertEqualMessage(Layout.row(System.getDeviceSettings().screenWidth), Layout.WIDTHS.indexOf(System.getDeviceSettings().screenWidth),
                            "this screen has its own row");
    Test.assertEqualMessage(Layout.row(300), 0, "a narrower screen takes the smallest");
    return true;
}

// Lib.Neon: the looks' tubes
(:test)
function testNeonTubes(logger as Logger) as Boolean {
    var yours = [3, 10, 13] as Array<Number>;
    Test.assertEqualMessage(SignTesting.joined(Lib.Neon.tubes(Lib.Look.YOURS, yours, 0)), "3 10 13", "the owner's own");
    Test.assertEqualMessage(SignTesting.joined(Lib.Neon.tubes(Lib.Look.BRIGHT, yours, 0)), "15 4 15", "a white sign with neon red");
    Test.assertEqualMessage(SignTesting.joined(Lib.Neon.tubes(Lib.Look.BRIGHT_BLUE, yours, 0)), "15 11 15", "with horizon blue");
    Test.assertEqualMessage(SignTesting.joined(Lib.Neon.tubes(Lib.Look.BRIGHT_GREEN, yours, 0)), "15 12 15", "with green");
    Test.assertEqualMessage(SignTesting.joined(Lib.Neon.tubes(Lib.Look.LOW, yours, 0)), "14 2 2", "the warm end of the chart");
    Test.assertEqualMessage(Lib.Neon.SETS.size(), Lib.Neon.NAMES.size(), "a name per set");
    for (var day = 0; day < 2 * Lib.Neon.SETS.size(); day++) {
        var t = Lib.Neon.tubes(Lib.Look.DAILY, yours, day);
        Test.assertEqualMessage(SignTesting.joined(t), SignTesting.joined(Lib.Neon.SETS[day % Lib.Neon.SETS.size()]), "the day's set");
        for (var i = 0; i < 3; i++) {
            Test.assertMessage(t[i] >= 0 && t[i] < Lib.Neon.TUBES.size(), "a tube of the chart");
        }
        Test.assertMessage(t[0] != t[1], "the hours and the minutes in different tubes");
    }
    Test.assertEqualMessage(SignTesting.joined(Lib.Neon.tubes(Lib.Look.DAILY, yours, 0)), "0 1 2", "Downtown: rose, turquoise, amber");
    Test.assertEqualMessage(Lib.Neon.TUBES.size(), 16, "sixteen tubes");
    Test.assertEqualMessage(Lib.Neon.TUBES[Lib.Neon.ROSE], 0xE83E6C, "rose");
    Test.assertEqualMessage(Lib.Neon.TUBES[Lib.Neon.SNOW], 0xDCE8F4, "snow white");
    Test.assertEqualMessage(Lib.Neon.colors(Lib.Look.LOW)[1], Lib.Neon.TUBES[Lib.Neon.AMBER], "the look's colours");
    Test.assertEqualMessage(Lib.Neon.title(Lib.Look.BRIGHT), "HI-VIS RED", "a clear red tube, not orange");
    Test.assertEqual(Lib.Neon.title(Lib.Look.LOW), "LOW LIGHT");
    Test.assertEqual(Lib.Neon.title(Lib.Look.YOURS), "YOUR LOOK");
    return true;
}

// Lib.Neon: a tube's core, its standby colour, and the wash under both
(:test)
function testNeonColors(logger as Logger) as Boolean {
    Test.assertEqualMessage(Lib.Neon.wash(0x000000, 0, 100), 0x000000, "nothing done");
    Test.assertEqualMessage(Lib.Neon.wash(0x204060, 0, 100), 0x204060, "nothing done to a colour");
    Test.assertEqualMessage(Lib.Neon.wash(0x000000, 100, 100), 0xFFFFFF, "all the way to white");
    Test.assertEqualMessage(Lib.Neon.wash(0xFFFFFF, 0, 50), 0x7F7F7F, "half the level");
    Test.assertEqualMessage(Lib.Neon.wash(0x000000, 50, 100), 0x7F7F7F, "halfway to white");
    // rose E83E6C: 45 % of the way to white, as designs/colors.py's core()
    Test.assertEqualMessage(Lib.Neon.core(0xE83E6C), 0xF294AE, "rose's core");
    Test.assertEqualMessage(Lib.Neon.core(0xFFFFFF), 0xFFFFFF, "white stays white");
    // and 25 % of the way at 62 %, as standby()
    Test.assertEqualMessage(Lib.Neon.standby(0xE83E6C), 0x924459, "rose in standby");
    for (var i = 0; i < Lib.Neon.TUBES.size(); i++) {
        var c = Lib.Neon.TUBES[i];
        var core = Lib.Neon.core(c);
        var dim = Lib.Neon.standby(c);
        for (var shift = 0; shift <= 16; shift += 8) {
            Test.assertMessage(((core >> shift) & 0xFF) >= ((c >> shift) & 0xFF), "a core is paler than its tube");
            Test.assertMessage(((dim >> shift) & 0xFF) <= ((core >> shift) & 0xFF), "standby is dimmer than the core");
        }
        Test.assertMessage(dim != 0, "a standby tube is lit");
    }
    return true;
}
