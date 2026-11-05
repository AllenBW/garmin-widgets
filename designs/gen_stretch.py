# Generate the Stretching God tables (design #20) from the stretches and
# routines defined in designs/stretch_catalogue.py:
#   python3 -I designs/gen_stretch.py
# writes apps/stretch/source/StretchData.mc (poses, cues, routine steps; the
# app only) and apps/stretch/source/StretchRoutines.mc (names and lengths;
# the glance too). Never edit those two by hand.
#
# A figure is a hip and twelve segment angles, drawn as thick lines: no
# bitmaps, about 27 bytes a stretch. The model here and StretchFigure.mc
# must agree; designs/preview_stretch.py draws from this one.
import math, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Segment lengths in body heights. Front view: half the shoulder and hip widths.
L_TORSO, L_HEAD_AT, R_HEAD = 0.30, 0.097, 0.062
L_UA, L_FA, L_TH, L_SH, L_FOOT = 0.165, 0.155, 0.245, 0.245, 0.075
SH_W, HIP_W = 0.085, 0.05
FRONT_FOOT = 0.35   # feet seen from the front are short

# Angle slots, in the order stored: absolute degrees, y up, 0 = facing right,
# except head (relative to the upper back), bend (the spine's curve: the
# lower back turns by +bend, the upper by -bend, so plus rounds the back
# and minus arches it) and yaw (where the face points: 0 ahead, 180 behind,
# seen from the side; 0 at us, +90 the near side, seen from the front)
SLOTS = ["torso", "head", "nua", "nfa", "fua", "ffa", "nth", "nsh", "fth", "fsh", "nfoot", "ffoot",
         "bend", "yaw"]
NSLOT = len(SLOTS)
# Target bits: the segments drawn in the accent
TARGET_BITS = {s: i for i, s in enumerate(SLOTS[:12])}
TARGET_BITS["neck"] = TARGET_BITS.pop("head")
NOSE_AT, R_NOSE = 0.95, 0.32   # a nose in the head's colour, only when the head turns; head radii
# Joints an anchor can name (its x stays put while the figure moves)
ANCHORS = ["hip", "nan", "fan", "nha", "fha", "nkn", "fkn", "nto", "fto"]
# Starting positions
POS = {"stand": 0, "wall": 1, "chair": 2, "floor": 3, "kneel": 4, "all4": 5}
SEAT_DROP, SEAT_BACK, SEAT_FRONT, CHAIR_BACK_H = 0.035, 0.075, 0.13, 0.26

# Kinds and flags, as StretchCoach.mc reads them
KIND_HOLD, KIND_REPS = 0, 1
F_FRONT, F_CLOSEUP, F_SIDED, F_WALL, F_PNF, F_WALL_BACK, F_CHAIR = 1, 2, 4, 8, 16, 32, 64
# Routine flags
RF_PRE, RF_SLOW, RF_PNF = 1, 2, 4


def pt(o, ang, l):
    a = math.radians(ang)
    return (o[0] + l * math.cos(a), o[1] + l * math.sin(a))


def ik(o, tgt, l1, l2, bend):
    """Two-bone IK from o to tgt; bend +1 turns the middle joint anticlockwise."""
    dx, dy = tgt[0] - o[0], tgt[1] - o[1]
    d = min(math.hypot(dx, dy), (l1 + l2) * 0.999)
    base = math.degrees(math.atan2(dy, dx))
    c = (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)
    a1 = math.degrees(math.acos(max(-1.0, min(1.0, c))))
    j = pt(o, base + bend * a1, l1)
    return base + bend * a1, math.degrees(math.atan2(tgt[1] - j[1], tgt[0] - j[0]))


class Pose:
    """n = near (the side being stretched; the figure's left), f = far."""

    def __init__(self, front=False, **k):
        self.front = front
        d = dict(torso=90, head=0, nua=-92, nfa=-88, fua=-88, ffa=-92,
                 nth=-90, nsh=-90, fth=-90, fsh=-90, nfoot=None, ffoot=None, bend=0, yaw=0)
        if front:
            d.update(nth=-86, fth=-94, nua=-80, nfa=-86, fua=-100, ffa=-94)
        d.update(k)
        self.a = d

    def __getattr__(self, k):
        if k in ("a", "front"):
            raise AttributeError(k)
        return self.a[k]

    def angles(self):
        a = dict(self.a)
        for s in "nf":
            if a[s + "foot"] is None:
                a[s + "foot"] = -90 if self.front else a[s + "sh"] + 90
        return [a[s] for s in SLOTS]

    def joints(self):
        return joints(self.angles(), self.front)

    def reach(self, side, limb, target, bend):
        """Put a hand or ankle on a point (figure units, hip at 0,0)."""
        j = self.joints()
        if limb == "arm":
            a, b = ik(j[side + "so"], target, L_UA, L_FA, bend)
            self.a[side + "ua"], self.a[side + "fa"] = a, b
        else:
            a, b = ik(j[side + "ho"], target, L_TH, L_SH, bend)
            self.a[side + "th"], self.a[side + "sh"] = a, b
        return self

    def plant(self, other, shift, nbend=1, fbend=1):
        """Keep both ankles where they are in `other` while the hip moves by shift."""
        j = other.joints()
        for side, b in (("n", nbend), ("f", fbend)):
            x, y = j[side + "an"]
            self.reach(side, "leg", (x - shift[0], y - shift[1]), b)
        return self


def joints(ang, front):
    torso, head, nua, nfa, fua, ffa, nth, nsh, fth, fsh, nfoot, ffoot, bend, yaw = ang
    hip = (0.0, 0.0)
    lower, upper = torso + bend, torso - bend
    mid = pt(hip, lower, L_TORSO / 2)
    sh = pt(mid, upper, L_TORSO / 2)
    hd = pt(sh, upper + head, L_HEAD_AT)
    k = math.sin(math.radians(yaw)) if front else math.cos(math.radians(yaw))
    out = {"hip": hip, "mid": mid, "sh": sh, "head": hd,
           "nose": pt(hd, upper + head - 90, R_HEAD * NOSE_AT * k)}
    w, hw = (SH_W, HIP_W) if front else (0.0, 0.0)
    limbs = {"n": (nua, nfa, nth, nsh, nfoot), "f": (fua, ffa, fth, fsh, ffoot)}
    for side, s in (("n", 1), ("f", -1)):
        ua, fa, th, shin, foot = limbs[side]
        so = pt(sh, upper - 90, s * w)
        ho = pt(hip, lower - 90, s * hw)
        el = pt(so, ua, L_UA)
        kn = pt(ho, th, L_TH)
        an = pt(kn, shin, L_SH)
        out.update({side + "so": so, side + "ho": ho, side + "el": el,
                    side + "ha": pt(el, fa, L_FA), side + "kn": kn, side + "an": an,
                    side + "to": pt(an, foot, L_FOOT * (FRONT_FOOT if front else 1.0))})
    return out


def nose_shows(ang, front):
    """Only a turned head is marked: looking to a side, or back over a shoulder."""
    yaw = (ang[13] + 180) % 360 - 180
    k = math.sin(math.radians(yaw)) if front else math.cos(math.radians(yaw))
    return abs(yaw) > 5 and abs(k) > 0.3


def chair(j):
    """Seat, legs and back under a seated hip, in figure units."""
    hx, hy = j["hip"]
    seat = hy - SEAT_DROP
    return [((hx - SEAT_BACK, seat), (hx + SEAT_FRONT, seat)),
            ((hx - SEAT_BACK, seat), (hx - SEAT_BACK, 0.0)),
            ((hx + SEAT_FRONT, seat), (hx + SEAT_FRONT, 0.0)),
            ((hx - SEAT_BACK, seat), (hx - SEAT_BACK, seat + CHAIR_BACK_H))]


def placed(st, ang):
    """Joints standing on the ground with the anchor's x held at pose A's."""
    front = bool(st["flags"] & F_FRONT)
    j = grounded(joints(ang, front))
    a = st.get("anchor", "hip")
    if a != "hip":
        ja = grounded(joints(quant(st["a"].angles())[1], front))
        dx = ja[a][0] - j[a][0]
        j = {k: (x + dx, y) for k, (x, y) in j.items()}
    return j


def grounded(j):
    """Shift so the lowest point (head included) sits on y = 0."""
    lo = min(min(y for k, (_, y) in j.items() if k != "nose"), j["head"][1] - R_HEAD)
    return {k: (x, y - lo) for k, (x, y) in j.items()}


def lerp_angles(a, b, t):
    out = []
    for x, y in zip(a, b):
        d = (y - x + 180) % 360 - 180
        out.append(x + d * t)
    return out


def quant(ang):
    """Degrees to the stored byte (2-degree steps) and back."""
    q = [int(round((x % 360) / 2.0)) % 180 for x in ang]
    return q, [v * 2 for v in q]


def frame(st):
    """lift (cut below the hips for close-ups) and the box both poses fill."""
    qa, qb = quant(st["a"].angles())[1], quant(st["b"].angles())[1]
    ja, jb = placed(st, qa), placed(st, qb)
    lift = 0.0
    if st["flags"] & F_CLOSEUP:
        lift = ja["hip"][1] - 0.05
    pts = []
    for j in (ja, jb):
        pts += [(x, y - lift) for x, y in j.values() if y - lift > -0.01]
        hx, hy = j["head"]
        pts += [(hx - R_HEAD, hy - lift), (hx + R_HEAD, hy - lift + R_HEAD)]
        if st["flags"] & F_CHAIR and not st["flags"] & F_CLOSEUP:
            for a, b in chair(j):
                pts += [a, b]
    x0 = min(p[0] for p in pts)
    x1 = max(p[0] for p in pts)
    top = max(p[1] for p in pts)
    return lift, x0, x1, top


def wall_back(st):
    """The wall goes where the hands reach at full stretch: behind the figure?"""
    if not st["flags"] & F_WALL:
        return False
    jb = joints(quant(st["b"].angles())[1], bool(st["flags"] & F_FRONT))
    hand = max((jb["nha"], jb["fha"]), key=lambda p: abs(p[0]))
    return hand[0] < 0


def anchor_x(st):
    a = st.get("anchor", "hip")
    if a == "hip":
        return 0.0
    front = bool(st["flags"] & F_FRONT)
    ja = grounded(joints(quant(st["a"].angles())[1], front))
    return ja[a][0] - ja["hip"][0]


def byte(v, lo, hi, what):
    if not lo <= v <= hi:
        raise SystemExit(f"{what}: {v} outside {lo}..{hi}")
    return v


def mc_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def wrap(items, indent, width=96):
    lines, line = [], indent
    for it in items:
        piece = it + ", "
        if len(line) + len(piece) > width and line.strip():
            lines.append(line.rstrip())
            line = indent
        line += piece
    if line.strip():
        lines.append(line.rstrip().rstrip(","))
    if lines:
        lines[-1] = lines[-1].rstrip(",")
    return "\n".join(lines)


KIND_BREATH = 2
DOWN = (POS["floor"], POS["kneel"], POS["all4"])


def setup_ms(C, prev_pos, pos):
    """A setup's length from where the last stretch left you; prev_pos None at the start."""
    if prev_pos is None:
        return C.SETUP_FIRST_DOWN if pos in DOWN else C.SETUP_FIRST
    if prev_pos == pos:
        return C.SETUP_SAME
    if pos in DOWN and prev_pos not in DOWN:
        return C.SETUP_GET_DOWN
    if prev_pos in DOWN and pos not in DOWN:
        return C.SETUP_GET_UP
    return C.SETUP_STEP


def routine_seconds(cat, r, scale, pnf):
    """The same arithmetic as StretchSession's timeline, for the glance's lengths."""
    import stretch_catalogue as C
    if r["flags"] & RF_PRE and scale > 100:
        scale = 100   # holds stay short before an activity
    total = 0   # milliseconds, summed like the watch does
    prev = None
    for step in r["steps"]:
        st = cat[step[0]]
        dose, rounds = step[1], step[2]
        sides = 2 if st["flags"] & F_SIDED else 1
        pos = POS[st["pos"]]
        for rd in range(rounds):
            for sd in range(sides):
                if rd == 0 and sd == 0:
                    total += setup_ms(C, prev, pos) * 1000
                else:
                    total += (C.SETUP_SIDE if sd == 1 else C.SETUP_ROUND) * 1000
                if st["kind"] == KIND_REPS:
                    total += dose * st["tempo"] * 100
                elif st["kind"] == KIND_BREATH:
                    total += dose * 1000
                elif pnf and (r["flags"] & RF_PNF) and (st["flags"] & F_PNF) and rd == rounds - 1:
                    total += (C.PNF_HOLD + C.PNF_PUSH + C.PNF_RELAX + C.RELEASE) * 1000 \
                        + hold(C.PNF_DEEPEN, scale)
                else:
                    total += C.RELEASE * 1000 + hold(dose, scale)
        prev = pos
    return (total + 500) // 1000


def hold(dose, scale):
    """Milliseconds."""
    return max(5000, dose * scale * 10)


def main():
    import stretch_catalogue as C
    cat = {s["id"]: s for s in C.STRETCHES}
    order = [s["id"] for s in C.STRETCHES]
    index = {sid: i for i, sid in enumerate(order)}
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    src = os.path.join(root, "apps", "stretch", "source")

    poses, meta, names, cues = [], [], [], []
    for sid in order:
        st = cat[sid]
        poses += quant(st["a"].angles())[0] + quant(st["b"].angles())[0]
        if wall_back(st):
            st["flags"] |= F_WALL_BACK
        lift, x0, x1, top = frame(st)
        tbits = 0
        for t in st["targets"]:
            tbits |= 1 << TARGET_BITS[t]
        meta += [st["kind"], st["flags"], tbits & 0xFF, tbits >> 8,
                 byte(st["dose"], 1, 255, sid + " dose"), byte(st["tempo"], 0, 255, sid + " tempo"),
                 byte(int(round(x0 * 100)) + 128, 0, 255, sid + " x0"),
                 byte(int(round(x1 * 100)) + 128, 0, 255, sid + " x1"),
                 byte(int(round(top * 100)), 1, 255, sid + " top"),
                 byte(int(round(lift * 100)), 0, 255, sid + " lift"),
                 ANCHORS.index(st.get("anchor", "hip")),
                 byte(int(round(anchor_x(st) * 100)) + 128, 0, 255, sid + " anchor"),
                 POS[st["pos"]]]
        names.append(mc_string(st["name"]))
        if len(st["cues"]) != (5 if st["flags"] & F_PNF else 4):
            raise SystemExit(sid + ": setup, three cues in the stretch, and the push for contract-relax")
        for c in st["cues"]:
            if len(c) > 34:
                raise SystemExit(f"{sid}: cue too long for the watch ({len(c)}): {c}")
        cues.append("[" + ", ".join(mc_string(c) for c in st["cues"]) + "]")

    steps, rnames, rabout, rflags, rsecs, rconsts = [], [], [], [], [], []
    for i, r in enumerate(C.ROUTINES):
        b = []
        for step in r["steps"]:
            sid, dose, rounds = step
            if sid not in index:
                raise SystemExit(f"{r['name']}: no stretch {sid}")
            b += [index[sid], byte(dose, 1, 255, sid + " dose"), byte(rounds, 1, 9, sid + " rounds")]
        steps.append("[" + ", ".join(str(x) for x in b) + "]b")
        rnames.append(mc_string(r["name"]))
        rabout.append(mc_string(r["about"]))
        rflags.append(str(r["flags"]))
        rsecs.append("[" + ", ".join(str(routine_seconds(cat, r, s, False)) for s in C.LEVELS) + "]")
        rconsts.append(f"    const {r['const']} = {i};")

    n = len(order)
    head = ("// Generated by designs/gen_stretch.py from designs/stretch_catalogue.py.\n"
            "// Do not edit by hand: change the catalogue and run the generator.\n")
    data = f"""{head}import Toybox.Lang;

module StretchData {{

    const COUNT = {n};

    // Per stretch, pose A (the start) then pose B (the stretch): fourteen
    // angles each, degrees / 2. torso, head (from the upper back), near
    // upper arm, forearm, far upper arm, forearm, near thigh, shin, far
    // thigh, shin, near foot, far foot, the spine's bend, where the face
    // points. Near is the side being stretched.
    const POSES = [
{wrap([str(x) for x in poses], "        ")}
    ]b;

    // Per stretch, thirteen bytes: kind, flags, target bits (low, high),
    // hold seconds or reps, tenths of a second a rep, the box both poses
    // fill (x0 and x1 + 128, top, in hundredths of a body height), the
    // lift a close-up is cut at, the joint held in place and its x in pose
    // A (+ 128), and the starting position.
    const META = [
{wrap([str(x) for x in meta], "        ")}
    ]b;

    const NAMES = [
{wrap(names, "        ")}
    ] as Array<String>;

    // Getting into it, three lines to coach the hold, and the push for contract-relax
    const CUES = [
{chr(10).join("        " + c + "," for c in cues).rstrip(",")}
    ] as Array<Array<String> >;

    // Per routine, three bytes a step: stretch, hold seconds or reps, rounds
    const STEPS = [
{chr(10).join("        " + s + "," for s in steps).rstrip(",")}
    ] as Array<ByteArray>;
}}
"""
    routines = f"""{head}import Toybox.Lang;

// What the glance needs: names, what each is for, and lengths
(:glance)
module StretchRoutines {{

    const COUNT = {len(C.ROUTINES)};
{chr(10).join(rconsts)}

    const NAMES = [
{wrap(rnames, "        ")}
    ] as Array<String>;

    const ABOUT = [
{chr(10).join("        " + a + "," for a in rabout).rstrip(",")}
    ] as Array<String>;

    // 1 before an activity (holds stay short), 4 contract-relax allowed
    const FLAGS = [{", ".join(rflags)}] as Array<Number>;

    // Seconds at each level ({", ".join(str(s) for s in C.LEVELS)} %), without contract-relax
    const SECONDS = [
{chr(10).join("        " + s + "," for s in rsecs).rstrip(",")}
    ] as Array<Array<Number> >;
}}
"""
    os.makedirs(src, exist_ok=True)
    open(os.path.join(src, "StretchData.mc"), "w").write(data)
    open(os.path.join(src, "StretchRoutines.mc"), "w").write(routines)
    print(f"{n} stretches ({len(poses) + len(meta)} bytes of poses and framing), "
          f"{len(C.ROUTINES)} routines")
    for r, s in zip(C.ROUTINES, rsecs):
        print(f"  {r['name']}: {s} s")


if __name__ == "__main__":
    main()
