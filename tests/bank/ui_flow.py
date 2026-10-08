"""Bedienablauf Kontoauszug-Import (Playwright): Datei wählen, Zeile bearbeiten, ausblenden, anlegen, zweiter Import, falsche Datei.
Aufruf im Repo-Ordner:  python3 -m http.server 8765 &  python3 tests/bank/ui_flow.py"""
import json, os, sys
from playwright.sync_api import sync_playwright
OUT = os.environ.get("KONTIVO_SHOTS", "/tmp/kontivo-bank-ui")
os.makedirs(OUT, exist_ok=True)
S = os.path.join(os.path.dirname(os.path.abspath(__file__)), "samples") + "/"
st = {"settings": {"home": "CHF", "onboarded": 9, "holders": ["Sinan", "Lara"], "rateTs": 9999999999999},
      "contracts": {"a": {"partner": "CSS", "label": "Krankenkasse", "cat": "Versicherung", "amount": 389.60, "cur": "CHF", "cycle": 1, "due": "2026-11-01", "status": "active", "holders": ["Sinan"]},
                    "b": {"partner": "Netflix", "label": "Streaming", "cat": "Abos & Medien", "amount": 18.90, "cur": "CHF", "cycle": 1, "due": "2026-10-12", "status": "active", "holders": ["Sinan", "Lara"]}},
      "incomes": {}}
errs = []
with sync_playwright() as p:
    b = p.chromium.launch()
    for theme in ["light", "dark"]:
        ctx = b.new_context(viewport={"width": 393, "height": 852}, device_scale_factor=2, color_scheme=theme, has_touch=True)
        ctx.add_init_script("window.__KONTIVO_TODAY='2026-10-08';")
        pg = ctx.new_page(); pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.goto("http://localhost:8765/index.html")
        pg.evaluate("s=>localStorage.setItem('vertraege.v1',s)", json.dumps(st)); pg.reload(); pg.wait_for_timeout(500)
        pg.click('.tabbar button[data-tab="set"]'); pg.wait_for_timeout(300)
        if theme == "light": pg.screenshot(path=f"{OUT}/0_mehr.png")
        pg.set_input_files("#bankFile", S + "ch_postfinance.csv"); pg.wait_for_timeout(700)
        assert pg.is_visible("#sheetBank.on"), "Sheet nicht offen"
        pg.screenshot(path=f"{OUT}/1_liste_{theme}.png")
        # Swisscom aufklappen und bearbeiten
        pg.click('#bkBody .bkmain:has-text("Swisscom")'); pg.wait_for_timeout(300)
        pg.fill('#bkA', "81.50"); pg.click('#bkBody [data-bkh="*"]'); pg.select_option('#bkC', "1")
        pg.screenshot(path=f"{OUT}/2_bearbeiten_{theme}.png")
        if theme == "light":
            pg.click('#bkBody .bkdone'); pg.wait_for_timeout(200)
            # Serafe (Vielleicht) aufklappen → Nie mehr vorschlagen
            pg.click('#bkBody .bkmain:has-text("Serafe")'); pg.click('#bkBody [data-bkign]'); pg.wait_for_timeout(200)
            # Mobiliar ankreuzen
            pg.click('#bkBody .bkrow:has-text("Die Mobiliar") [data-bkon]')
            btn = pg.inner_text("#bkGo"); print("Knopf:", btn)
            pg.click("#bkGo"); pg.wait_for_timeout(500)
            pg.screenshot(path=f"{OUT}/3_nachher.png")
            d = pg.evaluate("()=>JSON.parse(localStorage.getItem('vertraege.v1'))")
            cs = d["contracts"]; names = sorted(c["partner"] for c in cs.values())
            print("Verträge:", names)
            sw = [c for c in cs.values() if c["partner"] == "Swisscom"][0]
            print("Swisscom:", sw["amount"], sw["holders"], sw["cycle"], sw["cancF"], sw["notice"], sw["noticeU"], sw["due"])
            print("CSS prices:", cs["a"].get("prices"))
            print("bankIgn:", d["settings"].get("bankIgn"))
            imm = [c for c in cs.values() if c["partner"].startswith("Immo")][0]; print("Immo:", imm["cat"], imm["amount"], imm["holders"])
            stv = [c for c in cs.values() if c["partner"].startswith("Steuer")][0]; print("Steuer:", stv["cat"], stv.get("noCancel"))
            # zweiter Import: Serafe ausgeblendet, angelegte jetzt «bereits erfasst»
            pg.click('.tabbar button[data-tab="set"]'); pg.set_input_files("#bankFile", S + "ch_postfinance.csv"); pg.wait_for_timeout(600)
            pg.screenshot(path=f"{OUT}/4_zweiter_import.png")
            print("Zweiter Import:", pg.inner_text("#bkBody")[:400].replace("\n", " | "))
            pg.click("#bkX")
            # Datei, die kein Auszug ist
            open(OUT + "/x.csv", "w").write("a;b;c\n1;2;3\n")
            pg.set_input_files("#bankFile", OUT + "/x.csv"); pg.wait_for_timeout(400)
            print("Fehlermeldung:", pg.inner_text("#askT"))
        ctx.close()
    b.close()
print("Fehler:", errs or "keine")
