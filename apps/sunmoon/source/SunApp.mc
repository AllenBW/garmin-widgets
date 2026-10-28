import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Sun & Moon (designs/DESIGNS.md, design #5): the next sun event and a
// countdown to golden hour in the glance; the sun's arc, golden and blue
// hour and the moon in the app. Pure maths on the last known location,
// so it works with no phone and no network.
(:glance)
class SunApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getGlanceView() as [GlanceView] or [GlanceView, GlanceViewDelegate] or Null {
        return [new SunGlance()];
    }

    function getGlanceTheme() as AppBase.GlanceTheme {
        return AppBase.GLANCE_THEME_GOLD;
    }

    (:typecheck(disableGlanceCheck))
    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new SunView()];
    }
}
