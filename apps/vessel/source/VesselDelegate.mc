import Toybox.Application.WatchFaceConfig;
import Toybox.Complications;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Watch faces get one gesture: press and hold. Holding on a reading opens
// the widget of whatever complication it shows, other apps' included, and
// holding on the date opens the calendar. In
// the watch face editor, a tap on a reading picks its slot, and each edit
// redraws.
class VesselDelegate extends WatchUi.WatchFaceDelegate {

    private var _view as VesselView;

    function initialize(view as VesselView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onPress(clickEvent as ClickEvent) as Boolean {
        if (!(Toybox has :Complications)) {
            return false;
        }
        var xy = clickEvent.getCoordinates();
        var id = _view.targetAt(xy[0], xy[1]);
        if (id == null) {
            return false;
        }
        try {
            Complications.exitTo(id);
            return true;
        } catch (e) {
            return false;   // no widget for this on this watch
        }
    }

    // The editor changed the style, a colour or a reading: it wins over the
    // phone app's settings until they are next changed
    function onWatchFaceConfigEdited(options as {:configId as WatchFaceConfig.Id, :type as WatchUi.WatchFaceConfigType?,
                                                 :committed as Boolean}) as Void {
        Lib.Config.changedInEditor();
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
        System.println("Vessel: power budget exceeded");
    }
}
