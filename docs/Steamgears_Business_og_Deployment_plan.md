# Steamgears Prints – business plan og deployment plan

**Dato:** 13. november 2026 · **Opdateret:** 14. november 2026 · **Beslutning:** plakater på bestilling (print-on-demand) · **Erstatter:** dropshipping-planen af 13. november 2026

steamgears.eu bliver en plakatbutik med retro- og steampunk-motiver. Gelato trykker i EU og sender direkte til kunden, så der er intet lager og ingen leverandørjagt. Pengene tjenes på plakater i ramme og på sæt. Plakater uden ramme er døråbneren via Pinterest, Etsy og SEO, som Command Center og Autopilot allerede kan drive.

> Priser og salgstal herunder er **regneeksempler** fra offentlige kilder og leverandørblogs. De bekræftes med en gratis Gelato-konto og en testordre i uge 1.

---

## 1. Hvorfor plakater (beslutningsgrundlag)

Fem muligheder blev scoret på efterspørgsel, indtjening pr. salg, genbrug af det eksisterende, tid til første salg, risiko og lager:

| Mulighed | Point (af 30) | Hvorfor den ikke blev valgt |
| --- | --- | --- |
| **Plakater på bestilling** | **22** | Valgt |
| Værktøjerne som tjeneste | 19 | Højt loft, men mest arbejde og ansvar. Mulig senere fase |
| Steam Deck-affiliate | 18 | Lav provision (1–5 %), varemærkerisiko ved "Steam", faldende søgetrafik |
| STL-filer | 17 | Ca. $4 pr. salg, og køberne bruger markedspladserne |
| Dropshipping af fysiske varer | – | €3 i told pr. pakke siden 1. juli 2026, og steampunk-varer findes ikke på EU-lager |
| Dropshipping af spilnøgler | – | Svindel og inddragne nøgler, gråzone hos betalingsudbydere, varemærkerisiko |

## 2. Koncept og samlinger

| Samling | Indhold | Annoncer | Rolle |
| --- | --- | --- | --- |
| **Steampunk & Gears** | Maskiner, luftskibe, tandhjul, ure | Ja | Kerne. Genbruger eksisterende indhold og SEO |
| **Dieselpunk & Art Deco** | Byer, tog, fly og vintage-reklamer i deco-stil | Ja | Bred appel |
| **Værksted & Garage** | Retro-skilte, motorcykler, værktøj | Ja | Bred målgruppe og gaveegnet |
| **Retro Pin-up** | Egne motiver i "sød" stil, uden nøgenhed | **Nej** (Metas regler) | Pinterest, Etsy og SEO |
| **Det mekaniske cirkus** | Akrobater, karruseller og telte i messing og striber | Ja | Pinterest-trend 2026 (+70–130 % søgninger) |
| **Mekanisk botanik** | Botaniske plancher af kobber og tandhjul | Ja | Den største faste kategori med egen vinkel |
| **Airship Chronicles** (realistisk serie) | Luftskibskaptajnen og hendes verden, malerisk realisme | Ja | Hovedserien: sælges enkeltvis og som sæt |
| **Engine Room / Mechanica Naturalis** (realistisk) | Mekanikeren, den mekaniske ugle og urværkshjertet | Ja | Supplerer hovedserien |
| **Dieselpunk & Clockwork punk** (realistisk, ny) | Zeppelin-storby, aviatrix, iron titan; renæssanceværksted, ornithopter, automat | Ja | Udvider universet. Prompter D1–D3 og C1–C3 |

**Formater:** 30×40, 50×70 og 70×100 cm, uden ramme eller i ramme, plus sæt med 2–3 motiver i samme stil. **Metal** (3 mm aluminium hos Gelato, også i børstet sølv) er et tilvalg til værkstedsskilte og patenttegninger: 30×40 standard koster 180 kr. + 59 kr. fragt (dækning ca. 150 kr. ved 449 kr.), 50×70 standard koster 284 kr. + 147 kr. (dækning ca. 192 kr. ved 799 kr.). Metal trykkes i Tyskland og leveres på 7–11 dage.

**NSFW:** ikke på steamgears.eu. Stripe forbyder AI-genereret voksenindhold, Meta og Pinterest begrænser nøgenhed, og Google SafeSearch kan filtrere hele domænet. Pin-up forbliver fuldt påklædt. En eventuel NSFW-afdeling hører til et separat domæne med egen betalingsudbyder og motiver lavet af mennesker.

## 2b. Motivproduktion

| Trin | Værktøj | Status 14. november |
| --- | --- | --- |
| Prompter | [`steamgears-udkast/Gemini_prompter.pdf`](steamgears-udkast/Gemini_prompter.pdf): 18 prompter (R1–R5, K1–K7, D1–D3, C1–C3) | Færdig |
| Billeder | Gemini Pro (manuelt), Canva (kvote brugt op) eller OpenRouter via [`gen_batch.py`](steamgears-udkast/gen_batch.py) med `google/gemini-3-pro-image` i 4K | 12 billeder fra Gemini på Drive. 2 fra Canva (samme kaptajn i Sky Boarding og The Storm Plank). OpenRouter venter på kredit |
| Mockups | [`make_posters.py`](steamgears-udkast/make_posters.py): 5:7 med titel og serie | 12 mockups i [`steamgears-udkast/realistisk/`](steamgears-udkast/realistisk/) |
| Trykfiler | Mindst ca. 4.100 px på højkanten til 50×70 (150 dpi), helst 8.300 px (300 dpi) | **Mangler:** Gemini-billederne er kun ca. 900×1.250 px. De laves igen i 4K via OpenRouter (ca. $0,24 pr. billede) eller opskaleres |
| Produkter | Gelato-plugin på WooCommerce | Mangler WordPress-adgang (se afsnit 7) |

**Konsistens:** samme kaptajn i hele Airship Chronicles. Billeder laves med The Aurora Helm som referencebillede (`gen_batch.py --ref`).

## 3. Motiver og ophavsret

- [ ] **Kun motiver, I har ret til at sælge:**
  - egne, AI-genererede og kuraterede motiver
  - illustratorer, hvor I køber rettighederne skriftligt
  - frie værker af kunstnere, der døde før 1956 (EU: 70 år efter død)
- [ ] **Ingen kendte pin-up-kunstnere.** Elvgren (død 1980) er beskyttet til ca. 2050 og Vargas (© Hearst) til ca. 2052.
- [ ] **Ingen varemærker, logoer eller kendte figurer** (bilmærker, film, spil).
- [ ] **AI-motiver kan næppe ophavsretsbeskyttes**, så konkurrenter må kopiere dem. Modtræk: samlinger, egen stil og hurtig udgivelse.
- [ ] Hvert motiv redigeres manuelt og kvalitetstjekkes i fuld størrelse (300 dpi ved 50×70) før udgivelse.

## 4. Økonomi pr. ordre (Gelato-priser hentet 13. november 2026)

Priserne er hentet fra Gelatos API (`/v3/products/{uid}/prices` og `/v4/orders:quote`) for levering til Aarhus. Papiret er 200 g mat. **Antagelse:** Gelatos priser er uden moms. Det skal bekræftes på den første faktura. Kunden betaler **49 kr. i fragt** (39 kr. ex moms) under 499 kr. og ingen fragt over.

| Produkt | Trykkes i | Levering | Gelato: vare + fragt (kr.) | Salgspris inkl. moms (kr.) | **Dækning før annoncer (kr.)** |
| --- | --- | --- | --- | --- | --- |
| 30×40 uden ramme | DK | 4–5 dage | 57 + 58 | 199 | **≈ 80** |
| 50×70 uden ramme | DK | 5–6 dage | 87 + 58 | 299 | **≈ 127** |
| 70×100 uden ramme | DK | 5–6 dage | 95 + 64 | 399 | **≈ 190** |
| Sæt 3 × 30×40 uden ramme | DK | 4–5 dage | 170 + 67 | 449 | **≈ 152** |
| Sæt 3 × 50×70 uden ramme | DK | 5–6 dage | 260 + 67 | 699 (fri fragt) | **≈ 219** |
| 30×40 i kobberramme (alu) | DE | 7–11 dage (DHL) | 179 + 51 | 449 | **≈ 159** |
| Sæt 3 × 30×40 i kobberramme | DE | 7–11 dage (DHL) | 537 + 99 | 1.199 (fri fragt) | **≈ 300** |
| 50×70 i kobberramme (alu) | DE | 7–11 dage (DHL) | 353 + 163 | 899 (fri fragt) | **≈ 186** |
| 50×70 i sort træramme | SE | 5–6 dage | 409 + 163 | 899 (fri fragt) | **≈ 130** |

**Det har ændret sig i forhold til regneeksemplet:**
- En 50×70 i ramme koster ca. **516–572 kr.** hos Gelato inkl. fragt, ikke ca. 193 kr. Til 599 kr. ville hver ordre give underskud. Store rammer skal koste mindst 899 kr.
- Plakater uden ramme **trykkes i Danmark** og leveres på 4–6 dage. Rammer sendes fra Tyskland eller Sverige. Den billigste fragt tager 7–11 dage, mens UPS (6–7 dage) koster 42–83 kr. mere.
- **70×100 uden ramme har den bedste dækning**, fordi trykket kun koster 8 kr. mere end 50×70.
- Gelato har **kobber- og guldrammer i aluminium**. De er de billigste og passer direkte til steampunk.

**Regler:**
1. Kerneprodukterne er **plakater uden ramme i 50×70 og 70×100 samt sæt** (dansk tryk og hurtig levering). Rammer er et tilbud oveni, primært 30×40 i kobber.
2. Kunden betaler 49 kr. i fragt under 499 kr. Fri fragt over 499 kr. trækker kurven op mod sæt.
3. Betalte annoncer kun på produkter med en dækning på mindst 186 kr.: 70×100, sæt og kobberrammer. Kunden må højst koste det, produktet dækker.
4. Rammer leveres på 7–11 dage, og det står ærligt på produktsiden. Alternativt vælges UPS, og prisen hæves med ca. 50 kr.
5. Store træ- og aluminiumsrammer i 50×70 og 70×100 tages først med, hvis efterspørgslen viser sig.

## 5. Kanaler

| Prioritet | Kanal | Værktøj | Mål efter 90 dage |
| --- | --- | --- | --- |
| 1 | Pinterest (pin som "indretning", ikke "kunst") | Autopilot: planlagte opslag | 5 pins om dagen. Mindst 1.000 besøg om måneden |
| 2 | Etsy (samme motiver, ekstra kanal) | Gelato–Etsy-integration | 40 opslag. Første salg inden uge 6 |
| 3 | SEO og AI-synlighed | Command Center: Vækst-fanen, briefs, AI-synlighed | 10 sider på smalle søgninger ("steampunk plakat", "retro værksted plakat") |
| 4 | E-mail | Velkomst, forladt kurv, ny samling | Mindst 15 % af omsætningen |
| 5 | Meta-annoncer (ikke pin-up) | Test på 3.000 kr. | Overskud på mindst ét motiv |

## 6. Deployment plan (90 dage)

| Fase | Uger | Indhold | Fortsæt hvis | Stop eller ret hvis |
| --- | --- | --- | --- | --- |
| 0. Fundament | 1–2 | Gelato-konto, WooCommerce-plugin, testordre til DK, første 18 realistiske motiver som trykfiler i 4K (afsnit 2b), resten af motivlisten løbende | Kvaliteten er god, levering højst 5 dage, priserne bekræftet | Kvaliteten holder ikke, så prøv Prodigi eller Printful |
| 1. Organisk start | 3–6 | Pinterest hver dag, Etsy-butik, 10 SEO-sider, e-mail-flows | Mindst 1.000 besøg om måneden og første salg | 0 salg efter 6 uger: skift motiver eller samling |
| 2. Kurvværdi og test | 7–12 | Rammer og sæt, tilbud ved kassen, Meta-test på 3.000 kr. | Ordre over 450 kr. og pris pr. kunde under produktets dækning (afsnit 4) | Annoncerne giver underskud: kun organisk |
| 3. Skalering | 13+ | Flere samlinger, sæsoner (jul, fars dag), flere sprog (DE/SE) | | |

**Budget for de 90 dage:** ca. 5.000 kr. (prøvetryk ca. 1.000, Etsy-gebyrer ca. 500, Meta-test 3.000, buffer ca. 500). Ingen faste omkostninger ud over den eksisterende hosting.

## 7. Teknisk tjekliste (fase 0)

**Status på sitet 14. november 2026** (læst via Steam-connectoren, intet ændret):
- WordPress 7.1.4, WooCommerce 11.2.2, Rank Math, Stripe, Autopilot **7.86.0**. **Gelato Integration for WooCommerce 1.3.3**, **Pinterest for WooCommerce** og **Google for WooCommerce** er allerede installeret.
- 20 udgivne produkter: T-shirts (530 kr.), hoodies (335 kr.), mobilcovers (330 kr.), tre Herbarium-plakater (395 kr., én størrelse), lommeure (865–1.000 kr.) og gamle dropship-varer (korsetter, frakker, hat, briller).
- Kategorierne til de nye serier findes allerede, men er tomme: *Airship Pirates & Sky Armada*, *Engineers & Steam Machines*, *Mechanical Nature & Botany*, *Neodeco & Cameo Series*, *Steam Rail Legends* og *Posters & Wall Art*.
- **Fejl:** de eksisterende produkter har ingen Gelato-kobling (ingen Gelato-felter på fx Clockwork Rose, id 965). En ordre bliver altså ikke sendt til tryk af sig selv. Plakaterne har heller ingen størrelser.


- [ ] **Adgang til WordPress:** connectoren *Steam* (AI Engine på steamgears.eu) og *Novamira – Steamgears* (`/wp-json/mcp/novamira-oauth`) forbinder kun ind imellem i cloud-sessionerne. Applikationsadgangskoden i miljøet *command-center* skal gemmes igen med brugernavnet `steam`.
- [ ] **OpenRouter-kredit:** kontoen stod i minus ($15,13 brugt af $15) 14. november. Det stopper både billedproduktionen og Command Centers AI-funktioner.
- [ ] **Trykfiler i 4K** for de første 18 motiver (afsnit 2b), og en testordre af mindst ét af dem.
- [x] Autopilot er på 7.86.0. [ ] Command Center 7.28.0 tjekkes på serveren (`bash scripts/update.sh --version` giver kode 0).
- [x] Gelato-konto og API-nøgle. Priser og fragt til Danmark er hentet (afsnit 4).
- [x] **Gelato Integration for WooCommerce** er installeret (1.3.3).
- [ ] **Kobl produkterne til Gelato.** Produkter skal oprettes eller kobles fra Gelatos dashboard (med trykfil), ellers bliver ordrer ikke sendt til tryk. Start med de tre Herbarium-plakater, og tjek tøj og covers.
- [ ] Fragt: fragtpriser i realtid fra Gelato, eller faste 49 kr. med fri fragt over 499 kr. (afsnit 4).
- [ ] Bestil en testordre til Danmark: 50×70 uden ramme og i ramme. Notér pris, leveringstid og kvalitet.
- [ ] WooCommerce: kategorier pr. samling, variationer for størrelse og ramme, fragtpris synlig i produktoversigten.
- [ ] Ryd eller skjul de gamle dropshipping-produkter. 301-omdiriger de vigtigste URL'er til nye samlinger, og kontrollér det med Command Centers redirect-audit.
- [ ] Command Center:
  - overvåg forsiden og kassen
  - kør et planlagt crawl
  - læg 5 AI-synlighedsspørgsmål ind (fx "hvor køber jeg en steampunk plakat?")
  - lav briefs til de første 10 sider
- [ ] Pinterest for WooCommerce er installeret: forbind kataloget og tjek, at produkterne synkroniseres. Autopilot: 5 opslag om dagen fra kladdekøen.
- [ ] Etsy-butik koblet på Gelato med samme motiver og priser plus Etsy-gebyrer.

## 8. Lovkrav

- [ ] Fragtpris vises allerede i produktoversigten (Forbrugerombudsmanden har politianmeldt for det modsatte).
- [ ] **Fortrydelsesret på 14 dage:** standardplakater er ikke "fremstillet efter kundens specifikationer", så fortrydelsesretten gælder. Gelatos returvilkår skal dække det, ellers bærer butikken udgiften.
- [ ] GPSR: Gelato som producent og importør i EU skal fremgå. Bekræft det hos Gelato.
- [ ] OSS-moms ved salg til andre EU-lande. Etsy afregner selv moms på sine salg.
- [ ] Handelsbetingelser, cookie-samtykke og privatlivspolitik er opdateret til den nye butik.

## 9. Mål og risici

**KPI'er** (følges i Autopilot og Command Center):
- besøg
- konvertering (mål 1,5 % eller mere)
- gennemsnitlig ordre (mål over 450 kr.)
- andel af ordrer med ramme
- pris pr. kunde (under produktets dækning, afsnit 4)
- returandel (højst 3 %)

| Risiko | Modtræk |
| --- | --- |
| Konkurrence fra Desenio og Poster Store | Smal niche og samlinger frem for generisk indretning |
| Motiver kopieres | Hurtig udgivelse, samlinger og brandet Steamgears |
| Platforme (Etsy rydder op i AI-indhold, Meta afviser pin-up) | Kuratering, flere kanaler, pin-up kun organisk |
| Gelatos kvalitet eller priser passer ikke | Prodigi og Printful som alternativ (fase 0-gate) |
| Pinterest-trafik konverterer dårligt | Bedre motiver og titler. Etsy og SEO som andre ben |
| Billeder i for lav opløsning | Lav trykfiler i 4K før salg. Testordre på hvert nyt format |
| Billed-AI-kvoter (Gemini, Canva) løber tør | OpenRouter som fast kilde med betaling pr. billede |

**Åbne spørgsmål:**
- Hvem laver og kuraterer motiverne, og hvor mange timer om ugen?
- Skal butikken være på dansk, engelsk eller begge? Det afgør SEO og Etsy.
- Hvad sker der med eksisterende kunder og e-mail-liste?

## 10. Kilder

Research 12.–13. november 2026. De fleste kilder er leverandør- og affiliateblogs, så brug tallene som retning.

- [Gelato: WooCommerce-integration](https://www.gelato.com/uk/print-on-demand/woocommerce) · [Gelato: vægkunst og priser](https://www.gelato.com/au/custom-wall-art)
- [Gelato vs. Printful vs. Printify i EU](https://marketing4ecommerce.net/en/gelato-printful-printify-comparative/) · [Printful-priser 2026](https://www.stylefactoryproductions.com/?p=26252) · [Prodigi-anmeldelse](https://ecommerce-platforms.com/?p=108099)
- [Desenio Group, delårsrapport 2026](https://storage.mfn.se/e4667d46-fe4a-4b37-8a58-a8841986dd50/desenio-interim-report-q1-2026.pdf)
- [Pinterest for plakatsælgere](https://www.artomate.app/blog/pinterest-etsy-poster-sellers-free-traffic) · [Etsy: salg af plakater 2026](https://www.insightagent.app/guides/selling-posters-on-etsy)
- [Meta: regler for nøgenhed og seksuelt indhold i annoncer](https://transparency.meta.com/policies/ad-standards/objectionable-content/adult-nudity-and-sexual-activity/)
- [Etsy, printables og OSS-moms](https://freenance.io/side-hustle/selling-printables-etsy-eu-2026-passive-income-pl-de-fr-es-it-vat-oss-shop-setup/)
- [Bigblue: €3-told](https://www.bigblue.co/blog/end-of-de-minimis-eu-3-euro-customs-duty-small-parcels) · [Dansk Erhverv: fragtpris i oversigten](https://www.danskerhverv.dk/presse-og-nyheder/nyheder/2019/november/forbrugerombudsmanden-politianmelder-netbutik-for-ikke-at-oplyse-om-fragt-i-produktoversigten/)
