import Toybox.Graphics;
import Toybox.Lang;
import Toybox.ScanCode;
import Toybox.WatchUi;

// The app: one code at a time, black modules on a white card with a quiet
// zone, the code's name above and "2 of 3 · Wi-Fi" below. Up/down or a swipe
// pages through the codes; select or menu lists them.
class QrView extends WatchUi.View {

    private const WHITE = 0xF2F2F2;
    private const GRAY = 0x8A8A8A;

    private var _codes as Array<QrCode> = [] as Array<QrCode>;
    private var _index as Number = 0;
    private var _image as Graphics.BufferedBitmap?;
    private var _imageIndex as Number = -1;   // which code _image (or _error) belongs to
    private var _error as String?;            // set when the current code cannot be encoded
    private var _size as Number = 0;          // QR image side in px
    private var _card as Number = 0;          // white card side in px
    private var _nameWidth as Number = 0;     // room for the name along the chord near the top
    private var _nameFont as FontType = Graphics.FONT_SMALL;
    private var _smallFont as FontType = Graphics.FONT_XTINY;

    function initialize() {
        View.initialize();
    }

    function onLayout(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var d = (w < h) ? w : h;
        // The largest square inside the round screen is d / sqrt(2) = 0.707 d. The card
        // stays inside that with room for the name above and the counter below.
        _card = (d * 0.66).toNumber();
        _size = (d * 0.58).toNumber();
        _nameWidth = (w * 0.58).toNumber();
        _nameFont = Lib.Fmt.vectorFont("RobotoCondensedBold", (h * 0.075).toNumber(), Graphics.FONT_SMALL);
        _smallFont = Lib.Fmt.vectorFont("RobotoCondensedRegular", (h * 0.05).toNumber(), Graphics.FONT_XTINY);
    }

    function onShow() as Void {
        reload();
    }

    // Re-read the settings; keeps the current position when it still exists
    function reload() as Void {
        _codes = QrCodes.load();
        if (_index >= _codes.size()) {
            _index = 0;
        }
        _image = null;
        _imageIndex = -1;
        _error = null;
    }

    function codes() as Array<QrCode> {
        return _codes;
    }

    function index() as Number {
        return _index;
    }

    function select(i as Number) as Void {
        var n = _codes.size();
        _index = (n == 0) ? 0 : ((i % n) + n) % n;
    }

    function next() as Void {
        select(_index + 1);
    }

    function previous() as Void {
        select(_index - 1);
    }

    // The current code's image, built on first use and kept until the code changes
    function image() as Graphics.BufferedBitmap? {
        if (_imageIndex == _index) {
            return _image;
        }
        _imageIndex = _index;
        _image = null;
        _error = null;
        if (_codes.size() == 0) {
            return null;
        }
        try {
            _image = ScanCode.createQrCodeImage(_codes[_index].value, ScanCode.QR_CODE_ECC_MEDIUM, _size,
                {:color => Graphics.COLOR_BLACK, :backgroundColor => Graphics.COLOR_WHITE});
        } catch (e) {
            _error = "Too long to encode";
        }
        return _image;
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        if (_codes.size() == 0) {
            dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - (h * 0.08).toNumber(), _nameFont, "No codes yet", center);
            dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + (h * 0.02).toNumber(), _smallFont, "Add them in the Connect IQ app", center);
            dc.drawText(cx, cy + (h * 0.08).toNumber(), _smallFont, "under this app's settings", center);
            return;
        }

        var code = _codes[_index];
        var img = image();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - _card / 2, cy - _card / 2, _card, _card, (_card * 0.06).toNumber());
        if (img != null) {
            dc.drawBitmap(cx - _size / 2, cy - _size / 2, img);
        } else {
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy, _smallFont, (_error == null) ? "" : _error, center);
        }

        dc.setColor(WHITE, Graphics.COLOR_TRANSPARENT);
        var name = Graphics.fitTextToArea(code.name, _nameFont, _nameWidth, dc.getFontHeight(_nameFont) + 2, true);
        dc.drawText(cx, (h * 0.10).toNumber(), _nameFont, name, center);
        dc.setColor(GRAY, Graphics.COLOR_TRANSPARENT);
        var counter = (_codes.size() > 1) ? ((_index + 1) + " of " + _codes.size() + " · ") : "";
        dc.drawText(cx, (h * 0.905).toNumber(), _smallFont, counter + QrCodes.kind(code.value), center);
    }
}

// Up/down (and swipes) page through the codes; select or menu lists them
class QrDelegate extends WatchUi.BehaviorDelegate {

    private var _view as QrView;

    function initialize(view as QrView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onNextPage() as Boolean {
        _view.next();
        WatchUi.requestUpdate();
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.previous();
        WatchUi.requestUpdate();
        return true;
    }

    function onSelect() as Boolean {
        return showMenu();
    }

    function onMenu() as Boolean {
        return showMenu();
    }

    function showMenu() as Boolean {
        var codes = _view.codes();
        if (codes.size() == 0) {
            return false;
        }
        var menu = new WatchUi.Menu2({:title => "Codes"});
        for (var i = 0; i < codes.size(); i++) {
            menu.addItem(new WatchUi.MenuItem(codes[i].name, QrCodes.kind(codes[i].value), i, null));
        }
        WatchUi.pushView(menu, new QrMenuDelegate(_view), WatchUi.SLIDE_UP);
        return true;
    }
}

class QrMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _view as QrView;

    function initialize(view as QrView) {
        Menu2InputDelegate.initialize();
        _view = view;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id instanceof Number) {
            _view.select(id);
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }

    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
