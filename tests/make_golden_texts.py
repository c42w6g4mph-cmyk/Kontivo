"""Erzeugt golden_texts.json aus der Web-App: Referenzwerte für Texte und Regeln (Ergänzung zu golden.json).

Aufruf im Repo-Ordner:
  python3 -m http.server 8771 &
  KONTIVO_URL=http://localhost:8771/index.html python3 tests/make_golden_texts.py
Benötigt: pip install playwright (Chromium). index.html wird nicht verändert.

Inhalt je Stichtag aus cases.json:
  urgency    Stufe/Tage/Datum je Fall (Quelltext von urgency/daysBetween/today aus index.html, mit den Funktionen des Test-Hakens)
  deadlines  Tab «Fristen» aus dem gerenderten DOM (Variante 1, v88): Status, Liste nach Datum, Karte «Flexibel» (aufgeklappt), Klappgruppen (aufgeklappt)
  csv        CSV-Export (Inhalt der heruntergeladenen Datei, mit BOM und CRLF)
Für das Test-Backup cases_texts.json:
  quality    Datenqualität aus dem DOM (Verwalten → Datenqualität): Kopf, Checkliste mit Zählern, je «n offen»-Seite die Einträge
             (Schlüssel aus «Ignorieren», Name, Zusatzzeile)
  letters    Kündigungsschreiben aus dem DOM (Detail → «Kündigungsschreiben»): Absenderzeile, Empfänger, Betreff, Text, Hinweise
"""
import json, os, re
from playwright.sync_api import sync_playwright

D = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(D)
spec = json.load(open(os.path.join(D, 'cases.json'), encoding='utf-8'))
texts = json.load(open(os.path.join(D, 'cases_texts.json'), encoding='utf-8'))
URL = os.environ.get('KONTIVO_URL', 'http://localhost:8765/index.html')
HTML = open(os.path.join(ROOT, 'index.html'), encoding='utf-8').read()


def js_function(name):
    """Quelltext einer Funktion `function name(...){...}` aus index.html (Klammern gezählt, Zeichenketten beachtet)."""
    m = re.search(r'function ' + re.escape(name) + r'\(', HTML)
    if not m:
        raise SystemExit('Funktion fehlt: ' + name)
    i = HTML.index('{', m.end())
    depth, q, j = 0, None, i
    while j < len(HTML):
        ch = HTML[j]
        if q:
            if ch == '\\':
                j += 2
                continue
            if ch == q:
                q = None
        elif ch in '"\'':
            q = ch
        elif ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                return HTML[m.start():j + 1]
        j += 1
    raise SystemExit('Funktion unvollständig: ' + name)


URGENCY_SRC = js_function('today') + '\n' + js_function('daysBetween') + '\n' + js_function('urgency')

JS_URGENCY = """(src)=>{var K=window.KontivoCalc();
  var f=new Function('K','var noticeDeadline=K.noticeDeadline,isAnytime=K.isAnytime,termEnd=K.termEnd,iso=K.iso;'+src+'\\nreturn urgency;')(K);
  var out={};Object.keys(K.state.contracts).forEach(function(k){var u=f(K.state.contracts[k]);
    out[k]={lvl:u.lvl,days:u.days,date:u.date?K.iso(u.date):null};});return out;}"""

JS_DEADLINES = """()=>{var v=document.getElementById('view'),r={status:null,items:[],flex:null,folds:[]};
  var st=v.querySelector('.tstat');if(st){var ok=st.classList.contains('ok');
    r.status={kind:ok?'ok':(st.classList.contains('alert')?'alert':'warn'),count:ok?null:parseInt(st.querySelector('i').textContent,10),
      title:st.querySelector('b').textContent,sub:st.querySelector('span').textContent};}
  v.querySelectorAll('.tlist .tit').forEach(function(t){var b=t.querySelector('[data-open]'),ch=t.querySelector('.tchip'),acts=t.querySelectorAll('.tacts button');
    var lv=['warn','alert','ok','end'].filter(function(k){return ch.classList.contains(k);})[0]||'';
    r.items.push({id:b.dataset.open,sub:t.querySelector('.mm').textContent,chip:ch.textContent,lvl:lv,acts:acts.length>0,trial:!!t.querySelector('[data-trial]'),
      keep:acts.length?acts[0].textContent:null,kill:acts.length?acts[1].textContent:null});});
  var fx=v.querySelector('.tflex');if(fx){var nt=fx.querySelector('.tfnote');
    r.flex={count:fx.querySelector('.tfx .mn').textContent,sub:fx.querySelector('.tfx .mm').textContent,note:nt?nt.textContent:null,
      stack:fx.querySelectorAll('.tstk .mark').length,rows:[]};
    fx.querySelectorAll('.mrows2 .trow').forEach(function(x){r.flex.rows.push({id:x.dataset.open,sub:x.querySelector('.mm').textContent,chip:x.querySelector('.tchip').textContent});});}
  v.querySelectorAll('.tfg').forEach(function(g){var b=g.querySelector('.tfold'),rows=[];
    g.querySelectorAll('.trow').forEach(function(x){rows.push({id:x.dataset.open||x.dataset.qnotice,text:x.querySelector('.tst').textContent});});
    r.folds.push({key:b.dataset.tfold,title:b.textContent,rows:rows});});
  return r;}"""

JS_QUAL_TOP = """()=>{var b=document.getElementById('mdBody'),r={headline:null,text:null,rows:[]};
  var top=b.querySelector('.qtop');if(top){r.headline=top.querySelector('b').textContent;r.text=top.querySelector('span').textContent;}
  b.querySelectorAll('.qgrp').forEach(function(g){var gt=g.querySelector('.qgh span').textContent;
    g.querySelectorAll('li').forEach(function(li){var btn=li.querySelector('[data-qf]');
      r.rows.push({group:gt,title:li.querySelector('span').textContent,qf:btn?btn.dataset.qf:null,count:btn?parseInt(li.querySelector('b').textContent,10):0});});});
  var note=b.querySelector('.mdhint');r.footnote=note?note.textContent:null;return r;}"""

JS_QUAL_LIST = """()=>{var out=[];document.querySelectorAll('#mdBody .qrow').forEach(function(q){var sm=q.querySelector('.mdrow .t small');
  out.push({key:q.querySelector('[data-qig]').dataset.qig,name:q.querySelector('.mdrow .t b').textContent,small:sm?sm.textContent:''});});return out;}"""

JS_LETTER = """()=>({sender:document.getElementById('ltSender').textContent,to:document.getElementById('ltTo').value,
  subject:document.getElementById('ltSubj').value,body:document.getElementById('ltBody').value,hint:document.getElementById('ltHint').textContent})"""


def load(pg, state):
    pg.evaluate("s=>localStorage.setItem('vertraege.v1',s)", json.dumps(state))
    pg.reload()
    pg.wait_for_timeout(400)


res = {"generated_from": "Kontivo Web-App (make_golden_texts.py)", "settings": spec["settings"], "results": {}, "texts": {}}
with sync_playwright() as p:
    b = p.chromium.launch()
    # Stichtage aus cases.json
    for t in spec["todays"]:
        ctx = b.new_context(viewport={"width": 430, "height": 900}, accept_downloads=True, service_workers="block")
        ctx.add_init_script("window.__KONTIVO_TODAY='%s';" % t)
        pg = ctx.new_page()
        pg.goto(URL)
        cs = {}
        for c in spec["cases"]:
            x = {"cat": "Sonstiges", "status": "active"}
            x.update(c["c"])
            cs[c["id"]] = x
        load(pg, {"settings": dict(spec["settings"], onboarded=9, rateTs=9999999999999), "contracts": cs, "incomes": {}})
        out = {"urgency": pg.evaluate(JS_URGENCY, URGENCY_SRC)}
        pg.click('.tabbar button[data-tab="term"]')
        pg.wait_for_timeout(150)
        for k in ["any", "none", "unw"]:
            el = pg.query_selector('[data-tfold="%s"]' % k)
            if el:
                el.click()
                pg.wait_for_timeout(80)
        out["deadlines"] = pg.evaluate(JS_DEADLINES)
        with pg.expect_download() as dl:
            pg.evaluate("()=>document.getElementById('csvBtn').click()")
        out["csv"] = open(dl.value.path(), 'rb').read().decode('utf-8')
        res["results"][t] = out
        ctx.close()

    # Test-Backup: Datenqualität und Kündigungsschreiben
    t = texts["today"]
    ctx = b.new_context(viewport={"width": 430, "height": 900}, accept_downloads=True, service_workers="block")
    ctx.add_init_script("window.__KONTIVO_TODAY='%s';" % t)
    pg = ctx.new_page()
    pg.goto(URL)
    st = {"settings": dict(texts["settings"], onboarded=9, rateTs=9999999999999), "contracts": texts["contracts"], "incomes": texts["incomes"]}
    load(pg, st)
    pg.evaluate("()=>document.querySelector('[data-md=\"qual\"]').click()")
    pg.wait_for_timeout(250)
    q = pg.evaluate(JS_QUAL_TOP)
    q["lists"] = {}
    for row in q["rows"]:
        if not row["qf"]:
            continue
        load(pg, st)
        pg.evaluate("()=>document.querySelector('[data-md=\"qual\"]').click()")
        pg.wait_for_timeout(200)
        pg.evaluate("qf=>document.querySelector('[data-qf=\"'+qf+'\"]').click()", row["qf"])
        pg.wait_for_timeout(200)
        q["lists"][row["qf"]] = pg.evaluate(JS_QUAL_LIST)
    letters = {}
    for cid in texts["letters"]:
        load(pg, st)
        pg.evaluate("id=>document.querySelector('[data-open=\"'+id+'\"]').click()", cid)
        pg.wait_for_timeout(250)
        pg.evaluate("()=>document.querySelector('[data-act=\"ktext\"]').click()")
        pg.wait_for_timeout(250)
        letters[cid] = pg.evaluate(JS_LETTER)
    res["texts"] = {"today": t, "quality": q, "letters": letters}
    ctx.close()
    b.close()

json.dump(res, open(os.path.join(D, 'golden_texts.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print("golden_texts.json:", len(res["results"]), "Stichtage,", sum(len(v) for v in res["texts"]["quality"]["lists"].values()),
      "Datenqualitäts-Einträge,", len(res["texts"]["letters"]), "Briefe")
