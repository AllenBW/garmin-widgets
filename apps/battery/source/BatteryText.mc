import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

// The words on the glance and the app, in one place so both say the same
// thing. Lib.Fmt is glance-safe, so both can use it.
(:glance)
module BatteryText {

    // "6d 4h left", or the watch's own estimate while the log fills up
    function headline(s as BatterySummary) as String {
        var hours = s.hoursLeft;
        if (hours != null) {
            return Lib.Fmt.duration(hours) + " left";
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
            return "charge by " + Lib.Fmt.shortDate(by);
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
                    text += " (" + Lib.Fmt.duration(heavyHours) + " activity)";
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
