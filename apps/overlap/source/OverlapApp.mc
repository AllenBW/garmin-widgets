import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Overlap: the hours enormous and quiet, the minutes bright in front,
// and a standby that stays on (designs/DESIGNS.md, design #18).
class OverlapApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    private var _view as OverlapView?;

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new OverlapView();
        _view = view;
        return [view, new OverlapDelegate(view)];
    }

    // The settings changed in the phone app (or the simulator's settings
    // editor): they win over the watch face editor until it is next used
    function onSettingsChanged() as Void {
        Lib.Config.changedOnPhone();
        var view = _view;
        if (view != null) {
            view.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}
