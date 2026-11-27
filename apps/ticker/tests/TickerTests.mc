import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Run No Evil tests for Ticker: scripts/test.sh ticker [device]

(:test)
module TickerTest {

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

    // The sketch's readings: 14:38, sunset 19:22 in 4:44, 46°, 52 and 38, 72 bpm, 6214 steps, Body Battery 82, 87 %
    function base() as Array<String> {
        return values("10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "72", "6214", "82", "87%");
    }

    // A face shown awake with `first` settled, its clock at `t`
    function awake(d as Dc, first as Array<String>, t as Number) as TickerView {
        var view = new TickerView();
        view.onLayout(d);
        view.setClock(t);
        view.setValues(first);
        view.setAwake(true);
        for (var n = 0; n < 10 && (n == 0 || view.isAnimating()); n++) {
            view.onUpdate(d);     // a start builds over a few frames, the time first
        }
        return view;
    }

    // Frames 100 ms apart from `t` until the move settles; returns the clock
    // then. Fails if it never does, or a frame draws over the budget.
    function settle(view as TickerView, d as Dc, t as Number, logger as Test.Logger) as Number {
        var most = 0;
        for (var n = 0; n < 60 && view.isAnimating(); n++) {
            t += 100;
            view.setClock(t);
            view.onUpdate(d);
            var chars = view.charsLastFrame();
            most = (chars > most) ? chars : most;
            Test.assertMessage(chars <= view.BUDGET, "a frame within the budget: " + chars);
        }
        Test.assertMessage(!view.isAnimating(), "it settles");
        logger.debug("most characters in a frame: " + most);
        return t;
    }
}

(:test)
function tickerDrawsEveryMode(logger as Test.Logger) as Boolean {
    var dc = TickerTest.dc();
    var view = new TickerView();
    view.onLayout(dc);

    // Whatever the simulator provides
    var started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake, every band: " + (System.getTimer() - started) + " ms");
    started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake, nothing changed: " + (System.getTimer() - started) + " ms");

    var samples = [
        TickerTest.values("1/1", "00", "00", "--:--", "--:--", "--", "--", "--", "--", "--", "--", "--"),      // nothing yet
        TickerTest.values("3/5", "07", "05", "07:12", "0:05", "5°", "9", "-2", "58", "0", "7", "5%"),          // short
        TickerTest.values("10/31", "21", "05", "07:12", "10:07", "28°", "41", "24", "58", "11382", "47", "87%"),
        TickerTest.values("11/11", "11", "11", "17:01", "11:11", "-12°", "-4", "-19", "148", "21114", "100", "100%"),   // widest
        TickerTest.values("12/28", "20", "08", "20:08", "20:08", "-88°", "-88", "-88", "188", "88888", "100", "88%")     // most ink
    ] as Array<Array<String>>;
    view.setAwake(true);
    var t = 1000;
    for (var i = 0; i < samples.size(); i++) {
        view.setClock(t);
        view.setValues(samples[i]);
        started = System.getTimer();
        view.onUpdate(dc);
        logger.debug("awake " + i + ": " + (System.getTimer() - started) + " ms, " + view.charsLastFrame() + " characters");
        t = TickerTest.settle(view, dc, t, logger);
        view.setAwake(false);
        started = System.getTimer();
        view.onUpdate(dc);
        logger.debug("standby " + i + ": " + (System.getTimer() - started) + " ms");
        view.setAwake(true);
    }
    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}

// Every look draws, awake and in standby
(:test)
function tickerLooks(logger as Test.Logger) as Boolean {
    var dc = TickerTest.dc();
    var view = TickerTest.awake(dc, TickerTest.base(), 1000);
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

// A minute passing while awake: the minute tape steps one minute, the top
// tape turns to the countdown and only its changed digit slides
(:test)
function tickerMinute(logger as Test.Logger) as Boolean {
    var dc = TickerTest.dc();
    var view = TickerTest.awake(dc, TickerTest.base(), 1000);
    Test.assertMessage(!view.isAnimating(), "the first sight: nothing moves");
    Test.assertEqualMessage(view.centre(0), Lib.Numbers.SUN_TIME, "the top tape rests on the sun");
    Test.assertEqualMessage(view.centre(1), Lib.Numbers.TEMP, "the bottom one on the temperature");

    view.setValues(TickerTest.values("10/31", "14", "39", "19:22", "4:43", "46°", "52", "38", "72", "6214", "82", "87%"));
    view.setClock(1100);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.minuteSteps(), 1, "one minute");
    Test.assertMessage(view.turns(0), "the top tape turns");
    Test.assertEqualMessage(view.centre(0), Lib.Numbers.COUNTDOWN, "to the countdown");
    Test.assertMessage(view.slides(Lib.Numbers.COUNTDOWN), "whose digits slide");
    Test.assertMessage(!view.turns(1), "the bottom tape stays");
    Test.assertMessage(!view.slides(Lib.Numbers.HEART) && !view.slides(Lib.Numbers.TEMP) && !view.slides(Lib.Numbers.SUN_TIME), "nothing else");
    var t = TickerTest.settle(view, dc, 1100, logger);
    Test.assertEqualMessage(view.centre(0), Lib.Numbers.COUNTDOWN, "it stays on the countdown");

    // The next minute: already on the countdown, so only digits slide
    view.setValues(TickerTest.values("10/31", "14", "40", "19:22", "4:42", "46°", "52", "38", "72", "6214", "82", "87%"));
    view.setClock(t + 100);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.minuteSteps(), 1, "one minute more");
    Test.assertMessage(!view.turns(0), "no turn");
    Test.assertMessage(view.slides(Lib.Numbers.COUNTDOWN), "the digit slides");
    TickerTest.settle(view, dc, t + 100, logger);
    return true;
}

// A new heart rate alone: the bottom tape turns to it and its digit slides;
// nothing else moves
(:test)
function tickerHeartOnly(logger as Test.Logger) as Boolean {
    var dc = TickerTest.dc();
    var view = TickerTest.awake(dc, TickerTest.base(), 1000);
    view.setValues(TickerTest.values("10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "74", "6214", "82", "87%"));
    view.setClock(1100);
    view.onUpdate(dc);
    Test.assertMessage(view.isAnimating(), "it moves");
    Test.assertEqualMessage(view.minuteSteps(), 0, "not the minutes");
    Test.assertMessage(!view.turns(0), "not the top tape");
    Test.assertMessage(view.turns(1), "the bottom tape turns");
    Test.assertEqualMessage(view.centre(1), Lib.Numbers.HEART, "to the heart rate");
    Test.assertMessage(view.slides(Lib.Numbers.HEART), "which slides");
    Test.assertMessage(!view.slides(Lib.Numbers.STEPS) && !view.slides(Lib.Numbers.TEMP) && !view.slides(Lib.Numbers.COUNTDOWN), "nothing else");
    TickerTest.settle(view, dc, 1100, logger);
    return true;
}

// Nothing changed, nothing moves
(:test)
function tickerNothing(logger as Test.Logger) as Boolean {
    var dc = TickerTest.dc();
    var view = TickerTest.awake(dc, TickerTest.base(), 1000);
    for (var t = 1100; t <= 3000; t += 100) {
        view.setValues(TickerTest.base());
        view.setClock(t);
        view.onUpdate(dc);
        Test.assertMessage(!view.isAnimating(), "still");
    }
    // Nor across a sleep with nothing new
    view.setAwake(false);
    view.onUpdate(dc);
    view.setAwake(true);
    view.setClock(4000);
    view.onUpdate(dc);
    Test.assertMessage(!view.isAnimating(), "still after a wake");
    return true;
}

// A wake moves what changed while asleep: the minutes run through every one
// missed, twelve at most; the tapes turn to the first change
(:test)
function tickerWake(logger as Test.Logger) as Boolean {
    var dc = TickerTest.dc();
    var view = TickerTest.awake(dc, TickerTest.values("10/31", "14", "31", "19:22", "4:51", "45°", "52", "38", "88", "5980", "83", "88%"), 1000);
    view.setValues(TickerTest.values("10/31", "14", "31", "19:22", "4:51", "45°", "52", "38", "73", "5980", "83", "88%"));
    view.setClock(1100);
    view.onUpdate(dc);
    TickerTest.settle(view, dc, 1100, logger);
    Test.assertEqualMessage(view.centre(1), Lib.Numbers.HEART, "awake, on the heart rate");

    view.setAwake(false);
    view.setClock(5000);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.centre(0), Lib.Numbers.SUN_TIME, "asleep, back to rest");
    Test.assertEqualMessage(view.centre(1), Lib.Numbers.TEMP, "both");
    view.setValues(TickerTest.base());                     // seven minutes on
    view.setClock(420000);
    view.onUpdate(dc);
    Test.assertMessage(!view.isAnimating(), "standby doesn't move");

    view.setAwake(true);
    view.setClock(421000);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.minuteSteps(), 7, "every minute missed");
    Test.assertEqualMessage(view.centre(0), Lib.Numbers.COUNTDOWN, "the top tape to the countdown");
    Test.assertEqualMessage(view.centre(1), Lib.Numbers.HEART, "the bottom to the heart rate");
    Test.assertMessage(view.slides(Lib.Numbers.HEART) && view.slides(Lib.Numbers.STEPS) && view.slides(Lib.Numbers.BODY)
                       && view.slides(Lib.Numbers.TEMP) && view.slides(view.BATTERY), "what changed slides");
    Test.assertMessage(!view.slides(Lib.Numbers.HIGH) && !view.slides(Lib.Numbers.DATE), "not the rest");
    var t = TickerTest.settle(view, dc, 421000, logger);

    // Forty minutes away: the run starts twelve back
    view.setAwake(false);
    view.onUpdate(dc);
    view.setValues(TickerTest.values("10/31", "15", "18", "19:22", "4:04", "46°", "52", "38", "72", "6214", "82", "87%"));
    view.onUpdate(dc);
    view.setAwake(true);
    view.setClock(t + 2400000);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.minuteSteps(), 12, "twelve at most");
    Test.assertMessage(!view.turns(1), "the bottom tape: nothing new");
    TickerTest.settle(view, dc, t + 2400000, logger);

    // Across midnight
    view.setAwake(false);
    view.onUpdate(dc);
    view.setValues(TickerTest.values("11/1", "00", "02", "06:58", "6:56", "46°", "52", "38", "72", "6214", "82", "87%"));
    view.onUpdate(dc);
    view.setAwake(true);
    view.setClock(t + 9000000);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.minuteSteps(), 12, "a long sleep");
    Test.assertEqualMessage(view.centre(0), Lib.Numbers.DATE, "a new day");
    TickerTest.settle(view, dc, t + 9000000, logger);
    return true;
}

// Off, a change shows at once, the tapes on what changed, nothing moving
(:test)
function tickerMotionOff(logger as Test.Logger) as Boolean {
    var dc = TickerTest.dc();
    var view = TickerTest.awake(dc, TickerTest.base(), 1000);
    view.setMotion(false);
    view.setValues(TickerTest.values("10/31", "14", "39", "19:22", "4:43", "46°", "52", "38", "74", "6214", "82", "87%"));
    view.setClock(1100);
    view.onUpdate(dc);
    Test.assertMessage(!view.isAnimating(), "no motion");
    Test.assertEqualMessage(view.centre(0), Lib.Numbers.COUNTDOWN, "the countdown at once");
    Test.assertEqualMessage(view.centre(1), Lib.Numbers.HEART, "the heart rate at once");
    return true;
}

// Before the face is shown awake (no wake, no once-a-second updates yet) a
// change waits rather than playing at a frame a second
(:test)
function tickerWaitsForAwake(logger as Test.Logger) as Boolean {
    var dc = TickerTest.dc();
    var view = new TickerView();
    view.onLayout(dc);
    view.setClock(1000);
    view.setValues(TickerTest.base());
    for (var n = 0; n < 10 && (n == 0 || view.isAnimating()); n++) {
        view.onUpdate(dc);     // a start builds over a few frames, the time first: frames it asks for, which prove nothing
    }
    view.setValues(TickerTest.values("10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "74", "6214", "82", "87%"));
    view.setClock(5000);
    view.onUpdate(dc);
    Test.assertMessage(!view.isAnimating(), "it waits");
    view.setClock(6000);
    view.onUpdate(dc);
    view.setClock(7000);
    view.onUpdate(dc);                                     // the system's once-a-second updates: awake
    Test.assertMessage(view.isAnimating(), "then moves");
    Test.assertMessage(view.slides(Lib.Numbers.HEART), "what changed");
    return true;
}

// The move's arithmetic: where it starts and ends
(:test)
function tickerMoveTimes(logger as Test.Logger) as Boolean {
    var a = TickerTest.base();
    var move = new TickerMove(a, a, 871, 7, [1, 3] as Array<Number>, [2, 0] as Array<Number>, [1, 4] as Array<Number>);
    Test.assertEqual(move.minutePos(), 871.0);
    Test.assertEqual(move.tapePos(0), 1.0);
    Test.assertEqual(move.slide(1, 0), 0.0);
    Test.assertEqualMessage(move.ends[1], 70 + 450 + 7 * 120 + 500, "the run: 450 ms and 120 a minute");
    Test.assertEqualMessage(move.slideAt[1], 850, "slides after the turn");
    Test.assertEqualMessage(move.ends[2], 850 + 3 * 60 + 70 + 360 + 500, "units first, 60 ms apart");
    move.t = move.end();
    Test.assert(move.done());
    Test.assertEqual(move.minutePos(), 878.0);
    Test.assertEqual(move.tapePos(1), 0.0);
    Test.assertEqual(move.slide(1, 3), 1.0);
    var still = new TickerMove(a, a, 871, 0, [1, 3] as Array<Number>, [1, 3] as Array<Number>, [2, 0] as Array<Number>);
    Test.assertEqualMessage(still.slideAt[0], 150, "no turn: the slides start at once");
    Test.assertEqualMessage(still.ends[1], 0, "the minutes still");
    return true;
}

(:test)
function tickerDigits(logger as Test.Logger) as Boolean {
    var chars = "0123456789:/°-%".toCharArray();
    Test.assertEqualMessage(Digits.BLACK.size(), chars.size(), "a block per character");
    for (var i = 0; i < chars.size(); i++) {
        Test.assertEqualMessage(Digits.index(chars[i]), i, "the index");
        var g = Digits.BLACK[i];
        Test.assertMessage(g[0] > 0 && g[0] <= 1000, "a width");
        Test.assertEqualMessage((g.size() - 2) % 4, 0, "whole rectangles");
    }
    var type = new TickerType();
    Test.assertEqualMessage(type.width("14:38"), 740 + 1000 + 300 + 1000 + 1000 + 4 * 120, "a time's width");
    return true;
}

// A hold on a tape's centre reading opens it; on the time it steps the look
(:test)
function tickerTargets(logger as Test.Logger) as Boolean {
    var dc = TickerTest.dc();
    var w = dc.getWidth();
    var view = TickerTest.awake(dc, TickerTest.base(), 1000);
    Test.assertMessage(view.onTime((w * 0.5).toNumber(), (w * 0.5).toNumber()), "the time");
    Test.assertMessage(view.targetAt((w * 0.5).toNumber(), (w * 0.5).toNumber()) == null, "is no reading");
    Test.assertMessage(view.targetAt((w * 0.5).toNumber(), (w * 0.215).toNumber()) == Complications.COMPLICATION_TYPE_SUNRISE, "the sun");
    Test.assertMessage(view.targetAt((w * 0.5).toNumber(), (w * 0.785).toNumber()) == Complications.COMPLICATION_TYPE_CURRENT_WEATHER, "the weather");
    Test.assertMessage(view.targetAt((w * 0.2).toNumber(), (w * 0.215).toNumber()) == null, "a neighbour is not");
    Test.assertMessage(!view.onTime((w * 0.5).toNumber(), (w * 0.9).toNumber()), "below is nothing");
    view.setValues(TickerTest.values("10/31", "14", "38", "19:22", "4:44", "46°", "52", "38", "74", "6214", "82", "87%"));
    view.setClock(1100);
    view.onUpdate(dc);
    TickerTest.settle(view, dc, 1100, logger);
    Test.assertMessage(view.targetAt((w * 0.5).toNumber(), (w * 0.785).toNumber()) == Complications.COMPLICATION_TYPE_HEART_RATE, "what it turned to");
    return true;
}

// A start lights the time alone, then builds the rest a band a frame; a
// wake with nothing changed draws nothing
(:test)
function tickerLightsFast(logger as Test.Logger) as Boolean {
    var dc = TickerTest.dc();
    var view = new TickerView();
    view.onLayout(dc);
    view.setClock(1000);
    view.setValues(TickerTest.base());
    view.setAwake(true);
    view.onUpdate(dc);
    Test.assertMessage(view.timeOnly(), "a start's first frame: the time alone");
    Test.assertMessage(view.isAnimating(), "the rest to come");
    var frames = 1;
    while (view.isAnimating() && frames < 10) {
        view.onUpdate(dc);
        frames++;
    }
    Test.assertMessage(!view.isAnimating(), "built");
    Test.assertEqualMessage(frames, 3, "a band a frame");

    view.setAwake(false);
    view.onUpdate(dc);
    view.setAwake(true);
    view.setClock(4000);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.charsLastFrame(), 0, "a wake with nothing changed: a blit");
    return true;
}
