import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Run No Evil tests for Shuttle: scripts/test.sh shuttle [device]

(:test)
module ShuttleTest {

    function dc() as Dc {
        var settings = System.getDeviceSettings();
        return (Graphics.createBufferedBitmap({:width => settings.screenWidth, :height => settings.screenHeight}).get()
                as Graphics.BufferedBitmap).getDc();
    }

    // Date, hours, minutes, sun, countdown, temperature, high, low, heart,
    // steps, body, altitude, wind, battery, time
    function values(date as String, hh as String, mm as String, sun as String, count as String, temp as String, hi as String, lo as String,
                    heart as String, steps as String, body as String, battery as String) as Array<String> {
        return [date, hh, mm, sun, count, temp, hi, lo, heart, steps, body, "", "", battery, hh + ":" + mm] as Array<String>;
    }

    // The sample readings
    function base() as Array<String> {
        return values("10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "72", "6214", "82", "87%");
    }

    // A view showing the sample, settled, its clock at `t`
    function view(d as Dc, t as Number) as ShuttleView {
        var v = new ShuttleView();
        v.onLayout(d);
        v.setRolling(true);
        v.setClock(t);
        v.setValues(base());
        for (var n = 0; n < 10 && (n == 0 || v.isAnimating()); n++) {
            v.onUpdate(d);     // a start builds over a few frames, the time first
        }
        return v;
    }

    // Every reading but those named is still
    function stillBut(v as ShuttleView, moving as Array<Number>) as Boolean {
        var keys = [Lib.Numbers.DATE, Lib.Numbers.SUN_TIME, Lib.Numbers.COUNTDOWN, Lib.Numbers.TEMP, Lib.Numbers.HIGH, Lib.Numbers.LOW,
                    Lib.Numbers.HEART, Lib.Numbers.STEPS, Lib.Numbers.BODY, v.BATTERY, v.TIME] as Array<Number>;
        for (var i = 0; i < keys.size(); i++) {
            if (v.isRolling(keys[i]) != (moving.indexOf(keys[i]) >= 0)) {
                return false;
            }
        }
        return true;
    }

    // Frames from `from` to `to` ms, every `step`
    function run(v as ShuttleView, d as Dc, from as Number, to as Number, step as Number) as Void {
        for (var t = from; t <= to; t += step) {
            v.setClock(t);
            v.onUpdate(d);
        }
    }
}

(:test)
function testShuttleDrawsEveryMode(logger as Logger) as Boolean {
    var dc = ShuttleTest.dc();
    var view = new ShuttleView();
    view.onLayout(dc);

    // Whatever the simulator provides
    var started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake, every row: " + (System.getTimer() - started) + " ms");
    started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake, nothing changed: " + (System.getTimer() - started) + " ms");

    var samples = [
        ShuttleTest.values("1/1", "00", "00", "--:--", "--:--", "--", "--", "--", "--", "--", "--", "--"),      // nothing yet
        ShuttleTest.values("3/5", "07", "05", "07:12", "0:05", "5°", "9", "-2", "58", "0", "7", "5%"),          // short
        ShuttleTest.values("10/31", "21", "05", "07:12", "10:07", "28°", "41", "24", "58", "11382", "47", "87%"),
        ShuttleTest.values("11/11", "11", "11", "17:01", "11:11", "-12°", "-4", "-19", "148", "21114", "100", "100%"),   // widest
        ShuttleTest.values("12/28", "20", "08", "20:08", "20:08", "-88°", "-88", "-88", "188", "88888", "100", "88%")     // most ink
    ] as Array<Array<String>>;
    for (var i = 0; i < samples.size(); i++) {
        view.setValues(samples[i]);
        view.onUpdate(dc);
        view.setAwake(false);
        started = System.getTimer();
        view.onUpdate(dc);
        logger.debug("standby " + i + ": " + (System.getTimer() - started) + " ms");
        view.setAwake(true);
        view.onUpdate(dc);
    }
    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}

// Every look draws, awake and in standby, the look's name for a moment
(:test)
function testShuttleLooks(logger as Logger) as Boolean {
    var dc = ShuttleTest.dc();
    var view = new ShuttleView();
    view.onLayout(dc);
    Application.Storage.setValue(Lib.Look.KEY, Lib.Look.LOW);
    for (var m = 0; m < Lib.Look.MODES; m++) {
        Lib.Look.next();
        view.reloadSettings();
        view.onUpdate(dc);
        view.setAwake(false);
        view.onUpdate(dc);
        view.setAwake(true);
        view.onUpdate(dc);
    }
    Application.Storage.deleteValue(Lib.Look.KEY);
    return true;
}

// A minute passing moves the time and the countdown, one digit each, the
// sun's band before the time's, and nothing else; then it all settles
(:test)
function testShuttleMinute(logger as Logger) as Boolean {
    var dc = ShuttleTest.dc();
    var view = ShuttleTest.view(dc, 1000);
    view.setClock(5000);
    view.setValues(ShuttleTest.values("10/31", "14", "39", "19:22", "4:43", "46°", "52", "38", "72", "6214", "82", "87%"));
    Test.assertMessage(ShuttleTest.stillBut(view, [view.TIME, Lib.Numbers.COUNTDOWN] as Array<Number>), "the time and the countdown only");
    Test.assertEqualMessage(view.movedOf(view.TIME), 1, "one digit of the time");
    Test.assertEqualMessage(view.movedOf(Lib.Numbers.COUNTDOWN), 1, "one of the countdown");
    Test.assertMessage(view.leadOf(Lib.Numbers.COUNTDOWN) < view.leadOf(view.TIME), "the sun's band goes first");
    Test.assertMessage(view.isAnimating(), "frames are wanted");
    ShuttleTest.run(view, dc, 5000, 5800, 50);
    Test.assertMessage(view.isRolling(view.TIME), "still bouncing");
    ShuttleTest.run(view, dc, 5850, 6200, 50);
    Test.assertMessage(!view.isRolling(view.TIME), "and it stops");
    Test.assertMessage(!view.isAnimating(), "no more frames");
    return true;
}

// A new heart rate alone moves one digit and nothing else
(:test)
function testShuttleHeartAlone(logger as Logger) as Boolean {
    var dc = ShuttleTest.dc();
    var view = ShuttleTest.view(dc, 1000);
    view.setClock(2000);
    view.setValues(ShuttleTest.values("10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "74", "6214", "82", "87%"));
    Test.assertMessage(ShuttleTest.stillBut(view, [Lib.Numbers.HEART] as Array<Number>), "the heart rate only");
    Test.assertEqualMessage(view.movedOf(Lib.Numbers.HEART), 1, "one digit");
    ShuttleTest.run(view, dc, 2000, 3400, 70);
    Test.assertMessage(!view.isAnimating(), "it settles");
    return true;
}

// Nothing changed, nothing moves
(:test)
function testShuttleNothing(logger as Logger) as Boolean {
    var dc = ShuttleTest.dc();
    var view = ShuttleTest.view(dc, 1000);
    view.setClock(2000);
    view.setValues(ShuttleTest.base());
    Test.assertMessage(ShuttleTest.stillBut(view, [] as Array<Number>), "nothing moves");
    Test.assertMessage(!view.isAnimating(), "no frames");
    view.onUpdate(dc);
    return true;
}

// Units first: across a band, a reading waits for the changed digits of
// the readings to its right that began with it
(:test)
function testShuttleUnitsFirst(logger as Logger) as Boolean {
    var dc = ShuttleTest.dc();
    var view = ShuttleTest.view(dc, 1000);
    view.setClock(2000);
    view.setValues(ShuttleTest.values("10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "88", "6900", "83", "87%"));
    Test.assertEqualMessage(view.movedOf(Lib.Numbers.STEPS), 3, "three of the steps' digits");
    Test.assertEqualMessage(view.movedOf(Lib.Numbers.HEART), 2, "both of the heart rate's");
    var steps = view.leadOf(Lib.Numbers.STEPS);
    Test.assertEqualMessage(view.leadOf(Lib.Numbers.BODY), steps, "stacked readings go together");
    Test.assertEqualMessage(view.leadOf(Lib.Numbers.HEART) - steps, 60 * 4, "the heart rate after the four digits right of it");
    ShuttleTest.run(view, dc, 2000, 3200, 40);
    Test.assertMessage(view.isRolling(Lib.Numbers.HEART), "the heart rate is still moving");
    ShuttleTest.run(view, dc, 3240, 4000, 40);
    Test.assertMessage(!view.isAnimating(), "it all settles");
    return true;
}

// A new length is redrawn, not moved; the setting turns motion off; asleep
// nothing moves
(:test)
function testShuttleStill(logger as Logger) as Boolean {
    var dc = ShuttleTest.dc();
    var view = ShuttleTest.view(dc, 1000);
    view.setClock(2000);
    view.setValues(ShuttleTest.values("10/31", "14", "38", "19:22", "10:43", "46°", "52", "38", "100", "6214", "82", "87%"));
    Test.assertMessage(!view.isRolling(Lib.Numbers.COUNTDOWN), "a new length");
    Test.assertMessage(!view.isRolling(Lib.Numbers.HEART), "nor the heart rate's");
    view.onUpdate(dc);

    view.setRolling(false);
    view.setValues(ShuttleTest.values("10/31", "14", "39", "19:22", "10:43", "46°", "52", "38", "100", "6214", "82", "86%"));
    Test.assertMessage(ShuttleTest.stillBut(view, [] as Array<Number>), "the setting");
    view.onUpdate(dc);

    view.setRolling(true);
    view.setAwake(false);
    view.setValues(ShuttleTest.values("10/31", "14", "59", "19:22", "4:23", "47°", "52", "38", "72", "6900", "81", "85%"));
    Test.assertMessage(!view.isAnimating(), "asleep");
    view.onUpdate(dc);
    return true;
}

// On a wake what changed while asleep moves from what was last seen; what
// changed and changed back, or changed length, doesn't
(:test)
function testShuttleWake(logger as Logger) as Boolean {
    var dc = ShuttleTest.dc();
    var view = ShuttleTest.view(dc, 1000);
    view.setAwake(false);
    view.onUpdate(dc);
    view.setClock(60000);
    view.setValues(ShuttleTest.values("10/31", "14", "45", "19:22", "4:37", "46°", "55", "38", "72", "6900", "81", "85%"));
    view.onUpdate(dc);
    view.setClock(90000);
    view.setValues(ShuttleTest.values("10/31", "14", "59", "19:22", "4:23", "47°", "52", "38", "72", "16900", "81", "85%"));
    view.onUpdate(dc);
    Test.assertMessage(!view.isAnimating(), "nothing moves asleep");
    view.setAwake(true);
    view.onUpdate(dc);
    Test.assertMessage(ShuttleTest.stillBut(view, [view.TIME, Lib.Numbers.COUNTDOWN, Lib.Numbers.TEMP, Lib.Numbers.BODY, view.BATTERY] as Array<Number>),
                       "what changed since last seen");
    Test.assertEqualMessage(view.movedOf(view.TIME), 2, "the time from 14:38");
    Test.assertEqualMessage(view.movedOf(Lib.Numbers.COUNTDOWN), 2, "the countdown from 4:44");
    var started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("a wake's frame: " + (System.getTimer() - started) + " ms");
    ShuttleTest.run(view, dc, 90000, 92500, 60);
    Test.assertMessage(!view.isAnimating(), "it settles");
    return true;
}

// A busy wake, everything moving, takes its frames within the budget and settles
(:test)
function testShuttleBusyWake(logger as Logger) as Boolean {
    var dc = ShuttleTest.dc();
    var view = ShuttleTest.view(dc, 1000);
    view.setAwake(false);
    view.onUpdate(dc);
    view.setClock(420000);
    view.setValues(ShuttleTest.values("11/29", "15", "49", "18:17", "2:35", "59°", "61", "47", "96", "8357", "39", "54%"));
    view.onUpdate(dc);
    view.setAwake(true);
    var most = 0;
    for (var t = 420000; t <= 423000; t += 63) {
        view.setClock(t);
        var started = System.getTimer();
        view.onUpdate(dc);
        var took = System.getTimer() - started;
        most = (took > most) ? took : most;
    }
    logger.debug("a busy wake's longest frame, watchdog off: " + most + " ms");
    Test.assertMessage(!view.isAnimating(), "it settles");
    return true;
}

(:test)
function testShuttleDigits(logger as Logger) as Boolean {
    var chars = "0123456789:/°-%".toCharArray();
    Test.assertEqualMessage(Digits.BLACK.size(), chars.size(), "a block per character");
    Test.assertEqualMessage(Digits.REGULAR.size(), chars.size(), "both weights");
    for (var i = 0; i < chars.size(); i++) {
        Test.assertEqualMessage(Digits.index(chars[i]), i, "the index");
        var g = Digits.BLACK[i];
        Test.assertMessage(g[0] > 0 && g[0] <= 1000, "a width");
        Test.assertEqualMessage((g.size() - 2) % 4, 0, "whole rectangles");
    }
    Test.assertEqualMessage(Digits.index('x'), -1, "none");
    return true;
}

// A hold on a reading opens it; on the time it steps the look
(:test)
function testShuttleTargets(logger as Logger) as Boolean {
    var dc = ShuttleTest.dc();
    var w = dc.getWidth();
    var view = ShuttleTest.view(dc, 1000);
    Test.assertMessage(view.targetAt((w * 0.5).toNumber(), (w * 0.44).toNumber()) == null, "the time is no target");
    Test.assertMessage(view.targetAt((w * 0.8).toNumber(), (w * 0.26).toNumber()) == Complications.COMPLICATION_TYPE_BATTERY, "the battery");
    Test.assertMessage(view.targetAt((w * 0.3).toNumber(), (w * 0.65).toNumber()) == Complications.COMPLICATION_TYPE_HEART_RATE, "heart rate");
    Test.assertMessage(view.targetAt((w * 0.5).toNumber(), (w * 0.85).toNumber()) == Complications.COMPLICATION_TYPE_CURRENT_WEATHER, "the weather");
    return true;
}

// A start lights the time alone, then builds the rest over a few frames; a
// wake draws only the rows that changed
(:test)
function testShuttleLightsFast(logger as Logger) as Boolean {
    var dc = ShuttleTest.dc();
    var view = new ShuttleView();
    view.onLayout(dc);
    view.setRolling(false);
    view.setValues(ShuttleTest.base());
    view.onUpdate(dc);
    Test.assertEqualMessage(view.rowsDrawn(), 1, "a start's first frame: the time alone");
    Test.assertMessage(view.isAnimating(), "the rest to come");
    var frames = 1;
    while (view.isAnimating() && frames < 20) {
        view.onUpdate(dc);
        frames++;
    }
    Test.assertMessage(!view.isAnimating(), "built");
    Test.assertMessage(frames > 2, "over a few frames");

    view.setAwake(false);
    view.onUpdate(dc);
    view.setAwake(true);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.rowsDrawn(), 0, "a wake with nothing changed: a blit");

    view.setAwake(false);
    view.onUpdate(dc);
    view.setValues(ShuttleTest.values("10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "72", "6900", "82", "87%"));
    view.onUpdate(dc);
    view.setAwake(true);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.rowsDrawn(), 1, "a wake after the steps changed: their row alone");
    return true;
}
