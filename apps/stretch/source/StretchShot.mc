import Toybox.Lang;

// Sample builds for captures (sample.jungle and the shot-*.jungle files
// beside it, through CIQ_SHOT_JUNGLE): open straight on a screen, without
// the glance. start() gives [routine, contract-relax (0 or 1), the phase
// to stop at, how many of that phase to pass first, milliseconds into
// it], or null for the opening card. The live build never starts anything
// by itself.
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

// After a run: the standing quad on the right, mid-hold
(:shothold)
module StretchShot {
    function start() as Array<Number>? {
        return [StretchRoutines.R_AFTER_RUN, 0, PH_HOLD, 5, 12000] as Array<Number>;
    }
}

// The morning routine: the hip flexor coming up, its ghost behind
(:shotsetup)
module StretchShot {
    function start() as Array<Number>? {
        return [StretchRoutines.R_MORNING, 0, PH_SETUP, 11, 1500] as Array<Number>;
    }
}

// Before a run: leg swings, counting
(:shotreps)
module StretchShot {
    function start() as Array<Number>? {
        return [StretchRoutines.R_BEFORE_RUN, 0, PH_REPS, 1, 7000] as Array<Number>;
    }
}

// Full body with contract-relax: the push
(:shotpush)
module StretchShot {
    function start() as Array<Number>? {
        return [StretchRoutines.R_FULL, 1, PH_PUSH, 0, 2000] as Array<Number>;
    }
}

// Before bed: the slow breath
(:shotbreathe)
module StretchShot {
    function start() as Array<Number>? {
        return [StretchRoutines.R_BEDTIME, 0, PH_BREATHE, 0, 12000] as Array<Number>;
    }
}

// The done screen after the desk break
(:shotdone)
module StretchShot {
    function start() as Array<Number>? {
        return [StretchRoutines.R_DESK, 0, PH_DONE, 0, 0] as Array<Number>;
    }
}
