import Toybox.Lang;

// The two kinds of heat; constants rather than an enum so the glance sees them too
(:glance) const KIND_SAUNA = 0;
(:glance) const KIND_STEAM = 1;

// What happened this second: the view buzzes about it, the recorder laps on it
enum {
    EVENT_NONE,
    EVENT_ENTER,          // into the heat
    EVENT_LEAVE,          // out of it
    EVENT_ROUND_TARGET,   // the round reached its target: time to cool down
    EVENT_ROUND_OVER,     // past the longest sensible round, once a minute
    EVENT_HEAT_CAP,       // the visit's heat total reached the cap
    EVENT_BREAK_TARGET,   // cooled down long enough: ready for the next round
    EVENT_PLAN_DONE,      // cooled down after the last planned round
    EVENT_RECOVERY,       // the one-minute fall just became known
    EVENT_HOT,            // the watch itself is at or over the warning temperature
    EVENT_HR_HIGH,        // the heart rate has been over the ceiling for a minute
    EVENT_NOT_RECOVERED   // a minute after leaving the heart rate is still high: the break grows
}

enum {
    PHASE_ARRIVAL,   // recording, not yet in the heat
    PHASE_SAUNA,     // in the heat, sauna or steam
    PHASE_BREAK
}

// The plan for one kind of heat: targets in seconds, goals per week, and how
// quickly the watch must warm or cool for the door to count. The defaults
// follow the published guidance: rounds of 15 to 20 minutes in a sauna and
// 10 to 15 in steam, a cool-down at least as long as the round, about 30 to
// 45 minutes of heat in a visit, several visits a week.
(:glance)
class SaunaPlan {
    var kind as Number = KIND_SAUNA;
    var roundTarget as Number = 15 * 60;   // when to come out
    var roundMax as Number = 20 * 60;      // nag past this
    var breakTarget as Number = 15 * 60;   // at least this long out, and never shorter than the round
    var rounds as Number = 3;
    var heatCap as Number = 45 * 60;       // seconds of heat in one visit
    var weekSessions as Number = 4;
    var weekMinutes as Number = 60;
    var enterRate as Float = 1.5;          // degrees C the watch must warm in a minute
    var leaveRate as Float = 1.0;          // and cool

    function initialize(kind as Number) {
        self.kind = kind;
        if (kind == KIND_STEAM) {
            roundTarget = 12 * 60;
            roundMax = 15 * 60;
            breakTarget = 12 * 60;
            rounds = 2;
            heatCap = 30 * 60;
            weekSessions = 3;
            weekMinutes = 40;
            enterRate = 0.8;   // a steam room is only a few degrees above skin
            leaveRate = 0.6;
        }
    }
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
// fast outside), the heart-rate recovery after each round, the plan's
// targets and the coaching line, and the heat guard. Pure arithmetic
// driven once a second by tick(); nothing here touches hardware, so the
// tests feed it synthetic visits.
class SaunaTracker {
    const WINDOW = 60;          // seconds the temperature change is measured over
    const MIN_PHASE = 90;       // no automatic change this soon after the last one
    const MANUAL_HOLD = 180;    // nor this soon after a button press
    const PEAK_WINDOW = 30;     // seconds after leaving in which the peak is looked for
    const TRACE_MAX = 40 * 60;  // heart-rate samples kept for the chart
    const RECOVERY_SHOWN = 30;  // seconds the coach line reports a fresh recovery
    const DRINK_SHOWN = 45;     // seconds the coach line asks for water at the start of a break
    const STAND_SHOWN = 20;     // seconds "stand up slowly" shows first
    const HR_HIGH_AFTER = 60;   // seconds over the ceiling before the rule speaks
    const BREAK_EXTENSION = 300; // seconds added to the break when the heart has not settled

    var plan as SaunaPlan = new SaunaPlan(KIND_SAUNA);
    var guided as Boolean = true;      // false: a free session, in and out as you like, no targets
    var auto as Boolean = true;
    var sensitivity as Float = 1.0;    // scales the plan's door rates: under 1 is more eager
    var hotTemp as Float = 50.0;       // 0 turns the heat guard off
    var baselineDrop as Number? = null;   // this kind's usual one-minute fall from earlier visits

    // Heart-rate coaching, each rule with its own switch (the occupational
    // heat-strain criteria: a sustained rate over 180 minus age, a rate
    // still over 110 a minute after the peak)
    var coachHrHigh as Boolean = true;
    var hrCeiling as Number = 0;       // bpm; 0 is off (the settings fill in 180 minus age)
    var coachRecovery as Boolean = true;
    var recoveryHr as Number = 110;    // a minute after leaving the heart should be under this
    var coachStand as Boolean = true;

    // The other readings, for the file and the screens
    var breath as Number? = null;
    var stress as Number? = null;
    var hrv as Number? = null;         // RMSSD in ms over the last minute

    var now as Number = 0;             // seconds since the visit began
    var phase as Number = PHASE_ARRIVAL;
    var rounds as Array<SaunaRound> = [] as Array<SaunaRound>;
    var hr as Number? = null;          // the latest readings
    var temp as Float? = null;
    var maxTemp as Float? = null;
    var hot as Boolean = false;
    var trace as Array<Number?> = [] as Array<Number?>;   // heart rate per second from the last entry
    var traceStart as Number = 0;
    var recoveryAt as Number? = null;  // when the latest one-minute fall became known
    var recoveryDrop as Number? = null;

    private var _temps as Array<Float?>;   // the last WINDOW + 1 readings, a ring
    private var _lastChange as Number = -100000;
    private var _lastManual as Number = -100000;
    private var _lastHot as Number = -100000;
    private var _breakStart as Number = 0;
    private var _breakTotal as Number = 0;
    private var _capHit as Boolean = false;
    private var _recoveryNew as Boolean = false;
    private var _hrHighFor as Number = 0;          // consecutive seconds over the ceiling
    private var _lastHrHigh as Number = -100000;
    private var _notRecoveredNew as Boolean = false;
    private var _notRecoveredAt as Number? = null;
    private var _notRecoveredHr as Number = 0;
    private var _breakExtra as Number = 0;         // added to this break's goal by the recovery rule

    function initialize() {
        _temps = new [WINDOW + 1] as Array<Float?>;
    }

    // One second on, with the readings of that second (null when missing)
    function tick(hr as Number?, temp as Float?) as Number {
        return tickAll(hr, temp, null, null);
    }

    function tickAll(hr as Number?, temp as Float?, breath as Number?, stress as Number?) as Number {
        now += 1;
        self.hr = hr;
        if (breath != null) {
            self.breath = breath;
        }
        if (stress != null) {
            self.stress = stress;
        }
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

        // the door
        var event = EVENT_NONE;
        if (auto && now - _lastChange >= MIN_PHASE && now - _lastManual >= MANUAL_HOLD) {
            if (phase != PHASE_SAUNA) {
                var rise = rise();
                if (rise != null && rise >= plan.enterRate * sensitivity - 0.001) {
                    enter();
                    event = EVENT_ENTER;
                }
            } else {
                var fall = fall();
                if (fall != null && fall >= plan.leaveRate * sensitivity - 0.001) {
                    leave();
                    event = EVENT_LEAVE;
                }
            }
        }

        // the heart-rate ceiling, in the heat, guided or free
        if (coachHrHigh && hrCeiling > 0 && phase == PHASE_SAUNA && hr != null && hr >= hrCeiling) {
            _hrHighFor += 1;
            if (event == EVENT_NONE && _hrHighFor >= HR_HIGH_AFTER && now - _lastHrHigh >= 60) {
                _lastHrHigh = now;
                event = EVENT_HR_HIGH;
            }
        } else {
            _hrHighFor = 0;
        }

        // the plan, in a guided session
        if (event == EVENT_NONE && guided) {
            var ps = phaseSeconds();
            if (phase == PHASE_SAUNA) {
                if (!_capHit && plan.heatCap > 0 && saunaSeconds() >= plan.heatCap) {
                    _capHit = true;
                    event = EVENT_HEAT_CAP;
                } else if (plan.roundTarget > 0 && ps == plan.roundTarget) {
                    event = EVENT_ROUND_TARGET;
                } else if (plan.roundMax > 0 && ps >= plan.roundMax && (ps - plan.roundMax) % 60 == 0) {
                    event = EVENT_ROUND_OVER;
                }
            } else if (phase == PHASE_BREAK) {
                var goal = breakGoal();
                if (goal > 0 && ps == goal) {
                    event = morePlanned() ? EVENT_BREAK_TARGET : EVENT_PLAN_DONE;
                }
            }
        }
        if (_recoveryNew) {
            _recoveryNew = false;
            if (event == EVENT_NONE) {
                event = _notRecoveredNew ? EVENT_NOT_RECOVERED : EVENT_RECOVERY;
            }
            _notRecoveredNew = false;
        }

        // the heat guard
        var t = self.temp;
        if (hotTemp > 0 && t != null && t >= hotTemp) {
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
        _breakExtra = 0;
        _hrHighFor = 0;
        rounds.add(new SaunaRound(now));
        trace = [] as Array<Number?>;
        traceStart = now;
    }

    // The heart rate has been over the ceiling for a minute
    function hrHigh() as Boolean {
        return _hrHighFor >= HR_HIGH_AFTER;
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
            recoveryAt = now;
            recoveryDrop = round.drop1;
            _recoveryNew = true;
            if (coachRecovery && hr > recoveryHr) {
                _notRecoveredNew = true;
                _notRecoveredAt = now;
                _notRecoveredHr = hr;
                _breakExtra = BREAK_EXTENSION;
            }
        } else if (now == at + 120) {
            round.drop2 = round.peakHr - hr;
        }
    }

    // ---- the plan ----

    // The break must be at least the plan's, never shorter than the round
    // before it, and longer still when the heart had not settled
    function breakGoal() as Number {
        var last = lastDone();
        var len = last == null ? 0 : last.seconds(now);
        return (plan.breakTarget > len ? plan.breakTarget : len) + _breakExtra;
    }

    function breakExtended() as Boolean {
        return _breakExtra > 0;
    }

    function morePlanned() as Boolean {
        return roundCount() < plan.rounds && (plan.heatCap == 0 || saunaSeconds() < plan.heatCap);
    }

    // The coaching line for the live screen
    function coach() as String {
        if (hot) {
            return "Watch hot, take it off";
        }
        var h = hr;
        if (hrHigh() && h != null) {
            return "HR " + h + " · come out";
        }
        var na = _notRecoveredAt;
        if (na != null && now - na < RECOVERY_SHOWN) {
            return "HR " + _notRecoveredHr + " · cool down longer";
        }
        var ra = recoveryAt;
        var rd = recoveryDrop;
        if (ra != null && rd != null && now - ra < RECOVERY_SHOWN) {
            var s = "Fell " + rd + " in 1 min";
            var b = baselineDrop;
            if (b != null && b > 0) {
                s = "Fell " + rd + (rd >= b ? " · above your " + b : " · usual " + b);
            }
            return s;
        }
        var ps = phaseSeconds();
        if (phase == PHASE_ARRIVAL) {
            if (ps < 90 && guided) {
                return "Drink, shower, then go in";
            }
            return auto ? "Walk in when ready" : "LAP when you go in";
        }
        if (phase == PHASE_BREAK && coachStand && ps < STAND_SHOWN) {
            return "Stand up slowly";
        }
        if (!guided) {
            if (phase == PHASE_SAUNA) {
                return "Out when you like";
            }
            return ps < DRINK_SHOWN ? "Drink some water" : "In again when ready";
        }
        if (phase == PHASE_SAUNA) {
            if (plan.heatCap > 0 && saunaSeconds() >= plan.heatCap) {
                return (plan.heatCap / 60) + " min of heat · come out";
            }
            if (plan.roundMax > 0 && ps >= plan.roundMax) {
                return "Over " + (plan.roundMax / 60) + " min · come out";
            }
            if (plan.roundTarget > 0 && ps >= plan.roundTarget) {
                return "Time to cool down";
            }
            if (plan.roundTarget > 0) {
                return SaunaText.clock(plan.roundTarget - ps) + " left";
            }
            return "In the heat";
        }
        if (ps < DRINK_SHOWN) {
            return "Drink some water";
        }
        var goal = breakGoal();
        if (ps < goal) {
            return "Cool down " + SaunaText.clock(goal - ps) + " more";
        }
        if (morePlanned()) {
            return "Ready for round " + (roundCount() + 1);
        }
        return "Done · START to save";
    }

    // ---- sums ----

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

    // A made-up sauna visit for the demo: two rounds done, four minutes into
    // the second break, with a recovery, a heart-rate trace and readings
    function seedDemo() as Void {
        plan = new SaunaPlan(KIND_SAUNA);
        now = 3030;
        phase = PHASE_BREAK;
        hr = 96;
        temp = 44.6;
        maxTemp = 48.4;
        breath = 14;
        stress = 48;
        hrv = 34;
        baselineDrop = 30;
        var r1 = new SaunaRound(90);
        r1.end = 990;
        r1.maxHr = 132;
        r1.hrSum = 118 * 900;
        r1.hrCount = 900;
        r1.maxTemp = 47.9;
        r1.peakHr = 128;
        r1.peakAt = 1000;
        r1.drop1 = 31;
        r1.drop2 = 44;
        var r2 = new SaunaRound(1890);
        r2.end = 2790;
        r2.maxHr = 136;
        r2.hrSum = 121 * 900;
        r2.hrCount = 900;
        r2.maxTemp = 48.4;
        r2.peakHr = 131;
        r2.peakAt = 2800;
        r2.drop1 = 29;
        r2.drop2 = 40;
        rounds = [r1, r2] as Array<SaunaRound>;
        _breakStart = 2790;
        _breakTotal = 900;
        _lastChange = 2790;
        recoveryAt = 2860;
        recoveryDrop = 29;
        trace = [] as Array<Number?>;
        for (var i = 0; i < 1050; i++) {
            if (i < 900) {
                trace.add(95 + (36 * i) / 900 + ((i / 7) % 3));
            } else {
                trace.add(131 - (41 * (i - 900)) / 150);
            }
        }
        traceStart = 1890;
    }

    // The visit as a history row (see SaunaHistory); Body Battery -1 when unknown
    function historyRow(startUnix as Number, bbStart as Number?, bbEnd as Number?) as Array<Number> {
        var drop = avgDrop1();
        var mt = maxTemp;
        return [startUnix, plan.kind, roundCount(), saunaSeconds(), breakSeconds(), maxHr(),
                drop == null ? -1 : drop,
                mt == null ? -1000 : (mt * 10.0 + 0.5).toNumber(),
                bbStart == null ? -1 : bbStart,
                bbEnd == null ? -1 : bbEnd] as Array<Number>;
    }
}
