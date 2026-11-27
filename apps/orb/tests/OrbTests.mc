import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Run No Evil tests for Orb: scripts/test.sh orb [device]

(:test)
module OrbTest {

    function dc() as Dc {
        var settings = System.getDeviceSettings();
        return (Graphics.createBufferedBitmap({:width => settings.screenWidth, :height => settings.screenHeight}).get()
                as Graphics.BufferedBitmap).getDc();
    }

    // Date, hours, minutes, sun, countdown, temperature, high, low, heart,
    // steps, body, altitude, wind, battery, time
    function values(date as String, hh as String, mm as String, sun as String, count as String, temp as String, hi as String,
                    lo as String, heart as String, steps as String, body as String, battery as String) as Array<String> {
        return [date, hh, mm, sun, count, temp, hi, lo, heart, steps, body, "", "", battery, hh + ":" + mm] as Array<String>;
    }

    // The sample readings, and as they were seven minutes before
    function base() as Array<String> {
        return values("10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "72", "6214", "82", "87%");
    }

    function away() as Array<String> {
        return values("10/31", "14", "31", "19:22", "4:51", "45°", "52", "38", "88", "5980", "83", "88%");
    }

    // What each band does, joined: "date|sun|time|body|weather"
    function moves(view as OrbView) as String {
        var s = "";
        for (var i = 0; i < 5; i++) {
            s += ((i > 0) ? "|" : "") + view.moving(i);
        }
        return s;
    }

    // Frames every `step` ms from `from` until nothing moves; the frames taken
    function settle(view as OrbView, dc as Dc, from as Number, step as Number) as Number {
        var frames = 0;
        var t = from;
        while (view.isAnimating() && frames < 200) {
            t += step;
            view.setClock(t);
            view.onUpdate(dc);
            frames++;
        }
        return frames;
    }

    function fresh(dc as Dc, values as Array<String>) as OrbView {
        var view = new OrbView();
        view.onLayout(dc);
        view.setMotion(true);
        view.setClock(1000);
        view.setValues(values);
        for (var n = 0; n < 10 && (n == 0 || view.isAnimating()); n++) {
            view.onUpdate(dc);     // a start builds over a few frames, the time first
        }
        return view;
    }
}

(:test)
function testOrbDrawsEveryMode(logger as Logger) as Boolean {
    var dc = OrbTest.dc();
    var view = new OrbView();
    view.onLayout(dc);

    // Whatever the simulator provides
    var started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake, every band: " + (System.getTimer() - started) + " ms");
    started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake, nothing changed: " + (System.getTimer() - started) + " ms");

    var samples = [
        OrbTest.values("1/1", "00", "00", "--:--", "--:--", "--", "--", "--", "--", "--", "--", "--"),      // nothing yet
        OrbTest.values("3/5", "07", "05", "07:12", "0:05", "5°", "9", "-2", "58", "0", "7", "5%"),          // short
        OrbTest.base(),
        OrbTest.values("11/11", "11", "11", "17:01", "11:11", "-12°", "-4", "-19", "148", "21114", "100", "100%"),   // widest
        OrbTest.values("12/28", "20", "08", "20:08", "20:08", "-88°", "-88", "-88", "188", "88888", "100", "88%")     // most ink
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
function testOrbLooks(logger as Logger) as Boolean {
    var dc = OrbTest.dc();
    var view = new OrbView();
    view.onLayout(dc);
    var phone = Application.Properties.getValue(Lib.Look.KEY);    // a hold moves the phone's Look too: put it back
    var seen = Application.Storage.getValue(Lib.Look.SEEN);
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
    if (phone != null) {
        Application.Properties.setValue(Lib.Look.KEY, phone as Number);
    }
    if (seen != null) {
        Application.Storage.setValue(Lib.Look.SEEN, seen as Number);
    } else {
        Application.Storage.deleteValue(Lib.Look.SEEN);
    }
    return true;
}

// The rule: a turn when at least half a band changed or a reading changed
// its length, drums for fewer, units first
(:test)
function testOrbMoves(logger as Logger) as Boolean {
    var t = OrbMoves.mode(["14:38"] as Array<String>, ["14:39"] as Array<String>, true);
    Test.assertEqualMessage(t, OrbMoves.DRUMS, "a minute: one digit");
    t = OrbMoves.mode(["14:59"] as Array<String>, ["15:00"] as Array<String>, true);
    Test.assertEqualMessage(t, OrbMoves.TURN, "three of five");
    t = OrbMoves.mode(["14:59"] as Array<String>, ["15:00"] as Array<String>, false);
    Test.assertEqualMessage(t, OrbMoves.DRUMS, "turns off: drums");
    t = OrbMoves.mode(["9:59"] as Array<String>, ["10:00"] as Array<String>, true);
    Test.assertEqualMessage(t, OrbMoves.TURN, "a new length turns");
    t = OrbMoves.mode(["9:59"] as Array<String>, ["10:00"] as Array<String>, false);
    Test.assertEqualMessage(t, OrbMoves.SNAP, "or, turns off, just changes");
    t = OrbMoves.mode(["72", "6214", "82"] as Array<String>, ["72", "6214", "82"] as Array<String>, true);
    Test.assertEqualMessage(t, OrbMoves.NONE, "nothing");
    var d = OrbMoves.delays([false, true, false, true, true] as Array<Boolean>, 70);
    Test.assertEqualMessage(d[4], 0, "units first");
    Test.assertEqualMessage(d[3], 70, "then the tens");
    Test.assertEqualMessage(d[1], 140, "and so on");
    Test.assertEqualMessage(d[0], -1, "the rest stay");
    return true;
}

// A minute passing: the time's last digit and the countdown's, nothing else
(:test)
function testOrbMinute(logger as Logger) as Boolean {
    var dc = OrbTest.dc();
    var view = OrbTest.fresh(dc, OrbTest.base());
    Test.assertEqualMessage(OrbTest.moves(view), "||||", "at rest");
    view.setValues(OrbTest.values("10/31", "14", "39", "19:22", "4:43", "46°", "52", "38", "72", "6214", "82", "87%"));
    Test.assertEqualMessage(OrbTest.moves(view), "|........x...|....x||", "only the changed digits");
    Test.assertMessage(view.isAnimating(), "frames are wanted");
    var frames = OrbTest.settle(view, dc, 1000, 50);
    logger.debug("a minute: " + frames + " frames");
    Test.assertMessage(!view.isAnimating(), "and it settles");
    Test.assertMessage(frames > 10 && frames < 40, "in about a second");
    return true;
}

// A heart rate alone: one digit
(:test)
function testOrbHeartAlone(logger as Logger) as Boolean {
    var dc = OrbTest.dc();
    var view = OrbTest.fresh(dc, OrbTest.base());
    view.setValues(OrbTest.values("10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "74", "6214", "82", "87%"));
    Test.assertEqualMessage(OrbTest.moves(view), "|||.x......|", "one digit");
    OrbTest.settle(view, dc, 1000, 50);
    Test.assertMessage(!view.isAnimating(), "settles");

    // Nothing changed, nothing moves
    view.setValues(OrbTest.values("10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "74", "6214", "82", "87%"));
    Test.assertEqualMessage(OrbTest.moves(view), "||||", "nothing");
    Test.assertMessage(!view.isAnimating(), "no frames");
    return true;
}

// Most of a band changed: the band turns whole; a new length too
(:test)
function testOrbTurns(logger as Logger) as Boolean {
    var dc = OrbTest.dc();
    var view = OrbTest.fresh(dc, OrbTest.base());
    view.setValues(OrbTest.values("10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "88", "5980", "83", "87%"));
    Test.assertEqualMessage(OrbTest.moves(view), "|||turn|", "the body's band turns");
    var frames = OrbTest.settle(view, dc, 1000, 50);
    logger.debug("a turn: " + frames + " frames");
    Test.assertMessage(!view.isAnimating(), "and settles");
    view.setValues(OrbTest.values("10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "88", "5980", "100", "87%"));
    Test.assertEqualMessage(OrbTest.moves(view), "|||turn|", "a new length turns");

    // Off is off
    OrbTest.settle(view, dc, 5000, 50);
    view.setMotion(false);
    view.setValues(OrbTest.base());
    Test.assertEqualMessage(OrbTest.moves(view), "||||", "the setting");
    Test.assertMessage(!view.isAnimating(), "no frames");
    return true;
}

// On a wake what changed while asleep moves from what was last seen; asleep nothing does
(:test)
function testOrbWake(logger as Logger) as Boolean {
    var dc = OrbTest.dc();
    var view = OrbTest.fresh(dc, OrbTest.away());
    view.setAwake(false);
    view.onUpdate(dc);
    view.setClock(90000);
    view.setValues(OrbTest.base());
    Test.assertEqualMessage(OrbTest.moves(view), "||||", "asleep nothing moves");
    Test.assertMessage(!view.isAnimating(), "asleep");
    view.onUpdate(dc);
    view.setAwake(true);
    view.onUpdate(dc);
    Test.assertEqualMessage(OrbTest.moves(view), "|.......xx.x.|....x|turn|...x...", "what changed while asleep");
    Test.assertMessage(view.isAnimating(), "frames are wanted");
    var frames = OrbTest.settle(view, dc, 90000, 50);
    logger.debug("a wake: " + frames + " frames");
    Test.assertMessage(!view.isAnimating(), "it settles");

    // Asleep mid-motion: it lands, and standby draws
    view.setValues(OrbTest.away());
    Test.assertMessage(view.isAnimating(), "moving");
    view.setAwake(false);
    Test.assertMessage(!view.isAnimating(), "landed");
    view.onUpdate(dc);
    return true;
}

// A stall skips motion rather than stretching it
(:test)
function testOrbStall(logger as Logger) as Boolean {
    var dc = OrbTest.dc();
    var view = OrbTest.fresh(dc, OrbTest.away());
    view.setValues(OrbTest.base());
    var frames = OrbTest.settle(view, dc, 1000, 1000);
    logger.debug("a wake, a frame a second: " + frames + " frames");
    Test.assertMessage(frames < 40, "it still ends");
    return true;
}

(:test)
function testOrbDigits(logger as Logger) as Boolean {
    var chars = "0123456789:/°-%".toCharArray();
    Test.assertEqualMessage(Digits.BLACK.size(), chars.size(), "a block per character");
    Test.assertEqualMessage(Digits.REGULAR.size(), chars.size(), "both weights");
    for (var i = 0; i < chars.size(); i++) {
        Test.assertEqualMessage(Digits.index(chars[i]), i, "the index");
    }
    return true;
}

// A hold on a reading opens it; on the time it steps the look
(:test)
function testOrbTargets(logger as Logger) as Boolean {
    var dc = OrbTest.dc();
    var w = dc.getWidth();
    var view = OrbTest.fresh(dc, OrbTest.base());
    Test.assertMessage(view.targetAt((w * 0.5).toNumber(), (w * 0.44).toNumber()) == null, "the time is no target");
    Test.assertMessage(view.targetAt((w * 0.85).toNumber(), (w * 0.22).toNumber()) == Complications.COMPLICATION_TYPE_BATTERY, "the battery");
    Test.assertMessage(view.targetAt((w * 0.2).toNumber(), (w * 0.22).toNumber()) == Complications.COMPLICATION_TYPE_SUNRISE, "the sun");
    Test.assertMessage(view.targetAt((w * 0.2).toNumber(), (w * 0.66).toNumber()) == Complications.COMPLICATION_TYPE_HEART_RATE, "heart rate");
    Test.assertMessage(view.targetAt((w * 0.5).toNumber(), (w * 0.66).toNumber()) == Complications.COMPLICATION_TYPE_STEPS, "steps");
    Test.assertMessage(view.targetAt((w * 0.5).toNumber(), (w * 0.85).toNumber()) == Complications.COMPLICATION_TYPE_CURRENT_WEATHER, "the weather");
    return true;
}

// A start lights the time alone, then builds the rest a band a frame; a
// wake with nothing changed draws nothing
(:test)
function testOrbLightsFast(logger as Logger) as Boolean {
    var dc = OrbTest.dc();
    var view = new OrbView();
    view.onLayout(dc);
    view.setMotion(true);
    view.setClock(1000);
    view.setValues(OrbTest.base());
    view.onUpdate(dc);
    var drawn = view.bandsDrawn();
    Test.assertMessage(drawn.size() == 1 && drawn[0] == view.TIME_BAND, "a start's first frame: the time alone");
    Test.assertMessage(view.isAnimating(), "the rest to come");
    var frames = 1;
    while (view.isAnimating() && frames < 10) {
        view.onUpdate(dc);
        Test.assertEqualMessage(view.bandsDrawn().size(), 1, "a band a frame");
        frames++;
    }
    Test.assertMessage(!view.isAnimating(), "built");
    Test.assertEqualMessage(frames, 5, "five bands");

    view.setAwake(false);
    view.onUpdate(dc);
    view.setAwake(true);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.bandsDrawn().size(), 0, "a wake with nothing changed: a blit");
    return true;
}
