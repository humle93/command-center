"""Bygger Gemini_prompter.pdf: prompter til realistiske Steamgears-plakater.

Brug: python3 gemini_prompter.py <ud-mappe>   (kræver Playwright + Chromium via node)
"""
import html, os, subprocess, sys, json

OUT = sys.argv[1]
STYLE = ("Style: cinematic, realistic digital painting, warm golden-hour light, brass and copper tones with teal "
         "shadows, volumetric light, rich detail, sharp focus. Portrait orientation 5:7. Keep the bottom fifth "
         "calm and empty for a title. No text, no letters, no logos, no watermark.")

SERIES = [
    ("R1", "Luftskibspiraten ved roret", "Hovedmotiv. Lav dette først, og brug det bedste billede som reference for hende i R2–R3.",
     "A confident, beautiful woman airship pirate captain in her thirties stands at a large brass-and-mahogany ship's "
     "wheel on the open deck of a steampunk airship, one hand resting on the wheel, gazing out toward the horizon. "
     "She wears a fitted dark-red leather long coat with brass buttons, a high-collared cream blouse, a leather corset "
     "vest over it, a wide belt with a brass compass and a holstered flintlock pistol, tall boots, and a tricorn hat "
     "with aviator goggles on the brim. Wind in her long auburn hair. Behind her a huge copper-plated balloon envelope, "
     "ropes and rigging, spinning propellers. Beyond, a sea of clouds lit by a setting sun, distant airships "
     "silhouetted on the horizon. Heroic, adventurous mood, three-quarter view from slightly below. Fully clothed, tasteful."),
    ("R2", "Kaptajnen i kortrummet", "Samme kvinde som R1 (vedhæft R1 som reference).",
     "The same woman airship pirate captain as in the reference image leans over a large map table in a cabin of "
     "polished brass and dark wood, studying hand-drawn sky charts with a brass sextant. Oil lamps, a round porthole "
     "showing clouds outside, a globe of the sky, rich warm interior light, quiet concentration."),
    ("R3", "Entringen", "Samme kvinde som R1. Actionmotiv, godt som 70×100.",
     "Two steampunk airships side by side above the clouds at sunset, grappling hooks and ropes stretched between "
     "them. The same woman pirate captain as in the reference image swings across on a rope with a cutlass raised, "
     "coat flaring, smoke and sparks, birds scattering. Epic, wide, dynamic composition."),
    ("R4", "Mekanikeren i maskinrummet", "Ny karakter i samme univers.",
     "A capable woman airship engineer with rolled-up sleeves, a leather apron and welding goggles pushed up on her "
     "forehead adjusts giant brass gears and pressure valves in a steam-filled engine room. Warm glow from a furnace, "
     "gauges, copper pipes, rivets, determined expression. Fully clothed, tasteful."),
    ("R5", "Havnen i skyerne", "Landskab uden personer. Godt som sæt sammen med R1 og R3.",
     "A floating sky harbour at dawn: wooden docks on chains suspended beneath a giant balloon, several moored "
     "steampunk airships, a lighthouse with a rotating brass lamp, tiny figures loading cargo, misty pastel clouds "
     "far below, soft morning light."),
]
CLASSICS = [
    ("K1", "Luftskibet over byen (motiv 1)", "Realistisk udgave af udkastet.",
     "A large copper-plated steampunk airship with a brass gondola and spinning propellers glides over a Victorian "
     "city at dusk. Chimneys with drifting smoke, a tall clock tower, warm lit windows, a huge setting sun behind the "
     "skyline, birds in the sky. Atmospheric and nostalgic."),
    ("K2", "Strix mechanica – den mekaniske ugle (motiv 4)", "Studiebelyst, næsten som et produktfoto af et kunstværk.",
     "A mechanical owl built from riveted copper plates and brass, perched on a brass pipe branch. Its eyes are "
     "glowing amber lenses set in brass gears, a small clockwork is visible behind a glass window in its chest, "
     "feathers are overlapping metal scales. Dark teal background with faint gears, dramatic studio lighting."),
    ("K3", "Cor Horologium – urværkshjertet (motiv 61)", "Bør have lys baggrund, så det kan hænge i en lys stue.",
     "An anatomical human heart crafted from copper plates and brass pipes, with valves and pressure wheels, and an "
     "intricate clockwork visible through a cut-away window. Presented like a museum specimen on aged cream paper "
     "with faint ruled lines, soft even light, scientific illustration feel rendered realistically."),
    ("K4", "Luftskibskaptajnen – portræt (motiv 33)", "Pin-up-portræt. Fuldt påklædt, kun til organisk salg.",
     "Elegant portrait of a beautiful steampunk airship captain in profile, wearing a tall top hat with brass "
     "goggles and a red feather, a high lace collar, a brass choker and a small gear earring. Oval brass cameo frame "
     "decorated with small gears, dark damask background, soft painterly light. Fully clothed, tasteful, classy."),
    ("K5", "Skyskraberen – Neodeco (motiv 11)", "Art deco, til samling 1. Trend i 2026.",
     "A towering art deco skyscraper seen from below at night, stepped setbacks, brass and gold ornament, "
     "searchlight beams fanning into the sky like sunrays, a zeppelin moored at the spire, glossy black and gold "
     "palette, elegant and monumental."),
    ("K6", "Rosa mechanica – mekanisk botanik (motiv 51)", "Botanisk planche, lys baggrund.",
     "A single rose whose petals are thin hammered copper sheets and whose centre is a small brass gear, on a brass "
     "stem with tiny rivets and two patinated green metal leaves. Vintage botanical plate on cream paper, soft "
     "natural light, delicate and detailed."),
    ("K7", "Det mekaniske cirkus (motiv 41)", "Cirkus-trend 2026. Godt til børneværelse og stue.",
     "A grand vintage circus tent with red and cream stripes and brass finials under a starry night sky, a "
     "clockwork acrobat on a trapeze visible through the open entrance, glowing lanterns, a mechanical elephant made "
     "of copper plates waiting outside. Magical, warm, nostalgic."),
]

PUNK = [
    ("D1", "Zeppelin Metropolis (dieselpunk)", "1930'er art deco-storby. Passer til samling 2.",
     "A towering 1930s art deco metropolis at night, a massive riveted diesel zeppelin docking at the mooring mast of a "
     "stepped skyscraper, searchlight beams sweeping the clouds, rain-slick streets far below with vintage cars and "
     "glowing signs without readable text, smoke and steam, gold and black palette, dramatic and monumental."),
    ("D2", "The Diesel Aviatrix (dieselpunk)", "Pin-up-agtig heltinde, fuldt påklædt. Kan annonceres.",
     "A confident, beautiful woman aviator in her thirties stands beside a huge riveted silver propeller aircraft on "
     "an airfield at dawn, wearing a brown leather flight jacket with sheepskin collar, a white silk scarf blowing in "
     "the wind, high-waisted trousers, tall boots and a leather flying helmet with goggles pushed up. Heroic 1930s "
     "mood, fuel trucks and hangars behind her, warm sunrise light with long shadows. Fully clothed, tasteful."),
    ("D3", "Iron Titan (dieselpunk)", "Episk 70×100-motiv.",
     "A colossal riveted diesel-powered walking machine strides through an industrial harbour at sunset, exhaust "
     "stacks pouring black smoke, cranes and cargo ships around it, tiny workers silhouetted on the docks for scale, "
     "orange sky with heavy clouds, gunmetal, rust and brass tones, dramatic perspective from below."),
    ("C1", "The Clockmaker's Workshop (clockwork punk)", "Renæssance, kun urværk, ingen damp.",
     "A Renaissance inventor's workshop lit by candles and a tall window, an elegant clockwork automaton of carved "
     "walnut wood and polished brass with visible gears and springs stands half-assembled on a workbench, parchment "
     "design drawings, quills, hourglasses, brass astrolabes and wooden gear wheels hanging from the beams, warm "
     "golden light and soft dust in the air. No steam, only clockwork."),
    ("C2", "The Ornithopter (clockwork punk)", "Lyst og sommerligt. Godt som sæt med C1 og C3.",
     "A wooden clockwork ornithopter with canvas wings and brass gears flies over a Renaissance hilltop city of "
     "terracotta roofs, bell towers and a cathedral dome at golden hour, a pilot in a leather cap at the controls, "
     "cypress trees and rolling hills beyond, soft warm light. No steam, only clockwork."),
    ("C3", "The Automaton Lady (clockwork punk)", "Elegant og mystisk, fuldt påklædt.",
     "An elegant female clockwork automaton with a porcelain face, brass joints and visible gears behind a glass panel "
     "in her chest, wearing a high-collared Renaissance gown of deep green velvet with gold embroidery, standing in a "
     "cabinet of curiosities among globes, astrolabes, pocket watches and specimen jars, candlelight and soft window "
     "light. Fully clothed, tasteful, graceful and slightly mysterious."),
]


def card(code, title, note, prompt):
    full = f"{prompt}\n\n{STYLE}"
    return (f'<section class="card"><div class="head"><span class="code">{code}</span><h3>{html.escape(title)}</h3></div>'
            f'<p class="note">{html.escape(note)}</p><pre>{html.escape(full)}</pre>'
            f'<p class="file">Gem som: <b>{code.lower()}-{{variant}}.png</b> &nbsp;·&nbsp; fx {code.lower()}-a.png, {code.lower()}-b.png</p></section>')


doc = f"""<!doctype html><html lang="da"><head><meta charset="utf-8"><style>
@page {{ size: A4; margin: 16mm 15mm; }}
body {{ font-family: Inter, sans-serif; color:#1E1A15; font-size: 10.5pt; line-height: 1.45; }}
h1 {{ font-family: 'DejaVu Serif', serif; font-size: 24pt; margin: 0 0 2mm; color:#7E5E26; }}
h2 {{ break-after: avoid; font-family: 'DejaVu Serif', serif; font-size: 15pt; color:#7E5E26; border-bottom: 1.5px solid #C9A45A; padding-bottom: 1mm; margin-top: 8mm; }}
.lead {{ font-size: 11.5pt; }}
ol li, ul li {{ margin-bottom: 1.5mm; }}
.card {{ border: 1px solid #C9A45A; border-radius: 3mm; padding: 4mm 5mm; margin: 4mm 0; break-inside: avoid; background: #FBF6EA; }}
.head {{ display:flex; align-items:center; gap: 3mm; }}
.code {{ background:#7E5E26; color:#F0E4C8; font-weight:700; border-radius: 2mm; padding: 0.5mm 2.5mm; font-size: 10pt; }}
h3 {{ margin: 0; font-size: 12.5pt; }}
.note {{ margin: 1.5mm 0 2mm; color:#7A3F22; font-size: 9.5pt; }}
pre {{ white-space: pre-wrap; font-family: 'JetBrains Mono', monospace; font-size: 8.6pt; background:#fff; border:1px solid #E6D7B4; border-radius: 2mm; padding: 3mm; margin: 0; }}
.file {{ font-size: 9pt; margin: 2mm 0 0; color:#555; }}
.box {{ background:#2E5C58; color:#F0E4C8; border-radius: 3mm; padding: 4mm 5mm; margin: 4mm 0; }}
.box b {{ color:#E6C987; }}
table {{ border-collapse: collapse; width: 100%; font-size: 9.5pt; }}
td, th {{ border-bottom: 1px solid #E6D7B4; padding: 1.5mm 2mm; text-align: left; vertical-align: top; }}
</style></head><body>
<h1>Steamgears Prints</h1>
<p class="lead"><b>Gemini-prompter til realistiske plakater</b> · 14. november 2026 · 18 motiver</p>

<div class="box"><b>Sådan bruger du dem i Gemini</b><br>
1. Åbn gemini.google.com, og vælg billedgenerering (Pro).<br>
2. Kopiér hele den grå boks for ét motiv, inklusive stil-linjen nederst, og send den.<br>
3. Bed om 3–4 varianter: skriv <i>"Lav tre varianter mere af samme motiv"</i>.<br>
4. Vælg den bedste, og skriv <i>"Lav den i højeste opløsning, stående format 5:7"</i>.<br>
5. Download billedet, og navngiv det som angivet under hver prompt.</div>

<h2>Gode råd</h2>
<ul>
<li><b>Samme kvinde i R1–R3:</b> lav R1 først. Vedhæft derefter det bedste R1-billede, når du sender R2 og R3, og skriv <i>"Brug samme kvinde som på billedet"</i>.</li>
<li><b>Ingen tekst i billedet:</b> titler sætter vi bagefter i Steamgears-typografien. Kommer der alligevel bogstaver med, så skriv <i>"Fjern al tekst"</i>.</li>
<li><b>Tom bund:</b> den nederste femtedel skal være rolig, så titlen kan stå der. Ellers skriv <i>"Gør bunden mere rolig og mørk"</i>.</li>
<li><b>Opløsning:</b> til 50×70 skal billedet helst være mindst 3.000 px på højkanten. Vi opskalerer til trykfilen bagefter.</li>
<li><b>Hold det pænt:</b> alle personer er fuldt påklædte og uden udfordrende positurer, så motiverne kan sælges overalt (se planens regler for pin-up).</li>
<li><b>Ophavsret:</b> skriv aldrig "i stil med" en navngiven kunstner, film eller et spil.</li>
</ul>

<h2 style="break-before: page">Den realistiske serie: luftskibspiraten</h2>
{''.join(card(*c) for c in SERIES)}

<h2 style="break-before: page">Realistiske udgaver af udkastene</h2>
{''.join(card(*c) for c in CLASSICS)}

<h2 style="break-before: page">Dieselpunk og clockwork punk</h2>
{''.join(card(*c) for c in PUNK)}

<h2>Upload</h2>
<table>
<tr><th>Hvad</th><th>Hvordan</th></tr>
<tr><td>Hvor</td><td>Send billederne her i chatten, eller læg dem i repoet under <b>docs/steamgears-udkast/realistisk/</b>.</td></tr>
<tr><td>Filnavne</td><td>Kode + variant, fx <b>r1-a.png</b>, <b>r1-b.png</b>, <b>k3-a.png</b>. Så ved vi, hvilken prompt billedet hører til.</td></tr>
<tr><td>Antal</td><td>Gerne 2–3 varianter pr. motiv. Vi vælger sammen.</td></tr>
<tr><td>Bagefter</td><td>Titel og typografi i Steamgears-stilen, trykfil i 5:7 og upload som produkt via Gelato.</td></tr>
</table>
</body></html>"""

os.makedirs(OUT, exist_ok=True)
src = os.path.join(OUT, "Gemini_prompter.html")
with open(src, "w", encoding="utf-8") as f:
    f.write(doc)
js = ("const {chromium}=require('playwright');(async()=>{const b=await chromium.launch();const p=await b.newPage();"
      f"await p.goto('file://'+{json.dumps(os.path.abspath(src))});"
      f"await p.pdf({{path:{json.dumps(os.path.join(os.path.abspath(OUT), 'Gemini_prompter.pdf'))},format:'A4',printBackground:true}});"
      "await p.screenshot({path:" + json.dumps(os.path.join(os.path.abspath(OUT), 'gemini_preview.png')) + ",fullPage:false});"
      "await b.close();})();")
subprocess.run(["node", "-e", js], check=True)
os.remove(src)
print("ok")
