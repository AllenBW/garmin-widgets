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
    var pebbles as Array<Array<Number>> = [] as Array<Array<Number>>;    // [x, y, rx, ry], scattered order

    // The samples stay in Field's constant arrays, scaled as they are read:
    // a scaled copy of all 3,005 took about 38 KB of the face's 128 KB.
    // Pieces 0 to count() - 1 are the layers, top piece first; the rest,
    // always-on's.
    // (StrataView.drawLayers reads them directly: a call per sample would
    // spend the watchdog's allowance)
    var chunks as Array<Array<Number>> = [] as Array<Array<Number>>;
    var offsets as Array<Number> = [] as Array<Number>;                 // each piece's first sample
    var f as Float = 0.1;                                                // tenths of a generated px to screen px

    function initialize(w as Number, h as Number) {
        scale = w.toFloat() / Field.SIZE;
        step = Field.STEP * scale;
        f = scale / 10.0;
        chunks = Field.chunks();
        var at = 0;
        for (var k = 0; k < Field.LENGTH.size(); k++) {
            offsets.add(at);
            at += Field.LENGTH[k];
        }
        for (var k = 0; k < Field.AOD_LENGTH.size(); k++) {
            offsets.add(at);
            at += Field.AOD_LENGTH[k];
        }
        for (var p = 0; p + 3 < Field.PEBBLES.size(); p += 4) {
            pebbles.add([
                (Field.PEBBLES[p] * scale).toNumber(),
                (Field.PEBBLES[p + 1] * scale).toNumber(),
                (Field.PEBBLES[p + 2] * scale).toNumber(),
                (Field.PEBBLES[p + 3] * scale).toNumber()
            ]);
        }
    }

    // How many pieces the layers come in, and always-on's after them
    function count() as Number {
        return Field.LENGTH.size();
    }

    function aodCount() as Number {
        return Field.AOD_LENGTH.size();
    }

    // Piece k's first sample's x, and its number of samples
    function start(k as Number) as Float {
        return ((k < count()) ? Field.FIRST[k] : Field.AOD_FIRST[k - count()]) * step;
    }

    function length(k as Number) as Number {
        return (k < count()) ? Field.LENGTH[k] : Field.AOD_LENGTH[k - count()];
    }

    // Piece k's y at sample i
    function y(k as Number, i as Number) as Float {
        var n = offsets[k] + i;
        return chunks[n / Field.CHUNK][n % Field.CHUNK] * f;
    }

    // True for the accent layers (every fourth, like the planter's deep score)
    function isAccent(k as Number) as Boolean {
        return k < count() && Field.ACCENT[k] == 1;
    }
}
