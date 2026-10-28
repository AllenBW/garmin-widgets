import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Run No Evil tests for Horizon: scripts/test.sh horizon [device].

(:test)
function testOutlook(logger as Logger) as Boolean {
    var now = 10 * 3600 + 8 * 60;      // 10:08
    var hours = [] as Array<[Number, Number]>;
    for (var k = 0; k < 13; k++) {
        var chance = (k == 5) ? 70 : ((k == 6) ? 45 : ((k == 7) ? 25 : 5));   // rain from 15:00
        hours.add([10 * 3600 + k * 3600, chance]);
    }
    var rise = 6 * 3600 + 52 * 60;
    var set = 17 * 3600 + 41 * 60;
    var o = HorizonModel.build(now, hours, rise, set, rise + 86400 + 60, "16:00");
    Test.assertEqualMessage(o.hourStart, 10 * 3600, "current hour");
    Test.assertMessage(o.hasForecast, "has forecast");
    Test.assertEqualMessage(o.rain[0], 5, "slot 0 is 10:00");
    Test.assertEqualMessage(o.rain[5], 70, "15:00 is 70 %");
    var from = o.rainFrom;
    Test.assertMessage(from != null && from == 5, "rain from slot 5");
    Test.assertEqualMessage(HorizonModel.rainText(o), "rain from " + Lib.Fmt.clock(15 * 3600) + ", 70%", "rain line");
    Test.assertMessage(!o.night[0] && !o.night[7], "10:00 and 17:00 are day");
    Test.assertMessage(o.night[8] && o.night[11], "18:00 and 21:00 are night");
    var sun = o.sunSecs;
    Test.assertMessage(sun != null && sun == set && !o.sunIsRise, "next sun event is sunset");
    var cal = o.calendarSecs;
    Test.assertMessage(cal != null && cal == 16 * 3600, "event at 16:00");
    logger.debug(HorizonModel.rainText(o));

    // Evening: the window wraps past midnight, sunrise tomorrow inside it
    var evening = HorizonModel.build(20 * 3600, [] as Array<[Number, Number]>, rise, set, rise + 86400, "7:30 am");
    Test.assertEqualMessage(HorizonModel.rainText(evening), "no forecast", "no forecast");
    Test.assertMessage(evening.night[0] && evening.night[3], "20:00 and 23:00 are night");
    Test.assertMessage(evening.night[4] && evening.night[10], "00:00 and 06:00 are night");
    Test.assertMessage(!evening.night[11], "07:00 is day (sunrise 06:52)");
    sun = evening.sunSecs;
    Test.assertMessage(sun != null && sun == rise + 86400 && evening.sunIsRise, "next sun event is tomorrow's sunrise");
    cal = evening.calendarSecs;
    Test.assertMessage(cal != null && cal == 86400 + 7 * 3600 + 30 * 60, "7:30 am is tomorrow");

    // Rain now
    var wet = HorizonModel.build(now, [[10 * 3600, 80]] as Array<[Number, Number]>, rise, set, null, null);
    Test.assertEqualMessage(HorizonModel.rainText(wet), "rain now, 80%", "rain now");
    var dry = HorizonModel.build(now, [[10 * 3600, 10]] as Array<[Number, Number]>, rise, set, null, null);
    Test.assertEqualMessage(HorizonModel.rainText(dry), "no rain in the next 12 h", "dry");
    Test.assertMessage(dry.sunSecs != null, "sunset within 12 h of 10:08");
    var late = HorizonModel.build(5 * 3600, [] as Array<[Number, Number]>, rise, set, null, null);
    Test.assertMessage(late.sunSecs != null && late.sunIsRise, "sunrise next at 05:00");
    return true;
}

(:test)
function testParseClock(logger as Logger) as Boolean {
    var cases = [["16:05", 16 * 3600 + 5 * 60], ["4:05 pm", 16 * 3600 + 5 * 60], ["12:00 AM", 0],
                 ["12:30 PM", 12 * 3600 + 30 * 60], ["9 am", 9 * 3600]] as Array<[String, Number]>;
    for (var i = 0; i < cases.size(); i++) {
        var parsed = HorizonModel.parseClock(cases[i][0]);
        Test.assertMessage(parsed != null && parsed == cases[i][1], cases[i][0] + " -> " + parsed);
    }
    Test.assertMessage(HorizonModel.parseClock(null) == null, "null");
    Test.assertMessage(HorizonModel.parseClock("none") == null, "no digits");
    Test.assertMessage(HorizonModel.parseClock("25:00") == null, "out of range");
    return true;
}

(:test)
function testDial(logger as Logger) as Boolean {
    Test.assertEqualMessage(HorizonModel.dialDegrees(0), 0.0, "midnight at 12");
    Test.assertEqualMessage(HorizonModel.dialDegrees(3 * 3600), 90.0, "3:00 at 3");
    Test.assertEqualMessage(HorizonModel.dialDegrees(15 * 3600), 90.0, "15:00 at 3");
    Test.assertEqualMessage(HorizonModel.dialDegrees(18 * 3600 + 30 * 60), 195.0, "18:30");
    return true;
}

(:test)
function testFaceDrawsBothModes(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();
    var view = new HorizonView();
    view.onLayout(dc);
    view.onUpdate(dc);
    view.onEnterSleep();
    view.onUpdate(dc);
    view.onExitSleep();
    view.onUpdate(dc);
    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}
