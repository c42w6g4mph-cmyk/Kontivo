"""Erzeugt golden_form.json: welcher Vertrag bzw. welche Einnahme gespeichert wird, wenn man das Formular so ausfüllt.
Hält die Regeln beim Sichern fest (Vertragsart → end/renew/cancTerm/notice/noCancel/noWatch/trial, Kündigungsweg → cancUrl,
Aufteilung, Preisänderung, Sonderzahlung, Zahlenformat der Eingabe). Referenz für das SwiftUI-Formular, abgelesen aus der laufenden App.
Aufruf im Repo-Ordner:  python3 -m http.server 8765 &  python3 tests/make_golden_form.py   (anderer Port über KONTIVO_URL)
Jeder Fall startet mit leeren Daten (Personen Sinan und Lara, Hauptwährung CHF), Stichtag 2026-10-24.
Ergebnis je Fall: gespeicherter Eintrag ohne Zeitstempel t; "error" = Meldung, wenn nicht gespeichert wurde."""
import json, os
from playwright.sync_api import sync_playwright
D = os.path.dirname(os.path.abspath(__file__))
URL = os.environ.get("KONTIVO_URL", "http://localhost:8765/index.html")
BASE = {"settings": {"home": "CHF", "rates": {"EUR": 0.94, "USD": 0.8}, "holders": ["Sinan", "Lara"], "onboarded": 9, "rateCheckedAt": 9999999999999, "dataVer": 2},
        "contracts": {}, "incomes": {}, "vars": {}}
def c(label, partner, amount, cat, *more):
    return [("fill", "#fLabel", label), ("fill", "#fPartner", partner), ("key", "Tab"), ("fill", "#fAmt", amount), ("cat", cat)] + list(more)
CASES = {
 "flexibel-minimal": c("Streaming", "Testanbieter Eins", "12.90", "Abos & Medien"),
 "flexibel-quartal-email-pflicht": c("Krankenkasse", "Testkasse", "389.90", "Versicherung",
    ("select", "#fCycle", "3"), ("click", '#fNoticeC [data-nc="3"]'), ("select", "#fTermP", "q"), ("click", '#fCancT [data-cv="E-Mail"]'),
    ("fill", "#fCancMail", "kuendigung@example.ch"), ("check", "#fMand", True)),
 "mindestlaufzeit-2j-verlaengerung": c("Internet", "Testnetz", "59", "Mobilfunk & Internet",
    ("click", '#termSeg [data-tm="fixed"]'), ("fill", "#fStart", "2026-01-01"), ("click", '#fTermMC [data-tmm="24"]'), ("select", "#fRenew", "12"),
    ("click", '#fNoticeC [data-nc="3"]'), ("click", '#fCancT [data-cv="Brief"]')),
 "mindestlaufzeit-ohne-verlaengerung": c("Leasing", "Testleasing", "349", "Mobilität",
    ("click", '#termSeg [data-tm="fixed"]'), ("fill", "#fStart", "2024-07-01"), ("click", '#fTermMC [data-tmm="36"]')),
 "probeabo-1-monat": c("Musik", "Testmusik", "10.95", "Abos & Medien",
    ("click", '#termSeg [data-tm="trial"]'), ("click", '#fTrialD [data-trd="1m"]'), ("fill", "#fStart", "2026-10-24")),
 "nicht-kuendbar": c("Rundfunk", "Testgebühr", "335", "Wohnen", ("click", '#termSeg [data-tm="tax"]'), ("select", "#fCycle", "12")),
 "steuern": c("Staatssteuer", "Teststeueramt", "5400", "Steuern & Gebühren", ("select", "#fCycle", "12")),
 "eur-zahlungsart-kontakt": c("Strom", "Teststrom", "1.234,50", "Energie & Wasser",
    ("select", "#fCur", "EUR"), ("select", "#fPayM", "Lastschrift (LSV/SEPA)"), ("fill", "#fPayA", "Visa …4417"),
    ("fill", "#fCustNo", "K-123"), ("fill", "#fContrNo", "V-456"), ("fill", "#fWeb", "teststrom.de"), ("fill", "#fTel", "+49 30 123"),
    ("fill", "#fMail", "service@teststrom.de"), ("fill", "#fNote", "Zählerstand im Januar")),
 "online-link": c("Fitness", "Teststudio", "79", "Freizeit & Sport", ("click", '#fNoticeC [data-nc="1"]'), ("select", "#fTermP", "m"),
    ("click", '#fCancT [data-cv="Online / Kundenkonto"]'), ("fill", "#fCancUrl", "konto.teststudio.ch")),
 "online-dann-brief": c("Zeitung", "Testzeitung", "29", "Abos & Medien", ("click", '#fCancT [data-cv="Online / Kundenkonto"]'),
    ("fill", "#fCancUrl", "abo.testzeitung.ch"), ("click", '#fCancT [data-cv="Brief"]')),
 "jahresabo-ende-periode": c("Cloud", "Testcloud", "99", "Abos & Medien", ("select", "#fCycle", "12")),
 "zwei-personen-gleich": c("Miete", "Testverwaltung", "2400", "Wohnen", ("holder", "Lara")),
 "preisaenderung-geplant": c("Handy", "Testmobil", "45", "Mobilfunk & Internet", ("click", "#pOpen"), ("fill", "#pFrom", "2027-01-01"), ("fill", "#pAmt", "49.90"), ("key", "Tab")),
 "sonderzahlung-und-gutschrift": c("Heizung", "Testenergie", "120", "Energie & Wasser",
    ("click", "#xOpen"), ("fill", "#xDate", "2026-12-15"), ("fill", "#xAmt", "250"), ("fill", "#xNote", "Nachzahlung"), ("click", "#xAdd"),
    ("click", "#xOpen"), ("click", '#xKind [data-xk="cr"]'), ("fill", "#xDate", "2027-03-01"), ("fill", "#xAmt", "40"), ("click", "#xAdd")),
 "fehler-ohne-kategorie": [("fill", "#fLabel", "Ohne Kategorie"), ("fill", "#fAmt", "10")],
 "fehler-ohne-betrag": [("fill", "#fLabel", "Ohne Betrag"), ("cat", "Sonstiges")],
 "fehler-mindestlaufzeit-ohne-ende": c("Vertrag", "Testfirma", "20", "Sonstiges", ("click", '#termSeg [data-tm="fixed"]')),
}
INC = {
 "lohn-monatlich": [("fill", "#iName", "Testarbeitgeber"), ("fill", "#iLabel", "Lohn"), ("fill", "#iAmt", "6'800.00")],
 "einmalig": [("fill", "#iName", "Testkasse"), ("fill", "#iLabel", "Rückerstattung"), ("fill", "#iAmt", "350"), ("select", "#iCycle", "0")],
 "eur-mit-ende": [("fill", "#iName", "Testmieter"), ("fill", "#iLabel", "Vermietung"), ("fill", "#iAmt", "800"), ("select", "#iCur", "EUR"),
    ("fill", "#iStart", "2026-05-01"), ("fill", "#iEnd", "2027-04-30")],
}
def run(pg, acts):
    for a in acts:
        k = a[0]
        if k == "fill": pg.fill(a[1], a[2]); pg.dispatch_event(a[1], "change")
        elif k == "select": pg.select_option(a[1], a[2]);
        elif k == "click": pg.click(a[1])
        elif k == "check": pg.set_checked(a[1], a[2])
        elif k == "key": pg.keyboard.press(a[1])
        elif k == "cat": pg.click("#fCats"); pg.wait_for_timeout(250); pg.click('#pickList [data-pv="%s"]' % a[1])
        elif k == "holder": pg.click('#fHolders button:text-is("%s")' % a[1])
        pg.wait_for_timeout(120)
res = {"generated_from": "Kontivo Web-App", "today": "2026-10-24", "contracts": {}, "incomes": {}}
with sync_playwright() as p:
    b = p.chromium.launch()
    for part, cases, open_sel, save in [("contracts", CASES, '[data-am="form"]', "#saveForm"), ("incomes", INC, '[data-am="inc"]', "#iSave")]:
        for name, acts in cases.items():
            ctx = b.new_context(viewport={"width": 393, "height": 852}, locale="de-CH", timezone_id="Europe/Zurich", reduced_motion="reduce")
            ctx.add_init_script("window.__KONTIVO_TODAY='2026-10-24';")
            ctx.route("**/*", lambda r: r.continue_() if r.request.url.startswith(("http://localhost", "data:", "blob:")) else r.abort())
            pg = ctx.new_page(); errs = []; pg.on("pageerror", lambda e: errs.append(str(e)))
            pg.goto(URL); pg.evaluate("s=>localStorage.setItem('vertraege.v1',s)", json.dumps(BASE)); pg.reload(); pg.wait_for_timeout(500)
            pg.evaluate("()=>{var s=document.getElementById('splash');if(s)s.remove();}")
            pg.click("#addBtn"); pg.wait_for_timeout(250); pg.click(open_sel); pg.wait_for_timeout(450)
            run(pg, acts); pg.click(save); pg.wait_for_timeout(500)
            d = json.loads(pg.evaluate("()=>localStorage.getItem('vertraege.v1')") or "{}")
            items = list((d.get(part) or {}).values())
            if items: out = {k: v for k, v in items[0].items() if k != "t"}
            else: out = {"error": pg.evaluate("()=>document.getElementById('toast').textContent")}
            if errs: out["jsErrors"] = errs
            res[part][name] = out; ctx.close()
    b.close()
json.dump(res, open(os.path.join(D, "golden_form.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("golden_form.json:", len(res["contracts"]), "Verträge,", len(res["incomes"]), "Einnahmen")
