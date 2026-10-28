import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Sun Compass (designs/DESIGNS.md, design #8): a compass rose that turns
// with the watch, with today's sun path drawn across the sky inside it.
// The glance says where the sun is now; the app adds the live heading.
(:glance)
class CompassApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getGlanceView() as [GlanceView] or [GlanceView, GlanceViewDelegate] or Null {
        return [new CompassGlance()];
    }

    function getGlanceTheme() as AppBase.GlanceTheme {
        return AppBase.GLANCE_THEME_GOLD;
    }

    (:typecheck(disableGlanceCheck))
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new CompassView()];
    }
}
