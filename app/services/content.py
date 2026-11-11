"""Indholdsproduktion: strategi, AI-udkast, kvalitetsgate og autopilot.

Modulet indeholder de tunge, rene funktioner bag /articles og autopiloten. De
skriver i databasen via app.core og bruger app.services.wp til at pushe kladder."""
from app.core import AI_KEY
from app.core import AI_KEY_ENV
from app.core import ai_chat
from app.core import HTTP
from app.core import SERPAPI_KEY
from app.core import TRACK_DOMAIN
from app.core import WP_APP_PASSWORD
from app.core import WP_URL
from app.core import WP_USER
from app.core import get_db
from app.core import module_on
from app.core import now_iso
from app.core import safe_request
from app.services.alarms import add_alarm
from app.services.wp import wp_push_draft
from bs4 import BeautifulSoup
from urllib.parse import urlparse
import json as jsonlib
import os
import re
TEMPLATE_ARTICLE = """
<h2>Hvad er {keyword}?</h2>
<p>{keyword} er et emne, hvor god struktur, klar information og brugervenligt indhold gor en stor forskel.</p>
<h3>Hvorfor er {keyword} vigtigt?</h3>
<ul><li>Det hjaelper besogende med hurtigt at finde relevant information.</li><li>Godt struktureret indhold understotter sogemaskineforstaelse.</li></ul>
<h3>Sadan kommer du i gang</h3>
<ol><li>Definer malgruppen og deres behov.</li><li>Lav en klar side med overskrifter, korte afsnit og relevante links.</li><li>Tilfoj FAQ, interne links og relevant struktureret data.</li></ol>
<h3>Konklusion</h3>
<p>Med fokus paa kvalitet, struktur og brugerbehov kan indhold om {keyword} skabe langtidsholdbar vaerdi.</p>
"""

def serp_competitor_context(keyword: str, n: int = 5):
    """Hent top-SERP-resultater som konkurrent-kontekst til artikelgenerering."""
    if not SERPAPI_KEY:
        return ""
    try:
        r = HTTP.get(
            "https://serpapi.com/search",
            params={"engine": "google", "q": keyword, "num": 10, "api_key": SERPAPI_KEY},
            timeout=30,
        )
        r.raise_for_status()
        org = r.json().get("organic_results") or []
        lines = []
        for it in org[:n]:
            t = (it.get("title") or "").strip()
            sn = (it.get("snippet") or "").strip()
            if t:
                lines.append(f"- {t}: {sn}" if sn else f"- {t}")
        if not lines:
            return ""
        return "\n".join(lines)
    except Exception:
        return ""

STRATEGIES = {
    "adsense": {
        "label": "AdSense-indkomst",
        "desc": "Long-tail informationsartikler, volumen forst, rolig CTA",
        "words": "1000-1400",
        "style": (
            "Artikeltypen er LANG og informationsrig (1000-1400 ord). Maalgruppe: laesere fra "
            "Google-sogninger der vil vide noget. Dybdegaaende sektioner, tabel eller liste med "
            "konkrete data, FAQ-sektion med 4-5 spoergsmaal. Roelig, nyttig tone; hojst 1 diskret "
            "produktlink. Fokus: laesetid, laesbarhed og reelle svar."
        ),
        "autopilot": "artikel",
    },
    "affiliate": {
        "label": "Affiliate",
        "desc": "Buyer-intent (best/vs/review), sammenligningstabeller, CTA-tung",
        "words": "900-1200",
        "style": (
            "Artikeltypen er koebeside-venlig (900-1200 ord). Keywordet er typisk buyer-intent "
            "(best, vs, review, hvor kan man koebe). Indhold: sammenligningstabel med 3-5 produkter/"
            "valg, fordele-ulemper-lister, tydelig men aeldelig CTA efter hver stor sektion, FAQ med "
            "4 koeb-relaterede spoergsmaal. Fokus: hjaelp laeseren at vælge."
        ),
        "autopilot": "artikel",
    },
    "backlinks": {
        "label": "Backlink-vÃ¦kst",
        "desc": "Link-vÃ¦rdigt indhold + prospector/outreach autopilot",
        "words": "700-1000",
        "style": (
            "Artikeltypen er link-venlig (700-1000 ord): lister ('10 bedste ...'), checklister, "
            "begynder-guides og ressourcesider andre sider naturligt vil linke til. Klar struktur, "
            "citervenlige facts, faerre produktlinks. Autopiloten koerer ogsa backlink-prospecting "
            "paa keywords i denne strategi."
        ),
        "autopilot": "backlink",
    },
}

DEFAULT_STRATEGY = "adsense"

def get_active_strategy() -> dict:
    try:
        with get_db() as db:
            row = db.execute("SELECT value FROM settings WHERE key='active_strategy'").fetchone()
        key = row["value"] if row else DEFAULT_STRATEGY
    except Exception:
        key = DEFAULT_STRATEGY
    return STRATEGIES.get(key, STRATEGIES[DEFAULT_STRATEGY])

def generate_article_ai(keyword: str, strategy: dict = None):
    st = strategy or get_active_strategy()
    competitors = serp_competitor_context(keyword)
    if competitors:
        comp_block = (
            "TOP 5 KONKURRENTER PA GOOGLE FOR DETA KEYWORD (titel + snippet):\n"
            f"{competitors}\n\n"
            "DIN OPGAVE: Skriv en artikel der er MAERKBART BEDRE end disse resultater. "
            "Dæk alt hvad konkurrenterne dækker (content gap), og tilføj mere: konkrete "
            "materialer, prisestimater, trin-for-trin, praktiske detaljer. "
            "Byg KUN pa faktuelle, verifikbare oplysninger - ingen opdigtede tal, "
            "ingen tom fyldstof-saetninger ('in today's world', 'look no further' osv. "
            "er forbudt). Hver saetning skal give laeseren ny, brugbar info."
        )
    else:
        comp_block = (
            "KVALITETSKRAV: Byg KUN pa faktuelle, verifikbare oplysninger om emnet - "
            "ingen opdigtede tal eller statistik. Ingen tom fyldstof-saetninger. "
            "Hver saetning skal give laeseren konkret, brugbar info (materialer, "
            "prisniveauer, trin, fejl man skal undga). Mål: bedre end de nuværende "
            "topresultater pa Google for dette keyword."
        )
    prompt = (
        f"Write an SEO-optimized blog article draft in English about '{keyword}' for a steampunk "
        f"cosplay & merchandise webshop. Output raw HTML (h2/h3/p/ul/ol only, no <html> wrapper). "
        f"Include: engaging intro, 3-4 H2 sections, a bullet list, an FAQ section, "
        f"and a short conclusion. Around {st['words']} words. No images. Natural, helpful tone.\n\n"
        f"STRATEGI ({st['label']}): {st['style']}\n\n"
        f"{comp_block}"
    )
    return ai_chat(prompt, max_tokens=3000)

QUALITY_MIN_WORDS = int(os.environ.get("QUALITY_MIN_WORDS", "400") or 0)

def quality_check(content: str, keyword: str) -> dict:
    """Deterministisk tjek foer en artikel maa blive WP-kladde.
    Blokerer: for faa ord (min. QUALITY_MIN_WORDS, eller 80 % af SERP-gennemsnittet fra Content Gap),
    fokus-keyword mangler, under 2 H2-overskrifter. Advarer: faerre end 2 interne links."""
    soup = BeautifulSoup(content or "", "html.parser")
    text = soup.get_text(" ", strip=True)
    words = len(text.split())
    min_words = QUALITY_MIN_WORDS
    try:
        with get_db() as db:
            gap = db.execute("SELECT stats_json FROM content_gap WHERE keyword=? ORDER BY id DESC LIMIT 1", (keyword,)).fetchone()
        avg = jsonlib.loads(gap["stats_json"]).get("summary", {}).get("avg_words", 0) if gap and gap["stats_json"] else 0
        if avg:
            min_words = max(min_words, int(avg * 0.8))
    except Exception:
        pass
    h2 = len(soup.find_all("h2")) or len([l for l in (content or "").splitlines() if l.startswith("## ")])
    internal = 0
    for a in soup.find_all("a", href=True):
        href = a["href"]
        if href.startswith("/") or (TRACK_DOMAIN and TRACK_DOMAIN in href):
            internal += 1
    errors, warnings = [], []
    if words < min_words:
        errors.append(f"for kort: {words} ord (min. {min_words})")
    if keyword and keyword.lower() not in text.lower():
        errors.append(f"fokus-keyword '{keyword}' mangler")
    if h2 < 2:
        errors.append(f"kun {h2} H2-overskrift(er), min. 2")
    if internal < 2:
        warnings.append(f"kun {internal} interne link(s), anbefalet min. 2")
    return {"passed": not errors, "words": words, "min_words": min_words, "h2": h2, "internal_links": internal,
            "errors": errors, "warnings": warnings}

def autopilot_sync():
    """Growth-autopilot: vaelg aeldste ubrugte keyword-idee -> AI-artikel -> (valgfrit) WP-kladde."""
    if not AI_KEY:
        with get_db() as db:
            add_alarm(db, "growth", f"Autopilot sprang over: {AI_KEY_ENV} mangler", "advarsel")
        return "no-ai"
    with get_db() as db:
        row = db.execute(
            "SELECT id, idea FROM keyword_ideas WHERE idea IS NOT NULL AND idea != '' "
            "AND idea NOT IN (SELECT keyword FROM articles) ORDER BY id ASC LIMIT 1"
        ).fetchone()
    if not row:
        # Idea-puljen er tom: sow nye via Google-autocomplete fra eksisterende keywords
        try:
            with get_db() as db:
                seeds = [r["keyword"] for r in db.execute("SELECT DISTINCT keyword FROM keywords LIMIT 5").fetchall()]
            if not seeds:
                seeds = ["steampunk costume", "steampunk goggles"]
            import urllib.parse as _up
            newideas = []
            for seed in seeds[:3]:
                rr = HTTP.get(
                    "https://suggestqueries.google.com/complete/search",
                    params={"client": "firefox", "q": seed, "hl": "en"},
                    timeout=10,
                )
                for sug in (rr.json()[1] or [])[:5]:
                    if sug.lower() != seed.lower():
                        newideas.append(sug)
            with get_db() as db:
                for ni in dict.fromkeys(newideas):
                    db.execute("INSERT OR IGNORE INTO keyword_ideas (keyword, idea, source, created_at) VALUES (?,?,?,?)",
                               (ni.split()[0] if ni else "", ni, "autopilot", now_iso()))
            with get_db() as db:
                row = db.execute(
                    "SELECT id, idea FROM keyword_ideas WHERE idea IS NOT NULL AND idea != '' "
                    "AND idea NOT IN (SELECT keyword FROM articles) ORDER BY id ASC LIMIT 1"
                ).fetchone()
        except Exception as e:
            with get_db() as db:
                add_alarm(db, "growth", f"Autopilot kunne ikke hente nye ideer: {str(e)[:120]}", "advarsel")
            return "no-ideas"
        if not row:
            return "no-ideas"
    idea = row["idea"].strip()
    st_auto = get_active_strategy()
    if st_auto.get("autopilot") == "backlink":
        try:
            prospect_sync(idea)
        except Exception as e:
            with get_db() as db:
                add_alarm(db, "growth", f"Autopilot-prospecting fejlede for '{idea}': {str(e)[:120]}", "advarsel")
        with get_db() as db:
            db.execute("DELETE FROM keyword_ideas WHERE id=?", (row["id"],))
        return "backlink-prospect"
    try:
        content = generate_article_ai(idea, st_auto)
    except Exception as e:
        with get_db() as db:
            add_alarm(db, "growth", f"Autopilot-generering fejlede for '{idea}': {str(e)[:150]}", "advarsel")
        return "ai-fail"
    title = f"Guide: {idea}"
    with get_db() as db:
        cur = db.execute(
            "INSERT INTO articles (title, keyword, content, source, created_at) VALUES (?,?,?,?,?)",
            (title, idea, content, "Autopilot", now_iso()),
        )
        art_id = cur.lastrowid
        db.execute("DELETE FROM keyword_ideas WHERE id=?", (row["id"],))
    gate = quality_check(content, idea)
    if not gate["passed"]:
        with get_db() as db:
            db.execute("UPDATE articles SET status=? WHERE id=?", ("Stoppet af kvalitetsgate: " + "; ".join(gate["errors"]), art_id))
            add_alarm(db, "kvalitet", f"Autopilot-artikel #{art_id} ('{idea}') blev ikke sendt til WP: " + "; ".join(gate["errors"]), "advarsel")
        return f"quality-blocked:{art_id}"
    if WP_URL and WP_USER and WP_APP_PASSWORD and module_on("wp_push"):
        try:
            wp_id = wp_push_draft(title, content)
            link = f"{WP_URL.rstrip('/')}/wp-admin/post.php?post={wp_id}&action=edit"
            with get_db() as db:
                db.execute("UPDATE articles SET status='Sendt til WP (kladde)', wp_link=? WHERE id=?", (link, art_id))
        except Exception as e:
            with get_db() as db:
                add_alarm(db, "growth", f"Autopilot WP-push fejlede for #{art_id}: {str(e)[:150]}", "advarsel")
    return f"ok:{art_id}"

def classify_site(url: str):
    u = (url or "").lower()
    if any(x in u for x in ("/blog/", ".blogspot", "medium.com", "substack.com")):
        return "blog"
    if any(x in u for x in ("directory", "liste", "resources", "tools")):
        return "liste"
    if any(x in u for x in ("forum", "reddit.com", "quora.com")):
        return "forum"
    return "artikel"

EMAIL_RE = re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")

def prospect_sync(keyword: str):
    if not SERPAPI_KEY:
        with get_db() as db:
            add_alarm(db, "growth", "Backlink-prospector: SERPAPI_KEY mangler", "advarsel")
        return
    r = HTTP.get(
        "https://serpapi.com/search",
        params={"engine": "google", "q": keyword, "num": 10, "api_key": SERPAPI_KEY},
        timeout=20,
    )
    results = (r.json().get("organic_results") or [])[:10]
    for res in results:
        url = res.get("link") or ""
        if not url or urlparse(url).netloc in (TRACK_DOMAIN, "www." + TRACK_DOMAIN):
            continue
        site = urlparse(url).netloc
        stype = classify_site(url)
        email, draft = None, None
        try:
            resp = safe_request(url, timeout=6)
            found = EMAIL_RE.findall(resp.text or "")
            email = next((e for e in found if not any(x in e.lower() for x in (".png", ".jpg", ".webp", ".svg", "example.com", "sentry"))), None)
        except Exception:
            pass
        if AI_KEY and email:
            try:
                prompt = (
                    f"Write a short (max 120 words) friendly outreach email in English to {email} "
                    f"who runs {site}. Suggest a steampunk cosplay guide or resource relevant to "
                    f"their page about '{keyword}' as a reason to add a link to our site {TRACK_DOMAIN}. "
                    f"Output only the email body."
                )
                draft = ai_chat(prompt, max_tokens=3000, timeout=60)
            except Exception:
                draft = None
        if not draft:
            draft = (f"Hej! Vi har lavet en guide om '{keyword}' paa {TRACK_DOMAIN}, som dine laesere "
                     f"maaske kan bruge. Maa vi linke den ind? (Skabelon-draft - saet {AI_KEY_ENV} for AI-drafts)")
        with get_db() as db:
            db.execute(
                "INSERT INTO backlink_prospects (keyword, site, url, type, email, draft, created_at) VALUES (?,?,?,?,?,?,?)",
                (keyword, site, url, stype, email, draft, now_iso()),
            )
