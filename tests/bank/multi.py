"""Mehrere Dateien auf einmal: gleiche Datei doppelt (überlappender Export) zählt nur einmal; Konto + Kreditkarte ergänzen sich.
Aufruf im Repo-Ordner:  python3 -m http.server 8765 &  python3 tests/bank/multi.py"""
import base64, json, os, sys
from playwright.sync_api import sync_playwright
D = os.path.dirname(os.path.abspath(__file__)); URL = os.environ.get("KONTIVO_URL", "http://localhost:8765/index.html")
def b64(p): return base64.b64encode(open(os.path.join(D, p), "rb").read()).decode()
JS = """(fs)=>{var B=window.KontivoBank(),rs=fs.map(function(b){var bin=atob(b),u=new Uint8Array(bin.length);for(var i=0;i<bin.length;i++)u[i]=bin.charCodeAt(i);return B.read(u.buffer);});
  var r=B.merge(rs),f=B.find(r,[]);return {n:r.tx.length,s:f.sugg.map(function(s){return [s.name,s.cycle,s.amount,s.n];})};}"""
fails = 0
with sync_playwright() as p:
    b = p.chromium.launch(); ctx = b.new_context(); ctx.add_init_script("window.__KONTIVO_TODAY='2026-10-08';"); pg = ctx.new_page(); pg.goto(URL)
    st = {"settings": {"home": "CHF", "onboarded": 9, "holders": ["Max"], "rateTs": 9999999999999}, "contracts": {}, "incomes": {}}
    pg.evaluate("s=>localStorage.setItem('vertraege.v1',s)", json.dumps(st)); pg.reload(); pg.wait_for_timeout(400)
    one = pg.evaluate(JS, [b64("samples/ch_postfinance.csv")])
    two = pg.evaluate(JS, [b64("samples/ch_postfinance.csv"), b64("samples/ch_postfinance.csv")])
    ok = one == two; print(("✓" if ok else "✗"), "gleiche Datei doppelt = einmal", "" if ok else (one["n"], two["n"])); fails += not ok
    acc = pg.evaluate(JS, [b64("real/de/de_sparkasse_camt_v2.csv")]); card = pg.evaluate(JS, [b64("real/de/de_sparkasse_kreditkarte.csv")])
    both = pg.evaluate(JS, [b64("real/de/de_sparkasse_camt_v2.csv"), b64("real/de/de_sparkasse_kreditkarte.csv")])
    names = lambda r: sorted(x[0] for x in r["s"])
    ok = both["n"] == acc["n"] + card["n"] and set(names(acc)) | set(names(card)) == set(names(both))
    print(("✓" if ok else "✗"), "Konto + Kreditkarte ergänzen sich", "" if ok else (names(acc), names(card), names(both))); fails += not ok
    b.close()
print("Alles gut" if not fails else f"{fails} Fehler"); sys.exit(1 if fails else 0)
