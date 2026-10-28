import Toybox.Lang;
import Toybox.UserProfile;

// Activity time per day from the watch's activity history, to explain a
// heavy-drain day. Foreground only (the glance does not need it).
module BatteryActivity {

    const MAX_ACTIVITIES = 100;

    // Hours of recorded activity that started on the day beginning at dayStart
    function hoursOn(dayStart as Number) as Float {
        if (!(Toybox has :UserProfile) || !(UserProfile has :getUserActivityHistory)) {
            return 0.0;
        }
        var seconds = 0;
        var iterator = UserProfile.getUserActivityHistory();
        var activity = iterator.next() as UserActivity?;
        var seen = 0;
        while (activity != null && seen < MAX_ACTIVITIES) {
            var start = activity.startTime;
            var duration = activity.duration;
            if (start != null && duration != null) {
                var t = start.value();
                if (t >= dayStart && t < dayStart + 86400) {
                    seconds += duration.value();
                }
            }
            activity = iterator.next() as UserActivity?;
            seen++;
        }
        return seconds / 3600.0;
    }
}
