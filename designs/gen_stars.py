# Generate apps/nightsky/source/Stars.mc from the Yale Bright Star Catalog JSON
# (https://raw.githubusercontent.com/aduboisforge/Bright-Star-Catalog-JSON/master/BSC.json):
#   python3 -I designs/gen_stars.py BSC.json apps/nightsky/source/Stars.mc
# every star to magnitude LIMIT plus the asterism members, and the asterism lines.
import json, math, sys
src, out = sys.argv[1], sys.argv[2]
LIMIT = 3.6
raw = json.load(open(src))
def parse(star):
    ra = star['RA']; dec = star['DEC']; mag = star.get('MAG', '')
    try:
        h, m, s = [float(x) for x in ra.split(':')]
        sign = -1 if dec.strip().startswith('-') else 1
        dd, dm, ds = [float(x) for x in dec.strip().lstrip('+-').split(':')]
        return (h + m / 60 + s / 3600) * 15.0, sign * (dd + dm / 60 + ds / 3600), float(mag)
    except Exception:
        return None
stars = [p for p in (parse(s) for s in raw) if p]
print(len(stars), 'stars parsed')

# Asterisms: approximate J2000 degrees; each is matched to the nearest catalogue star
A = {
 'Betelgeuse': (88.8, 7.4), 'Bellatrix': (81.3, 6.3), 'Mintaka': (83.0, -0.3), 'Alnilam': (84.1, -1.2), 'Alnitak': (85.2, -1.9), 'Saiph': (86.9, -9.7), 'Rigel': (78.6, -8.2),
 'Dubhe': (165.9, 61.8), 'Merak': (165.5, 56.4), 'Phecda': (178.5, 53.7), 'Megrez': (183.9, 57.0), 'Alioth': (193.5, 56.0), 'Mizar': (201.0, 54.9), 'Alkaid': (206.9, 49.3),
 'Caph': (2.3, 59.1), 'Schedar': (10.1, 56.5), 'GamCas': (14.2, 60.7), 'Ruchbah': (21.5, 60.2), 'Segin': (28.6, 63.7),
 'Deneb': (310.4, 45.3), 'Sadr': (305.6, 40.3), 'Albireo': (292.7, 28.0), 'DelCyg': (296.2, 45.1), 'EpsCyg': (311.6, 34.0),
 'Vega': (279.2, 38.8), 'Altair': (297.7, 8.9), 'Tarazed': (296.6, 10.6), 'Alshain': (298.8, 6.4),
 'Antares': (247.4, -26.4), 'TauSco': (248.97, -28.2), 'EpsSco': (252.5, -34.3), 'ZetSco': (253.6, -42.4), 'EtaSco': (258.0, -43.2), 'Sargas': (264.3, -43.0), 'IotSco': (266.9, -40.1), 'KapSco': (265.6, -39.0), 'Shaula': (263.4, -37.1), 'Lesath': (262.7, -37.3), 'SigSco': (245.3, -25.6), 'Dschubba': (240.1, -22.6), 'Acrab': (241.4, -19.8), 'PiSco': (239.7, -26.1),
 'Regulus': (152.1, 12.0), 'EtaLeo': (151.8, 16.8), 'Algieba': (154.99, 19.8), 'ZetLeo': (154.2, 23.4), 'MuLeo': (148.2, 26.0), 'EpsLeo': (146.5, 23.8), 'Zosma': (168.5, 20.5), 'Denebola': (177.3, 14.6), 'Chertan': (168.6, 15.4),
 'Castor': (113.65, 31.9), 'Pollux': (116.3, 28.0), 'TauGem': (107.8, 30.2), 'Mebsuta': (100.98, 25.1), 'MuGem': (95.7, 22.5), 'Wasat': (110.0, 22.0), 'Mekbuda': (106.0, 20.6), 'Alhena': (99.4, 16.4), 'UpsGem': (113.98, 26.9),
 'Aldebaran': (69.0, 16.5), 'The2Tau': (67.2, 15.9), 'GamTau': (64.9, 15.6), 'DelTau': (65.7, 17.5), 'EpsTau': (67.2, 19.2), 'Elnath': (81.6, 28.6), 'ZetTau': (84.4, 21.1),
 'Sirius': (101.3, -16.7), 'Mirzam': (95.7, -18.0), 'Wezen': (107.1, -26.4), 'Adhara': (104.7, -29.0), 'Aludra': (111.0, -29.3),
 'Acrux': (186.65, -63.1), 'Mimosa': (191.9, -59.7), 'Gacrux': (187.8, -57.1), 'DelCru': (183.8, -58.7),
 'RigilKent': (219.9, -60.8), 'Hadar': (210.96, -60.4),
 'Markab': (346.2, 15.2), 'Scheat': (345.9, 28.1), 'Algenib': (3.3, 15.2), 'Alpheratz': (2.1, 29.1), 'DelAnd': (9.8, 30.9), 'Mirach': (17.4, 35.6), 'Almach': (30.97, 42.3),
 'Arcturus': (213.9, 19.2), 'Izar': (221.2, 27.1), 'DelBoo': (228.9, 33.3), 'Nekkar': (225.5, 40.4), 'GamBoo': (218.0, 38.3), 'Muphrid': (208.7, 18.4), 'RhoBoo': (217.96, 30.4),
 'KausAus': (276.0, -34.4), 'KausMed': (275.2, -29.8), 'KausBor': (276.99, -25.4), 'Alnasl': (271.5, -30.4), 'Ascella': (285.65, -29.9), 'PhiSgr': (281.4, -27.0), 'Nunki': (283.8, -26.3), 'TauSgr': (286.7, -27.7),
 'Mirfak': (51.1, 49.9), 'Algol': (47.0, 40.96), 'GamPer': (46.2, 53.5), 'DelPer': (55.7, 47.8), 'EpsPer': (59.5, 40.0), 'ZetPer': (58.5, 31.9),
 'Capella': (79.2, 46.0), 'Menkalinan': (89.9, 44.9), 'TheAur': (89.9, 37.2), 'IotAur': (74.2, 33.2), 'EpsAur': (75.5, 43.8),
 'Polaris': (37.95, 89.26), 'Kochab': (222.7, 74.2), 'Pherkad': (230.2, 71.8), 'DelUMi': (263.05, 86.6), 'EpsUMi': (251.5, 82.0), 'ZetUMi': (236.0, 77.8), 'EtaUMi': (244.4, 75.8),
 'Spica': (201.3, -11.2), 'Porrima': (190.4, -1.4), 'EtaVir': (184.98, -0.7), 'DelVir': (193.9, 3.4), 'Vindemiatrix': (195.5, 10.96),
}
LINES = [
 ('Betelgeuse','Bellatrix'),('Bellatrix','Mintaka'),('Mintaka','Alnilam'),('Alnilam','Alnitak'),('Alnitak','Saiph'),('Saiph','Rigel'),('Rigel','Mintaka'),('Betelgeuse','Alnitak'),
 ('Dubhe','Merak'),('Merak','Phecda'),('Phecda','Megrez'),('Megrez','Dubhe'),('Megrez','Alioth'),('Alioth','Mizar'),('Mizar','Alkaid'),
 ('Caph','Schedar'),('Schedar','GamCas'),('GamCas','Ruchbah'),('Ruchbah','Segin'),
 ('Deneb','Sadr'),('Sadr','Albireo'),('Sadr','DelCyg'),('Sadr','EpsCyg'),
 ('Vega','Deneb'),('Deneb','Altair'),('Altair','Vega'),('Altair','Tarazed'),('Altair','Alshain'),
 ('Antares','SigSco'),('SigSco','Dschubba'),('Dschubba','Acrab'),('Dschubba','PiSco'),('Antares','TauSco'),('TauSco','EpsSco'),('EpsSco','ZetSco'),('ZetSco','EtaSco'),('EtaSco','Sargas'),('Sargas','IotSco'),('IotSco','KapSco'),('KapSco','Shaula'),('Shaula','Lesath'),
 ('Regulus','EtaLeo'),('EtaLeo','Algieba'),('Algieba','ZetLeo'),('ZetLeo','MuLeo'),('MuLeo','EpsLeo'),('Algieba','Zosma'),('Zosma','Denebola'),('Denebola','Chertan'),('Chertan','Regulus'),('Zosma','Chertan'),
 ('Castor','TauGem'),('TauGem','Mebsuta'),('Mebsuta','MuGem'),('Pollux','UpsGem'),('UpsGem','Wasat'),('Wasat','Mekbuda'),('Mekbuda','Alhena'),
 ('Aldebaran','The2Tau'),('The2Tau','GamTau'),('GamTau','DelTau'),('DelTau','EpsTau'),('EpsTau','Elnath'),('Aldebaran','ZetTau'),
 ('Sirius','Mirzam'),('Sirius','Wezen'),('Wezen','Adhara'),('Wezen','Aludra'),
 ('Acrux','Gacrux'),('Mimosa','DelCru'),('RigilKent','Hadar'),
 ('Markab','Scheat'),('Scheat','Alpheratz'),('Alpheratz','Algenib'),('Algenib','Markab'),('Alpheratz','DelAnd'),('DelAnd','Mirach'),('Mirach','Almach'),
 ('Arcturus','Izar'),('Izar','DelBoo'),('DelBoo','Nekkar'),('Nekkar','GamBoo'),('GamBoo','RhoBoo'),('RhoBoo','Arcturus'),('Arcturus','Muphrid'),
 ('KausBor','KausMed'),('KausMed','Alnasl'),('KausMed','KausAus'),('KausAus','Ascella'),('Ascella','PhiSgr'),('PhiSgr','KausBor'),('PhiSgr','Nunki'),('Nunki','TauSgr'),('TauSgr','Ascella'),
 ('Mirfak','Algol'),('Mirfak','GamPer'),('Mirfak','DelPer'),('DelPer','EpsPer'),('EpsPer','ZetPer'),
 ('Capella','Menkalinan'),('Menkalinan','TheAur'),('TheAur','Elnath'),('Elnath','IotAur'),('IotAur','EpsAur'),('EpsAur','Capella'),
 ('Polaris','DelUMi'),('DelUMi','EpsUMi'),('EpsUMi','ZetUMi'),('ZetUMi','Kochab'),('Kochab','Pherkad'),('Pherkad','EtaUMi'),('EtaUMi','ZetUMi'),
 ('Spica','Porrima'),('Porrima','EtaVir'),('Porrima','DelVir'),('DelVir','Vindemiatrix'),
]
def sep(a, b):
    ra1, d1 = math.radians(a[0]), math.radians(a[1]); ra2, d2 = math.radians(b[0]), math.radians(b[1])
    return math.degrees(math.acos(max(-1, min(1, math.sin(d1)*math.sin(d2) + math.cos(d1)*math.cos(d2)*math.cos(ra1-ra2)))))
chosen = {}   # index in `stars` -> True
named = {}
for name, approx in A.items():
    best = None
    for idx, s in enumerate(stars):
        if s[2] > 5.0: continue
        d = sep(approx, s)
        if d < 1.3 and (best is None or d < best[0]): best = (d, idx)
    if best is None:
        print('UNMATCHED', name, approx); continue
    named[name] = best[1]; chosen[best[1]] = True
    if best[0] > 0.6: print('  weak match', name, round(best[0], 2), stars[best[1]])
for idx, s in enumerate(stars):
    if s[2] <= LIMIT: chosen[idx] = True
order = sorted(chosen, key=lambda i: stars[i][2])
pos = {idx: k for k, idx in enumerate(order)}
ra = [round(stars[i][0] * 10) for i in order]
dec = [round(stars[i][1] * 10) for i in order]
mag = [round(stars[i][2] * 10) for i in order]
lines = []
for a, b in LINES:
    if a in named and b in named: lines += [pos[named[a]], pos[named[b]]]
    else: print('line skipped', a, b)
def fmt(name, values, per=20):
    rows = [', '.join(str(v) for v in values[i:i+per]) for i in range(0, len(values), per)]
    return f'    const {name} = [\n        ' + ',\n        '.join(rows) + '\n    ] as Array<Number>;\n'
with open(out, 'w') as f:
    f.write('import Toybox.Lang;\n\n')
    f.write(f'// Generated by designs/gen_stars.py from the Yale Bright Star Catalog (J2000):\n')
    f.write(f'// the {len(order)} stars to magnitude {LIMIT} plus the members of {len(set(a for l in LINES for a in l))} asterism stars,\n')
    f.write('// brightest first. RA and DEC are degrees x 10, MAG is magnitude x 10, LINES\n')
    f.write('// holds index pairs to join. Regenerate rather than edit.\nmodule Stars {\n\n')
    f.write(f'    const COUNT = {len(order)};\n\n')
    f.write(fmt('RA', ra)); f.write('\n'); f.write(fmt('DEC', dec)); f.write('\n'); f.write(fmt('MAG', mag)); f.write('\n'); f.write(fmt('LINES', lines, 24))
    f.write('}\n')
print(len(order), 'stars written,', len(lines) // 2, 'lines; brightest:', [stars[i] for i in order[:5]])
