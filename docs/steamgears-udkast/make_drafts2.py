"""Runde 2: fire mere detaljerede udkast midt i steampunk-universet (inkl. pin-up)."""
import math, os, sys, random

OUT = sys.argv[1]
W, H = 500, 700
P = dict(brass="#C9A45A", brass_l="#E6C987", brass_d="#7E5E26", copper="#B66A3E", copper_l="#DB9466",
         copper_d="#7A3F22", cream="#F0E4C8", sepia="#E8D6AE", ink="#1E1A15", smoke="#6B6257",
         sky1="#F2C77E", sky2="#C9784A", sky3="#5B3A2E", teal="#2E5C58", red="#8E3328", glass="#9CC3B8")
DEFS = """<filter id="grain" x="0" y="0" width="100%" height="100%">
<feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="2" seed="4" result="n"/>
<feColorMatrix in="n" type="saturate" values="0"/>
<feComponentTransfer><feFuncA type="table" tableValues="0 0.13"/></feComponentTransfer>
<feBlend in="SourceGraphic" mode="multiply"/></filter>
<radialGradient id="vig" cx="50%" cy="45%" r="75%"><stop offset="0.6" stop-color="#000" stop-opacity="0"/>
<stop offset="1" stop-color="#000" stop-opacity="0.45"/></radialGradient>
<filter id="blur6"><feGaussianBlur stdDeviation="6"/></filter>"""


def gear(cx, cy, r, teeth, depth=None, fill=P["brass"], stroke=P["ink"], sw=1.2, rot=0, hole=0, spokes=0, rim=0.72):
    depth = depth or r * 0.15
    n = teeth * 4
    pts = []
    for i in range(n):
        a = math.radians(rot) + 2 * math.pi * i / n
        rr = r if (i % 4) in (1, 2) else r - depth
        pts.append(f"{cx + rr * math.cos(a):.2f},{cy + rr * math.sin(a):.2f}")
    s = f'<path d="M{" L".join(pts)} Z" fill="{fill}" stroke="{stroke}" stroke-width="{sw}" stroke-linejoin="round"/>'
    if spokes:
        ri = (r - depth) * rim
        s += f'<circle cx="{cx}" cy="{cy}" r="{ri:.1f}" fill="{P["ink"]}" opacity="0.85"/>'
        for k in range(spokes):
            a = math.radians(rot) + 2 * math.pi * k / spokes
            s += (f'<line x1="{cx}" y1="{cy}" x2="{cx + ri * math.cos(a):.1f}" y2="{cy + ri * math.sin(a):.1f}" '
                  f'stroke="{fill}" stroke-width="{max(2, r * 0.12):.1f}" stroke-linecap="round"/>')
        s += f'<circle cx="{cx}" cy="{cy}" r="{r * 0.2:.1f}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>'
    if hole:
        s += f'<circle cx="{cx}" cy="{cy}" r="{hole}" fill="{P["ink"]}"/>'
    return s


def rivets(pts, r=2.2, fill=P["brass_l"]):
    return "".join(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="{fill}" stroke="{P["ink"]}" stroke-width="0.6"/>' for x, y in pts)


def text(x, y, t, size, fill, family="DejaVu Serif", weight=400, ls=0, anchor="middle", style="normal"):
    return (f'<text x="{x}" y="{y}" font-family="{family}" font-size="{size}" font-weight="{weight}" '
            f'letter-spacing="{ls}" text-anchor="{anchor}" font-style="{style}" fill="{fill}">{t}</text>')


def frame(color=P["brass"], inset=16):
    s = f'<rect x="{inset}" y="{inset}" width="{W - 2 * inset}" height="{H - 2 * inset}" fill="none" stroke="{color}" stroke-width="2.5"/>'
    s += f'<rect x="{inset + 7}" y="{inset + 7}" width="{W - 2 * inset - 14}" height="{H - 2 * inset - 14}" fill="none" stroke="{color}" stroke-width="0.8"/>'
    for x, y in ((inset, inset), (W - inset, inset), (inset, H - inset), (W - inset, H - inset)):
        s += gear(x, y, 13, 10, fill=color, stroke=P["ink"], sw=0.8, hole=3.5)
    return s


def svg(body, extra_defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}">'
            f'<defs>{DEFS}{extra_defs}</defs><g filter="url(#grain)">{body}'
            f'<rect width="{W}" height="{H}" fill="url(#vig)"/></g></svg>')


# ---------- 1 · Luftskibet over byen (motiv 1) ----------
def airship():
    d = (f'<linearGradient id="dusk" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{P["sky3"]}"/>'
         f'<stop offset="0.45" stop-color="{P["sky2"]}"/><stop offset="0.8" stop-color="{P["sky1"]}"/></linearGradient>'
         f'<linearGradient id="env" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{P["copper_l"]}"/>'
         f'<stop offset="0.55" stop-color="{P["copper"]}"/><stop offset="1" stop-color="{P["copper_d"]}"/></linearGradient>')
    b = [f'<rect width="{W}" height="{H}" fill="url(#dusk)"/>']
    # sol-tandhjul bag byen
    b.append(gear(250, 470, 150, 32, fill=P["brass_l"], stroke="none", sw=0, rot=4))
    b.append(f'<circle cx="250" cy="470" r="112" fill="{P["sky1"]}" opacity="0.6"/>')
    # fjerne skyer
    for x, y, rx in ((90, 330, 90), (400, 290, 110), (300, 360, 70)):
        b.append(f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="16" fill="{P["cream"]}" opacity="0.35" filter="url(#blur6)"/>')
    # skyline bag
    random.seed(2)
    back = "M0,560 "
    x = 0
    while x < W:
        w = random.randint(18, 40); h = random.randint(470, 530)
        back += f"L{x},{h} L{x + w},{h} "
        x += w
    b.append(f'<path d="{back} L{W},560 L{W},{H} L0,{H} Z" fill="{P["sky3"]}" opacity="0.55"/>')
    # urtårn
    tx = 360
    b.append(f'<path d="M{tx - 26},{H} L{tx - 26},420 L{tx - 32},420 L{tx},372 L{tx + 32},420 L{tx + 26},420 L{tx + 26},{H} Z" fill="{P["ink"]}"/>')
    b.append(f'<line x1="{tx}" y1="372" x2="{tx}" y2="340" stroke="{P["ink"]}" stroke-width="3"/>')
    b.append(f'<circle cx="{tx}" cy="452" r="18" fill="{P["brass_l"]}" stroke="{P["ink"]}" stroke-width="3"/>')
    for k in range(12):
        a = 2 * math.pi * k / 12
        b.append(f'<line x1="{tx + 14 * math.cos(a):.1f}" y1="{452 + 14 * math.sin(a):.1f}" x2="{tx + 17 * math.cos(a):.1f}" y2="{452 + 17 * math.sin(a):.1f}" stroke="{P["ink"]}" stroke-width="1.2"/>')
    b.append(f'<line x1="{tx}" y1="452" x2="{tx}" y2="440" stroke="{P["ink"]}" stroke-width="2"/><line x1="{tx}" y1="452" x2="{tx + 9}" y2="456" stroke="{P["ink"]}" stroke-width="2"/>')
    # forreste skyline med skorstene og lys i vinduer
    front = [(0, 560, 70), (70, 520, 50), (120, 545, 60), (180, 505, 45), (225, 535, 70), (295, 515, 40), (386, 530, 55), (441, 500, 59)]
    for x0, y0, w in front:
        b.append(f'<rect x="{x0}" y="{y0}" width="{w}" height="{H - y0}" fill="{P["ink"]}"/>')
        b.append(f'<polygon points="{x0 - 4},{y0} {x0 + w / 2},{y0 - 22} {x0 + w + 4},{y0}" fill="{P["ink"]}"/>')
        for wx in range(x0 + 8, x0 + w - 8, 14):
            for wy in range(y0 + 14, H - 30, 22):
                if random.random() < 0.3:
                    b.append(f'<rect x="{wx}" y="{wy}" width="6" height="9" fill="{P["brass_l"]}"/>')
    for cx_, top in ((95, 480), (200, 470), (465, 455)):
        b.append(f'<rect x="{cx_}" y="{top}" width="12" height="60" fill="{P["ink"]}"/>')
        b.append(f'<path d="M{cx_ + 6},{top} c-20,-30 25,-40 5,-80 c-15,-25 20,-35 10,-60" fill="none" stroke="{P["smoke"]}" stroke-width="14" stroke-linecap="round" opacity="0.4" filter="url(#blur6)"/>')
    # luftskib
    ex, ey, erx, ery = 230, 205, 165, 62
    b.append(f'<path d="M{ex + erx - 10},{ey} l40,-38 l14,0 l-20,38 l20,38 l-14,0 Z" fill="{P["copper_d"]}" stroke="{P["ink"]}" stroke-width="1.5"/>')
    b.append(f'<ellipse cx="{ex}" cy="{ey}" rx="{erx}" ry="{ery}" fill="url(#env)" stroke="{P["ink"]}" stroke-width="2"/>')
    for k in range(1, 8):
        rx = erx * (1 - k / 8)
        b.append(f'<path d="M{ex - rx:.1f},{ey - ery * math.sqrt(1 - (rx / erx) ** 2) + 0.5:.1f}" fill="none"/>')
    for k in range(-6, 7):
        x = ex + k * erx / 7
        yy = ery * math.sqrt(max(0, 1 - ((x - ex) / erx) ** 2))
        b.append(f'<line x1="{x:.1f}" y1="{ey - yy:.1f}" x2="{x:.1f}" y2="{ey + yy:.1f}" stroke="{P["copper_d"]}" stroke-width="1" opacity="0.7"/>')
    for f in (-0.5, 0, 0.5):
        b.append(f'<path d="M{ex - erx},{ey} Q{ex},{ey + ery * f * 1.9} {ex + erx},{ey}" fill="none" stroke="{P["copper_d"]}" stroke-width="1" opacity="0.6"/>')
    b.append(f'<path d="M{ex - erx + 20},{ey - 30} Q{ex},{ey - ery - 6} {ex + erx - 30},{ey - 34}" fill="none" stroke="{P["cream"]}" stroke-width="5" opacity="0.35" stroke-linecap="round"/>')
    b.append(f'<rect x="{ex - 60}" y="{ey - 6}" width="120" height="12" fill="{P["brass"]}" stroke="{P["ink"]}" stroke-width="1.2"/>')
    b.append(rivets([(ex - 54 + 12 * i, ey) for i in range(10)], r=1.8))
    gy = ey + ery + 22
    for xa, xb in ((ex - 80, ex - 50), (ex + 80, ex + 50), (ex - 20, ex - 20), (ex + 20, ex + 20)):
        b.append(f'<line x1="{xa}" y1="{ey + ery - 8}" x2="{xb}" y2="{gy}" stroke="{P["ink"]}" stroke-width="1.2"/>')
    b.append(f'<path d="M{ex - 62},{gy} L{ex + 62},{gy} L{ex + 52},{gy + 28} L{ex - 52},{gy + 28} Z" fill="{P["brass"]}" stroke="{P["ink"]}" stroke-width="1.6"/>')
    for i in range(6):
        b.append(f'<circle cx="{ex - 40 + i * 16}" cy="{gy + 13}" r="5" fill="{P["brass_l"]}" stroke="{P["ink"]}" stroke-width="1.4"/>')
    for side in (-1, 1):
        px = ex + side * 88
        b.append(f'<line x1="{ex + side * 55}" y1="{gy + 10}" x2="{px}" y2="{gy + 10}" stroke="{P["ink"]}" stroke-width="2.5"/>')
        b.append(f'<ellipse cx="{px + side * 4}" cy="{gy + 10}" rx="4" ry="22" fill="{P["brass_d"]}" stroke="{P["ink"]}" stroke-width="1" opacity="0.9"/>')
        b.append(gear(px, gy + 10, 7, 8, fill=P["brass"], sw=0.8))
    # fugle
    for x, y in ((90, 120), (110, 135), (420, 330), (440, 318)):
        b.append(f'<path d="M{x - 7},{y} q7,-6 7,0 q0,-6 7,0" fill="none" stroke="{P["ink"]}" stroke-width="1.4"/>')
    b.append(f'<rect x="23" y="606" width="{W - 46}" height="71" fill="{P["ink"]}"/>')
    b.append(text(250, 640, "LUFTSKIBET", 30, P["brass_l"], weight=700, ls=10))
    b.append(text(250, 664, "OVER  NEW  CLOCKHAVEN  ·  ANNO  1887", 10, P["brass"], family="Inter Display", weight=500, ls=3.5))
    b.append(frame())
    return svg("".join(b), d)


# ---------- 2 · Den mekaniske ugle (motiv 4) ----------
def owl():
    d = (f'<radialGradient id="bgo" cx="50%" cy="38%" r="70%"><stop offset="0" stop-color="#2F5450"/><stop offset="1" stop-color="#132624"/></radialGradient>'
         f'<radialGradient id="lens" cx="40%" cy="35%" r="65%"><stop offset="0" stop-color="#FFE7A6"/><stop offset="0.5" stop-color="#E0A43C"/><stop offset="1" stop-color="#7A4A12"/></radialGradient>'
         f'<linearGradient id="plate" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{P["copper_l"]}"/><stop offset="1" stop-color="{P["copper_d"]}"/></linearGradient>')
    b = [f'<rect width="{W}" height="{H}" fill="url(#bgo)"/>']
    # baggrund: store, svage tandhjul
    for (x, y, r, t) in ((70, 130, 70, 18), (440, 210, 95, 22), (410, 560, 60, 16), (60, 520, 50, 14)):
        b.append(gear(x, y, r, t, fill="none", stroke=P["brass"], sw=1, rot=7))
        b.append(f'<circle cx="{x}" cy="{y}" r="{r * 0.55:.0f}" fill="none" stroke="{P["brass"]}" stroke-width="0.6" opacity="0.6"/>')
    cx = 250
    # gren af rør
    b.append(f'<path d="M30,560 C150,540 330,548 470,520" fill="none" stroke="{P["brass_d"]}" stroke-width="22" stroke-linecap="round"/>')
    b.append(f'<path d="M30,560 C150,540 330,548 470,520" fill="none" stroke="{P["brass"]}" stroke-width="12" stroke-linecap="round"/>')
    for x in (110, 300, 420):
        b.append(f'<rect x="{x - 8}" y="{536 - (x - 110) * 0.07:.0f}" width="16" height="30" rx="3" fill="{P["brass_d"]}" stroke="{P["ink"]}" stroke-width="1"/>')
    # krop: skælplader
    body = f'M{cx},170 C{cx + 120},180 {cx + 135},330 {cx + 110},430 C{cx + 90},510 {cx + 40},545 {cx},548 C{cx - 40},545 {cx - 90},510 {cx - 110},430 C{cx - 135},330 {cx - 120},180 {cx},170 Z'
    b.append(f'<path d="{body}" fill="url(#plate)" stroke="{P["ink"]}" stroke-width="2.5"/>')
    b.append(f'<clipPath id="bc"><path d="{body}"/></clipPath>')
    sc = []
    for row in range(14):
        y = 300 + row * 18
        off = 11 if row % 2 else 0
        for x in range(cx - 120 + off, cx + 121, 22):
            sc.append(f'<path d="M{x - 11},{y} a11,13 0 0,0 22,0" fill="none" stroke="{P["copper_d"]}" stroke-width="1.6"/>')
            sc.append(f'<circle cx="{x}" cy="{y + 9}" r="1.3" fill="{P["brass_l"]}"/>')
    b.append(f'<g clip-path="url(#bc)">{"".join(sc)}</g>')
    # bryst-plade med urværk
    b.append(f'<ellipse cx="{cx}" cy="420" rx="52" ry="70" fill="{P["ink"]}" stroke="{P["brass"]}" stroke-width="3"/>')
    b.append(gear(cx - 14, 400, 30, 14, fill=P["brass"], sw=1, spokes=5, rot=10))
    b.append(gear(cx + 22, 440, 20, 11, fill=P["copper_l"], sw=1, spokes=4, rot=3))
    b.append(gear(cx - 6, 462, 13, 9, fill=P["brass_l"], sw=1, hole=3))
    # vinger
    for s in (-1, 1):
        wing = (f'M{cx + s * 95},250 C{cx + s * 160},300 {cx + s * 170},420 {cx + s * 130},520 '
                f'L{cx + s * 112},500 L{cx + s * 120},470 L{cx + s * 100},455 C{cx + s * 110},380 {cx + s * 100},300 {cx + s * 95},250 Z')
        b.append(f'<path d="{wing}" fill="{P["brass_d"]}" stroke="{P["ink"]}" stroke-width="2"/>')
        for k in range(5):
            y = 300 + k * 42
            b.append(f'<path d="M{cx + s * (104 + k * 3)},{y} q{s * 35},{20} {s * 46},{60}" fill="none" stroke="{P["brass"]}" stroke-width="3"/>')
        b.append(rivets([(cx + s * (110 + k * 6), 290 + k * 45) for k in range(5)], r=2))
    # hoved og øretotter
    for s in (-1, 1):
        b.append(f'<path d="M{cx + s * 60},185 L{cx + s * 112},110 L{cx + s * 96},200 Z" fill="{P["copper"]}" stroke="{P["ink"]}" stroke-width="2"/>')
        b.append(f'<line x1="{cx + s * 70}" y1="180" x2="{cx + s * 104}" y2="125" stroke="{P["copper_d"]}" stroke-width="1.4"/>')
    b.append(f'<path d="M{cx - 108},250 C{cx - 110},170 {cx - 40},160 {cx},175 C{cx + 40},160 {cx + 110},170 {cx + 108},250 C{cx + 80},300 {cx - 80},300 {cx - 108},250 Z" fill="{P["copper_l"]}" stroke="{P["ink"]}" stroke-width="2.5"/>')
    # øjne: tandhjul + linser
    for s in (-1, 1):
        ex = cx + s * 52
        b.append(gear(ex, 240, 46, 18, fill=P["brass"], sw=1.4, rot=s * 5))
        b.append(f'<circle cx="{ex}" cy="240" r="34" fill="{P["ink"]}"/>')
        b.append(f'<circle cx="{ex}" cy="240" r="28" fill="url(#lens)" stroke="{P["brass_l"]}" stroke-width="3"/>')
        b.append(f'<circle cx="{ex}" cy="240" r="11" fill="{P["ink"]}"/>')
        b.append(f'<circle cx="{ex - 9}" cy="230" r="5" fill="#FFF6DA" opacity="0.9"/>')
        b.append(rivets([(ex + 40 * math.cos(a), 240 + 40 * math.sin(a)) for a in [k * math.pi / 4 for k in range(8)]], r=1.6))
    b.append(f'<path d="M{cx - 14},262 L{cx + 14},262 L{cx},300 Z" fill="{P["brass_l"]}" stroke="{P["ink"]}" stroke-width="2"/>')
    # kløer
    for s in (-1, 1):
        for k in (-1, 0, 1):
            x = cx + s * 40 + k * 12
            b.append(f'<path d="M{x},540 q{k * 3},14 {k * 4 + 2},24" fill="none" stroke="{P["brass_l"]}" stroke-width="5" stroke-linecap="round"/>')
    b.append(text(250, 624, "STRIX MECHANICA", 26, P["brass_l"], weight=700, ls=6))
    b.append(text(250, 648, "DEN MEKANISKE UGLE · VÆRK NR. 4", 10, P["brass"], family="Inter Display", weight=500, ls=3.5))
    b.append(frame())
    return svg("".join(b), d)


# ---------- 3 · Urværkshjertet (nyt motiv) ----------
def heart():
    d = (f'<linearGradient id="hp" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{P["copper_l"]}"/><stop offset="0.6" stop-color="{P["copper"]}"/><stop offset="1" stop-color="{P["copper_d"]}"/></linearGradient>'
         f'<linearGradient id="tube" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{P["brass_d"]}"/><stop offset="0.45" stop-color="{P["brass_l"]}"/><stop offset="1" stop-color="{P["brass_d"]}"/></linearGradient>')
    b = [f'<rect width="{W}" height="{H}" fill="{P["sepia"]}"/>']
    # anatomisk planche-baggrund: linjer og noter
    for y in range(80, 620, 26):
        b.append(f'<line x1="40" y1="{y}" x2="{W - 40}" y2="{y}" stroke="{P["brass_d"]}" stroke-width="0.4" opacity="0.35"/>')
    cx = 250
    # rør (aorta, lungearterie, vener)
    tubes = [f"M{cx - 10},230 C{cx - 15},160 {cx + 60},120 {cx + 110},150 L{cx + 140},230",
             f"M{cx - 45},225 C{cx - 60},170 {cx - 95},150 {cx - 130},130",
             f"M{cx + 30},215 C{cx + 25},175 {cx + 20},140 {cx + 25},95",
             f"M{cx - 75},245 C{cx - 110},240 {cx - 140},250 {cx - 160},275"]
    for t in tubes:
        b.append(f'<path d="{t}" fill="none" stroke="{P["ink"]}" stroke-width="32" stroke-linecap="butt"/>')
        b.append(f'<path d="{t}" fill="none" stroke="{P["brass"]}" stroke-width="26"/>')
        b.append(f'<path d="{t}" fill="none" stroke="{P["brass_l"]}" stroke-width="6" opacity="0.6" transform="translate(-5,-3)"/>')
    for (x, y) in ((cx + 140, 232), (cx - 130, 130), (cx + 25, 95), (cx - 160, 275)):
        b.append(f'<ellipse cx="{x}" cy="{y}" rx="17" ry="17" fill="{P["ink"]}" stroke="{P["brass_l"]}" stroke-width="3"/>')
        b.append(f'<circle cx="{x}" cy="{y}" r="6" fill="{P["copper_d"]}"/>')
    # ventil-hjul
    b.append(gear(cx + 70, 128, 16, 10, fill=P["red"], sw=1, spokes=4))
    # hjertekrop
    heart = (f'M{cx - 20},230 C{cx - 120},215 {cx - 150},320 {cx - 120},390 C{cx - 90},460 {cx - 20},520 {cx + 20},560 '
             f'C{cx + 60},500 {cx + 140},430 {cx + 140},340 C{cx + 140},260 {cx + 70},215 {cx - 20},230 Z')
    b.append(f'<path d="{heart}" fill="url(#hp)" stroke="{P["ink"]}" stroke-width="3"/>')
    b.append(f'<clipPath id="hc"><path d="{heart}"/></clipPath>')
    seams = [f"M{cx + 10},235 C{cx - 10},320 {cx + 30},430 {cx + 20},555", f"M{cx - 120},300 C{cx - 60},310 {cx + 60},280 {cx + 135},300"]
    g = []
    for sm in seams:
        g.append(f'<path d="{sm}" fill="none" stroke="{P["copper_d"]}" stroke-width="2"/>')
    random.seed(9)
    for _ in range(60):
        g.append(f'<circle cx="{random.uniform(cx - 140, cx + 140):.0f}" cy="{random.uniform(230, 560):.0f}" r="1.6" fill="{P["brass_l"]}" stroke="{P["ink"]}" stroke-width="0.4"/>')
    # udskåret vindue med urværk
    g.append(f'<path d="M{cx - 85},330 C{cx - 85},300 {cx + 90},290 {cx + 95},330 C{cx + 100},420 {cx + 20},470 {cx - 10},480 C{cx - 60},440 {cx - 90},390 {cx - 85},330 Z" fill="{P["ink"]}" stroke="{P["brass"]}" stroke-width="4"/>')
    g.append(gear(cx - 30, 370, 42, 16, fill=P["brass"], sw=1, spokes=6, rot=8))
    g.append(gear(cx + 42, 352, 28, 12, fill=P["copper_l"], sw=1, spokes=5, rot=2))
    g.append(gear(cx + 20, 420, 22, 10, fill=P["brass_l"], sw=1, spokes=4))
    g.append(gear(cx - 40, 435, 15, 9, fill=P["copper"], sw=1, hole=3))
    g.append(f'<path d="M{cx + 60},400 q14,-20 6,-38" fill="none" stroke="{P["brass_l"]}" stroke-width="2"/>')
    b.append(f'<g clip-path="url(#hc)">{"".join(g)}</g>')
    b.append(f'<path d="{heart}" fill="none" stroke="{P["ink"]}" stroke-width="3"/>')
    # etiketter som anatomisk planche
    labels = [(cx + 140, 214, 462, 118, "I. Aorta mechanica", "end"), (cx - 130, 130, 60, 104, "II. Vena vaporis", "start"),
              (cx + 62, 352, 462, 486, "III. Horologium cordis", "end"), (cx - 100, 400, 52, 526, "IV. Ventriculus", "start")]
    for x1, y1, x2, y2, t, anc in labels:
        b.append(f'<line x1="{x1}" y1="{y1}" x2="{x2 - 4 if anc == "end" else x2 + 4}" y2="{y2 + 4}" stroke="{P["ink"]}" stroke-width="0.7"/>')
        b.append(f'<circle cx="{x1}" cy="{y1}" r="2.2" fill="{P["ink"]}"/>')
        b.append(text(x2, y2, t, 10, P["ink"], style="italic", anchor=anc))
    b.append(text(250, 610, "Cor Horologium", 32, P["ink"], style="italic"))
    b.append(text(250, 636, "URVÆRKSHJERTET · TAB. XII", 10, P["copper_d"], family="Inter Display", weight=600, ls=3.5))
    b.append(frame(color=P["brass_d"]))
    return svg("".join(b), d)


# ---------- 4 · Luftskibskaptajnen, pin-up-camé (motiv 33) ----------
def captain():
    d = (f'<radialGradient id="cam" cx="50%" cy="45%" r="60%"><stop offset="0" stop-color="#F6E9CC"/><stop offset="1" stop-color="#D9BE8C"/></radialGradient>'
         f'<linearGradient id="bgc" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3B1F1A"/><stop offset="1" stop-color="#1C1210"/></linearGradient>')
    b = [f'<rect width="{W}" height="{H}" fill="url(#bgc)"/>']
    # damask-mønster
    for y in range(40, 700, 60):
        for x in range(30 + (30 if (y // 60) % 2 else 0), 500, 60):
            b.append(f'<path d="M{x},{y - 10} q8,10 0,20 q-8,-10 0,-20" fill="{P["brass_d"]}" opacity="0.35"/>')
    cx, cy, rx, ry = 250, 330, 170, 225
    # tandhjulsring omkring camé
    for k in range(26):
        a = 2 * math.pi * k / 26
        b.append(gear(cx + (rx + 14) * math.cos(a), cy + (ry + 14) * math.sin(a), 11, 8, fill=P["brass"], sw=0.8, rot=k * 9))
    b.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx + 6}" ry="{ry + 6}" fill="{P["brass_d"]}" stroke="{P["ink"]}" stroke-width="2"/>')
    b.append(f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="url(#cam)" stroke="{P["brass_l"]}" stroke-width="3"/>')
    b.append(f'<clipPath id="cc"><ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}"/></clipPath>')
    s = []
    # luftskib i baggrunden af caméen
    s.append(f'<ellipse cx="335" cy="190" rx="70" ry="24" fill="{P["copper"]}" opacity="0.35"/>')
    s.append(f'<rect x="318" y="218" width="34" height="9" fill="{P["copper"]}" opacity="0.35"/>')
    # silhuet i profil (vendt mod venstre), fuldt påklædt
    sil = ("M285,420 C280,395 278,372 282,352 "
           "C300,346 312,326 305,306 C300,292 288,286 282,288 "
           "C286,275 282,262 270,256 "
           "L300,246 L300,236 L262,236 L262,160 L194,160 L194,236 L170,238 L172,246 L205,248 "
           "C196,258 190,268 190,278 C190,284 188,288 186,290 "
           "C180,300 174,308 172,314 C176,318 182,318 186,320 "
           "C184,324 182,328 186,330 C184,333 184,336 188,338 "
           "C186,344 188,352 196,356 C206,358 214,362 220,372 "
           "C218,386 214,398 210,410 C196,420 172,432 160,452 "
           "C190,476 270,478 336,456 C320,440 300,428 285,420 Z")
    s.append(f'<path d="{sil}" fill="{P["ink"]}"/>')
    s.append(f'<rect x="194" y="214" width="68" height="12" fill="{P["brass"]}"/>')
    for gx in (212, 244):
        s.append(f'<circle cx="{gx}" cy="220" r="11" fill="{P["ink"]}" stroke="{P["brass_l"]}" stroke-width="3"/>')
        s.append(f'<circle cx="{gx}" cy="220" r="6" fill="{P["glass"]}" opacity="0.8"/>')
    s.append(f'<path d="M262,190 C290,160 300,130 296,104 C286,128 272,150 262,170 Z" fill="{P["red"]}"/>')
    s.append(f'<path d="M262,190 C285,160 296,134 296,104" fill="none" stroke="{P["ink"]}" stroke-width="1"/>')
    s.append(gear(300, 312, 8, 8, fill=P["brass"], sw=0.6, hole=2.2))
    s.append(f'<path d="M216,392 C240,400 262,398 281,388" fill="none" stroke="{P["brass"]}" stroke-width="5"/>')
    s.append(f'<line x1="258" y1="318" x2="258" y2="334" stroke="{P["brass"]}" stroke-width="1.4"/>')
    s.append(gear(258, 342, 8, 8, fill=P["brass_l"], sw=0.6, hole=2.2))
    s.append(f'<path d="M206,414 C230,426 270,428 300,432" fill="none" stroke="{P["brass"]}" stroke-width="2.5"/>')
    for k in range(5):
        s.append(f'<line x1="{300 + k * 7}" y1="{434 + k * 3}" x2="{298 + k * 7}" y2="{450 + k * 3}" stroke="{P["brass"]}" stroke-width="2"/>')
    s.append(f'<path d="M160,452 C190,476 270,478 336,456" fill="none" stroke="{P["brass_l"]}" stroke-width="3"/>')
    b.append(f'<g clip-path="url(#cc)">{"".join(s)}</g>')
    # banner
    b.append(f'<path d="M70,592 L430,592 L410,620 L430,648 L70,648 L90,620 Z" fill="{P["red"]}" stroke="{P["ink"]}" stroke-width="2"/>')
    b.append(text(250, 628, "LUFTSKIBSKAPTAJNEN", 22, P["cream"], weight=700, ls=4))
    b.append(text(250, 668, "MISS AURELIA COGSWORTH · H.M.A. ZEPHYR", 10, P["brass_l"], family="Inter Display", weight=500, ls=3))
    b.append(frame())
    return svg("".join(b), d)


DRAFTS = [("r2-01-luftskibet-over-byen", airship), ("r2-04-den-mekaniske-ugle", owl),
          ("r2-61-urvaerkshjertet", heart), ("r2-33-luftskibskaptajnen", captain)]
for name, fn in DRAFTS:
    with open(os.path.join(OUT, name + ".svg"), "w", encoding="utf-8") as f:
        f.write(fn())
print("ok", len(DRAFTS))
