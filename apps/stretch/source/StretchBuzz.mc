import Toybox.Lang;

// The buzz vocabulary: each meaning its own rhythm and strength, so the
// routine can be followed with the watch out of sight. Patterns are
// (duty %, milliseconds) pairs, a duty of 0 a pause; the guide in the
// routines menu plays each one with its name.
module StretchBuzz {

    // In the order the guide plays them: how a stretch goes
    const GUIDE = [BUZZ_TICK, BUZZ_GO, BUZZ_TEN, BUZZ_RELEASE, BUZZ_SWITCH, BUZZ_NEXT, BUZZ_PUSH, BUZZ_RELAX, BUZZ_DONE] as Array<Number>;

    function pattern(buzz as Number) as Array<Number> {
        if (buzz == BUZZ_TICK) {
            return [25, 60];                                        // a light tap
        }
        if (buzz == BUZZ_GO) {
            return [80, 350];                                       // one firm buzz
        }
        if (buzz == BUZZ_TEN) {
            return [30, 50, 0, 50, 30, 50, 0, 50, 30, 50];          // a light flutter
        }
        if (buzz == BUZZ_RELEASE) {
            return [70, 250, 45, 250, 25, 350];                     // long, fading away
        }
        if (buzz == BUZZ_SWITCH) {
            return [100, 90, 0, 130, 100, 90];                      // two sharp taps
        }
        if (buzz == BUZZ_NEXT) {
            return [35, 100, 0, 110, 65, 100, 0, 110, 100, 140];    // three taps, rising
        }
        if (buzz == BUZZ_PUSH) {
            return [100, 650];                                      // strong and long
        }
        if (buzz == BUZZ_RELAX) {
            return [50, 200, 25, 300];                              // a short fade
        }
        if (buzz == BUZZ_DONE) {
            return [100, 120, 0, 100, 100, 120, 0, 100, 100, 600];  // two taps and a long one
        }
        return [] as Array<Number>;
    }

    function name(buzz as Number) as String {
        if (buzz == BUZZ_TICK) {
            return "3 · 2 · 1";
        }
        if (buzz == BUZZ_GO) {
            return "GO";
        }
        if (buzz == BUZZ_TEN) {
            return "10 SECONDS";
        }
        if (buzz == BUZZ_RELEASE) {
            return "RELEASE";
        }
        if (buzz == BUZZ_SWITCH) {
            return "SWITCH";
        }
        if (buzz == BUZZ_NEXT) {
            return "NEXT";
        }
        if (buzz == BUZZ_PUSH) {
            return "PUSH";
        }
        if (buzz == BUZZ_RELAX) {
            return "RELAX";
        }
        return "DONE";
    }

    function meaning(buzz as Number) as String {
        if (buzz == BUZZ_TICK) {
            return "Light taps: about to start";
        }
        if (buzz == BUZZ_GO) {
            return "One firm buzz: ease in";
        }
        if (buzz == BUZZ_TEN) {
            return "A flutter: nearly there";
        }
        if (buzz == BUZZ_RELEASE) {
            return "A long fade: come out slowly";
        }
        if (buzz == BUZZ_SWITCH) {
            return "Two sharp taps: other side";
        }
        if (buzz == BUZZ_NEXT) {
            return "Three rising: next stretch";
        }
        if (buzz == BUZZ_PUSH) {
            return "Strong and long: push gently";
        }
        if (buzz == BUZZ_RELAX) {
            return "A short fade: let go";
        }
        return "Two taps and a long one: done";
    }
}
