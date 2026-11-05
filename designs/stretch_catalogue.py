# The stretches and routines of Stretching God (design #20), from the
# research in designs/stretch_research.md. Read by
# designs/gen_stretch.py (the watch's tables) and designs/preview_stretch.py
# (the contact sheet). Poses are joint angles, with two-bone IK where a hand
# or foot must land on something. Facing right, y up; near is the side
# being stretched (the figure's left; mirrored for the right).
from gen_stretch import (Pose, pt, KIND_HOLD, KIND_REPS, KIND_BREATH, F_FRONT, F_CLOSEUP,
                         F_SIDED, F_WALL, F_PNF, F_CHAIR, RF_PRE, RF_PNF, SEAT_BACK)

# Phase lengths in seconds; StretchSession.mc uses the same numbers
SETUP_FIRST, SETUP_FIRST_DOWN = 8, 10          # the first stretch, standing or on the floor
SETUP_SAME, SETUP_STEP = 5, 7                  # the next stretch: same position, or another
SETUP_GET_DOWN, SETUP_GET_UP = 10, 8           # down to the floor, back up
SETUP_SIDE, SETUP_ROUND = 4, 3
EASE, RELEASE = 4, 3                           # the ease-in counts toward the hold
PNF_HOLD, PNF_PUSH, PNF_RELAX, PNF_DEEPEN = 10, 5, 3, 20
LEVELS = (75, 100, 150)   # gentle, standard, deep: percent of each hold

STRETCHES = []


def stretch(id, name, a, b, targets, dose, cues, pos, kind=KIND_HOLD, tempo=0, flags=0,
            anchor="hip", top=False):
    STRETCHES.append(dict(id=id, name=name, a=a, b=b, targets=targets, dose=dose, cues=cues,
                          pos=pos, kind=kind, tempo=tempo, flags=flags, anchor=anchor, top=top))


def reps(id, name, a, b, targets, dose, tempo, cues, pos, flags=0, anchor="hip"):
    stretch(id, name, a, b, targets, dose, cues, pos, kind=KIND_REPS, tempo=tempo, flags=flags,
            anchor=anchor)


# ---- Starting shapes

def stand(**k):
    return Pose(**k)


def wide(**k):
    """Standing, seen from the front, feet apart."""
    d = dict(nth=-82, fth=-98)
    d.update(k)
    return Pose(front=True, **d)


def front(**k):
    return Pose(front=True, **k)


def seated(**k):
    """On a chair, hands on the thighs."""
    d = dict(nth=0, fth=-2, nsh=-90, fsh=-92)
    d.update(k)
    p = Pose(**d)
    if "nua" not in k:
        p.reach("n", "arm", (0.17, 0.035), -1)
    if "fua" not in k:
        p.reach("f", "arm", (0.15, 0.035), -1)
    return p


def supine(**k):
    """On the back, head to the left, knees bent, feet flat."""
    d = dict(torso=180, nth=55, nsh=-55, fth=50, fsh=-60, nfoot=0, ffoot=0,
             nua=0, nfa=0, fua=-2, ffa=-2)
    d.update(k)
    return Pose(**d)


def prone(**k):
    """Face down, head to the right."""
    d = dict(torso=0, head=-10, nth=180, nsh=180, fth=181, fsh=181, nfoot=205, ffoot=205)
    d.update(k)
    return Pose(**d)


def all4(**k):
    d = dict(torso=0, nth=-90, nsh=180, fth=-91, fsh=181, nfoot=180, ffoot=180,
             nua=-90, nfa=-90, fua=-89, ffa=-89)
    d.update(k)
    return Pose(**d)


def kneel_lunge(**k):
    """Half kneeling: near (back) knee down, far foot forward."""
    d = dict(torso=92, nth=-112, nsh=180, nfoot=182, fth=-5, fsh=-90)
    d.update(k)
    p = Pose(**d)
    p.reach("n", "arm", p.joints()["fkn"], -1)
    p.reach("f", "arm", p.joints()["fkn"], -1)
    return p


# ---- Neck

stretch("neck_side_tilt", "Neck tilt", front(), front(head=-30, fua=-98, ffa=-96),
        ["neck"], 20,
        ["Sit tall, shoulders down", "Ear toward shoulder", "Keep other shoulder low",
         "Chin stays level"], "chair", flags=F_FRONT | F_CLOSEUP | F_SIDED)

stretch("neck_rotation", "Neck turn", front(), front(yaw=72), ["neck"], 5,
        ["Sit tall, look ahead", "Turn head as far as easy", "Shoulders stay still",
         "Return slowly to centre"], "chair", flags=F_FRONT | F_CLOSEUP | F_SIDED)

reps("chin_tuck", "Chin tuck", seated(head=-14), seated(head=8), ["neck"], 8, 40,
     ["Sit tall, eyes level", "Slide chin straight back", "Eyes stay level",
      "Grow tall through the crown"], "chair", flags=F_CLOSEUP | F_CHAIR)

# ---- Shoulders and chest

b = stand(torso=86, bend=-6, nua=180, nfa=181)
stretch("wall_pec", "Wall chest", stand(nua=-150, nfa=-160), b, ["nua"], 30,
        ["Side to a wall, palm on it", "Hand just below shoulder", "Turn chest away slowly",
         "Shoulder stays down", "Press palm into the wall"], "wall",
        flags=F_SIDED | F_WALL | F_PNF | F_CLOSEUP)

b = front()
b.reach("n", "arm", pt(b.joints()["fso"], 185, 0.13), -1)
b.reach("f", "arm", b.joints()["nel"], +1)
stretch("cross_arm", "Cross arm", front(), b, ["nua"], 30,
        ["Stand tall, arm across chest", "Pull elbow across chest", "Shoulder stays down",
         "Torso faces forward"], "stand", flags=F_FRONT | F_CLOSEUP | F_SIDED)

stretch("chest_opener", "Chest opener", seated(),
        seated(bend=-10, head=6, nua=-118, nfa=-130, fua=-116, ffa=-128),
        ["nua"], 20,
        ["Sit forward, hands behind", "Push chest forward and up", "Squeeze shoulder blades",
         "Neck stays long"], "chair", flags=F_CHAIR)

reps("arm_circles", "Arm circles", stand(nua=-80, nfa=-78, fua=-76, ffa=-74),
     stand(nua=104, nfa=108, fua=108, ffa=112), ["nua", "fua"], 12, 20,
     ["Stand tall, arms loose", "Start small, grow bigger", "Big slow circles",
      "Keep ribs down"], "stand")

reps("shoulder_rolls", "Shoulder rolls", stand(head=-6, nua=-80, nfa=-84),
     stand(bend=-8, head=4, nua=-112, nfa=-100, fua=-110, ffa=-98), ["neck"], 10, 30,
     ["Arms loose at your sides", "Lift, roll back, drop", "Slow full circles",
      "Finish back and down"], "stand", flags=F_CLOSEUP)

# ---- Upper back

reps("cat_cow", "Cat-cow", all4(bend=-14, head=28), all4(bend=22, head=-42), ["torso"], 6, 80,
     ["Hands under shoulders", "Breathe out, round your back", "Breathe in, lift your chest",
      "Move through the middle"], "all4")

p = seated()
p.reach("n", "arm", pt(p.joints()["head"], 170, 0.07), -1)
p.reach("f", "arm", pt(p.joints()["head"], 165, 0.07), -1)
q = seated(torso=100, bend=-14, head=12)
q.reach("n", "arm", pt(q.joints()["head"], 185, 0.07), -1)
q.reach("f", "arm", pt(q.joints()["head"], 180, 0.07), -1)
reps("chair_extension", "Chair arch", p, q, ["torso"], 6, 60,
     ["Sit back, hands behind head", "Arch over the chair back", "Lead with your breastbone",
      "Ribs stay down"], "chair", flags=F_CHAIR)

stretch("side_bend", "Side bend", front(nua=150, nfa=110),
        front(torso=102, bend=-12, head=6, nua=118, nfa=152, fua=-112, ffa=-108),
        ["torso"], 15,
        ["Feet hip-width, arm overhead", "Reach up and over", "Hips stay level",
         "Don't lean forward"], "stand", flags=F_FRONT | F_CLOSEUP | F_SIDED)

reps("torso_rotation", "Torso twist", wide(nua=182, nfa=180, fua=178, ffa=176, yaw=-60),
     wide(nua=2, nfa=0, fua=-2, ffa=-4, yaw=60), ["torso"], 10, 30,
     ["Feet wide, arms loose", "Turn from the ribs", "Hips face forward",
      "Let your arms swing"], "stand", flags=F_FRONT)

p = seated()
q = seated(yaw=150)
q.reach("n", "arm", (-SEAT_BACK - 0.01, 0.17), +1)
q.reach("f", "arm", q.joints()["nkn"], -1)
stretch("seated_twist", "Seated twist", p, q, ["torso"], 15,
        ["Sit tall, hand on chair back", "Lengthen, then turn", "Turn from your mid back",
         "Hips stay square"], "chair", flags=F_SIDED | F_CHAIR)

# ---- Lower back

p = supine(bend=6, nth=115, nsh=-20, fth=112, fsh=-24, nfoot=70, ffoot=70)
p.reach("n", "arm", pt(p.joints()["nkn"], -60, 0.06), -1)
p.reach("f", "arm", pt(p.joints()["fkn"], -60, 0.06), -1)
stretch("knees_to_chest", "Knees to chest", supine(), p, ["torso"], 30,
        ["Lie on your back, knees bent", "Hug knees to chest", "Low back softens down",
         "Breathe into your belly"], "floor")

# seen from above: arms out, knees fall to the near side, the face turns away
stretch("supine_twist", "Lying twist",
        Pose(front=True, torso=180, nua=90, nfa=90, fua=-90, ffa=-90, nth=0, fth=0, nsh=0, fsh=0,
             nfoot=0, ffoot=0),
        Pose(front=True, torso=180, nua=90, nfa=90, fua=-90, ffa=-90, nth=78, fth=70, nsh=-5,
             fsh=-12, nfoot=0, ffoot=0, yaw=-70),
        ["torso"], 30,
        ["Lie on your back, knees bent", "Knees fall to one side", "Both shoulders stay down",
         "Breathe and let go"], "floor", flags=F_FRONT | F_SIDED, top=True)

stretch("sphinx", "Sphinx", prone(nua=4, nfa=2, fua=6, ffa=4),
        prone(torso=30, bend=-10, head=-28, nua=-90, nfa=2, fua=-92, ffa=0), ["torso"], 30,
        ["Lie face down on forearms", "Elbows under shoulders", "Hips stay on the floor",
         "Relax your low back"], "floor")

stretch("child_pose", "Child's pose",
        Pose(torso=60, nth=-25, nsh=180, nfoot=180, fth=-25, fsh=180, ffoot=180,
             nua=-80, nfa=-80, fua=-80, ffa=-80),
        Pose(torso=-4, bend=14, head=10, nth=-30, nsh=178, nfoot=180, fth=-30, fsh=178, ffoot=180,
             nua=-8, nfa=-6, fua=-6, ffa=-4),
        ["torso"], 45,
        ["Kneel, sit back to your heels", "Reach your arms forward", "Sink hips to heels",
         "Breathe into your back"], "kneel")

# ---- Hips

stretch("kneeling_hip_flexor", "Hip flexor", kneel_lunge(),
        kneel_lunge(torso=95, bend=-4, nth=-128, fth=-18, fsh=-95), ["nth"], 30,
        ["Half kneel, front knee at 90°", "Tuck your tailbone under", "Squeeze the back glute",
         "Shift hips forward", "Press back knee into floor"], "kneel",
        flags=F_SIDED | F_PNF, anchor="nkn")

a = supine()
a.reach("n", "leg", pt(a.joints()["fkn"], 10, 0.03), -1)
b = supine(fth=100, fsh=10, ffoot=100)
b.reach("n", "leg", pt(b.joints()["fkn"], 10, 0.03), -1)
for p in (a, b):
    p.reach("n", "arm", pt(p.joints()["fkn"], 190, 0.08), -1)
    p.reach("f", "arm", pt(p.joints()["fkn"], 190, 0.08), -1)
stretch("figure_four", "Figure four", a, b, ["nth"], 30,
        ["On your back, ankle over knee", "Pull thigh toward chest", "Knee opens out",
         "Head stays down", "Press knee out into hand"], "floor", flags=F_SIDED | F_PNF)

a = seated()
a.reach("n", "leg", pt(a.joints()["fkn"], 95, 0.03), +1)
b = seated(torso=68)
b.reach("n", "leg", pt(b.joints()["fkn"], 95, 0.03), +1)
for p in (a, b):
    p.reach("n", "arm", p.joints()["nkn"], -1)
    p.reach("f", "arm", p.joints()["nan"], -1)
stretch("chair_figure_four", "Chair figure 4", a, b, ["nth"], 20,
        ["Sit tall, ankle on knee", "Hinge forward from hips", "Keep your spine long",
         "Let the knee relax down"], "chair", flags=F_SIDED | F_CHAIR)

def butterfly(knees):
    p = Pose(front=True, nth=-knees, fth=-180 + knees)
    j = p.joints()
    p.reach("n", "leg", (0.035, -0.035), +1)
    p.reach("f", "leg", (-0.035, -0.035), -1)
    p.a["nfoot"], p.a["ffoot"] = 180, 0
    j = p.joints()
    p.reach("n", "arm", j["nan"], +1)
    p.reach("f", "arm", j["fan"], -1)
    return p


stretch("butterfly", "Butterfly", butterfly(30), butterfly(12), ["nth", "fth"], 30,
        ["Sit, soles of feet together", "Sit tall on your sit bones", "Let your knees fall open",
         "Hold feet, don't push", "Lift knees into elbows"], "floor", flags=F_FRONT | F_PNF)

reps("hip_circles", "Hip circles",
     wide(torso=84).plant(wide(), (-0.05, 0)), wide(torso=96).plant(wide(), (0.05, 0)),
     ["torso"], 16, 20,
     ["Hands on hips, knees soft", "Draw big slow circles", "Change direction halfway",
      "Head stays still"], "stand", flags=F_FRONT, anchor="nan")
for st in STRETCHES[-1:]:
    for p in (st["a"], st["b"]):
        j = p.joints()
        p.reach("n", "arm", pt(j["nho"], 30, 0.03), +1)
        p.reach("f", "arm", pt(j["fho"], 150, 0.03), -1)

reps("glute_bridge", "Glute bridge", supine(),
     supine(torso=214, fua=-4, nua=-2).plant(supine(), (0.0, 0.17)), ["nth", "fth"], 10, 40,
     ["On your back, feet hip-width", "Press heels, lift hips", "Squeeze glutes at the top",
      "Ribs stay down"], "floor", anchor="nan")

reps("side_lunge", "Side lunge", wide(nth=-62, fth=-118),
     wide(nth=-62, fth=-118).plant(wide(nth=-62, fth=-118), (0.10, -0.08), 1, 1),
     ["fth"], 6, 40,
     ["Feet wide, toes forward", "Sit back into one hip", "Other leg stays straight",
      "Chest stays up"], "stand", flags=F_FRONT | F_SIDED, anchor="nan")

# ---- Hamstrings, quads

a = supine(nth=88, nsh=-5, nfoot=85)
a.reach("n", "arm", pt(a.joints()["nkn"], 180, 0.05), -1)
a.reach("f", "arm", pt(a.joints()["nkn"], 180, 0.06), -1)
b = supine(nth=96, nsh=94, nfoot=184)
b.reach("n", "arm", pt(b.joints()["nkn"], -90, 0.0), -1)
b.reach("f", "arm", pt(b.joints()["nkn"], -90, 0.02), -1)
stretch("supine_hamstring", "Hamstring", a, b, ["nth"], 30,
        ["On your back, hold your thigh", "Straighten the knee slowly", "Other leg stays bent",
         "Hips stay down", "Press heel away into hands"], "floor", flags=F_SIDED | F_PNF)

s = stand(nth=-108, nsh=88, nfoot=178, fua=-20, ffa=-5)
s.reach("n", "arm", s.joints()["nan"], -1)
stretch("standing_quad", "Standing quad", stand(fua=-20, ffa=-5), s, ["nth"], 30,
        ["Hand on a wall, hold one foot", "Knees side by side", "Tuck your tailbone a little",
         "Stand tall", "Press foot back into hand"], "wall",
        flags=F_SIDED | F_WALL | F_PNF, anchor="fan")

# ---- Calves and ankles

stretch("wall_calf", "Wall calf",
        Pose(torso=80, nth=-122, nsh=-122, nfoot=-5, fth=-65, fsh=-100, nua=8, nfa=12, fua=2, ffa=8),
        Pose(torso=74, nth=-128, nsh=-128, nfoot=-5, fth=-55, fsh=-110, nua=5, nfa=10, fua=-2, ffa=5),
        ["nsh"], 30,
        ["Hands on a wall, one leg back", "Back heel stays down", "Back knee straight",
         "Toes point forward", "Press the ball of the foot"], "wall",
        flags=F_SIDED | F_WALL | F_PNF, anchor="nan")

stretch("soleus_calf", "Soleus calf",
        Pose(torso=84, nth=-112, nsh=-112, nfoot=-3, fth=-70, fsh=-100, nua=6, nfa=10, fua=0, ffa=6),
        Pose(torso=82, nth=-98, nsh=-128, nfoot=-3, fth=-60, fsh=-112, nua=4, nfa=8, fua=-2, ffa=4),
        ["nsh"], 30,
        ["Like the wall calf, step closer", "Bend the back knee", "Heel stays down",
         "Sink your hips down"], "wall", flags=F_SIDED | F_WALL, anchor="nan")

a = Pose(torso=86, nth=-78, nsh=-95, fth=-108, fsh=-110, fua=-6, ffa=4, nua=-8, nfa=2)
b = Pose(torso=84, fth=-108, fsh=-110, fua=-6, ffa=4, nua=-8, nfa=2)
b.plant(a, (0.05, -0.03), 1, 1)
reps("ankle_rocks", "Ankle rocks", a, b, ["nsh"], 10, 20,
     ["Foot near a wall, knee forward", "Knee toward the wall", "Heel stays down",
      "Knee tracks over your toes"], "wall", flags=F_SIDED | F_WALL, anchor="nan")

reps("calf_raises", "Calf raises", stand(nua=-30, nfa=-10, fua=-28, ffa=-8),
     stand(nua=-30, nfa=-10, fua=-28, ffa=-8, nfoot=-48, ffoot=-48), ["nsh", "fsh"], 12, 20,
     ["Stand tall, fingers on a wall", "Rise onto the balls of your feet", "Pause at the top",
      "Lower slowly"], "wall", flags=F_WALL, anchor="nto")

# ---- Wrists

b = stand(nua=0, nfa=0)
b.reach("f", "arm", pt(b.joints()["nha"], 175, 0.01), -1)
stretch("wrist_flexor", "Wrist flexor", stand(nua=-60, nfa=-20), b, ["nfa"], 20,
        ["Arm straight, palm up", "Pull fingers back gently", "Elbow stays straight",
         "Shoulder stays down"], "stand", flags=F_SIDED | F_CLOSEUP)

# ---- Moving warm-up

reps("march", "March", stand(nth=0, nsh=-92, nua=-125, nfa=-100, fua=-55, ffa=-15),
     stand(fth=0, fsh=-92, fua=-125, ffa=-100, nua=-55, nfa=-15), ["nth", "fth"], 20, 20,
     ["Stand tall", "Lift knees, swing arms", "Breathe easy", "Pick up the pace"], "stand")

reps("leg_swing_fb", "Leg swing", stand(nth=-140, nsh=-145, fua=-10, ffa=0),
     stand(nth=-30, nsh=-55, fua=-10, ffa=0), ["nth"], 10, 15,
     ["Hand on a wall, stand tall", "Swing forward and back", "Grow the range each swing",
      "Trunk stays upright"], "wall", flags=F_SIDED | F_WALL, anchor="fan")

reps("leg_swing_side", "Side swing", front(nth=-118, nsh=-112, nua=-60, nfa=95, fua=-120, ffa=85),
     front(nth=-38, nsh=-42, nua=-60, nfa=95, fua=-120, ffa=85), ["nth"], 10, 15,
     ["Face a wall, hands on it", "Swing across and out", "Hips face the wall",
      "Grow the range each swing"], "wall", flags=F_FRONT | F_SIDED, anchor="fan")

a = stand()
b = stand(torso=92, nth=-112, nsh=-168, nfoot=-100, fth=-22, fsh=-92, nua=96, nfa=94, fua=98, ffa=96)
reps("lunge_reach", "Lunge & reach", a, b, ["nth"], 5, 40,
     ["Stand tall, then step forward", "Lunge, reach your arms up", "Front knee over ankle",
      "Push back to stand"], "stand", flags=F_SIDED, anchor="nto")

a = Pose(torso=28, head=-20, nth=-125, nsh=-128, nfoot=-60, fth=-30, fsh=-95)
a.reach("n", "arm", pt(a.joints()["fan"], 180, 0.09), -1)
a.reach("f", "arm", pt(a.joints()["fan"], 180, 0.06), -1)
b = Pose(torso=34, head=30, yaw=90, nth=-125, nsh=-128, nfoot=-60, fth=-30, fsh=-95, fua=92, ffa=92)
b.reach("n", "arm", pt(b.joints()["fan"], 180, 0.09), -1)
reps("worlds_greatest", "World's best", a, b, ["nth", "torso"], 3, 80,
     ["Step into a long lunge", "Elbow to your front instep", "Turn, reach the arm high",
      "Back knee off the floor"], "stand", flags=F_SIDED, anchor="fan")

reps("air_squat", "Air squat", stand(nua=-80, nfa=-80, fua=-78, ffa=-78),
     stand(torso=62, bend=-4, nth=-10, nsh=-118, fth=-12, fsh=-116, nua=4, nfa=4, fua=6, ffa=6),
     ["nth", "fth"], 8, 30,
     ["Feet shoulder-width", "Sit hips back and down", "Knees follow your toes",
      "Chest stays up"], "stand", anchor="nan")

a = Pose(torso=-75, bend=16, head=-10, nth=-88, nsh=-90, fth=-90, fsh=-92)
a.reach("n", "arm", pt(a.joints()["nto"], 0, 0.06), -1)
a.reach("f", "arm", pt(a.joints()["fto"], 0, 0.05), -1)
b = Pose(torso=8, head=-14, nth=188, nsh=188, fth=187, fsh=187, nfoot=255, ffoot=255,
         nua=-90, nfa=-90, fua=-91, ffa=-91)
reps("inchworm", "Inchworm", a, b, ["nth", "fth"], 4, 100,
     ["Stand, hands to the floor", "Walk your hands to a plank", "Hips stay level",
      "Walk your feet up to your hands"], "stand", anchor="nto")

# ---- Breathing

# the hands on the belly rise as it fills
a = supine()
a.reach("n", "arm", (0.0, 0.07), -1)
a.reach("f", "arm", (0.01, 0.065), -1)
b = supine(bend=-4)
b.reach("n", "arm", (0.0, 0.10), -1)
b.reach("f", "arm", (0.01, 0.095), -1)
stretch("belly_breath", "Slow breath", a, b, ["torso"], 60,
        ["Lie down, a hand on your belly", "In for five, belly rises", "Out for five, let go",
         "Shoulders stay soft"], "floor", kind=KIND_BREATH)


# ---- Routines: (stretch, hold seconds or reps, rounds); see DESIGNS.md #20

ROUTINES = [
    dict(const="R_MORNING", name="Morning", about="Gentle, no forward bends", flags=0,
         steps=[("march", 10, 1), ("shoulder_rolls", 10, 1), ("neck_side_tilt", 15, 1),
                ("chin_tuck", 6, 1), ("arm_circles", 12, 1), ("cat_cow", 6, 1),
                ("side_bend", 15, 1), ("torso_rotation", 8, 1), ("hip_circles", 16, 1),
                ("kneeling_hip_flexor", 30, 1), ("wall_calf", 30, 1)]),
    dict(const="R_QUICK", name="Quick 5", about="Hips, legs, chest and neck", flags=0,
         steps=[("march", 8, 1), ("cat_cow", 6, 1), ("worlds_greatest", 3, 1),
                ("standing_quad", 15, 1), ("wall_calf", 15, 1), ("wall_pec", 15, 1),
                ("neck_side_tilt", 15, 1)]),
    dict(const="R_DESK", name="Desk break", about="Undo sitting, no floor", flags=0,
         steps=[("chin_tuck", 6, 1), ("neck_side_tilt", 15, 1), ("chest_opener", 20, 1),
                ("chair_extension", 4, 1), ("seated_twist", 15, 1), ("chair_figure_four", 15, 1),
                ("wrist_flexor", 15, 1)]),
    dict(const="R_BEDTIME", name="Before bed", about="Long holds, slow breaths", flags=0,
         steps=[("belly_breath", 60, 1), ("wall_calf", 30, 1), ("child_pose", 45, 1),
                ("supine_hamstring", 40, 1), ("figure_four", 40, 1), ("butterfly", 40, 1),
                ("supine_twist", 30, 1), ("knees_to_chest", 40, 1), ("belly_breath", 60, 1)]),
    dict(const="R_FULL", name="Full body", about="60 s a muscle, when warm", flags=RF_PNF,
         steps=[("wall_pec", 30, 2), ("cross_arm", 30, 1), ("kneeling_hip_flexor", 30, 2),
                ("standing_quad", 30, 2), ("supine_hamstring", 30, 2), ("figure_four", 30, 2),
                ("butterfly", 30, 2), ("wall_calf", 30, 2), ("child_pose", 30, 1)]),
    dict(const="R_BEFORE_RUN", name="Before a run", about="Moving warm-up, no holds", flags=RF_PRE,
         steps=[("march", 22, 1), ("leg_swing_fb", 10, 1), ("leg_swing_side", 10, 1),
                ("hip_circles", 16, 1), ("ankle_rocks", 10, 1), ("calf_raises", 12, 1),
                ("lunge_reach", 5, 1), ("worlds_greatest", 3, 1), ("air_squat", 8, 1)]),
    dict(const="R_AFTER_RUN", name="After a run", about="Calves, quads and hips",
         flags=RF_PNF,
         steps=[("wall_calf", 30, 1), ("soleus_calf", 30, 1), ("standing_quad", 30, 1),
                ("kneeling_hip_flexor", 30, 1), ("supine_hamstring", 30, 1), ("figure_four", 30, 1),
                ("butterfly", 30, 1), ("belly_breath", 30, 1)]),
    dict(const="R_BEFORE_RIDE", name="Before a ride", about="Hips, back and neck",
         flags=RF_PRE,
         steps=[("march", 15, 1), ("cat_cow", 6, 1), ("hip_circles", 16, 1), ("leg_swing_fb", 10, 1),
                ("air_squat", 8, 1), ("worlds_greatest", 3, 1), ("torso_rotation", 8, 1),
                ("neck_rotation", 5, 2)]),
    dict(const="R_AFTER_RIDE", name="After a ride", about="Open the hips and chest",
         flags=RF_PNF,
         steps=[("kneeling_hip_flexor", 30, 2), ("standing_quad", 30, 1), ("supine_hamstring", 30, 1),
                ("figure_four", 30, 1), ("sphinx", 30, 1), ("wall_pec", 30, 1), ("chin_tuck", 6, 1)]),
    dict(const="R_BEFORE_LIFT", name="Before lifting", about="Warm up, wake the glutes",
         flags=RF_PRE,
         steps=[("march", 22, 1), ("arm_circles", 12, 1), ("cat_cow", 6, 1), ("glute_bridge", 10, 1),
                ("leg_swing_fb", 10, 1), ("side_lunge", 6, 1), ("worlds_greatest", 3, 1),
                ("inchworm", 3, 1), ("air_squat", 10, 1)]),
    dict(const="R_AFTER_LIFT", name="After lifting", about="One hold a big muscle",
         flags=RF_PNF,
         steps=[("child_pose", 30, 1), ("wall_pec", 30, 1), ("cross_arm", 30, 1),
                ("kneeling_hip_flexor", 30, 1), ("standing_quad", 30, 1), ("supine_hamstring", 30, 1),
                ("figure_four", 30, 1), ("butterfly", 30, 1)]),
    dict(const="R_BEFORE_HIKE", name="Before a hike", about="Ankles, calves and hips",
         flags=RF_PRE,
         steps=[("march", 22, 1), ("ankle_rocks", 10, 1), ("calf_raises", 12, 1),
                ("leg_swing_fb", 10, 1), ("leg_swing_side", 10, 1), ("hip_circles", 16, 1),
                ("lunge_reach", 5, 1), ("air_squat", 8, 1)]),
]
