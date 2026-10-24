"""Erzeugt golden_budget.json aus der Web-App: Summen (Kopfzeile, Kosten, Budget), «Fair geteilt?», variable Kosten und Duplikat-Hinweise.
Eingabe: cases_budget.json (ein Haushalt, mehrere Stichtage). Referenz für den SwiftUI-Nachbau.
Aufruf im Repo-Ordner:  python3 -m http.server 8765 &  python3 tests/make_golden_budget.py
Anderer Port über KONTIVO_URL. Benötigt: pip install playwright (Chromium).

Aufbau je Stichtag (Jahre: Vorjahr, Stichtagsjahr, Folgejahr; Personen: "alle", "Sinan", "Lara"):
- fixPerMonth[Person]: Fixkosten pro Monat wie die Kopfzeile (laufend, begonnen, ohne laufendes Probeabo)
- cost[Jahr][Person]: Kosten-Tab je Monat {sum, paid, open, count} und n (alle Zahlungen im Jahr); mit Person nur deren Verträge (wie der Personenfilter)
- budget[Jahr][Person][Kostenart]: je Monat {inc, fix, vr, free} und Jahressummen; Kostenart all | fix | none (settings.bArt)
- budgetPrevMonth[Person][Kostenart]: Monat des Stichtags im Vorjahr (Vergleichszeile im Budget)
- fairShare: Anteil je Person an Fixkosten und Einnahmen pro Monat (null ohne gemeinsamen Vertrag)
- incMonthNow, varMonth[Jahr]: Einnahmen bzw. variable Kosten pro Monat
- dup[Abfrage]: ID des möglichen Duplikats oder null; partnerGroups: [Name, Schlüssel, Dublette]"""
import json, os, re
from playwright.sync_api import sync_playwright
D = os.path.dirname(os.path.abspath(__file__))
spec = json.load(open(os.path.join(D, 'cases_budget.json'), encoding='utf-8'))
URL = os.environ.get('KONTIVO_URL', 'http://localhost:8765/index.html')
JS = """(sp)=>{var K=window.KontivoCalc(),S=K.state,o={};
  var r=function(x){var v=Math.round(x*100)/100;return v===0?0:v;};
  var t=new Date(window.__KONTIVO_TODAY+"T00:00:00"),Y0=t.getFullYear(),years=[Y0-1,Y0,Y0+1];
  var key=function(h){return h||"alle";},shr=function(h){return function(c){return h?K.holderShare(c,h):1;};};
  var pool=K.withIds(S.contracts),all=function(){return true;};
  o.fixPerMonth={};sp.persons.forEach(function(h){o.fixPerMonth[key(h)]=r(K.fixMonthSum(K.running().filter(function(c){return !K.notStarted(c);}),h));});
  o.cost={};o.budget={};o.varMonth={};
  years.forEach(function(Y){o.cost[Y]={};o.budget[Y]={};
    sp.persons.forEach(function(h){var cm=K.costMonths(pool,Y,h?function(c){return (c.holders||[]).indexOf(h)>=0;}:all,h);
      o.cost[Y][key(h)]={n:cm.n,months:cm.months.map(function(m){return {sum:r(m.sum),paid:r(m.paid),open:r(m.open),count:m.items.length};})};
      o.budget[Y][key(h)]={};
      sp.costKinds.forEach(function(BA){var b=K.budgetYear(Y,shr(h),BA);
        o.budget[Y][key(h)][BA]={inc:r(b.inc),fix:r(b.fix),vr:r(b.vr),free:r(b.free),months:b.M.map(function(m){return {inc:r(m.inc),fix:r(m.fix),vr:r(m.vr),free:r(m.free)};})};});});
    o.varMonth[Y]=[0,1,2,3,4,5,6,7,8,9,10,11].map(function(m){return r(K.varMonth(Y,m));});});
  o.budgetPrevMonth={};sp.persons.forEach(function(h){o.budgetPrevMonth[key(h)]={};
    sp.costKinds.forEach(function(BA){var b=K.budgetMonth(Y0-1,t.getMonth(),shr(h),BA);o.budgetPrevMonth[key(h)][BA]={inc:r(b.inc),fix:r(b.fix),vr:r(b.vr),free:r(b.free)};});});
  var fs=K.fairShare(S.settings.holders);
  o.fairShare=fs?{fix:r(fs.fix),inc:r(fs.inc),per:Object.keys(fs.per).reduce(function(a,h){a[h]={fix:r(fs.per[h].f),inc:r(fs.per[h].i)};return a;},{})}:null;
  o.incMonthNow=r(K.incMonthNow());
  o.dup={};var ids={};Object.keys(S.contracts).forEach(function(k){ids[k]=S.contracts[k];});
  sp.dupQueries.forEach(function(q){var hit=K.dupOf(q.partner,q.label,q.amount,q.cur,q.skip||null),id=null;
    Object.keys(ids).forEach(function(k){if(ids[k]===hit)id=k;});o.dup[q.id]=id;});
  o.partnerGroups=K.partnerGroups().map(function(g){return [g.name,g.pk,g.dup];});
  return o;}"""
res = {"generated_from": "Kontivo Web-App", "settings": spec["settings"], "results": {}}
with sync_playwright() as p:
    b = p.chromium.launch()
    for t in spec["todays"]:
        ctx = b.new_context(); ctx.add_init_script("window.__KONTIVO_TODAY='%s';" % t)
        ctx.route(re.compile(r"frankfurter\.|open\.er-api\.com"), lambda r: r.abort())  # kein Live-Kursabruf: feste Testkurse
        pg = ctx.new_page(); pg.goto(URL)
        st = {"settings": dict(spec["settings"], onboarded=9, rateCheckedAt=9999999999999, dataVer=2),
              "contracts": spec["contracts"], "incomes": spec["incomes"], "vars": spec["vars"]}
        pg.evaluate("s=>localStorage.setItem('vertraege.v1',s)", json.dumps(st)); pg.reload(); pg.wait_for_timeout(500)
        res["results"][t] = pg.evaluate(JS, spec); ctx.close()
    b.close()
json.dump(res, open(os.path.join(D, 'golden_budget.json'), 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print("golden_budget.json:", len(res["results"]), "Stichtage")
