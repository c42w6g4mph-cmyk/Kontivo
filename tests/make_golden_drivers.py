"""Erzeugt golden_drivers.json aus der Web-App: Tab «Kosten» → «Überblick» (Säulen, Kategorien-Donut) und «Was sich verändert hat»
(Kategorien mit Betrag, Chips, aufgeklappte Verträge mit Grund, Hinweise) für den Testhaushalt main/tests/cases_budget.json und die
Beispieldaten Resources/costs_demo_backup.json
(Web v247–v257: Preistreiber als Chips, Grund mit Symbol, Wechsel, Donut, Hinweis ohne Vertragsbeginn).
Aufruf:  cd <main-Repo> && python3 -m http.server 8765 &   KONTIVO_URL=http://localhost:8765/index.html WEB=<main-Repo> python3 tests/make_golden_drivers.py
Ergebnis: ios/KontivoCore/Tests/KontivoCoreTests/Resources/golden_drivers.json (Vergleich in GoldenDriversTests.swift)."""
import json, os, re
from playwright.sync_api import sync_playwright
D = os.path.dirname(os.path.abspath(__file__))
WEB = os.environ.get("WEB", "/home/claude/kontivo")
URL = os.environ.get("KONTIVO_URL", "http://localhost:8765/index.html")
spec = json.load(open(os.path.join(WEB, "tests", "cases_budget.json"), encoding="utf-8"))
demo = json.load(open(os.path.join(os.path.dirname(D), "ios", "KontivoCore", "Tests", "KontivoCoreTests", "Resources", "costs_demo_backup.json"), encoding="utf-8"))
SETS = [("budget", ["2026-10-24", "2027-01-15", "2026-02-28"],
         {"settings": dict(spec["settings"], onboarded=9, rateCheckedAt=9999999999999, dataVer=2), "contracts": spec["contracts"], "incomes": spec["incomes"], "vars": spec["vars"]}),
        ("swap", ["2026-10-24"], {"settings": {"home": "CHF", "holders": ["Sinan"], "onboarded": 9, "rateCheckedAt": 9999999999999, "dataVer": 2}, "incomes": {}, "contracts": {
            "st25": {"partner": "Steueramt", "label": "Steuern Lohn 2025", "cat": "Steuern & Gebühren", "amount": 400, "cur": "CHF", "cycle": 1, "due": "2025-01-31", "start": "2025-01-01", "end": "2025-12-31", "holders": ["Sinan"], "status": "active"},
            "st26": {"partner": "Steueramt", "label": "Steuern Lohn 2026", "cat": "Steuern & Gebühren", "amount": 420, "cur": "CHF", "cycle": 1, "due": "2026-01-31", "start": "2026-01-01", "holders": ["Sinan"], "status": "active"},
            "m1": {"partner": "Wincasa AG", "label": "Miete", "cat": "Wohnen", "amount": 1800, "cur": "CHF", "cycle": 1, "due": "2025-01-01", "start": "2024-01-01", "end": "2026-03-31", "holders": ["Sinan"], "status": "active"},
            "m2": {"partner": "Regimo AG", "label": "Miete", "cat": "Wohnen", "amount": 1950, "cur": "CHF", "cycle": 1, "due": "2026-04-01", "start": "2026-04-01", "holders": ["Sinan"], "status": "active"},
            "tv": {"partner": "Sky", "label": "Sky", "cat": "Abos & Medien", "amount": 30, "cur": "CHF", "cycle": 1, "due": "2025-01-10", "start": "2024-01-10", "end": "2026-05-31", "holders": ["Sinan"], "status": "active"},
            "dp": {"partner": "Disney+", "label": "Disney+", "cat": "Abos & Medien", "amount": 12, "cur": "CHF", "cycle": 1, "due": "2026-06-10", "start": "2026-06-10", "holders": ["Sinan"], "status": "active"},
            "a1": {"partner": "A", "label": "Zeitung A", "cat": "Abos & Medien", "amount": 5, "cur": "CHF", "cycle": 1, "due": "2026-02-01", "start": "2026-02-01", "holders": ["Sinan"], "status": "active"},
            "a2": {"partner": "B", "label": "Zeitung B", "cat": "Abos & Medien", "amount": 6, "cur": "CHF", "cycle": 1, "due": "2026-03-01", "start": "2026-03-01", "holders": ["Sinan"], "status": "active"},
            "a3": {"partner": "C", "label": "Zeitung C", "cat": "Abos & Medien", "amount": 7, "cur": "CHF", "cycle": 1, "due": "2026-04-01", "start": "2026-04-01", "holders": ["Sinan"], "status": "active"}}}),
        ("demo", ["2026-10-03"], {"settings": dict(demo["settings"], onboarded=9, rateCheckedAt=9999999999999, dataVer=2), "contracts": demo["contracts"], "incomes": demo.get("incomes", {})})]
JS = """()=>{var v=document.getElementById('view'),r={cols:[],note:[],cats:[],links:[]};
  v.querySelectorAll('.ptc').forEach(function(b){var d=b.querySelector('.ptd');r.cols.push({y:+b.dataset.pty,p:b.querySelector('.ptp').textContent.replace(/\\u00a0/g,''),
    v:b.querySelector('.v').textContent,d:d?d.textContent.replace(/\\u00a0/g,''):'',dc:d?(d.classList.contains('up')?'up':d.classList.contains('down')?'down':''):'',
    cls:['cur','past','fut'].filter(function(k){return b.classList.contains(k);})[0]||''});});
  var h=v.querySelector('.ptgrp2 .grphead');r.head=h?h.textContent:null;
  v.querySelectorAll('.ptnote').forEach(function(p){r.note.push(p.textContent);});
  v.querySelectorAll('.ptlink').forEach(function(p){r.links.push(p.dataset.open);});
  v.querySelectorAll('.ptrow2').forEach(function(b){var pv=b.querySelector('.ptv');
    r.cats.push({k:b.dataset.ptcat,v:pv.textContent,vc:pv.classList.contains('up')?'up':pv.classList.contains('down')?'down':'',
      chips:[].map.call(b.querySelectorAll('.ptl .ptch'),function(c){return {t:c.textContent,cls:['pu','pd','ps','ptm2'].filter(function(k){return c.classList.contains(k);})[0]||''};})});});
  return r;}"""
JS_SUB = """()=>[].map.call(document.querySelectorAll('#view .ptsub .ptsr'),function(b){var pv=b.querySelector('.ptv');return {id:b.dataset.open,
  n:b.querySelector('.mn').textContent,m:b.querySelector('.mm').textContent,v:pv.textContent};})"""
JS_DONUT = """()=>[].map.call(document.querySelectorAll('#view .ptlg > *'),function(x){var s=x.querySelector('span'),e=x.querySelector('em');return {k:s?s.textContent:'',p:e?e.textContent:''};})"""
res = {"generated_from": "Kontivo Web-App (make_golden_drivers.py)", "results": {},
       "inputs": {n: dict(st, app="vertraege", version=2) for n, _, st in SETS if n == "swap"}}
with sync_playwright() as p:
    b = p.chromium.launch()
    for name, todays, st in SETS:
      for t in todays:
          ctx = b.new_context(viewport={"width": 430, "height": 900}, service_workers="block")
          ctx.add_init_script("window.__KONTIVO_TODAY='%s';" % t)
          ctx.route(re.compile(r"frankfurter\.|open\.er-api\.com"), lambda r: r.abort())
          pg = ctx.new_page(); pg.goto(URL)
          pg.evaluate("s=>localStorage.setItem('vertraege.v1',s)", json.dumps(st)); pg.reload(); pg.wait_for_timeout(500)
          pg.click('.tabbar button[data-tab="stat"]'); pg.wait_for_timeout(200)
          Y0 = int(t[:4]); out = {}
          for Y in [Y0 - 1, Y0, Y0 + 1]:
              pg.evaluate("y=>{var b=document.querySelector('[data-pty=\"'+y+'\"]');if(b)b.click();}", Y); pg.wait_for_timeout(150)
              r = pg.evaluate(JS)
              for c in r["cats"]:
                  pg.evaluate("k=>{var b=[].filter.call(document.querySelectorAll('[data-ptcat]'),function(x){return x.dataset.ptcat===k;})[0];if(b)b.click();}", c["k"]); pg.wait_for_timeout(80)
                  c["sub"] = pg.evaluate(JS_SUB)
                  pg.evaluate("k=>{var b=[].filter.call(document.querySelectorAll('[data-ptcat]'),function(x){return x.dataset.ptcat===k;})[0];if(b)b.click();}", c["k"]); pg.wait_for_timeout(80)
              pg.evaluate("()=>document.querySelector('[data-ptview=\"cat\"]').click()"); pg.wait_for_timeout(120)
              r["donut"] = pg.evaluate(JS_DONUT)
              pg.evaluate("()=>document.querySelector('[data-ptview=\"\"]').click()"); pg.wait_for_timeout(120)
              out[str(Y)] = r
          res["results"][name + "|" + t] = out; ctx.close()
    b.close()
OUT = os.path.join(os.path.dirname(D), "ios", "KontivoCore", "Tests", "KontivoCoreTests", "Resources", "golden_drivers.json")
json.dump(res, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("golden_drivers.json:", sum(len(v) for v in res["results"].values()), "Jahre")
