import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Run No Evil tests for Lockup: scripts/test.sh lockup [device]

function lockupDc() as Dc {
    var settings = System.getDeviceSettings();
    return (Graphics.createBufferedBitmap({:width => settings.screenWidth, :height => settings.screenHeight}).get()
            as Graphics.BufferedBitmap).getDc();
}

// Date, hours, minutes, sun, countdown, temperature, high, low, heart, steps,
// body, altitude, wind, battery, time
function lockupValues(date as String, hh as String, mm as String, sun as String, count as String, temp as String, hi as String, lo as String,
                      heart as String, steps as String, body as String, battery as String) as Array<String> {
    return [date, hh, mm, sun, count, temp, hi, lo, heart, steps, body, "", "", battery, hh + ":" + mm] as Array<String>;
}

(:test)
function testLockupDrawsEveryMode(logger as Logger) as Boolean {
    var dc = lockupDc();
    var view = new LockupView();
    view.onLayout(dc);

    // Whatever the simulator provides
    var started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake, every row: " + (System.getTimer() - started) + " ms");
    started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake, nothing changed: " + (System.getTimer() - started) + " ms");

    var samples = [
        lockupValues("1/1", "00", "00", "--:--", "--:--", "--", "--", "--", "--", "--", "--", "--"),      // nothing yet
        lockupValues("3/5", "07", "05", "07:12", "0:05", "5°", "9", "-2", "58", "0", "7", "5%"),          // short
        lockupValues("10/31", "21", "05", "07:12", "10:07", "28°", "41", "24", "58", "11382", "47", "87%"),
        lockupValues("11/11", "11", "11", "17:01", "11:11", "-12°", "-4", "-19", "148", "21114", "100", "100%"),   // widest
        lockupValues("12/28", "20", "08", "20:08", "20:08", "-88°", "-88", "-88", "188", "88888", "100", "88%")     // most ink
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
function testLockupLooks(logger as Logger) as Boolean {
    var dc = lockupDc();
    var view = new LockupView();
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

// A change rolls while awake and stops; asleep, nothing does
(:test)
function testLockupRolling(logger as Logger) as Boolean {
    var dc = lockupDc();
    var view = new LockupView();
    view.onLayout(dc);
    view.setRolling(true);
    view.setClock(1000);
    var a = lockupValues("10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "72", "6214", "82", "87%");
    var b = lockupValues("10/31", "14", "39", "19:22", "4:43", "46°", "52", "38", "73", "6214", "82", "86%");
    view.setValues(a);
    view.onUpdate(dc);
    view.setClock(5000);
    view.setValues(b);
    Test.assertMessage(view.isRolling(view.TIME), "the time rolls");
    Test.assertMessage(view.isRolling(Lib.Numbers.COUNTDOWN), "the countdown rolls");
        Test.assertMessage(!view.isRolling(Lib.Numbers.TEMP), "what didn't change doesn't");
    Test.assertMessage(view.isAnimating(), "frames are wanted");
    for (var t = 5000; t <= 5400; t += 100) {
        view.setClock(t);
        view.onUpdate(dc);
    }
    Test.assertMessage(!view.isRolling(view.TIME), "and it stops");
    Test.assertMessage(!view.isAnimating(), "no more frames");

    // A digit more can't roll: it just changes
    view.setValues(lockupValues("10/31", "14", "39", "19:22", "10:43", "46°", "52", "38", "100", "6214", "82", "86%"));
    Test.assertMessage(!view.isRolling(Lib.Numbers.COUNTDOWN), "a new length");

    // Off is off
    view.setRolling(false);
    view.setValues(b);
    Test.assertMessage(!view.isRolling(view.TIME), "the setting");

    // Asleep nothing animates, whatever changes
    view.setRolling(true);
    view.setAwake(false);
    view.setValues(a);
    Test.assertMessage(!view.isAnimating(), "asleep");
    view.onUpdate(dc);
    return true;
}

// On a wake what changed rolls from what was last seen
(:test)
function testLockupWake(logger as Logger) as Boolean {
    var dc = lockupDc();
    var view = new LockupView();
    view.onLayout(dc);
    view.setRolling(true);
    view.setClock(1000);
    view.setValues(lockupValues("10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "72", "6214", "82", "87%"));
    view.onUpdate(dc);
    view.setAwake(false);
    view.onUpdate(dc);
    view.setClock(90000);
    view.setValues(lockupValues("10/31", "14", "59", "19:22", "4:23", "47°", "52", "38", "72", "6900", "81", "85%"));
    view.onUpdate(dc);
    view.setAwake(true);
    view.onUpdate(dc);
    Test.assertMessage(view.isRolling(view.TIME), "the time");
    Test.assertMessage(view.isRolling(Lib.Numbers.STEPS), "the steps");
    Test.assertMessage(!view.isRolling(Lib.Numbers.HIGH), "not the high");
        Test.assertMessage(view.isAnimating(), "frames are wanted");
    for (var t = 90000; t <= 93200; t += 250) {
        view.setClock(t);
        view.onUpdate(dc);
    }
    Test.assertMessage(!view.isAnimating(), "it settles");
    return true;
}

(:test)
function testLockupDigits(logger as Logger) as Boolean {
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
function testLockupTargets(logger as Logger) as Boolean {
    var dc = lockupDc();
    var w = dc.getWidth();
    var view = new LockupView();
    view.onLayout(dc);
    view.setValues(lockupValues("10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "72", "6214", "82", "87%"));
    view.onUpdate(dc);
    Test.assertMessage(view.targetAt((w * 0.5).toNumber(), (w * 0.44).toNumber()) == null, "the time is no target");
    Test.assertMessage(view.targetAt((w * 0.8).toNumber(), (w * 0.26).toNumber()) == Complications.COMPLICATION_TYPE_BATTERY, "the battery");
    Test.assertMessage(view.targetAt((w * 0.3).toNumber(), (w * 0.65).toNumber()) == Complications.COMPLICATION_TYPE_HEART_RATE, "heart rate");
    Test.assertMessage(view.targetAt((w * 0.5).toNumber(), (w * 0.85).toNumber()) == Complications.COMPLICATION_TYPE_CURRENT_WEATHER, "the weather");
    return true;
}
