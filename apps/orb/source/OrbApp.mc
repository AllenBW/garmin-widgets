import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Orb: Lockup's rows printed round a globe, where only what changed moves
// (designs/README.md, design #27).
class OrbApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    private var _view as OrbView?;

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new OrbView();
        _view = view;
        return [view, new OrbDelegate(view)];
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
