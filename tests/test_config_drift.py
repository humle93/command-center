"""Config-drift: hver miljøvariabel koden læser skal stå i .env.example.

Baggrunden er PSI_API_KEY: den blev læst i app/main.py og dokumenteret i README, men
manglede i .env.example — så en frisk installation fik ingen PageSpeed-nøgle at udfylde.
Testen læser koden med ast (ikke regex), så os.environ.get("X"), os.getenv("X") og
os.environ["X"] alle tæller, og fejler hvis bare én nøgle mangler i .env.example.

Usage: python3 tests/test_config_drift.py   (fra repo-roden, ingen dependencies)
"""
import ast
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Standardvariable som systemet/CI saetter selv — de hoerer ikke i .env.example.
IGNORED = {"PATH", "HOME", "PYTHONPATH", "TZ", "LANG", "USER", "PWD", "CI"}

FAILED = []


def check(name, ok, detail=None):
    print(("PASS " if ok else "FAIL ") + name + ("" if ok or detail is None else f" -> {detail}"))
    if not ok:
        FAILED.append(name)


def read_env_keys(path):
    """Nøgler i en .env-fil: linjer med KEY=verdi, kommentarer og tomme linjer springes over."""
    keys = set()
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            keys.add(line.split("=", 1)[0].strip())
    return keys


def code_env_keys(path):
    """Alle miljøvariabel-navne koden læser, fundet via ast."""
    with open(path, encoding="utf-8") as fh:
        tree = ast.parse(fh.read(), filename=path)
    found = set()
    for node in ast.walk(tree):
        # os.environ.get("X"), os.getenv("X") — men ikke dict.get("X") og andre get-kald
        if isinstance(node, ast.Call) and node.args:
            fn, first = node.func, node.args[0]
            if not (isinstance(first, ast.Constant) and isinstance(first.value, str)):
                continue
            if (isinstance(fn, ast.Attribute) and fn.attr == "get"
                    and isinstance(fn.value, ast.Attribute) and fn.value.attr == "environ"):
                found.add(first.value)
            elif isinstance(fn, ast.Attribute) and fn.attr == "getenv":
                found.add(first.value)
            elif isinstance(fn, ast.Name) and fn.id == "getenv":  # from os import getenv
                found.add(first.value)
        # os.environ["X"]
        elif isinstance(node, ast.Subscript) and isinstance(node.slice, ast.Constant):
            target = node.value
            if (isinstance(target, ast.Attribute) and target.attr == "environ"
                    and isinstance(node.slice.value, str)):
                found.add(node.slice.value)
    return found


py_files = []
for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, "app")):
    dirnames[:] = [d for d in dirnames if d not in ("data", "static", "__pycache__")]
    py_files += [os.path.join(dirpath, f) for f in filenames if f.endswith(".py")]

used = set()
for path in sorted(py_files):
    used |= code_env_keys(path)
used -= IGNORED

example_path = os.path.join(ROOT, ".env.example")
documented = read_env_keys(example_path)

check("koden læser mindst 15 miljøvariable (sanity)", len(used) >= 15, sorted(used))
missing = sorted(used - documented)
check("hver variabel koden læser findes i .env.example", not missing, "mangler: " + ", ".join(missing))

# Modsat retning er ikke en fejl (en variabel kan vaere dokumenteret foer den bruges),
# men den er vaerd at se i loggen: doed dokumentation bliver sjaeldent ryddet op.
unused = sorted(documented - used)
if unused:
    print("NOTE .env.example dokumenterer variabler koden ikke læser endnu: " + ", ".join(unused))

# PSI_API_KEY er selve anledningen til testen: den skal baade dokumenteres og kunne udfyldes.
check("PSI_API_KEY staar i .env.example", "PSI_API_KEY" in documented, sorted(documented))

print("ALL PASS" if not FAILED else f"{len(FAILED)} FAILED")
sys.exit(1 if FAILED else 0)
