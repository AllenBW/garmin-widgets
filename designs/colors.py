#!/usr/bin/env python3
"""The colour dictionary: every named colour the project draws with, in
one place, by family. `designs/gen_colors.py` writes it to the library
(`Lib.Colors`, and the neon tubes and their sets to `Lib.Neon`) and checks
that the library draws with nothing that isn't named here.

A colour's name is its word in the settings and in the looks' titles, so a
name is never reused for another value, and a family's order is the order
watches have stored: new colours go at the end of their family.

    from colors import C, rgb, TUBES, NEON_SETS
    rgb("BONE")            # (242, 236, 226)
    rgb("TUBE_ROSE")
"""

# ---------------------------------------------------------------- families
# name: (0xRRGGBB, what it is for)

NEUTRALS = {
    "WHITE": (0xFFFFFF, "high visibility's text"),
    "BONE": (0xF2ECE2, "the data colour most faces open with"),
    "SILVER": (0xB4BAC2, "data colour"),
    "SAND": (0xE6CFA0, "data colour; Gold's and Ember's neutral"),
    "ICE": (0xCFE6FF, "data colour"),
    "BLUSH": (0xF8D2D8, "data colour; Dusk's neutral"),
    "CREAM": (0xF0D2A8, "low light's text"),
    "PARCHMENT": (0xD9C08F, "low light's weather"),
}

ACCENTS = {
    "AMBER": (0xFFB020, "accent; the sun's family"),
    "LIME": (0x8CE03C, "accent"),
    "SKY": (0x38A8FF, "accent"),
    "FLAME": (0xFF5A36, "accent"),
    "MINT": (0x2EE6B0, "accent"),
    "VIOLET": (0xA77BFF, "accent"),
    "ROSE": (0xFF5C9E, "accent; the body's family"),
    "GOLD": (0xE8D44A, "accent"),
    "AZURE": (0x4DB2FF, "the weather's family in a face's own colours"),
}

FLUORESCENTS = {
    "BLAZE": (0xFF6A13, "fluorescent orange: high visibility's accent"),
    "VOLT": (0x5CFF2E, "fluorescent green"),
    "FLARE": (0xD4FF1A, "fluorescent yellow-green"),
    "ARC": (0x2EA8FF, "electric blue"),
    "SUNBEAM": (0xFFD21A, "high visibility orange's weather"),
    "PUNCH": (0xFF3D6E, "high visibility orange's body"),
    "CYAN": (0x2EF0E0, "high visibility blue's weather"),
    "ORCHID": (0xB48CFF, "high visibility blue's body"),
    "SPRING": (0x2EF0B0, "high visibility green's body"),
    "CERISE": (0xFF4F7A, "Flare's body"),
}

NIGHT = {
    "GLOW": (0xFF9A3C, "low light's accent"),
    "COAL": (0xE8785A, "low light's body"),
    "BEDSIDE": (0x8C2A1C, "a dim ember red that keeps night vision"),
}

# The muted weeks (Lib.Numbers.MUTED): each set's neutral, sun, weather, body
MUTED = {
    "SAGE": (0xE3E0D0, 0xD9A15C, 0x8DB08A, 0xC48A80),
    "SMOKE": (0xDED6CC, 0xE39B5B, 0x9AA7BF, 0xB98AA6),
    "UMBER": (0xE3CFB2, 0xC8843C, 0x7E9A9E, 0xA86B73),
    "SLATE": (0xDCE0E2, 0xD8A26A, 0x6F9CC4, 0xBF8697),
    "CLAY": (0xEADBC8, 0xE0894A, 0x86A9A3, 0xB87A8F),
    "OCHRE": (0xE8DFC9, 0xD4A548, 0x7C9CB5, 0xBD7F8C),
}
MUTED_PARTS = ("NEUTRAL", "SUN", "WEATHER", "BODY")

# ---------------------------------------------------------------- neon
# Only colours a sign shop bends: a gas, and the glass or the phosphor
# coating it glows through. Red-family tubes are neon gas; blues, greens
# and whites are argon with mercury. The values are the halo's colour, a
# little under a photograph's so a face stays muted; the tube's core is the
# same colour washed toward white (CORE). The gases and glasses are the
# sign trade's standard chart as remembered, not yet checked against a
# maker's (EGL, Voltarc) list.
# name: (0xRRGGBB, gas, glass, the word in the settings)
TUBES = {
    "ROSE": (0xE83E6C, "neon", "pink-coated", "Rose"),
    "TURQUOISE": (0x18B0AA, "argon and mercury", "turquoise-coated", "Turquoise"),
    "AMBER": (0xEC9224, "neon", "gold-coated", "Amber"),
    "RUBY": (0xD81E36, "neon", "ruby glass", "Ruby"),
    "RED": (0xFF4422, "neon", "clear", "Neon red"),
    "ORANGE": (0xFF7420, "neon", "orange-coated", "Orange"),
    "CORAL": (0xFF6A62, "neon", "coral-coated", "Coral"),
    "MAGENTA": (0xEC3CA4, "neon", "purple-coated", "Magenta"),
    "PURPLE": (0x9458F0, "argon and mercury", "purple-coated", "Purple"),
    "LAVENDER": (0xA99CF2, "argon", "clear", "Lavender"),
    "COBALT": (0x2C6CF4, "argon and mercury", "cobalt glass", "Cobalt"),
    "HORIZON": (0x52B4F2, "argon and mercury", "blue-coated", "Horizon blue"),
    "GREEN": (0x2CCB6A, "argon and mercury", "green-coated", "Green"),
    "LEMON": (0xEED43A, "argon and mercury", "yellow-coated", "Lemon"),
    "WARM_WHITE": (0xF4D2A2, "argon and mercury", "warm white-coated", "Warm white"),
    "SNOW": (0xDCE8F4, "argon and mercury", "cool white-coated", "Snow white"),
}
CORE = 0.45                    # how far a tube's core is washed toward white
STANDBY = (0.25, 0.62)         # standby: washed this far, at this brightness, no halo

# The neon faces' sets: the hours' tube, the minutes', the details'. The
# daily look steps through them, one a day, as the other faces' personas.
NEON_SETS = {
    "DOWNTOWN": ("ROSE", "TURQUOISE", "AMBER"),
    "MOTEL": ("RED", "HORIZON", "WARM_WHITE"),
    "ARCADE": ("MAGENTA", "COBALT", "LEMON"),
    "DINER": ("GREEN", "CORAL", "WARM_WHITE"),
    "RAIN": ("HORIZON", "LAVENDER", "SNOW"),
    "ORCHID": ("PURPLE", "ROSE", "AMBER"),
    "LAST CALL": ("RUBY", "AMBER", "WARM_WHITE"),
}
# Lib.Look's other looks in tubes: high visibility is a white sign with one
# strong colour, low light the warm end of the chart
NEON_LOOKS = {
    "BRIGHT": ("SNOW", "RED", "SNOW"),
    "BRIGHT_BLUE": ("SNOW", "HORIZON", "SNOW"),
    "BRIGHT_GREEN": ("SNOW", "GREEN", "SNOW"),
    "LOW": ("WARM_WHITE", "AMBER", "AMBER"),
}

# ---------------------------------------------------------------- the dictionary

C = {}
for family in (NEUTRALS, ACCENTS, FLUORESCENTS, NIGHT):
    for name, (value, _) in family.items():
        C[name] = value
for name, values in MUTED.items():
    for part, value in zip(MUTED_PARTS, values):
        C[f"{name}_{part}"] = value
for name, (value, *_) in TUBES.items():
    C[f"TUBE_{name}"] = value
assert len(set(C.values())) == len(C), "two names for one colour"


def rgb(name):
    v = C[name]
    return (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF


def wash(c, k):
    """An (r, g, b) taken k of the way to white."""
    return tuple(int(v + (255 - v) * k) for v in c)


def core(c):
    """A lit tube's core."""
    return wash(c, CORE)


def standby(c):
    """A tube in standby."""
    return tuple(int(v * STANDBY[1]) for v in wash(c, STANDBY[0]))
