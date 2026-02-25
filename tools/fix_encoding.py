from __future__ import annotations
import re
from pathlib import Path

# Detecta mojibake típico + replacement char
BAD_RE = re.compile(r"(?:Ã.|Â.|â€|â€œ|â€|â€™|â€“|â€”|\uFFFD)")

def score(s: str) -> int:
    return len(BAD_RE.findall(s))

def trans(txt: str, enc: str) -> str:
    """Intenta revertir mojibake: txt (mal-decoded) -> bytes(enc) -> utf-8."""
    try:
        return txt.encode(enc, errors="strict").decode("utf-8", errors="strict")
    except Exception:
        return txt

def best_fix_line(line: str) -> str:
    cands = [line]

    # 1 y 2 rondas (arregla casos como mÃƒÂ­nimo -> mÃ­nimo -> mínimo)
    for enc in ("cp1252", "latin1"):
        c1 = trans(line, enc)
        c2 = trans(c1, enc)
        cands.extend([c1, c2])

    # combinaciones cruzadas
    cands.append(trans(trans(line, "cp1252"), "latin1"))
    cands.append(trans(trans(line, "latin1"), "cp1252"))

    best = min(set(cands), key=lambda s: (score(s), len(s)))
    return best if score(best) < score(line) else line

def patch_lines(path: Path, text: str) -> str:
    lines = text.splitlines(True)
    out = []
    replaced_regex = False

    for line in lines:
        # Header de main.py
        if path.name.lower() == "main.py" and line.lstrip().startswith("# app/main.py"):
            out.append("# app/main.py  STUDIO_MVP V2 (Studio puro)\n")
            continue

        # Línea del re.sub(...) en main.py (con escapes unicode ASCII)
        if (path.name.lower() == "main.py"
            and (not replaced_regex)
            and "t = re.sub(" in line
            and "strip().lower()" in line
            and 're.sub(r"[^a-zA-Z0-9' in line):
            indent = re.match(r"^(\s*)", line).group(1)
            out.append(
                indent
                + 't = re.sub("[^a-zA-Z0-9\\u00e1\\u00e9\\u00ed\\u00f3\\u00fa\\u00fc\\u00f1\\u00c1\\u00c9\\u00cd\\u00d3\\u00da\\u00dc\\u00d1 ]+", "", t).strip().lower()\n'
            )
            replaced_regex = True
            continue

        out.append(line)

    text = "".join(out)

    # Normaliza comentarios "marcadores" en v02_core.py a ASCII
    if path.name.lower() == "v02_core.py":
        text = re.sub(
            r'(?m)^(\s*)MARK_A_TILDE\s*=\s*"(\\u00C3)".*$',
            r'\1MARK_A_TILDE = "\2"  # U+00C3 marker',
            text, count=1
        )
        text = re.sub(
            r'(?m)^(\s*)MARK_A_CIRC\s*=\s*"(\\u00C2)".*$',
            r'\1MARK_A_CIRC  = "\2"  # U+00C2 marker',
            text, count=1
        )
        text = re.sub(
            r'(?m)^(\s*)MARK_FLORIN\s*=\s*"(\\u0192)".*$',
            r'\1MARK_FLORIN  = "\2"  # U+0192 marker',
            text, count=1
        )
        text = re.sub(
            r'(?m)^(\s*)MARK_REPL\s*=\s*"(\\uFFFD)".*$',
            r'\1MARK_REPL    = "\2"  # U+FFFD replacement char',
            text, count=1
        )

    return text

def read_text_safely(p: Path) -> str:
    b = p.read_bytes()
    for enc in ("utf-8", "cp1252", "latin1"):
        try:
            return b.decode(enc)
        except UnicodeDecodeError:
            continue
    return b.decode("utf-8", errors="replace")

def process_file(p: Path) -> None:
    raw = read_text_safely(p).lstrip("\ufeff")
    s0 = score(raw)

    fixed = "".join(best_fix_line(line) for line in raw.splitlines(True))
    fixed = patch_lines(p, fixed)
    s1 = score(fixed)

    if fixed != raw:
        bak = p.with_suffix(p.suffix + ".bak")
        if not bak.exists():
            bak.write_text(raw, encoding="utf-8", newline="\n")
        p.write_text(fixed, encoding="utf-8", newline="\n")

    print(f"{p}: score {s0} -> {s1}; changed={fixed != raw}")

def main() -> None:
    files = sorted(Path("app").glob("*.py"))
    if not files:
        print("No encontré app/*.py")
        return
    for p in files:
        process_file(p)

if __name__ == "__main__":
    main()