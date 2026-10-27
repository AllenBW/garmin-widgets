import Toybox.Complications;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Input for the Field face. Watch faces only get one gesture: a press and
// hold (onPress). Holding on a slot opens the native widget for its data.
class FieldDelegate extends WatchUi.WatchFaceDelegate {

    private var _view as FieldView;

    function initialize(view as FieldView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onPress(clickEvent as ClickEvent) as Boolean {
        if (!(Toybox has :Complications)) {
            return false;
        }
        var xy = clickEvent.getCoordinates();
        var kind = _view.slotAt(xy[0], xy[1]);
        if (kind == null) {
            return false;
        }
        var type = Slots.complicationType(kind);
        if (type == null) {
            return false;
        }
        try {
            Complications.exitTo(new Complications.Id(type));
            return true;
        } catch (e instanceof Lang.InvalidValueException) {
            // No app registered for this complication on this watch
            return false;
        }
    }

    // The firmware calls this when onUpdate takes too long in low power mode.
    // The simulator shows it in the console; on the watch the face is blanked.
    function onPowerBudgetExceeded(powerInfo as WatchFacePowerInfo) as Void {
        System.println("Field: power budget exceeded");
    }
}
