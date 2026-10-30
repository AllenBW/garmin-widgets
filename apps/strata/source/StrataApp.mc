import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Strata: the Today list drawn into a field of soil layers (designs/DESIGNS.md, design #12).
class StrataApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    private var _view as StrataView?;

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new StrataView();
        _view = view;
        return [view, new StrataDelegate(view)];
    }

    // The colours or switches changed in the phone app or the on-device editor
    function onSettingsChanged() as Void {
        var view = _view;
        if (view != null) {
            view.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}
