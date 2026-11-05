import Toybox.Lang;
import Toybox.Math;

// What the figure and the coach are doing
enum {
    PH_SETUP,     // getting into position: the start pose, the stretch as a ghost
    PH_EASE,      // breathing out into the stretch (the hold's first seconds)
    PH_HOLD,      // holding, the figure sinking a little on each breath out
    PH_RELEASE,   // easing out
    PH_REPS,      // a moving stretch, start to stretch and back, counted
    PH_PUSH,      // contract-relax: push gently against the stretch, not moving
    PH_RELAX,     // let go
    PH_DEEPEN,    // and hold a little deeper
    PH_BREATHE,   // slow breathing, the figure rising and falling with it
    PH_DONE
}

// What a setup leads into
enum {
    SET_FIRST,    // the routine's first stretch
    SET_STEP,     // the next stretch
    SET_SIDE,     // the other side
    SET_ROUND     // the same again
}

// Getting there from the last stretch
enum {
    MOVE_NONE,
    MOVE_DOWN,    // down to the floor
    MOVE_UP       // back up
}

// The buzz as a phase begins
enum {
    BUZZ_NONE,
    BUZZ_GO,        // ease in, start the reps, push
    BUZZ_RELEASE,   // the hold is over
    BUZZ_SWITCH,    // other side, or again
    BUZZ_NEXT,      // a new stretch
    BUZZ_DONE
}

// A routine laid out as a timeline of phases, then played by tick(). Pure
// arithmetic: the view feeds it milliseconds, the tests feed it whole
// routines. The lengths match designs/stretch_catalogue.py, and so the
// glance's minutes.
class StretchSession {

    static const SETUP_FIRST = 8000;
    static const SETUP_FIRST_DOWN = 10000;
    static const SETUP_SAME = 5000;
    static const SETUP_STEP = 7000;
    static const SETUP_GET_DOWN = 10000;
    static const SETUP_GET_UP = 8000;
    static const SETUP_SIDE = 4000;
    static const SETUP_ROUND = 3000;
    static const EASE = 4000;
    static const RELEASE = 3000;
    static const PNF_HOLD = 10000;
    static const PNF_PUSH = 5000;
    static const PNF_RELAX = 3000;
    static const PNF_DEEPEN = 20;     // seconds, before the level
    static const MIN_HOLD = 5000;
    static const BREATH = 10000;      // six breaths a minute,
    static const INHALE = 5000;       // in as long as out

    static const KIND_HOLD = 0;
    static const KIND_REPS = 1;
    static const KIND_BREATH = 2;
    static const RF_PRE = 1;
    static const RF_PNF = 4;
    static const POS_FLOOR = 3;       // floor, kneeling and all fours are "down"

    var routine as Number;
    var steps as Number = 0;
    var total as Number = 0;          // planned milliseconds, extensions included
    var elapsed as Number = 0;        // milliseconds played, skips not counted

    // Each phase: phase | set << 4 | side << 6 | round << 7 | step << 10 | stretch << 16 | move << 23
    private var _segs as Array<Number> = [] as Array<Number>;
    private var _durs as Array<Number> = [] as Array<Number>;
    private var _cursor as Number = 0;
    private var _in as Number = 0;        // milliseconds into the current phase
    private var _before as Number = 0;    // planned milliseconds before the current phase
    private var _eased as Boolean = false;   // this release came from "ease off"

    // level: percent of each hold (75, 100, 150); pnf: contract-relax where the routine allows it
    function initialize(r as Number, level as Number, pnf as Boolean) {
        routine = r;
        var flags = StretchRoutines.FLAGS[r];
        if ((flags & RF_PRE) != 0 && level > 100) {
            // static holds stay short before an activity
            level = 100;
        }
        var list = StretchData.STEPS[r];
        var meta = StretchData.META;
        var stride = StretchFigure.META;
        steps = list.size() / 3;
        var prev = -1;
        for (var k = 0; k < steps; k++) {
            var st = list[3 * k];
            var dose = list[3 * k + 1];
            var rounds = list[3 * k + 2];
            var kind = meta[st * stride];
            var f = meta[st * stride + 1];
            var pos = meta[st * stride + 12];
            var sides = (f & StretchFigure.F_SIDED) != 0 ? 2 : 1;
            var usePnf = pnf && (flags & RF_PNF) != 0 && (f & StretchFigure.F_PNF) != 0;
            var hold = holdFor(dose, level);
            for (var rd = 0; rd < rounds; rd++) {
                for (var sd = 0; sd < sides; sd++) {
                    var tag = (sd << 6) | (rd << 7) | (k << 10) | (st << 16);
                    if (rd == 0 && sd == 0) {
                        var set = prev < 0 ? SET_FIRST : SET_STEP;
                        var down = pos >= POS_FLOOR;
                        var move = MOVE_NONE;
                        if (prev >= 0 && down != (prev >= POS_FLOOR)) {
                            move = down ? MOVE_DOWN : MOVE_UP;
                        }
                        add(PH_SETUP | (set << 4) | (move << 23) | tag, setupMs(prev, pos));
                    } else if (sd == 1) {
                        add(PH_SETUP | (SET_SIDE << 4) | tag, SETUP_SIDE);
                    } else {
                        add(PH_SETUP | (SET_ROUND << 4) | tag, SETUP_ROUND);
                    }
                    if (kind == KIND_REPS) {
                        add(PH_REPS | tag, dose * meta[st * stride + 5] * 100);
                    } else if (kind == KIND_BREATH) {
                        add(PH_BREATHE | tag, dose * 1000);
                    } else if (usePnf && rd == rounds - 1) {
                        // the last round becomes contract-relax
                        add(PH_EASE | tag, EASE);
                        add(PH_HOLD | tag, PNF_HOLD - EASE);
                        add(PH_PUSH | tag, PNF_PUSH);
                        add(PH_RELAX | tag, PNF_RELAX);
                        add(PH_DEEPEN | tag, holdFor(PNF_DEEPEN, level));
                        add(PH_RELEASE | tag, RELEASE);
                    } else {
                        add(PH_EASE | tag, EASE);
                        add(PH_HOLD | tag, hold - EASE);
                        add(PH_RELEASE | tag, RELEASE);
                    }
                }
            }
            prev = pos;
        }
        add(PH_DONE | ((steps - 1) << 10), 0);
    }

    static function holdFor(seconds as Number, level as Number) as Number {
        var ms = seconds * level * 10;
        return ms < MIN_HOLD ? MIN_HOLD : ms;
    }

    // From where the last stretch left you (prev -1 at the start) to pos
    static function setupMs(prev as Number, pos as Number) as Number {
        var down = pos >= POS_FLOOR;
        if (prev < 0) {
            return down ? SETUP_FIRST_DOWN : SETUP_FIRST;
        }
        if (prev == pos) {
            return SETUP_SAME;
        }
        var wasDown = prev >= POS_FLOOR;
        if (down && !wasDown) {
            return SETUP_GET_DOWN;
        }
        if (wasDown && !down) {
            return SETUP_GET_UP;
        }
        return SETUP_STEP;
    }

    private function add(seg as Number, ms as Number) as Void {
        _segs.add(seg);
        _durs.add(ms);
        total += ms;
    }

    // Move on by ms; the buzz for the last phase begun, if any
    function tick(ms as Number) as Number {
        if (done()) {
            return BUZZ_NONE;
        }
        elapsed += ms;
        _in += ms;
        var buzz = BUZZ_NONE;
        while (!done() && _in >= _durs[_cursor]) {
            _in -= _durs[_cursor];
            _before += _durs[_cursor];
            _cursor++;
            _eased = false;
            var b = buzzFor(_cursor);
            if (b != BUZZ_NONE) {
                buzz = b;
            }
        }
        if (done()) {
            _in = 0;
        }
        return buzz;
    }

    // End the current phase now: "go now" during a setup
    function advance() as Number {
        if (done()) {
            return BUZZ_NONE;
        }
        return tick(_durs[_cursor] - _in);
    }

    // Straight to the next setup (the other side, again, or the next stretch)
    function skip() as Number {
        return jump(false);
    }

    // Straight to the next stretch
    function skipStretch() as Number {
        return jump(true);
    }

    private function jump(wholeStep as Boolean) as Number {
        if (done()) {
            return BUZZ_NONE;
        }
        var step = stepIndex();
        _before += _durs[_cursor];
        _cursor++;
        while (!done()) {
            var seg = _segs[_cursor];
            if ((seg & 15) == PH_SETUP && (!wholeStep || ((seg >> 10) & 63) != step)) {
                break;
            }
            _before += _durs[_cursor];
            _cursor++;
        }
        _in = 0;
        _eased = false;
        return buzzFor(_cursor);
    }

    // It hurts: out of the stretch now, gently, and on
    function easeOff() as Number {
        var p = phase();
        if (p != PH_EASE && p != PH_HOLD && p != PH_PUSH && p != PH_RELAX && p != PH_DEEPEN) {
            return BUZZ_NONE;
        }
        while ((_segs[_cursor] & 15) != PH_RELEASE) {
            _before += _durs[_cursor];
            _cursor++;
        }
        _in = 0;
        _eased = true;
        return BUZZ_RELEASE;
    }

    // Ten more seconds in a hold or the reps
    function extend(ms as Number) as Boolean {
        var p = phase();
        if (p == PH_HOLD || p == PH_DEEPEN || p == PH_REPS || p == PH_BREATHE) {
            _durs[_cursor] += ms;
            total += ms;
            return true;
        }
        return false;
    }

    private function buzzFor(i as Number) as Number {
        var seg = _segs[i];
        var p = seg & 15;
        if (p == PH_SETUP) {
            var set = (seg >> 4) & 3;
            return set == SET_STEP ? BUZZ_NEXT : (set == SET_FIRST ? BUZZ_NONE : BUZZ_SWITCH);
        }
        if (p == PH_EASE || p == PH_REPS || p == PH_PUSH || p == PH_BREATHE) {
            return BUZZ_GO;
        }
        if (p == PH_RELEASE || p == PH_RELAX) {
            return BUZZ_RELEASE;
        }
        return p == PH_DONE ? BUZZ_DONE : BUZZ_NONE;
    }

    function done() as Boolean {
        return (_segs[_cursor] & 15) == PH_DONE;
    }

    function phase() as Number {
        return _segs[_cursor] & 15;
    }

    function setKind() as Number {
        return (_segs[_cursor] >> 4) & 3;
    }

    function move() as Number {
        return (_segs[_cursor] >> 23) & 3;
    }

    function side() as Number {
        return (_segs[_cursor] >> 6) & 1;
    }

    function round() as Number {
        return (_segs[_cursor] >> 7) & 7;
    }

    function stepIndex() as Number {
        return (_segs[_cursor] >> 10) & 63;
    }

    function stretch() as Number {
        return (_segs[_cursor] >> 16) & 127;
    }

    function rounds() as Number {
        return StretchData.STEPS[routine][3 * stepIndex() + 2];
    }

    function sided() as Boolean {
        return (StretchData.META[stretch() * StretchFigure.META + 1] & StretchFigure.F_SIDED) != 0;
    }

    function kind() as Number {
        return StretchData.META[stretch() * StretchFigure.META];
    }

    function pre() as Boolean {
        return (StretchRoutines.FLAGS[routine] & RF_PRE) != 0;
    }

    // The stretch after this one, or -1 at the last
    function nextStretch() as Number {
        var k = stepIndex() + 1;
        return k < steps ? StretchData.STEPS[routine][3 * k] : -1;
    }

    function phaseMs() as Number {
        return _in;
    }

    function phaseLength() as Number {
        return _durs[_cursor];
    }

    // The hold coming up on this side, the ease-in included (with
    // contract-relax, the deeper hold)
    function holdMs() as Number {
        var best = 0;
        for (var i = _cursor; i < _segs.size() && i < _cursor + 7; i++) {
            var p = _segs[i] & 15;
            if (i > _cursor && p == PH_SETUP) {
                break;
            }
            if (p == PH_HOLD && _durs[i] + EASE > best) {
                best = _durs[i] + EASE;
            } else if ((p == PH_DEEPEN || p == PH_BREATHE) && _durs[i] > best) {
                best = _durs[i];
            }
        }
        return best;
    }

    function remaining() as Number {
        return _durs[_cursor] - _in;
    }

    // Time left in the hold, the ease-in included, for the big digits
    function holdLeft() as Number {
        var left = remaining();
        if (phase() == PH_EASE && _cursor + 1 < _segs.size()) {
            left += _durs[_cursor + 1];
        }
        return left;
    }

    // The fraction of the hold done, ease-in included, for the bezel
    function holdDone() as Float {
        var p = phase();
        if (p == PH_EASE) {
            var len = _durs[_cursor] + _durs[_cursor + 1];
            return _in.toFloat() / len;
        }
        if (p == PH_HOLD && _cursor > 0 && (_segs[_cursor - 1] & 15) == PH_EASE) {
            var len = _durs[_cursor - 1] + _durs[_cursor];
            return (_durs[_cursor - 1] + _in).toFloat() / len;
        }
        return _durs[_cursor] > 0 ? _in.toFloat() / _durs[_cursor] : 1.0;
    }

    function left() as Number {
        return total - _before - _in;
    }

    function breathingIn() as Boolean {
        return _in % BREATH < INHALE;
    }

    // The rep under way, from 1, and how many
    function rep() as Number {
        var tempo = StretchData.META[stretch() * StretchFigure.META + 5] * 100;
        var n = _in / tempo + 1;
        var reps = repCount();
        return n > reps ? reps : n;
    }

    function repCount() as Number {
        return StretchData.STEPS[routine][3 * stepIndex() + 1];
    }

    // Where the figure is between the start (0) and the stretch (1)
    function blend() as Float {
        var p = phase();
        var len = _durs[_cursor];
        if (p == PH_EASE) {
            return smooth(_in.toFloat() / len);
        }
        if (p == PH_RELEASE) {
            return 1.0 - smooth(_in.toFloat() / len);
        }
        if (p == PH_HOLD || p == PH_DEEPEN) {
            // back a touch on the breath in, deeper on the breath out
            var m = _in % BREATH;
            if (m < INHALE) {
                return 1.0 - 0.06 * smooth(m.toFloat() / INHALE);
            }
            return 0.94 + 0.06 * smooth((m - INHALE).toFloat() / (BREATH - INHALE));
        }
        if (p == PH_BREATHE) {
            var m = _in % BREATH;
            if (m < INHALE) {
                return smooth(m.toFloat() / INHALE);
            }
            return 1.0 - smooth((m - INHALE).toFloat() / (BREATH - INHALE));
        }
        if (p == PH_REPS) {
            var tempo = StretchData.META[stretch() * StretchFigure.META + 5] * 100;
            return (0.5 - 0.5 * Math.cos(2.0 * Math.PI * (_in % tempo) / tempo)).toFloat();
        }
        if (p == PH_PUSH || p == PH_RELAX) {
            return 1.0;
        }
        return 0.0;
    }

    function smooth(x as Float) as Float {
        if (x <= 0.0) {
            return 0.0;
        }
        if (x >= 1.0) {
            return 1.0;
        }
        return x * x * (3.0 - 2.0 * x);
    }

    // The coach's line
    function line() as String {
        var p = phase();
        if (p == PH_DONE) {
            return pre() ? "Now start easy, then build" : "Done · nice work";
        }
        var cues = StretchData.CUES[stretch()];
        if (p == PH_SETUP) {
            var mv = move();
            if (mv != MOVE_NONE && _in < 3000) {
                return mv == MOVE_DOWN ? "Come down to the floor" : "Stand up slowly";
            }
            if (setKind() == SET_SIDE) {
                return "Other side, same setup";
            }
            return cues[0];
        }
        if (p == PH_EASE) {
            return "Ease in · find mild tension";
        }
        if (p == PH_RELEASE) {
            return _eased ? "Ease off · smaller range" : "Slowly release";
        }
        if (p == PH_PUSH) {
            return cues.size() > 4 ? cues[4] : "Push gently · quarter effort";
        }
        if (p == PH_RELAX) {
            return "Relax · breathe out";
        }
        if (p == PH_BREATHE) {
            if (_in < BREATH) {
                return breathingIn() ? "Breathe in slowly" : "And out, slowly";
            }
            return cues[1 + (_in / BREATH) % 3];
        }
        if (p == PH_REPS) {
            var left = repCount() - rep();
            if (left == 2) {
                return "Three more";
            }
            if (left == 1) {
                return "Two more";
            }
            if (left == 0 && repCount() > 2) {
                return "Last one";
            }
            var w = _in / 6000;
            return w % 3 == 2 ? "Smooth and controlled" : cues[1 + (w - w / 3) % 3];
        }
        // a hold: the stretch's cues and the breath in turn, ten seconds before the end a warning
        var rem = remaining();
        if (rem <= 10000 && rem > 7000 && _durs[_cursor] >= 15000) {
            return "Ten seconds · keep breathing";
        }
        var w = _in / BREATH;
        if (p == PH_DEEPEN && w == 0) {
            return "Now sink a bit deeper";
        }
        if (w % 2 == 1) {
            return breathingIn() ? "Breathe in · stay tall" : "Breathe out · let go";
        }
        return cues[1 + (w / 2) % 3];
    }
}
