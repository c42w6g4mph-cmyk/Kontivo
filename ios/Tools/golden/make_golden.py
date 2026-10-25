"""Erzeugt golden.json aus der Web-App (Referenz für den SwiftUI-Nachbau).
Aufruf:  cd <main-Repo> && python3 -m http.server 8765 &  WEB=<main-Repo> python3 ios/Tools/golden/make_golden.py
Benötigt: pip install playwright (Chromium).

Für Felder ausserhalb von window.KontivoCalc (trialOn, endsSelf, skrInfo, openSkr, renderHero …) wird index.html beim
Laden im Speicher um einen Test-Haken window.__KX ergänzt (Datei bleibt unverändert).

Je Stichtag:
  results[t][id]   Rechenwerte je Fall aus cases.json (wie bisher) + trialOn, endsSelf (v157/v160), skr (skrInfo, v205–v209)
  hero[t][name]    Kopf «Verträge» je Filter/Status (v161/v164/v189): Summe, Beschriftung, Unterzeile, Zähler aus dem DOM
  skr[t][id]       Fälle aus cases.json «skrCases» (eigene Stichtage «skrTodays»): skrInfo, Zeile im Detail, Blatt (DOM von openSkr)
"""
import json, os
from playwright.sync_api import sync_playwright

D = os.path.dirname(os.path.abspath(__file__))
ROOT = os.environ['WEB']  # Web-Repo (main) mit index.html
RES = os.path.join(D, "..", "..", "KontivoCore", "Tests", "KontivoCoreTests", "Resources")  # Prüffälle im Swift-Paket
spec = json.load(open(os.path.join(RES, 'cases.json'), encoding='utf-8'))
URL = os.environ.get('KONTIVO_URL', 'http://localhost:8765/index.html')
HTML = open(os.path.join(ROOT, 'index.html'), encoding='utf-8').read()
_i = HTML.find("window.KontivoCalc=function(){return {")
if _i < 0 or HTML.find("};};", _i) < 0:
    raise SystemExit("Anker für den Test-Haken fehlt in index.html")
ANCHOR = HTML[_i:HTML.find("};};", _i) + 4]
HOOK = ("window.__KX=function(){return {trialOn:trialOn,endsSelf:endsSelf,skrInfo:skrInfo,openSkr:openSkr,renderHero:renderHero,"
        "isFixed:isFixed,endedByTerm:endedByTerm};};")
PATCHED = HTML.replace(ANCHOR, ANCHOR + HOOK, 1)
# Web v259: kein Hinweis, wenn ordentlich vorher kündbar (regEndsFirst). Für die Regel selbst zusätzlich ohne diese Prüfung (window.__noREF)
REF = "if(regEndsFirst(c,f))return null;"
if REF in PATCHED:
    PATCHED = PATCHED.replace(REF, "if(!window.__noREF&&regEndsFirst(c,f))return null;", 1)

JS_SKR = """function skrOut(K,X,c){var x=X.skrInfo(c);if(!x)return null;var r=x.r;function d(v){return v?K.iso(v):null;}
  return {from:d(x.f),amount:x.a,prev:x.prev,pct:x.pct,until:d(x.until),head:x.head,tail:x.tail,none:!!r.none,
    min:!!r.min,end:d(r.end),endMin:!!r.endMin,endTxt:r.endTxt||null,when:r.when||null,src:r.src||null,tips:r.tips};}"""

JS = """(cases)=>{var K=window.KontivoCalc(),X=window.__KX(),out={};
  function d(x){return x?K.iso(x):null;}
  """ + JS_SKR + """
  cases.forEach(function(cs){var c=Object.assign({cat:"Sonstiges",status:"active",_id:cs.id},cs.c);K.state.contracts[cs.id]=c;
    var e=K.termEnd(c),nd=K.nextDue(c),occ=K.occurrences(c,new Date(window.__KONTIVO_TODAY+"T00:00:00"),new Date(new Date(window.__KONTIVO_TODAY+"T00:00:00").getFullYear()+1,11,31));
    out[cs.id]={termEnd:d(e),noticeDeadline:d(K.noticeDeadline(c)),nextTerm:d(K.nextTerm(c)),effEnd:d(K.effEnd(c)),renewTo:d(K.renewTo(c)),ended:K.isEnded(c),nextDue:d(nd),
      paymentsNext12:occ.slice(0,12).map(d),curPrice:Math.round(K.curPrice(c)*100)/100,monthlyCostHome:Math.round(K.monthlyCost(c)*100)/100,
      anytime:K.isAnytime(c),needsAction:K.needsAction(c),trialNeeds:K.trialNeeds(c),paused:K.isPaused(c),
      shareSinan:K.holderShare(c,"Sinan"),shareLara:K.holderShare(c,"Lara"),cancVia:K.cancVia(c),
      trialOn:X.trialOn(c),endsSelf:X.endsSelf(c),skr:skrOut(K,X,c)};});
  return out;}"""

HERO_VARIANTS = [
    ["all", {}, ""], ["act", {}, "act"], ["paused", {}, "paused"], ["fut", {}, "fut"],
    ["sinan", {"holder": "Sinan"}, ""], ["lara", {"holder": "Lara"}, ""], ["lara-paused", {"holder": "Lara"}, "paused"],
    ["tax", {"cat": "Steuern & Gebühren"}, ""], ["other-fut", {"cat": "Sonstiges"}, "fut"],
]

JS_HERO = """(vs)=>{var K=window.KontivoCalc(),X=window.__KX(),out={};
  vs.forEach(function(v){K.state.flt=Object.assign({cat:null,partner:null,holder:null},v[1]);K.state.heroF=v[2];X.renderHero();
    var chips={};document.querySelectorAll('#hChips [data-hf]').forEach(function(b){chips[b.dataset.hf]=parseInt(b.querySelector('b').textContent,10);});
    out[v[0]]={status:K.state.heroF||null,month:document.getElementById('hMonth').textContent,label:document.querySelector('.hero .hlabel').textContent,
      sub:document.getElementById('hSub').textContent,chips:chips};});
  K.state.flt={cat:null,partner:null,holder:null};K.state.heroF="";return out;}"""

JS_SKRCASES = """(cases)=>{var K=window.KontivoCalc(),X=window.__KX(),out={};
  """ + JS_SKR + """
  function sheet(id){X.openSkr(id);var l=document.getElementById('pickList');if(l.dataset.dim!=='skr')return null;
    var q=function(s){var e=l.querySelector(s);return e?e.textContent:null;};
    return {title:document.getElementById('pickTitle').textContent,intro:q('.skri'),
      rows:Array.prototype.map.call(l.querySelectorAll('.skrc:not(.skrt) .skrr'),function(r){var b=r.querySelector('b'),sm=b.querySelector('small'),t=b.textContent;
        return {key:r.querySelector('span').textContent,value:sm?t.slice(0,t.length-sm.textContent.length):t,sub:sm?sm.textContent:'',accent:b.classList.contains('skrk')};}),
      tipsTitle:q('.skrh'),tips:Array.prototype.map.call(l.querySelectorAll('.skrt p'),function(p){return p.textContent;}),footer:q('.fqf span')};}
  cases.forEach(function(cs){var c=Object.assign({cat:"Sonstiges",status:"active",_id:cs.id},cs.c);K.state.contracts[cs.id]=c;});
  cases.forEach(function(cs){var c=K.state.contracts[cs.id],x=X.skrInfo(c),gone=c.status==="cancelled"||!!c.cancelPer||X.endedByTerm(c);
    var l=document.getElementById('pickList');l.dataset.dim='';
    out[cs.id]={skr:skrOut(K,X,c),detail:!!(x&&!gone&&!X.isFixed(c)),line:x?(x.head+(x.tail?" · "+x.tail:"")):null,sheet:x?sheet(cs.id):null};
    window.__noREF=true;var xr=X.skrInfo(c);l.dataset.dim='';out[cs.id].skrRaw=skrOut(K,X,c);out[cs.id].sheetRaw=xr?sheet(cs.id):null;window.__noREF=false;});
  return out;}"""


def page_for(b, t):
    ctx = b.new_context(service_workers="block")
    ctx.add_init_script("window.__KONTIVO_TODAY='%s';" % t)
    ctx.route("**/index.html", lambda route: route.fulfill(status=200, content_type="text/html; charset=utf-8", body=PATCHED))
    pg = ctx.new_page()
    pg.goto(URL)
    st = {"settings": dict(spec["settings"], onboarded=9, rateTs=9999999999999), "contracts": {}, "incomes": {}}
    pg.evaluate("s=>localStorage.setItem('vertraege.v1',s)", json.dumps(st))
    pg.reload()
    pg.wait_for_timeout(500)
    return ctx, pg


res = {"generated_from": "Kontivo Web-App", "settings": spec["settings"], "results": {}, "hero": {}, "skr": {}}
with sync_playwright() as p:
    b = p.chromium.launch()
    for t in spec["todays"]:
        ctx, pg = page_for(b, t)
        res["results"][t] = pg.evaluate(JS, spec["cases"])
        res["hero"][t] = pg.evaluate(JS_HERO, HERO_VARIANTS)
        ctx.close()
    for t in spec.get("skrTodays", []):
        ctx, pg = page_for(b, t)
        res["skr"][t] = pg.evaluate(JS_SKRCASES, spec["skrCases"])
        ctx.close()
    b.close()
import re as _re
res = json.loads(_re.sub(r"(?<=\d)'(?=\d{3})", "\u2019", json.dumps(res, ensure_ascii=False)))  # Chromium de-CH «'» → «’» (Safari/iOS)
json.dump(res, open(os.environ.get('OUT', os.path.join(RES, 'golden.json')), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print("golden.json:", sum(len(v) for v in res["results"].values()), "Ergebnisse,",
      sum(len(v) for v in res["hero"].values()), "Kopfzeilen,", sum(len(v) for v in res["skr"].values()), "Sonderkündigungs-Fälle")
