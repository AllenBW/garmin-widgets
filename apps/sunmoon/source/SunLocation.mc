import Toybox.Activity;
import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Weather;

// The last known position, as [latitude, longitude] in degrees: the weather
// observation point when the phone has synced, else the last GPS fix the
// watch has (from an activity, or the system's last fix), else what this
// app saved last time. Null until one of those has ever existed.
(:glance)
module SunLocation {

    const LAT_KEY = "lat";
    const LON_KEY = "lon";

    function get() as [Float, Float]? {
        var fresh = live();
        if (fresh != null) {
            remember(fresh);
            return fresh;
        }
        var lat = Storage.getValue(LAT_KEY);
        var lon = Storage.getValue(LON_KEY);
        if (lat instanceof Float && lon instanceof Float) {
            return [lat, lon];
        }
        return null;
    }

    function live() as [Float, Float]? {
        var position = null;
        if (Toybox has :Weather) {
            var conditions = Weather.getCurrentConditions();
            if (conditions != null) {
                position = conditions.observationLocationPosition;
            }
        }
        if (position == null) {
            var info = Activity.getActivityInfo();
            if (info != null) {
                position = info.currentLocation;
            }
        }
        if (position == null && (Toybox has :Position)) {
            // The system's last fix; no GPS is switched on for this
            var fix = Position.getInfo();
            if (fix.accuracy != null && fix.accuracy != Position.QUALITY_NOT_AVAILABLE) {
                position = fix.position;
            }
        }
        if (position == null) {
            return null;
        }
        var degrees = position.toDegrees();
        return [degrees[0].toFloat(), degrees[1].toFloat()];
    }

    // Save a position when it differs from the saved one (storage writes are slow)
    function remember(where as [Float, Float]) as Void {
        var lat = Storage.getValue(LAT_KEY);
        var lon = Storage.getValue(LON_KEY);
        if (lat instanceof Float && lon instanceof Float && (lat - where[0]).abs() < 0.01 && (lon - where[1]).abs() < 0.01) {
            return;
        }
        Storage.setValue(LAT_KEY, where[0]);
        Storage.setValue(LON_KEY, where[1]);
    }
}
