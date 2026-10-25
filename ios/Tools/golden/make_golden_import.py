"""Erzeugt golden_import.json: Web-Backup mit Grenzwerten, so wie die Web-App es beim Einspielen bereinigt (sanitizeImport, Stand
Bereinigung E/Gegenprüfung: einmalige Einnahmen, rgb()-Logohintergrund, Datei-IDs, Kategorien ohne Namen, Zyklus, Beträge …).
Vergleich in WebImportSanitizeTests.swift (Swift WebImport.importObject mit demselben Backup).
Aufruf:  cd <main-Repo> && python3 -m http.server 8765 &   KONTIVO_URL=http://localhost:8765/index.html WEB=<main-Repo> python3 ios/Tools/golden/make_golden_import.py"""
import json, os
from playwright.sync_api import sync_playwright
D = os.path.dirname(os.path.abspath(__file__))
WEB = os.environ["WEB"]
RES = os.path.join(D, "..", "..", "KontivoCore", "Tests", "KontivoCoreTests", "Resources")  # Prüffälle im Swift-Paket
URL = os.environ.get("KONTIVO_URL", "http://localhost:8765/index.html")
HTML = open(os.path.join(WEB, "index.html"), encoding="utf-8").read()
A = "function sanitizeImport(o){"
assert HTML.count(A) == 1
PATCHED = HTML.replace(A, "window.__san=function(o){return sanitizeImport(JSON.parse(JSON.stringify(o)));};" + A, 1)
C = lambda **k: dict({"partner": "", "label": "x", "cat": "Sonstiges", "amount": 10, "cur": "CHF", "cycle": 1, "due": "2026-11-01", "status": "active", "holders": ["Sinan"]}, **k)
BACKUP = {"app": "vertraege", "version": 2,
  "settings": {"home": "CHF", "holders": ["Sinan", "", 7, "Lara"], "bankIgn": ["a|1", 5], "bankAlias": {"k1": {"n": "  Muster AG ", "c": "Wohnen"}, "k2": {"n": ""}, "k3": "x"},
               "catList": [{"n": "Wohnen", "c": "#ABC", "k": "Wohnen", "i": "Wohnen"}, {"n": "", "c": "#fff"}, {"c": "#000"}, {"n": "Hobby", "c": "red", "i": "tag"}, "x"],
               "avatars": {"Sinan": "0123456789abcdef0123456789abcdef", "Lara": "nope"}},
  "contracts": {
    "c1": C(label="Zyklus 5", cycle=5, amount="12.345"),
    "c2": C(label="Zyklus 0", cycle=0, amount=-3.2),
    "c3": C(label="Betrag riesig", amount=5e9, cur="XYZ"),
    "c4": C(label="Logo rgb", logoId="logo_1:ab", logoBg="rgb(10,20,30)"),
    "c5": C(label="Logo kaputt", logoId="../../etc", logoBg="javascript:x"),
    "c6": C(label="Logo leer", logoId="", logoBg="#fff"),
    "c7": C(label="Dokumente", docs=[{"id": "doc_1", "name": "a.pdf", "type": "application/pdf"}, {"id": "bad id!", "name": "b"}, {"id": "", "name": "c"}, "x"]),
    "c8": C(label="Frist", notice="3", renew=1300, noticeU="m", cancTerm="m", prices=[{"from": "2026-12-01", "amount": "15"}, {"from": 5, "amount": 1}, {"amount": 2}],
            extras=[{"date": "2026-03-01", "amount": "-4", "note": 7}, {"date": "x", "amount": "a"}]),
    "c9": C(label="Split", holders=["Sinan", "Lara"], split={"Sinan": 70, "Lara": "30", "Mia": 200}),
    "bad key!": C(label="Schlüssel neu"),
    "c10": C(label="Farbe", color="url(x)"),
  },
  "incomes": {
    "i1": {"name": "Bonus einmalig", "label": "Bonus", "cat": "Bonus", "amount": 1000, "cur": "CHF", "cycle": 0, "due": "2026-12-20", "holders": ["Sinan"], "status": "active"},
    "i2": {"name": "Lohn", "label": "Lohn", "cat": "Lohn", "amount": "5000.555", "cur": "EUR", "cycle": 7, "due": "2026-11-25", "holders": ["Lara"], "status": "active", "logoId": "i_1", "logoBg": "rgb(1,2,3)"},
  },
  "vars": {
    "v1": {"label": "Essen", "ic": "essen", "amount": 900, "cur": "CHF", "holders": ["Sinan"], "start": "", "end": "", "t": 1, "logoId": "ok_1", "logoBg": "rgb(255,255,255)"},
    "v2": {"label": "x" * 80, "ic": "??", "amount": 2e7, "cur": "USD", "holders": "Sinan", "start": "2026-02-30", "end": "2026-12-31", "logoId": "bad id", "logoBg": "rgb(1, 2, 3)"},
  },
  "files": {"doc_1": "data:application/pdf;base64,AAAA", "bad key": "x", "__proto__": "y"}}
with sync_playwright() as p:
    b = p.chromium.launch(); ctx = b.new_context(service_workers="block")
    ctx.route("**/index.html", lambda r: r.fulfill(status=200, content_type="text/html; charset=utf-8", body=PATCHED))
    pg = ctx.new_page(); pg.goto(URL); pg.wait_for_timeout(500)
    out = pg.evaluate("o=>window.__san(o)", BACKUP); b.close()
OUT = os.path.join(RES, "golden_import.json")
json.dump({"generated_from": "Kontivo Web-App sanitizeImport (make_golden_import.py)", "backup": BACKUP, "sanitized": out},
          open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("golden_import.json:", len(out["contracts"]), "Verträge,", len(out["incomes"]), "Einnahmen,", len(out["vars"]), "variable Kosten")
