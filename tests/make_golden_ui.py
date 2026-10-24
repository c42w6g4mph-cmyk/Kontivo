"""Erzeugt golden_ui.json: was die Web-App in «Fristen», in der Vertrags- und Einnahmenansicht und in «Vollständigkeit» anzeigt.
Referenz für den SwiftUI-Nachbau (Texte, Reihenfolge, Gruppen, Knöpfe), abgelesen aus der laufenden App, ohne Eingriff in den Code.
Daten: der Haushalt aus cases_budget.json plus alle Verträge aus cases.json (Sonderfälle), an den Stichtagen beider Dateien.
Aufruf im Repo-Ordner:  python3 -m http.server 8765 &  python3 tests/make_golden_ui.py   (anderer Port über KONTIVO_URL)

Aufbau je Stichtag:
- badge: Zahl am Tab «Fristen» ("" = keine)
- term.stat: Kopf {cls: ok|warn|alert, count, title, sub}; term.rows: alle Zeilen in Anzeigereihenfolge (aufgeklappt)
  {group, id, title, sub, chip, chipCls, acts}; term.review: Quartals-Check-Karte sichtbar
- detail[ID] / incDetail[ID]: sichtbarer Text der Ansicht (Zeilen, Leerraum zusammengefasst)
- vk: Zeile unter «Mehr» und Startseite «Vollständigkeit» (Text)
- hero: Kopfzeile im Tab «Verträge» (Text)"""
import json, os, re
from playwright.sync_api import sync_playwright
D = os.path.dirname(os.path.abspath(__file__))
cb = json.load(open(os.path.join(D, "cases_budget.json"), encoding="utf-8"))
cs = json.load(open(os.path.join(D, "cases.json"), encoding="utf-8"))
URL = os.environ.get("KONTIVO_URL", "http://localhost:8765/index.html")
C = dict(cb["contracts"])
for c in cs["cases"]:
    C[c["id"]] = dict({"partner": c["id"], "label": c.get("note", c["id"])[:40], "cat": "Sonstiges", "status": "active"}, **c["c"])
DATA = {"settings": dict(cb["settings"], onboarded=9, rateCheckedAt=9999999999999, dataVer=2, lastReview="2026-09-01"),
        "contracts": C, "incomes": cb["incomes"], "vars": cb["vars"]}
TODAYS = sorted(set(cb["todays"] + cs["todays"]))
TERM = """()=>{var v=document.getElementById('view'),o={stat:null,rows:[],review:!!v.querySelector('.review')};
  var s=v.querySelector('.tstat');if(s){var i=s.querySelector('i');o.stat={cls:(s.className.match(/\\b(ok|warn|alert)\\b/)||[''])[0],count:i&&!i.querySelector('svg')?i.textContent:'',title:s.querySelector('b').textContent,sub:s.querySelector('span').textContent};}
  var t=function(e,q){var x=e&&e.querySelector(q);return x?x.textContent.replace(/\\s+/g,' ').trim():'';};
  v.querySelectorAll('[data-open],[data-qnotice]').forEach(function(b){if(b.closest('.tstk'))return;var g=b.closest('.grp'),h=g&&g.querySelector('.grphead span, .tfold span'),it=b.closest('.tit,.tcard'),ch=b.querySelector('.tchip');
    o.rows.push({group:h?h.textContent.replace(/\\s+/g,' ').trim():'',id:b.dataset.open||b.dataset.qnotice,title:t(b,'.mn')||t(b,'.n'),sub:t(b,'.mm')||t(b,'.tline2')||t(b,'.tst'),
      chip:ch?ch.textContent:'',chipCls:ch?ch.className.replace('tchip','').trim():'',acts:it?[].map.call(it.querySelectorAll('.tacts button'),function(x){return x.textContent;}):[]});});
  return o;}"""
norm = lambda s: re.sub(r"[ \t]+", " ", re.sub(r"\n\s*\n+", "\n", s)).strip()
res = {"generated_from": "Kontivo Web-App", "todays": TODAYS, "results": {}}
with sync_playwright() as p:
    b = p.chromium.launch()
    for t in TODAYS:
        ctx = b.new_context(viewport={"width": 393, "height": 852}, locale="de-CH", timezone_id="Europe/Zurich", reduced_motion="reduce")
        ctx.add_init_script("window.__KONTIVO_TODAY='%s';" % t)
        ctx.route("**/*", lambda r: r.continue_() if r.request.url.startswith(("http://localhost", "data:", "blob:")) else r.abort())
        pg = ctx.new_page(); errs = []; pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.goto(URL); pg.evaluate("s=>localStorage.setItem('vertraege.v1',s)", json.dumps(DATA)); pg.reload(); pg.wait_for_timeout(600)
        pg.evaluate("()=>{var s=document.getElementById('splash');if(s)s.remove();}")
        r = {"hero": norm(pg.inner_text("#hero")), "badge": pg.inner_text("#cTerm")}
        pg.click('.tabbar button[data-tab="term"]'); pg.wait_for_timeout(200)
        for _ in range(6):  # alle Klappgruppen öffnen (jeder Klick zeichnet neu)
            n = pg.evaluate("()=>{var e=document.querySelector('#view [data-tfold][aria-expanded=\"false\"]');if(e){e.click();return 1;}return 0;}")
            if not n: break
            pg.wait_for_timeout(80)
        r["term"] = pg.evaluate(TERM)
        r["detail"] = {}; r["incDetail"] = {}
        for kind, ids, attr in [("detail", sorted(C), "data-open"), ("incDetail", sorted(cb["incomes"]), "data-inc")]:
            for i in ids:
                pg.evaluate("([a,i])=>{var v=document.getElementById('view'),x=document.createElement('button');x.setAttribute(a,i);x.hidden=true;v.appendChild(x);x.click();x.remove();}", [attr, i])
                pg.wait_for_timeout(120)
                r[kind][i] = norm(pg.inner_text("#sheetDetail"))
                pg.keyboard.press("Escape"); pg.wait_for_timeout(120)
        pg.click('.tabbar button[data-tab="set"]'); pg.wait_for_timeout(200)
        row = norm(pg.inner_text("#vkOpen")); pg.click("#vkOpen"); pg.wait_for_timeout(300)
        r["vk"] = {"row": row, "start": norm(pg.inner_text("#vkBody"))}
        r["errors"] = errs
        res["results"][t] = r; ctx.close()
    b.close()
json.dump(res, open(os.path.join(D, "golden_ui.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("golden_ui.json:", len(TODAYS), "Stichtage,", len(C), "Verträge,", len(cb["incomes"]), "Einnahmen")
