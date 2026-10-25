"""Grenzfälle des Kontoauszug-Imports (tests/bank/edge_cases.json, aus dem Review 08.10.2026).
Aufruf im Repo-Ordner:  python3 -m http.server 8765 &  python3 tests/bank/edge.py"""
import json, os, sys, re
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
 "kartenbez": dict(s=[("Spotify", 1, 13.95), ("YouTube Premium", 1, 15.9), ("Netflix", 1, 18.9), ("Notion", 1, 9.5), ("Apple", 1, 2.0)]),
 "camtcodes": dict(s=[("Muster Versicherung", 1, 12.5), ("Muster Versicherung", 1, 12.5), ("Muster Energie", 1, 100.1), ("Neues Fitness", 1, 24.9, "mittel")]),
 "alias": dict(s=[("Deutschlandticket", 1, 63)]),
 "gepflegt": dict(s=[], k=["Swisscom", "Immo Seeblick", "Die Mobiliar"]),
 # Review 23.10.2026
 "mietkonto": dict(s=[("Muster Hausverwaltung", 1, 350)]),
 "zweikinder": dict(s=[("FC Muster", 1, 45), ("FC Muster", 1, 45)]),
 "kuend_vorher": dict(s=[("Sunrise", 1, 39)], k=["AXA"]),
 "kuend_danach": dict(s=[("Sunrise", 1, 39), ("AXA", 12, 159.6)]),
 "rechtsschutz": dict(s=[("Sunrise", 1, 39)], k=["Die Mobiliar"]),
 "promoende": dict(s=[("Muster Telecom", 1, 39.9)]),
 "zweigemeinden": dict(s=[("Gemeinde Taegerwilen", 1, 80), ("Gemeinde Kreuzlingen", 3, 85)]),
 "kuend_neu": dict(s=[("Sunrise", 1, 49)]),
 "swisscom2": dict(s=[("Swisscom", 1, 32.9), ("Swisscom", 1, 29.9)]),
 "swisscom2_known": dict(s=[("Swisscom", 1, 32.9)], k=["Swisscom"]),
 "kinderkk": dict(s=[("Muster Krankenkasse", 1, 105.3), ("Muster Krankenkasse", 1, 98.4)]),
 "jahr_kurz": dict(s=[("Sunrise", 1, 39), ("Helvetia", 12, 480)]),
 "kernreihe": dict(s=[("Apple", 1, 10)]),
 "stabilkey": dict(s=[("Haftpflicht Muster", 1, 25), ("Muster Assekuranz", 1, 12), ("Muster Assekuranz", 1, 8)]),
 # Review 25.10.2026: Kürzel vor Komma, Jahresrechnung früher bezahlt (339 Tage), Versicherer mit mehreren Policen ohne Bezeichnung
 "kuerzel": dict(s=[("Sunrise", 1, 39), ("Muster Kautionsservice", 12, 320)]),
 "jahr_frueh": dict(s=[("Sunrise", 1, 39), ("Muster Abgabestelle", 12, 187.4)]),
 "kk_einmal": dict(s=[("Sunrise", 1, 39), ("Muster Krankenkasse", 1, 456.8)]),
 "pause_monat": dict(s=[("Sunrise", 1, 39), ("Muster Sportclub", 1, 64)]),
 "jahresreihe": dict(s=[("Sunrise", 1, 39), ("Muster Versicherung", 12, 404.1, "mittel"), ("Muster Versicherung", 6, 372.7, "mittel")]),
 "beendet_monat": dict(s=[("Sunrise", 1, 39)]),
 "zwei_fahrzeuge": dict(s=[("Sunrise", 1, 39), ("Strassenverkehrsamt", 12, 168), ("Strassenverkehrsamt", 12, 153.15)]),
 "verein_einmal": dict(s=[("Sunrise", 1, 39), ("FC Muster", 12, 230)]),
 "rund_jaehrlich": dict(s=[("Sunrise", 1, 39), ("Stadtverwaltung Musterstadt", 12, 100, "hoch")]),
 "rund_zweimal": dict(s=[("Sunrise", 1, 39), ("Stadtverwaltung Musterstadt", 12, 100, "niedrig")]),
 "faelligkeit": dict(s=[("Sunrise", 1, 39)], k=["Muster Versicherung", "Muster Versicherung"]),
 "halbjahr": dict(s=[("Sunrise", 1, 39), ("Muster Versicherung", 6, 372.7)]),
 "teilzahlung": dict(s=[("Sunrise", 1, 39)], k=["Muster Versicherung"]),
 "steuerjahre": dict(s=[("Sunrise", 1, 39), ("Steuerverwaltung Musterkanton", 12, 549)]),
 "vereine": dict(s=[("Sunrise", 1, 39), ("TV Musterdorf", 12, 120), ("Musikgesellschaft Musterdorf", 12, 80), ("STV Musterberg", 12, 150)]),
 "policen": dict(s=[("Sunrise", 1, 39), ("Muster Versicherung", 12, 404.1), ("Muster Versicherung", 12, 383.2), ("Muster Versicherung", 12, 372.7)]),
}
JS = """([txt,contracts,alias])=>{var B=window.KontivoBank();B.state.contracts=contracts||{};B.state.settings.bankAlias=alias||{};var r=B.read(txt);if(!r)return null;var f=B.find(r,[]);
 return {sugg:f.sugg.map(function(s){return [s.name,s.cycle,s.amount,s.due,!!s.match,s.conf]}),
  known:f.known.map(function(s){return (B.state.contracts[s.match.id]||{}).partner}),miss:([]).map(function(id){return B.state.contracts[id].partner})};}"""
fails = 0
with sync_playwright() as p:
    b = p.chromium.launch(); ctx = b.new_context(); ctx.add_init_script("window.__KONTIVO_TODAY='2026-10-08';")
    ctx.route(re.compile(r"frankfurter\.|open\.er-api\.com"), lambda r: r.abort())  # kein Live-Kursabruf: feste Testkurse
    pg = ctx.new_page(); pg.goto(URL)
    st = {"settings": {"home": "CHF", "onboarded": 9, "holders": ["Sinan"], "rateCheckedAt": 9999999999999}, "contracts": {}, "incomes": {}}
    pg.evaluate("s=>localStorage.setItem('vertraege.v1',s)", json.dumps(st)); pg.reload(); pg.wait_for_timeout(400)
    for k, e in E.items():
        r = pg.evaluate(JS, [C[k]["txt"], C[k].get("contracts"), C[k].get("alias")]); errs = []
        if not r: errs.append("nicht gelesen")
        else:
            got = list(r["sugg"])
            for x in e["s"]:
                nm, cy, am = x[:3]; cf = x[3] if len(x) > 3 else None
                h = [g for g in got if g[0].lower().startswith(nm.lower()) and g[1] == cy and abs(g[2] - am) < .01 and (not cf or g[5] == cf)]
                if not h: errs.append(f"fehlt {nm} {cy}M {am}")
                else: got.remove(h[0])
                if h and e.get("nomatch") and h[0][4]: errs.append(f"{nm} fälschlich einem Vertrag zugeordnet")
                if h and e.get("due") and h[0][3] != e["due"]: errs.append(f"{nm} nächste Zahlung {h[0][3]}")
            if got: errs.append("zu viel: " + ", ".join(f"{g[0]} {g[1]}M {g[2]}" for g in got))
            if sorted(r["known"]) != sorted(e.get("k", [])): errs.append(f"bereits erfasst {r['known']}")
            if "miss" in e and sorted(r["miss"]) != sorted(e["miss"]): errs.append(f"nicht im Auszug {r['miss']}")
        print(("✓" if not errs else "✗"), f"{k:15}", "; ".join(errs)); fails += bool(errs)
    # Laufzeit (Review 23.10.2026: Katalogabgleich war O(n²), 94 s bei 1'720 Buchungen): Stressdatei muss unter 3 s ausgewertet sein
    for fn in ["ch_tkb_stress.csv", "de_sparkasse_stress.csv"]:
        ms = pg.evaluate("""(txt)=>{var B=window.KontivoBank();B.state.contracts={};var t0=performance.now(),r=B.read(txt);B.find(r,[]);B.findInc(r);return Math.round(performance.now()-t0);}""",
                         open(os.path.join(D, "stress", fn), encoding="utf-8", errors="replace").read())
        ok = ms < 3000; print(("✓" if ok else "✗"), f"{'zeit '+fn[:9]:15}", f"{ms} ms"); fails += (not ok)
    b.close()
print("Alles gut" if not fails else f"{fails} Fehler"); sys.exit(1 if fails else 0)
