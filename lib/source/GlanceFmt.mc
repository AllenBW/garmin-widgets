import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

module Lib {

    // Formatting for glances. Lib.Fmt is foreground-only; this module carries
    // the (:glance) annotation, so only apps with glances link it (a watch
    // face that linked it would get a compiler warning). It repeats the two
    // Fmt functions glances need, so keep both in step.
    (:glancefmt, :glance)
    module GlanceFmt {

        // Hours -> "6d 4h", "14h", "45m" (same as Fmt.duration)
        function duration(hours as Float) as String {
            if (hours < 1.0) {
                return (hours * 60).toNumber().toString() + "m";
            }
            var whole = hours.toNumber();
            if (whole < 24) {
                return whole.toString() + "h";
            }
            return (whole / 24).toString() + "d " + (whole % 24).toString() + "h";
        }

        // Seconds -> "6h 48m", "48m", "1d 2h"; "now" when none are left
        function countdown(seconds as Number) as String {
            if (seconds < 60) {
                return "now";
            }
            var minutes = seconds / 60;
            if (minutes < 60) {
                return minutes.toString() + "m";
            }
            var hours = minutes / 60;
            if (hours < 24) {
                return hours.toString() + "h " + (minutes % 60).format("%02d") + "m";
            }
            return (hours / 24).toString() + "d " + (hours % 24).toString() + "h";
        }

        // Seconds since local midnight -> "6:52" or "17:41" (same as Fmt.clock)
        function clock(secondsSinceMidnight as Number) as String {
            var hour = (secondsSinceMidnight / 3600) % 24;
            var min = (secondsSinceMidnight / 60) % 60;
            if (!System.getDeviceSettings().is24Hour) {
                hour = hour % 12;
                if (hour == 0) {
                    hour = 12;
                }
            }
            return Lang.format("$1$:$2$", [hour.format("%d"), min.format("%02d")]);
        }

        // Unix seconds -> "17:41" in local time
        function clockAt(unix as Number) as String {
            return clock(localSeconds(unix));
        }

        // Unix seconds -> seconds since local midnight
        function localSeconds(unix as Number) as Number {
            var info = Gregorian.info(new Time.Moment(unix), Time.FORMAT_SHORT);
            return info.hour * 3600 + info.min * 60 + info.sec;
        }

        // Moment -> "Sun 2 Nov"
        function shortDate(moment as Time.Moment) as String {
            var info = Gregorian.info(moment, Time.FORMAT_MEDIUM);
            return Lang.format("$1$ $2$ $3$", [info.day_of_week, info.day, info.month]);
        }
    }
}
