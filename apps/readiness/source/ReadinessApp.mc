import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// Readiness (designs/DESIGNS.md, design #4): the recovery picture as a
// watch face. Body Battery and stress gauges, sleep score, recovery time,
// resting heart rate and the training status, with the time in the middle.
class ReadinessApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new ReadinessView();
        return [view, new ReadinessDelegate(view)];
    }
}
