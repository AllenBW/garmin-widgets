import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Sauna (designs/DESIGNS.md, design #10): a sauna visit, round by round,
// with the door noticed by the watch's own thermometer, the heart-rate
// recovery after each round, and the visit saved to Garmin Connect. The
// glance is the last visit; the app records a new one.
(:glance)
class SaunaApp extends Application.AppBase {

    private var _view as SaunaView?;

    function initialize() {
        AppBase.initialize();
    }

    function getGlanceView() as [GlanceView] or [GlanceView, GlanceViewDelegate] or Null {
        return [new SaunaGlance()];
    }

    function getGlanceTheme() as AppBase.GlanceTheme {
        return AppBase.GLANCE_THEME_RED;
    }

    (:typecheck(disableGlanceCheck))
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new SaunaView();
        _view = view;
        return [view, new SaunaDelegate(view)];
    }

    // Settings edited on the phone while the app is open
    (:typecheck(disableGlanceCheck))
    function onSettingsChanged() as Void {
        var view = _view;
        if (view != null) {
            view.reloadSettings();
            WatchUi.requestUpdate();
        }
    }

    // Leaving the app mid-visit keeps the recording rather than losing it
    (:typecheck(disableGlanceCheck))
    function onStop(state as Dictionary?) as Void {
        var view = _view;
        if (view != null) {
            view.shutdown();
        }
    }
}
