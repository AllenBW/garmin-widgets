import Toybox.Lang;

// What the weather means for the bees, one hour at a time
enum {
    BEES_UNKNOWN,   // no forecast for this hour
    BEES_NIGHT,     // the sun is down
    BEES_RAIN,      // rain likely, or a wet condition
    BEES_WIND,      // too windy to fly
    BEES_COLD,      // too cold to fly
    BEES_CLEANSE,   // only cleansing flights: a sunny winter day, 50 to 54 °F
    BEES_FLY,       // the foragers are out
    BEES_OPEN       // flying, and a good hour to open the hive
}

// The weather for one hour (or now), in the units the watch gives:
// degrees Celsius, metres per second, percent, a Weather.CONDITION_* value
class ForageHour {
    var secs as Number;         // seconds since today's local midnight; tomorrow runs past 86400
    var celsius as Numeric?;
    var rain as Number?;
    var wind as Numeric?;
    var cloud as Number?;
    var condition as Number?;

    function initialize(secs as Number, celsius as Numeric?, rain as Number?, wind as Numeric?,
                        cloud as Number?, condition as Number?) {
        self.secs = secs;
        self.celsius = celsius;
        self.rain = rain;
        self.wind = wind;
        self.cloud = cloud;
        self.condition = condition;
    }
}

// The next twelve hours, from the current clock hour
class ForageOutlook {
    var hourStart as Number = 0;
    var kinds as Array<Number> = new [12] as Array<Number>;
    var now as Number = BEES_UNKNOWN;       // the verdict, from the current conditions
    var windowKnown as Boolean = false;     // every daylight hour from 10 to 16 in view has weather
    var openFrom as Number? = null;   // the first run of good hours to open the hive, as slots
    var openTo as Number? = null;

    function initialize() {
        for (var i = 0; i < 12; i++) {
            kinds[i] = BEES_UNKNOWN;
        }
    }
}

// Worked out from plain numbers so the tests can feed it a synthetic day.
// The thresholds are beekeepers' rules of thumb (DESIGNS.md #15).
module ForageModel {

    const FLY_C = 12.8;        // 55 °F
    const CLEANSE_C = 10.0;    // 50 °F
    const OPEN_C = 18.3;       // 65 °F
    const OPEN_MAX_C = 35.0;   // 95 °F: too hot to open, the comb softens and the bees are fanning
    const WIND_FLY = 8.9;      // 20 mph, in m/s
    const WIND_OPEN = 4.5;     // 10 mph
    const RAIN_FLY = 40;       // percent
    const RAIN_OPEN = 20;
    const CLOUD_OPEN = 70;
    const CLOUD_CLEANSE = 50;
    const OPEN_FROM = 10;      // the hive is opened between 10:00 and 16:00
    const OPEN_UNTIL = 16;

    // What one hour means for the bees. day: the sun is up. hour: the clock
    // hour, 0 to 23. winter: November to March, when a sunny 50 °F day means
    // cleansing flights rather than simply too cold.
    function kind(w as ForageHour, day as Boolean, hour as Number, winter as Boolean) as Number {
        var celsius = w.celsius;
        if (celsius == null) {
            return BEES_UNKNOWN;
        }
        var rain = (w.rain != null) ? w.rain as Number : 0;
        var wind = (w.wind != null) ? w.wind as Numeric : 0;
        var cloud = w.cloud;
        var condition = w.condition;
        if (rain >= RAIN_FLY || wet(condition)) {
            return BEES_RAIN;
        }
        if (!day) {
            return BEES_NIGHT;
        }
        if (wind >= WIND_FLY) {
            return BEES_WIND;
        }
        if (celsius >= FLY_C) {
            var bright = (cloud != null && cloud < CLOUD_OPEN) || clear(condition);
            if (hour >= OPEN_FROM && hour < OPEN_UNTIL && celsius >= OPEN_C && celsius < OPEN_MAX_C
                    && rain < RAIN_OPEN && wind < WIND_OPEN && bright) {
                return BEES_OPEN;
            }
            return BEES_FLY;
        }
        if (winter && celsius >= CLEANSE_C && ((cloud != null && cloud < CLOUD_CLEANSE) || clear(condition))) {
            return BEES_CLEANSE;
        }
        return BEES_COLD;
    }

    // nowSecs: seconds since midnight. current: the conditions now, or null
    // when there are none or they are stale; they decide the verdict and the
    // first cell, so the two always agree. hours: the forecast, the first
    // entry for an hour winning. rise, set: today's; tomorrowRise past 86400.
    function build(nowSecs as Number, current as ForageHour?, hours as Array<ForageHour>,
                   rise as Number?, set as Number?, tomorrowRise as Number?, winter as Boolean) as ForageOutlook {
        var o = new ForageOutlook();
        o.hourStart = (nowSecs / 3600) * 3600;
        if (current != null) {
            o.now = kind(current, isDay(nowSecs, rise, set, tomorrowRise), nowSecs / 3600 % 24, winter);
            o.kinds[0] = o.now;
        }
        for (var i = 0; i < hours.size(); i++) {
            var h = hours[i];
            if (h.secs < o.hourStart) {
                continue;
            }
            var slot = (h.secs - o.hourStart) / 3600;
            if (slot >= 12 || o.kinds[slot] != BEES_UNKNOWN) {
                continue;
            }
            var start = o.hourStart + slot * 3600;
            o.kinds[slot] = kind(h, isDay(start + 1800, rise, set, tomorrowRise), (start / 3600) % 24, winter);
        }
        // "No hive weather" is only a claim when the hours that could have
        // been good are in view and all have weather
        var openable = 0;
        var known = 0;
        for (var k = 0; k < 12; k++) {
            var start = o.hourStart + k * 3600;
            var hour = (start / 3600) % 24;
            if (hour >= OPEN_FROM && hour < OPEN_UNTIL && isDay(start + 1800, rise, set, tomorrowRise)) {
                openable++;
                if (o.kinds[k] != BEES_UNKNOWN) {
                    known++;
                }
            }
        }
        o.windowKnown = openable > 0 && known == openable;
        for (var k = 0; k < 12; k++) {
            if (o.kinds[k] == BEES_OPEN) {
                if (o.openFrom == null) {
                    o.openFrom = k;
                }
                o.openTo = k;
            } else if (o.openFrom != null) {
                break;
            }
        }
        return o;
    }

    // Whether the sun is up at `secs` (seconds since today's midnight, past 86400 for tomorrow)
    function isDay(secs as Number, rise as Number?, set as Number?, tomorrowRise as Number?) as Boolean {
        if (rise == null || set == null) {
            var hour = (secs / 3600) % 24;
            return hour >= 7 && hour < 18;   // no sun times: a plain day
        }
        if (secs < 86400) {
            return secs >= rise && secs < set;
        }
        var morning = (tomorrowRise != null) ? tomorrowRise : rise + 86400;
        return secs >= morning && secs < set + 86400;
    }

    function wet(condition as Number?) as Boolean {
        if (condition == null) {
            return false;
        }
        // rain, snow, storms, showers, drizzle and the rest that fall from the sky
        var falling = [3, 4, 6, 7, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 24, 25, 26,
                       31, 32, 34, 36, 41, 42, 48, 49, 50, 51] as Array<Number>;
        return falling.indexOf(condition) >= 0;
    }

    function clear(condition as Number?) as Boolean {
        if (condition == null) {
            return false;
        }
        // clear, partly cloudy, partly clear, mostly clear, fair, thin clouds
        return [0, 1, 22, 23, 40, 52].indexOf(condition) >= 0;
    }

    // Snow, sleet and the wintry mixes, a subset of wet()
    function snow(condition as Number?) as Boolean {
        return condition != null
            && ([4, 7, 16, 17, 18, 19, 21, 48, 50, 51] as Array<Number>).indexOf(condition) >= 0;
    }

    // November to March
    function winter(month as Number) as Boolean {
        return month >= 11 || month <= 3;
    }

    // The verdict for now, in words: what the bees are doing
    function verdict(kind as Number) as String {
        switch (kind) {
            case BEES_OPEN:
            case BEES_FLY:
                return "BEES FLYING";
            case BEES_CLEANSE:
                return "CLEANSING FLIGHTS";
            case BEES_COLD:
                return "TOO COLD TO FLY";
            case BEES_WIND:
                return "TOO WINDY";
            case BEES_RAIN:
                return "RAIN, BEES HOME";
            case BEES_NIGHT:
                return "NIGHT, BEES HOME";
        }
        return "NO WEATHER YET";
    }

    // The line about opening the hive
    function windowText(o as ForageOutlook) as String {
        var from = o.openFrom;
        var to = o.openTo;
        if (from != null && to != null) {
            var end = clock24(o.hourStart + (to + 1) * 3600);
            if (from == 0) {
                return "open the hive now, until " + end;
            }
            return "open the hive " + clock24(o.hourStart + from * 3600) + "-" + end;
        }
        return o.windowKnown ? "no hive weather in 12 h" : "";
    }

    // Seconds since midnight -> "07:05", always 24-hour
    function clock24(secs as Number) as String {
        return ((secs / 3600) % 24).format("%02d") + ":" + ((secs / 60) % 60).format("%02d");
    }

    // ---------------------------------------------------------------- the year
    // The beekeeper's year in Northern Virginia, by day of the year (1 to
    // 365, leap days ignored). Approximate; to be corrected from the hives.

    // [first day, name] in order; each season runs until the next starts
    function seasons() as Array<[Number, String]> {
        return [[1, "WINTER CLUSTER"], [46, "MAPLE AND WILLOW"], [91, "FRUIT BLOOM"],
                [121, "MAIN FLOW"], [167, "CLOVER"], [197, "SUMMER DEARTH"],
                [244, "FALL FLOW"], [294, "WINTER PREP"], [335, "WINTER CLUSTER"]] as Array<[Number, String]>;
    }

    // The nectar flows on the bezel: [first day, last day, strong]
    function flows() as Array<[Number, Number, Boolean]> {
        return [[91, 166, true], [167, 196, false], [244, 293, false]] as Array<[Number, Number, Boolean]>;
    }

    function season(dayOfYear as Number) as String {
        var all = seasons();
        var name = all[0][1];
        for (var i = 0; i < all.size(); i++) {
            if (dayOfYear >= all[i][0]) {
                name = all[i][1];
            }
        }
        return name;
    }

    // Month 1 to 12, day 1 to 31 -> 1 to 365
    function dayOfYear(month as Number, day as Number) as Number {
        var before = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334] as Array<Number>;
        return before[month - 1] + day;
    }
}
