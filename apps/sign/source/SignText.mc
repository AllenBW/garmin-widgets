import Toybox.Lang;

// What the sign says: pure text, fed by the tests.
module SignText {

    const DAYS = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"] as Array<String>;

    // The hours as the watch's clock shows them: two numerals in 24-hour
    // time, one or two in 12-hour time
    function hours(hour as Number, is24 as Boolean) as String {
        if (is24) {
            return hour.format("%02d");
        }
        var h = hour % 12;
        return ((h == 0) ? 12 : h).format("%d");
    }

    function minutes(minute as Number) as String {
        return minute.format("%02d");
    }

    // The date: the weekday (1 is Sunday, as Gregorian counts) and the day
    function date(weekday as Number, day as Number) as String {
        return DAYS[(weekday + 6) % 7] + " " + day.format("%d");
    }

    // The places of `fresh` whose numeral differs from `old`'s: all of them
    // when the count of numerals changed (9 to 10 on a 12-hour clock), since
    // every numeral of the row then moves
    function changed(old as String, fresh as String) as Array<Number> {
        var out = [] as Array<Number>;
        var a = old.toCharArray();
        var b = fresh.toCharArray();
        for (var i = 0; i < b.size(); i++) {
            if (a.size() != b.size() || a[i] != b[i]) {
                out.add(i);
            }
        }
        return out;
    }

    // A look's name in one line or two, split at its first space
    function lines(title as String) as Array<String> {
        var at = title.find(" ");
        if (at == null) {
            return [title] as Array<String>;
        }
        return [title.substring(0, at) as String, title.substring(at + 1, title.length()) as String] as Array<String>;
    }
}
