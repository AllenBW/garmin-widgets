import Toybox.Lang;

// What moves when a band's readings change: pure arithmetic, fed by the tests.
// A digit that changed turns like a small globe of its own (a drum), units
// first; when at least half the band's characters changed, or a reading
// changed its length, the whole band turns half a revolution instead.
module OrbMoves {

    enum Mode { NONE, TURN, DRUMS, SNAP }

    // Whether every reading keeps its length
    function sameShape(old as Array<String>, now as Array<String>) as Boolean {
        if (old.size() != now.size()) {
            return false;
        }
        for (var s = 0; s < now.size(); s++) {
            if (old[s].length() != now[s].length()) {
                return false;
            }
        }
        return true;
    }

    // Which of the band's characters changed, left to right over its readings
    // (both the same shape)
    function changed(old as Array<String>, now as Array<String>) as Array<Boolean> {
        var out = [] as Array<Boolean>;
        for (var s = 0; s < now.size(); s++) {
            var a = old[s].toCharArray();
            var b = now[s].toCharArray();
            for (var c = 0; c < b.size(); c++) {
                out.add(a[c] != b[c]);
            }
        }
        return out;
    }

    // How the band moves from `old` to `now`: not at all, a turn of the whole
    // band, drums for the digits that changed, or, when a reading changed its
    // length and turns are off, a plain change
    function mode(old as Array<String>, now as Array<String>, turns as Boolean) as Number {
        if (!sameShape(old, now)) {
            return turns ? TURN : SNAP;
        }
        var moved = changed(old, now);
        var count = 0;
        for (var i = 0; i < moved.size(); i++) {
            if (moved[i]) {
                count++;
            }
        }
        if (count == 0) {
            return NONE;
        }
        return (turns && count * 2 >= moved.size()) ? TURN : DRUMS;
    }

    // Each changed digit's delay in ms, units first: `step` for every changed
    // digit to its right; -1 for one that stays
    function delays(moved as Array<Boolean>, step as Number) as Array<Number> {
        var out = new [moved.size()] as Array<Number>;
        var right = 0;
        for (var i = moved.size() - 1; i >= 0; i--) {
            if (moved[i]) {
                out[i] = right * step;
                right++;
            } else {
                out[i] = -1;
            }
        }
        return out;
    }
}
