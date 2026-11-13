"""Genererer seks SVG-udkast (5:7) til Steamgears Prints i en fælles palet."""
import math, os, sys, random

OUT = sys.argv[1]
W, H = 500, 700
P = dict(brass="#C29A4B", brass_d="#8C6A2C", copper="#B4643C", copper_l="#D08A5C",
         teal="#1F4E52", teal_d="#143437", cream="#EFE3C8", cream_d="#E2D2AE",
         ink="#1B1A17", red="#9A3328", navy="#18233A", patina="#5E8C7A")
GRAIN = """<filter id="grain" x="0" y="0" width="100%" height="100%">
<feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="7" result="n"/>
<feColorMatrix in="n" type="saturate" values="0"/>
<feComponentTransfer><feFuncA type="table" tableValues="0 0.10"/></feComponentTransfer>
<feBlend in="SourceGraphic" mode="multiply"/></filter>"""


def gear(cx, cy, r, teeth, depth=None, hole=None, fill=P["brass"], stroke="none", sw=0, rot=0):
    depth = depth or r * 0.16
    pts = []
    n = teeth * 4
    for i in range(n):
        a = rot + 2 * math.pi * i / n
        rr = r if (i % 4) in (1, 2) else r - depth
        pts.append(f"{cx + rr * math.cos(a):.2f},{cy + rr * math.sin(a):.2f}")
    d = "M" + " L".join(pts) + " Z"
    s = f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round"/>'
    if hole:
        s += f'<circle cx="{cx}" cy="{cy}" r="{hole}" fill="{stroke if fill == "none" else P["ink"]}" opacity="{0 if fill == "none" else 0.85}"/>'
    return s


def gear_line(cx, cy, r, teeth, color, sw=1.4, spokes=0, hub=None):
    s = gear(cx, cy, r, teeth, fill="none", stroke=color, sw=sw)
    s += f'<circle cx="{cx}" cy="{cy}" r="{r * 0.62}" fill="none" stroke="{color}" stroke-width="{sw}"/>'
    for i in range(spokes):
        a = 2 * math.pi * i / spokes
        s += (f'<line x1="{cx + r * 0.18 * math.cos(a):.1f}" y1="{cy + r * 0.18 * math.sin(a):.1f}" '
              f'x2="{cx + r * 0.62 * math.cos(a):.1f}" y2="{cy + r * 0.62 * math.sin(a):.1f}" stroke="{color}" stroke-width="{sw}"/>')
    s += f'<circle cx="{cx}" cy="{cy}" r="{hub or r * 0.18}" fill="none" stroke="{color}" stroke-width="{sw}"/>'
    return s


def svg(body, bg, defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">'
            f'<defs>{GRAIN}{defs}</defs><g filter="url(#grain)"><rect width="{W}" height="{H}" fill="{bg}"/>{body}</g></svg>')


def text(x, y, t, size, fill, family="Inter Display", weight=600, ls=0, anchor="middle", style="normal"):
    return (f'<text x="{x}" y="{y}" font-family="{family}" font-size="{size}" font-weight="{weight}" '
            f'letter-spacing="{ls}" text-anchor="{anchor}" font-style="{style}" fill="{fill}">{t}</text>')


# 1 · Art deco: Skyskraberen (motiv 11)
def deco():
    b = []
    cx = W / 2
    for i in range(-14, 15):
        a = math.radians(90 + i * 6.2)
        x2, y2 = cx + 900 * math.cos(a), 250 - 900 * math.sin(a)
        b.append(f'<line x1="{cx}" y1="250" x2="{x2:.0f}" y2="{y2:.0f}" stroke="{P["brass"]}" stroke-width="{1.6 if i % 2 else 0.6}" opacity="{0.55 if i % 2 else 0.35}"/>')
    b.append(f'<circle cx="{cx}" cy="250" r="70" fill="{P["ink"]}" stroke="{P["brass"]}" stroke-width="2"/>')
    for r in (58, 46):
        b.append(f'<circle cx="{cx}" cy="250" r="{r}" fill="none" stroke="{P["brass"]}" stroke-width="0.8"/>')
    # trappet tårn
    tiers = [(150, 600, 640), (120, 470, 600), (92, 380, 470), (66, 300, 380), (40, 225, 300), (18, 170, 225)]
    for w2, top, bot in tiers:
        b.append(f'<rect x="{cx - w2}" y="{top}" width="{2 * w2}" height="{bot - top}" fill="{P["ink"]}" stroke="{P["brass"]}" stroke-width="1.6"/>')
        for k in range(-w2 + 10, w2 - 4, 14):
            b.append(f'<line x1="{cx + k}" y1="{top + 8}" x2="{cx + k}" y2="{bot - 4}" stroke="{P["brass"]}" stroke-width="0.7" opacity="0.7"/>')
    b.append(f'<line x1="{cx}" y1="70" x2="{cx}" y2="170" stroke="{P["brass"]}" stroke-width="3"/>')
    b.append(f'<polygon points="{cx - 10},170 {cx + 10},170 {cx},120" fill="{P["brass"]}"/>')
    # vinduer med lys
    random.seed(3)
    for w2, top, bot in tiers[:4]:
        for k in range(-w2 + 17, w2 - 4, 14):
            for yy in range(top + 18, bot - 10, 22):
                if random.random() < 0.18:
                    b.append(f'<rect x="{cx + k - 3}" y="{yy}" width="6" height="9" fill="{P["brass"]}" opacity="0.9"/>')
    b.append(f'<rect x="27" y="640" width="{W - 54}" height="33" fill="{P["ink"]}"/>')
    b.append(f'<rect x="18" y="18" width="{W - 36}" height="{H - 36}" fill="none" stroke="{P["brass"]}" stroke-width="2"/>')
    b.append(f'<rect x="26" y="26" width="{W - 52}" height="{H - 52}" fill="none" stroke="{P["brass"]}" stroke-width="0.8"/>')
    b.append(text(cx, 663, "SKYSKRABEREN", 18, P["brass"], weight=500, ls=9))
    return svg("".join(b), "#121212")


# 2 · Mekanisk botanik: Rosa mechanica (motiv 51)
def botanik():
    b = []
    cx, cy = 250, 270
    c = P["copper"]
    b.append(f'<path d="M{cx},{cy + 60} C{cx - 8},{cy + 170} {cx + 10},{cy + 260} {cx - 4},{cy + 340}" fill="none" stroke="{P["brass_d"]}" stroke-width="7"/>')
    for t in (0.25, 0.5, 0.75):
        y = cy + 60 + 280 * t
        b.append(f'<circle cx="{cx + (2 if t != 0.5 else -2)}" cy="{y:.0f}" r="3" fill="{P["brass"]}"/>')
    for sx, y0, rot in ((1, cy + 170, -28), (-1, cy + 240, 24)):
        x0 = cx + 2 * sx
        leaf = (f'M{x0},{y0} C{x0 + sx * 40},{y0 - 50} {x0 + sx * 110},{y0 - 40} {x0 + sx * 130},{y0 - 70} '
                f'C{x0 + sx * 100},{y0 + 5} {x0 + sx * 50},{y0 + 15} {x0},{y0} Z')
        b.append(f'<path d="{leaf}" fill="{P["patina"]}" opacity="0.85" stroke="{P["ink"]}" stroke-width="1"/>')
        b.append(f'<path d="M{x0},{y0} Q{x0 + sx * 70},{y0 - 28} {x0 + sx * 126},{y0 - 66}" fill="none" stroke="{P["ink"]}" stroke-width="0.8"/>')
    for ring, (n, rr, sc) in enumerate(((9, 92, 1.0), (7, 68, 0.85), (5, 46, 0.7))):
        for i in range(n):
            a = 2 * math.pi * (i + ring * 0.5) / n
            px, py = cx + rr * 0.55 * math.cos(a), cy + rr * 0.55 * math.sin(a)
            deg = math.degrees(a) + 90
            col = [c, P["copper_l"], c][ring]
            b.append(f'<ellipse cx="{px:.1f}" cy="{py:.1f}" rx="{30 * sc:.0f}" ry="{44 * sc:.0f}" transform="rotate({deg:.0f} {px:.1f} {py:.1f})" '
                     f'fill="{col}" stroke="{P["ink"]}" stroke-width="1" opacity="0.95"/>')
    b.append(gear(cx, cy, 26, 12, fill=P["brass"], stroke=P["ink"], sw=1))
    b.append(f'<circle cx="{cx}" cy="{cy}" r="7" fill="{P["ink"]}"/>')
    b.append(f'<rect x="30" y="30" width="{W - 60}" height="{H - 60}" fill="none" stroke="{P["ink"]}" stroke-width="1"/>')
    b.append(text(250, 72, "Tab. LI", 14, P["ink"], family="DejaVu Serif", weight=400, ls=3))
    b.append(text(250, 640, "Rosa mechanica", 30, P["ink"], family="DejaVu Serif", weight=400, style="italic"))
    b.append(text(250, 664, "MEKANISK ROSE · HERBARIUM MECHANICUM", 9, P["ink"], weight=500, ls=3))
    return svg("".join(b), P["cream"])


# 3 · Det mekaniske cirkus (motiv 41)
def cirkus():
    b = []
    random.seed(11)
    for _ in range(70):
        x, y, r = random.uniform(30, 470), random.uniform(30, 330), random.uniform(0.6, 1.8)
        b.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r:.1f}" fill="{P["cream"]}" opacity="0.8"/>')
    cx, top, eave, base = 250, 170, 330, 600
    stripes = 12
    for i in range(stripes):
        x0 = 70 + (360 / stripes) * i
        x1 = x0 + 360 / stripes
        col = P["red"] if i % 2 == 0 else P["cream"]
        b.append(f'<polygon points="{cx},{top} {x0:.1f},{eave} {x1:.1f},{eave}" fill="{col}"/>')
        b.append(f'<rect x="{x0:.1f}" y="{eave}" width="{360 / stripes:.1f}" height="{base - eave}" fill="{col}"/>')
    for i in range(stripes):
        x0 = 70 + (360 / stripes) * i
        b.append(f'<path d="M{x0:.1f},{eave} q{180 / stripes:.1f},26 {360 / stripes:.1f},0" fill="{P["brass"]}" stroke="{P["brass_d"]}" stroke-width="1"/>')
    b.append(f'<path d="M215,{base} L215,450 Q250,410 285,450 L285,{base} Z" fill="{P["ink"]}"/>')
    b.append(f'<line x1="{cx}" y1="{top}" x2="{cx}" y2="105" stroke="{P["brass"]}" stroke-width="3"/>')
    b.append(gear(cx, 98, 16, 10, fill=P["brass"], stroke=P["brass_d"], sw=1, hole=4))
    b.append(f'<polygon points="{cx + 2},70 {cx + 2},84 {cx + 30},77" fill="{P["red"]}"/>')
    b.append(f'<line x1="{cx}" y1="70" x2="{cx}" y2="84" stroke="{P["brass"]}" stroke-width="2"/>')
    for side in (-1, 1):
        for i in range(1, 7):
            t = i / 7
            x, y = cx + side * 180 * t, top + (eave - top) * t
            b.append(f'<polygon points="{x - 6:.0f},{y + 4:.0f} {x + 6:.0f},{y + 4:.0f} {x:.0f},{y + 17:.0f}" fill="{P["brass"] if i % 2 else P["cream"]}" stroke="{P["brass_d"]}" stroke-width="0.6"/>')
        b.append(f'<line x1="{cx}" y1="{top + 2}" x2="{cx + side * 180}" y2="{eave + 2}" stroke="{P["brass_d"]}" stroke-width="1"/>')
    b.append(f'<rect x="0" y="{base}" width="{W}" height="{H - base}" fill="{P["ink"]}"/>')
    for x in (60, 440):
        b.append(f'<polygon points="{x},640 {x + 6},652 {x + 19},652 {x + 9},660 {x + 13},673 {x},665 {x - 13},673 {x - 9},660 {x - 19},652 {x - 6},652" fill="{P["brass"]}"/>')
    b.append(text(cx, 645, "DET MEKANISKE", 18, P["cream"], weight=500, ls=7))
    b.append(text(cx, 678, "CIRKUS", 34, P["brass"], weight=800, ls=10))
    b.append(f'<rect x="16" y="16" width="{W - 32}" height="{H - 32}" fill="none" stroke="{P["brass"]}" stroke-width="1.5"/>')
    return svg("".join(b), P["navy"])


# 4 · Patenttegning: dampmaskine, personlig (motiv 7)
def patent():
    c = P["cream"]
    b = []
    for x in range(40, W - 39, 20):
        b.append(f'<line x1="{x}" y1="40" x2="{x}" y2="{H - 40}" stroke="{c}" stroke-width="0.3" opacity="0.25"/>')
    for y in range(40, H - 39, 20):
        b.append(f'<line x1="40" y1="{y}" x2="{W - 40}" y2="{y}" stroke="{c}" stroke-width="0.3" opacity="0.25"/>')
    b.append(gear_line(170, 260, 105, 28, c, sw=1.6, spokes=6, hub=16))
    b.append(gear_line(318, 168, 44, 14, c, sw=1.4, spokes=4))
    b.append(f'<rect x="250" y="330" width="170" height="70" fill="none" stroke="{c}" stroke-width="1.6"/>')
    b.append(f'<rect x="262" y="342" width="60" height="46" fill="none" stroke="{c}" stroke-width="1" stroke-dasharray="4 3"/>')
    b.append(f'<line x1="170" y1="260" x2="292" y2="365" stroke="{c}" stroke-width="1.6"/>')
    b.append(f'<circle cx="292" cy="365" r="5" fill="none" stroke="{c}" stroke-width="1.4"/>')
    b.append(f'<rect x="70" y="400" width="370" height="28" fill="none" stroke="{c}" stroke-width="1.6"/>')
    for x in (90, 420):
        b.append(f'<line x1="{x}" y1="428" x2="{x}" y2="446" stroke="{c}" stroke-width="1.6"/>')
    b.append(f'<line x1="65" y1="140" x2="65" y2="380" stroke="{c}" stroke-width="0.8"/>')
    for y in (140, 380):
        b.append(f'<line x1="58" y1="{y}" x2="72" y2="{y}" stroke="{c}" stroke-width="0.8"/>')
    b.append(text(58, 264, "Ø 210", 10, c, family="JetBrains Mono", weight=400, anchor="end"))
    for (x, y, lbl) in ((170, 150, "A"), (318, 112, "B"), (430, 322, "C"), (300, 455, "D")):
        b.append(text(x, y, lbl, 12, c, family="JetBrains Mono", weight=500))
    b.append(text(250, 92, "STEAM ENGINE · FIG. 1", 14, c, family="JetBrains Mono", weight=500, ls=4))
    b.append(f'<rect x="250" y="540" width="200" height="110" fill="none" stroke="{c}" stroke-width="1.2"/>')
    for y in (568, 596, 624):
        b.append(f'<line x1="250" y1="{y}" x2="450" y2="{y}" stroke="{c}" stroke-width="0.8"/>')
    rows = [("PATENT NO.", "1"), ("INVENTOR", "A. HANSEN"), ("DATE", "13.11.2026"), ("SCALE", "1:20")]
    for i, (k, v) in enumerate(rows):
        y = 559 + 28 * i
        b.append(text(260, y, k, 9, c, family="JetBrains Mono", weight=400, anchor="start"))
        b.append(text(440, y, v, 11, P["brass"] if k == "INVENTOR" else c, family="JetBrains Mono", weight=600, anchor="end"))
    b.append(text(60, 650, "personligt felt: navn →", 9, P["brass"], family="JetBrains Mono", weight=400, anchor="start"))
    b.append(f'<rect x="40" y="40" width="{W - 80}" height="{H - 80}" fill="none" stroke="{c}" stroke-width="1.6"/>')
    return svg("".join(b), P["teal"])


# 5 · Emaljeskilt, personligt (motiv 26)
def skilt():
    b = []
    b.append(f'<rect x="40" y="70" width="420" height="560" rx="28" fill="{P["teal"]}" stroke="{P["cream"]}" stroke-width="10"/>')
    b.append(f'<rect x="62" y="92" width="376" height="516" rx="16" fill="none" stroke="{P["cream"]}" stroke-width="2"/>')
    for x, y in ((70, 100), (430, 100), (70, 600), (430, 600)):
        b.append(f'<circle cx="{x}" cy="{y}" r="7" fill="{P["brass"]}" stroke="{P["brass_d"]}" stroke-width="2"/>')
    b.append(gear(250, 250, 78, 16, fill=P["brass"], stroke=P["brass_d"], sw=2))
    b.append(f'<circle cx="250" cy="250" r="50" fill="{P["teal"]}"/>')
    for deg in (45, -45):
        b.append(f'<g transform="rotate({deg} 250 250)"><rect x="244" y="190" width="12" height="120" rx="4" fill="{P["cream"]}"/>'
                 f'<circle cx="250" cy="190" r="16" fill="{P["cream"]}"/><rect x="243" y="172" width="14" height="22" fill="{P["teal"]}"/>'
                 f'<circle cx="250" cy="310" r="12" fill="{P["cream"]}"/></g>')
    b.append(text(250, 395, "MADS'", 58, P["cream"], weight=800, ls=6))
    b.append(text(250, 452, "VÆRKSTED", 44, P["brass"], weight=700, ls=8))
    b.append(f'<line x1="120" y1="485" x2="380" y2="485" stroke="{P["cream"]}" stroke-width="2"/>')
    b.append(text(250, 520, "ÅBENT · REPARATION · KAFFE", 15, P["cream"], weight=500, ls=3))
    b.append(text(250, 572, "EST. 2026", 15, P["brass"], weight=600, ls=6))
    b.append(text(250, 672, "personligt felt: navn (“MADS'”)", 11, P["brass_d"], family="JetBrains Mono", weight=400))
    rust = "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{P["copper"]}" opacity="0.25"/>'
                   for x, y, r in ((88, 140, 12), (420, 580, 16), (400, 120, 7), (95, 560, 9)))
    return svg("".join(b) + rust, P["cream_d"])


# 6 · Rejseplakat: Nordlys-ekspressen, personlig by (motiv 17)
def rejse():
    defs = (f'<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0E1A2B"/><stop offset="1" stop-color="{P["teal_d"]}"/></linearGradient>'
            f'<linearGradient id="aur" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#7FD6B0" stop-opacity="0"/>'
            f'<stop offset="0.6" stop-color="#7FD6B0" stop-opacity="0.55"/><stop offset="1" stop-color="{P["patina"]}" stop-opacity="0"/></linearGradient>'
            '<filter id="soft" x="-10%" y="-30%" width="120%" height="160%"><feGaussianBlur stdDeviation="9"/></filter>')
    b = [f'<rect width="{W}" height="{H}" fill="url(#sky)"/>']
    random.seed(5)
    for _ in range(60):
        b.append(f'<circle cx="{random.uniform(20, 480):.0f}" cy="{random.uniform(20, 300):.0f}" r="{random.uniform(0.5, 1.4):.1f}" fill="{P["cream"]}" opacity="0.8"/>')
    for k, (y, amp) in enumerate(((150, 40), (200, 55), (120, 30))):
        d = f"M-20,{y} " + " ".join(f"Q{x + 50},{y - amp * (1 if i % 2 else -1)} {x + 100},{y}" for i, x in enumerate(range(-20, 520, 100)))
        b.append(f'<path d="{d} L520,{y + 140} L-20,{y + 140} Z" fill="url(#aur)" filter="url(#soft)" opacity="{0.9 - 0.25 * k}"/>')
    b.append(f'<polygon points="0,470 90,340 160,420 250,300 340,410 420,330 500,430 500,520 0,520" fill="#2B3B4A"/>')
    b.append(f'<polygon points="250,300 228,334 272,334" fill="{P["cream"]}" opacity="0.85"/>')
    b.append(f'<polygon points="90,340 72,366 108,366" fill="{P["cream"]}" opacity="0.85"/>')
    b.append(f'<rect x="0" y="500" width="{W}" height="200" fill="{P["ink"]}"/>')
    b.append(f'<rect x="0" y="492" width="{W}" height="8" fill="{P["brass_d"]}"/>')
    for x in range(20, 500, 46):
        b.append(f'<path d="M{x},500 q23,-34 46,0" fill="none" stroke="{P["brass_d"]}" stroke-width="3"/>')
    # tog
    b.append(f'<path d="M60,488 L60,452 Q60,438 76,438 L150,438 L150,488 Z" fill="{P["ink"]}" stroke="{P["brass"]}" stroke-width="1.5"/>')
    b.append(f'<rect x="38" y="460" width="24" height="28" fill="{P["ink"]}" stroke="{P["brass"]}" stroke-width="1.5"/>')
    b.append(f'<rect x="120" y="424" width="12" height="14" fill="{P["ink"]}" stroke="{P["brass"]}" stroke-width="1.2"/>')
    for i in range(4):
        x = 158 + i * 78
        b.append(f'<rect x="{x}" y="446" width="72" height="42" rx="4" fill="{P["ink"]}" stroke="{P["brass"]}" stroke-width="1.5"/>')
        for j in range(4):
            b.append(f'<rect x="{x + 8 + j * 16}" y="455" width="10" height="12" fill="{P["brass"]}"/>')
    b.append(f'<path d="M126,422 q-20,-30 10,-50 q30,-20 10,-48" fill="none" stroke="{P["cream"]}" stroke-width="10" stroke-linecap="round" opacity="0.35"/>')
    b.append(text(250, 76, "NORDLYS-", 40, P["cream"], weight=800, ls=6))
    b.append(text(250, 120, "EKSPRESSEN", 40, P["brass"], weight=800, ls=6))
    b.append(text(250, 590, "TIL NORDKAP", 30, P["cream"], weight=600, ls=10))
    b.append(text(250, 625, "NATTOG · AFGANG 23.10 · SPOR 7", 11, P["brass"], weight=500, ls=3))
    b.append(text(250, 672, "personligt felt: by (“NORDKAP”)", 10, P["brass_d"], family="JetBrains Mono", weight=400))
    return svg("".join(b), "#0E1A2B", defs)


DRAFTS = [("11-skyskraberen", deco), ("51-rosa-mechanica", botanik), ("41-det-mekaniske-cirkus", cirkus),
          ("07-patent-dampmaskine", patent), ("26-mads-vaerksted", skilt), ("17-nordlys-ekspressen", rejse)]
for name, fn in DRAFTS:
    with open(os.path.join(OUT, name + ".svg"), "w", encoding="utf-8") as f:
        f.write(fn())
print("ok", len(DRAFTS))
