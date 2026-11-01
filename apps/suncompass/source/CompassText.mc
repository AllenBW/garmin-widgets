import Toybox.Lang;
import Toybox.System;

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

    // The glance's short line: "sets 17:41 · 232°", "rises 7:12 · 108°",
    // "up all day"; the headline already says where the sun is
    function detail(s as SunSky) as String {
        if (!s.located) {
            return "sync phone or use GPS";
        }
        var at = s.nextEvent;
        var az = s.nextAz;
        if (at == null || az == null) {
            return nextLine(s);
        }
        return (s.nextIsRise ? "rises " : "sets ") + Lib.Fmt.clockAt(at) + " · " + degrees(az);
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

    // The label for a full hour on the path: "15", or "3" on a 12-hour watch
    function hourLabel(hour as Number) as String {
        if (System.getDeviceSettings().is24Hour) {
            return hour.toString();
        }
        var h = hour % 12;
        return ((h == 0) ? 12 : h).toString();
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
