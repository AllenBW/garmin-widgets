import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Time;

// The last reading, kept for the glance: [dB, unix time, the band's name].
// Shared by the glance and the app, so no meter code is needed here.
(:glance)
module SoundStore {

    const KEY = "last";
    const DB = 0;
    const AT = 1;
    const NAME = 2;

    function save(db as Number, unix as Number, name as String) as Void {
        Storage.setValue(KEY, [db, unix, name] as Array<Storage.ValueType>);
    }

    function clear() as Void {
        Storage.deleteValue(KEY);
    }

    // The saved reading, or null when there is none or it looks wrong
    function last() as Array<Storage.ValueType>? {
        var v = Storage.getValue(KEY);
        if (!(v instanceof Array) || v.size() != 3) {
            return null;
        }
        if (!(v[DB] instanceof Number) || !(v[AT] instanceof Number) || !(v[NAME] instanceof String)) {
            return null;
        }
        return v as Array<Storage.ValueType>;
    }

    // "just now", "4 min ago", "3 h ago", "2 days ago"
    function ago(unix as Number) as String {
        var s = Time.now().value() - unix;
        if (s < 90) {
            return "just now";
        }
        if (s < 3600) {
            return (s / 60) + " min ago";
        }
        if (s < 86400) {
            return (s / 3600) + " h ago";
        }
        var days = s / 86400;
        return days == 1 ? "yesterday" : days + " days ago";
    }
}
