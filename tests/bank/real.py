"""Kontoauszug-Import gegen nachgebaute echte Bankformate (tests/bank/real/de|ch, Quellen in SOURCES.md).
Gleiches Szenario in allen Dateien; geprüft wird, ob die erwarteten Verträge vorgeschlagen werden und nichts anderes.
Aufruf im Repo-Ordner:  python3 -m http.server 8765 &  python3 tests/bank/real.py [-v] [Dateifilter]"""
import base64, json, os, sys
from playwright.sync_api import sync_playwright
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "real")
URL = os.environ.get("KONTIVO_URL", "http://localhost:8765/index.html")
V = "-v" in sys.argv; F = [a for a in sys.argv[1:] if not a.startswith("-")]
# Name beginnt mit → (Turnus, Betrag, Preisänderung ab)
DE = {"Wohnbau Konstanz": (1, 1180, None), "Telekom": (1, 39.95, None), "Netflix": (1, 13.99, None), "Spotify": (1, 11.99, None),
      "Rundfunkbeitrag": (3, 55.08, None), "Allianz": (12, 89.40, None)}
CH = {"Immo Seeblick": (1, 1850, None), "CSS": (1, 412.30, "2026-01"), "Swisscom": (1, 79, None), "Netflix": (1, 18.90, None),
      "Energie Kreuzlingen": (3, 180.50, None), "Serafe": (12, 335, None)}
CARD = ("kreditkarte", "visa", "card", "creditcard", "swisscard", "viseca", "amex", "barclays")
JS = """(b64)=>{var bin=atob(b64),u=new Uint8Array(bin.length);for(var i=0;i<bin.length;i++)u[i]=bin.charCodeAt(i);
  var B=window.KontivoBank(),r=B.read(u.buffer);if(!r)return null;var f=B.find(r,[]);
  return {fmt:f.fmt,bank:f.bank,n:f.n,from:f.from,to:f.to,neg:r.tx.filter(function(t){return t.a<0}).length,pos:r.tx.filter(function(t){return t.a>0}).length,
   sugg:f.sugg.map(function(s){return {cur:s.cur,name:s.name,cycle:s.cycle,amount:s.amount,conf:s.conf,change:s.change,kind:s.kind,n:s.n};})};}"""
tot = fails = 0
with sync_playwright() as p:
    b = p.chromium.launch(); ctx = b.new_context(); ctx.add_init_script("window.__KONTIVO_TODAY='2026-10-08';")
    pg = ctx.new_page(); pg.goto(URL)
    st = {"settings": {"home": "CHF", "onboarded": 9, "holders": ["Max"], "rateTs": 9999999999999}, "contracts": {}, "incomes": {}}
    pg.evaluate("s=>localStorage.setItem('vertraege.v1',s)", json.dumps(st)); pg.reload(); pg.wait_for_timeout(400)
    for cc in ("de", "ch"):
        for fn in sorted(os.listdir(os.path.join(D, cc))):
            if fn.endswith(".md") or (F and not any(x in fn for x in F)): continue
            tot += 1
            res = pg.evaluate(JS, base64.b64encode(open(os.path.join(D, cc, fn), "rb").read()).decode())
            exp = dict(DE if cc == "de" else CH)
            card = any(x in fn for x in CARD)
            if card:
                exp = {"Netflix": exp["Netflix"]}
                if cc == "de": exp["Spotify"] = DE["Spotify"]   # in den DE-Kartendateien läuft Spotify über die Karte
            if fn == "de_revolut.csv":   # Revolut zeigt bei PayPal nur «PayPal Europe …», ohne Händler
                exp["PayPal"] = exp.pop("Spotify")
            if not res: print(f"✗ {fn:34} nicht gelesen"); fails += 1; continue
            got = {s["name"]: s for s in res["sugg"]}; errs = []
            for k, (cy, amt, ch) in exp.items():
                hit = [s for n, s in got.items() if n.lower().startswith(k.lower()) or k.lower() in n.lower()]
                if not hit: errs.append(f"fehlt {k}"); continue
                s = hit[0]
                if s["cycle"] != cy: errs.append(f"{k} Turnus {s['cycle']}≠{cy}")
                if abs(s["amount"] - amt) > 0.01: errs.append(f"{k} Betrag {s['amount']}≠{amt}")
                sc = s["change"]["from"][:7] if s["change"] else None
                if sc != ch: errs.append(f"{k} Preisänderung {sc}≠{ch}")
            wc = [s["name"] for s in res["sugg"] if s["cur"] != ("EUR" if cc == "de" else "CHF")]
            if wc: errs.append("falsche Währung: " + ", ".join(wc))
            extra = [f"{n} ({s['cycle']}M {s['amount']})" for n, s in got.items() if not any(n.lower().startswith(k.lower()) or k.lower() in n.lower() for k in exp)]
            if extra: errs.append("zu viel: " + ", ".join(extra))
            print(("✓" if not errs else "✗"), f"{fn:34} {res['bank'] or res['fmt']:12} {res['n']:4} Buch. ({res['neg']}−/{res['pos']}+)", ("  " + "; ".join(errs)) if errs else "")
            fails += bool(errs)
            if V or errs:
                for s in res["sugg"]: print(f"      {s['conf']:7} {s['name'][:34]:34} {s['cycle']:>2}M {s['amount']:>9.2f} {s['kind'] or '-':4} n={s['n']}")
    b.close()
print(f"{tot - fails}/{tot} ok"); sys.exit(1 if fails else 0)
