"""SEO-audit og crawl.

Sideanalyse, PageSpeed, crawl og link-tjek - det der kan koeres uden en HTTP-request
fra brugeren. Ruterne i main.py kalder funktionerne herfra."""
from app.core import HTTP
from app.core import LINKCHECK_LIMIT
from app.core import PSI_API_KEY
from app.core import get_db
from app.core import normalize_url
from app.core import now_iso
from app.core import safe_request
from app.services.alarms import add_alarm
from bs4 import BeautifulSoup
from datetime import datetime
from urllib.parse import urlparse
import hashlib
import re
import time
import urllib.parse
def _check(name, ok, weight, info=""):
    return {"name": name, "ok": bool(ok), "weight": weight, "info": info}

def analyze_page(url: str, keyword: str = "", html: str = None, status_code: int = None, ms: int = None):
    """Dyb sideanalyse i stil med RankMath Pro / Yoast Premium."""
    keyword = (keyword or "").strip().lower()
    items = []
    try:
        if html is None:
            url = normalize_url(url)
            t0 = datetime.now()
            response = safe_request(url, timeout=10)
            ms = int((datetime.now() - t0).total_seconds() * 1000)
            status_code = response.status_code
            html = response.text
        soup = BeautifulSoup(html, "html.parser")

        # --- Grundlaeggende ---
        items.append(_check("HTTP 200", status_code == 200, 3, f"status {status_code}"))
        is_https = url.startswith("https://")
        items.append(_check("HTTPS", is_https, 3))
        title = soup.find("title")
        title_text = title.get_text(strip=True) if title else ""
        title_len = len(title_text)
        items.append(_check("Titel findes", bool(title_text), 3))
        items.append(_check("Titel-laengde 30-60", 30 <= title_len <= 60, 2, f"{title_len} tegn"))
        meta = soup.find("meta", attrs={"name": "description"})
        meta_text = (meta.get("content", "").strip() if meta else "")
        meta_len = len(meta_text)
        items.append(_check("Meta description findes", bool(meta_text), 3))
        items.append(_check("Meta description 70-160", 70 <= meta_len <= 160, 2, f"{meta_len} tegn"))
        h1s = soup.find_all("h1")
        items.append(_check("Praecis een H1", len(h1s) == 1, 3, f"{len(h1s)} stk"))
        h2s = soup.find_all("h2")
        items.append(_check("Min. 2 H2-underoverskrifter", len(h2s) >= 2, 2, f"{len(h2s)} stk"))
        h1_text = h1s[0].get_text(strip=True).lower() if h1s else ""
        viewport = soup.find("meta", attrs={"name": "viewport"})
        items.append(_check("Viewport (mobil)", bool(viewport), 3))
        robots_meta = soup.find("meta", attrs={"name": "robots"})
        noindex = robots_meta and "noindex" in (robots_meta.get("content", "") or "").lower()
        items.append(_check("Ikke noindex", not noindex, 3, "noindex!" if noindex else ""))
        canonical = soup.find("link", rel=lambda v: v and "canonical" in v)
        items.append(_check("Canonical", bool(canonical), 2))
        jsonlds = soup.find_all("script", attrs={"type": "application/ld+json"})
        schema_types = []
        for s in jsonlds:
            try:
                import json as _json
                d = _json.loads(s.string or "{}")
                g = d.get("@graph") or [d]
                for node in g:
                    t = node.get("@type")
                    if isinstance(t, list):
                        schema_types.extend(t)
                    elif t:
                        schema_types.append(t)
            except Exception:
                pass
        items.append(_check("JSON-LD schema", bool(jsonlds), 2, ", ".join(schema_types[:3])))
        og_title = soup.find("meta", attrs={"property": "og:title"})
        og_img = soup.find("meta", attrs={"property": "og:image"})
        items.append(_check("Open Graph", bool(og_title), 1, "med billede" if og_img else "uden billede"))
        twitter = soup.find("meta", attrs={"name": re.compile("twitter:card", re.I)})
        items.append(_check("Twitter card", bool(twitter), 1))
        favicon = soup.find("link", rel=lambda v: v and "icon" in v)
        items.append(_check("Favicon", bool(favicon), 1))
        html_tag = soup.find("html")
        lang = html_tag.get("lang") if html_tag else None
        items.append(_check("lang-attribut", bool(lang), 1, lang or ""))
        images = soup.find_all("img")
        no_alt = [img for img in images if not img.get("alt", "").strip()]
        items.append(_check("Billeder har alt-tekst", len(no_alt) == 0, 2, f"{len(no_alt)} mangler af {len(images)}"))

        # --- Indhold ---
        for tag in soup(["script", "style", "noscript"]):
            tag.decompose()
        text = soup.get_text(" ", strip=True)
        words = re.findall(r"[\w\u00C0-\u024F']+", text)
        wc = len(words)
        items.append(_check("Mindst 300 ord", wc >= 300, 3, f"{wc} ord"))
        sentences = [s for s in re.split(r"[.!?]+\s", text) if len(s.strip()) > 2]
        avg_sent = round(wc / max(len(sentences), 1), 1)
        items.append(_check("Lesbarhed: saetninger < 25 ord", avg_sent < 25, 1, f"snit {avg_sent} ord"))
        def _syllables(w):
            w = w.lower()
            groups = re.findall(r"[aeiouyaeiouy]+", w)
            return max(len(groups), 1)
        try:
            syl = sum(_syllables(w) for w in words)
            flesch = round(206.835 - 1.015 * (wc / max(len(sentences), 1)) - 84.6 * (syl / max(wc, 1)))
            items.append(_check("Flesch-lesbarhed > 50", flesch > 50, 1, f"score {flesch}"))
        except Exception:
            pass
        paragraphs = [p for p in soup.find_all("p") if len(p.get_text(strip=True)) > 20]
        long_paras = 0
        for p in paragraphs:
            if len(re.findall(r"[\w']+", p.get_text())) > 150:
                long_paras += 1
        items.append(_check("Korte afsnit (< 150 ord)", long_paras == 0, 1, f"{long_paras} lange"))
        links_all = [a.get("href", "") for a in soup.find_all("a", href=True)]
        host = urlparse(url).netloc if url else ""
        internal = [l for l in links_all if l.startswith("/") or (host and host in l)]
        external = [l for l in links_all if l.startswith("http") and host and host not in l]
        items.append(_check("Min. 3 interne links", len(internal) >= 3, 2, f"{len(internal)} stk"))
        items.append(_check("Min. 1 eksternt link", len(external) >= 1, 1, f"{len(external)} stk"))
        mixed = is_https and "http://" in html.replace("http://www.w3.org", "")
        items.append(_check("Intet mixed content", not mixed, 2))

        # --- Focus keyword (som RankMath) ---
        if keyword:
            kw = re.sub(r"\s+", " ", keyword)
            items.append(_check("Keyword i titel", kw in title_text.lower(), 3, title_text[:60]))
            items.append(_check("Keyword i meta description", kw in meta_text.lower(), 2))
            slug = urllib.parse.unquote(urlparse(url).path.lower()) if url else ""
            items.append(_check("Keyword i URL", kw.replace(" ", "-") in slug or kw in slug, 2, slug[:40]))
            items.append(_check("Keyword i H1", kw in h1_text, 2))
            first10 = " ".join(words[: max(int(wc * 0.1), 20)]).lower()
            items.append(_check("Keyword i foerste 10 % af teksten", kw in first10, 2))
            density = (text.lower().count(kw) * max(len(kw.split()), 1)) / max(wc, 1) * 100
            items.append(_check("Keyword density 0,5-3 %", 0.5 <= density <= 3.0, 2, f"{density:.1f} %"))

        # --- Hastighed ---
        if ms is not None:
            items.append(_check("Svartid < 1500 ms", ms < 1500, 2, f"{ms} ms"))

        total_weight = sum(c["weight"] for c in items)
        earned = sum(c["weight"] for c in items if c["ok"])
        score = round(earned / total_weight * 100) if total_weight else 0
        return {
            "score": score,
            "items": [{"ok": c["ok"], "text": c["name"] + (f" ({c['info']})" if c["info"] else "")} for c in items],
            "raw": items,
            "title": title_text, "meta": meta_text, "h1": h1_text,
            "words": wc, "internal": len(internal), "external": len(external),
        }
    except Exception as e:
        return {"score": 0, "items": [{"ok": False, "text": f"Fejl: {e}"}], "raw": [],
                "title": "", "meta": "", "h1": "", "words": 0, "internal": 0, "external": 0}

def psi_fetch(url: str):
    if not PSI_API_KEY:
        return None
    try:
        r = HTTP.get(
            "https://www.googleapis.com/pagespeedonline/v5/runPagespeed",
            params={"url": url, "key": PSI_API_KEY, "strategy": "mobile"},
            timeout=60,
        )
        r.raise_for_status()
        d = r.json()
        lr = d.get("lighthouseResult", {})
        cats = lr.get("categories", {}).get("performance", {}).get("score")
        audits = lr.get("audits", {})
        lcp = audits.get("largest-contentful-paint", {}).get("displayValue", "")
        cls = audits.get("cumulative-layout-shift", {}).get("displayValue", "")
        return {"perf": round((cats or 0) * 100), "lcp": lcp, "cls": cls}
    except Exception:
        return None

def deep_extras(url: str):
    """Dyb-niveau: status paa eksterne links + billeder uden alt-tekst."""
    items = []
    try:
        r = safe_request(url, timeout=12)
        soup = BeautifulSoup(r.text, "html.parser")
        base = url
        ext_links = []
        seen = set()
        for a_ in soup.find_all("a", href=True):
            href = urllib.parse.urljoin(base, a_["href"].split("#")[0])
            d = urlparse(href).netloc
            if d and d != urlparse(base).netloc and href not in seen:
                seen.add(href)
                ext_links.append(href)
            if len(ext_links) >= 8:
                break
        broken = 0
        for link in ext_links:
            try:
                lr = safe_request(link, timeout=8)
                if lr.status_code >= 400:
                    broken += 1
            except Exception:
                broken += 1
        items.append({"ok": broken == 0, "text": f"Eksterne links: {len(ext_links)} tjekket, {broken} brodne"})
        no_alt = [im for im in soup.find_all("img") if not (im.get("alt") or "").strip()]
        items.append({"ok": len(no_alt) == 0, "text": f"Billeder uden alt-tekst: {len(no_alt)}"})
    except Exception as e:
        items.append({"ok": False, "text": "Dyb-scan fejlede: " + str(e)[:100]})
    return items

CRAWL_STATE = {"running": False, "done": 0, "total": 0, "start": "", "error": None, "avg": None}

def site_crawl_sync(start_url: str, max_pages: int = 30):
    try:
        start_url = normalize_url(start_url)
        host = urlparse(start_url).netloc
        with get_db() as db:
            db.execute("DELETE FROM seopages")
            db.execute("DELETE FROM crawl_runs")
        # robots.txt + sitemap.xml
        robots_ok = sitemap_ok = False
        sitemap_count = 0
        try:
            r = safe_request(f"https://{host}/robots.txt", timeout=8)
            robots_ok = (r.status_code == 200)
            m = re.search(r"Sitemap:\s*(\S+)", r.text, re.I)
            sitemap_url = m.group(1) if m else f"https://{host}/sitemap.xml"
            r2 = safe_request(sitemap_url, timeout=10)
            if r2.status_code == 200:
                sm = BeautifulSoup(r2.text, "html.parser")
                sitemap_count = len(sm.find_all("loc"))
                sitemap_ok = sitemap_count > 0
        except Exception:
            pass
        with get_db() as db:
            db.execute(
                "INSERT INTO crawl_runs (host, robots_ok, sitemap_ok, sitemap_urls, started_at) VALUES (?,?,?,?,?)",
                (host, int(robots_ok), int(sitemap_ok), sitemap_count, now_iso()),
            )
            run_id = db.execute("SELECT last_insert_rowid() AS id").fetchone()["id"]

        queue = [start_url]
        seen = set()
        CRAWL_STATE.update({"running": True, "done": 0, "total": max_pages, "start": start_url, "error": None, "avg": None})
        total_score = 0
        pages_saved = 0
        while queue and len(seen) < max_pages:
            current = queue.pop(0)
            if current in seen:
                continue
            seen.add(current)
            resp = None
            try:
                t0 = datetime.now()
                resp = safe_request(current, timeout=10)
                ms = int((datetime.now() - t0).total_seconds() * 1000)
                res = analyze_page(current, "", html=resp.text if resp.status_code == 200 else None,
                                   status_code=resp.status_code, ms=ms)
                status = resp.status_code
            except Exception:
                res = {"score": 0, "title": "", "meta": "", "h1": "", "words": 0, "raw": []}
                status = 0
            issues = [c["name"] for c in res.get("raw", []) if not c["ok"]]
            redirects = ""
            if resp is not None and resp.history:
                redirects = " -> ".join([str(r.status_code) for r in resp.history] + [str(resp.status_code)]) +                             " | " + " -> ".join([r.url for r in resp.history] + [resp.url])
            content_hash = ""
            if resp is not None and resp.status_code == 200:
                psoup2 = BeautifulSoup(resp.text, "html.parser")
                for t in psoup2(["script", "style", "noscript"]):
                    t.decompose()
                content_hash = hashlib.md5(" ".join(psoup2.get_text().split()).encode()).hexdigest()
            with get_db() as db:
                db.execute(
                    "INSERT INTO seopages (run_id, url, http_status, title, meta_len, h1, words, score, issues, redirects, content_hash, crawled_at) "
                    "VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                    (run_id, current, status, res.get("title", "")[:200], len(res.get("meta", "")),
                     res.get("h1", "")[:200], res.get("words", 0), res["score"],
                     "; ".join(issues[:8]), redirects[:300], content_hash, now_iso()),
                )
            if resp is not None and resp.status_code < 400:
                total_score += res["score"]
                pages_saved += 1
                try:
                    psoup = BeautifulSoup(resp.text, "html.parser")
                    for a in psoup.find_all("a", href=True):
                        href = urllib.parse.urljoin(current, a["href"].split("#")[0])
                        ph = urlparse(href)
                        if ph.netloc == host and ph.scheme.startswith("http") and href not in seen:
                            queue.append(href)
                except Exception:
                    pass
            CRAWL_STATE["done"] = len(seen)
            time.sleep(0.4)
        avg = round(total_score / pages_saved) if pages_saved else 0
        # sitemap-validering: tjek foerste 50 sitemap-URLs for 404/fejl
        sitemap_broken = []
        sitemap_missing = 0
        if sitemap_ok:
            try:
                sm_urls = []
                r3 = safe_request(sitemap_url, timeout=10)
                for loc in BeautifulSoup(r3.text, "html.parser").find_all("loc"):
                    sm_urls.append(loc.get_text(strip=True))
                for su in sm_urls[:50]:
                    try:
                        rr = safe_request(su, timeout=8)
                        if rr.status_code >= 400:
                            sitemap_broken.append(f"{su} ({rr.status_code})")
                    except Exception:
                        sitemap_broken.append(f"{su} (timeout)")
                    time.sleep(0.2)
            except Exception:
                pass
        with get_db() as db:
            db.execute("UPDATE crawl_runs SET pages=?, avg_score=?, finished_at=?, sitemap_broken=?, sitemap_missing=? WHERE id=?",
                       (pages_saved, avg, now_iso(), "; ".join(sitemap_broken[:10]) if sitemap_broken else "",
                        max(sitemap_count - pages_saved, 0) if sitemap_ok else 0, run_id))
            db.execute("INSERT INTO health_history (host, avg_score, pages, run_id, checked_at) VALUES (?,?,?,?,?)",
                       (host, avg, pages_saved, run_id, now_iso()))
            if sitemap_broken:
                add_alarm(db, "sitemap", f"{len(sitemap_broken)} sitemap-URLs fejler (foerste 50 tjekket)", "advarsel")
        CRAWL_STATE.update({"running": False, "avg": avg})
        return {"ok": True, "pages": pages_saved, "avg_score": avg, "robots_ok": robots_ok,
                "sitemap_ok": sitemap_ok, "sitemap_urls": sitemap_count}
    except Exception as e:
        CRAWL_STATE.update({"running": False, "error": str(e)[:200]})
        return {"ok": False, "error": str(e)[:200]}

def discover_competitors_sync(keyword: str):
    try:
        query = urllib.parse.quote_plus(keyword)
        response = safe_request(f"https://html.duckduckgo.com/html/?q={query}", timeout=10)
        soup = BeautifulSoup(response.text, "html.parser")
        found = []
        for anchor in soup.select("a.result__url[href]"):
            href = anchor.get("href", "")
            if "uddg=" in href:
                parsed = urllib.parse.parse_qs(urllib.parse.urlparse(href).query)
                href = parsed.get("uddg", [href])[0]
            if href.startswith("http") and "duckduckgo.com" not in href:
                domain = urlparse(href).netloc
                if domain and domain not in [item[0] for item in found]:
                    found.append((domain, href))
                if len(found) >= 5:
                    break
        if not found:
            raise RuntimeError("Ingen resultater (DuckDuckGo blokerede muligvis - proev igen eller brug Juno/SerpAPI)")
        with get_db() as db:
            for domain, url in found:
                info = crawl_competitor(url)
                db.execute(
                    "INSERT INTO competitors (name, url, crawled_info, found_at) VALUES (?,?,?,?)",
                    (domain, url, info, now_iso()),
                )
        return {"ok": True, "count": len(found), "error": None}
    except Exception as e:
        err = str(e)[:200]
        with get_db() as db:
            add_alarm(db, "serp-scan", f"Konkurrent-scan '{keyword}' fejlede: {err}", "advarsel")
        return {"ok": False, "count": 0, "error": err}

def crawl_competitor(url: str):
    try:
        url = normalize_url(url)
        response = safe_request(url)
        if response.status_code != 200:
            return f"HTTP-fejl {response.status_code}"
        soup = BeautifulSoup(response.text, "html.parser")
        title = soup.title.get_text(strip=True) if soup.title else "Ingen titel"
        meta = soup.find("meta", attrs={"name": "description"})
        description = meta.get("content", "").strip() if meta else "Ingen beskrivelse"
        h1 = soup.find("h1")
        h1_text = h1.get_text(strip=True) if h1 else "Ingen H1"
        return f"Titel: {title[:80]} | H1: {h1_text[:60]} | Beskrivelse: {description[:100]}"
    except Exception as e:
        return f"Fejl: {e}"

def check_links_sync(url: str):
    try:
        url = normalize_url(url)
        response = safe_request(url)
        soup = BeautifulSoup(response.text, "html.parser")
        links = [a["href"] for a in soup.find_all("a", href=True)]
        external = [l for l in links if l.startswith("http")]
        checked = 0
        broken = 0
        broken_list = []
        for link in external[:LINKCHECK_LIMIT]:
            checked += 1
            try:
                result = safe_request(link, timeout=5)
                if result.status_code >= 400:
                    broken += 1
                    broken_list.append(f"{link} ({result.status_code})")
            except Exception:
                broken += 1
                broken_list.append(f"{link} (timeout)")
        result_text = (
            f"Fandt {len(links)} links. Eksterne: {len(external)}. "
            f"Tjekkede: {checked}. Broedte/muligt fejlende: {broken}."
        )
        if broken:
            result_text += " | " + "; ".join(broken_list[:5])
        return {"ok": True, "text": result_text, "broken": broken, "url": url, "error": None}
    except Exception as e:
        return {"ok": False, "text": f"Fejl: {e}", "broken": 0, "url": url, "error": str(e)[:200]}
