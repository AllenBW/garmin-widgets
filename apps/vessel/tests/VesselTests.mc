import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Run No Evil tests for Vessel and the Lib modules the three faces share
// (Slots, Config, Ink): scripts/test.sh vessel [device].

(:test)
function testSlotArithmetic(logger as Logger) as Boolean {
    Test.assertMessage(Lib.Slots.fraction(null, 100) == null, "no value");
    Test.assertMessage(Lib.Slots.fraction(50, null) == null, "no goal");
    Test.assertMessage(Lib.Slots.fraction(50, 0) == null, "a zero goal");
    Test.assertEqualMessage(Lib.Slots.fraction(2500, 10000) as Float, 0.25, "a quarter");
    Test.assertEqualMessage(Lib.Slots.fraction(12000, 10000) as Float, 1.0, "capped at the goal");
    Test.assertEqualMessage(Lib.Slots.fraction(-5, 100) as Float, 0.0, "never below none");
    Test.assertEqualMessage(Lib.Slots.between(15, 10, 20) as Float, 0.5, "half way between low and high");
    Test.assertMessage(Lib.Slots.between(15, 20, 10) == null, "a range upside down");
    Test.assertEqualMessage(Lib.Slots.between(25, 10, 20) as Float, 1.0, "over the high");
    Test.assertEqualMessage(Lib.Slots.text(null), "--", "nothing yet");
    Test.assertEqualMessage(Lib.Slots.text(112), "112", "a whole number");
    Test.assertEqualMessage(Lib.Slots.text(5.26), "5.3", "a fraction to one place");
    Test.assertEqualMessage(Lib.Slots.text(1013.4), "1013", "a big fraction whole");
    Test.assertEqualMessage(Lib.Slots.text("Mostly cloudy"), "Mostly", "long text cut to six");
    Test.assertEqualMessage(Lib.Slots.label("glucose") as String, "GLUC", "a label in four capitals");
    Test.assertMessage(Lib.Slots.label("") == null, "no label");
    return true;
}

(:test)
function testKinds(logger as Logger) as Boolean {
    Test.assertEqualMessage(Lib.Slots.kindOf(Complications.COMPLICATION_TYPE_HEART_RATE), Lib.Slots.HEART, "heart rate");
    Test.assertEqualMessage(Lib.Slots.kindOf(Complications.COMPLICATION_TYPE_CURRENT_WEATHER), Lib.Slots.TEMPERATURE, "weather shows the temperature");
    Test.assertEqualMessage(Lib.Slots.kindOf(Complications.COMPLICATION_TYPE_SUNSET), Lib.Slots.SUN, "sunset is the sun");
    Test.assertEqualMessage(Lib.Slots.kindOf(Complications.COMPLICATION_TYPE_VO2MAX_BIKE), Lib.Slots.VO2, "either VO2max");
    Test.assertEqualMessage(Lib.Slots.kindOf(Complications.COMPLICATION_TYPE_INVALID), Lib.Slots.OTHER, "another app's");
    Test.assertEqualMessage(Lib.Slots.kindOf(null), Lib.Slots.OTHER, "nothing");
    // Every kind reads without throwing, whatever the simulator has
    var types = [Complications.COMPLICATION_TYPE_HEART_RATE, Complications.COMPLICATION_TYPE_STEPS,
                 Complications.COMPLICATION_TYPE_BATTERY, Complications.COMPLICATION_TYPE_BODY_BATTERY,
                 Complications.COMPLICATION_TYPE_CURRENT_TEMPERATURE, Complications.COMPLICATION_TYPE_STRESS,
                 Complications.COMPLICATION_TYPE_CALORIES, Complications.COMPLICATION_TYPE_FLOORS_CLIMBED,
                 Complications.COMPLICATION_TYPE_INTENSITY_MINUTES, Complications.COMPLICATION_TYPE_ALTITUDE,
                 Complications.COMPLICATION_TYPE_PULSE_OX, Complications.COMPLICATION_TYPE_RESPIRATION_RATE,
                 Complications.COMPLICATION_TYPE_SUNRISE, Complications.COMPLICATION_TYPE_NOTIFICATION_COUNT,
                 Complications.COMPLICATION_TYPE_RECOVERY_TIME, Complications.COMPLICATION_TYPE_VO2MAX_RUN,
                 Complications.COMPLICATION_TYPE_SLEEP_SCORE, Complications.COMPLICATION_TYPE_SEA_LEVEL_PRESSURE,
                 Complications.COMPLICATION_TYPE_CALENDAR_EVENTS, Complications.COMPLICATION_TYPE_FORECAST_WEATHER_1DAY]
                as Array<Complications.Type>;
    for (var i = 0; i < types.size(); i++) {
        var kind = Lib.Slots.kindOf(types[i]);
        var r = Lib.Slots.read(kind, new Complications.Id(types[i]));
        var bulbs = r[2];
        Test.assertMessage(r[0].length() > 0, "a value or dashes");
        Test.assertMessage(bulbs == null || (bulbs >= 0.0 && bulbs <= 1.0), "a fill in range");
        if (kind == Lib.Slots.PRESSURE && !r[0].equals("--")) {
            Test.assertMessage(r[1].equals("HPA") || r[1].equals("INHG"), "pressure in hPa or inHg, never raw pascals");
        }
        logger.debug(r[0] + r[1] + " " + Lib.Slots.word(kind, r, false) + " / " + Lib.Slots.word(kind, r, true));
        Test.assertMessage(Lib.Slots.word(kind, r, true).length() <= Lib.Slots.word(kind, r, false).length(), "a short word is no longer");
    }
    Test.assertEqualMessage(Lib.Slots.word(Lib.Slots.HEART, ["72", "", null, null, 0], false), "BPM", "heart rate's word");
    Test.assertEqualMessage(Lib.Slots.word(Lib.Slots.SUN, ["7:12", "", null, null, 1], false), "SUNRISE", "a sunrise");
    Test.assertEqualMessage(Lib.Slots.word(Lib.Slots.SUN, ["19:22", "", null, null, 0], true), "SUNSET", "a sunset: a whole word even when short");
    Test.assertEqualMessage(Lib.Slots.word(Lib.Slots.BATTERY, ["81", "%", null, null, 0], true), "BATT", "the battery, short");
    Test.assertEqualMessage(Lib.Slots.word(Lib.Slots.ALTITUDE, ["5280", "FT", null, null, 0], false), "", "the unit says it");
    Test.assertEqualMessage(Lib.Slots.word(Lib.Slots.OTHER, ["112", "", null, "GLU", 0], true), "GLU", "another app's label");
    return true;
}

(:test)
function testBarometerAndWeather(logger as Logger) as Boolean {
    Test.assertEqualMessage(Lib.Slots.trend(null, null), 0, "no history, no trend");
    Test.assertEqualMessage(Lib.Slots.trend(150.0, 2.0), 1, "up 1.5 hPa standing still: rising");
    Test.assertEqualMessage(Lib.Slots.trend(-120.0, null), -1, "down 1.2 hPa: falling");
    Test.assertEqualMessage(Lib.Slots.trend(60.0, 0.0), 0, "under 1 hPa: steady");
    Test.assertEqualMessage(Lib.Slots.trend(-300.0, 25.0), 0, "a climb moves the pressure: no trend");
    var trend = Lib.Slots.pressureTrend();
    Test.assertMessage(trend >= -1 && trend <= 1, "the watch's own trend reads");
    var temp = new Complications.Id(Complications.COMPLICATION_TYPE_CURRENT_TEMPERATURE);
    Test.assertEqualMessage(Lib.Slots.opens(Lib.Slots.TEMPERATURE, temp).getType(), Complications.COMPLICATION_TYPE_CURRENT_WEATHER,
                            "a hold on the temperature opens the weather");
    var steps = new Complications.Id(Complications.COMPLICATION_TYPE_STEPS);
    Test.assertEqualMessage(Lib.Slots.opens(Lib.Slots.STEPS, steps).getType(), Complications.COMPLICATION_TYPE_STEPS, "the rest open their own");
    // the arrow every way, level and round a rim
    var dc = (Graphics.createBufferedBitmap({:width => 60, :height => 60}).get() as Graphics.BufferedBitmap).getDc();
    for (var way = -1; way <= 1; way++) {
        Lib.Icons.draw(dc, Lib.Slots.PRESSURE, 30.0, 30.0, 18.0, 0xFFFFFF, false, way, 80);
        Lib.Icons.trend(dc, 30.0, 30.0, 18.0, way, 0.0, 1.0, 1.0, 0.0);
    }
    return true;
}

(:test)
function testColorsAndInk(logger as Logger) as Boolean {
    Test.assertEqualMessage(Lib.Config.lift(0x000080), 0x9393FF, "navy lifted, still blue");
    Test.assertEqualMessage(Lib.Config.lift(0x000000), 0x939393, "black lifted to a grey that reads");
    Test.assertEqualMessage(Lib.Config.lift(0xFF0000), 0xFF6F6F, "pure red lifted to hold its own beside Bone");
    Test.assertEqualMessage(Lib.Config.lift(0xFF5A36), 0xFF5A36, "Flame left as it is");
    Test.assertEqualMessage(Lib.Config.lift(0xFFB020), 0xFFB020, "Amber left as it is");
    Test.assertEqualMessage(Lib.Config.scale(0xFFFFFF, 0.5), 0x7F7F7F, "half brightness");
    // Ink: a "1" in Roboto Condensed carries far more space on its right than a "0"
    var em = Lib.Ink.em(Lib.Ink.CONDENSED_BOLD, 100.0);
    Test.assertMessage(em > 135.0 && em < 140.0, "digits 100 px tall need an em of about 137 px");
    Test.assertMessage(Lib.Ink.right(Lib.Ink.CONDENSED_BOLD, "21", em) > 3 * Lib.Ink.right(Lib.Ink.CONDENSED_BOLD, "20", em),
                       "the 1's wide right bearing");
    Test.assertEqualMessage(Lib.Ink.left(Lib.Ink.CONDENSED_BOLD, "", em), 0.0, "no text, no bearing");
    Test.assertEqualMessage(Lib.Ink.height(Lib.Ink.BIONIC_BOLD, Lib.Ink.em(Lib.Ink.BIONIC_BOLD, 120.0)), 120.0,
                            "the height an em was made for");
    return true;
}

(:test)
function testVesselDrawsEveryMode(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();

    var view = new VesselView();
    view.onLayout(dc);

    // Whatever the simulator provides
    var started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("awake: " + (System.getTimer() - started) + " ms");

    // Nothing yet; full and empty glasses; labels and long values; a one-digit hour; night
    var empty = [["--", "", null, null, 0], ["--", "", null, null, 0], ["--", "", null, null, 0]]
                as Array<Lib.Slots.Reading>;
    view.setState("00", "00", empty, 0, false, false);
    view.onUpdate(dc);
    var full = [["100", "", 1.0, null, 0], ["0", "", 0.0, null, 0], ["81", "%", 0.81, null, 0]]
               as Array<Lib.Slots.Reading>;
    view.setState("23", "59", full, 2, false, false);
    view.onUpdate(dc);
    var odd = [["112", "", 0.45, "GLU", 0], ["1013", "HPA", null, null, 0], ["Mostly", "", null, "?", 0]]
              as Array<Lib.Slots.Reading>;
    view.setState("8", "05", odd, 1, true, false);
    view.onUpdate(dc);

    // Press targets: the glasses and the foot open their readings, the date the calendar
    var day = [["64", "", 0.64, null, 0], ["8412", "", 0.84, null, 0], ["81", "%", 0.81, null, 0]]
              as Array<Lib.Slots.Reading>;
    view.setState("14", "38", day, 1, false, false);
    view.onUpdate(dc);
    Test.assertEqualMessage(view.slotAt((w * 0.50).toNumber(), (h * 0.33).toNumber()) as Number, 1, "the hours' glass");
    Test.assertEqualMessage(view.slotAt((w * 0.50).toNumber(), (h * 0.67).toNumber()) as Number, 2, "the minutes' glass");
    Test.assertEqualMessage(view.slotAt((w * 0.43).toNumber(), (h * 0.870).toNumber()) as Number, 3, "the foot");
    // the date is centred on the glasses' axis (VesselView.AXIS, DATE_Y)
    Test.assertMessage(view.slotAt((w * 0.43).toNumber(), (h * 0.112).toNumber()) == null, "the date is no slot");
    var id = view.targetAt((w * 0.43).toNumber(), (h * 0.112).toNumber());
    Test.assertMessage(id != null && id.getType() == Complications.COMPLICATION_TYPE_CALENDAR_EVENTS, "the date opens the calendar");
    id = view.targetAt((w * 0.50).toNumber(), (h * 0.33).toNumber());
    Test.assertMessage(id != null && id.getType() == Complications.COMPLICATION_TYPE_CURRENT_WEATHER, "the weather by default");

    // Standby, then the bedside clock with and without an alarm
    view.setAwake(false);
    started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("standby: " + (System.getTimer() - started) + " ms");
    Test.assertMessage(view.slotAt((w * 0.50).toNumber(), (h * 0.33).toNumber()) == null, "no targets in standby");
    view.setState("23", "59", odd, 1, true, true);
    view.onUpdate(dc);
    view.setState("3", "10", full, 0, false, true);
    view.onUpdate(dc);
    view.setAwake(true);
    view.onUpdate(dc);

    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}

(:test)
function testPhoneSettings(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();

    // Changed in the phone app last: its readings and style win
    Application.Properties.setValue("Reading1", Complications.COMPLICATION_TYPE_STRESS as Number);
    Application.Properties.setValue("Style", 1);
    Application.Properties.setValue("Accent", 99);   // out of range: Amber
    Lib.Config.changedOnPhone();
    var s = Lib.Config.read(3, [Complications.COMPLICATION_TYPE_CURRENT_WEATHER, Complications.COMPLICATION_TYPE_HEART_RATE,
                                Complications.COMPLICATION_TYPE_SUNRISE] as Array<Complications.Type>);
    var view = new VesselView();
    view.onLayout(dc);
    view.onUpdate(dc);
    var id = view.targetAt((w * 0.50).toNumber(), (h * 0.33).toNumber());
    var phone = id != null && id.getType() == Complications.COMPLICATION_TYPE_STRESS;
    id = view.targetAt((w * 0.50).toNumber(), (h * 0.67).toNumber());
    var kept = id != null && id.getType() == Complications.COMPLICATION_TYPE_HEART_RATE;

    Application.Properties.setValue("Reading1", Complications.COMPLICATION_TYPE_CURRENT_WEATHER as Number);
    Application.Properties.setValue("Style", 0);
    Application.Properties.setValue("Accent", 0);
    Application.Storage.deleteValue(Lib.Config.SOURCE);
    Test.assertEqualMessage(s[0], 1, "the phone's typeface");
    Test.assertEqualMessage(s[1], 0xFFB020, "an accent out of range is Amber");
    Test.assertMessage(s[4], "the bedside clock on by default");
    Test.assertMessage(phone, "the phone app's reading in the hours' glass");
    Test.assertMessage(kept, "the other slots at their defaults");
    var foot = s[3][2];
    Test.assertEqualMessage(foot.getType(), Complications.COMPLICATION_TYPE_SUNRISE, "the foot: the next sunrise or sunset");
    return true;
}
