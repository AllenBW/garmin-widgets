import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;
import Toybox.Time.Gregorian;

// Words and numbers for the glance and the screens
(:glance)
module SaunaText {

    // Temperatures are shown in Fahrenheit unless the setting says Celsius
    var fahrenheit as Boolean = true;

    // Degrees C from the watch -> "118°" in the chosen unit
    function temp(celsius as Numeric) as String {
        var v = fahrenheit ? celsius * 9.0 / 5.0 + 32.0 : celsius;
        return Math.round(v).toNumber().toString() + "°";
    }

    function unit() as String {
        return fahrenheit ? "°F" : "°C";
    }

    function kindName(kind as Number) as String {
        return kind == KIND_STEAM ? "Steam room" : "Sauna";
    }

    function kindUpper(kind as Number) as String {
        return kind == KIND_STEAM ? "STEAM" : "SAUNA";
    }

    // "2/4 saunas", "1/3 steams"
    function kindCount(kind as Number, n as Number, goal as Number) as String {
        return n + "/" + goal + (kind == KIND_STEAM ? " steams" : " saunas");
    }

    // Seconds -> "12:34", or "1:02:34" past an hour
    function clock(seconds as Number) as String {
        if (seconds < 0) {
            seconds = 0;
        }
        var h = seconds / 3600;
        var m = (seconds / 60) % 60;
        var s = seconds % 60;
        if (h > 0) {
            return h.toString() + ":" + m.format("%02d") + ":" + s.format("%02d");
        }
        return m.toString() + ":" + s.format("%02d");
    }

    // Seconds -> "38 min", or "1 h 05" past an hour
    function minutes(seconds as Number) as String {
        var m = (seconds + 30) / 60;
        if (m < 60) {
            return m.toString() + " min";
        }
        return (m / 60).toString() + " h " + (m % 60).format("%02d");
    }

    function rounds(n as Number) as String {
        return n == 1 ? "1 round" : n.toString() + " rounds";
    }

    // A fall in heart rate -> "-28", or "--" when it was not measured
    function drop(bpm as Number?) as String {
        if (bpm == null) {
            return "--";
        }
        return (bpm >= 0 ? "-" : "+") + bpm.abs().toString();
    }

    // Unix seconds -> "29 Oct": short enough for a table column
    function date(unix as Number) as String {
        var info = Gregorian.info(new Time.Moment(unix), Time.FORMAT_MEDIUM);
        return info.day + " " + info.month;
    }

    // Tenths of a degree C from a history row -> "118°", or "" when none
    function tenths(value as Number) as String {
        return value <= -1000 ? "" : temp(value / 10.0);
    }

    // The glance headline from a history row: "Sauna · 3 rounds · 38 min"
    function headline(row as Array<Number>?) as String {
        if (row == null) {
            return "No visits yet";
        }
        return kindName(row[SaunaHistory.KIND]) + " · " + rounds(row[SaunaHistory.ROUNDS]) + " · " + minutes(row[SaunaHistory.SAUNA_SEC]);
    }

    // A visit's detail: "Tue 28 Oct · max 142 bpm · -31 in 1 min"
    function detail(row as Array<Number>?) as String {
        if (row == null) {
            return "START records a visit";
        }
        var s = Lib.Fmt.shortDate(new Time.Moment(row[SaunaHistory.START]));
        if (row[SaunaHistory.MAX_HR] > 0) {
            s += " · max " + row[SaunaHistory.MAX_HR] + " bpm";
        }
        if (row[SaunaHistory.DROP] >= 0) {
            s += " · " + drop(row[SaunaHistory.DROP]) + " in 1 min";
        }
        if (row[SaunaHistory.BB_START] >= 0 && row[SaunaHistory.BB_END] >= 0) {
            s += " · Body Battery " + row[SaunaHistory.BB_START] + "→" + row[SaunaHistory.BB_END];
        }
        return s;
    }

    // This week against the plan: "Week 2/4 saunas · 46/60 min"
    function week(plan as SaunaPlan) as String {
        var w = SaunaHistory.thisWeek(plan.kind);
        return "Week " + kindCount(plan.kind, w[0], plan.weekSessions) + " · " + ((w[1] + 30) / 60) + "/" + plan.weekMinutes + " min";
    }

    // The glance's version, one short line: "Week 2/4 · 46/60 min"
    function weekShort(plan as SaunaPlan) as String {
        var w = SaunaHistory.thisWeek(plan.kind);
        return "Week " + w[0] + "/" + plan.weekSessions + " · " + ((w[1] + 30) / 60) + "/" + plan.weekMinutes + " min";
    }
}
