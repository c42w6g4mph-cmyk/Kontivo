"""Mehrere Dateien zusammen (25.10.2026): gleiche Buchungen in verschiedenen Formaten ergeben keine doppelten Vorschläge, Einnahmen bleiben erkannt,
Dateien mit unterschiedlichem Ende machen Einnahmen nicht «veraltet». Musterdateien in tests/bank/muster (erfundene Daten).
Aufruf im Repo-Ordner:  python3 -m http.server 8765 &  python3 tests/bank/multi2.py"""
import base64, os, sys
from playwright.sync_api import sync_playwright
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "samples")
URL = os.environ.get("KONTIVO_URL", "http://localhost:8765/index.html")
M = lambda f: os.path.join(os.path.dirname(D), "muster", f)
# 5. Feld False = doppelte Namen erlaubt (CHF- und EUR-Konto mit je eigenem Netflix/Spotify sind zwei Verträge)
CASES = [
  ("Sparkasse + N26 (gleiche Buchungen)", [M("sparkasse.csv"), M("n26.csv")], ["Musterhandel"], None),
  ("Format 1 + Format 3 (gleiche Buchungen)", [M("format1.csv"), M("format3.csv")], ["Musterfirma", "Versicherung Muster"], None),
  ("alle Musterdateien", [M(f) for f in ["sparkasse.csv", "n26.csv", "dkb.csv", "format1.csv", "format2.csv", "format3.csv"]], ["Musterhandel", "Musterfirma"], None),
  ("Muster (Ende 12/2026) + CH-Konto (Ende 09/2026)", [M("sparkasse.csv"), os.path.join(D, "ch_zkb.csv")], ["Musterhandel", "Muster Pharma"], None, False),
]
JS = """L=>{var K=window.KontivoBank(),rs=L.map(function(b){var s=atob(b),u=new Uint8Array(s.length);for(var i=0;i<s.length;i++)u[i]=s.charCodeAt(i);return K.read(u.buffer);});
  var r=K.merge(rs),f=K.findInc(r),c=K.find(r,[]),nm=c.sugg.map(function(s){return s.name;});
  return {n:r.tx.length,inc:(f.sugg||[]).map(function(s){return s.name;}),dup:nm.filter(function(x,i){return nm.indexOf(x)!==i;})};}"""
ok = True
with sync_playwright() as p:
    pg = p.chromium.launch().new_page(); pg.add_init_script("window.__KONTIVO_TODAY='2026-10-25';"); pg.goto(URL); pg.wait_for_timeout(1500)
    for c in CASES:
        name, files, want, n = c[:4]; nodup = c[4] if len(c) > 4 else True
        r = pg.evaluate(JS, [base64.b64encode(open(f, "rb").read()).decode() for f in files])
        good = all(any(w in x for x in r["inc"]) for w in want) and (n is None or r["n"] == n) and (not nodup or not r["dup"])
        ok &= good; print("✓" if good else "✗", name, r["n"], r["inc"], ("doppelt: %s" % r["dup"]) if r["dup"] else "")
print("Alles gut" if ok else "FEHLER"); sys.exit(0 if ok else 1)
