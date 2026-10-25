"""Testgenerator Kontoauszug-Import (25.10.2026): erfundene Auszüge mit bekannter Wahrheit, CH (CHF) und DE (EUR).
Misst Trefferquote, Fehlalarme, Rhythmus/Betrag, Bezeichnung/Kategorie. Nur erfundene Namen («Muster …») und bekannte Katalog-Anbieter.
Aufruf im Repo-Ordner:  python3 -m http.server 8765 &  python3 tests/bank/gen.py [Anzahl Personen] [Seed]"""
import json, os, random, re, sys
from datetime import date, timedelta
from playwright.sync_api import sync_playwright
URL = os.environ.get("KONTIVO_URL", "http://localhost:8765/index.html")
TODAY = date(2026, 10, 8); START = date(2023, 10, 1); END = date(2026, 9, 30)

def months(a, b):
    y, m = a.year, a.month
    while (y, m) <= (b.year, b.month):
        yield y, m
        m += 1
        if m > 12: y, m = y + 1, 1
def day(y, m, d):
    import calendar
    return date(y, m, min(d, calendar.monthrange(y, m)[1]))

class P:
    def __init__(s, rnd, de):
        s.r, s.de, s.tx, s.truth, s.notc = rnd, de, [], [], []
    def add(s, d, text, a, kind=""):
        if START <= d <= END: s.tx.append((d, text, round(a, 2), kind))
    def truth_(s, name, cyc, amt, label=None, cat=None, tol=0.011):
        s.truth.append(dict(name=name, cyc=cyc, amt=round(amt, 2), label=label, cat=cat, tol=tol))

def person_ch(r):
    p = P(r, False); cur = "CHF"
    # Miete (Dauerauftrag, Mitteilung)
    rent = r.choice([1450, 1850, 2200, 2700]); dd = r.choice([25, 28, 30])
    for y, m in months(START, END): p.add(day(y, m, dd), "DAUERAUFTRAG Seeblick Immobilien AG Mitteilung: Miete Wohnung", -rent, "so")
    p.truth_("Seeblick Immobilien", 1, rent, "Miete", "Wohnen")
    # Telecom mit Preiserhöhung
    tel = r.choice([39.9, 49.9, 59.0]); up = r.choice([0, 3.0, 5.0]); chg = date(2025, r.randint(2, 11), 1)
    for y, m in months(START, END):
        d = day(y, m, 5); p.add(d, "LASTSCHRIFT Helvetel Telecom AG", -(tel + (up if d >= chg else 0)), "dd")
    p.truth_("Helvetel Telecom", 1, tel + up)
    # Krankenkasse: jedes Jahr im Januar neue Prämie
    kk = r.choice([380, 620, 980, 1280]); a = kk
    for y, m in months(START, END):
        if m == 1: a = round(a * r.uniform(1.02, 1.08), 2)
        p.add(day(y, m, 1), "LASTSCHRIFT Alpina Krankenkasse Mitteilung: Praemie", -a, "dd")
    p.truth_("Alpina Krankenkasse", 1, a, "Krankenkasse", "Versicherung")
    # Netflix per Karte
    if r.random() < 0.7:
        nf = r.choice([12.9, 18.9, 24.9])
        for y, m in months(START, END): p.add(day(y, m, 12), "KARTENZAHLUNG NETFLIX.COM", -nf, "card")
        p.truth_("Netflix", 1, nf)
    # iCloud plus App-Käufe beim selben Händler
    if r.random() < 0.6:
        for y, m in months(START, END):
            p.add(day(y, m, 17), "KARTENZAHLUNG APPLE.COM/BILL", -3.0, "card")
            if r.random() < 0.3: p.add(day(y, m, r.randint(1, 28)), "KARTENZAHLUNG APPLE.COM/BILL", -r.choice([1.0, 4.0, 7.0, 12.0]), "card")
        p.truth_("Apple", 1, 3.0)
    # Strom quartalsweise, schwankend
    sb = r.choice([150, 220, 300])
    for y, m in months(START, END):
        if m in (1, 4, 7, 10): last_s = round(sb * r.uniform(0.88, 1.12), 2); p.add(day(y, m, r.randint(20, 28)), "ZAHLUNG Energie Seetal Mitteilung: Rechnung Nr %d" % r.randint(100000, 999999), -last_s)
    p.truth_("Energie Seetal", 3, last_s, "Strom", "Energie & Wasser", tol=0.25)
    # Hausrat jährlich, Prämie schwankt, Zahltag ±25 Tage
    hm = r.randint(1, 12); hb = r.choice([320, 410, 520])
    for y in (2023, 2024, 2025, 2026):
        if date(y, hm, 15) > END: continue
        last_h = round(hb * r.uniform(0.9, 1.15), 2); p.add(date(y, hm, 15) + timedelta(days=r.randint(-25, 25)), "ZAHLUNG Bodensee Versicherung AG", -last_h)
    p.truth_("Bodensee Versicherung", 12, last_h, None, "Versicherung", tol=0.2)
    # zweite Police beim selben Versicherer, anderer Monat, anderer Betrag
    if r.random() < 0.5:
        vm = (hm + 5) % 12 + 1; vb = r.choice([780, 1150, 1390])
        for y in (2023, 2024, 2025, 2026):
            if date(y, vm, 20) > END: continue
            last_v = round(vb * r.uniform(0.93, 1.07), 2); p.add(date(y, vm, 20) + timedelta(days=r.randint(-15, 15)), "ZAHLUNG Bodensee Versicherung AG", -last_v)
        p.truth_("Bodensee Versicherung", 12, last_v, None, "Versicherung", tol=0.2)
    # Halbjahresprämie
    if r.random() < 0.5:
        hj = r.choice([180, 260, 390]); m0 = r.randint(1, 6)
        for y in (2023, 2024, 2025, 2026):
            for mm in (m0, m0 + 6):
                p.add(day(y, mm, 10), "ZAHLUNG Rigi Assekuranz AG", -hj)
        p.truth_("Rigi Assekuranz", 6, hj)
    # Verein jährlich (eine oder zwei Zahlungen im Auszug)
    club = r.choice(["FC Musterdorf", "TV Musterberg", "Musikgesellschaft Musterhausen", "STV Mustertal", "Tennisclub Musterwil"])
    cm = r.randint(1, 9); ca = r.choice([120, 180, 250])
    for y in (2025, 2026): p.add(day(y, cm, 15), "ZAHLUNG " + club, -ca)
    p.truth_(club, 12, ca, None, "Freizeit & Sport")
    # Serafe
    for y in (2024, 2025, 2026): p.add(date(y, 5, 10) + timedelta(days=r.randint(-12, 20)), "ZAHLUNG SERAFE AG", -335.0)
    p.truth_("Serafe", 12, 335.0)
    # zwei Fahrzeuge, gleicher Tag
    if r.random() < 0.5:
        k1, k2 = r.choice([168, 210]), r.choice([153.15, 432])
        for y in (2024, 2025, 2026):
            d = date(y, 1, 26) + timedelta(days=r.randint(0, 10))
            p.add(d, "ZAHLUNG Strassenverkehrsamt Musterkanton", -k1); p.add(d, "ZAHLUNG Strassenverkehrsamt Musterkanton", -k2)
        p.truth_("Strassenverkehrsamt", 12, k1); p.truth_("Strassenverkehrsamt", 12, k2)
    # Steuerraten mit Steuerperiode, neue Rate je Jahr
    rt = r.choice([340, 520, 760]); rt0 = rt
    for y, m in months(date(2024, 2, 1), END):
        if m == 2: rt = r.choice([340, 520, 760, 410])
        if 2 <= m <= 11: p.add(day(y, m, 27), "DAUERAUFTRAG Gemeinde Musterdorf Mitteilung: Staats- und Gemeindesteuern Steuerperiode %d" % y, -rt, "so")
    p.truth_("Gemeinde Musterdorf", 1, rt, "Staats- und Gemeindesteuern", "Steuern & Gebühren")
    # beendeter Vertrag (soll NICHT kommen)
    for y, m in months(date(2024, 1, 1), date(2025, 12, 31)): p.add(day(y, m, 8), "LASTSCHRIFT Vitalis Fitnesspark", -79.0, "dd")
    p.notc.append("Vitalis Fitnesspark")
    noise(p, r, False)
    return p

def person_de(r):
    p = P(r, True)
    for y, m in months(START, END): p.add(day(y, m, 1), "Rheinblick Hausverwaltung GmbH|Miete Wohnung", -r.choice([980.0]), "so")
    p.truth_("Rheinblick Hausverwaltung", 1, 980.0, "Miete", "Wohnen")
    tk = r.choice([39.95, 44.95])
    for y, m in months(START, END): p.add(day(y, m, 3), "Telekom Deutschland GmbH|Lastschrift Festnetz", -tk, "dd")
    p.truth_("Telekom", 1, tk)
    for y, m in months(START, END):
        if m in (1, 4, 7, 10): p.add(day(y, m, 15), "ARD ZDF Deutschlandradio Beitragsservice|Rundfunkbeitrag", -55.08, "dd")
    p.truth_("Beitragsservice", 3, 55.08)
    ha = r.choice([89.4, 112.0])
    for y in (2023, 2024, 2025, 2026):
        if date(y, 3, 1) <= END: p.add(date(y, 3, 1), "HUK-COBURG Versicherung|Haftpflicht Beitrag", -ha, "dd")
    p.truth_("HUK", 12, ha)
    for y, m in months(START, END): p.add(day(y, m, 30), "Sparkasse Musterstadt|Entgeltabschluss Kontofuehrung", -6.9, "dd")
    p.truth_("Sparkasse", 1, 6.9)
    for y in (2024, 2025, 2026): p.add(date(y, 2, 10), "TSV Musterstadt e.V.|Mitgliedsbeitrag %d" % y, -96.0, "dd")
    p.truth_("TSV Musterstadt", 12, 96.0, None, "Freizeit & Sport")
    for y in (2024, 2025, 2026): p.add(date(y, 6, 20), "Bundeskasse Hauptzollamt|Kraftfahrzeugsteuer", -148.0, "dd")
    p.truth_("Bundeskasse Hauptzollamt", 12, 148.0)
    noise(p, r, True)
    return p

SHOPS_CH = ["Migros M Musterstadt", "Coop Pronto Musterstadt", "Denner Musterdorf", "Hobbyland Baumarkt", "Restaurant Musterhof", "Muster Apotheke", "SBB CFF FFS", "Muster Tankstelle"]
SHOPS_DE = ["REWE Markt", "EDEKA Center", "Lidl Dienstleistung", "dm-drogerie markt", "Hobbyland Baumarkt", "Aral Tankstelle", "Restaurant Musterhof"]
def noise(p, r, de):
    shops = SHOPS_DE if de else SHOPS_CH
    d = START
    while d <= END:
        for _ in range(r.randint(0, 2)):
            sh = r.choice(shops); a = round(r.uniform(4, 160), 2)
            p.add(d, ("Kartenzahlung|" if de else "KARTENZAHLUNG ") + sh, -a, "card")
        if r.random() < 0.06: p.add(d, ("PayPal Europe|Ihr Einkauf bei Muster Shop" if de else "KARTENZAHLUNG AMAZON.DE"), -round(r.uniform(9, 90), 2), "card")
        if r.random() < 0.04: p.add(d, ("Max Muster|Umbuchung Sparkonto" if de else "KONTOUEBERTRAG Max Muster"), -r.choice([100, 200, 500, 1000]))
        if r.random() < 0.03 and not de: p.add(d, "KARTENZAHLUNG Revolut**1234*", -r.choice([50, 100, 200, 300]), "card")
        if r.random() < 0.02: p.add(d, ("Stadt Musterstadt|Verwarnungsgeld" if de else "ZAHLUNG Stadtpolizei Musterstadt Busse"), -r.choice([40, 60, 120]))
        if r.random() < 0.02: p.add(d, ("Praxis Dr. Muster|Rechnung" if de else "ZAHLUNG Praxis Dr. Muster Rechnung"), -round(r.uniform(60, 300), 2))
        if r.random() < 0.03: p.add(d, ("Max Muster|Erstattung" if de else "GUTSCHRIFT Muster Shop Rueckerstattung"), round(r.uniform(10, 80), 2))
        d += timedelta(days=1)
    # Lohn als Einnahme (nicht Teil der Fixkosten-Wahrheit)
    for y, m in months(START, END): p.add(day(y, m, 25), ("Muster Arbeitgeber GmbH|Lohn/Gehalt" if de else "GUTSCHRIFT Muster Arbeitgeber AG Lohn"), 5200.0)

def to_csv(p):
    p.tx.sort(key=lambda t: t[0])
    if p.de:
        h = "Buchungstag;Valuta;Auftraggeber/Zahlungsempfänger;Empfänger/Zahlungspflichtiger;Konto-Nr.;IBAN;BLZ;BIC;Vorgang/Verwendungszweck;Kundenreferenz;Währung;Umsatz;Soll/Haben"
        L = [h]
        for d, text, a, k in p.tx:
            nm, vz = (text.split("|") + [""])[:2]; ds = d.strftime("%d.%m.%Y")
            am = f"{abs(a):.2f}".replace(".", ",")
            L.append(f"{ds};{ds};{nm};Max Muster;;DE00;;;{vz};;EUR;{am}" + (";S" if a < 0 else ";H"))
        return "\n".join(L)
    return "\n".join(["Datum;Buchungstext;Betrag"] + [f"{d.strftime('%d.%m.%Y')};{t};{a:.2f}" for d, t, a, k in p.tx])

JS = """(txt)=>{var B=window.KontivoBank();B.state.contracts={};B.state.settings.bankAlias={};B.state.settings.bankLearn={};var r=B.read(txt);if(!r)return null;var f=B.find(r,[]);
 return f.sugg.map(function(s){return {n:s.name,c:s.cycle,a:s.amount,conf:s.conf,l:window.__lbl?window.__lbl(s):'',cat:s.cat||''};});}"""
def norm(x): return re.sub(r"[^a-z0-9]", "", x.lower().replace("ä", "a").replace("ö", "o").replace("ü", "u"))

def evaluate(n=40, seed=1, verbose=False):
    rnd = random.Random(seed); persons = [(person_de if i % 4 == 3 else person_ch)(random.Random(rnd.random())) for i in range(n)]
    M = dict(truth=0, hit=0, wrongcyc=0, wrongamt=0, miss=0, fp=0, fpq=0, notc=0, label_ok=0, label_n=0, cat_ok=0, cat_n=0)
    issues = []
    with sync_playwright() as pw:
        b = pw.chromium.launch(); ctx = b.new_context(); ctx.add_init_script("window.__KONTIVO_TODAY='%s';" % TODAY.isoformat())
        ctx.route(re.compile(r"^https?://(?!localhost)"), lambda r: r.abort())
        pg = ctx.new_page(); pg.goto(URL); pg.wait_for_timeout(1200)
        pg.evaluate("()=>{window.__lbl=function(s){try{return window.KontivoBank().state&&window.__bl?window.__bl(s):''}catch(e){return ''}};}")
        for i, p in enumerate(persons):
            sug = pg.evaluate(JS, to_csv(p))
            if sug is None: issues.append((i, "nicht gelesen", "")); continue
            used = set()
            for t in p.truth:
                M["truth"] += 1
                cands = [j for j, s in enumerate(sug) if j not in used and norm(s["n"]).startswith(norm(t["name"])[:12])]
                ok = [j for j in cands if s_ok(sug[j], t)]
                if ok:
                    j = ok[0]; used.add(j); M["hit"] += 1
                    if t["cat"]: M["cat_n"] += 1; M["cat_ok"] += sug[j]["cat"] == t["cat"]
                    if t["cat"] and sug[j]["cat"] != t["cat"]: issues.append((i, "Kategorie", f"{t['name']}: {sug[j]['cat']} statt {t['cat']}"))
                elif cands:
                    j = min(cands, key=lambda j: abs(sug[j]["a"] - t["amt"])); used.add(j)
                    if sug[j]["c"] != t["cyc"]: M["wrongcyc"] += 1; issues.append((i, "Rhythmus", f"{t['name']} {t['amt']}: {sug[j]['c']}M statt {t['cyc']}M ({sug[j]['a']})"))
                    else: M["wrongamt"] += 1; issues.append((i, "Betrag", f"{t['name']} {t['cyc']}M: {sug[j]['a']} statt {t['amt']}"))
                else: M["miss"] += 1; issues.append((i, "fehlt", f"{t['name']} {t['cyc']}M {t['amt']}"))
            for j, s in enumerate(sug):
                if j in used: continue
                if any(norm(s["n"]).startswith(norm(x)[:12]) for x in p.notc): M["notc"] += 1; issues.append((i, "beendet vorgeschlagen", s["n"])); continue
                if s["conf"] == "niedrig": M["fpq"] += 1; issues.append((i, "Rückfrage ohne Vertrag", f"{s['n']} {s['c']}M {s['a']}"))
                else: M["fp"] += 1; issues.append((i, "Fehlalarm", f"{s['n']} {s['c']}M {s['a']} ({s['conf']})"))
        b.close()
    return M, issues

def s_ok(s, t):
    return s["c"] == t["cyc"] and abs(s["a"] - t["amt"]) <= max(0.01, t["amt"] * t["tol"])

if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 40; seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    M, iss = evaluate(n, seed)
    from collections import Counter
    print(json.dumps(M))
    print("Trefferquote %.1f %% · Fehlalarme %d · Rückfragen ohne Vertrag %d · Kategorie %d/%d" % (100 * M["hit"] / max(1, M["truth"]), M["fp"], M["fpq"], M["cat_ok"], M["cat_n"]))
    c = Counter((k, re.sub(r"[\d.]+", "#", v)) for _, k, v in iss)
    for (k, v), cnt in c.most_common(40): print(f"{cnt:4d}  {k:24s} {v}")
    # Abnahme (25.10.2026): Trefferquote ≥ 99 %, höchstens 1 Fehlalarm pro 20 Personen
    ok = M["hit"] >= 0.99 * M["truth"] and M["fp"] <= max(1, n // 20)
    print("Alles gut" if ok else "Unter Abnahmegrenze"); sys.exit(0 if ok else 1)
