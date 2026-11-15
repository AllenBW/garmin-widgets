import Toybox.Lang;
import Toybox.Test;

// Lib.Motion: the ease's shape, the pacer's clock and its cadence

(:test)
function motionEase(logger as Test.Logger) as Boolean {
    Test.assertEqual(Lib.Motion.ease(0, 400, true, 0.05), 0.0);
    Test.assert(Lib.Motion.ease(35, 400, true, 0.05) < 0.0);                  // the push goes back a little
    Test.assert(Lib.Motion.ease(270, 400, true, 0.05) < 0.3);                 // a fall accelerates
    Test.assert((Lib.Motion.ease(270, 400, false, 0.05) - 0.5).abs() < 0.001); // in and out: half way at half time
    var last = -1.0;
    for (var t = 70; t <= 470; t += 20) {
        var v = Lib.Motion.ease(t, 400, false, 0.05);
        Test.assert(v >= last);
        last = v;
    }
    var bounce = Lib.Motion.ease(530, 400, true, 0.05);                       // off the stop and back
    Test.assert(bounce < 1.0 && bounce > 0.95);
    Test.assertEqual(Lib.Motion.ease(970, 400, true, 0.05), 1.0);
    Test.assert(!Lib.Motion.done(969, 400));
    Test.assert(Lib.Motion.done(970, 400));
    return true;
}

(:test)
function motionPacerClock(logger as Test.Logger) as Boolean {
    var p = new Lib.Motion.Pacer(50, 4);
    p.setStill();
    Test.assertEqual(p.step(1000), 50);      // the first frame: one period
    Test.assertEqual(p.step(1030), 30);
    Test.assertEqual(p.step(1530), 200);     // a stall: four frames at most
    Test.assertEqual(p.step(5000), 50);      // over two seconds since: one period
    return true;
}

(:test)
function motionPacerCadence(logger as Test.Logger) as Boolean {
    var p = new Lib.Motion.Pacer(50, 4);
    p.setStill();
    p.onShow();
    Test.assert(!p.proven());
    p.step(10000);
    p.step(11000);
    p.step(12000);                           // the system's once-a-second updates
    Test.assert(p.proven() && p.awake);
    p.step(80000);                           // a minute's gap, nothing said: asleep
    Test.assert(!p.awake && !p.proven());
    p.onExitSleep();
    Test.assert(p.awake && p.proven());
    p.onEnterSleep();
    Test.assert(!p.awake && !p.proven());
    p.want(true);
    Test.assert(!p.running());               // never a timer asleep
    return true;
}
