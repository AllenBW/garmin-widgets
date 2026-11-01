import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Complications;
import Toybox.Lang;
import Toybox.Math;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.UserProfile;
import Toybox.Weather;

module Lib {

    // What a reading slot shows. The watch face editor lets each of the
    // slots hold any complication on the watch, other apps' included; the
    // Garmin ones the faces know get their own icon, number and bar, read from
    // the watch's own APIs where they are steadier than the complication, and
    // anything else shows its short label, its value as it comes and the bar
    // its declared range gives. Uses Daily, Fmt and Sun, so a
    // face links those too.
    (:slots)
    module Slots {

        typedef Reading as [String, String, Float?, String?, Number];

        const TREND_WINDOW = 3 * 3600;   // seconds of barometer history the trend looks at
        const TREND = 100.0;             // pascals over the window that make a trend: 1 hPa
        const CLIMB = 10.0;              // metres: more than this in the window, no trend

        enum Kind {
            HEART, STEPS, BATTERY, BODY, STRESS, TEMPERATURE, CALORIES, FLOORS, INTENSITY,
            ALTITUDE, PULSE_OX, BREATH, SUN, NOTIFICATIONS, RECOVERY, VO2, SLEEP, PRESSURE,
            CALENDAR, OTHER
        }

        // The kind for a complication type; OTHER for third-party ones and the
        // Garmin types there is no icon for
        function kindOf(type as Complications.Type?) as Number {
            if (type == null) {
                return OTHER;
            }
            switch (type as Complications.Type) {
                case Complications.COMPLICATION_TYPE_HEART_RATE:          return HEART;
                case Complications.COMPLICATION_TYPE_STEPS:               return STEPS;
                case Complications.COMPLICATION_TYPE_BATTERY:             return BATTERY;
                case Complications.COMPLICATION_TYPE_BODY_BATTERY:        return BODY;
                case Complications.COMPLICATION_TYPE_STRESS:              return STRESS;
                case Complications.COMPLICATION_TYPE_CURRENT_TEMPERATURE:
                case Complications.COMPLICATION_TYPE_CURRENT_WEATHER:     return TEMPERATURE;
                case Complications.COMPLICATION_TYPE_CALORIES:            return CALORIES;
                case Complications.COMPLICATION_TYPE_FLOORS_CLIMBED:      return FLOORS;
                case Complications.COMPLICATION_TYPE_INTENSITY_MINUTES:   return INTENSITY;
                case Complications.COMPLICATION_TYPE_ALTITUDE:            return ALTITUDE;
                case Complications.COMPLICATION_TYPE_PULSE_OX:            return PULSE_OX;
                case Complications.COMPLICATION_TYPE_RESPIRATION_RATE:    return BREATH;
                case Complications.COMPLICATION_TYPE_SUNRISE:
                case Complications.COMPLICATION_TYPE_SUNSET:              return SUN;
                case Complications.COMPLICATION_TYPE_NOTIFICATION_COUNT:  return NOTIFICATIONS;
                case Complications.COMPLICATION_TYPE_RECOVERY_TIME:       return RECOVERY;
                case Complications.COMPLICATION_TYPE_VO2MAX_RUN:
                case Complications.COMPLICATION_TYPE_VO2MAX_BIKE:         return VO2;
                case Complications.COMPLICATION_TYPE_SLEEP_SCORE:         return SLEEP;
                case Complications.COMPLICATION_TYPE_SEA_LEVEL_PRESSURE:  return PRESSURE;
                case Complications.COMPLICATION_TYPE_CALENDAR_EVENTS:     return CALENDAR;
            }
            return OTHER;
        }

        // What a slot shows now: [value, unit (small, after it, or ""), bulbs
        // lit 0..1 or null for none, the label in place of an icon or null,
        // which way: 1 for a sunrise and a rising barometer, -1 for a sunset
        // and a falling one, else 0]
        function read(kind as Number, id as Complications.Id) as Reading {
            switch (kind) {
                case HEART: {
                    var hr = Lib.Daily.heartRateBpm();
                    return [dashes(hr), "", heartFraction(hr), null, 0];
                }
                case STEPS: {
                    var info = ActivityMonitor.getInfo();
                    return [dashes(info.steps), "", fraction(info.steps, info.stepGoal), null, 0];
                }
                case BATTERY: {
                    var level = Lib.Daily.watchBattery();
                    return [level.toString(), "%", fraction(level, 100), null, 0];
                }
                case BODY: {
                    var body = bodyBattery(id);
                    return [dashes(body), "", fraction(body, 100), null, 0];
                }
                case STRESS: {
                    var stress = ActivityMonitor.getInfo().stressScore;
                    if (stress == null) {
                        stress = number(id);
                    }
                    return [dashes(stress), "", fraction(stress, 100), null, 0];
                }
                case TEMPERATURE:
                    return temperature();
                case CALORIES:
                    return [dashes(ActivityMonitor.getInfo().calories), "", null, null, 0];
                case FLOORS: {
                    var info = ActivityMonitor.getInfo();
                    return [dashes(info.floorsClimbed), "", fraction(info.floorsClimbed, info.floorsClimbedGoal), null, 0];
                }
                case INTENSITY: {
                    var info = ActivityMonitor.getInfo();
                    var week = info.activeMinutesWeek;
                    var total = (week != null) ? week.total : null;
                    return [dashes(total), "", fraction(total, info.activeMinutesWeekGoal), null, 0];
                }
                case ALTITUDE:
                    return altitude();
                case PULSE_OX: {
                    var spo2 = number(id);
                    return [dashes(spo2), (spo2 != null) ? "%" : "", fraction(spo2, 100), null, 0];
                }
                case BREATH: {
                    var rate = ActivityMonitor.getInfo().respirationRate;
                    return [dashes((rate != null) ? rate : number(id)), "", null, null, 0];
                }
                case SUN:
                    return sun();
                case NOTIFICATIONS:
                    return [System.getDeviceSettings().notificationCount.toString(), "", null, null, 0];
                case RECOVERY: {
                    var hours = ActivityMonitor.getInfo().timeToRecovery;
                    return [dashes(hours), (hours != null) ? "H" : "", null, null, 0];
                }
                case PRESSURE:
                    return pressure(id);
                case SLEEP: {
                    var score = number(id);
                    return [dashes(score), "", fraction(score, 100), null, 0];
                }
            }
            if (kind == VO2) {
                var vo2 = other(id, false);
                vo2[3] = "VO2";
                return vo2;
            }
            return other(id, kind == OTHER);
        }

        // The word that names a reading when it is set as text, after its
        // value ("72 BPM", "8412 STEPS"), or before it for the sun
        // ("SUNSET 19:22"); `short` gives a shorter whole word, or a
        // familiar one, for a tight spot ("81% BATT", "64 BODY"), never a
        // cryptic abbreviation. "" where the unit says it ("5280FT").
        // Other apps' readings use their label.
        function word(kind as Number, reading as Reading, short as Boolean) as String {
            var words = null;
            switch (kind) {
                case HEART:         words = ["BPM", "BPM"]; break;
                case STEPS:         words = ["STEPS", "STEPS"]; break;
                case BATTERY:       words = ["BATTERY", "BATT"]; break;
                case BODY:          words = ["BODY BATT", "BODY"]; break;
                case STRESS:        words = ["STRESS", "STRESS"]; break;
                case TEMPERATURE:   words = ["TEMP", "TEMP"]; break;
                case CALORIES:      words = ["CAL", "CAL"]; break;
                case FLOORS:        words = ["FLOORS", "FLOORS"]; break;
                case INTENSITY:     words = ["ACTIVE MIN", "MIN"]; break;
                case PULSE_OX:      words = ["SPO2", "SPO2"]; break;
                case BREATH:        words = ["BRPM", "BRPM"]; break;
                case SUN:           words = (reading[4] > 0) ? ["SUNRISE", "SUNRISE"] : ["SUNSET", "SUNSET"]; break;
                case NOTIFICATIONS: words = ["ALERTS", "ALERTS"]; break;
                case RECOVERY:      words = ["RECOVERY", "REST"]; break;
                case SLEEP:         words = ["SLEEP", "SLEEP"]; break;
                case CALENDAR:      words = ["NEXT", "NEXT"]; break;
            }
            if (words != null) {
                return words[short ? 1 : 0];
            }
            var label = reading[3];
            return (label != null) ? label : "";
        }

        // The complication a press and hold on a slot opens: the weather
        // for the temperature, else the slot's own
        function opens(kind as Number, id as Complications.Id) as Complications.Id {
            return (kind == TEMPERATURE) ? new Complications.Id(Complications.COMPLICATION_TYPE_CURRENT_WEATHER) : id;
        }

        // value / goal, capped at 1; null when either is missing
        function fraction(value as Numeric?, goal as Numeric?) as Float? {
            if (value == null || goal == null || goal <= 0) {
                return null;
            }
            var f = value.toFloat() / goal.toFloat();
            return (f < 0.0) ? 0.0 : ((f > 1.0) ? 1.0 : f);
        }

        function dashes(n as Number?) as String {
            return (n != null) ? n.toString() : "--";
        }

        // Where `value` sits between `low` and `high`, 0..1, or null
        function between(value as Numeric?, low as Numeric?, high as Numeric?) as Float? {
            if (value == null || low == null || high == null || high <= low) {
                return null;
            }
            return fraction(value - low, high - low);
        }

        // A complication's value as text, as it comes: whole numbers plain,
        // fractions to one place, text cut to six characters
        function text(value as Object?) as String {
            if (value == null) {
                return "--";
            }
            if (value instanceof Float || value instanceof Double) {
                var f = value.toFloat();
                return (f.abs() >= 100.0) ? Math.round(f).toNumber().toString() : f.format("%.1f");
            }
            var s = value.toString();
            return (s.length() > 6) ? s.substring(0, 6) as String : s;
        }

        // A label cut to four capitals ("GLU"), or null
        function label(s as String?) as String? {
            if (s == null || s.length() == 0) {
                return null;
            }
            s = s.toUpper();
            return (s.length() > 4) ? s.substring(0, 4) as String : s;
        }

        // ------------------------------------------------------------- readers

        function complication(id as Complications.Id) as Complications.Complication? {
            if (!(Toybox has :Complications)) {
                return null;
            }
            try {
                return Complications.getComplication(id);
            } catch (e) {
                return null;
            }
        }

        // The complication's value as a whole number, or null
        function number(id as Complications.Id) as Number? {
            var c = complication(id);
            var value = (c != null) ? c.value : null;
            if (value instanceof Number) {
                return value;
            }
            if (value instanceof Float || value instanceof Double || value instanceof Long) {
                return Math.round(value.toFloat()).toNumber();
            }
            return null;
        }

        // A complication shown as it comes: its value, its range as the bar,
        // and for OTHER its short label in place of an icon
        function other(id as Complications.Id, labelled as Boolean) as Reading {
            var c = complication(id);
            if (c == null) {
                return ["--", "", null, labelled ? "?" : null, 0];
            }
            var bar = null;
            var ranges = c.ranges;
            var value = c.value;
            if (ranges != null && ranges.size() >= 2 && (value instanceof Number || value instanceof Float)) {
                bar = between(value, ranges[0], ranges[ranges.size() - 1]);
            }
            var name = label(c.shortLabel);
            if (name == null) {
                name = label(c.longLabel);
            }
            var unit = c.unit;
            return [text(value), (unit instanceof String && unit.length() <= 3) ? unit : "", bar,
                    labelled ? ((name != null) ? name : "?") : null, 0];
        }

        // How far the heart rate sits from resting towards the maximum
        function heartFraction(hr as Number?) as Float? {
            if (hr == null || !(Toybox has :UserProfile)) {
                return null;
            }
            var profile = UserProfile.getProfile();
            var resting = profile.restingHeartRate;
            var zones = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_GENERIC);
            var max = (zones != null && zones.size() > 0) ? zones[zones.size() - 1] : null;
            return between(hr, (resting != null && resting > 0) ? resting : 40, max);
        }

        // The newest Body Battery sample, else the complication
        function bodyBattery(id as Complications.Id) as Number? {
            if ((Toybox has :SensorHistory) && (Toybox.SensorHistory has :getBodyBatteryHistory)) {
                var sample = SensorHistory.getBodyBatteryHistory({:period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST}).next();
                if (sample != null && sample.data != null) {
                    return (sample.data as Numeric).toNumber();
                }
            }
            return number(id);
        }

        // The temperature in the watch's unit with a degree sign; the bar is
        // where it sits between today's forecast low and high
        function temperature() as Reading {
            var conditions = (Toybox has :Weather) ? Weather.getCurrentConditions() : null;
            var now = (conditions != null) ? conditions.temperature : null;
            if (now == null) {
                return ["--", "", null, null, 0];
            }
            var today = conditions as Weather.CurrentConditions;
            return [Lib.Fmt.temperatureValue(now) + "°", "", between(now, today.lowTemperature, today.highTemperature), null, 0];
        }

        // The next sunrise or sunset; the bar is how much of the day (or the
        // night) has gone by
        function sun() as Reading {
            var times = Lib.Sun.today();
            var next = Lib.Sun.next(times);
            if (next == null) {
                return ["--:--", "", null, null, 0];
            }
            var clock = System.getClockTime();
            var now = clock.hour * 3600 + clock.min * 60;
            var rise = times[0];
            var set = times[1];
            var bar = null;
            if (rise != null && set != null) {
                if (!next[0]) {
                    bar = between(now, rise, set);                       // the day so far
                } else {
                    var length = 86400 - (set - rise);                   // the night, across midnight
                    var gone = (now >= set) ? now - set : now + 86400 - set;
                    bar = fraction(gone, length);
                }
            }
            return [Lib.Fmt.clock(next[1]), "", bar, null, next[0] ? 1 : -1];
        }

        // Altitude in feet or metres as the watch is set
        function altitude() as Reading {
            var info = Activity.getActivityInfo();
            var metres = (info != null) ? info.altitude : null;
            if (metres == null && (Toybox has :SensorHistory) && (Toybox.SensorHistory has :getElevationHistory)) {
                var sample = SensorHistory.getElevationHistory({:period => 1, :order => SensorHistory.ORDER_NEWEST_FIRST}).next();
                metres = (sample != null && sample.data != null) ? (sample.data as Numeric).toFloat() : null;
            }
            var feet = System.getDeviceSettings().elevationUnits == System.UNIT_STATUTE;
            if (metres == null) {
                return ["--", "", null, null, 0];
            }
            return [Math.round(feet ? metres * 3.28084 : metres).toNumber().toString(), feet ? "FT" : "M", null, null, 0];
        }

        // Sea-level pressure in inHg on a watch set to statute units, else hPa;
        // else whatever the complication says
        function pressure(id as Complications.Id) as Reading {
            var info = Activity.getActivityInfo();
            var pa = (info != null) ? info.meanSeaLevelPressure : null;
            if (pa == null) {
                // the complication's value, in pascals (the simulator's) or hectopascals
                var c = complication(id);
                var v = (c != null) ? c.value : null;
                if (v instanceof Number || v instanceof Float) {
                    pa = (v > 2000) ? v : v * 100;
                }
            }
            if (pa == null) {
                return other(id, false);
            }
            var trend = pressureTrend();
            if (System.getDeviceSettings().elevationUnits == System.UNIT_STATUTE) {   // the same setting as altitude
                return [(pa / 3386.39).format("%.2f"), "INHG", null, null, trend];
            }
            return [Math.round(pa / 100.0).toNumber().toString(), "HPA", null, null, trend];
        }

        // The barometer over the last three hours, newest sample against
        // oldest: 1 rising, -1 falling, 0 steady (or not known). Climbing or
        // descending moves the pressure too (about 12 Pa a metre), so the
        // trend is left out when the altitude changed in the window.
        function pressureTrend() as Number {
            if (!(Toybox has :SensorHistory) || !(Toybox.SensorHistory has :getPressureHistory)) {
                return 0;
            }
            var window = new Time.Duration(TREND_WINDOW);
            var change = ends(SensorHistory.getPressureHistory({:period => window, :order => SensorHistory.ORDER_NEWEST_FIRST}),
                              SensorHistory.getPressureHistory({:period => window, :order => SensorHistory.ORDER_OLDEST_FIRST}));
            var climb = null;
            if (change != null && (Toybox.SensorHistory has :getElevationHistory)) {
                climb = ends(SensorHistory.getElevationHistory({:period => window, :order => SensorHistory.ORDER_NEWEST_FIRST}),
                             SensorHistory.getElevationHistory({:period => window, :order => SensorHistory.ORDER_OLDEST_FIRST}));
            }
            return trend(change, climb);
        }

        // The trend from the pressure's change (Pa) and the altitude's (m)
        // over the window
        function trend(change as Float?, climb as Float?) as Number {
            if (change == null || (climb != null && climb.abs() > CLIMB)) {
                return 0;
            }
            return (change >= TREND) ? 1 : ((change <= -TREND) ? -1 : 0);
        }

        // Newest minus oldest sample, reading only from each end, or null
        function ends(newestFirst as SensorHistory.SensorHistoryIterator,
                      oldestFirst as SensorHistory.SensorHistoryIterator) as Float? {
            var newest = first(newestFirst);
            var oldest = first(oldestFirst);
            return (newest != null && oldest != null) ? newest - oldest : null;
        }

        // The first sample with data, giving up after a few empty ones
        function first(iterator as SensorHistory.SensorHistoryIterator) as Float? {
            for (var i = 0; i < 5; i++) {
                var sample = iterator.next();
                if (sample == null) {
                    return null;
                }
                var data = sample.data;
                if (data != null) {
                    return (data as Numeric).toFloat();
                }
            }
            return null;
        }
    }
}
