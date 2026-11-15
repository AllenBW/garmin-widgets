import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Ticker: the time as a tape of minutes, two thin tapes of readings that turn
// to whatever changed (designs/README.md, design #25).
class TickerApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    private var _view as TickerView?;

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new TickerView();
        _view = view;
        return [view, new TickerDelegate(view)];
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
