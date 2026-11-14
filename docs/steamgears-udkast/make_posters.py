"""Plakat-mockups (5:7) med titel i Steamgears-stilen ud fra færdige billeder.

Brug: python3 make_posters.py <billedmappe> <ud-mappe>
Billednavne følger Drive: sg-<serie>-<nr>-<slug>-<kode>.jpg
"""
import html, json, os, subprocess, sys
from PIL import Image, ImageStat

SRC, OUT = sys.argv[1], sys.argv[2]
TITLES = {  # kode: (titel, undertitel, serie)
    "r1a": ("THE AURORA HELM", "Kaptajnen ved roret", "AIRSHIP CHRONICLES · No. 01"),
    "r2a": ("THE CELESTIAL DOME", "Kurs efter stjernerne", "AIRSHIP CHRONICLES · No. 02"),
    "r3a": ("SKY BOARDING", "Entringen", "AIRSHIP CHRONICLES · No. 03"),
    "r2m": ("THE CAPTAIN'S TABLE", "Kurs mod stormen", "AIRSHIP CHRONICLES · No. 04"),
    "r2f": ("THE BRIDGE", "Kursen sættes", "AIRSHIP CHRONICLES · No. 05"),
    "r3b": ("THE STORM PLANK", "Springet", "AIRSHIP CHRONICLES · No. 06"),
    "r5a": ("HARBOUR IN THE CLOUDS", "Havnen i skyerne", "AIRSHIP CHRONICLES · No. 07"),
    "k1a": ("THE ARMADA", "Over den victorianske by", "AIRSHIP CHRONICLES · No. 08"),
    "r2b": ("THE NAVIGATOR", "Stjernekortenes mester", "AIRSHIP CHRONICLES · No. 09"),
    "r4a": ("CHIEF ENGINEER", "Maskinrummet", "ENGINE ROOM · No. 11"),
    "k2a": ("STRIX MECHANICA", "Den mekaniske ugle", "MECHANICA NATURALIS · No. 31"),
    "k3b": ("COR HOROLOGIUM", "Urværkshjertet", "MECHANICA NATURALIS · No. 32"),
}

os.makedirs(OUT, exist_ok=True)
jobs = []
for f in sorted(os.listdir(SRC)):
    if not f.endswith(".jpg"):
        continue
    code = f.rsplit("-", 1)[1][:-4]
    if code not in TITLES:
        continue
    im = Image.open(os.path.join(SRC, f)).convert("L")
    w, h = im.size
    light = ImageStat.Stat(im.crop((0, int(h * 0.8), w, h))).mean[0] > 140
    title, sub, series = TITLES[code]
    tsize = 31 if len(title) <= 15 else 25
    ink, accent = ("#2A1F14", "#8A6420") if light else ("#F3E6C6", "#D9B46A")
    fade = ("rgba(240,228,200,0)", "rgba(240,228,200,0.92)") if light else ("rgba(12,10,8,0)", "rgba(12,10,8,0.88)")
    page = f"""<!doctype html><html><head><meta charset="utf-8"><style>
body{{margin:0}} .p{{position:relative;width:500px;height:700px;overflow:hidden;background:#111}}
.p img{{width:100%;height:100%;object-fit:cover;object-position:center 30%}}
.g{{position:absolute;left:0;right:0;bottom:0;height:260px;background:linear-gradient({fade[0]},{fade[1]} 62%)}}
.f{{position:absolute;inset:14px;border:1.5px solid {accent};outline:0.6px solid {accent};outline-offset:-6px}}
.t{{position:absolute;left:0;right:0;bottom:66px;text-align:center;color:{ink};font:700 {tsize}px 'DejaVu Serif';letter-spacing:5px;padding:0 34px}}
.r{{position:absolute;left:150px;right:150px;bottom:56px;height:1px;background:{accent}}}
.s{{position:absolute;left:0;right:0;bottom:34px;text-align:center;color:{accent};font:italic 15px 'DejaVu Serif'}}
.n{{position:absolute;left:0;right:0;bottom:20px;text-align:center;color:{ink};opacity:.75;font:500 8.5px Inter;letter-spacing:3.5px}}
</style></head><body><div class="p"><img src="file://{os.path.abspath(os.path.join(SRC, f))}">
<div class="g"></div><div class="f"></div><div class="t">{html.escape(title)}</div><div class="r"></div>
<div class="s">{html.escape(sub)}</div><div class="n">STEAMGEARS · {html.escape(series)}</div></div></body></html>"""
    hp = os.path.join(OUT, f[:-4] + ".html")
    open(hp, "w", encoding="utf-8").write(page)
    jobs.append((hp, os.path.join(OUT, "poster-" + f[:-4] + ".png")))

js = ("const {chromium}=require('playwright');(async()=>{const b=await chromium.launch();"
      "const p=await b.newPage({viewport:{width:500,height:700},deviceScaleFactor:2});"
      f"for (const [h,o] of {json.dumps(jobs)}) {{await p.goto('file://'+h);await p.waitForTimeout(150);await p.screenshot({{path:o}});}}"
      "await b.close();})();")
subprocess.run(["node", "-e", js], check=True)
for hp, _ in jobs:
    os.remove(hp)
# JPEG-kopier (mindre) + oversigt
pngs = [o for _, o in jobs]
for o in pngs:
    Image.open(o).convert("RGB").save(o[:-4] + ".jpg", quality=86); os.remove(o)
thumbs = [Image.open(o[:-4] + ".jpg").resize((300, 420)) for o in pngs]
cols = 4; rows = (len(thumbs) + cols - 1) // cols
sheet = Image.new("RGB", (cols * 316 + 16, rows * 436 + 16), (244, 241, 234))
for i, t in enumerate(thumbs):
    sheet.paste(t, (16 + (i % cols) * 316, 16 + (i // cols) * 436))
sheet.save(os.path.join(OUT, "oversigt-realistisk.jpg"), quality=88)
print("ok", len(pngs))
