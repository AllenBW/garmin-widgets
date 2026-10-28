import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

// Battery Planner (designs/DESIGNS.md, design #2): when do I need to charge,
// from the battery's actual drain over the last week rather than the
// spec-sheet estimate. A background service logs the level every half hour;
// the glance shows the time left and the charge-by date, the app adds the
// daily drain bars.
//
// The class runs in three places, so it carries all three annotations: the
// background service (only this class, BatterySampler and BatteryLog are
// loaded there), the glance (plus BatteryGlance and BatteryModel) and the
// full app.
(:background, :glance)
class BatteryApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
        scheduleSampling();
    }

    // Log the battery level every SAMPLE_MINUTES. Registering again replaces
    // the previous registration, so this is safe to call on every start.
    function scheduleSampling() as Void {
        if (!(Toybox has :Background)) {
            return;
        }
        try {
            if (Background.getTemporalEventRegisteredTime() == null) {
                Background.registerForTemporalEvent(new Time.Duration(BatteryLog.SAMPLE_MINUTES * 60));
            }
        } catch (e) {
            // Nothing to do: the next foreground start will try again
        }
    }

    // Only the background process calls this (BatterySampler exists only there)
    (:typecheck(disableGlanceCheck))
    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new BatterySampler()];
    }

    // Only the glance calls this (BatteryGlance is not loaded in the background)
    (:typecheck(disableBackgroundCheck))
    function getGlanceView() as [GlanceView] or [GlanceView, GlanceViewDelegate] or Null {
        return [new BatteryGlance()];
    }

    function getGlanceTheme() as AppBase.GlanceTheme {
        return AppBase.GLANCE_THEME_LIGHT_BLUE;
    }

    (:typecheck([disableBackgroundCheck, disableGlanceCheck]))
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new BatteryView();
        return [view, new BatteryDelegate(view)];
    }

    // The background service just logged a sample: redraw whatever is showing
    function onBackgroundData(data as PersistableType) as Void {
        WatchUi.requestUpdate();
    }
}
