import Toybox.Lang;

// The soil layers from the owner's laser-cut planter (good-tools,
// wall-planter, pattern "Strata"), generated offline by
// designs/gen_strata.py into Field.mc and scaled here to the screen: a
// face may not spend the time the noise takes (the watchdog trips). Lines
// run across the disc, parting round a clearing for each reading and cut
// where one would still touch it, so a layer may come in pieces; each one
// is the line above plus a gap the noise squeezed or opened; every fourth
// line is the accent; pebbles sit where the layers open up. Always-on has
// its own few layers, parted only round what it shows. The data colours
// the layers and decides how many pebbles show.
class Layers {

    var scale as Float = 1.0;                                            // screen px per generated px
    var step as Float = 8.0;                                             // px between samples along a line
    var starts as Array<Float> = [] as Array<Float>;                     // x of each piece's first sample
    var lines as Array<Array<Float>> = [] as Array<Array<Float>>;        // y at each sample, top piece first
    var aodStarts as Array<Float> = [] as Array<Float>;                  // the same for always-on's pieces
    var aodLines as Array<Array<Float>> = [] as Array<Array<Float>>;
    var pebbles as Array<Array<Number>> = [] as Array<Array<Number>>;    // [x, y, rx, ry], scattered order

    function initialize(w as Number, h as Number) {
        scale = w.toFloat() / Field.SIZE;
        step = Field.STEP * scale;
        var chunks = Field.chunks();
        var at = read(chunks, 0, Field.FIRST, Field.LENGTH, starts, lines);
        read(chunks, at, Field.AOD_FIRST, Field.AOD_LENGTH, aodStarts, aodLines);
        for (var p = 0; p + 3 < Field.PEBBLES.size(); p += 4) {
            pebbles.add([
                (Field.PEBBLES[p] * scale).toNumber(),
                (Field.PEBBLES[p + 1] * scale).toNumber(),
                (Field.PEBBLES[p + 2] * scale).toNumber(),
                (Field.PEBBLES[p + 3] * scale).toNumber()
            ]);
        }
    }

    // Read the pieces `firsts` and `lengths` describe, from sample `at` on,
    // into `xs` and `ys`, scaled. Returns the sample after the last.
    private function read(chunks as Array<Array<Number>>, at as Number, firsts as Array<Number>, lengths as Array<Number>,
                          xs as Array<Float>, ys as Array<Array<Float>>) as Number {
        for (var k = 0; k < firsts.size(); k++) {
            xs.add(firsts[k] * step);
            var piece = [] as Array<Float>;
            for (var i = 0; i < lengths[k]; i++) {
                var n = at + i;
                piece.add(chunks[n / Field.CHUNK][n % Field.CHUNK] * scale / 10.0);
            }
            at += lengths[k];
            ys.add(piece);
        }
        return at;
    }

    // True for the accent layers (every fourth, like the planter's deep score)
    function isAccent(k as Number) as Boolean {
        return Field.ACCENT[k] == 1;
    }
}
