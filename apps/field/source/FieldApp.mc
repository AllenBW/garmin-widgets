import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Field: the everyday watch face (designs/DESIGNS.md, design #1).
class FieldApp extends Application.AppBase {

    private var _view as FieldView?;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new FieldView();
        _view = view;
        return [view, new FieldDelegate(view)];
    }

    // Settings changed in the phone app or the on-device editor
    function onSettingsChanged() as Void {
        var view = _view;
        if (view != null) {
            view.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}
