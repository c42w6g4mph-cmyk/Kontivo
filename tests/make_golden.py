"""Erzeugt golden.json aus der Web-App (Referenz für den SwiftUI-Nachbau).
Aufruf im Repo-Ordner:  python3 -m http.server 8765 &  python3 tests/make_golden.py
Benötigt: pip install playwright (Chromium)."""
import json,os,sys
from playwright.sync_api import sync_playwright
D=os.path.dirname(os.path.abspath(__file__))
spec=json.load(open(os.path.join(D,'cases.json'),encoding='utf-8'))
URL=os.environ.get('KONTIVO_URL','http://localhost:8765/index.html')
JS="""(cases)=>{var K=window.KontivoCalc(),out={};
  function d(x){return x?K.iso(x):null;}
  cases.forEach(function(cs){var c=Object.assign({cat:"Sonstiges",status:"active",_id:cs.id},cs.c);K.state.contracts[cs.id]=c;
    var e=K.termEnd(c),nd=K.nextDue(c),occ=K.occurrences(c,new Date(window.__KONTIVO_TODAY+"T00:00:00"),new Date(new Date(window.__KONTIVO_TODAY+"T00:00:00").getFullYear()+1,11,31));
    out[cs.id]={termEnd:d(e),noticeDeadline:d(K.noticeDeadline(c)),nextTerm:d(K.nextTerm(c)),effEnd:d(K.effEnd(c)),nextDue:d(nd),
      paymentsNext12:occ.slice(0,12).map(d),curPrice:Math.round(K.curPrice(c)*100)/100,monthlyCostHome:Math.round(K.monthlyCost(c)*100)/100,
      anytime:K.isAnytime(c),needsAction:K.needsAction(c),trialNeeds:K.trialNeeds(c),paused:K.isPaused(c),
      shareSinan:K.holderShare(c,"Sinan"),shareLara:K.holderShare(c,"Lara"),cancVia:K.cancVia(c)};});
  return out;}"""
res={"generated_from":"Kontivo Web-App","settings":spec["settings"],"results":{}}
with sync_playwright() as p:
    b=p.chromium.launch()
    for t in spec["todays"]:
        ctx=b.new_context();ctx.add_init_script("window.__KONTIVO_TODAY='%s';"%t)
        pg=ctx.new_page();pg.goto(URL)
        st={"settings":dict(spec["settings"],onboarded=9,rateTs=9999999999999),"contracts":{},"incomes":{}}
        pg.evaluate("s=>localStorage.setItem('vertraege.v1',s)",json.dumps(st));pg.reload();pg.wait_for_timeout(500)
        res["results"][t]=pg.evaluate(JS,spec["cases"]);ctx.close()
    b.close()
json.dump(res,open(os.path.join(D,'golden.json'),'w',encoding='utf-8'),ensure_ascii=False,indent=1)
print("golden.json:",sum(len(v) for v in res["results"].values()),"Ergebnisse")
