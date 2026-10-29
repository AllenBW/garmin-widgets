import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Pocket QR (designs/DESIGNS.md, design #9): QR codes set up in the Connect IQ
// app settings (a name and the content, up to six), shown full screen so a
// phone or a scanner can read them off the wrist. The glance names the first
// code and counts the rest; the app pages through them.
(:glance)
class QrApp extends Application.AppBase {

    private var _view as QrView?;

    function initialize() {
        AppBase.initialize();
    }

    function getGlanceView() as [GlanceView] or [GlanceView, GlanceViewDelegate] or Null {
        return [new QrGlance()];
    }

    function getGlanceTheme() as AppBase.GlanceTheme {
        return AppBase.GLANCE_THEME_WHITE;
    }

    (:typecheck(disableGlanceCheck))
    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new QrView();
        _view = view;
        return [view, new QrDelegate(view)];
    }

    // Settings changed on the phone while the app is open: reload the codes
    (:typecheck(disableGlanceCheck))
    function onSettingsChanged() as Void {
        var view = _view;
        if (view != null) {
            view.reload();
        }
        WatchUi.requestUpdate();
    }
}
