import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.ScanCode;
import Toybox.System;
import Toybox.Test;

(:test)
function testCodesParse(logger as Logger) as Boolean {
    var codes = QrCodes.parse([
        {"name" => " Home Wi-Fi ", "value" => "WIFI:T:WPA;S:home;P:secret;;"},
        {"name" => "", "value" => "https://example.org"},
        {"name" => "Empty", "value" => "   "},
        "garbage",
        {"value" => "BEGIN:VCARD\nN:Doe;Jane\nEND:VCARD"},
        {"name" => "Note", "value" => "plain words"},
    ] as Array<Application.PropertyValueType>);
    Test.assertEqualMessage(codes.size(), 4, "empty and malformed entries skipped");
    Test.assertEqualMessage(codes[0].name, "Home Wi-Fi", "name trimmed");
    Test.assertEqualMessage(codes[1].name, "Code 2", "missing name is numbered");
    Test.assertEqualMessage(codes[3].value, "plain words", "value kept");
    Test.assertEqualMessage(QrCodes.kind(codes[0].value), "Wi-Fi", "wifi kind");
    Test.assertEqualMessage(QrCodes.kind(codes[1].value), "Link", "link kind");
    Test.assertEqualMessage(QrCodes.kind(codes[2].value), "Contact", "contact kind");
    Test.assertEqualMessage(QrCodes.kind(codes[3].value), "Text", "text kind");
    Test.assertEqualMessage(QrCodes.kind("mailto:a@b.c"), "Email", "email kind");
    Test.assertEqualMessage(QrCodes.kind("tel:+15550100"), "Phone", "phone kind");
    Test.assertEqualMessage(QrCodes.summary(codes), "4 codes · Wi-Fi, Link, Contact…", "summary of four");
    Test.assertEqualMessage(QrCodes.summary([codes[0]] as Array<QrCode>), "1 code · Wi-Fi", "summary of one");
    Test.assertEqualMessage(QrCodes.summary([] as Array<QrCode>), "add them in the Connect IQ app", "empty summary");
    Test.assertEqualMessage(QrCodes.parse(null).size(), 0, "null property");
    Test.assertEqualMessage(QrCodes.parse("nope").size(), 0, "wrong type");
    var many = [] as Array<Application.PropertyValueType>;
    for (var i = 0; i < 10; i++) {
        many.add({"name" => "n" + i, "value" => "v" + i} as Dictionary<Application.PropertyKeyType, Application.PropertyValueType>);
    }
    Test.assertEqualMessage(QrCodes.parse(many).size(), QrCodes.MAX, "capped at MAX");
    return true;
}

(:test)
function testQrImage(logger as Logger) as Boolean {
    var start = System.getTimer();
    var img = ScanCode.createQrCodeImage("https://example.org/pocket-qr", ScanCode.QR_CODE_ECC_MEDIUM, 263,
        {:color => Graphics.COLOR_BLACK, :backgroundColor => Graphics.COLOR_WHITE});
    logger.debug("encode: " + (System.getTimer() - start) + " ms, " + img.getWidth() + "x" + img.getHeight());
    Test.assertMessage(img instanceof Graphics.BufferedBitmap, "a bitmap");
    Test.assertEqualMessage(img.getWidth(), 263, "requested size");
    // Far beyond QR capacity (2953 bytes): record what the API does, the view guards both outcomes
    var huge = "";
    for (var i = 0; i < 200; i++) {
        huge += "0123456789abcdefghij";
    }
    try {
        var big = ScanCode.createQrCodeImage(huge, ScanCode.QR_CODE_ECC_MEDIUM, 263, null);
        logger.debug("4000 chars: returned " + big);
    } catch (e) {
        logger.debug("4000 chars: threw " + e);
    }
    return true;
}

(:test)
function testGlanceAndAppDraw(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var screen = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();
    var glanceDc = (Graphics.createBufferedBitmap({:width => (w * 0.77).toNumber(), :height => (h * 0.29).toNumber()}).get() as Graphics.BufferedBitmap).getDc();

    // No codes
    Application.Properties.setValue(QrCodes.KEY, [] as Array<Application.PropertyValueType>);
    var glance = new QrGlance();
    glance.onLayout(glanceDc);
    glance.onShow();
    glance.onUpdate(glanceDc);
    var view = new QrView();
    view.onLayout(screen);
    view.onShow();
    view.onUpdate(screen);
    Test.assertEqualMessage(view.codes().size(), 0, "no codes");
    Test.assertMessage(!new QrDelegate(view).onMenu(), "no menu without codes");

    // Three codes
    Application.Properties.setValue(QrCodes.KEY, [
        {"name" => "Home Wi-Fi", "value" => "WIFI:T:WPA;S:home;P:secret;;"},
        {"name" => "Repository", "value" => "https://github.com/AllenBW/garmin-widgets"},
        {"name" => "A rather long name that will not fit", "value" => "Hello from Pocket QR"},
    ] as Array<Application.PropertyValueType>);
    glance.onShow();
    glance.onUpdate(glanceDc);
    view.onShow();
    Test.assertEqualMessage(view.codes().size(), 3, "three codes");
    var start = System.getTimer();
    view.onUpdate(screen);
    logger.debug("first draw with encoding: " + (System.getTimer() - start) + " ms");
    start = System.getTimer();
    view.onUpdate(screen);
    logger.debug("cached draw: " + (System.getTimer() - start) + " ms");
    Test.assertMessage(view.image() != null, "image built");

    var delegate = new QrDelegate(view);
    delegate.onNextPage();
    Test.assertEqualMessage(view.index(), 1, "next");
    delegate.onNextPage();
    delegate.onNextPage();
    Test.assertEqualMessage(view.index(), 0, "wraps forward");
    delegate.onPreviousPage();
    Test.assertEqualMessage(view.index(), 2, "wraps back");
    view.onUpdate(screen);
    Test.assertMessage(view.image() != null, "third image built");

    // Settings shrink while the last code is showing: the position must stay valid
    Application.Properties.setValue(QrCodes.KEY, [{"name" => "Only", "value" => "x"}] as Array<Application.PropertyValueType>);
    view.reload();
    Test.assertEqualMessage(view.index(), 0, "index reset after reload");
    view.onUpdate(screen);

    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}
