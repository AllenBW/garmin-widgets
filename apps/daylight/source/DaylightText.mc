import Toybox.Lang;

// The one line of words on the face, kept pure so it can be tested
module DaylightText {

    // "7h 33m of light left" during the day, "sunrise in 9h 12m" at night.
    // Times are seconds since local midnight; tomorrowRise is Unix seconds.
    // polarDay: the sun never sets today.
    function light(now as Number, rise as Number?, set as Number?, tomorrowRise as Number?,
                   dayStart as Number, located as Boolean, polarDay as Boolean) as String {
        if (rise != null && now < rise) {
            return "sunrise in " + Lib.Fmt.countdown(rise - now);
        }
        if (set != null && now < set) {
            return Lib.Fmt.countdown(set - now) + " of light left";
        }
        if (tomorrowRise != null) {
            return "sunrise in " + Lib.Fmt.countdown(tomorrowRise - (dayStart + now));
        }
        if (!located) {
            return "no location yet";
        }
        return polarDay ? "no sunset today" : "no sunrise today";
    }
}
