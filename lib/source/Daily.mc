import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;

module Lib {

    // The owner's everyday readings, shared by the Today and Strata faces:
    // heart rate, outside temperature, distance walked today, the weather's
    // rain, humidity and wind, steps, the watch's battery, alarms, the
    // date. Text comes back as "--" when the watch has nothing yet.
    (:daily)
    module Daily {

        // The live heart rate, else the newest sample the watch logged (one
        // every minute or two at rest), else null.
        function heartRateBpm() as Number? {
            var info = Activity.getActivityInfo();
            var hr = (info != null) ? info.currentHeartRate : null;
            if (hr == null && (ActivityMonitor has :getHeartRateHistory)) {
                var sample = ActivityMonitor.getHeartRateHistory(1, true).next();
                var bpm = (sample != null) ? sample.heartRate : null;
                if (bpm != null && bpm != ActivityMonitor.INVALID_HR_SAMPLE) {
                    hr = bpm;
                }
            }
            return hr;
        }

        function heartRate() as String {
            var hr = heartRateBpm();
            return (hr != null) ? hr.toString() : "--";
        }

        // The heart rate over the last `window` seconds in `bins` equal
        // slices, oldest first: the mean of the logged samples in each
        // slice, or null where there are none. The newest slice takes the
        // live reading when the log has nothing there yet.
        function heartRateTrace(bins as Number, window as Number) as Array<Number?> {
            var sums = [] as Array<Number>;
            var counts = [] as Array<Number>;
            for (var b = 0; b < bins; b++) {
                sums.add(0);
                counts.add(0);
            }
            if (ActivityMonitor has :getHeartRateHistory) {
                var now = Time.now().value();
                var iterator = ActivityMonitor.getHeartRateHistory(new Time.Duration(window), true);
                var sample = iterator.next();
                while (sample != null) {
                    var bpm = sample.heartRate;
                    var when = sample.when;
                    if (bpm != null && bpm != ActivityMonitor.INVALID_HR_SAMPLE && when != null) {
                        var ago = now - when.value();
                        if (ago >= 0 && ago < window) {
                            var b = bins - 1 - (ago * bins / window);
                            sums[b] += bpm;
                            counts[b] += 1;
                        }
                    }
                    sample = iterator.next();
                }
            }
            var trace = [] as Array<Number?>;
            for (var b = 0; b < bins; b++) {
                trace.add(counts[b] > 0 ? sums[b] / counts[b] : null);
            }
            if (trace[bins - 1] == null) {
                var info = Activity.getActivityInfo();
                var live = (info != null) ? info.currentHeartRate : null;
                if (live != null) {
                    trace[bins - 1] = live;
                }
            }
            return trace;
        }

        // The outside temperature from the phone's weather, in Celsius;
        // null until the phone has synced.
        function temperatureCelsius() as Float? {
            if (!(Toybox has :Weather)) {
                return null;
            }
            var conditions = Weather.getCurrentConditions();
            var celsius = (conditions != null) ? conditions.temperature : null;
            return (celsius != null) ? celsius.toFloat() : null;
        }

        // The outside temperature, always in Fahrenheit (the owner's choice,
        // whatever the watch's unit setting), "52°F"
        function temperature() as String {
            var celsius = temperatureCelsius();
            return (celsius != null) ? Lib.Fmt.fahrenheit(celsius) : "--";
        }

        // Distance walked today in centimetres, or null
        function distanceCm() as Number? {
            return ActivityMonitor.getInfo().distance;
        }

        // Distance walked today, "2.3"; the unit is the label
        function distance() as String {
            var cm = distanceCm();
            return (cm != null) ? Lib.Fmt.distanceValue(cm) : "--";
        }

        function distanceLabel() as String {
            return Lib.Fmt.distanceUnit().equals("km") ? "KM" : "MILES";
        }

        // The phone's weather now: chance of rain and relative humidity in
        // percent, wind in metres a second; null until the phone has synced
        function rainChance() as Number? {
            var conditions = (Toybox has :Weather) ? Weather.getCurrentConditions() : null;
            return (conditions != null) ? conditions.precipitationChance : null;
        }

        function humidity() as Number? {
            var conditions = (Toybox has :Weather) ? Weather.getCurrentConditions() : null;
            return (conditions != null) ? conditions.relativeHumidity : null;
        }

        function windSpeed() as Float? {
            var conditions = (Toybox has :Weather) ? Weather.getCurrentConditions() : null;
            var speed = (conditions != null) ? conditions.windSpeed : null;
            return (speed != null) ? speed.toFloat() : null;
        }

        // Wind in the watch's distance unit: [value, "mph" or "km/h"], or
        // ["--", unit] with no weather yet
        function wind() as [String, String] {
            var metric = Lib.Fmt.distanceUnit().equals("km");
            var unit = metric ? "km/h" : "mph";
            var speed = windSpeed();
            if (speed == null) {
                return ["--", unit];
            }
            return [Math.round(speed * (metric ? 3.6 : 2.23694)).toNumber().toString(), unit];
        }

        // Steps today, or null
        function steps() as Number? {
            return ActivityMonitor.getInfo().steps;
        }

        // The watch's own battery, 0 to 100
        function watchBattery() as Number {
            return Math.round(System.getSystemStats().battery).toNumber();
        }

        // How many alarms are set. The watch tells apps the count only,
        // never the times (EXPLORATION.md 10.1).
        function alarms() as Number {
            var settings = System.getDeviceSettings();
            return (settings has :alarmCount) ? settings.alarmCount : 0;
        }

        // "WED OCT 29"
        function date() as String {
            var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
            return Lang.format("$1$ $2$ $3$", [info.day_of_week, info.month, info.day]).toUpper();
        }
    }
}
