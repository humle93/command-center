# ⚡ Command Center v6.0 – Visuel Bruger- og Systemmanual

---

## 📑 Indeks

1. [Hvad er Command Center?](#1-hvad-er-command-center)  
2. [Installationsguide (Trin for trin)](#2-installationsguide-trin-for-trin)  
3. [Arkitektur & Bygningsproces](#3-arkitektur--bygningsproces)  
4. [Gennemgang af Moduler](#4-gennemgang-af-moduler)  
   - [🎛️ 1\. Cockpit (Domæneovervågning)](#1-cockpit-domæneovervågning)  
   - [🕷️ 2\. SERP & Spy (Konkurrentanalyse)](#2-serp--spy-konkurrentanalyse)  
   - [✍️ 3\. Artikler (AI Indholdsgenerator)](#3-artikler-ai-indholdsgenerator)  
   - [🔗 Links (Brudte links tjekker)](#4-links-brudte-links-tjekker)  
   - [📱 Social (Opslagskø)](#5-social-opslagskø)  
   - [📈 SEO (On-Page SEO Audit)](#6-seo-on-page-seo-audit)  
   - [📝 Noter (Workflow & Idéer)](#7-noter-workflow--idéer)

---

## 1\. Hvad er Command Center?

Command Center er dit alt-i-én dashboard til styring af WordPress-sites, SEO-analyser, konkurrentovervågning og indholdsgenerering.

 ┌─────────────────────────────────────────────────────────┐

 \|                   COMMAND CENTER v6.0                   \|

 \|  \[ Cockpit \] \[ Spy \] \[ Artikler \] \[ Links \] \[ Social \]  \|

 └────────────────────────────┬────────────────────────────┘

                              ▼

                 \[ FastAPI \+ SQLite Database \]

---

## 2\. Installationsguide (Trin for trin)

Det er lynhurtigt at komme i gang. Følg blot disse enkle trin i din terminal:

\# 1\. Opret og gå ind i mappen

mkdir \-p \~/command-center && cd \~/command-center

\# 2\. Kør installationsscriptet / start serveren

./run.sh

---

## 3\. Arkitektur & Bygningsproces

Systemet opbygges automatisk via følgende flow:

\[ Terminal \] ──► Opretter Mapper ──► Opsætter Python VENV ──► Installerer Pakker ──► Starter SQLite & Webserver

1. **Mappestruktur**: Der oprettes mapper til templates, statiske filer og database.  
2. **Python VENV**: Isolerede pakker (`fastapi`, `uvicorn`, `requests`, `beautifulsoup4`, `Jinja2`) installeres.  
3. **Database**: SQLite opretter automatisk tabeller ved første start.

---

## 4\. Gennemgang af Moduler

### 🎛️ 1\. Cockpit (Domæneovervågning)

Hold øje med dine websites oppetid og sikkerhed.

* **Funktion**: Tjekker om dine sites er online, måler svartid og tjekker SSL-certifikater.  
* **Illustration af flow**:  
    
  \[ Tilføj Domæne \] ──► \[ HTTP Request & SSL Check \] ──► \[ Vis Oppetid & Svartid (ms) \]

---

### 🕷️ 2\. SERP & Spy (Konkurrentanalyse)

Find ud af hvad dine konkurrenter laver på Google.

* **Funktion**: Indtast et søgeord og hent de 5 bedste konkurrenter automatisk.  
* **Illustration af flow**:  
    
  \[ Indtast Søgeord \] ──► \[ Søg via DuckDuckGo \] ──► \[ Udtræk Titel & H1 \]

---

### ✍️ 3\. Artikler (AI Indholdsgenerator)

Skab strukturerede tekster til dine sider på sekunder.

* **Funktion**: Genererer SEO-venlige kladder med H2/H3-overskrifter og lister.  
* **Illustration af flow**:  
    
  \[ Indtast Emne \] ──► \[ Generér Struktur \] ──► \[ Gem som Kladde \]

---

### 🔗 4\. Links (Brudte links tjekker)

Undgå døde links på dine sider.

* **Funktion**: Scanner indholdet for eksterne links og tjekker for HTTP-fejl (400+).  
* **Illustration af flow**:  
    
  \[ Indtast URL \] ──► \[ Find alle Links \] ──► \[ Test HTTP Status \]

---

### 📱 5\. Social (Opslagskø)

Planlæg dit indhold til de sociale medier.

* **Funktion**: Simpel kø til opbevaring af opslag til f.eks. LinkedIn eller X.  
* **Illustration af flow**:  
    
  \[ Skriv Opslag \] ──► \[ Vælg Platform \] ──► \[ Gem i Kø \]

---

### 📈 6\. SEO (On-Page SEO Audit)

Få en prompte vurdering af en sides tekniske SEO.

* **Funktion**: Tjekker titel, meta-beskrivelse, viewport, schema og billeders alt-tekster.  
* **Illustration af flow**:  
    
  \[ Indtast Side URL \] ──► \[ Analyser HTML \] ──► \[ Beregn % Score \]

---

### 📝 7\. Noter (Workflow & Idéer)

* **Funktion**: Tidsstemplede hurtignoter til dine daglige opgaver.