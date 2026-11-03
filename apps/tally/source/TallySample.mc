import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Time;

// Made-up buttons and two weeks of entries for the simulator and the store
// pictures (sample.jungle): coffee in the morning and after lunch,
// medicine at 8 and 8, snacks, dinner about 5:40, water through the day,
// some nausea, and a headache about 7:50 on most evenings. Normal builds leave this out.
(:glance)
module TallySample {

    (:live)
    function load() as Void {
    }

    // The page the app opens on: the sample build can open on any of them
    // for a capture (an extra jungle that excludes the other two)
    (:live)
    function page() as Number {
        return 0;   // PAGE_LOG (the enum is not in the glance's scope)
    }

    (:sample, :shotlog)
    function page() as Number {
        return 0;   // PAGE_LOG (the enum is not in the glance's scope)
    }

    (:sample, :shotrings)
    function page() as Number {
        return 1;   // PAGE_RINGS
    }

    (:sample, :shotstrip)
    function page() as Number {
        return 2;   // PAGE_STRIP
    }

    (:sample, :shotbefore)
    function page() as Number {
        return 3;   // PAGE_BEFORE
    }

    (:sample, :shotglance)
    function page() as Number {
        return -1;
    }

    (:sample)
    function load() as Void {
        if (TallyLog.count() > 0) {
            return;
        }
        Math.srand(4);
        var now = Time.now().value();
        var midnight = now - Lib.Fmt.localSeconds(now);
        var plan = [["Coffee", 8.2, 0.3, 100], ["Coffee", 13.4, 0.3, 70], ["Medicine", 8.1, 0.2, 95],
                    ["Medicine", 20.0, 0.2, 90], ["Snack", 10.6, 0.6, 60], ["Snack", 15.6, 0.6, 60],
                    ["Dinner", 17.7, 0.25, 100], ["Water", 10.5, 1.5, 100], ["Water", 15.0, 1.5, 100],
                    ["Nausea", 19.4, 0.3, 40], ["Headache", 19.85, 0.25, 80], ["Bed", 22.6, 0.3, 100]] as Array<Array>;
        for (var d = 13; d >= 0; d--) {
            var day = midnight - d * 86400;
            var times = [] as Array<Number>;
            var names = [] as Array<String>;
            for (var k = 0; k < plan.size(); k++) {
                var p = plan[k];
                if (Math.rand() % 100 >= (p[3] as Number)) {
                    continue;
                }
                var t = day + ((p[1] as Float) + (p[2] as Float) * wobble()) * 3600;
                if (t.toNumber() < now - 30 * 60) {
                    // in time order: insert
                    var i = times.size();
                    while (i > 0 && times[i - 1] > t.toNumber()) {
                        i--;
                    }
                    times = times.slice(0, i).addAll([t.toNumber()]).addAll(times.slice(i, null));
                    names = names.slice(0, i).addAll([p[0] as String]).addAll(names.slice(i, null));
                }
            }
            for (var i = 0; i < times.size(); i++) {
                TallyLog.add(times[i], names[i]);
            }
        }
        TallyLog.confirm(TallyLog.count());
        Storage.setValue("picked", "Headache");
        // the glance's line, as TallyView writes it after a tap
        var log = TallyLog.since(now - 86400 * 14);
        var n = log[0].size();
        if (n > 0) {
            var name = TallyLog.names()[log[1][n - 1]];
            var colours = {"Coffee" => 0xFFB020, "Water" => 0x5AB4FF, "Medicine" => 0xA88BFF, "Snack" => 0xA8E05F,
                           "Nausea" => 0xFF7EB6, "Dinner" => 0xF2ECE2, "Headache" => 0xFF6B5A, "Bed" => 0x7A8CFF};
            Storage.setValue(TallyLog.LAST, [log[0][n - 1], name, colours[name] as Number, (name.equals("Headache")) ? 3 : 14]);
        }
    }

    // Roughly normal, -1.7 .. 1.7
    (:sample)
    function wobble() as Float {
        var s = 0.0;
        for (var i = 0; i < 3; i++) {
            s += (Math.rand() % 1000) / 1000.0;
        }
        return (s - 1.5) * 1.15;
    }
}
