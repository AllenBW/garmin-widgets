import Toybox.Lang;

// The words and numbers on the Readiness face
module ReadinessText {

    // "74", or "--" when unknown
    function score(value as Number?) as String {
        return (value != null) ? value.toString() : "--";
    }

    // "14h" (rounded up), "45m" under an hour, "ready" at zero, "--" unknown
    function recovery(minutes as Number?) as String {
        if (minutes == null) {
            return "--";
        }
        if (minutes <= 0) {
            return "ready";
        }
        if (minutes < 60) {
            return minutes.toString() + "m";
        }
        return ((minutes + 59) / 60).toString() + "h";
    }

    // "Training: Productive", or nothing when the watch has no status
    function training(status as String?) as String {
        return (status != null && status.length() > 0) ? "Training: " + status : "";
    }

    // The always-on line: "BB 74 · SLEEP 82"
    function summary(r as Readings) as String {
        return "BB " + score(r.bodyBattery) + " · SLEEP " + score(r.sleepScore);
    }
}
