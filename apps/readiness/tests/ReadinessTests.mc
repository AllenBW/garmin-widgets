import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Test;

// Run No Evil tests for Readiness: scripts/test.sh readiness [device].

(:test)
function testReadinessText(logger as Logger) as Boolean {
    Test.assertEqualMessage(ReadinessText.score(74), "74", "score");
    Test.assertEqualMessage(ReadinessText.score(null), "--", "no score");
    Test.assertEqualMessage(ReadinessText.recovery(null), "--", "no recovery");
    Test.assertEqualMessage(ReadinessText.recovery(0), "ready", "recovered");
    Test.assertEqualMessage(ReadinessText.recovery(45), "45m", "under an hour");
    Test.assertEqualMessage(ReadinessText.recovery(13 * 60 + 1), "14h", "rounds up");
    Test.assertEqualMessage(ReadinessText.recovery(14 * 60), "14h", "whole hours");
    Test.assertEqualMessage(ReadinessText.training("Productive"), "Training: Productive", "training");
    Test.assertEqualMessage(ReadinessText.training(null), "", "no training status");
    Test.assertEqualMessage(ReadinessText.training(""), "", "empty training status");

    var r = new Readings();
    Test.assertEqualMessage(ReadinessText.summary(r), "BB -- · SLEEP --", "empty summary");
    r.bodyBattery = 74;
    r.sleepScore = 82;
    Test.assertEqualMessage(ReadinessText.summary(r), "BB 74 · SLEEP 82", "summary");
    return true;
}

(:test)
function testMetricsRead(logger as Logger) as Boolean {
    var started = System.getTimer();
    var r = Metrics.read();
    logger.debug("read: " + (System.getTimer() - started) + " ms");
    logger.debug("body " + r.bodyBattery + " stress " + r.stress + " sleep " + r.sleepScore
        + " recovery " + r.recoveryMinutes + " rhr " + r.restingHr + " training " + r.trainingStatus);
    var body = r.bodyBattery;
    Test.assertMessage(body == null || (body >= 0 && body <= 100), "Body Battery in range");
    var stress = r.stress;
    Test.assertMessage(stress == null || (stress >= 0 && stress <= 100), "stress in range");
    var sleep = r.sleepScore;
    Test.assertMessage(sleep == null || (sleep >= 0 && sleep <= 100), "sleep score in range");
    var recovery = r.recoveryMinutes;
    Test.assertMessage(recovery == null || recovery >= 0, "recovery not negative");
    return true;
}

(:test)
function testReadinessDrawsEveryMode(logger as Logger) as Boolean {
    var settings = System.getDeviceSettings();
    var w = settings.screenWidth;
    var h = settings.screenHeight;
    var dc = (Graphics.createBufferedBitmap({:width => w, :height => h}).get() as Graphics.BufferedBitmap).getDc();

    var view = new ReadinessView();
    view.onLayout(dc);

    // Whatever the simulator provides
    var started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("draw: " + (System.getTimer() - started) + " ms");

    // Everything known
    var full = new Readings();
    full.bodyBattery = 74;
    full.stress = 28;
    full.sleepScore = 82;
    full.recoveryMinutes = 14 * 60;
    full.restingHr = 48;
    full.trainingStatus = "Productive";
    view.setReadings(full);
    view.onUpdate(dc);
    var left = view.metricAt((w * 0.12).toNumber(), h / 2);
    Test.assertMessage(left != null && left == Complications.COMPLICATION_TYPE_BODY_BATTERY, "left gauge opens Body Battery");
    var right = view.metricAt((w * 0.88).toNumber(), h / 2);
    Test.assertMessage(right != null && right == Complications.COMPLICATION_TYPE_STRESS, "right gauge opens stress");
    var middle = view.metricAt(w / 2, (h * 0.68).toNumber());
    Test.assertMessage(middle != null && middle == Complications.COMPLICATION_TYPE_RECOVERY_TIME, "middle tile opens recovery");
    var footer = view.metricAt(w / 2, (h * 0.83).toNumber());
    Test.assertMessage(footer != null && footer == Complications.COMPLICATION_TYPE_TRAINING_STATUS, "footer opens training status");
    Test.assertMessage(view.metricAt(w / 2, (h * 0.44).toNumber()) == null, "the time is not a target");

    // Nothing known, and the extremes
    var empty = new Readings();
    view.setReadings(empty);
    view.onUpdate(dc);
    Test.assertMessage(view.metricAt(w / 2, (h * 0.83).toNumber()) == null, "no footer without a status");
    full.bodyBattery = 100;
    full.stress = 100;
    full.recoveryMinutes = 0;
    view.setReadings(full);
    view.onUpdate(dc);
    full.bodyBattery = 0;
    full.stress = 0;
    full.recoveryMinutes = 30;
    view.setReadings(full);
    view.onUpdate(dc);

    // Always-on
    view.onEnterSleep();
    started = System.getTimer();
    view.onUpdate(dc);
    logger.debug("always-on draw: " + (System.getTimer() - started) + " ms");
    Test.assertMessage(view.metricAt((w * 0.12).toNumber(), h / 2) == null, "no targets while asleep");
    view.onExitSleep();
    view.onUpdate(dc);

    var stats = System.getSystemStats();
    logger.debug("memory: " + stats.usedMemory + " of " + stats.totalMemory + " bytes used");
    return true;
}
