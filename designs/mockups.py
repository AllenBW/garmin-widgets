"""Render design mockups for the fēnix 8 Pro (454x454 round) as SVG.

Run from the repo root:  python3 designs/mockups.py
Writes one SVG per screen into designs/svg/.
These are sketches for layout and hierarchy, not pixel-exact renders: the watch
uses Garmin system fonts, approximated here with a condensed sans-serif.
"""
import math
import os

W = 454
C = W / 2
OUT = os.path.join(os.path.dirname(__file__), 'svg')

# Palette (AMOLED: true black background)
BG = '#000000'
WHITE = '#F2F2F2'
GRAY = '#8A8A8A'
DIM = '#5A5A5A'
TRACK = '#262626'
AMBER = '#FFB020'
CYAN = '#3EC6E0'
GREEN = '#46D18A'
ORANGE = '#FF7A3D'
RED = '#FF4D4D'
NIGHT = '#1A2A4A'

FONT = "font-family=\"'Roboto Condensed','Arial Narrow',Arial,sans-serif\""


def polar(r, deg):
    """Point at radius r, angle in degrees clockwise from 12 o'clock."""
    a = math.radians(deg)
    return C + r * math.sin(a), C - r * math.cos(a)


def arc(r, start, end, color, width, cap='round'):
    """Clockwise arc from start to end (degrees from 12 o'clock)."""
    sweep = (end - start) % 360
    if sweep == 0:
        return f'<circle cx="{C}" cy="{C}" r="{r}" fill="none" stroke="{color}" stroke-width="{width}"/>'
    x1, y1 = polar(r, start)
    x2, y2 = polar(r, end)
    large = 1 if sweep > 180 else 0
    return (f'<path d="M{x1:.1f},{y1:.1f} A{r},{r} 0 {large} 1 {x2:.1f},{y2:.1f}" fill="none" '
            f'stroke="{color}" stroke-width="{width}" stroke-linecap="{cap}"/>')


def text(x, y, s, size, color=WHITE, weight=400, anchor='middle', extra=''):
    return (f'<text x="{x:.1f}" y="{y:.1f}" font-size="{size}" fill="{color}" font-weight="{weight}" '
            f'text-anchor="{anchor}" dominant-baseline="middle" {FONT} {extra}>{s}</text>')


def outline_text(x, y, s, size, color=GRAY, width=1.6):
    """Hollow digits for always-on mode: only the glyph outline is lit."""
    return text(x, y, s, size, 'none', 300, extra=f'stroke="{color}" stroke-width="{width}"')


def screen(name, body, note=None):
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {W}" width="{W}" height="{W}">',
        f'<defs><clipPath id="face"><circle cx="{C}" cy="{C}" r="{C}"/></clipPath></defs>',
        f'<circle cx="{C}" cy="{C}" r="{C}" fill="{BG}"/>',
        f'<g clip-path="url(#face)">', body, '</g>',
        f'<circle cx="{C}" cy="{C}" r="{C - 1}" fill="none" stroke="#3a3a3a" stroke-width="2"/>',
    ]
    if note:
        parts.append(f'<!-- {note} -->')
    parts.append('</svg>')
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, f'{name}.svg'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(parts) + '\n')


def sun_marker(x, y, s, color, rise=True):
    """Small triangle: up for sunrise, down for sunset."""
    h = s / 2
    if rise:
        pts = f'{x:.1f},{y - h:.1f} {x - h:.1f},{y + h:.1f} {x + h:.1f},{y + h:.1f}'
    else:
        pts = f'{x:.1f},{y + h:.1f} {x - h:.1f},{y - h:.1f} {x + h:.1f},{y - h:.1f}'
    return f'<polygon points="{pts}" fill="{color}"/>'


def heart(x, y, s, color):
    return (f'<path transform="translate({x - s / 2:.1f},{y - s / 2:.1f}) scale({s / 24:.3f})" '
            f'd="M12 21s-7.5-4.6-10-9.2C.3 8.4 2.2 4.5 6 4.5c2.2 0 3.6 1.3 4.5 2.6l1.5 2 1.5-2c.9-1.3 2.3-2.6 4.5-2.6 3.8 0 5.7 3.9 4 7.3C19.5 16.4 12 21 12 21z" '
            f'fill="{color}"/>')


# ---------------------------------------------------------------------------
# Face 1: Field (everyday essentials)
# ---------------------------------------------------------------------------

def field_active():
    b = []
    # Bezel ring: progress to the daily step goal, clockwise from 12 o'clock
    b.append(arc(214, 0, 0, TRACK, 10))
    b.append(arc(214, 0, 360 * 0.70, AMBER, 10))
    # Date
    b.append(text(C, 112, 'TUE 27 OCT', 30, GRAY, 500, extra='letter-spacing="2"'))
    # Time
    b.append(text(C, 210, '10:08', 128, WHITE, 700))
    # Three tappable complication slots
    slots = [(117, 'HR', '62', RED), (227, 'STEPS', '8,412', WHITE), (337, 'BODY BATT', '74', GREEN)]
    for x, label, val, col in slots:
        b.append(text(x, 312, label, 17, DIM, 600, extra='letter-spacing="1"'))
        b.append(text(x, 345, val, 38, col, 600))
    b.append(heart(117, 286, 16, RED))
    # Footer: the next sun event only (weather + notifications is a setting)
    b.append(sun_marker(C - 34, 386, 12, ORANGE, rise=False))
    b.append(text(C + 12, 386, '17:41', 22, GRAY))
    screen('face-field-active', '\n'.join(b))


def field_aod():
    b = []
    # Shifted a few px (minute-based) and hollow: well under 10% of pixels lit
    dx, dy = 6, -4
    b.append(text(C + dx, 132 + dy, 'TUE 27', 24, DIM))
    b.append(outline_text(C + dx, 220 + dy, '10:08', 116, GRAY, 1.8))
    b.append(sun_marker(C + dx - 30, 327 + dy, 9, DIM, rise=False))
    b.append(text(C + dx + 12, 327 + dy, '17:41', 20, DIM))
    b.append(arc(206, 0, 360 * 0.70, '#4a3a10', 2))
    screen('face-field-aod', '\n'.join(b), 'AOD: hollow digits, next sun event, thin 2px hairline ring, shift +-12px per minute')


# ---------------------------------------------------------------------------
# Face 2: Daylight (24-hour sun dial, outdoors)
# ---------------------------------------------------------------------------

def hour_deg(h):
    """24h dial: noon at the top, midnight at the bottom."""
    return (h / 24 * 360 + 180) % 360


def daylight_active():
    b = []
    rise, sset, now = 6 + 52 / 60, 17 + 41 / 60, 10 + 8 / 60
    # Night band, then day band on top
    b.append(arc(196, 0, 0, NIGHT, 26))
    b.append(arc(196, hour_deg(rise), hour_deg(sset), AMBER, 26, cap='butt'))
    # Golden hour slices
    b.append(arc(196, hour_deg(sset - 0.75), hour_deg(sset), ORANGE, 26, cap='butt'))
    b.append(arc(196, hour_deg(rise), hour_deg(rise + 0.75), ORANGE, 26, cap='butt'))
    # Hour ticks and labels
    for h in range(24):
        r1 = 214 if h % 6 else 208
        x1, y1 = polar(r1, hour_deg(h))
        x2, y2 = polar(224, hour_deg(h))
        b.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{GRAY}" stroke-width="{3 if h % 6 == 0 else 1.5}"/>')
    for h, lab in [(0, '0'), (6, '6'), (12, '12'), (18, '18')]:
        x, y = polar(166, hour_deg(h))
        b.append(text(x, y, lab, 20, DIM, 600))
    # Sun hand
    x, y = polar(196, hour_deg(now))
    xi, yi = polar(150, hour_deg(now))
    b.append(f'<line x1="{xi:.1f}" y1="{yi:.1f}" x2="{x:.1f}" y2="{y:.1f}" stroke="{WHITE}" stroke-width="4" stroke-linecap="round"/>')
    b.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="15" fill="{WHITE}" stroke="{BG}" stroke-width="3"/>')
    # Centre stack
    b.append(text(C, 168, '7h 33m of light left', 20, AMBER, 500))
    b.append(text(C, 222, '10:08', 92, WHITE, 700))
    b.append(text(C, 278, '↑ 06:52   ↓ 17:41', 24, GRAY))
    b.append(text(C, 314, '1,240 m   1012 hPa ↘', 20, DIM))
    screen('face-daylight-active', '\n'.join(b))


def daylight_aod():
    b = []
    now = 10 + 8 / 60
    for h in (0, 6, 12, 18):
        x1, y1 = polar(206, hour_deg(h))
        x2, y2 = polar(222, hour_deg(h))
        b.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{DIM}" stroke-width="2"/>')
    x, y = polar(196, hour_deg(now))
    b.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="12" fill="none" stroke="{GRAY}" stroke-width="2"/>')
    b.append(outline_text(C - 4, 226, '10:08', 84, GRAY, 1.6))
    b.append(text(C - 4, 282, '↓ 17:41', 20, DIM))
    screen('face-daylight-aod', '\n'.join(b), 'AOD: cardinal ticks, hollow sun marker, hollow time')


# ---------------------------------------------------------------------------
# Face 3: Readiness (body metrics at a glance)
# ---------------------------------------------------------------------------

def readiness_active():
    b = []
    # Left gauge: Body Battery (bottom -> top, clockwise on the left side)
    b.append(arc(206, 205, 335, TRACK, 14))
    b.append(arc(206, 205, 205 + 130 * 0.74, GREEN, 14))
    # Right gauge: stress (counter-clockwise visual: drawn clockwise from 25 to 155, filled from the bottom)
    b.append(arc(206, 25, 155, TRACK, 14))
    b.append(arc(206, 155 - 130 * 0.28, 155, ORANGE, 14))
    lx, ly = polar(172, 270)
    rx, ry = polar(172, 90)
    b.append(text(lx + 4, ly - 16, '74', 34, GREEN, 700))
    b.append(text(lx + 4, ly + 14, 'BODY', 14, DIM, 600))
    b.append(text(rx - 4, ry - 16, '28', 34, ORANGE, 700))
    b.append(text(rx - 4, ry + 14, 'STRESS', 14, DIM, 600))
    b.append(text(C, 116, 'TUE 27 OCT', 26, GRAY, 500, extra='letter-spacing="2"'))
    b.append(text(C, 198, '10:08', 86, WHITE, 700))
    # Bottom tiles
    tiles = [(137, 'SLEEP', '82'), (227, 'RECOVERY', '14h'), (317, 'RHR', '48')]
    for x, label, val in tiles:
        b.append(text(x, 292, val, 36, WHITE, 600))
        b.append(text(x, 322, label, 15, DIM, 600, extra='letter-spacing="1"'))
    b.append(text(C, 378, 'Training: Productive', 20, CYAN, 500))
    screen('face-readiness-active', '\n'.join(b))


def readiness_aod():
    b = []
    b.append(outline_text(C + 4, 210, '10:08', 96, GRAY, 1.6))
    b.append(text(C + 4, 290, 'BB 74 · SLEEP 82', 22, DIM))
    screen('face-readiness-aod', '\n'.join(b), 'AOD: hollow time + one summary line')


# ---------------------------------------------------------------------------
# Glances: rendered as the glance loop (our row highlighted) and the full app
# ---------------------------------------------------------------------------

def glance_loop(name, title, big, sub, spark=None, accent=WHITE):
    b = []
    # Neighbouring native glances, dimmed
    b.append(text(C, 70, 'HEART RATE   62', 22, DIM))
    b.append(f'<line x1="70" y1="104" x2="384" y2="104" stroke="{TRACK}" stroke-width="2"/>')
    # Our glance row (selected)
    b.append(f'<rect x="38" y="122" width="378" height="210" rx="24" fill="#111" stroke="{accent}" stroke-width="2"/>')
    b.append(text(70, 160, title, 20, accent, 600, anchor='start', extra='letter-spacing="2"'))
    b.append(text(70, 218, big, 46, WHITE, 700, anchor='start'))
    b.append(text(70, 270, sub, 22, GRAY, 400, anchor='start'))
    if spark:
        pts = ' '.join(f'{300 + i * 14:.0f},{300 - v * 0.6:.0f}' for i, v in enumerate(spark))
        b.append(f'<polyline points="{pts}" fill="none" stroke="{accent}" stroke-width="3" stroke-linejoin="round"/>')
    b.append(f'<line x1="70" y1="350" x2="384" y2="350" stroke="{TRACK}" stroke-width="2"/>')
    b.append(text(C, 388, 'BODY BATTERY   74', 22, DIM))
    screen(name, '\n'.join(b))


def battery_app():
    b = []
    b.append(text(C, 76, 'BATTERY PLANNER', 20, CYAN, 600, extra='letter-spacing="2"'))
    b.append(text(C, 140, '6d 4h', 84, WHITE, 700))
    b.append(text(C, 196, 'at your 7-day pace · charge by Sun 2 Nov', 20, GRAY))
    # 7-day drain bars (% per day)
    drains = [9, 11, 8, 24, 10, 12, 9]
    days = ['W', 'T', 'F', 'S', 'S', 'M', 'T']
    x0, base = 112, 330
    for i, (d, lab) in enumerate(zip(drains, days)):
        h = d * 4
        col = ORANGE if d > 15 else CYAN
        b.append(f'<rect x="{x0 + i * 34}" y="{base - h}" width="22" height="{h}" rx="4" fill="{col}"/>')
        b.append(text(x0 + i * 34 + 11, base + 18, lab, 16, DIM, 600))
    b.append(text(C, 374, 'avg −11%/day · Sat −24% (3h activity)', 18, GRAY))
    screen('app-battery', '\n'.join(b))


def sun_app():
    b = []
    b.append(text(C, 70, 'SUN &amp; MOON', 20, AMBER, 600, extra='letter-spacing="2"'))
    # Horizon arc: half-ellipse from sunrise (left) to sunset (right)
    b.append(f'<line x1="40" y1="250" x2="414" y2="250" stroke="{DIM}" stroke-width="2"/>')
    b.append(f'<path d="M70,250 A157,130 0 0 1 384,250" fill="none" stroke="{AMBER}" stroke-width="3" stroke-dasharray="6 6"/>')
    t = (10 + 8 / 60 - (6 + 52 / 60)) / ((17 + 41 / 60) - (6 + 52 / 60))
    ang = math.pi * (1 - t)
    sx, sy = C + 157 * math.cos(ang), 250 - 130 * math.sin(ang)
    b.append(f'<circle cx="{sx:.1f}" cy="{sy:.1f}" r="16" fill="{AMBER}"/>')
    b.append(text(70, 274, '06:52', 20, GRAY))
    b.append(text(384, 274, '17:41', 20, GRAY))
    rows = [('Golden hour', '16:56', ORANGE), ('Blue hour', '17:58', CYAN), ('Moon', 'Waxing 78%', WHITE)]
    for i, (k, v, col) in enumerate(rows):
        y = 316 + i * 34
        b.append(text(110, y, k, 22, GRAY, 400, anchor='start'))
        b.append(text(344, y, v, 22, col, 600, anchor='end'))
    # Moon glyph next to the moon row
    b.append(f'<circle cx="368" cy="384" r="11" fill="{WHITE}"/><circle cx="361" cy="384" r="11" fill="{BG}" opacity="0.85"/>')
    screen('app-sun', '\n'.join(b))


if __name__ == '__main__':
    field_active()
    field_aod()
    daylight_active()
    daylight_aod()
    readiness_active()
    readiness_aod()
    glance_loop('glance-battery', 'BATTERY', '6d 4h left', 'charge by Sun 2 Nov',
                spark=[90, 80, 72, 50, 40, 30, 22], accent=CYAN)
    battery_app()
    glance_loop('glance-sun', 'SUN', 'Sunset 17:41', 'golden hour in 6h 48m', accent=AMBER)
    sun_app()
    print('wrote', len(os.listdir(OUT)), 'SVGs to', OUT)
