# Steamgears Prints – udkast

Seks vektor-udkast, ét pr. samling, i den fælles Steamgears-palet (messing, kobber, petrol, creme, sort). Udkastene viser **komposition, palet og typografi**. De endelige motiver laves ud fra prompterne i [`../Steamgears_Motiver_og_SEO_briefs.md`](../Steamgears_Motiver_og_SEO_briefs.md) og efterredigeres.

| Fil | Motiv | Samling | Personligt felt |
| --- | --- | --- | --- |
| `11-skyskraberen` | 11 Skyskraberen | Art Deco & Dieselpunk | – |
| `51-rosa-mechanica` | 51 Rosa mechanica | Mekanisk botanik | – |
| `41-det-mekaniske-cirkus` | 41 Det mekaniske cirkus | Det mekaniske cirkus | – |
| `07-patent-dampmaskine` | 7 Patenttegning: dampmaskine | Steampunk & Gears | Opfinderens navn |
| `26-mads-vaerksted` | 26 Emaljeskilt | Værksted & Garage | Navn |
| `17-nordlys-ekspressen` | 17 Rejseplakat | Art Deco & Dieselpunk | By |

`oversigt.png` viser alle seks. Pin-up (samling 4) er ikke med: figurtegning skal laves af en illustrator eller med billed-AI.

**Format:** SVG i 5:7 (500×700 enheder) kan skaleres til 30×40, 50×70 og 70×100 uden tab. PNG-filerne er kun til visning (1000×1400 px). Teksterne om "personligt felt" er markeringer i udkastet og skal ikke trykkes.

**Skrifter:** udkastene bruger Inter Display, DejaVu Serif og JetBrains Mono, fordi de var installeret. Til tryk bør der vælges skrifter med fri kommerciel licens (fx et art deco-snit til samling 2 og en klassisk antikva til botanik), og teksten konverteres til kurver i trykfilen.

**Genskab eller ret:**

```bash
python3 make_drafts.py .   # skriver de seks SVG-filer
node render.js . 2         # PNG i 2x + oversigt.png (kræver Playwright og Chromium)
```
