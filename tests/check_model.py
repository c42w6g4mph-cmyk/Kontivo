"""Prüft Kontivo-Daten gegen docs/datenmodell.md: unbekannte Felder und falsche Typen.
Aufruf: python3 tests/check_model.py <Datei.json> [...]
Datei = Backup (kontivo-sicherung-….json), localStorage-Inhalt von «vertraege.v1» oder tests/cases_budget.json.
Ohne Datei: prüft die Testdaten im Ordner tests/. Exit-Code 0 = alles passt."""
import json, os, re, sys
R = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MD = open(os.path.join(R, "docs", "datenmodell.md"), encoding="utf-8").read()
SECT = {"contracts": "## 2 ", "incomes": "## 3 ", "vars": "## 4 ", "settings": "### 5.1 "}

def table(head):
    i = MD.index(head); j = MD.find("\n## ", i + 3); txt = MD[i:j if j > 0 else None]
    out = {}
    for line in txt.splitlines():
        if not line.startswith("| `"): continue
        # Spalte Typ darf «\|» enthalten
        cells = re.split(r"(?<!\\)\|", line.strip().strip("|")); cells = [c.strip().replace("\\|", "|") for c in cells]
        names = re.findall(r"`([A-Za-z]+)`", cells[0]); typ = cells[1]; req = len(cells) > 3 and cells[2] == "ja"
        for n in names: out[n] = (typ, req)
    return out
SPEC = {k: table(v) for k, v in SECT.items()}
DATE = re.compile(r"^\d{4}-\d\d-\d\d$")

def ok_type(v, typ):
    alts = []
    for t in typ.split("|"):
        t = t.strip()
        if t.startswith("Text[]"): alts.append(isinstance(v, list) and all(isinstance(x, str) for x in v))
        elif t.endswith("[]"): alts.append(isinstance(v, list))
        elif t.startswith("{"): alts.append(isinstance(v, dict))
        elif t == "Text": alts.append(isinstance(v, str))
        elif t == "Zahl": alts.append(isinstance(v, (int, float)) and not isinstance(v, bool))
        elif t == "Bool": alts.append(isinstance(v, bool))
        elif t == "`true`": alts.append(v is True)
        elif t == '`""`': alts.append(v == "")
        elif t == "Datum": alts.append(isinstance(v, str) and (v == "" or bool(DATE.match(v))))
        else: alts.append(True)
    return any(alts)

def check(data, name):
    err = []
    if "vertraege.v1" in data and isinstance(data["vertraege.v1"], str): data = json.loads(data["vertraege.v1"])
    for part in ("contracts", "incomes", "vars"):
        for k, c in (data.get(part) or {}).items():
            for f, v in c.items():
                if f not in SPEC[part]: err.append("%s.%s: Feld «%s» nicht beschrieben" % (part, k, f)); continue
                if not ok_type(v, SPEC[part][f][0]): err.append("%s.%s.%s: Typ %r passt nicht zu «%s»" % (part, k, f, v, SPEC[part][f][0]))
    for f, v in (data.get("settings") or {}).items():
        if f not in SPEC["settings"]: err.append("settings: Feld «%s» nicht beschrieben" % f)
        elif not ok_type(v, SPEC["settings"][f][0]): err.append("settings.%s: Typ passt nicht zu «%s»" % (f, SPEC["settings"][f][0]))
    print("%s: %s" % (name, "ok" if not err else "%d Abweichungen" % len(err)))
    for e in err[:40]: print("  " + e)
    return not err

files = sys.argv[1:] or [os.path.join(R, "tests", "cases_budget.json")]
good = all([check(json.load(open(f, encoding="utf-8")), os.path.basename(f)) for f in files])
print("Felder beschrieben:", {k: len(v) for k, v in SPEC.items()})
sys.exit(0 if good else 1)
