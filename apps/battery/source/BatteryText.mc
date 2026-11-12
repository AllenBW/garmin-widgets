import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

// The words on the glance and the app, in one place so both say the same
// thing. Lib.Fmt is glance-safe, so both can use it.
(:glance)
module BatteryText {

    // "CHARGING 64%" on the charger, else `idle`
    function title(s as BatterySummary, idle as String) as String {
        return s.charging ? "CHARGING " + s.level.toString() + "%" : idle;
    }

    // "6d 4h left", or the watch's own estimate while the log fills up; on
    // the charger "42m to full"
    function headline(s as BatterySummary) as String {
        if (s.charging) {
            if (s.full) {
                return "Full";
            }
            var toFull = s.toFull;
            if (toFull != null) {
                return Lib.Fmt.countdown((toFull < 60) ? 60 : toFull) + " to full";
            }
            return "Charging";
        }
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

    // "charge by Sun 2 Nov", or what is still missing; on the charger
    // "full at 14:32"
    function chargeLine(s as BatterySummary) as String {
        if (s.charging) {
            var fullAt = s.fullAt;
            if (s.full) {
                return lastsLine(s);
            }
            if (fullAt != null) {
                return "full at " + Lib.Fmt.clockAt(fullAt);
            }
            return "timing the charge";
        }
        var by = s.chargeBy;
        if (by != null) {
            return "charge by " + Lib.Fmt.shortDate(by);
        }
        return "watch estimate, logging day 1";
    }

    // "lasts 5d 19h": what the charge so far is good for at the recent pace
    function lastsLine(s as BatterySummary) as String {
        var hours = s.hoursLeft;
        return (hours != null) ? "lasts " + Lib.Fmt.duration(hours) : "";
    }

    // "+82% an hour": the charger's speed at this level
    function speedLine(s as BatterySummary) as String {
        var perHour = s.perHour;
        return (perHour != null) ? "+" + perHour.format("%.0f") + "% an hour" : "";
    }

    // "pace -11%/day"
    function paceLine(s as BatterySummary) as String {
        var pace = s.pace;
        if (pace == null) {
            return "no full day yet";
        }
        return "pace -" + pace.format("%.0f") + "%/day";
    }

    // "Wed -19% · 2h activity": the heavy day, when there is one
    function heavyLine(s as BatterySummary, heavy as Number?, heavyHours as Float) as String {
        var drain = (heavy != null) ? s.drains[heavy] : null;
        if (heavy == null || drain == null) {
            return "";
        }
        var text = dayName(s.dayStarts[heavy]) + " -" + drain.format("%.0f") + "%";
        if (heavyHours >= 0.5) {
            text += " · " + Lib.Fmt.duration(heavyHours) + " activity";
        }
        return text;
    }

    function dayName(dayStart as Number) as String {
        var info = Gregorian.info(new Time.Moment(dayStart + 43200), Time.FORMAT_MEDIUM);
        return info.day_of_week.toString();
    }
}
