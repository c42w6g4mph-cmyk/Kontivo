"""Erfundene, realitätsnahe Auszüge (UBS-Konto + Swisscard, Format wie Originalexporte, 15.09.2025–27.10.2026) – Erwartung je Vertrag/Einnahme.
Erzeugt mit beispiel/make_ubs_swisscard.py. Aufruf im Repo-Ordner:  python3 -m http.server 8765 &  python3 tests/bank/beispiel.py"""
import os, re, sys, json
from playwright.sync_api import sync_playwright
D = os.path.dirname(os.path.abspath(__file__)); URL = os.environ.get("KONTIVO_URL", "http://localhost:8765/index.html")
FIX = [("Muster Immobilien", 1, 2150), ("Kita Sonnenschein", 1, 1260), ("Steueramt der Stadt Winterthur", 1, 900), ("CSS", 1, 845.1), ("VIAC", 1, 500),
       ("AMAG Leasing", 1, 389), ("Musikschule", 6, 640), ("Migros Zuerich Fitnesspark", 1, 89), ("Sunrise", 1, 59.9), ("Salt", 1, 29.95), ("Spotify", 1, 25.95),
       ("Netflix", 1, 20.9), ("YouTube Premium", 1, 15.9), ("Apple", 1, 3), ("Amazon Kindle", 1, None), ("Microsoft 365", 12, 99), ("Stadtwerk Winterthur", 3, None), ("Kantonales Steueramt", 12, 1240), ("AXA", 12, 1184.5),
       ("Die Mobiliar", 12, 486.3), ("Strassenverkehrsamt", 12, 412), ("Serafe", 12, 335), ("Protekta", 12, 318), ("FC Winterthur", 12, 290), ("SBB Halbtax", 12, 190),
       ("Stadtpolizei Winterthur Hundekontrolle", 12, 160), ("Amazon Prime", 12, None), ("Duolingo", 12, 89)]
INC = [("Muster Engineering", 1, 8700), ("SVA Zuerich", 1, 215), ("Muster Engineering", 12, 8450), ("Muster Engineering", 12, 4200)]
NOT = ["Max Muster", "Swisscard", "Bancomat", "Muster Anna", "Zahnarzt", "Stadtpolizei Winterthur Ordnungsbusse", "Malergeschaeft", "Disney", "Migros", "Coop", "Lidl", "Digitec", "Zalando", "Shell"]
ST = {"settings": {"home": "CHF", "holders": ["Max"], "onboarded": 9, "sender": {"name": "Max Muster"}, "rateCheckedAt": 9999999999999}, "contracts": {}, "incomes": {}}
fails = 0
with sync_playwright() as p:
    b = p.chromium.launch(); ctx = b.new_context(); ctx.add_init_script("window.__KONTIVO_TODAY='2026-10-27';")
    ctx.route(re.compile(r"^https?://(?!localhost)"), lambda r: r.abort())
    pg = ctx.new_page(); pg.goto(URL); pg.evaluate("s=>localStorage.setItem('vertraege.v1',s)", json.dumps(ST)); pg.reload(); pg.wait_for_timeout(1500)
    pg.set_input_files("#bankFile", [os.path.join(D, "beispiel", f) for f in ("UBS_erweitert.csv", "Swisscard_erweitert.csv")])
    pg.wait_for_selector("#sheetBank.on", timeout=60000); pg.wait_for_timeout(3000)
    r = pg.evaluate("()=>{var b=window.KontivoBank().bk();return {fix:b.items.map(it=>[it.ed.name,it.s.cycle,it.s.amount]),inc:b.inc.map(it=>[it.ed.name,it.s.cycle,it.s.amount])};}")
    def check(lst, got, what):
        global fails
        got = list(got)
        for nm, cy, am in lst:
            h = [g for g in got if g[0].startswith(nm) and g[1] == cy and (am is None or abs(g[2] - am) < .01)]
            if h: got.remove(h[0])
            else: print("✗", what, "fehlt", nm, cy, am); fails += 1
        return got
    rest = check(FIX, r["fix"], "Vertrag"); rest_i = check(INC, r["inc"], "Einnahme")
    for g in rest:
        print("✗ Vertrag zu viel", g); fails += 1
    for g in rest_i:
        print("✗ Einnahme zu viel", g); fails += 1
    print(f"{len(r['fix'])} Verträge, {len(r['inc'])} Einnahmen")
    b.close()
print("Alles gut" if not fails else f"{fails} Fehler"); sys.exit(1 if fails else 0)
