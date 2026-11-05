import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Stretching God (designs/DESIGNS.md, design #20): guided stretching, each
// stretch drawn as a moving figure and coached through the hold, the
// release and both sides, strung into routines for the morning, before
// and after an activity, the desk and bedtime. The glance suggests the
// routine for now; the app plays it.
(:glance)
class StretchApp extends Application.AppBase {

    private var _view as StretchView?;

    function initialize() {
        AppBase.initialize();
    }

    (:glanceview)
    function getGlanceView() as [GlanceView] or [GlanceView, GlanceViewDelegate] or Null {
        return [new StretchGlance()];
    }

    function getGlanceTheme() as AppBase.GlanceTheme {
        return AppBase.GLANCE_THEME_GOLD;
    }

    (:typecheck(disableGlanceCheck))
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new StretchView();
        _view = view;
        return [view, new StretchDelegate(view)];
    }

    (:typecheck(disableGlanceCheck))
    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }

    // Leaving mid-routine keeps what was done
    (:typecheck(disableGlanceCheck))
    function onStop(state as Dictionary?) as Void {
        var view = _view;
        if (view != null) {
            view.shutdown();
        }
    }
}
