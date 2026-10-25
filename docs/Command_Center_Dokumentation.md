# Command Center v6.0 – Dokumentation og Arkitektur

## 1\. Bygningsproces (Installationsflow)

Command Center er bygget som en selv-installerende arkitektur, der automatiserer opsætningen fra terminalen:

1. **Mappestruktur**: Systemet opretter automatisk de nødvendige undermapper (`app/templates`, `app/static`, `app/data`) for at holde skilt ad mellem logik, visning og database.  
2. **Afhængigheder (`requirements.txt`)**: Nødvendige Python-pakker (FastAPI, Uvicorn, Requests, BeautifulSoup4 og Jinja2) defineres og installeres i et isoleret `venv` (Virtual Environment).  
3. **Database (SQLite)**: Ved opstart initialiserer `app/main.py` automatisk en lokal SQLite-database (`data/center.db`) med tabeller til domæner, konkurrenter, artikler, linktjek, social kø og noter.  
4. **Webserver**: FastAPI-applikationen startes via Uvicorn med automatisk genindlæsning (`--reload`).

---

## 2\. Gennemgang af Moduler

### 🎛️ Cockpit (Domæneovervågning)

* **Funktion**: Overvåger dine websites og WordPress-installations-domæner.  
* **Teknik**: Sender HTTP-forespørgsler, måler svartid (ms) og tjekker SSL-certifikatets udløbsdato (antal dage til udløb) via sockets og SSL-moduler.

### 🕷️ SERP & Spy (Konkurrentanalyse)

* **Funktion**: Finder konkurrenter på nettet ud fra specifikke søgeord.  
* **Teknik**: Scraper søgeresultater (f.eks. via DuckDuckGo HTML) og trækker automatisk meta-titler, H1-overskrifter og metabeskrivelser ud fra konkurrenternes sider ved hjælp af BeautifulSoup.

### ✍️ Artikler (AI / Indholdsgenerator)

* **Funktion**: Genererer struktureret og SEO-optimeret indhold baseret på nøgleord.  
* **Teknik**: Producerer skabeloner med overskrifter (H2, H3), lister og konklusioner, som automatisk gemmes i databasen som kladder.

### 🔗 Links (Link- og brudt-link-tjekker)

* **Funktion**: Scanner en side for eksterne og interne links for at finde fejl.  
* **Teknik**: Parser alt HTML-indhold, udtrækker `href`\-attributter og tester modulet igennem op til 25 eksterne links for at fange HTTP 400+ fejl eller timeouts.

### 📱 Social (Opslagskø)

* **Funktion**: Administrerer og planlægger opslag til sociale medier (f.eks. LinkedIn, X).  
* **Teknik**: CRUD-funktionalitet koblet direkte til databasekøen, så opslag kan tilføjes, ses og slettes.

### 📈 SEO (SEO Audit)

* **Funktion**: Analyserer en kildekode-side for grundlæggende on-page SEO-faktorer.  
* **Teknik**: Tjekker for eksistensen af `<title>`, `<meta name="description">`, viewport, JSON-LD schema, H1-overskrifter og manglende alt-tekster på billeder, og beregner en samlet score i procent.

### 📝 Noter (Hurtige noter)

* **Funktion**: Simpel notesblok til workflow-notater.  
* **Teknik**: Tidsstemplede noter gemt direkte i SQLite.