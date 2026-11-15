import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Shuttle: Lockup's rows of numbers, whose changed digits slide sideways in
// slots of their own (designs/README.md, design #26).
class ShuttleApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    private var _view as ShuttleView?;

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new ShuttleView();
        _view = view;
        return [view, new ShuttleDelegate(view)];
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
