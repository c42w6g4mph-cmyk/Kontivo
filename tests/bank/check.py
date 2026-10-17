"""Prüft den Kontoauszug-Import gegen die Musterdateien (tests/bank/samples, erzeugt mit make_samples.py).
Aufruf im Repo-Ordner:  python3 -m http.server 8765 &  python3 tests/bank/check.py   (-v zeigt alle Vorschläge)"""
import base64, json, os, sys
from playwright.sync_api import sync_playwright
D = os.path.dirname(os.path.abspath(__file__)); S = os.path.join(D, "samples")
URL = os.environ.get("KONTIVO_URL", "http://localhost:8765/index.html")
V = "-v" in sys.argv
# Erwartet: Vertragspartner → (Turnus in Monaten, aktueller Betrag, Preisänderung ab JJJJ-MM oder None)
CH = {"Immo Seeblick": (1, 1850, None), "CSS": (1, 412.30, "2026-01"), "Swisscom": (1, 79.00, None), "Netflix": (1, 18.90, None),
      "Spotify": (1, 13.95, None), "Energie Kreuzlingen": (3, 180.50, None), "Steuerverwaltung": (1, 600, None),
      "Rundfunkgebühr": (12, 335, None), "Die Mobiliar": (12, 486.70, None)}
DE = {"Wohnbau Konstanz": (1, 1180, None), "Telekom": (1, 39.95, None), "Stadtwerke Konstanz": (1, 102, "2026-03"), "Netflix": (1, 13.99, None),
      "Spotify": (1, 11.99, "2026-07"), "Rundfunkgebühr": (3, 55.08, None), "McFit": (1, 24.90, None), "Deutschlandticket": (1, 63, "2026-01"),
      "Allianz": (12, 89.40, None)}
DE90 = {"Wohnbau Konstanz": (1, 1180, None), "Telekom": (1, 39.95, None), "Stadtwerke Konstanz": (1, 102, None), "Netflix": (1, 13.99, None),
        "Spotify": (1, 11.99, None), "Rundfunkgebühr": (12, 55.08, None), "McFit": (1, 24.90, None), "Deutschlandticket": (1, 63, None)}
JS = """(b64)=>{var bin=atob(b64),u=new Uint8Array(bin.length);for(var i=0;i<bin.length;i++)u[i]=bin.charCodeAt(i);
  var B=window.KontivoBank(),r=B.read(u.buffer);if(!r)return null;var f=B.find(r,[]);
  return {fmt:f.fmt,bank:f.bank,n:f.n,from:f.from,to:f.to,known:f.known.map(function(s){return s.name;}),
    sugg:f.sugg.map(function(s){return {name:s.name,cycle:s.cycle,amount:s.amount,conf:s.conf,cat:s.cat,change:s.change,match:s.match,n:s.n,due:s.due};})};}"""
fails = 0
with sync_playwright() as p:
    b = p.chromium.launch(); ctx = b.new_context(); ctx.add_init_script("window.__KONTIVO_TODAY='2026-10-08';")
    pg = ctx.new_page(); pg.goto(URL)
    st = {"settings": {"home": "CHF", "onboarded": 9, "holders": ["Sinan"], "rateTs": 9999999999999}, "contracts": {}, "incomes": {}}
    pg.evaluate("s=>localStorage.setItem('vertraege.v1',s)", json.dumps(st)); pg.reload(); pg.wait_for_timeout(400)
    for fn in sorted(os.listdir(S)):
        res = pg.evaluate(JS, base64.b64encode(open(os.path.join(S, fn), "rb").read()).decode())
        exp = DE90 if "comdirect" in fn else (CH if fn.startswith("ch_") else DE)
        if fn == "de_revolut.csv":  # Revolut liefert nur den Empfänger, ohne Verwendungszweck → «DB Vertrieb» statt «Deutschlandticket»
            exp = {("DB Vertrieb" if k == "Deutschlandticket" else k): v for k, v in exp.items()}
        if not res: print(f"✗ {fn}: nicht gelesen"); fails += 1; continue
        got = {s["name"]: s for s in res["sugg"]}; errs = []
        for k, (cy, amt, ch) in exp.items():
            hit = [s for n, s in got.items() if n.lower().startswith(k.lower()) or k.lower() in n.lower()]
            if not hit: errs.append(f"fehlt {k}"); continue
            s = hit[0]
            if s["cycle"] != cy: errs.append(f"{k} Turnus {s['cycle']}≠{cy}")
            if abs(s["amount"] - amt) > 0.01: errs.append(f"{k} Betrag {s['amount']}≠{amt}")
            sc = s["change"]["from"][:7] if s["change"] else None
            if sc != ch: errs.append(f"{k} Preisänderung {sc}≠{ch}")
        extra = [n for n in got if not any(n.lower().startswith(k.lower()) or k.lower() in n.lower() for k in exp)]
        if extra: errs.append("zu viel: " + ", ".join(extra))
        print(("✓" if not errs else "✗"), f"{fn:24} {res['fmt']:13} {res['bank'] or '–':13} {res['n']:4} Buchungen  {len(got)} Vorschläge", ("  " + "; ".join(errs)) if errs else "")
        fails += bool(errs)
        if V:
            for s in res["sugg"]: print(f"      {s['conf']:7} {s['name'][:34]:34} {s['cycle']:>2}M {s['amount']:>9.2f}  {s['cat']}  {s['change'] or ''}")
    # Abgleich mit erfassten Verträgen: CSS mit altem Preis → Preisänderung, Netflix gleich → bereits erfasst
    st["contracts"] = {"a": {"partner": "CSS", "cat": "Versicherung", "amount": 389.60, "cur": "CHF", "cycle": 1, "due": "2026-11-01", "status": "active", "holders": ["Sinan"]},
                       "b": {"partner": "Netflix", "cat": "Abos & Medien", "amount": 18.90, "cur": "CHF", "cycle": 1, "due": "2026-10-12", "status": "active", "holders": ["Sinan"]}}
    pg.evaluate("s=>localStorage.setItem('vertraege.v1',s)", json.dumps(st)); pg.reload(); pg.wait_for_timeout(400)
    res = pg.evaluate(JS, base64.b64encode(open(os.path.join(S, "ch_postfinance.csv"), "rb").read()).decode())
    css = [s for s in res["sugg"] if s["name"] == "CSS"]
    ok = css and css[0]["match"] and css[0]["match"]["kind"] == "price" and abs(css[0]["match"]["amount"] - 412.30) < .01 and "Netflix" in res["known"]
    print(("✓" if ok else "✗"), "Abgleich: CSS → Preisänderung 389.60 → 412.30, Netflix → bereits erfasst", "" if ok else json.dumps(css, ensure_ascii=False))
    fails += not ok
    b.close()
print("Alles gut" if not fails else f"{fails} Fehler"); sys.exit(1 if fails else 0)
