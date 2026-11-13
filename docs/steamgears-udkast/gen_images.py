"""Genererer realistiske plakatudkast via OpenRouter (billedmodel).

Brug: python3 gen_images.py <ud-mappe> <navn> <antal> [model]
Prompten læses fra stdin. Nøglen sendes af miljøets proxy eller fra OPENROUTER_API_KEY.
"""
import base64, json, os, sys, urllib.error, urllib.request

out, name, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
model = sys.argv[4] if len(sys.argv) > 4 else "google/gemini-3.1-flash-image"
prompt = sys.stdin.read().strip()
STYLE = ("cinematic realistic digital painting, golden hour, warm brass and copper tones with teal shadows, "
         "volumetric light through clouds, highly detailed, sharp focus, portrait orientation, "
         "empty calm area in the bottom fifth for a title, no text, no letters, no logos, no watermark")
key = os.environ.get("OPENROUTER_API_KEY", "proxy-injected")
os.makedirs(out, exist_ok=True)
for i in range(1, n + 1):
    body = {"model": model, "modalities": ["image", "text"],
            "messages": [{"role": "user", "content": f"{prompt}\n\nStyle: {STYLE}. Variation {i}."}],
            "image_config": {"aspect_ratio": "3:4"}}
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}",
                                          "X-Title": "Steamgears Prints"})
    try:
        with urllib.request.urlopen(req, timeout=240) as r:
            d = json.load(r)
    except urllib.error.HTTPError as e:
        hint = " (ingen kredit på OpenRouter-kontoen)" if e.code == 402 else ""
        sys.exit(f"OpenRouter svarede {e.code}{hint}: {e.read()[:300].decode(errors='replace')}")
    if "error" in d:
        print("fejl", d["error"]); continue
    msg = d["choices"][0]["message"]
    imgs = msg.get("images") or []
    if not imgs:
        print("intet billede:", (msg.get("content") or "")[:200]); continue
    url = imgs[0]["image_url"]["url"]
    ext = "png" if "image/png" in url[:40] else "jpg"
    path = os.path.join(out, f"{name}-{i}.{ext}")
    with open(path, "wb") as f:
        f.write(base64.b64decode(url.split(",", 1)[1]))
    print("gemt", path, d.get("usage", {}).get("cost"))
