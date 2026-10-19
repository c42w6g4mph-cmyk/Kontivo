#!/usr/bin/env python3
"""Web-Gegenstücke zu den Swift-Simulatorfotos (CI, ci-logs:shots-<branch>/).

Für jedes Swift-Foto wird die Web-App (index.html im Repo-Wurzelordner) mit denselben Daten
(tests/visual/demo_web.json = ios/Kontivo/App/DemoData.swift im Format von localStorage['vertraege.v1']),
demselben Stichtag (window.__KONTIVO_TODAY = 2026-10-03, wie -uiToday-Standard in UITestHooks.swift),
derselben Darstellung (hell/dunkel nach Fotoname) und derselben Ansicht (über Klicks) fotografiert.

Aufruf (im Repo-Wurzelordner):
    python3 tests/visual/web_shots.py --swift /home/claude/visual/swift --out /home/claude/visual/web [--only 03-vertraege,08-detail]

- startet selbst einen lokalen http.server (Port --port, Standard 8765) im Repo-Wurzelordner
- Externe Netzaufrufe werden abgefangen (nur localhost erlaubt)
- Viewport 402×874 pt (iPhone 17 Pro), device_scale_factor 3, Sicherheitsabstände wie iPhone (oben 62, unten 34)
  über CDP Emulation.setSafeAreaInsetsOverride; iPad: 1032×1376, Abstände 24/20
- Ergebnis wird auf die Pixelgrösse des Swift-Fotos gebracht (Swift-Fotos sind mit sips -Z 1400 verkleinert)
- Ansichten ohne 1:1-Gegenstück im Web: siehe SKIP (Grund wird in <out>/_skipped.json geschrieben)
"""
import argparse
import contextlib
import functools
import http.server
import io
import json
import os
import socketserver
import sys
import threading

from PIL import Image
from playwright.sync_api import sync_playwright

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TODAY = "2026-10-03"  # UITestHooks.swift: -uiToday Standard

PHONE = dict(w=402, h=874, top=62, bottom=34)
PAD = dict(w=1032, h=1376, top=24, bottom=20)

# Fotos ohne Web-Gegenstück (Name -> Grund)
SKIP = {
    "15-verwalten": "Web hat keine eigene Ansicht «Verwalten» (Swift-Blatt mit Vertragspartner/Personen/Kategorien/Vollständigkeit); im Web ist das die Gruppe «Verwalten» in Mehr (siehe 07-mehr).",
    "c5-bericht-pdf": "Web erzeugt das PDF und gibt es an den Browser/Download weiter; keine In-App-Dokumentansicht wie Swift (QuickLook-ähnliche Vorschau).",
}


# ---------------------------------------------------------------- Daten

def demo_data():
    with open(os.path.join(HERE, "demo_web.json"), encoding="utf-8") as f:
        return json.load(f)


def empty_data(onboarded):
    # Swift: AppData.initial(homeCurrency: .CHF), onboarded 1 (bei -uiEmpty) bzw. 0 (-uiOnboarding)
    d = {"settings": {"home": "CHF", "holders": ["Ich"]}, "contracts": {}, "incomes": {}}
    if onboarded:
        d["settings"]["onboarded"] = 1
    return d


def add_days(iso, n):
    import datetime
    d = datetime.date.fromisoformat(iso) + datetime.timedelta(days=n)
    return d.isoformat()


def contract_key(d, label):
    for k, c in d["contracts"].items():
        if c.get("label") == label:
            return k
    raise KeyError(label)


def seed(d, seeds):
    """Swift -uiSeed (ContractsShared.swift CTUITestSeed) und -uiDeadlines (DeadlinesTab.swift DLUITestSeed)."""
    for s in seeds:
        if s == "skr":
            d["contracts"][contract_key(d, "Krankenkasse")]["prices"] = [{"from": "2027-01-01", "amount": 430}]
        elif s == "endsself":
            d["contracts"][contract_key(d, "Fitnessabo")].pop("renew", None)
        elif s == "review":
            d["settings"]["lastReview"] = add_days(TODAY, -120)
        elif s == "marked":
            d["contracts"][contract_key(d, "Halbtax")]["review"] = {"v": "kill", "at": TODAY}
        elif s == "mailcheck":
            c = d["contracts"][contract_key(d, "Handy")]
            c.update({"cancF": "E-Mail", "mail": "kuendigung@example.ch", "custNo": "", "contrNo": ""})
    return d


def bank_sample_csv():
    src = open(os.path.join(ROOT, "ios/Kontivo/Import/BankSample.swift"), encoding="utf-8").read()
    return src.split('#"""', 1)[1].split('"""#', 1)[0].lstrip("\n").encode("utf-8")


# ---------------------------------------------------------------- Seite

class Ctx:
    def __init__(self, page):
        self.pg = page

    def js(self, code, arg=None):
        return self.pg.evaluate(code, arg)

    def wait(self, ms):
        self.pg.wait_for_timeout(ms)

    def click(self, sel, ms=450):
        """Klick wie mit dem Finger; fällt auf element.click() zurück, wenn das Element verdeckt ist."""
        loc = self.pg.locator(sel).first
        try:
            loc.click(timeout=2500)
        except Exception:
            self.js("s=>{const e=document.querySelector(s); if(!e) throw new Error('fehlt: '+s); e.click();}", sel)
        self.wait(ms)

    def click_text(self, text, within="body", ms=450, exact=True):
        loc = self.pg.locator(within).get_by_text(text, exact=exact).first
        try:
            loc.click(timeout=2500)
        except Exception:
            loc.evaluate("e=>e.click()")
        self.wait(ms)

    def tab(self, t):
        self.click('.tabbar [data-tab="%s"]' % t, 500)

    def scroll_to(self, sel, block="start", offset=0, container=None):
        self.js("""([s,b,o,c])=>{const e=document.querySelector(s); if(!e) throw new Error('fehlt: '+s);
            const box=c?document.querySelector(c):null;
            if(box){box.scrollTop+= e.getBoundingClientRect().top-box.getBoundingClientRect().top-o;}
            else{window.scrollTo(0, window.scrollY+e.getBoundingClientRect().top-o);}}""", [sel, block, offset, container])
        self.wait(400)

    def scroll_bottom(self, container=None):
        self.js("c=>{const b=c?document.querySelector(c):null; if(b) b.scrollTop=b.scrollHeight; else window.scrollTo(0,document.body.scrollHeight);}", container)
        self.wait(400)


TABS = {"contracts": "list", "costs": "stat", "budget": "budget", "deadlines": "term", "more": "set"}

# ---------------------------------------------------------------- Ansichten
# Jede Ansicht: dict(data="demo"|"empty"|"onb", seeds=[...], device="phone"|"pad", steps=function(ctx))
# Hinweise zu Swift-Auswahl (UITestHooks.openUITestSheet):
#   detail/edit: erster aktiver Vertrag mit Vertragspartner = «Handy» (Swisscom)
#   letter: erster aktiver Vertrag mit Kündigungsweg Brief = «Krankenkasse» (CSS, mit Adresse)
#   cancelpick: erster aktiver Vertrag ohne Kündigungsweg = «Handy»
#   incomeDetail/incomeEdit: erste Einnahme mit Preisänderungen = «Lohn» (Pharma AG)
#   sender: erste Person = «Sinan»


def open_contract(c, label):
    c.click_text(label, within="#view", ms=700)


def v_tab(t):
    def f(c):
        c.tab(TABS[t])
    return f


def v_detail(label="Handy", tab="contracts"):
    def f(c):
        c.tab(TABS[tab])
        open_contract(c, label)
    return f


def v_form(c):
    c.tab("list")
    c.click("#addBtn", 500)
    c.click('#addMenu [data-am="form"]', 900)


def v_edit(c):
    v_detail()(c)
    c.click_text("Bearbeiten", within="#sheetDetail", ms=900)


def v_income_new(c):
    c.tab("list")
    c.click("#addBtn", 500)
    c.click('#addMenu [data-am="inc"]', 900)


def v_incomes(c):
    c.tab("budget")
    # Link «Alle Einnahmen» per element.click(), damit die Seite oben bleibt (Swift: Budget oben, Blatt darüber)
    c.js("()=>{const b=[...document.querySelectorAll('#view button, #view a')].find(e=>/Alle Einnahmen/.test(e.textContent)); b.click();}")
    c.wait(900)


def v_income_detail(c):
    v_incomes(c)
    c.click('#pickList [data-inc="i1"]', 900)  # «Lohn» Pharma AG


def v_income_edit(c):
    v_income_detail(c)
    c.click('#sheetDetail [data-iact="edit"]', 900)


def v_letter(c):
    c.tab("term")
    # Fristen → «Wechseln» bei Krankenkasse (CSS) öffnet das Kündigungsschreiben direkt
    c.click('[data-kill="c"]', 900)
    c.click_text("Kündigungsschreiben erstellen", ms=1000, exact=False)


def v_cancelpick(c):
    v_detail("Handy")(c)
    c.click_text("Kündigen", within="#sheetDetail", ms=900, exact=False)


def v_md(which):
    def f(c):
        c.tab("set")
        if which == "qual":
            c.click('[data-md="qual"]', 900)
        elif which == "sender":
            c.click('[data-md="holder"]', 900)
            c.click_text("Sinan", within="#sheetMd", ms=900, exact=False)
            c.click_text("Absender", within="#sheetMd", ms=900, exact=False)
        else:
            c.click('[data-md="%s"]' % which, 900)
    return f


def v_completeness(c):
    c.tab("set")
    c.click("#vkOpen", 900)


def v_report(c):
    c.tab("stat")
    c.click('[data-rep]', 900)


def bank_ready(c):
    c.pg.wait_for_function("()=>{const b=document.getElementById('bkGo'); return b && !b.disabled && !/warten/i.test(b.textContent);}", timeout=30000)
    c.wait(500)


def v_bank(step=None):
    """Swift -uiBankSample: eingebaute PostFinance-CSV (BankSample.swift) -> im Web über die Dateiauswahl von «Aus Kontoauszug»."""
    def f(c):
        c.pg.set_input_files("#bankFile", files=[{"name": "postfinance.csv", "mimeType": "text/csv", "buffer": bank_sample_csv()}])
        bank_ready(c)
        n = {"inc": 1, "term": 2}.get(step, 0)
        for _ in range(n):
            c.click("#bkGo", 900)
            bank_ready(c)
    return f


def v_onb(page):
    def f(c):
        for _ in range(page):
            c.click("#onb .obnext, #onb [data-ob=next]", 700)
    return f


def v_scroll(tab, target, y):
    """Swift -uiScrollTo <id> (KBShared.swift, anchor .top): Element-Oberkante auf dieselbe Höhe (pt) wie im Swift-Foto."""
    def f(c):
        c.tab(tab)
        c.scroll_to(target, offset=y)
    return f


def v_more_bottom(c):
    c.tab("set")
    c.scroll_bottom()


def v_deadlines_open(c):
    # Swift -uiDeadlines review,folds,end: Quartals-Check fällig, Klappgruppen offen, ans Ende gescrollt
    c.tab("term")
    c.click('[data-tfold="any"]', 500)
    c.click('[data-tfold="unw"]', 500)
    c.scroll_bottom()


VIEWS = {
    "01-onboarding": dict(data="onb", steps=v_onb(0)),
    "02-leer-vertraege": dict(data="empty", steps=v_tab("contracts")),
    "03-vertraege": dict(steps=v_tab("contracts")),
    "04-kosten": dict(steps=v_tab("costs")),
    "05-budget": dict(steps=v_tab("budget")),
    "06-fristen": dict(steps=v_tab("deadlines")),
    "07-mehr": dict(steps=v_tab("more")),
    "08-detail": dict(steps=v_detail()),
    "09-formular": dict(steps=v_form),
    "10-bearbeiten": dict(steps=v_edit),
    "10b-detail-sonderkuendigung": dict(seeds=["skr"], steps=v_detail("Krankenkasse")),
    "11-einnahme": dict(steps=v_income_new),
    "12-einnahmen": dict(steps=v_incomes),
    "12b-einnahme-ansicht": dict(steps=v_income_detail),
    "13-brief": dict(steps=v_letter),
    "14-kuendigungsweg": dict(steps=v_cancelpick),
    "16-vertragspartner": dict(steps=v_md("partner")),
    "17-inhaber": dict(steps=v_md("holder")),
    "18-absender": dict(steps=v_md("sender")),
    "19-kategorien": dict(steps=v_md("cat")),
    "20-datenqualitaet": dict(steps=v_md("qual")),
    "21-leer-kosten": dict(data="empty", steps=v_tab("costs")),
    "22-leer-fristen": dict(data="empty", steps=v_tab("deadlines")),
    "23-dunkel-vertraege": dict(steps=v_tab("contracts")),
    "24-dunkel-kosten": dict(steps=v_tab("costs")),
    "25-dunkel-detail": dict(steps=v_detail()),
    "26-ipad-vertraege": dict(device="pad", steps=v_tab("contracts")),
    "27-ipad-kosten": dict(device="pad", steps=v_tab("costs")),
    "28-ipad-formular": dict(device="pad", steps=v_form),
    "29-dunkel-mehr": dict(steps=v_tab("more")),
    "30-dunkel-verwalten": dict(steps=v_md("partner")),
    "31-splash": dict(data="empty", splash=True, steps=None),
    "32-mehr-unten": dict(steps=v_more_bottom),
    "33-vollstaendigkeit": dict(steps=v_completeness),
    "34-leer-budget": dict(data="empty", steps=v_tab("budget")),
    "41-fristen-vorgemerkt": dict(seeds=["marked", "endsself"], steps=v_tab("deadlines")),
    "42-fristen-offen": dict(seeds=["review"], steps=v_deadlines_open),
    "44-dunkel-fristen": dict(steps=v_tab("deadlines")),
    "45-dunkel-fristen-offen": dict(seeds=["review"], steps=v_deadlines_open),
    "46-dunkel-leer-fristen": dict(data="empty", steps=v_tab("deadlines")),
    "c1-kosten-liste": dict(steps=v_scroll("stat", "#view > .grp > .mrows", 120)),
    # Swift: Gruppe (Kopf 20 + 23.4) oben am Sicherheitsabstand 62 → Karte bei 105.4
    "c2-kosten-preistreiber": dict(steps=v_scroll("stat", "#view > .grp.ptgrp > .dcard", 105.4)),
    "c3-budget-listen": dict(steps=v_scroll("budget", "#view .grp > .ilist", 105.4)),
    "c4-bericht": dict(steps=v_report),
    "c6-einnahme-bearbeiten": dict(steps=v_income_edit),
    "c7-dunkel-budget": dict(steps=v_tab("budget")),
    "c8-dunkel-preistreiber": dict(steps=v_scroll("stat", "#view > .grp.ptgrp > .dcard", 105.4)),
    "i30-import-fixkosten": dict(data="empty", steps=v_bank()),
    "i31-import-einnahmen": dict(data="empty", steps=v_bank("inc")),
    "i32-import-fristen": dict(data="empty", steps=v_bank("term")),
    "i33-import-zuordnen": dict(steps=v_bank()),
    "i34-dunkel-import": dict(steps=v_bank()),
    "i35-dunkel-import-fristen": dict(data="empty", steps=v_bank("term")),
}
for _p in range(1, 8):
    VIEWS["40-onb-%d" % _p] = dict(data="onb", steps=v_onb(_p))
for _p in range(0, 8):
    VIEWS["43-dunkel-onb-%d" % _p] = dict(data="onb", steps=v_onb(_p))


def is_dark(name):
    return "dunkel" in name


# ---------------------------------------------------------------- Ablauf

def serve(port):
    class Quiet(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *a):
            pass

    handler = functools.partial(Quiet, directory=ROOT)
    socketserver.TCPServer.allow_reuse_address = True
    httpd = socketserver.ThreadingTCPServer(("127.0.0.1", port), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def shoot(browser, port, name, spec, out, swift_dir, debug=False):
    dev = PAD if spec.get("device") == "pad" else PHONE
    ctx = browser.new_context(viewport={"width": dev["w"], "height": dev["h"]}, device_scale_factor=3,
                              color_scheme="dark" if is_dark(name) else "light", locale="de-CH",
                              timezone_id="Europe/Zurich", has_touch=True, is_mobile=False)
    ctx.route("**/*", lambda r: r.continue_() if r.request.url.startswith(("http://localhost", "http://127.0.0.1")) else r.abort())
    kind = spec.get("data", "demo")
    if kind == "demo":
        data = seed(demo_data(), spec.get("seeds", []))
    else:
        data = empty_data(onboarded=(kind == "empty"))
    # nur beim ersten Laden setzen (die App speichert danach selbst)
    ctx.add_init_script("""(()=>{window.__KONTIVO_TODAY=%s;
        if(!sessionStorage.getItem('__vt')){sessionStorage.setItem('__vt','1');localStorage.clear();localStorage.setItem('vertraege.v1',%s);}})();"""
                        % (json.dumps(TODAY), json.dumps(json.dumps(data, ensure_ascii=False))))
    pg = ctx.new_page()
    cdp = ctx.new_cdp_session(pg)
    cdp.send("Emulation.setSafeAreaInsetsOverride", {"insets": {"top": dev["top"], "bottom": dev["bottom"], "left": 0, "right": 0}})
    errs = []
    pg.on("pageerror", lambda e: errs.append(str(e)))
    pg.goto("http://localhost:%d/index.html" % port)
    c = Ctx(pg)
    if spec.get("splash"):
        # Swift -uiSplashHold: Intro bei 1.7 s angehalten -> Web-Animationen bei 1700 ms anhalten
        pg.wait_for_timeout(300)
        c.js("()=>{for(const a of document.getAnimations()){a.pause();a.currentTime=1700;}}")
        pg.wait_for_timeout(200)
    else:
        pg.wait_for_timeout(700)
        c.js("()=>{const s=document.getElementById('splash'); if(s) s.remove();}")
        pg.wait_for_timeout(500)
        if spec.get("steps"):
            spec["steps"](c)
        pg.wait_for_timeout(700)
    png = pg.screenshot()
    ctx.close()
    im = Image.open(io.BytesIO(png)).convert("RGB")
    sw = os.path.join(swift_dir, name + ".png") if swift_dir else None
    if sw and os.path.exists(sw):
        im = im.resize(Image.open(sw).size, Image.LANCZOS)
    im.save(os.path.join(out, name + ".png"))
    return errs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--swift", default="/home/claude/visual/swift", help="Ordner mit den Swift-Fotos (für Namen und Pixelgrösse)")
    ap.add_argument("--out", default="/home/claude/visual/web")
    ap.add_argument("--only", default="", help="Komma-Liste von Fotonamen")
    ap.add_argument("--port", type=int, default=8765)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    names = sorted(VIEWS.keys() | SKIP.keys())
    if os.path.isdir(a.swift):
        names = sorted(f[:-4] for f in os.listdir(a.swift) if f.endswith(".png"))
    if a.only:
        names = [n for n in names if n in a.only.split(",")]
    httpd = serve(a.port)
    skipped, failed = {}, {}
    with sync_playwright() as p:
        browser = p.chromium.launch()
        for n in names:
            if n in SKIP:
                skipped[n] = SKIP[n]
                print("skip", n)
                continue
            if n not in VIEWS:
                skipped[n] = "keine Web-Ansicht definiert"
                print("skip (unbekannt)", n)
                continue
            try:
                errs = shoot(browser, a.port, n, VIEWS[n], a.out, a.swift)
                print("ok  ", n, ("JS-Fehler: " + "; ".join(errs)) if errs else "")
            except Exception as e:
                failed[n] = str(e).splitlines()[0]
                print("FEHL", n, failed[n])
        browser.close()
    httpd.shutdown()
    # mit früheren Läufen zusammenführen (Teilläufe mit --only)
    path = os.path.join(a.out, "_skipped.json")
    old = {"skipped": {}, "failed": {}}
    with contextlib.suppress(Exception):
        old = json.load(open(path, encoding="utf-8"))
    for n in names:
        old["failed"].pop(n, None)
    old["skipped"].update(skipped)
    old["failed"].update(failed)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(old, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
