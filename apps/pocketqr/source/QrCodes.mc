import Toybox.Application;
import Toybox.Lang;

// One saved code: the name the user gave it and the text the QR encodes
(:glance)
class QrCode {
    var name as String;
    var value as String;

    function initialize(name as String, value as String) {
        self.name = name;
        self.value = value;
    }
}

// The codes come from the "Codes" array setting: each entry is a dictionary
// with "name" and "value" strings, edited as a list in the Connect IQ app.
(:glance)
module QrCodes {

    const MAX = 6;
    const KEY = "Codes";

    // The saved codes in order, without empty or malformed entries
    function load() as Array<QrCode> {
        var raw = null;
        try {
            raw = Application.Properties.getValue(KEY);
        } catch (e) {
            raw = null;
        }
        return parse(raw);
    }

    // Accepts whatever the property holds (or a test literal); anything but an array of dictionaries is ignored
    function parse(raw as Object?) as Array<QrCode> {
        var codes = [] as Array<QrCode>;
        if (!(raw instanceof Array)) {
            return codes;
        }
        var list = raw as Array<Object?>;
        for (var i = 0; i < list.size() && codes.size() < MAX; i++) {
            var entry = list[i];
            if (!(entry instanceof Dictionary)) {
                continue;
            }
            var dict = entry as Dictionary<Object, Object?>;
            var value = text(dict.get("value"));
            if (value.length() == 0) {
                continue;
            }
            var name = text(dict.get("name"));
            if (name.length() == 0) {
                name = "Code " + (codes.size() + 1);
            }
            codes.add(new QrCode(name, value));
        }
        return codes;
    }

    // A string with the spaces at both ends removed; anything else is ""
    function text(v as Object?) as String {
        if (!(v instanceof String)) {
            return "";
        }
        var chars = v.toCharArray();
        var a = 0;
        var b = chars.size();
        while (a < b && chars[a] == ' ') {
            a++;
        }
        while (b > a && chars[b - 1] == ' ') {
            b--;
        }
        if (a == 0 && b == chars.size()) {
            return v;
        }
        var trimmed = v.substring(a, b);
        return (trimmed == null) ? "" : trimmed;
    }

    // What the content is, from its prefix: the phone treats these specially
    function kind(value as String) as String {
        var u = value.toUpper();
        if (u.find("WIFI:") == 0) {
            return "Wi-Fi";
        }
        if (u.find("HTTP://") == 0 || u.find("HTTPS://") == 0) {
            return "Link";
        }
        if (u.find("BEGIN:VCARD") == 0 || u.find("MECARD:") == 0) {
            return "Contact";
        }
        if (u.find("MAILTO:") == 0) {
            return "Email";
        }
        if (u.find("TEL:") == 0) {
            return "Phone";
        }
        return "Text";
    }

    // The glance's second line: "3 codes · Wi-Fi, Link, Text" (three kinds, then …)
    function summary(codes as Array<QrCode>) as String {
        var n = codes.size();
        if (n == 0) {
            return "add them in the Connect IQ app";
        }
        var s = n + (n == 1 ? " code · " : " codes · ");
        for (var i = 0; i < n && i < 3; i++) {
            s += (i > 0 ? ", " : "") + kind(codes[i].value);
        }
        return n > 3 ? s + "…" : s;
    }
}
