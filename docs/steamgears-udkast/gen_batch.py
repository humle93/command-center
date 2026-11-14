"""Batch-generering af Steamgears-motiver via OpenRouter.

Prompterne læses fra gemini_prompter.py (SERIES, CLASSICS, PUNK + STYLE), så PDF og billeder altid matcher.

Brug:
  python3 gen_batch.py <ud-mappe> D1 D2 C1 ...            # koder fra PDF'en
  python3 gen_batch.py <ud-mappe> R3 --ref aurora.jpg      # samme person som på referencebilledet
  Valg: --model <slug> (standard google/gemini-3-pro-image), --size 1K|2K|4K (standard 4K),
        --n <varianter pr. kode> (standard 1), --aspect 2:3
Nøglen sendes af miljøets proxy eller fra OPENROUTER_API_KEY. Stopper ved 402 (ingen kredit).
"""
import argparse, ast, base64, json, mimetypes, os, sys, time, urllib.error, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
API = "https://openrouter.ai/api/v1"
KEY = os.environ.get("OPENROUTER_API_KEY", "proxy-injected")


def load_prompts():
    tree = ast.parse(open(os.path.join(HERE, "gemini_prompter.py"), encoding="utf-8").read())
    vals = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name) and node.targets[0].id in ("STYLE", "SERIES", "CLASSICS", "PUNK"):
            vals[node.targets[0].id] = ast.literal_eval(node.value)
    prompts = {code: (title, prompt) for lst in ("SERIES", "CLASSICS", "PUNK") for code, title, _note, prompt in vals.get(lst, [])}
    return vals["STYLE"], prompts


def call(path, body=None, timeout=300):
    req = urllib.request.Request(API + path, data=json.dumps(body).encode() if body else None,
                                 headers={"Content-Type": "application/json", "Authorization": f"Bearer {KEY}",
                                          "X-Title": "Steamgears Prints"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out"); ap.add_argument("codes", nargs="+")
    ap.add_argument("--model", default="google/gemini-3-pro-image")
    ap.add_argument("--size", default="4K"); ap.add_argument("--aspect", default="2:3")
    ap.add_argument("--n", type=int, default=1); ap.add_argument("--ref")
    a = ap.parse_args()
    style, prompts = load_prompts()
    os.makedirs(a.out, exist_ok=True)
    credits = call("/credits")["data"]
    left = credits["total_credits"] - credits["total_usage"]
    print(f"OpenRouter-kredit tilbage: ${left:.2f}")
    if left <= 0:
        sys.exit("Ingen kredit på OpenRouter-kontoen. Sæt penge ind og kør igen.")
    ref_part = None
    if a.ref:
        mt = mimetypes.guess_type(a.ref)[0] or "image/jpeg"
        ref_part = {"type": "image_url", "image_url": {"url": f"data:{mt};base64,{base64.b64encode(open(a.ref, 'rb').read()).decode()}"}}
    total = 0.0
    for code in a.codes:
        code = code.upper()
        if code not in prompts:
            print(f"{code}: ukendt kode (findes ikke i gemini_prompter.py)"); continue
        title, prompt = prompts[code]
        text = f"{prompt}\n\n{style}"
        if ref_part:
            text = "Use the woman in the attached reference image as the same character: same face, hair, outfit and hat.\n\n" + text
        for i in range(1, a.n + 1):
            content = [{"type": "text", "text": text + (f"\n\nVariation {i}." if a.n > 1 else "")}]
            if ref_part:
                content.append(ref_part)
            body = {"model": a.model, "modalities": ["image", "text"], "messages": [{"role": "user", "content": content}],
                    "image_config": {"aspect_ratio": a.aspect, "image_size": a.size}}
            t0 = time.time()
            try:
                d = call("/chat/completions", body)
            except urllib.error.HTTPError as e:
                msg = e.read()[:300].decode(errors="replace")
                if e.code == 402:
                    sys.exit(f"Stoppet: ingen kredit tilbage (402). Brugt i denne kørsel: ${total:.3f}")
                print(f"{code}-{i}: fejl {e.code}: {msg}"); continue
            imgs = (d.get("choices") or [{}])[0].get("message", {}).get("images") or []
            if not imgs:
                print(f"{code}-{i}: intet billede: {json.dumps(d)[:300]}"); continue
            url = imgs[0]["image_url"]["url"]
            ext = "png" if url[:30].find("png") > 0 else "jpg"
            path = os.path.join(a.out, f"sg-{code.lower()}-{a.model.split('/')[-1]}-{i}.{ext}")
            open(path, "wb").write(base64.b64decode(url.split(",", 1)[1]))
            cost = float((d.get("usage") or {}).get("cost") or 0); total += cost
            print(f"{code}-{i}: {title} → {path} (${cost:.3f}, {time.time() - t0:.0f} s)")
    print(f"I alt brugt: ${total:.3f}")


if __name__ == "__main__":
    main()
