import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

// The words on the glance and the app, in one place so both say the same
// thing. Glance code cannot reach the Lib barrel (its (:glance) annotation
// would then be compiled into the watch faces that link Lib, and the
// compiler warns), so the two formatters it needs live here.
(:glance)
module BatteryText {

    // Hours -> "6d 4h", "14h", "45m" (same rules as Lib.Fmt.duration)
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

    // Moment -> "Sun 2 Nov"
    function shortDate(moment as Time.Moment) as String {
        var info = Gregorian.info(moment, Time.FORMAT_MEDIUM);
        return Lang.format("$1$ $2$ $3$", [info.day_of_week, info.day, info.month]);
    }

    // "6d 4h left", or the watch's own estimate while the log fills up
    function headline(s as BatterySummary) as String {
        var hours = s.hoursLeft;
        if (hours != null) {
            return duration(hours) + " left";
        }
        var days = s.watchDays;
        if (days != null) {
            return "~" + days.format("%d") + "d left";
        }
        return s.level.toString() + "%";
    }

    // "charge by Sun 2 Nov", or what is still missing
    function chargeLine(s as BatterySummary) as String {
        var by = s.chargeBy;
        if (by != null) {
            return "charge by " + shortDate(by);
        }
        return "watch estimate, logging day 1";
    }

    // "pace -11%/day" with the heavy day when there is one
    function paceLine(s as BatterySummary, heavy as Number?, heavyHours as Float) as String {
        var pace = s.pace;
        if (pace == null) {
            return "no complete day logged yet";
        }
        var text = "pace -" + pace.format("%.0f") + "%/day";
        if (heavy != null) {
            var drain = s.drains[heavy];
            if (drain != null) {
                text += "  ·  " + dayName(s.dayStarts[heavy]) + " -" + drain.format("%.0f") + "%";
                if (heavyHours >= 0.5) {
                    text += " (" + duration(heavyHours) + " activity)";
                }
            }
        }
        return text;
    }

    function dayName(dayStart as Number) as String {
        var info = Gregorian.info(new Time.Moment(dayStart + 43200), Time.FORMAT_MEDIUM);
        return info.day_of_week.toString();
    }
}
