import Toybox.Lang;

// What happened this second: the view buzzes about it, the recorder laps on it
enum {
    EVENT_NONE,
    EVENT_ENTER,          // into the heat
    EVENT_LEAVE,          // out of it
    EVENT_ROUND_TARGET,   // the round reached the target length
    EVENT_BREAK_TARGET,   // the break did
    EVENT_HOT             // the watch itself is at or over the warning temperature
}

enum {
    PHASE_ARRIVAL,   // recording, not yet in the sauna
    PHASE_SAUNA,
    PHASE_BREAK
}

// One round in the heat and the recovery after it, in seconds since the visit began
class SaunaRound {
    var start as Number;
    var end as Number? = null;      // null while still in the heat
    var maxHr as Number = 0;
    var hrSum as Number = 0;
    var hrCount as Number = 0;
    var maxTemp as Float? = null;   // the watch's hottest reading during the round
    var peakHr as Number = 0;       // highest heart rate in the half minute after leaving
    var peakAt as Number? = null;
    var drop1 as Number? = null;    // beats the heart rate fell a minute after that peak
    var drop2 as Number? = null;    // and two minutes after

    function initialize(start as Number) {
        self.start = start;
    }

    function seconds(now as Number) as Number {
        var e = end;
        return (e == null ? now : e) - start;
    }

    function avgHr() as Number? {
        return hrCount > 0 ? hrSum / hrCount : null;
    }

    function done() as Boolean {
        return end != null;
    }
}

// The visit: rounds and breaks, the door noticed from the watch's own
// thermometer (it warms a few degrees a minute in sauna air and cools as
// fast outside), the heart-rate recovery after each round, the targets and
// the heat guard. Pure arithmetic driven once a second by tick(); nothing
// here touches hardware, so the tests feed it synthetic visits.
class SaunaTracker {
    const WINDOW = 60;          // seconds the temperature change is measured over
    const MIN_PHASE = 90;       // no automatic change this soon after the last one
    const MANUAL_HOLD = 180;    // nor this soon after a button press
    const PEAK_WINDOW = 30;     // seconds after leaving in which the peak is looked for
    const TRACE_MAX = 40 * 60;  // heart-rate samples kept for the chart

    // Settings (see resources/settings)
    var auto as Boolean = true;
    var enterRate as Float = 1.5;      // degrees the watch must warm in a minute
    var leaveRate as Float = 1.0;      // and cool
    var roundTarget as Number = 15 * 60;
    var breakTarget as Number = 10 * 60;
    var goal as Number = 3;
    var hotTemp as Float = 50.0;

    var now as Number = 0;             // seconds since the visit began
    var phase as Number = PHASE_ARRIVAL;
    var rounds as Array<SaunaRound> = [] as Array<SaunaRound>;
    var hr as Number? = null;          // the latest readings
    var temp as Float? = null;
    var maxTemp as Float? = null;
    var hot as Boolean = false;
    var trace as Array<Number?> = [] as Array<Number?>;   // heart rate per second from the last entry
    var traceStart as Number = 0;

    private var _temps as Array<Float?>;   // the last WINDOW + 1 readings, a ring
    private var _lastChange as Number = -100000;
    private var _lastManual as Number = -100000;
    private var _lastHot as Number = -100000;
    private var _breakStart as Number = 0;
    private var _breakTotal as Number = 0;

    function initialize() {
        _temps = new [WINDOW + 1] as Array<Float?>;
    }

    // One second on, with the readings of that second (null when missing)
    function tick(hr as Number?, temp as Float?) as Number {
        now += 1;
        self.hr = hr;
        if (temp != null) {
            self.temp = temp;
            var mt = maxTemp;
            if (mt == null || temp > mt) {
                maxTemp = temp;
            }
        }
        _temps[now % (WINDOW + 1)] = self.temp;

        var round = current();
        if (phase == PHASE_SAUNA && round != null) {
            if (hr != null && hr > 0) {
                round.hrSum += hr;
                round.hrCount += 1;
                if (hr > round.maxHr) {
                    round.maxHr = hr;
                }
            }
            var t = self.temp;
            var rt = round.maxTemp;
            if (t != null && (rt == null || t > rt)) {
                round.maxTemp = t;
            }
        } else if (round != null && round.done()) {
            recover(round, hr);
        }
        if (round != null && trace.size() < TRACE_MAX
                && (phase == PHASE_SAUNA || now - (round.end as Number) <= 150)) {
            trace.add(hr);
        }

        var event = EVENT_NONE;
        if (auto && now - _lastChange >= MIN_PHASE && now - _lastManual >= MANUAL_HOLD) {
            if (phase != PHASE_SAUNA) {
                var rise = rise();
                if (rise != null && rise >= enterRate - 0.001) {
                    enter();
                    event = EVENT_ENTER;
                }
            } else {
                var fall = fall();
                if (fall != null && fall >= leaveRate - 0.001) {
                    leave();
                    event = EVENT_LEAVE;
                }
            }
        }
        if (event == EVENT_NONE) {
            if (phase == PHASE_SAUNA && roundTarget > 0 && phaseSeconds() == roundTarget) {
                event = EVENT_ROUND_TARGET;
            } else if (phase == PHASE_BREAK && breakTarget > 0 && phaseSeconds() == breakTarget) {
                event = EVENT_BREAK_TARGET;
            }
        }
        var t = self.temp;
        if (t != null && t >= hotTemp) {
            hot = true;
            if (event == EVENT_NONE && now - _lastHot >= 60) {
                _lastHot = now;
                event = EVENT_HOT;
            }
        } else if (t != null && t < hotTemp - 2.0) {
            hot = false;
        }
        return event;
    }

    // Degrees the watch is above its coolest reading of the last WINDOW
    // seconds: walking into the heat shows as a quick rise from that low.
    // Null until a minute of readings is in.
    function rise() as Float? {
        var latest = _temps[now % (WINDOW + 1)];
        var low = extreme(false);
        return (latest == null || low == null) ? null : latest - low;
    }

    // Degrees below the hottest reading of the last WINDOW seconds
    function fall() as Float? {
        var latest = _temps[now % (WINDOW + 1)];
        var high = extreme(true);
        return (latest == null || high == null) ? null : high - latest;
    }

    private function extreme(highest as Boolean) as Float? {
        if (now < WINDOW) {
            return null;
        }
        var best = null as Float?;
        for (var i = 0; i <= WINDOW; i++) {
            var v = _temps[i];
            if (v == null) {
                return null;
            }
            var b = best;
            if (b == null || (highest ? v > b : v < b)) {
                best = v;
            }
        }
        return best;
    }

    // The LAP button: into the heat, or out of it
    function mark() as Number {
        _lastManual = now;
        if (phase == PHASE_SAUNA) {
            leave();
            return EVENT_LEAVE;
        }
        enter();
        return EVENT_ENTER;
    }

    function enter() as Void {
        if (phase == PHASE_BREAK) {
            _breakTotal += now - _breakStart;
        }
        phase = PHASE_SAUNA;
        _lastChange = now;
        rounds.add(new SaunaRound(now));
        trace = [] as Array<Number?>;
        traceStart = now;
    }

    function leave() as Void {
        var round = current();
        if (round != null) {
            round.end = now;
        }
        phase = PHASE_BREAK;
        _lastChange = now;
        _breakStart = now;
    }

    // The peak after leaving, then the falls a minute and two minutes later
    private function recover(round as SaunaRound, hr as Number?) as Void {
        var end = round.end as Number;
        if (now - end <= PEAK_WINDOW) {
            if (hr != null && hr > round.peakHr) {
                round.peakHr = hr;
                round.peakAt = now;
            }
            return;
        }
        var at = round.peakAt;
        if (at == null || hr == null) {
            return;
        }
        if (now == at + 60) {
            round.drop1 = round.peakHr - hr;
        } else if (now == at + 120) {
            round.drop2 = round.peakHr - hr;
        }
    }

    function current() as SaunaRound? {
        var n = rounds.size();
        return n > 0 ? rounds[n - 1] : null;
    }

    // The last round that is over, for the recovery chart
    function lastDone() as SaunaRound? {
        for (var i = rounds.size() - 1; i >= 0; i--) {
            if (rounds[i].done()) {
                return rounds[i];
            }
        }
        return null;
    }

    // The round before the current one: its recovery belongs to the break just ended
    function previous() as SaunaRound? {
        var n = rounds.size();
        return n > 1 ? rounds[n - 2] : null;
    }

    function roundCount() as Number {
        return rounds.size();
    }

    // Seconds in the current phase
    function phaseSeconds() as Number {
        if (phase == PHASE_SAUNA) {
            var r = current();
            return r == null ? 0 : r.seconds(now);
        }
        if (phase == PHASE_BREAK) {
            return now - _breakStart;
        }
        return now;
    }

    function saunaSeconds() as Number {
        var s = 0;
        for (var i = 0; i < rounds.size(); i++) {
            s += rounds[i].seconds(now);
        }
        return s;
    }

    function breakSeconds() as Number {
        return _breakTotal + (phase == PHASE_BREAK ? now - _breakStart : 0);
    }

    function maxHr() as Number {
        var m = 0;
        for (var i = 0; i < rounds.size(); i++) {
            if (rounds[i].maxHr > m) {
                m = rounds[i].maxHr;
            }
        }
        return m;
    }

    // The average one-minute fall over the rounds that have one
    function avgDrop1() as Number? {
        var sum = 0;
        var n = 0;
        for (var i = 0; i < rounds.size(); i++) {
            var d = rounds[i].drop1;
            if (d != null) {
                sum += d;
                n += 1;
            }
        }
        return n > 0 ? sum / n : null;
    }

    // The visit as a history row (see SaunaHistory)
    function historyRow(startUnix as Number) as Array<Number> {
        var drop = avgDrop1();
        var mt = maxTemp;
        return [startUnix, roundCount(), saunaSeconds(), breakSeconds(), maxHr(),
                drop == null ? -1 : drop,
                mt == null ? -1000 : (mt * 10.0 + 0.5).toNumber()] as Array<Number>;
    }
}
