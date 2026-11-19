import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Sign: the time as a neon sign, numerals bent from one tube each
// (designs/README.md, design #57).
class SignApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    private var _view as SignView?;

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new SignView();
        _view = view;
        return [view, new SignDelegate(view)];
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
