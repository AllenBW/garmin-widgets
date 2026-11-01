import Toybox.Lang;
import Toybox.System;
import Toybox.Test;
import Toybox.Time;

// Run No Evil tests for the Lib barrel: scripts/test.sh field [device].
// Everything annotated (:test) is left out of normal builds.

(:test)
function testSunDialDegrees(logger as Logger) as Boolean {
    // Noon at the top (0), midnight at the bottom (180), 6:00 on the left
    Test.assertEqualMessage(Lib.Sun.dialDegrees(0), 180.0, "midnight");
    Test.assertEqualMessage(Lib.Sun.dialDegrees(12 * 3600), 0.0, "noon");
    Test.assertEqualMessage(Lib.Sun.dialDegrees(6 * 3600), 270.0, "06:00");
    Test.assertEqualMessage(Lib.Sun.dialDegrees(18 * 3600), 90.0, "18:00");
    var late = Lib.Sun.dialDegrees(23 * 3600 + 59 * 60);
    Test.assertMessage(late >= 0.0 && late < 360.0, "always 0..360");
    return true;
}

(:test)
function testSunNext(logger as Logger) as Boolean {
    var clock = System.getClockTime();
    var now = clock.hour * 3600 + clock.min * 60;
    // Make sunrise an hour ago and sunset an hour ahead, clamped to the day
    var rise = (now > 3600) ? now - 3600 : 0;
    var set = (now < 86400 - 3600) ? now + 3600 : 86399;
    if (rise < now && now < set) {
        var next = Lib.Sun.next([rise, set]);
        Test.assertMessage(next != null && !next[0] && next[1] == set, "daytime: next is sunset");
    }
    var before = Lib.Sun.next([set, 86399]);        // "sunrise" still ahead
    Test.assertMessage(before != null && before[0] && before[1] == set, "before sunrise: next is sunrise");
    if (now > 1) {
        var after = Lib.Sun.next([0, 1]);            // both passed: tomorrow's sunrise
        Test.assertMessage(after != null && after[0] && after[1] == 0, "after sunset: sunrise again");
    }
    Test.assertMessage(Lib.Sun.next([null, null]) == null, "no data: null");
    var onlySet = Lib.Sun.next([null, set]);
    Test.assertMessage(onlySet != null && !onlySet[0], "sunset only");
    return true;
}

(:test)
function testMoonPhase(logger as Logger) as Boolean {
    // Reference new moon 2000-01-06 18:14 UTC; new moon 2024-01-11 11:57 UTC;
    // full moon 2024-01-25 17:54 UTC
    Test.assertEqualMessage(Lib.Moon.phaseAt(947182440), 0.0, "reference new moon");
    var newMoon = Lib.Moon.phaseAt(1704974220);
    Test.assertMessage(newMoon < 0.02 || newMoon > 0.98, "2024-01-11 is a new moon: " + newMoon);
    var full = Lib.Moon.phaseAt(1706205240);
    Test.assertMessage((full - 0.5).abs() < 0.02, "2024-01-25 is a full moon: " + full);
    var today = Lib.Moon.phase();
    Test.assertMessage(today >= 0.0 && today < 1.0, "phase in 0..1");
    logger.debug("phase now " + today + ", lit " + Lib.Moon.illumination(today));

    Test.assertMessage(Lib.Moon.illumination(0.0) < 0.001, "new: dark");
    Test.assertMessage((Lib.Moon.illumination(0.5) - 1.0).abs() < 0.001, "full: lit");
    Test.assertMessage((Lib.Moon.illumination(0.25) - 0.5).abs() < 0.001, "quarter: half");

    Test.assertEqualMessage(Lib.Moon.name(0.0), "New moon", "new");
    Test.assertEqualMessage(Lib.Moon.name(0.97), "New moon", "almost new again");
    Test.assertEqualMessage(Lib.Moon.name(0.1), "Waxing crescent", "waxing crescent");
    Test.assertEqualMessage(Lib.Moon.name(0.24), "First quarter", "first quarter");
    Test.assertEqualMessage(Lib.Moon.name(0.35), "Waxing gibbous", "waxing gibbous");
    Test.assertEqualMessage(Lib.Moon.name(0.5), "Full moon", "full");
    Test.assertEqualMessage(Lib.Moon.name(0.65), "Waning gibbous", "waning gibbous");
    Test.assertEqualMessage(Lib.Moon.name(0.76), "Last quarter", "last quarter");
    Test.assertEqualMessage(Lib.Moon.name(0.9), "Waning crescent", "waning crescent");
    return true;
}

(:test)
function testArcs(logger as Logger) as Boolean {
    // Clockwise from 12 -> counter-clockwise from 3
    Test.assertEqualMessage(Lib.Arcs.toDc(0), 90, "12 o'clock");
    Test.assertEqualMessage(Lib.Arcs.toDc(90), 0, "3 o'clock");
    Test.assertEqualMessage(Lib.Arcs.toDc(180), 270, "6 o'clock");
    Test.assertEqualMessage(Lib.Arcs.toDc(270), 180, "9 o'clock");
    Test.assertEqualMessage(Lib.Arcs.toDc(450), 0, "wraps");
    Test.assertEqualMessage(Lib.Arcs.toDc(-90), 180, "negative wraps");

    var top = Lib.Arcs.point(100, 100, 50, 0);
    Test.assertMessage((top[0] - 100.0).abs() < 0.01 && (top[1] - 50.0).abs() < 0.01, "point at 12: " + top);
    var right = Lib.Arcs.point(100, 100, 50, 90);
    Test.assertMessage((right[0] - 150.0).abs() < 0.01 && (right[1] - 100.0).abs() < 0.01, "point at 3: " + right);
    var bottom = Lib.Arcs.point(100, 100, 50, 180);
    Test.assertMessage((bottom[0] - 100.0).abs() < 0.01 && (bottom[1] - 150.0).abs() < 0.01, "point at 6: " + bottom);
    return true;
}

(:test)
function testAodOffsets(logger as Logger) as Boolean {
    var step = 12;
    Test.assertMessage(Lib.Aod.offset(12, step)[0] == 0 && Lib.Aod.offset(12, step)[1] == 0, "minute 12 is the centre");
    // 25 distinct cells, every one within ±2 steps
    var seen = {} as Dictionary<Number, Boolean>;
    for (var m = 0; m < 60; m++) {
        var off = Lib.Aod.offset(m, step);
        Test.assertMessage(off[0].abs() <= 2 * step && off[1].abs() <= 2 * step, "offset in range at minute " + m);
        Test.assertMessage(off[0] % step == 0 && off[1] % step == 0, "whole steps");
        seen.put((off[0] / step + 2) * 5 + (off[1] / step + 2), true);
    }
    Test.assertEqualMessage(seen.size(), 25, "all 25 cells visited in an hour");
    for (var m = 0; m < 60; m++) {
        var a = Lib.Aod.offset(m, step);
        var b = Lib.Aod.offset(m + 1, step);
        Test.assertMessage(a[0] != b[0] && a[1] != b[1], "both axes move at minute " + m);
    }

    Test.assertEqualMessage(Lib.Aod.dim(0xFFB020), 0x3F2C08, "quarter brightness");
    Test.assertEqualMessage(Lib.Aod.dim(0xFFFFFF), 0x3F3F3F, "white dims to 25 %");
    Test.assertEqualMessage(Lib.Aod.dim(0x000000), 0, "black stays black");
    Test.assertMessage(Lib.Aod.required(), "fenix 8 screens need burn-in protection");
    return true;
}

(:test)
function testFmt(logger as Logger) as Boolean {
    Test.assertEqualMessage(Lib.Fmt.thousands(0), "0", "zero");
    Test.assertEqualMessage(Lib.Fmt.thousands(999), "999", "no separator");
    Test.assertEqualMessage(Lib.Fmt.thousands(1000), "1,000", "one separator");
    Test.assertEqualMessage(Lib.Fmt.thousands(8412), "8,412", "steps");
    Test.assertEqualMessage(Lib.Fmt.thousands(1234567), "1,234,567", "two separators");
    Test.assertEqualMessage(Lib.Fmt.thousands(-1500), "-1,500", "negative");

    Test.assertEqualMessage(Lib.Fmt.duration(0.5), "30m", "minutes");
    Test.assertEqualMessage(Lib.Fmt.duration(14.0), "14h", "hours");
    Test.assertEqualMessage(Lib.Fmt.duration(24.0), "1d 0h", "a day");
    Test.assertEqualMessage(Lib.Fmt.duration(148.0), "6d 4h", "days and hours");

    var is24 = System.getDeviceSettings().is24Hour;
    Test.assertEqualMessage(Lib.Fmt.clock(6 * 3600 + 52 * 60), "6:52", "morning");
    Test.assertEqualMessage(Lib.Fmt.clock(17 * 3600 + 41 * 60), is24 ? "17:41" : "5:41", "evening");
    Test.assertEqualMessage(Lib.Fmt.clock(0), is24 ? "0:00" : "12:00", "midnight");
    Test.assertEqualMessage(Lib.Fmt.clock(12 * 3600 + 5 * 60), "12:05", "noon");

    Test.assertEqualMessage(Lib.Fmt.clock24(0), "00:00", "24 h midnight");
    Test.assertEqualMessage(Lib.Fmt.clock24(7 * 3600 + 5 * 60), "07:05", "24 h keeps the leading zero");
    Test.assertEqualMessage(Lib.Fmt.clock24(17 * 3600 + 41 * 60), "17:41", "24 h evening");
    Test.assertEqualMessage(Lib.Fmt.clock24(23 * 3600 + 59 * 60 + 59), "23:59", "24 h last minute");
    Test.assertEqualMessage(Lib.Fmt.clock24(-600), "23:50", "yesterday wraps");
    var now = Time.now().value();
    var midnight = now - Lib.Fmt.localSeconds(now);
    Test.assertEqualMessage(Lib.Fmt.wallSeconds(midnight + 3 * 3600 + 60, midnight) % 3600, 60, "wall seconds keep the minutes");
    Test.assertMessage(Lib.Fmt.wallSeconds(midnight + 86400 + 7200, midnight) >= 86400, "tomorrow runs past 86400");
    Test.assertEqualMessage(Lib.Fmt.clock24(86400 + 300), "00:05", "tomorrow wraps");
    Test.assertEqualMessage(Lib.Fmt.clock(-600), is24 ? "23:50" : "11:50", "clock wraps too");

    var miles = System.getDeviceSettings().distanceUnits != System.UNIT_METRIC;
    Test.assertEqualMessage(Lib.Fmt.distanceUnit(), miles ? "mi" : "km", "distance unit");
    Test.assertEqualMessage(Lib.Fmt.distanceValue(160934), miles ? "1.0" : "1.6", "a mile");
    Test.assertEqualMessage(Lib.Fmt.distance(500000), miles ? "3.1 mi" : "5.0 km", "five kilometres");

    var metric = System.getDeviceSettings().temperatureUnits == System.UNIT_METRIC;
    Test.assertEqualMessage(Lib.Fmt.temperature(18), metric ? "18°" : "64°", "temperature");
    Test.assertEqualMessage(Lib.Fmt.temperature(-3.4), metric ? "-3°" : "26°", "temperature rounds");
    Test.assertEqualMessage(Lib.Fmt.temperatureWithUnit(18), metric ? "18°C" : "64°F", "temperature with its unit");
    Test.assertEqualMessage(Lib.Fmt.temperatureUnit(), metric ? "°C" : "°F", "temperature unit");
    Test.assertEqualMessage(Lib.Fmt.compact(8412), "8412", "four digits stay whole");
    Test.assertEqualMessage(Lib.Fmt.compact(12345), "12.3k", "five digits in thousands");
    Test.assertEqualMessage(Lib.Fmt.compact(123456), "123k", "six digits in whole thousands");
    Test.assertEqualMessage(Lib.Fmt.compact(-15000), "-15.0k", "below zero too");
    Test.assertEqualMessage(Lib.Fmt.temperatureWithUnit(-40), metric ? "-40°C" : "-40°F", "minus forty is the same in both");
    return true;
}
