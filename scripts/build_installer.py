#!/usr/bin/env python3
"""Bygger install.sh ud fra scripts/installer.template.sh.

install.sh er den fil, brugerne kører for at installere Command Center. Den
indeholder både shell-logikken og fulde kopier af de filer, den skriver til
disken. Kopierne bliver derfor aldrig redigeret i hånden: de kommer fra
repoet, og install.sh genereres herfra.

Rediger i stedet:
  - shell-logik  -> scripts/installer.template.sh
  - filer        -> selve filen i repoet (fx app/main.py, README.md)

Kør derefter:
    python3 scripts/build_installer.py            # skriv install.sh
    python3 scripts/build_installer.py --check    # fejl hvis install.sh er forældet (CI)

I templaten står hver indlejret fil som en markør mellem heredoc-start og
heredoc-slut:

    cat << 'EOF_MAIN' > "$PROJECT_DIR/app/main.py"
    #@@embed:app/main.py@@
    EOF_MAIN

Heredoc-tag og sti står i templaten, så det er synligt i shell-flowet hvilke
filer der skrives hvornår; kun indholdet bliver erstattet.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / "scripts" / "installer.template.sh"
OUTPUT = ROOT / "install.sh"

MARKER = re.compile(r"^#@@embed:(?P<path>[^@]+)@@$")
HEREDOC = re.compile(r"^cat << '(?P<tag>\w+)' > \"\$PROJECT_DIR/(?P<path>[^\"]+)\"$")


class BuildError(Exception):
    """Templaten eller en indlejret fil er ikke som forventet."""


def build() -> str:
    """Returnér det færdige install.sh som tekst."""
    if not TEMPLATE.is_file():
        raise BuildError(f"mangler {TEMPLATE.relative_to(ROOT)}")

    template = TEMPLATE.read_text(encoding="utf-8").splitlines()
    out: list[str] = []
    embedded: list[str] = []
    i = 0

    while i < len(template):
        line = template[i]
        heredoc = HEREDOC.match(line)
        marker = MARKER.match(line)

        if heredoc:
            # Næste linje skal være markøren for præcis den samme fil.
            tag, rel = heredoc.group("tag"), heredoc.group("path")
            body = template[i + 1] if i + 1 < len(template) else ""
            body_marker = MARKER.match(body)
            if not body_marker:
                raise BuildError(
                    f"{TEMPLATE.name}:{i + 1}: heredoc '{tag}' mangler en "
                    f"#@@embed:{rel}@@-markør som første linje i kroppen"
                )
            if body_marker.group("path") != rel:
                raise BuildError(
                    f"{TEMPLATE.name}:{i + 2}: markøren peger på "
                    f"'{body_marker.group('path')}', men heredoc'en skriver '{rel}'"
                )

            source = ROOT / rel
            if not source.is_file():
                raise BuildError(f"{TEMPLATE.name}:{i + 2}: filen '{rel}' findes ikke i repoet")

            out.append(line)
            out.extend(source.read_text(encoding="utf-8").splitlines())
            out.append(tag)
            embedded.append(rel)
            i += 3
            continue

        if marker:
            raise BuildError(
                f"{TEMPLATE.name}:{i + 1}: markøren '{line}' står ikke lige efter "
                f"en 'cat << ... > \"$PROJECT_DIR/{marker.group('path')}\"'-linje"
            )

        out.append(line)
        i += 1

    if not embedded:
        raise BuildError(f"{TEMPLATE.name}: ingen indlejrede filer fundet")

    return "\n".join(out) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--check",
        action="store_true",
        help="skriv ikke, men fejl hvis install.sh ikke matcher templaten og repoet",
    )
    args = parser.parse_args()

    try:
        generated = build()
    except BuildError as exc:
        print(f"✗ {exc}", file=sys.stderr)
        return 1

    current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.is_file() else None

    if args.check:
        if current == generated:
            print(f"✓ install.sh er opdateret ({len(generated.splitlines())} linjer)")
            return 0
        print(
            "✗ install.sh er forældet — kør: python3 scripts/build_installer.py",
            file=sys.stderr,
        )
        if current is not None:
            import difflib

            diff = difflib.unified_diff(
                current.splitlines(), generated.splitlines(),
                "install.sh (i repoet)", "install.sh (genereret)", n=1, lineterm="",
            )
            for line in list(diff)[:40]:
                print(line, file=sys.stderr)
        return 1

    if current == generated:
        print(f"✓ install.sh var allerede opdateret ({len(generated.splitlines())} linjer)")
        return 0

    OUTPUT.write_text(generated, encoding="utf-8")
    print(f"✓ skrev install.sh ({len(generated.splitlines())} linjer)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
