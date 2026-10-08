"""Grenzfälle des Kontoauszug-Imports (tests/bank/edge_cases.json, aus dem Review 08.10.2026).
Aufruf im Repo-Ordner:  python3 -m http.server 8765 &  python3 tests/bank/edge.py"""
import json, os, sys
from playwright.sync_api import sync_playwright
D = os.path.dirname(os.path.abspath(__file__)); URL = os.environ.get("KONTIVO_URL", "http://localhost:8765/index.html")
C = json.load(open(os.path.join(D, "edge_cases.json")))
# Erwartung je Fall: Vorschläge (Name beginnt mit …, Turnus, Betrag), bereits erfasst, nicht im Auszug
E = {
 "sollhaben": dict(s=[("Telekom", 1, 39.95)]),
 "plus": dict(s=[("Swisscom", 1, 79)]),
 "twocontracts": dict(s=[("Muster Assekuranz", 1, 12.5), ("Muster Assekuranz", 1, 8.9)]),
 "oldonce": dict(s=[("Bodensee Verkehrsverbund", 1, 63)]),
 "merge": dict(s=[("Seeblick", 1, 29)]),
 "falsematch": dict(s=[("Energie Kreuzlingen", 1, 180.5)], nomatch=True),
 "mt940free": dict(s=[("Swisscom", 1, 79)]),
 "mt940multi": dict(s=[("Swisscom", 1, 79), ("Muster Streaming", 1, 13.99)]),
 "camtrev": dict(s=[("McFit", 1, 24.9)]),
 "camtbatch02": dict(s=[("Immo Seeblick", 1, 1850), ("CSS", 1, 389.6)]),
 "otherproduct": dict(s=[("Swisscom", 1, 39)], nomatch=True),
 "delim": dict(s=[("Sunrise", 1, 39)]),
 "eom": dict(s=[("Hausverwaltung Muster", 1, 1500)]),
 "yearlylate": dict(s=[("Sunrise", 1, 39), ("Serafe", 12, 335)]),
 "css_known": dict(s=[], k=["CSS Kranken-Versicherung"]),
 "quotednl": dict(s=[("Sunrise", 1, 39)]),
 "ddmmyyyy_dash": dict(s=[("Sunrise", 1, 39)]),
 "us": dict(s=[("Sunrise", 1, 39)]),
 "dkbpending": dict(s=[("Telekom", 1, 39.95)], due="2026-11-03"),
 "camt054": dict(s=[("Swisscom", 1, 79)]),
 "paypal": dict(s=[("Disney", 1, 9.99), ("Muster Cloud", 1, 9.49)]),
 "yearlyq": dict(s=[("Muster Wasserwerk", 3, 80), ("Muster Haftpflicht", 12, 120)]),
 "alltag": dict(s=[("Sunrise", 1, 39)]),
 "gepflegt": dict(s=[], k=["Swisscom", "Immo Seeblick", "Die Mobiliar"]),
}
JS = """([txt,contracts])=>{var B=window.KontivoBank();B.state.contracts=contracts||{};var r=B.read(txt);if(!r)return null;var f=B.find(r,[]);
 return {sugg:f.sugg.map(function(s){return [s.name,s.cycle,s.amount,s.due,!!s.match]}),
  known:f.known.map(function(s){return (B.state.contracts[s.match.id]||{}).partner}),miss:([]).map(function(id){return B.state.contracts[id].partner})};}"""
fails = 0
with sync_playwright() as p:
    b = p.chromium.launch(); ctx = b.new_context(); ctx.add_init_script("window.__KONTIVO_TODAY='2026-10-08';")
    pg = ctx.new_page(); pg.goto(URL)
    st = {"settings": {"home": "CHF", "onboarded": 9, "holders": ["Sinan"], "rateTs": 9999999999999}, "contracts": {}, "incomes": {}}
    pg.evaluate("s=>localStorage.setItem('vertraege.v1',s)", json.dumps(st)); pg.reload(); pg.wait_for_timeout(400)
    for k, e in E.items():
        r = pg.evaluate(JS, [C[k]["txt"], C[k].get("contracts")]); errs = []
        if not r: errs.append("nicht gelesen")
        else:
            got = list(r["sugg"])
            for nm, cy, am in e["s"]:
                h = [g for g in got if g[0].lower().startswith(nm.lower()) and g[1] == cy and abs(g[2] - am) < .01]
                if not h: errs.append(f"fehlt {nm} {cy}M {am}")
                else: got.remove(h[0])
                if h and e.get("nomatch") and h[0][4]: errs.append(f"{nm} fälschlich einem Vertrag zugeordnet")
                if h and e.get("due") and h[0][3] != e["due"]: errs.append(f"{nm} nächste Zahlung {h[0][3]}")
            if got: errs.append("zu viel: " + ", ".join(f"{g[0]} {g[1]}M {g[2]}" for g in got))
            if sorted(r["known"]) != sorted(e.get("k", [])): errs.append(f"bereits erfasst {r['known']}")
            if "miss" in e and sorted(r["miss"]) != sorted(e["miss"]): errs.append(f"nicht im Auszug {r['miss']}")
        print(("✓" if not errs else "✗"), f"{k:15}", "; ".join(errs)); fails += bool(errs)
    b.close()
print("Alles gut" if not fails else f"{fails} Fehler"); sys.exit(1 if fails else 0)
