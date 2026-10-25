"""Lernen aus Korrekturen (25.10.2026): bewusst abgewählter Vorschlag ist beim nächsten Import vorab abgewählt,
geänderte Bezeichnung wird übernommen – je Vertragspartner und Betrag, eins zu eins (mehrere Policen beim selben Versicherer).
Aufruf im Repo-Ordner:  python3 -m http.server 8765 &  python3 tests/bank/learn.py"""
import json, os, re, sys
from playwright.sync_api import sync_playwright
D = os.path.dirname(os.path.abspath(__file__)); URL = os.environ.get("KONTIVO_URL", "http://localhost:8765/index.html")
TXT = json.load(open(os.path.join(D, "edge_cases.json")))["policen"]["txt"]
ST = {"settings": {"home": "CHF", "onboarded": 9, "holders": ["Max"], "rateCheckedAt": 9999999999999}, "contracts": {}, "incomes": {}}
L = "()=>window.KontivoBank().bk().items.map((it,i)=>[i,it.ed.name,it.ed.label,it.s.amount,it.on])"
fails = 0
with sync_playwright() as p:
    b = p.chromium.launch(); ctx = b.new_context(); ctx.add_init_script("window.__KONTIVO_TODAY='2026-10-08';")
    ctx.route(re.compile(r"^https?://(?!localhost)"), lambda r: r.abort())
    pg = ctx.new_page(); errs = []; pg.on("pageerror", lambda e: errs.append(str(e)))
    pg.goto(URL); pg.evaluate("s=>localStorage.setItem('vertraege.v1',s)", json.dumps(ST)); pg.reload(); pg.wait_for_timeout(1500)
    def imp():
        pg.set_input_files("#bankFile", files=[{"name": "auszug.csv", "mimeType": "text/csv", "buffer": TXT.encode()}])
        pg.wait_for_selector("#sheetBank.on", timeout=30000); pg.wait_for_timeout(1500)
    imp(); it = pg.evaluate(L)
    sun = [x[0] for x in it if x[1].startswith("Sunrise")][0]; pol = {x[3]: x[0] for x in it if x[1].startswith("Muster Versicherung")}
    pg.locator(f'[data-bkon="{sun}"]').click()                                  # Sunrise bewusst abwählen
    pg.locator(f'[data-bkyes="{pol[404.1]}"]').click()
    pg.evaluate("i=>{window.KontivoBank().bk().items[i].ed.label='Hausrat';}", pol[404.1])  # Police mit Bezeichnung übernehmen
    for _ in range(4):
        pg.locator("#bkGo").click(); pg.wait_for_timeout(600)
        if not pg.evaluate("!!document.querySelector('#sheetBank.on')"): break
    pg.evaluate("()=>{var s=JSON.parse(localStorage.getItem('vertraege.v1'));s.contracts={};localStorage.setItem('vertraege.v1',JSON.stringify(s));}"); pg.reload(); pg.wait_for_timeout(1500)
    imp(); it = {x[3]: x for x in pg.evaluate(L)}
    for ok, txt in [(it[39][4] is False, "abgewählt bleibt abgewählt"), (it[404.1][2] == "Hausrat", "Bezeichnung gelernt"),
                    (it[383.2][2] == "" and it[372.7][2] == "", "andere Policen bleiben ohne Bezeichnung"), (not errs, "keine JS-Fehler")]:
        print("✓" if ok else "✗", txt); fails += not ok
    b.close()
print("Alles gut" if not fails else f"{fails} Fehler"); sys.exit(1 if fails else 0)
