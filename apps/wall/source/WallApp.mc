import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Wall: a face made of numbers, sized by importance and coloured by family
// (designs/DESIGNS.md, design #22).
class WallApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    private var _view as WallView?;

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new WallView();
        _view = view;
        return [view, new WallDelegate(view)];
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
