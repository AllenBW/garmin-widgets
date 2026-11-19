import Toybox.Lang;

module Lib {

    // How a neon tube comes on, and how it goes out: the neon faces' number
    // transition (Sign, Edge, Noir). A tube that is struck stutters once or
    // twice, unevenly, at a part of its brightness with a dim ember between,
    // then warms to full: the core first, the halo after it, so the glow
    // seems to spread. A tube that dies dips, flickers back once and fades.
    // It is a tube warming up, not a strobe: no stutter reaches full
    // brightness, and the halo stays under a third of its own until the
    // tube has caught.
    //
    // Pure arithmetic in whole numbers, no drawing and no clock
    // (designs/preview_sign.py has the same tables and draws the previews
    // from them; the tests hold the two together):
    //
    //   Strike.lit(t, seed)    [core, halo] in percent, t ms after the strike
    //   Strike.dying(t)        [core, halo] in percent, t ms after it began to die
    //   Strike.settled(t, seed)  the strike is over: draw the tube as usual
    //   Strike.dead(t)           the dying tube is out: draw nothing
    //   Strike.LONGEST, Strike.DEATH   the longest strike and a death, in ms
    //
    // `seed` is any small number that differs between the tubes on a face (a
    // numeral's place, say): it picks one of the patterns and a short wait
    // before the strike, so two tubes never flicker in step. A percent
    // scales a colour (Lib.Neon.wash(colour, 0, percent)): the halo's tint
    // by the halo's, the core's by the core's. When a number changes while
    // the face is awake, the old tube dies for DEATH ms and the new one is
    // struck at t - DEATH; before its wait is over a tube is dark ([0, 0]).
    // Every stutter lasts at least 70 ms, longer than a frame on the watch
    // (about 63 ms), so none can fall between two frames.
    (:strike)
    module Strike {

        const EMBER_CORE = 12;     // between stutters the tube is not black
        const EMBER_HALO = 5;
        const RAMP = 15;           // ms a stutter takes to come on or drop
        const WAIT = 35;           // ms between the tubes' strikes
        const DEATH = 280;         // ms a dying tube takes
        const LONGEST = 965;       // ms the longest strike takes, its wait included

        // The patterns: [ms, core, halo] corners, straight lines between,
        // each ending at full brightness
        const PATTERNS = [
            // two stutters, the second longer and brighter
            [0, 55, 18, 90, 55, 18, 105, 12, 5, 190, 12, 5, 205, 70, 28, 290, 70, 28, 305, 12, 5, 360, 12, 5,
             375, 50, 20, 500, 78, 42, 680, 93, 75, 860, 100, 100] as Array<Number>,
            // a short one, a long dark, a long one
            [0, 45, 14, 70, 45, 14, 85, 12, 5, 200, 12, 5, 215, 75, 30, 330, 75, 30, 345, 12, 5, 390, 12, 5,
             405, 55, 22, 520, 80, 45, 690, 94, 78, 850, 100, 100] as Array<Number>,
            // one stutter, then it catches with a dip on the way up
            [0, 60, 20, 110, 60, 20, 125, 12, 5, 230, 12, 5, 245, 45, 16, 330, 70, 30, 380, 50, 22, 430, 72, 34,
             560, 85, 55, 720, 95, 82, 840, 100, 100] as Array<Number>
        ] as Array<Array<Number>>;

        // A death: a dip, one flicker back, and out
        const DYING = [0, 100, 100, 50, 85, 60, 70, 20, 8, 120, 20, 8, 140, 60, 30, 190, 45, 18, 280, 0, 0] as Array<Number>;

        // The wait before a tube with this seed is struck
        function wait(seed as Number) as Number {
            return ((seed * 37) % 4) * WAIT;
        }

        // A struck tube's brightness, [core, halo] in percent, `t` ms after
        // the strike
        function lit(t as Number, seed as Number) as Array<Number> {
            t -= wait(seed);
            if (t < 0) {
                return [0, 0] as Array<Number>;
            }
            return along(PATTERNS[seed % PATTERNS.size()], t, 100);
        }

        // A dying tube's brightness, [core, halo] in percent, `t` ms after it
        // began to die
        function dying(t as Number) as Array<Number> {
            if (t < 0) {
                return [100, 100] as Array<Number>;
            }
            return along(DYING, t, 0);
        }

        // Whether a strike is over
        function settled(t as Number, seed as Number) as Boolean {
            var p = PATTERNS[seed % PATTERNS.size()];
            return t - wait(seed) >= p[p.size() - 3];
        }

        // Whether a dying tube is out
        function dead(t as Number) as Boolean {
            return t >= DEATH;
        }

        // The table's value at `t`: on the line between the corners either
        // side of it, `last` past the end
        function along(table as Array<Number>, t as Number, last as Number) as Array<Number> {
            var n = table.size();
            if (t >= table[n - 3]) {
                return [last, last] as Array<Number>;
            }
            var i = 3;
            while (table[i] <= t) {
                i += 3;
            }
            var t0 = table[i - 3];
            var span = table[i] - t0;
            return [table[i - 2] + (table[i + 1] - table[i - 2]) * (t - t0) / span,
                    table[i - 1] + (table[i + 2] - table[i - 1]) * (t - t0) / span] as Array<Number>;
        }
    }
}
