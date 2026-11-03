import Toybox.Application;
import Toybox.Lang;

// One button as the owner set it up on the phone (Garmin Connect, the
// app's settings, Button 1 to 12): a name, a colour, a size, and the hours
// it shows on the main screen. Every button is always in the All list.
class TallyButton {
    var name as String;
    var colour as Number;
    var from as Number;     // the hour it appears, or ALWAYS
    var until as Number;    // the hour it goes, 1 .. 24; may be past midnight
    var size as Number;     // places it takes in the ring: 1 normal, 2 large

    function initialize(name as String, colour as Number, from as Number, until as Number, size as Number) {
        self.name = name;
        self.colour = colour;
        self.from = from;
        self.until = until;
        self.size = size;
    }

    // Shown at this hour (0 .. 23)?
    function shownAt(hour as Number) as Boolean {
        if (from == TallyButtons.ALWAYS || from % 24 == until % 24) {
            return true;
        }
        var start = from % 24;
        var end = until % 24;
        return (start < end) ? (hour >= start && hour < end) : (hour >= start || hour < end);
    }
}

module TallyButtons {

    const ALWAYS = -1;
    // Places in the main screen's ring: each of the four quarters split in
    // two. At eight a wedge is about 6 mm across at its inner edge and 12 at
    // its outer on the 47 mm watch, and a nine-letter name fits; at twelve
    // the inner edge would be 4 mm, too small to hit.
    const PLACES = 8;

    // The phone's colour list, in its order (designs/gen_tally_settings.py)
    const COLOURS = [0xFF6B5A, 0xFFB020, 0xA8E05F, 0x4FD1A5, 0x5AB4FF, 0xA88BFF, 0xFF7EB6, 0xF2ECE2,
                     0xFF8A3D, 0x3FC8C8, 0x7A8CFF, 0xF5E05A] as Array<Number>;
    const OTHER = 0x9A9A9A;     // a name logged with Other, or a button since renamed

    const SLOTS = 12;

    // Every button, in the phone's order; empty slots are skipped
    (:live)
    function all() as Array<TallyButton> {
        var out = [] as Array<TallyButton>;
        for (var i = 1; i <= SLOTS; i++) {
            var b = parse({"name" => Properties.getValue("B" + i + "Name"), "colour" => Properties.getValue("B" + i + "Colour"),
                           "from" => Properties.getValue("B" + i + "From"), "until" => Properties.getValue("B" + i + "Until"),
                           "size" => Properties.getValue("B" + i + "Size")});
            if (b != null) {
                out.add(b);
            }
        }
        return out;
    }

    // The sample build's buttons (TallySample)
    (:sample)
    function all() as Array<TallyButton> {
        return [new TallyButton("Coffee", COLOURS[1], 6, 15, 1), new TallyButton("Water", COLOURS[4], ALWAYS, 24, 1),
                new TallyButton("Medicine", COLOURS[5], 7, 10, 1), new TallyButton("Snack", COLOURS[2], ALWAYS, 24, 1),
                new TallyButton("Headache", COLOURS[0], ALWAYS, 24, 2), new TallyButton("Nausea", COLOURS[6], ALWAYS, 24, 1),
                new TallyButton("Dinner", COLOURS[7], 16, 21, 1), new TallyButton("Medicine", COLOURS[5], 19, 22, 1),
                new TallyButton("Bed", COLOURS[10], 19, 24, 1)] as Array<TallyButton>;
    }

    function parse(entry as Dictionary<String, Object?>) as TallyButton? {
        var name = entry["name"];
        if (!(name instanceof String)) {
            return null;
        }
        name = trim(name);
        if (name.length() == 0) {
            return null;
        }
        return new TallyButton(name, colour(entry["colour"]), number(entry["from"], ALWAYS), number(entry["until"], 24),
                               (number(entry["size"], 1) == 2) ? 2 : 1);
    }

    function colour(index as Object?) as Number {
        var i = number(index, 0);
        return (i >= 0 && i < COLOURS.size()) ? COLOURS[i] : COLOURS[0];
    }

    function number(v as Object?, fallback as Number) as Number {
        return (v instanceof Number) ? v : (v instanceof String && v.toNumber() != null) ? v.toNumber() as Number : fallback;
    }

    function trim(s as String) as String {
        var chars = s.toCharArray();
        var a = 0;
        var b = chars.size();
        while (a < b && chars[a] == ' ') {
            a++;
        }
        while (b > a && chars[b - 1] == ' ') {
            b--;
        }
        return s.substring(a, b) as String;
    }

    // The colour a logged name draws in: its button's, or grey
    function colourOf(name as String, buttons as Array<TallyButton>) as Number {
        for (var i = 0; i < buttons.size(); i++) {
            if (buttons[i].name.equals(name)) {
                return buttons[i].colour;
            }
        }
        return OTHER;
    }

    // The main screen's buttons at this hour, in the phone's order. Past
    // PLACES (a large button takes two), the ones most often logged around
    // this hour stay; `usual` gives that count per button.
    function onScreen(buttons as Array<TallyButton>, hour as Number, usual as Array<Number>) as Array<TallyButton> {
        var shown = [] as Array<Number>;
        for (var i = 0; i < buttons.size(); i++) {
            if (buttons[i].shownAt(hour)) {
                shown.add(i);
            }
        }
        while (places(buttons, shown) > PLACES) {
            // drop the least used, the later one on a tie
            var worst = shown.size() - 1;
            for (var k = shown.size() - 2; k >= 0; k--) {
                if (usual[shown[k]] < usual[shown[worst]]) {
                    worst = k;
                }
            }
            shown.remove(shown[worst]);
        }
        var out = [] as Array<TallyButton>;
        for (var k = 0; k < shown.size(); k++) {
            out.add(buttons[shown[k]]);
        }
        return out;
    }

    function places(buttons as Array<TallyButton>, which as Array<Number>) as Number {
        var n = 0;
        for (var k = 0; k < which.size(); k++) {
            n += buttons[which[k]].size;
        }
        return n;
    }

    // Each wedge's first place in a ring of `total` places: [starts, total]
    function starts(shown as Array<TallyButton>) as [Array<Number>, Number] {
        var out = [] as Array<Number>;
        var total = 0;
        for (var i = 0; i < shown.size(); i++) {
            out.add(total);
            total += shown[i].size;
        }
        return [out, total];
    }

    // Which wedge holds `angle` (degrees clockwise from 12 o'clock), with
    // the first wedge centred at the top
    function wedgeAt(shown as Array<TallyButton>, angle as Float) as Number {
        var s = starts(shown);
        var total = s[1];
        if (total == 0) {
            return -1;
        }
        var place = 360.0 / total;
        var a = angle + shown[0].size * place / 2;
        while (a < 0) {
            a += 360;
        }
        while (a >= 360) {
            a -= 360;
        }
        for (var i = shown.size() - 1; i >= 0; i--) {
            if (a >= s[0][i] * place) {
                return i;
            }
        }
        return 0;
    }
}
