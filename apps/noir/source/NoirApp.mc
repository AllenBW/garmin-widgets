import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Noir: an analog dial in neon, the hands loops of tube (design #59).
class NoirApp extends Application.AppBase {

    private var _view as NoirView?;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new NoirView();
        _view = view;
        return [view, new NoirDelegate(view)];
    }

    // A new look chosen in the phone app wins over the last hold
    function onSettingsChanged() as Void {
        Lib.Look.changedOnPhone();
        var view = _view;
        if (view != null) {
            view.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}
