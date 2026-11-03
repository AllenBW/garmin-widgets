import Toybox.Lang;
import Toybox.Time;

// The log's last DAYS days, laid out for the two pattern pages: for each
// entry its day (0 today, 1 yesterday, ...), its time of day in seconds and
// its name's index in the log's table.
class TallyDays {
    var day as Array<Number> = [] as Array<Number>;
    var sec as Array<Number> = [] as Array<Number>;
    var which as Array<Number> = [] as Array<Number>;
    var names as Array<String> = [] as Array<String>;

    function initialize(days as Number, now as Number) {
        var today = TallyStats.dayKey(now);
        var log = TallyLog.since(now - days * 86400 - 86400);
        var times = log[0];
        // in time order: a time changed in History can move an entry
        for (var i = 1; i < times.size(); i++) {
            var k = i;
            while (k > 0 && times[k - 1] > times[k]) {
                var t = times[k];
                times[k] = times[k - 1];
                times[k - 1] = t;
                var w = log[1][k];
                log[1][k] = log[1][k - 1];
                log[1][k - 1] = w;
                k--;
            }
        }
        for (var i = 0; i < times.size(); i++) {
            var ago = today - TallyStats.dayKey(times[i]);
            if (ago >= 0 && ago < days) {
                day.add(ago);
                sec.add(Lib.Fmt.localSeconds(times[i]));
                which.add(log[1][i]);
            }
        }
        names = TallyLog.names();
    }

    // The entries of one name: [days, times of day]
    function of(name as String) as [Array<Number>, Array<Number>] {
        var index = names.indexOf(name);
        var d = [] as Array<Number>;
        var s = [] as Array<Number>;
        for (var i = 0; i < which.size(); i++) {
            if (which[i] == index) {
                d.add(day[i]);
                s.add(sec[i]);
            }
        }
        return [d, s];
    }

    // How many entries each name has, by index
    function counts() as Array<Number> {
        var out = new [names.size()] as Array<Number>;
        for (var i = 0; i < out.size(); i++) {
            out[i] = 0;
        }
        for (var i = 0; i < which.size(); i++) {
            out[which[i]] += 1;
        }
        return out;
    }
}

// The arithmetic behind the pattern pages and the glance, kept pure for the tests
module TallyStats {

    const WINDOW = 7200;        // "usually": the busiest two hours of the day

    // A local calendar day as a number, the same for every moment in it
    function dayKey(unix as Number) as Number {
        return (unix - Lib.Fmt.localSeconds(unix) + 43200) / 86400;
    }

    // The usual time: the busiest WINDOW of the day (it may span midnight)
    // and the average time inside it. [time of day, entries inside, start
    // of the window], or null with fewer than two entries.
    function usual(secs as Array<Number>) as [Number, Number, Number]? {
        var n = secs.size();
        if (n < 2) {
            return null;
        }
        var s = sorted(secs);
        var best = 0;
        var bestStart = 0;
        var j = 0;
        for (var i = 0; i < n; i++) {
            // entries from s[i] to s[i] + WINDOW, wrapping into the next day
            if (j < i) {
                j = i;
            }
            while (j + 1 < i + n && at(s, j + 1) - s[i] < WINDOW) {
                j++;
            }
            if (j - i + 1 > best) {
                best = j - i + 1;
                bestStart = i;
            }
        }
        var sum = 0;
        for (var k = bestStart; k < bestStart + best; k++) {
            sum += at(s, k);
        }
        return [(sum / best) % 86400, best, s[bestStart]];
    }

    // The sorted list, then again a day later, as one circle
    function at(s as Array<Number>, k as Number) as Number {
        var n = s.size();
        return (k < n) ? s[k] : s[k - n] + 86400;
    }

    function sorted(secs as Array<Number>) as Array<Number> {
        var s = secs.slice(0, null);
        for (var i = 1; i < s.size(); i++) {
            var v = s[i];
            var k = i - 1;
            while (k >= 0 && s[k] > v) {
                s[k + 1] = s[k];
                k--;
            }
            s[k + 1] = v;
        }
        return s;
    }

    // Days with at least one entry between start and start + span seconds
    // of the day (the span may cross midnight)
    function daysWithin(days as Array<Number>, secs as Array<Number>, start as Number, span as Number) as Number {
        var seen = [] as Array<Number>;
        for (var i = 0; i < secs.size(); i++) {
            var off = (secs[i] - start) % 86400;
            if (off < 0) {
                off += 86400;
            }
            if (off < span && seen.indexOf(days[i]) < 0) {
                seen.add(days[i]);
            }
        }
        return seen.size();
    }

    // Distinct days with any entry
    function distinct(days as Array<Number>) as Number {
        var seen = [] as Array<Number>;
        for (var i = 0; i < days.size(); i++) {
            if (seen.indexOf(days[i]) < 0) {
                seen.add(days[i]);
            }
        }
        return seen.size();
    }

    // Days in a row with an entry, counting back from the newest such day
    function streak(days as Array<Number>) as Number {
        if (days.size() == 0) {
            return 0;
        }
        var d = days[0];
        for (var i = 1; i < days.size(); i++) {
            if (days[i] < d) {
                d = days[i];
            }
        }
        var run = 0;
        while (days.indexOf(d + run) >= 0) {
            run++;
        }
        return run;
    }

    const BEFORE = 6 * 3600;    // "came before": within six hours

    // How often `a` came before `b`, for any two names: of b's entries,
    // how many had an a in the BEFORE hours ahead of it, and the usual gap
    // (the median, in seconds); then the same at the control moments
    // (b's usual time on days with entries but no b), so a daily routine
    // isn't mistaken for a cause. [hits, of, median gap, control hits,
    // controls]. Days count back from today (0); times are of the day.
    function before(bDays as Array<Number>, bSecs as Array<Number>, aDays as Array<Number>, aSecs as Array<Number>,
                    controlDays as Array<Number>, controlSec as Number) as [Number, Number, Number, Number, Number] {
        var gaps = [] as Array<Number>;
        for (var i = 0; i < bDays.size(); i++) {
            var gap = gapBefore(bDays[i] * -86400 + bSecs[i], aDays, aSecs);
            if (gap != null) {
                gaps.add(gap);
            }
        }
        var controlHits = 0;
        for (var i = 0; i < controlDays.size(); i++) {
            if (gapBefore(controlDays[i] * -86400 + controlSec, aDays, aSecs) != null) {
                controlHits++;
            }
        }
        var median = 0;
        if (gaps.size() > 0) {
            median = sorted(gaps)[gaps.size() / 2];
        }
        return [gaps.size(), bDays.size(), median, controlHits, controlDays.size()];
    }

    // Seconds from the newest `a` in the BEFORE hours ahead of moment `t`
    // (seconds from today's midnight, negative for earlier days), or null
    function gapBefore(t as Number, aDays as Array<Number>, aSecs as Array<Number>) as Number? {
        var best = null;
        for (var k = 0; k < aDays.size(); k++) {
            var gap = t - (aDays[k] * -86400 + aSecs[k]);
            if (gap > 0 && gap <= BEFORE && (best == null || gap < best)) {
                best = gap;
            }
        }
        return best;
    }

    // Days among `logged` (any entry) without any of `days`
    function without(logged as Array<Number>, days as Array<Number>) as Array<Number> {
        var out = [] as Array<Number>;
        for (var i = 0; i < logged.size(); i++) {
            if (days.indexOf(logged[i]) < 0 && out.indexOf(logged[i]) < 0) {
                out.add(logged[i]);
            }
        }
        return out;
    }

    // The pattern strip's first hour: six hours before the usual time, so
    // what comes before it shows; or nine hours back from now
    function stripStart(usualTime as Number?, nowSec as Number) as Number {
        var t = ((usualTime != null) ? usualTime - 6 * 3600 : nowSec - 8 * 3600) % 86400;
        return ((t < 0) ? t + 86400 : t) / 3600;
    }
}
