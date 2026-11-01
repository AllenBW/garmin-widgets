import Toybox.Lang;

// The words on the glance and the app, so both say the same thing
(:glance)
module SunText {

    // "Sunset 17:41"
    function headline(s as SunStatus) as String {
        var next = s.nextEvent;
        if (next == null) {
            if (!s.located) {
                return "No location yet";
            }
            return s.up ? "No sunset today" : "No sunrise today";
        }
        return (s.nextIsRise ? "Sunrise " : "Sunset ") + Lib.Fmt.clockAt(next);
    }

    // "golden hour in 6h 48m" / "golden hour, ends in 23m"
    function goldenLine(s as SunStatus, now as Number) as String {
        var at = s.goldenAt;
        if (at == null) {
            return s.located ? "no golden hour soon" : "sync phone or use GPS";
        }
        if (s.goldenNow) {
            return "golden, ends in " + Lib.Fmt.countdown(at - now);
        }
        return "golden hour in " + Lib.Fmt.countdown(at - now);
    }
}
