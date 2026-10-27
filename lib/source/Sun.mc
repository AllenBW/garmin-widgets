import Toybox.Activity;
import Toybox.Complications;
import Toybox.Lang;
import Toybox.Position;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;

module Lib {

    // Today's sunrise and sunset. The watch's own figures come from the
    // sunrise/sunset complications (the app needs the ComplicationSubscriber
    // permission); the Weather module with the last known location is the
    // fallback. Times are seconds since local midnight, like the complications.
    (:sun)
    module Sun {

        // [sunrise, sunset]; either can be null when the watch has no data.
        function today() as [Number?, Number?] {
            var rise = fromComplication(Complications.COMPLICATION_TYPE_SUNRISE);
            var set = fromComplication(Complications.COMPLICATION_TYPE_SUNSET);
            if (rise == null || set == null) {
                var location = lastLocation();
                if (location != null) {
                    var now = Time.now();
                    if (rise == null) {
                        rise = secondsOf(Weather.getSunrise(location, now));
                    }
                    if (set == null) {
                        set = secondsOf(Weather.getSunset(location, now));
                    }
                }
            }
            return [rise, set];
        }

        // The next event from now: [isSunrise, secondsSinceMidnight], or null.
        // After sunset it points at sunrise again (tomorrow's is within a
        // minute or two of today's).
        function next(times as [Number?, Number?]) as [Boolean, Number]? {
            var clock = System.getClockTime();
            var now = clock.hour * 3600 + clock.min * 60;
            var rise = times[0];
            var set = times[1];
            if (rise != null && now < rise) {
                return [true, rise];
            }
            if (set != null && now < set) {
                return [false, set];
            }
            if (rise != null) {
                return [true, rise];
            }
            return null;
        }

        function fromComplication(type as Complications.Type) as Number? {
            if (!(Toybox has :Complications)) {
                return null;
            }
            try {
                var complication = Complications.getComplication(new Complications.Id(type));
                var value = complication.value;
                return (value instanceof Number) ? value : null;
            } catch (e) {
                return null;
            }
        }

        function lastLocation() as Position.Location? {
            if (Toybox has :Weather) {
                var conditions = Weather.getCurrentConditions();
                var position = (conditions != null) ? conditions.observationLocationPosition : null;
                if (position != null) {
                    return position;
                }
            }
            var info = Activity.getActivityInfo();
            return (info != null) ? info.currentLocation : null;
        }

        function secondsOf(moment as Time.Moment?) as Number? {
            if (moment == null) {
                return null;
            }
            var local = Gregorian.info(moment, Time.FORMAT_SHORT);
            return local.hour * 3600 + local.min * 60;
        }
    }
}
