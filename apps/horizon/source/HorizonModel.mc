import Toybox.Lang;

// The next twelve hours, worked out from plain numbers so it can be tested.
// Times are seconds since today's local midnight; tomorrow's run past 86400.
class HorizonOutlook {
    var hourStart as Number = 0;                   // start of the current clock hour
    var rain as Array<Number> = new [12] as Array<Number>;      // chance per hour slot, -1 unknown
    var night as Array<Boolean> = new [12] as Array<Boolean>;   // slot is after sunset / before sunrise
    var hasForecast as Boolean = false;            // at least one slot has a chance of rain
    var knownTo as Number = 0;                     // slots known in a run from the first known one
    var rainFrom as Number? = null;                // first slot at or over the threshold
    var sunSecs as Number? = null;                 // the next sunrise or sunset, when within 12 h
    var sunIsRise as Boolean = true;
    var calendarSecs as Number? = null;            // the next calendar event, when within 12 h

    function initialize() {
        for (var i = 0; i < 12; i++) {
            rain[i] = -1;
            night[i] = false;
        }
    }
}

module HorizonModel {

    const RAIN_CHANCE = 40;      // percent: worth a word
    const WINDOW = 12 * 3600;

    // nowSecs: seconds since midnight. hours: [time, chance] pairs from the
    // forecast and the conditions now, time in seconds since midnight; each
    // slot takes the highest. rise/set: today's; tomorrowRise already has
    // 86400 added. calendar: the complication's "16:00" string.
    function build(nowSecs as Number, hours as Array<[Number, Number]>,
                   rise as Number?, set as Number?, tomorrowRise as Number?, calendar as String?) as HorizonOutlook {
        var o = new HorizonOutlook();
        o.hourStart = (nowSecs / 3600) * 3600;

        // Rain per slot
        for (var i = 0; i < hours.size(); i++) {
            var t = hours[i][0];
            if (t < o.hourStart) {
                continue;
            }
            var slot = (t - o.hourStart) / 3600;
            if (slot < 12 && hours[i][1] > o.rain[slot]) {
                o.rain[slot] = hours[i][1];
            }
        }
        for (var k = 0; k < 12; k++) {
            if (o.rain[k] >= RAIN_CHANCE) {
                o.rainFrom = k;
                break;
            }
        }
        // How far the forecast reaches: an old forecast, or one that ends
        // early, must not read as dry hours
        for (var k = 0; k < 12; k++) {
            if (o.rain[k] >= 0) {
                o.hasForecast = true;
                o.knownTo = k + 1;
            } else if (o.hasForecast) {
                break;
            }
        }

        // Night per slot, from the midpoint of each hour
        for (var k = 0; k < 12; k++) {
            var m = o.hourStart + k * 3600 + 1800;
            var day = false;
            if (rise != null && set != null) {
                day = (m >= rise && m < set) || (m >= rise + 86400 && m < set + 86400);
                if (tomorrowRise != null && m >= 86400) {
                    day = (m >= tomorrowRise && m < set + 86400);
                }
            }
            o.night[k] = !day;
        }

        // The next sun event, when it falls inside the window
        var next = null;
        var isRise = true;
        if (rise != null && nowSecs < rise) {
            next = rise;
        } else if (set != null && nowSecs < set) {
            next = set;
            isRise = false;
        } else if (tomorrowRise != null) {
            next = tomorrowRise;
        }
        if (next != null && next - nowSecs <= WINDOW) {
            o.sunSecs = next;
            o.sunIsRise = isRise;
        }

        // The next calendar event
        var cal = parseClock(calendar);
        if (cal != null) {
            if (cal < nowSecs - 600) {
                cal += 86400;   // already past today: it is tomorrow's
            }
            if (cal - nowSecs <= WINDOW) {
                o.calendarSecs = cal;
            }
        }
        return o;
    }

    // The first time of day in the text: "16:05", "4:05 pm", "12:00 AM",
    // "9 am" -> seconds since midnight, else null. A bare number ("11/3",
    // "Room 2") is not a time.
    function parseClock(text as String?) as Number? {
        if (text == null) {
            return null;
        }
        var chars = text.toCharArray();
        var n = chars.size();
        var i = 0;
        while (i < n) {
            if (!digit(chars[i]) || (i > 0 && digit(chars[i - 1]))) {
                i++;
                continue;
            }
            // One or two digits for the hour
            var j = i;
            var hour = 0;
            while (j < n && digit(chars[j]) && j - i < 3) {
                hour = hour * 10 + (chars[j].toNumber() - '0'.toNumber());
                j++;
            }
            if (j - i > 2) {
                i = j;
                continue;
            }
            // ":MM", exactly two digits
            var minute = -1;
            if (j + 2 < n && chars[j] == ':' && digit(chars[j + 1]) && digit(chars[j + 2])
                    && (j + 3 >= n || !digit(chars[j + 3]))) {
                minute = (chars[j + 1].toNumber() - '0'.toNumber()) * 10 + (chars[j + 2].toNumber() - '0'.toNumber());
                j += 3;
            }
            // An optional "am" / "pm" after a space
            var k = j;
            while (k < n && chars[k] == ' ') {
                k++;
            }
            var half = 0;   // 1 am, 2 pm
            if (k + 1 < n && (chars[k + 1] == 'm' || chars[k + 1] == 'M')) {
                if (chars[k] == 'a' || chars[k] == 'A') {
                    half = 1;
                } else if (chars[k] == 'p' || chars[k] == 'P') {
                    half = 2;
                }
            }
            if (minute < 0 && half == 0) {
                i = j;
                continue;
            }
            if (minute < 0) {
                minute = 0;
            }
            if (half != 0 && (hour < 1 || hour > 12)) {
                return null;
            }
            if (half == 2 && hour < 12) {
                hour += 12;
            } else if (half == 1 && hour == 12) {
                hour = 0;
            }
            if (hour > 23 || minute > 59) {
                return null;
            }
            return hour * 3600 + minute * 60;
        }
        return null;
    }

    function digit(c as Char) as Boolean {
        return c >= '0' && c <= '9';
    }

    // Where a time of day sits on a 12-hour dial: degrees clockwise from 12
    function dialDegrees(secs as Number) as Float {
        return (secs % 43200) * 360.0 / 43200.0;
    }

    // The one line about rain
    function rainText(o as HorizonOutlook) as String {
        var from = o.rainFrom;
        if (from != null) {
            var chance = o.rain[from].toString() + "%";
            if (from == 0) {
                return "rain now, " + chance;
            }
            return "rain from " + Lib.Fmt.clock(o.hourStart + from * 3600) + ", " + chance;
        }
        if (!o.hasForecast) {
            return "no forecast";
        }
        if (o.knownTo < 12) {
            return "no rain until " + Lib.Fmt.clock(o.hourStart + o.knownTo * 3600);
        }
        return "no rain in the next 12 h";
    }
}
