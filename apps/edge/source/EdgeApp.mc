import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Edge: enormous numerals that are not drawn, only their edges lit in neon
// tube (designs/edge/DESIGN.md, design #58).
class EdgeApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    private var _view as EdgeView?;

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new EdgeView();
        _view = view;
        return [view, new EdgeDelegate(view)];
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
