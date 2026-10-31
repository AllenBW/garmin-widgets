import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Rings: three goal rings on the left, the day's numbers on the right (designs/DESIGNS.md, design #13).
class RingsApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    private var _view as RingsView?;

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new RingsView();
        _view = view;
        return [view, new RingsDelegate(view)];
    }

    // The colours changed in the phone app or the on-device editor
    function onSettingsChanged() as Void {
        var view = _view;
        if (view != null) {
            view.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}
