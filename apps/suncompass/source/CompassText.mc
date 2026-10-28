import Toybox.Lang;

// The words for a SunSky, shared by the glance and the app
(:glance)
module CompassText {

    // "Sun 148° SE", "Sun below horizon", "No location yet"
    function headline(s as SunSky) as String {
        if (!s.located) {
            return "No location yet";
        }
        if (!s.up) {
            return "Sun below horizon";
        }
        return "Sun " + degrees(s.az) + " " + CompassModel.cardinal(s.az);
    }

    // "31° up, sets 17:41 at 232°", "rises 7:12 at 108°", "up all day"
    function detail(s as SunSky) as String {
        if (!s.located) {
            return "sync the phone or use GPS";
        }
        if (s.up && s.nextEvent != null) {
            return degrees(s.alt) + " up, " + nextLine(s);
        }
        return nextLine(s);
    }

    // "sets 17:41 at 232°", "rises 7:12 at 108°", or the polar cases
    function nextLine(s as SunSky) as String {
        var at = s.nextEvent;
        var az = s.nextAz;
        if (!s.located) {
            return "no location yet";
        }
        if (at == null || az == null) {
            return s.up ? "up all day" : "down all day";
        }
        return (s.nextIsRise ? "rises " : "sets ") + Lib.Fmt.clockAt(at) + " at " + degrees(az);
    }

    // "148°": a bearing or altitude to the nearest degree, 360 shown as 0
    function degrees(value as Float) as String {
        var whole = (value + (value >= 0.0 ? 0.5 : -0.5)).toNumber();
        if (whole == 360) {
            whole = 0;
        }
        return whole.toString() + "°";
    }
}
