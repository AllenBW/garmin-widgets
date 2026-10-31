import Toybox.Application.WatchFaceConfig;
import Toybox.Complications;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Watch faces get one gesture: press and hold. Holding on the sun line, the
// date or a reading opens the native widget for it. In the watch face
// editor, a tap on a reading picks its slot, and each edit redraws.
class StrataDelegate extends WatchUi.WatchFaceDelegate {

    private var _view as StrataView;

    function initialize(view as StrataView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onPress(clickEvent as ClickEvent) as Boolean {
        if (!(Toybox has :Complications)) {
            return false;
        }
        var xy = clickEvent.getCoordinates();
        var type = _view.targetAt(xy[0], xy[1]);
        if (type == null) {
            return false;
        }
        try {
            Complications.exitTo(new Complications.Id(type));
            return true;
        } catch (e instanceof Lang.InvalidValueException) {
            return false;   // no widget for this on this watch
        }
    }

    // The editor changed the style, a colour or a reading
    function onWatchFaceConfigEdited(options as {:configId as WatchFaceConfig.Id, :type as WatchUi.WatchFaceConfigType?,
                                                 :committed as Boolean}) as Void {
        _view.reloadSettings();
        WatchUi.requestUpdate();
    }

    // In the editor: a tap on a reading selects that slot
    function onTap(clickEvent as ClickEvent) as Boolean {
        var xy = clickEvent.getCoordinates();
        var slot = _view.slotAt(xy[0], xy[1]);
        if (slot == null) {
            return false;
        }
        setSelectedComplication(slot);
        return true;
    }

    // The firmware calls this when onUpdate takes too long in low power mode
    function onPowerBudgetExceeded(powerInfo as WatchFacePowerInfo) as Void {
        System.println("Strata: power budget exceeded");
    }
}
