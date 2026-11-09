import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Blocks: a face made of numbers, sized by importance and coloured by family
// (designs/README.md, design #21).
class BlocksApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    private var _view as BlocksView?;

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new BlocksView();
        _view = view;
        return [view, new BlocksDelegate(view)];
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
