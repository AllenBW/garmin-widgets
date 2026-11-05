import Toybox.Lang;

// Sample builds for captures (sample.jungle and the CIQ_SHOT_JUNGLE files
// beside it): open straight on a screen, without the glance. The live
// build never starts anything by itself.
(:live)
module StretchShot {
    function start() as Array<Number>? {
        return null;
    }
}

// The opening card
(:shotidle)
module StretchShot {
    function start() as Array<Number>? {
        return null;
    }
}

// After a run, the quad on the right, mid-hold: [routine, milliseconds in]
(:shothold)
module StretchShot {
    function start() as Array<Number>? {
        return [StretchRoutines.R_AFTER_RUN, 191000] as Array<Number>;
    }
}

// The morning routine, the hip flexor coming up: a setup with its ghost
(:shotsetup)
module StretchShot {
    function start() as Array<Number>? {
        return [StretchRoutines.R_MORNING, 347000] as Array<Number>;
    }
}
