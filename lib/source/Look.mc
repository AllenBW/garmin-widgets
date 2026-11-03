import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

module Lib {

    // A face's look: the settings as chosen (YOURS), two looks for seeing it
    // easily (BRIGHT, high visibility: white and fluorescent orange, the
    // readings larger; LOW, low light: the same sizes in warm cream), and
    // DAILY, one of the face's personas, the next each day. Holding the time
    // steps through them in that order; the phone app's "Look" setting
    // picks one too, and whichever was changed last wins. Each face draws
    // the looks its own way; this keeps which one is on.
    (:look)
    module Look {

        enum Mode { YOURS, BRIGHT, LOW, DAILY }
        const MODES = 4;
        const SHOWN = 2500;        // ms the look's name stands in for the date after a hold

        // The looks' colours
        const BLAZE = 0xFF6A13;    // fluorescent orange: high visibility's accent
        const VOLT = 0x5CFF2E;     // fluorescent green
        const FLARE = 0xD4FF1A;    // fluorescent yellow-green
        const WHITE = 0xFFFFFF;
        const CREAM = 0xF0D2A8;    // low light's text
        const GLOW = 0xFF9A3C;     // and its accent

        const KEY = "Look";        // the phone's setting, and in storage the look on now
        const SEEN = "LookSeen";   // the phone's setting when last taken up

        var changedAt as Number? = null;

        // The look on now
        function mode() as Number {
            var m = Application.Storage.getValue(KEY);
            if (!(m instanceof Number)) {
                m = Application.Properties.getValue(KEY);
            }
            return (m instanceof Number && m >= 0 && m < MODES) ? m : YOURS;
        }

        // A hold on the time: the next look, its name shown for a moment
        function next() as Number {
            var m = (mode() + 1) % MODES;
            Application.Storage.setValue(KEY, m);
            changedAt = System.getTimer();
            return m;
        }

        // From onSettingsChanged: a new choice of look in the phone app wins
        // over the last hold; a change to another setting leaves it be
        function changedOnPhone() as Void {
            var phone = Application.Properties.getValue(KEY);
            var seen = Application.Storage.getValue(SEEN);
            if (phone instanceof Number && phone != ((seen instanceof Number) ? seen : YOURS)) {
                Application.Storage.setValue(SEEN, phone);
                Application.Storage.setValue(KEY, phone);
            }
        }

        // Whether the look's name is still showing after a hold
        function shown() as Boolean {
            var at = changedAt;
            return at != null && System.getTimer() - at < SHOWN;
        }

        // Today's persona of `count`, the next one each day
        function day(count as Number) as Number {
            return dayOf(Time.today().value() / 86400, count);
        }

        function dayOf(days as Number, count as Number) as Number {
            var p = days % count;
            return (p < 0) ? p + count : p;
        }

        // The look's name, in capitals: a persona's from `names`
        function title(m as Number, names as Array<String>) as String {
            if (m == BRIGHT) {
                return "HIGH VIS";
            }
            if (m == LOW) {
                return "LOW LIGHT";
            }
            if (m == DAILY) {
                return names[day(names.size())];
            }
            return "YOUR LOOK";
        }
    }
}
