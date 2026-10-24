"""Erwartungswerte für BankParityTests.swift direkt aus der Web-App (index.html, window.KontivoBank).
Aufruf:  cd <web-repo> && python3 -m http.server 8765 &   python3 -I make_expected.py [<web-repo>]
Kopiert tests/bank/samples und tests/bank/real/{ch,de} hierher und schreibt expected.json
(Grenzfälle aus tests/bank/edge_cases.json und EXTRA unten samt Eingabe unter «edgeInput»)."""
import base64, json, os, shutil, sys
from playwright.sync_api import sync_playwright
HERE = os.path.dirname(os.path.abspath(__file__))
WEB = sys.argv[1] if len(sys.argv) > 1 else "/home/claude/kontivo"
URL = os.environ.get("KONTIVO_URL", "http://localhost:8765/index.html")
SRC = os.path.join(WEB, "tests", "bank")
FILES = []
for sub in ("samples", "real/ch", "real/de", "stress"):
    os.makedirs(os.path.join(HERE, sub), exist_ok=True)
    for fn in sorted(os.listdir(os.path.join(SRC, sub))):
        if fn.endswith(".md") or fn.endswith(".py"): continue
        shutil.copyfile(os.path.join(SRC, sub, fn), os.path.join(HERE, sub, fn)); FILES.append(sub + "/" + fn)
EDGE = json.load(open(os.path.join(SRC, "edge_cases.json")))   # Texte landen in expected.json (edgeInput)
def backup(contracts): return json.dumps({"app": "vertraege", "version": 2, "settings": {"home": "CHF", "holders": ["Sinan"]}, "contracts": contracts or {}, "incomes": {}}, ensure_ascii=False)
# Zusätzliche Grenzfälle nur für die Swift-Parität (Regeln, die die Musterdateien kaum treffen)
def rows(head, lines): return head + "\n" + "\n".join(lines)
def monthly(day, n, start=(2025, 10)):
    y, m = start; out = []
    for i in range(n):
        out.append(f"{day:02d}.{m:02d}.{y}"); m += 1
        if m > 12: m = 1; y += 1
    return out
BASE = [f"{d};LASTSCHRIFT Sunrise GmbH;-39.00;Lastschrift;CHF" for d in monthly(5, 12)]
H = "Datum;Buchungstext;Betrag;Typ;Währung"
EXTRA = {
 "x_card_spiegel": rows(H, BASE + ["03.09.2026;KAUF/DIENSTLEISTUNG VOM 02.09.2026 KARTEN NR. XXXX1234 Spiegel Hamburg;-19.99;Lastschrift;EUR"]),
 "x_card_spiegel_web": rows(H, BASE + ["03.09.2026;KAUF/DIENSTLEISTUNG VOM 02.09.2026 KARTEN NR. XXXX1234 Spiegel spiegel.de;-19.99;Lastschrift;EUR"]),
 "x_garten": rows(H, BASE + [f"{d};Garten Center Spiegel;-25.00;Karte;CHF" for d in monthly(7, 6)]),
 "x_cluster": rows(H, BASE + [f"{d};LASTSCHRIFT Muster Assekuranz;-{a};Lastschrift;CHF" for d, a in zip(monthly(10, 12), ["12.50", "8.90"] * 6)]),
 "x_price": rows(H, BASE + [f"{d};LASTSCHRIFT Muster Streaming;-{'10.00' if i < 6 else '11.00'};Lastschrift;CHF" for i, d in enumerate(monthly(12, 12))]),
 "x_varies": rows(H, BASE + [f"{d};E-RECHNUNG EW Muster Energie AG;-{a};Lastschrift;CHF" for d, a in zip(monthly(20, 12), ["98.10", "102.40", "99.95", "101.20", "97.80", "100.00", "103.10", "98.70", "100.50", "99.10", "101.90", "100.30"])]),
 "x_cred_once": rows("Buchungstag;Auftraggeber / Begünstigter;Verwendungszweck;Gläubiger-ID;Mandatsreferenz;Betrag (EUR)",
     [f"{d};Telekom Deutschland GmbH;Festnetz;DE11TEL00000012345;M-1;-39,95" for d in monthly(3, 12)] + ["15.09.2026;Muster Haftpflicht VVaG;Jahresbeitrag 2026/27;DE22ZZZ00000099999;POL-778;-118,40"]),
 "x_paypal": rows(H, BASE + [f"{d};PayPal Europe S.a.r.l. et Cie;-9.49;Lastschrift;CHF" for d in monthly(14, 8, (2026, 1))] ),
 "x_quarterly_skip": rows(H, BASE + [f"{d};Muster Wasserversorgung AG;-80.00;Lastschrift;CHF" for d in ["15.10.2025", "15.01.2026", "15.07.2026"]]),
 "x_atm_and_retail": rows(H, BASE + [f"{d};Bezug Sparkasse Konstanz;-200.00;Karte;CHF" for d in monthly(9, 6)] + [f"{d};Migros M Kreuzlingen;-54.30;Karte;CHF" for d in monthly(11, 6)]),
 # v177–v223: Einnahmen, Kontoinhaber, Zahlungsart/Nummern, Zeitraum, Kontoführung, Zusatzzahlung, Detailhändler per Lastschrift, Rechtsform vorne
 "x_owner_income": rows("Kontoinhaber;Sinan Muster\nIBAN;CH93 0076 2011 6238 5295 7\n\n" + H, BASE + [f"{d};GUTSCHRIFT Muster Pharma AG Lohn {d[3:5]}/{d[6:]};5820.40;Gutschrift;CHF" for d in monthly(25, 12)]
     + [f"{d};GUTSCHRIFT Muster Pharma AG 13. Monatslohn;5820.40;Gutschrift;CHF" for d in ["20.12.2025"]] + [f"{d};Kinderzulage Familienausgleichskasse;215.00;Gutschrift;CHF" for d in monthly(10, 6, (2026, 4))]
     + [f"{d};TWINT von Lara;40.00;Gutschrift;CHF" for d in monthly(3, 8)]),
 "x_numbers": rows(H, BASE + [f"{d};LASTSCHRIFT Muster Versicherung AG Police 12.345.678 Kd-Nr. 998877;-48.70;Lastschrift;CHF" for d in monthly(2, 12)]
     + [f"{d};E-RECHNUNG Muster Strom AG Rechnung;-120.00;Lastschrift;CHF" for d in monthly(28, 4, (2026, 6))] + [f"{d};DAUERAUFTRAG Immo Seeblick AG Miete Wohnung 3.OG;-1850.00;Dauerauftrag;CHF" for d in monthly(1, 12)]),
 "x_period": rows("Buchungstag;Auftraggeber / Begünstigter;Verwendungszweck;Gläubiger-ID;Mandatsreferenz;Betrag (EUR)",
     ["15.07.2026;Rundfunk ARD, ZDF, DRadio;Rundfunk 07.2026 - 09.2026 Beitragsnr. 123456789;DE70ZZZ00000000001;M-777;-55,08",
      "02.09.2026;Muster Verein e.V.;Jahresbeitrag 2026;DE11ZZZ00000012345;MV-1;-60,00",
      "30.09.2026;;ENTGELTABSCHLUSS Entgeltabrechnung siehe Anlage;;;-7,90", "30.06.2026;;ENTGELTABSCHLUSS Entgeltabrechnung siehe Anlage;;;-7,90",
      "31.03.2026;;ENTGELTABSCHLUSS Entgeltabrechnung siehe Anlage;;;-7,90", "31.12.2025;;ENTGELTABSCHLUSS Entgeltabrechnung siehe Anlage;;;-7,90"]
     + [f"{d};Telekom Deutschland GmbH;Festnetz;DE11TEL00000012345;M-1;-39,95" for d in monthly(3, 12)]),
 "x_lone_extra": rows(H, BASE + [f"{d};LASTSCHRIFT Muster Energie AG;-{a};Lastschrift;CHF" for d, a in zip(monthly(18, 12), ["95.00"] * 5 + ["148.35"] + ["95.00"] * 6)]),
 "x_retail_lsv": rows(H, BASE + [f"{d};LSV Genossenschaft Migros Ostschweiz Fitnesspark;-89.00;Lastschrift;CHF" for d in monthly(6, 12)]),
}
# v272 (Web 23.10.2026): 13. Monatslohn als eigene Einnahme, Lohnverlauf, weitere Datumsformate, gekündigter Vertrag weiter abgebucht
SAL = [f"{d};GUTSCHRIFT Muster Pharma AG Lohn;{'5820.40' if i < 7 else '6020.00'};Gutschrift;CHF" for i, d in enumerate(monthly(25, 12))]
EXTRA.update({
 "x_bonus": rows(H, BASE + SAL + ["20.12.2025;GUTSCHRIFT Muster Pharma AG Lohn;5820.40;Gutschrift;CHF"]),
 "x_bonus_same": rows(H, BASE + [f"{d};GUTSCHRIFT Muster Pharma AG Lohn;{'11640.80' if d.startswith('25.12') else '5820.40'};Gutschrift;CHF" for d in monthly(25, 12)]),
 "x_dates_ymd": rows(H, [f"{d[6:]}/{d[3:5]}/{d[:2]};LASTSCHRIFT Sunrise GmbH;-39.00;Lastschrift;CHF" for d in monthly(5, 12)]),
 "x_dates_words": rows(H, [f"{int(d[:2])}. {['Jan','Feb','Mär','Apr','Mai','Jun','Jul','Aug','Sep','Okt','Nov','Dez'][int(d[3:5]) - 1]}. {d[6:]};LASTSCHRIFT Sunrise GmbH;-39.00;Lastschrift;CHF" for d in monthly(5, 12)]),
 "x_dates_en": rows(H, [f"{['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][int(d[3:5]) - 1]} {int(d[:2])}, {d[6:]};LASTSCHRIFT Sunrise GmbH;-39.00;Lastschrift;CHF" for d in monthly(5, 12)]),
 "x_eom_due": rows(H, [f"{d};LASTSCHRIFT Muster Leasing AG;-410.00;Lastschrift;CHF" for d in ["31.10.2025", "28.11.2025", "31.12.2025", "30.01.2026", "27.02.2026", "31.03.2026", "30.04.2026", "29.05.2026", "30.06.2026", "31.07.2026", "31.08.2026", "30.09.2026"]]),
})
for k, t in EXTRA.items(): EDGE[k] = {"txt": t}
EDGE["x_after"] = {"txt": rows(H, BASE[:6] + [f"{d};LASTSCHRIFT Muster Fitness AG;-79.00;Lastschrift;CHF" for d in monthly(15, 12)]),
                   "contracts": {"f": {"partner": "Muster Fitness AG", "cat": "Freizeit & Sport", "amount": 79, "cur": "CHF", "cycle": 1, "due": "2026-05-15",
                                       "cancelPer": "2026-05-31", "cancelledOn": "2026-02-10", "status": "cancelled", "holders": ["Sinan"]}}}
MULTI = [["samples/ch_postfinance.csv", "samples/ch_postfinance.csv"],
         ["real/de/de_sparkasse_camt_v2.csv", "real/de/de_sparkasse_kreditkarte.csv"],
         ["samples/ch_postfinance.csv", "samples/ch_ubs.csv", "samples/ch_camt053.xml"]]
CHECK_CONTRACTS = {"a": {"partner": "CSS", "cat": "Versicherung", "amount": 389.60, "cur": "CHF", "cycle": 1, "due": "2026-11-01", "status": "active", "holders": ["Sinan"]},
                   "b": {"partner": "Netflix", "cat": "Abos & Medien", "amount": 18.90, "cur": "CHF", "cycle": 1, "due": "2026-10-12", "status": "active", "holders": ["Sinan"]}}
# Kompakte Form je Ergebnis (gleiche Felder liest BankParityTests.swift)
LIB = r"""
window.__bk=function(){var B=window.KontivoBank();
 function u8(b64){var bin=atob(b64),u=new Uint8Array(bin.length);for(var i=0;i<bin.length;i++)u[i]=bin.charCodeAt(i);return u.buffer;}
 function tx(r){return r.tx.map(function(t){return [t.d,t.a,t.cur||"",t.name||"",t.text||"",t.type||"",t.kind||"",t.cred||"",t.mref||""];});}
 function sg(s){var m=s.match,c=m?B.state.contracts[m.id]:null;
   return {key:s.key,name:s.name,raw:s.raw||"",text:s.text||"",cur:s.cur,amount:s.amount,cycle:s.cycle,due:s.due,first:s.first,last:s.last,n:s.n,
     dates:s.dates,amounts:s.amounts,conf:s.conf,varies:!!s.varies,change:s.change||null,tpl:s.tpl?s.tpl[0]:null,cat:s.cat,kind:s.kind||"",
     cred:s.cred||"",mref:s.mref||"",ignored:!!s.ignored,
     match:m?{kind:m.kind,partner:c?c.partner:"",amount:m.amount==null?null:m.amount,old:m.old==null?null:m.old,from:m.from||null}:null};}
 function kn(s){var c=B.state.contracts[s.match.id];return {key:s.key,name:s.name,partner:c?c.partner:"",loose:!!s.loose,amount:s.amount};}
 function tc(s){var c=B.toContract(s,["Sinan"]);return {partner:c.partner,label:c.label,cat:c.cat,amount:c.amount,cur:c.cur,cycle:c.cycle,due:c.due,
   notice:c.notice,noticeU:c.noticeU,cancTerm:c.cancTerm,mand:c.mand,cancF:c.cancF,cancUrl:c.cancUrl,web:c.web,tel:c.tel,mail:c.mail,addr:c.addr,
   prices:c.prices,noCancel:!!c.noCancel,holders:c.holders,payM:c.payM||"",custNo:c.custNo||"",contrNo:c.contrNo||"",bkLabel:B.label(s)};}
 function inc(r){var f=B.findInc(r);return {sugg:f.sugg.map(function(s){return {key:s.key,name:s.name,label:s.label,cat:s.cat,cur:s.cur,amount:s.amount,cycle:s.cycle,due:s.due,
   n:s.n,first:s.first,last:s.last,dates:s.dates,amounts:s.amounts,lo:s.lo,hi:s.hi,varies:!!s.varies,skipped:s.skipped,raw:s.raw||"",text:s.text||"",conf:s.conf,
   once:!!s.once,hist:(function(){var h=B.priceHist(s,true);return h?{base:h.base,prices:h.prices}:null;})()};}),
   known:f.known.map(function(s){var c=B.state.incomes[s.match];return {key:s.key,name:s.name,income:c?(c.name||c.label):""};})};}
 function find(r,withTc){var f=B.find(r,[]);var o={sugg:f.sugg.map(sg),known:f.known.map(kn),inc:inc(r),
   after:(f.after||[]).map(function(a){return {partner:a.c.partner,n:a.n,last:a.last,amount:a.amount,cur:a.cur};})};if(withTc)o.contracts=f.sugg.map(tc);return o;}
 function read(r){return r?{bank:r.bank||"",fmt:r.fmt,n:r.tx.length,from:r.from,to:r.to,owner:r.owner||"",tx:tx(r)}:null;}
 return {
  file:function(b64,withTx,withTc){var r=B.read(u8(b64));if(!r)return null;var o=read(r);if(!withTx)delete o.tx;o.find=find(r,withTc);return o;},
  text:function(txt,contracts,alias){B.state.contracts=contracts||{};B.state.settings.bankAlias=alias||{};var r=B.read(txt);
    var o=r?read(r):null;if(o){delete o.tx;o.find=find(r,true);}B.state.contracts={};B.state.settings.bankAlias={};return o;},
  multi:function(list){var rs=list.map(function(b){return B.read(u8(b));});var r=B.merge(rs);var o=read(r);delete o.tx;o.find=find(r,false);return o;}
 };};
"""
def b64(rel): return base64.b64encode(open(os.path.join(HERE, rel), "rb").read()).decode()
out = {"today": "2026-10-08", "home": "CHF", "holders": ["Sinan"], "emptyBackup": backup({}), "checkBackup": backup(CHECK_CONTRACTS),
       "files": {}, "check": {}, "edge": {}, "edgeInput": {k: {"txt": c["txt"], "backup": backup(c.get("contracts")), "alias": c.get("alias") or {}} for k, c in EDGE.items()}, "multi": []}
with sync_playwright() as p:
    b = p.chromium.launch(); ctx = b.new_context(); ctx.add_init_script("window.__KONTIVO_TODAY='2026-10-08';")
    def serve(r):
        u = r.request.url
        if not u.startswith("http://localhost"): return r.abort()
        if u.split("?")[0].endswith("/index.html"):
            html = open(os.path.join(WEB, "index.html"), encoding="utf-8").read()
            hook = "window.KontivoBank=function(){return {"
            assert hook in html
            html = html.replace(hook, hook + "label:bankLabel,payM:bankPayM,nums:bankNums,who:bkWho,priceHist:bankPriceHist,", 1)
            # Tempo: lnorm/ltok sind reine Funktionen – Zwischenspeicher ändert kein Ergebnis (ltok liefert eine Kopie)
            ln = 'function lnorm(s){return String(s||"")'
            assert html.count(ln) == 1 and html.count("function ltok(s){") == 1
            html = html.replace(ln, 'var __LN=new Map();function lnorm(s){var k=String(s||"");var v=__LN.get(k);if(v===undefined){v=__lnorm0(k);__LN.set(k,v);}return v;}function __lnorm0(s){return String(s||"")', 1)
            html = html.replace("function ltok(s){", 'var __LT=new Map();function ltok(s){var k=String(s||"");var v=__LT.get(k);if(!v){v=__ltok0(k);__LT.set(k,v);}return v.slice();}function __ltok0(s){', 1)
            return r.fulfill(status=200, content_type="text/html; charset=utf-8", body=html)
        return r.continue_()
    ctx.route("**/*", serve)
    pg = ctx.new_page(); pg.goto(URL)
    def setState(contracts):
        st = {"settings": {"home": "CHF", "onboarded": 9, "holders": ["Sinan"], "rateTs": 9999999999999}, "contracts": contracts, "incomes": {}}
        pg.evaluate("s=>localStorage.setItem('vertraege.v1',s)", json.dumps(st)); pg.reload(); pg.wait_for_timeout(400); pg.evaluate(LIB)
    setState({})
    for f in FILES:
        out["files"][f] = pg.evaluate("([b,x,c])=>window.__bk().file(b,x,c)", [b64(f), True, True]); print(".", end="", flush=True)
    for k, c in EDGE.items(): out["edge"][k] = pg.evaluate("([t,c,a])=>window.__bk().text(t,c,a)", [c["txt"], c.get("contracts"), c.get("alias")])
    for m in MULTI: out["multi"].append({"files": m, "result": pg.evaluate("(l)=>window.__bk().multi(l)", [b64(x) for x in m])})
    setState(CHECK_CONTRACTS)
    for f in FILES: out["check"][f] = pg.evaluate("([b,x,c])=>window.__bk().file(b,x,c)", [b64(f), False, False])
    b.close()
json.dump(out, open(os.path.join(HERE, "expected.json"), "w"), ensure_ascii=False, separators=(",", ":"))
print(len(FILES), "Dateien,", len(EDGE), "Grenzfälle,", len(MULTI), "Kombinationen →", os.path.getsize(os.path.join(HERE, "expected.json")) // 1024, "KB")
