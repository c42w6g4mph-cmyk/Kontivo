"""Bedienablauf Kontoauszug-Import (Playwright): Datei wählen, Zeile bearbeiten, ausblenden, anlegen, zweiter Import, falsche Datei.
Prüft das Ergebnis mit asserts (Exit-Code 1 bei Abweichung) und legt Screenshots in KONTIVO_SHOTS ab (Standard /tmp/kontivo-bank-ui).
Aufruf im Repo-Ordner:  python3 -m http.server 8765 &  python3 tests/bank/ui_flow.py"""
import json, os, re, sys
from playwright.sync_api import sync_playwright
URL = os.environ.get("KONTIVO_URL", "http://localhost:8765/index.html")
OUT = os.environ.get("KONTIVO_SHOTS", "/tmp/kontivo-bank-ui")
os.makedirs(OUT, exist_ok=True)
S = os.path.join(os.path.dirname(os.path.abspath(__file__)), "samples") + "/"
st = {"settings": {"home": "CHF", "onboarded": 9, "holders": ["Sinan", "Lara"], "rateCheckedAt": 9999999999999},
      "contracts": {"a": {"partner": "CSS", "label": "Krankenkasse", "cat": "Versicherung", "amount": 389.60, "cur": "CHF", "cycle": 1, "due": "2026-11-01", "status": "active", "holders": ["Sinan"]},
                    "b": {"partner": "Netflix", "label": "Streaming", "cat": "Abos & Medien", "amount": 18.90, "cur": "CHF", "cycle": 1, "due": "2026-10-12", "status": "active", "holders": ["Sinan", "Lara"]}},
      "incomes": {}}
errs, fails = [], []
def check(ok, what):
    print(("✓" if ok else "✗"), what)
    if not ok: fails.append(what)
def set_amount(pg, sel, v):
    # nicht pg.fill: der focusin-Handler setzt den Cursor ans Ende, fill würde an den alten Wert anhängen
    pg.evaluate("([s,v])=>{var e=document.querySelector(s);e.value=v;e.dispatchEvent(new Event('input',{bubbles:true}));e.dispatchEvent(new Event('change',{bubbles:true}));}", [sel, v])
def load(pg, f):
    pg.set_input_files("#bankFile", f); pg.wait_for_selector("#bkBody .bkr, #bkBody .bkempty", timeout=20000)
    pg.wait_for_function("()=>{var b=window.KontivoBank().bk();return b&&!b.loading;}", timeout=20000); pg.wait_for_timeout(300)
with sync_playwright() as p:
    b = p.chromium.launch()
    for theme in ["light", "dark"]:
        ctx = b.new_context(viewport={"width": 393, "height": 852}, device_scale_factor=2, color_scheme=theme, has_touch=True)
        ctx.add_init_script("window.__KONTIVO_TODAY='2026-10-08';")
        ctx.route(re.compile(r"frankfurter\.|open\.er-api\.com"), lambda r: r.abort())  # kein Live-Kursabruf
        pg = ctx.new_page(); pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.goto(URL)
        pg.evaluate("s=>localStorage.setItem('vertraege.v1',s)", json.dumps(st)); pg.reload(); pg.wait_for_timeout(500)
        pg.click('.tabbar button[data-tab="set"]'); pg.wait_for_timeout(300)
        if theme == "light": pg.screenshot(path=f"{OUT}/0_mehr.png")
        load(pg, S + "ch_postfinance.csv")
        check(pg.is_visible("#sheetBank.on"), f"{theme}: Vorschläge offen")
        pg.screenshot(path=f"{OUT}/1_liste_{theme}.png")
        # Swisscom öffnen: Vorschlag öffnet das normale Vertragsformular
        pg.click('#bkBody .bkmain:has-text("Swisscom")'); pg.wait_for_selector("#sheetForm.on"); pg.wait_for_timeout(300)
        set_amount(pg, "#fAmt", "81.50"); pg.select_option("#fCycle", "1")
        check(pg.input_value("#fAmt") == "81.50", f"{theme}: Betrag im Formular gesetzt")
        pg.screenshot(path=f"{OUT}/2_bearbeiten_{theme}.png")
        if theme == "light":
            pg.click("#saveForm"); pg.wait_for_timeout(400)  # Sichern → zurück zur Liste
            check(pg.is_visible("#sheetBank.on") and not pg.is_visible("#sheetForm.on"), "Sichern führt zurück zur Liste")
            # Rundfunkgebühr (Vielleicht) öffnen → Nie mehr vorschlagen
            pg.click('#bkBody .bkmain:has-text("Rundfunkgebühr")'); pg.wait_for_timeout(400); pg.click("#fBankIgn"); pg.wait_for_timeout(300)
            check("Rundfunkgebühr" not in pg.inner_text("#bkBody"), "Rundfunkgebühr ausgeblendet")
            # Mobiliar ankreuzen
            pg.click('#bkBody .bkr:has-text("Die Mobiliar") [data-bkyes]'); pg.wait_for_timeout(200)
            # geführte Schritte: Weiter bis «… übernehmen»
            for _ in range(4):
                if pg.get_attribute("#bkGo", "data-mode") == "go": break
                pg.click("#bkGo"); pg.wait_for_timeout(250)
            btn = pg.inner_text("#bkGo"); print("  Knopf:", btn)
            check(pg.get_attribute("#bkGo", "data-mode") == "go" and "übernehmen" in btn, "letzter Schritt: «… übernehmen»")
            pg.click("#bkGo"); pg.wait_for_timeout(500)
            # nach 900 ms fragt Kontivo «Fast fertig!» (fehlende Angaben) – mit «Später» schliessen
            pg.wait_for_selector("#sheetAsk.on", timeout=5000)
            check(pg.inner_text("#askT") == "Fast fertig!", "Rückfrage «Fast fertig!»")
            pg.click("#askNo"); pg.wait_for_timeout(400)
            pg.screenshot(path=f"{OUT}/3_nachher.png")
            d = pg.evaluate("()=>JSON.parse(localStorage.getItem('vertraege.v1'))")
            cs = d["contracts"]; names = sorted(c["partner"] for c in cs.values())
            print("  Verträge:", names)
            check(names == ["CSS", "Die Mobiliar", "Energie Kreuzlingen", "Immo Seeblick AG", "Netflix", "Spotify", "Steuerverwaltung des Kantons Thurgau", "Swisscom"], "angelegte Verträge")
            sw = [c for c in cs.values() if c["partner"] == "Swisscom"][0]
            print("  Swisscom:", sw["amount"], sw["holders"], sw["cycle"], sw.get("cancF"), sw.get("notice"), sw.get("noticeU"), sw.get("due"))
            check(sw["amount"] == 81.5 and sw["cycle"] == 1 and sw["holders"] == ["Sinan"], "Swisscom mit bearbeitetem Betrag 81.50, monatlich, Sinan")
            print("  CSS prices:", cs["a"].get("prices"))
            check(cs["a"].get("prices") == [{"from": "2026-01-01", "amount": 412.3}], "CSS: neuer Preis ab 01.01.2026")
            check(d["settings"].get("bankIgn") and any("rundfunk" in k.lower() for k in d["settings"]["bankIgn"]), "Rundfunkgebühr in bankIgn")
            imm = [c for c in cs.values() if c["partner"].startswith("Immo")][0]; print("  Immo:", imm["cat"], imm["amount"], imm["holders"])
            check(imm["cat"] == "Wohnen" and imm["amount"] == 1850, "Immo Seeblick: Wohnen 1850")
            stv = [c for c in cs.values() if c["partner"].startswith("Steuer")][0]; print("  Steuer:", stv["cat"], stv.get("noCancel"))
            check(stv["cat"] == "Steuern & Gebühren", "Steuer: Kategorie Steuern & Gebühren")
            # zweiter Import: Rundfunkgebühr ausgeblendet, angelegte jetzt «bereits erfasst»
            pg.click('.tabbar button[data-tab="set"]'); load(pg, S + "ch_postfinance.csv")
            pg.screenshot(path=f"{OUT}/4_zweiter_import.png")
            t2 = pg.inner_text("#bkBody"); print("  Zweiter Import:", t2[:400].replace("\n", " | "))
            check("Keine neuen Fixkosten" in t2 and "8 Verträge sind schon in Kontivo" in t2 and "1 ausgeblendeter Vorschlag" in t2 and "Rundfunkgebühr" not in t2,
                  "zweiter Import: nichts Neues, 8 erfasst, Rundfunkgebühr bleibt ausgeblendet")
            # Abbrechen: wegen des ausgeblendeten Vorschlags fragt Kontivo nach
            pg.click("#bkX"); pg.wait_for_selector("#sheetAsk.on", timeout=5000)
            check(pg.inner_text("#askT") == "Import abbrechen?", "Abbrechen fragt nach")
            pg.click("#askOk"); pg.wait_for_timeout(400)
            check(not pg.is_visible("#sheetBank.on") and not pg.is_visible("#sheetAsk.on"), "Import geschlossen")
            # Datei, die kein Auszug ist
            open(OUT + "/x.csv", "w").write("a;b;c\n1;2;3\n")
            pg.set_input_files("#bankFile", OUT + "/x.csv"); pg.wait_for_selector("#sheetAsk.on", timeout=10000); pg.wait_for_timeout(300)
            print("  Fehlermeldung:", pg.inner_text("#askT"))
            check(pg.inner_text("#askT") == "Kein Kontoauszug", "falsche Datei: «Kein Kontoauszug»")
        ctx.close()
    b.close()
check(not errs, "keine JS-Fehler" + ("" if not errs else ": " + "; ".join(errs)))
print("Alles gut" if not fails else f"{len(fails)} Fehler"); sys.exit(1 if fails else 0)
