"""Erzeugt Sources/KontivoCore/Resources/catalog.json aus dem Anbieterkatalog TPL in index.html.

Aufruf (im Ordner ios/KontivoCore):  python3 Scripts/make_catalog.py
Liest die Konstanten H_* und das Array TPL («Anbieterkatalog Schweiz / Deutschland») aus ../../index.html,
löst die Hinweis-Konstanten als Text auf und schreibt ein JSON-Array mit benannten Feldern:
name, country ("" = international), category (Name der Vorbelegung), label, web, notice, noticeUnit (m|w|d|k),
cancelTerm (""|p|m|q|h|y|a), cancelChannel (online|email|letter|registered|null), mandatory, hint.
Bereinigung (Inventar 2, F10): die Zahl 0 im Feld «Kündigungsweg» wird zu null.
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SRC = os.path.join(ROOT, "index.html")
OUT = os.path.join(HERE, "..", "Sources", "KontivoCore", "Resources", "catalog.json")

html = open(SRC, encoding="utf-8").read()
start = html.index("/* ---------- Anbieterkatalog Schweiz / Deutschland ---------- */")
end = html.index("var TPLI=", start)
block = html[start:end]

consts = {}
for m in re.finditer(r'var (H_[A-Z]+)="((?:[^"\\]|\\.)*)";', block):
    consts[m.group(1)] = json.loads('"' + m.group(2) + '"')

arr = block[block.index("var TPL=[") + len("var TPL="):]
arr = arr[:arr.rindex("];") + 1]
# JS-Array-Literal ist (mit den H_*-Namen) gültiges Python
rows = eval(arr, {"__builtins__": {}}, dict(consts))

CHANNEL = {"Online / Kundenkonto": "online", "E-Mail": "email", "Brief": "letter", "Einschreiben": "registered"}
out = []
for r in rows:
    name, cc, cat, lab, web, no, nu, tm, cf, md, hint = r
    if not isinstance(cf, str) or not cf:
        ch = None
    else:
        ch = CHANNEL[cf]
    out.append({
        "name": name, "country": cc or "", "category": cat, "label": lab, "web": web or "",
        "notice": int(no or 0), "noticeUnit": nu or "m", "cancelTerm": tm or "", "cancelChannel": ch,
        "mandatory": bool(md), "hint": hint or "",
    })

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8") as f:
    json.dump(out, f, ensure_ascii=False, indent=1)
    f.write("\n")
print("catalog.json:", len(out), "Einträge")
