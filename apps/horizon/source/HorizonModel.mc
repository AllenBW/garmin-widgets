import Toybox.Lang;

// The next twelve hours, worked out from plain numbers so it can be tested.
// Times are seconds since today's local midnight; tomorrow's run past 86400.
class HorizonOutlook {
    var hourStart as Number = 0;                   // start of the current clock hour
    var rain as Array<Number> = new [12] as Array<Number>;      // chance per hour slot, -1 unknown
    var night as Array<Boolean> = new [12] as Array<Boolean>;   // slot is after sunset / before sunrise
    var hasForecast as Boolean = false;
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
    // forecast, time in seconds since midnight. rise/set: today's; tomorrowRise
    // already has 86400 added. calendar: the complication's "16:00" string.
    function build(nowSecs as Number, hours as Array<[Number, Number]>,
                   rise as Number?, set as Number?, tomorrowRise as Number?, calendar as String?) as HorizonOutlook {
        var o = new HorizonOutlook();
        o.hourStart = (nowSecs / 3600) * 3600;

        // Rain per slot
        o.hasForecast = hours.size() > 0;
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
            o.night = o.night;   // (arrays are shared references; assignment below)
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

    // "16:05", "4:05 pm", "12:00 AM" -> seconds since midnight, else null
    function parseClock(text as String?) as Number? {
        if (text == null) {
            return null;
        }
        var chars = text.toCharArray();
        var hour = -1;
        var minute = -1;
        var current = -1;
        var pm = false;
        var am = false;
        for (var i = 0; i < chars.size(); i++) {
            var c = chars[i];
            if (c >= '0' && c <= '9') {
                current = (current < 0 ? 0 : current * 10) + (c.toNumber() - '0'.toNumber());
            } else {
                if (current >= 0) {
                    if (hour < 0) {
                        hour = current;
                    } else if (minute < 0) {
                        minute = current;
                    }
                    current = -1;
                }
                if (c == 'p' || c == 'P') {
                    pm = true;
                } else if (c == 'a' || c == 'A') {
                    am = true;
                }
            }
        }
        if (current >= 0) {
            if (hour < 0) {
                hour = current;
            } else if (minute < 0) {
                minute = current;
            }
        }
        if (hour < 0) {
            return null;
        }
        if (minute < 0) {
            minute = 0;
        }
        if (pm && hour < 12) {
            hour += 12;
        } else if (am && hour == 12) {
            hour = 0;
        }
        if (hour > 23 || minute > 59) {
            return null;
        }
        return hour * 3600 + minute * 60;
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
        return "no rain in the next 12 h";
    }
}
