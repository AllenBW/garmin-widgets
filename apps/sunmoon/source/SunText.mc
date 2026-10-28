import Toybox.Lang;

// The words on the glance and the app, so both say the same thing
(:glance)
module SunText {

    // "Sunset 17:41"
    function headline(s as SunStatus) as String {
        var next = s.nextEvent;
        if (next == null) {
            return s.located ? "No sunset today" : "No location yet";
        }
        return (s.nextIsRise ? "Sunrise " : "Sunset ") + Lib.GlanceFmt.clockAt(next);
    }

    // "golden hour in 6h 48m" / "golden hour, ends in 23m"
    function goldenLine(s as SunStatus, now as Number) as String {
        var at = s.goldenAt;
        if (at == null) {
            return s.located ? "no golden hour today" : "sync the phone or record a GPS activity";
        }
        if (s.goldenNow) {
            return "golden hour, ends in " + Lib.GlanceFmt.countdown(at - now);
        }
        return "golden hour in " + Lib.GlanceFmt.countdown(at - now);
    }
}
