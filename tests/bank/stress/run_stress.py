"""Prüft die Stress-Auszüge: erwartete Vorschläge (Name, Turnus, Betrag, Preisänderung), Einnahmen, nichts Überflüssiges.
Aufruf im Repo-Ordner: python3 tests/bank/stress/run_stress.py [-v]"""
import base64, json, os, sys
from playwright.sync_api import sync_playwright
D = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.abspath(os.path.join(D, "..", "..", ".."))
URL = os.environ.get("KONTIVO_URL", "file://" + os.path.join(ROOT, "index.html")); V = "-v" in sys.argv
# erwartet: Name enthält → (Turnus, aktueller Betrag, Preisänderung ab JJJJ-MM oder None)
DE = {"Wohnbau": (1, 1215, "2026-04"), "Telekom": (1, 44.95, "2026-07"), "Netflix": (1, 13.99, None), "Spotify": (1, 12.99, "2026-01"),
      "Disney": (1, 9.99, None), "Rundfunk": (3, 55.08, None), "Allianz": (12, 89.40, None), "HUK": (6, 214.30, None),
      "Stadtwerke": (1, 104.00, "2026-03"), "McFit": (1, 24.90, None), "congstar": (1, 15.00, None), "Amazon Prime": (12, 89.90, None)}
DE_OPT = ("Trade Republic", "Vodafone")  # Sparplan / gekündigter Vertrag: Vorschlag erlaubt, aber nicht nötig
CH = {"Immo Seeblick": (1, 1850, None), "CSS": (1, 412.30, "2026-01"), "Helsana": (1, 48.70, None), "Swisscom": (1, 89.00, "2026-06"),
      "Netflix": (1, 20.90, "2026-04"), "Spotify": (1, 13.95, None), "Energie Kreuzlingen": (3, 180.50, None), "Serafe": (12, 335.00, None),
      "Mobiliar": (12, 289.20, None), "Migros": (1, 79.00, None), "Kreuzlingen": (1, 760.00, None)}
CH_OPT = ("SBB",)
INC = {"de": ("Muster Pharma",), "ch": ("Muster Pharma",)}
JS = """(b64)=>{var bin=atob(b64),u=new Uint8Array(bin.length);for(var i=0;i<bin.length;i++)u[i]=bin.charCodeAt(i);
  var B=window.KontivoBank(),r=B.read(u.buffer);if(!r)return null;var f=B.find(r,[]);var inc=B.findInc?B.findInc(r,[]):null;
  return {fmt:f.fmt,bank:f.bank,n:f.n,from:f.from,to:f.to,neg:r.tx.filter(function(t){return t.a<0}).length,pos:r.tx.filter(function(t){return t.a>0}).length,
   sugg:f.sugg.map(function(s){return {cur:s.cur,name:s.name,cycle:s.cycle,amount:s.amount,conf:s.conf,change:s.change,kind:s.kind,n:s.n};}),
   inc:((f.inc&&f.inc.sugg)||(inc&&inc.sugg)||[]).map(function(s){return {name:s.name,cycle:s.cycle,amount:s.amount,conf:s.conf,change:s.change};})};}"""
fails = 0
with sync_playwright() as p:
    b = p.chromium.launch(); ctx = b.new_context(); ctx.add_init_script("window.__KONTIVO_TODAY='2026-10-17';")
    pg = ctx.new_page(); pg.goto(URL)
    pg.evaluate("s=>localStorage.setItem('vertraege.v1',s)", json.dumps({"settings": {"home": "CHF", "onboarded": 9, "holders": ["Max"], "rateTs": 9999999999999}, "contracts": {}, "incomes": {}}))
    pg.reload(); pg.wait_for_timeout(500)
    for fn in sorted(f for f in os.listdir(D) if f.endswith(".csv")):
        cc = fn[:2]; exp, opt = (DE, DE_OPT) if cc == "de" else (CH, CH_OPT)
        res = pg.evaluate(JS, base64.b64encode(open(os.path.join(D, fn), "rb").read()).decode())
        if not res: print("✗", fn, "nicht gelesen"); fails += 1; continue
        got = res["sugg"]; errs = []; used = set()
        for k, (cy, amt, ch) in exp.items():
            hit = [s for s in got if k.lower() in s["name"].lower()]
            if not hit: errs.append(f"fehlt {k}"); continue
            s = hit[0]; used.add(s["name"])
            if s["cycle"] != cy: errs.append(f"{k}: Turnus {s['cycle']}≠{cy}")
            if abs(s["amount"] - amt) > 0.01: errs.append(f"{k}: Betrag {s['amount']}≠{amt}")
            sc = s["change"]["from"][:7] if s.get("change") else None
            if sc != ch: errs.append(f"{k}: Preisänderung {sc}≠{ch}")
        wc = [s["name"] for s in got if s["cur"] != ("EUR" if cc == "de" else "CHF")]
        if wc: errs.append("falsche Währung: " + ", ".join(wc))
        extra = [f"{s['name']} ({s['cycle']}M {s['amount']}, {s['conf']})" for s in got if s["name"] not in used and not any(o.lower() in s["name"].lower() for o in opt)]
        if extra: errs.append("zu viel: " + "; ".join(extra))
        incs = [i["name"] for i in res["inc"]]
        miss_inc = [k for k in INC[cc] if not any(k.lower() in n.lower() for n in incs)]
        if miss_inc: errs.append("Einnahme fehlt: " + ", ".join(miss_inc))
        print(("✓" if not errs else "✗"), f"{fn:26} {str(res['bank'] or res['fmt']):14} {res['n']:4} Buchungen ({res['neg']}−/{res['pos']}+) {res['from']}–{res['to']}")
        for e in errs: print("     -", e)
        fails += bool(errs)
        if V or errs:
            for s in got: print(f"       {s['conf']:7} {s['name'][:36]:36} {s['cycle']:>2}M {s['amount']:>9.2f} n={s['n']} {('Δ ab '+s['change']['from']) if s.get('change') else ''}")
            for i in res["inc"]: print(f"       Einnahme {i['name'][:30]:30} {i['cycle']}M {i['amount']:.2f} {i['conf']}")
    b.close()
sys.exit(1 if fails else 0)
