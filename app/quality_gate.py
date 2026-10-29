from bs4 import BeautifulSoup

def validate_article(html_content: str, focus_keyword: str, min_words: int = 600, min_internal_links: int = 3, domain: str = "steamgears.eu") -> dict:
    soup = BeautifulSoup(html_content or "", "html.parser")
    text = soup.get_text(" ", strip=True)
    words = text.split()
    word_count = len(words)
    
    kw = (focus_keyword or "").strip().lower()
    first_100 = " ".join(words[:100]).lower()
    kw_in_intro = bool(kw and kw in first_100)
    
    h2_tags = soup.find_all("h2")
    h2_count = len(h2_tags)
    kw_in_h2 = any(kw in h.get_text(" ", strip=True).lower() for h in h2_tags) if kw else True
    
    links = [a.get("href", "") for a in soup.find_all("a", href=True)]
    internal_links = [l for l in links if l.startswith("/") or domain in l]
    
    checks = {
        "word_count_ok": word_count >= min_words,
        "keyword_in_intro": kw_in_intro,
        "h2_structure_ok": h2_count >= 2,
        "keyword_in_h2": kw_in_h2,
        "internal_links_ok": len(internal_links) >= min_internal_links,
    }
    passed = all(checks.values())
    return {
        "passed": passed,
        "word_count": word_count,
        "h2_count": h2_count,
        "internal_links": len(internal_links),
        "checks": checks
    }
