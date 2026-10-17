"""Stresstest Kontoauszug-Import (17.10.2026): drei fiktive Auszüge über 18 Monate (01.04.2025–15.10.2026) mit vielen
Alltagsbuchungen und Sonderfällen. Nur Testdaten, keine echten Personen/Konten. Formate wie tests/bank/real (Quellen dort).
  de_sparkasse_stress.csv  Sparkasse CSV-CAMT V2 (cp1252, alle Felder in "", TT.MM.JJ, absteigend, vorgemerkte Umsätze)
  de_volksbank_stress.csv  VR/Atruvia (UTF-8 mit BOM, CRLF, ohne "", TT.MM.JJJJ, Saldo nach Buchung)
  ch_tkb_stress.csv        Thurgauer Kantonalbank 2024 (cp1252, mehrzeiliger Buchungstext, Sammelbelastung, kein Zeilenende)
Aufruf: python3 tests/bank/stress/make_stress.py"""
import os, random, datetime as dt
D = os.path.dirname(os.path.abspath(__file__)); S, E = dt.date(2025, 4, 1), dt.date(2026, 10, 15)
def months(day, step=1, start=S, end=E, first=None):
    y, m = (first or start).year, (first or start).month
    while True:
        last = (dt.date(y + m // 12, m % 12 + 1, 1) - dt.timedelta(days=1)).day; d = dt.date(y, m, min(day, last))
        if d > end: break
        if d >= start: yield d
        m += step
        while m > 12: m -= 12; y += 1
def bday(d):  # Wochenende → Montag (Lastschriften)
    while d.weekday() >= 5: d += dt.timedelta(days=1)
    return d
# ================= Deutschland (EUR) =================
def de_scenario(seed, who):
    R = random.Random(seed); T = []
    def t(d, a, name, text, kind, iban="", cred="", mref="", pend=False): T.append(dict(d=d, a=round(a, 2), name=name, text=text, kind=kind, iban=iban, cred=cred, mref=mref, pend=pend))
    for d in months(1):  # Miete mit Erhöhung ab 04/2026
        t(d, -(1180 if d < dt.date(2026, 4, 1) else 1215), "Wohnbau Konstanz GmbH", "Miete Wohnung 2.OG Rheingutstr. 14", "DAUERAUFTRAG", "DE00690500010000123456")
    for d in months(3):
        if d >= dt.date(2026, 8, 1) and d < dt.date(2026, 9, 1):  # Rücklastschrift + erneuter Einzug
            t(bday(d), -39.95 - 5.0, "Telekom Deutschland GmbH", "Kd-Nr 123456789 RG 0815/" + d.strftime("%m%y"), "FOLGELASTSCHRIFT", cred="DE81ZZZ00000013312", mref="TKD-77")
            t(bday(d) + dt.timedelta(days=3), 44.95, "Telekom Deutschland GmbH", "RUECKLASTSCHRIFT Kd-Nr 123456789", "RUECKLASTSCHRIFT", cred="DE81ZZZ00000013312", mref="TKD-77")
            t(bday(d) + dt.timedelta(days=10), -44.95, "Telekom Deutschland GmbH", "Kd-Nr 123456789 RG 0815/" + d.strftime("%m%y"), "FOLGELASTSCHRIFT", cred="DE81ZZZ00000013312", mref="TKD-77")
            continue
        t(bday(d), -(39.95 if d < dt.date(2026, 7, 1) else 44.95), "Telekom Deutschland GmbH", "Kd-Nr 123456789 RG 0815/" + d.strftime("%m%y"), "FOLGELASTSCHRIFT", cred="DE81ZZZ00000013312", mref="TKD-77")
    for d in months(15, end=dt.date(2025, 12, 31)):  # gekündigt: Vodafone Kabel endet 12/2025
        t(bday(d), -34.99, "Vodafone Deutschland GmbH", "Kabel Internet 200 Kd 556677", "FOLGELASTSCHRIFT", cred="DE29ZZZ00000014409", mref="VF-556677")
    for d in months(12): t(d, -13.99, "NETFLIX.COM", "NETFLIX.COM//Amsterdam/NL " + d.strftime("%Y-%m-%d"), "KARTENZAHLUNG")
    for d in months(5): t(bday(d), -(11.99 if d < dt.date(2026, 1, 1) else 12.99), "PayPal Europe S.a.r.l. et Cie S.C.A", "1045332211 PP.7812.PP . Spotify AB, Ihr Einkauf bei Spotify AB", "FOLGELASTSCHRIFT", cred="LU96ZZZ0000000000000000058", mref="5JMJ224")
    for d in months(18, start=dt.date(2026, 5, 1)): t(d, -9.99, "Disney Plus", "DISNEY PLUS//Amsterdam/NL " + d.strftime("%Y-%m-%d"), "KARTENZAHLUNG")
    for d in months(15, step=3, first=dt.date(2025, 5, 1)): t(bday(d), -55.08, "Rundfunk ARD, ZDF, DRadio", "Beitragsnummer 123456789 " + d.strftime("%m.%Y"), "FOLGELASTSCHRIFT", cred="DE70ZZZ00000004206", mref="RF-123456789")
    for d in months(2, step=12, first=dt.date(2025, 5, 1)): t(bday(d), -89.40, "Allianz Versicherungs-AG", "Privathaftpflicht Vers-Nr. AS-445566 Beitrag " + str(d.year), "FOLGELASTSCHRIFT", cred="DE43ZZZ00000043545", mref="AZ-445566")
    for d in months(1, step=6, first=dt.date(2025, 8, 1)): t(bday(d), -214.30, "HUK-COBURG", "Kfz-Versicherung KN-AB 123 halbjährlich", "FOLGELASTSCHRIFT", cred="DE18ZZZ00000032321", mref="HUK-99881")
    for d in months(10):
        t(bday(d), -(96.00 if d < dt.date(2026, 3, 1) else 104.00), "Stadtwerke Konstanz GmbH", "Abschlag Strom/Gas Vertragskonto 400123456", "FOLGELASTSCHRIFT", cred="DE91ZZZ00000002131", mref="SWK-400123456")
    t(dt.date(2026, 2, 20), -143.22, "Stadtwerke Konstanz GmbH", "Jahresabrechnung 2025 Nachzahlung Vertragskonto 400123456", "FOLGELASTSCHRIFT", cred="DE91ZZZ00000002131", mref="SWK-400123456")
    for d in months(1): t(bday(d), -24.90, "McFit GmbH", "Mitgliedsbeitrag " + d.strftime("%m/%Y") + " Mitgl.-Nr. 7788", "FOLGELASTSCHRIFT", cred="DE11ZZZ00000188776", mref="MCF-7788")
    t(dt.date(2025, 9, 1), -19.90, "McFit GmbH", "Servicepauschale Mitgl.-Nr. 7788", "FOLGELASTSCHRIFT", cred="DE11ZZZ00000188776", mref="MCF-7788")
    for d in months(28): t(bday(d), -15.00, "congstar", "congstar Rechnung " + d.strftime("%m/%Y") + " Kd 0172998877", "FOLGELASTSCHRIFT", cred="DE45ZZZ00000231234", mref="CS-0172998877")
    for d in months(14, step=12, first=dt.date(2025, 6, 1)): t(d, -89.90, "AMAZON PRIME", "Amazon Prime*AB12CD//Amazon.de/LU " + d.strftime("%Y-%m-%d"), "KARTENZAHLUNG")
    for d in months(16): t(d, -200.00, "Trade Republic Bank GmbH", "Sparplan ETF " + who, "DAUERAUFTRAG", "DE00100123450000654321")
    for d in months(28): t(d, 3920.00 if d < dt.date(2026, 3, 1) else 4050.00, "Muster Pharma GmbH", "Lohn/Gehalt " + d.strftime("%m/%Y") + " PersNr 4711", "GUTSCHR. UEBERWEISUNG", "DE00660000000000123406")
    t(dt.date(2025, 11, 27), 1960.00, "Muster Pharma GmbH", "Weihnachtsgeld 2025 PersNr 4711", "GUTSCHR. UEBERWEISUNG", "DE00660000000000123406")
    for d in months(4): t(d, 255.00, "Bundesagentur für Arbeit - Familienkasse", "Kindergeld KG-Nr. 123FK456789", "GUTSCHR. UEBERWEISUNG", "DE00760000000000000000")
    # Alltag (variabel)
    shops = [("REWE Markt GmbH", "REWE SAGT DANKE//Konstanz/DE", 12, 95), ("EDEKA Baur", "EDEKA BAUR KONSTANZ//Konstanz/DE", 8, 70), ("ALDI SUED", "ALDI SUED SAGT DANKE//Konstanz/DE", 9, 60),
             ("dm-drogerie markt", "DM-DROGERIE MARKT//Konstanz/DE", 5, 40), ("Aral Station", "ARAL STATION 1234//Konstanz/DE", 45, 85), ("Bäckerei Größ", "BAECKEREI GROESS//Konstanz/DE", 3, 12),
             ("Müller Drogerie", "MUELLER HANDELS//Konstanz/DE", 6, 45), ("Lieferando", "LIEFERANDO.DE//Berlin/DE", 18, 46), ("IKEA", "IKEA DEUTSCHLAND//Freiburg/DE", 25, 240)]
    d = S
    while d <= E:
        for _ in range(R.randint(0, 3)):
            n, txt, lo, hi = R.choice(shops); t(d, -round(R.uniform(lo, hi), 2), n, txt + " " + d.strftime("%Y-%m-%d"), "KARTENZAHLUNG")
        if R.random() < 0.08: t(d, -float(R.choice([50, 100, 200])), "", "GA NR00001234 BLZ69050001 Konstanz Bahnhof " + d.strftime("%d.%m"), "BARGELDAUSZAHLUNG")
        if R.random() < 0.06:
            amt = round(R.uniform(9, 160), 2); t(d, -amt, "AMAZON PAYMENTS EUROPE S.C.A.", "Amazon .Mktp DE " + str(R.randint(300, 309)) + "-" + str(R.randint(1000000, 9999999)), "FOLGELASTSCHRIFT", cred="LU96ZZZ0000000000000000058", mref="AMZ" + str(R.randint(1, 99)))
            if R.random() < 0.25: t(d + dt.timedelta(days=R.randint(4, 12)), amt, "AMAZON PAYMENTS EUROPE S.C.A.", "Erstattung Amazon .Mktp DE", "GUTSCHR. UEBERWEISUNG")
        if R.random() < 0.04: t(d, -round(R.uniform(10, 80), 2), "PayPal Europe S.a.r.l. et Cie S.C.A", "1045" + str(R.randint(100000, 999999)) + " PP.7812.PP . " + R.choice(["Zalando SE", "eBay GmbH", "Uber BV", "Booking.com"]) + ", Ihr Einkauf", "FOLGELASTSCHRIFT", cred="LU96ZZZ0000000000000000058", mref="5JMJ224")
        if R.random() < 0.02: t(d, round(R.uniform(15, 60), 2), "Lea Beispiel", "Anteil Abendessen", "GUTSCHR. UEBERWEISUNG", "DE00500000000000000099")
        d += dt.timedelta(days=1)
    t(dt.date(2026, 10, 14), -32.18, "REWE Markt GmbH", "REWE SAGT DANKE//Konstanz/DE 2026-10-14", "KARTENZAHLUNG", pend=True)
    t(dt.date(2026, 10, 15), -13.99, "NETFLIX.COM", "NETFLIX.COM//Amsterdam/NL 2026-10-15", "KARTENZAHLUNG", pend=True)
    T.sort(key=lambda x: x["d"]); return T
def de_amt(a): return f"{a:.2f}".replace(".", ",")
def sparkasse(T, fn):
    H = ["Auftragskonto","Buchungstag","Valutadatum","Buchungstext","Verwendungszweck","Glaeubiger ID","Mandatsreferenz","Kundenreferenz (End-to-End)","Sammlerreferenz","Lastschrift Ursprungsbetrag","Auslagenersatz Ruecklastschrift","Beguenstigter/Zahlungspflichtiger","Kontonummer/IBAN","BIC (SWIFT-Code)","Betrag","Waehrung","Info"]
    L = [";".join('"' + h + '"' for h in H)]
    for x in reversed(T):
        r = ["DE00690500010012345678", x["d"].strftime("%d.%m.%y"), x["d"].strftime("%d.%m.%y"), x["kind"], x["text"], x["cred"], x["mref"], "NOTPROVIDED" if x["kind"].startswith("GUTSCHR") else "", "", "", "", x["name"], x["iban"], "TESTDESSXXX" if x["iban"] else "", de_amt(x["a"]), "EUR", "Umsatz vorgemerkt" if x["pend"] else "Umsatz gebucht"]
        L.append(";".join('"' + str(v) + '"' for v in r))
    open(os.path.join(D, fn), "wb").write(("\r\n".join(L) + "\r\n").encode("cp1252"))
VRK = {"DAUERAUFTRAG": "Dauerauftragsbelast", "FOLGELASTSCHRIFT": "Basislastschrift", "KARTENZAHLUNG": "Kartenzahlung girocard", "GUTSCHR. UEBERWEISUNG": "Überweisungsgutschr.", "BARGELDAUSZAHLUNG": "Auszahlung girocard", "RUECKLASTSCHRIFT": "Rücklastschrift"}
def volksbank(T, fn):
    H = "Bezeichnung Auftragskonto;IBAN Auftragskonto;BIC Auftragskonto;Bankname Auftragskonto;Buchungstag;Valutadatum;Name Zahlungsbeteiligter;IBAN Zahlungsbeteiligter;BIC (SWIFT-Code) Zahlungsbeteiligter;Buchungstext;Verwendungszweck;Betrag;Waehrung;Saldo nach Buchung;Bemerkung;Gekennzeichneter Umsatz;Glaeubiger ID;Mandatsreferenz"
    bal = 8412.37; rows = []
    for x in T:
        if x["pend"]: continue
        bal = round(bal + x["a"], 2); vz = x["text"] + (f" EREF: {x['mref']}-{x['d']:%y%m%d} MREF: {x['mref']} CRED: {x['cred']}" if x["cred"] else "")
        rows.append(";".join(["GiroKonto Online", "DE00600901000012345678", "GENODES1VBK", "Volksbank Konstanz eG", x["d"].strftime("%d.%m.%Y"), x["d"].strftime("%d.%m.%Y"), x["name"], x["iban"], "TESTDESSXXX" if x["iban"] else "", VRK[x["kind"]], vz.replace(";", ","), de_amt(x["a"]), "EUR", de_amt(bal), "", "", x["cred"], x["mref"]]))
    open(os.path.join(D, fn), "wb").write(("﻿" + H + "\r\n" + "\r\n".join(reversed(rows)) + "\r\n").encode("utf-8"))
# ================= Schweiz (CHF, TKB) =================
def ch_scenario(seed):
    R = random.Random(seed); T = []
    def t(d, a, kind, lines, coll=None): T.append(dict(d=d, a=round(a, 2), kind=kind, lines=lines, coll=coll))
    def addr(n, *rest): return [n] + list(rest)
    ref = [1009000000]
    def rnr(): ref[0] += R.randint(3000, 9000); return str(ref[0])
    for d in months(1):  # Sammelbelastung: Miete + Krankenkasse-Zusatz + Steuern-Rate
        items = [(1850.00, "Immo Seeblick AG", "Seestrasse 12", "8280 Kreuzlingen", "Mitteilung: Miete " + d.strftime("%m.%Y")),
                 (48.70, "Helsana Zusatzversicherungen AG", "Zürichstrasse 130", "8600 Dübendorf", "Referenz: 210000000003139471430009017")]
        if 3 <= d.month <= 12 and d.year == 2026 or (d.year == 2025 and d.month >= 4): items.append((760.00, "Politische Gemeinde Kreuzlingen", "Steuerverwaltung", "8280 Kreuzlingen", "Mitteilung: Steuern Rate " + d.strftime("%m.%Y")))
        t(d, -sum(i[0] for i in items), "Sammelauftrag", ["Sammelbelastung e-banking (Anzahl Zahlungen: %d / Ref.-Nr. %s)" % (len(items), rnr())], coll=items)
    for d in months(28): t(bday(d), -(389.60 if d < dt.date(2026, 1, 1) else 412.30), "LSV", ["Lastschrift / Ref.-Nr. " + rnr(), "CSS Kranken-Versicherung AG", "Tribschenstrasse 21", "6005 Luzern", "Schweiz", "Mitteilung: Prämie Grundversicherung Police 1234567"])
    for d in months(20): t(d, -(79.00 if d < dt.date(2026, 6, 1) else 89.00), "eBill", ["Belastung e-banking / Ref.-Nr. " + rnr(), "Swisscom (Schweiz) AG", "3050 Bern", "", "Schweiz", "Referenz: 21000000002026%02d000900123" % d.month])
    for d in months(12): t(d + dt.timedelta(days=2), -(18.90 if d < dt.date(2026, 4, 1) else 20.90), "Debitkarte", ["Warenbezug Debitkarte / Ref.-Nr. " + rnr(), "NETFLIX.COM Amsterdam", d.strftime("%d.%m.%Y") + " 03:14"])
    for d in months(7): t(d + dt.timedelta(days=1), -13.95, "Debitkarte", ["Warenbezug Debitkarte / Ref.-Nr. " + rnr(), "Spotify P2A3B4C5 Stockholm", d.strftime("%d.%m.%Y") + " 06:02"])
    for d in months(30, step=3, first=dt.date(2025, 6, 1)): t(d, -180.50, "eBill", ["Belastung e-banking / Ref.-Nr. " + rnr(), "Energie Kreuzlingen", "Hauptstrasse 62", "8280 Kreuzlingen", "Schweiz", "Referenz: Akonto Strom Q"])
    for d in months(10, step=12, first=dt.date(2025, 5, 1)): t(d, -335.00, "QR-Zahlung", ["Belastung e-banking / Ref.-Nr. " + rnr(), "Serafe AG", "Postfach", "8010 Zürich", "Schweiz", "Referenz: Haushaltabgabe Radio/TV " + str(d.year)])
    for d in months(15, step=12, first=dt.date(2025, 9, 1)): t(d, -289.20, "eBill", ["Belastung e-banking / Ref.-Nr. " + rnr(), "Die Mobiliar", "Bundesgasse 35", "3001 Bern", "Schweiz", "Referenz: Hausrat/Privathaftpflicht Police 4.471.993"])
    for d in months(3): t(bday(d), -79.00, "LSV", ["Lastschrift / Ref.-Nr. " + rnr(), "Genossenschaft Migros Ostschweiz", "Fitnesspark", "9200 Gossau", "Schweiz", "Mitteilung: Abo Fitnesspark " + d.strftime("%m.%Y")])
    t(dt.date(2026, 2, 3), -190.00, "Debitkarte", ["Warenbezug Debitkarte / Ref.-Nr. " + rnr(), "SBB CFF FFS Kreuzlingen", "03.02.2026 07:41"])
    for d in months(25):
        t(d, 6850.00, "Vergütung", ["Gutschrift / Ref.-Nr. " + rnr(), "Muster Pharma AG", "Industriestrasse 50", "8590 Romanshorn", "Schweiz", "Mitteilung: Lohn " + d.strftime("%m.%Y")])
    t(dt.date(2025, 11, 25), 6850.00, "Vergütung", ["Gutschrift / Ref.-Nr. " + rnr(), "Muster Pharma AG", "Industriestrasse 50", "8590 Romanshorn", "Schweiz", "Mitteilung: 13. Monatslohn 2025"])
    t(dt.date(2026, 3, 25), 4200.00, "Vergütung", ["Gutschrift / Ref.-Nr. " + rnr(), "Muster Pharma AG", "Industriestrasse 50", "8590 Romanshorn", "Schweiz", "Mitteilung: Bonus 2025"])
    t(dt.date(2026, 5, 12), 1240.35, "Vergütung", ["Gutschrift / Ref.-Nr. " + rnr(), "Kantonale Steuerverwaltung Thurgau", "Schlossmühlestrasse 9", "8510 Frauenfeld", "Schweiz", "Mitteilung: Rückerstattung Steuern 2024"])
    shops = [("Migros Kreuzlingen", 12, 140), ("Coop Kreuzlingen Bodensee", 9, 120), ("Denner Kreuzlingen", 6, 55), ("Lidl Konstanz EUR", 20, 90), ("Kaufland Konstanz EUR", 15, 110),
             ("Shell Kreuzlingen", 50, 95), ("Starbucks Konstanz EUR", 5, 14), ("Galaxus Zürich", 30, 450), ("Zalando Schweiz", 40, 160)]
    d = S
    while d <= E:
        for _ in range(R.randint(0, 3)):
            n, lo, hi = R.choice(shops); a = round(R.uniform(lo, hi), 2)
            if "EUR" in n:
                eur = round(a / 0.94, 2); t(d + dt.timedelta(days=2), -a, "Debitkarte", ["Warenbezug Debitkarte / Ref.-Nr. " + rnr(), n.replace(" EUR", ""), d.strftime("%d.%m.%Y") + " 15:2%d" % R.randint(0, 9), "Originalbetrag: EUR %.2f / Kurs: 0.94 / Bearbeitungsgebühr: CHF 1.50" % eur])
            else: t(d + dt.timedelta(days=R.randint(0, 2)), -a, "Debitkarte", ["Warenbezug Debitkarte / Ref.-Nr. " + rnr(), n, d.strftime("%d.%m.%Y") + " 1%d:%02d" % (R.randint(0, 9), R.randint(0, 59))])
        if R.random() < 0.05: t(d, -float(R.choice([100, 200, 300])), "Debitkarte", ["Bargeldbezug Debitkarte / Ref.-Nr. " + rnr(), R.choice(["Bancomat TKB Kreuzlingen", "Bancomat Konstanz Grenze"]), d.strftime("%d.%m.%Y") + " 11:05"])
        if R.random() < 0.05:
            a = float(R.choice([12, 20, 25, 30, 45, 60])); out = R.random() < 0.6
            t(d, -a if out else a, "TWINT", ["TWINT " + ("Geld senden" if out else "Geld empfangen") + " / Ref.-Nr. " + rnr(), R.choice(["Laura Beispiel", "Marco Test", "Nina Muster"]), "Mitteilung: " + R.choice(["Pizza", "Konzert", "Geschenk", "Taxi"])])
        if R.random() < 0.015: t(d, round(R.uniform(15, 120), 2), "Vergütung", ["Gutschrift / Ref.-Nr. " + rnr(), "Digitec Galaxus AG", "Pfingstweidstrasse 60b", "8005 Zürich", "Schweiz", "Mitteilung: Rückerstattung Retoure"])
        d += dt.timedelta(days=1)
    T.sort(key=lambda x: x["d"]); return T
def tkb(T, fn):
    H = "Buchungsdatum;Valutadatum;Auftragsart;Buchungstext;Betrag Einzelzahlung (CHF);Belastung (CHF);Gutschrift (CHF);Saldo in (CHF)"
    bal = 23418.60; rows = []
    for x in T:
        bal = round(bal + x["a"], 2); txt = '"' + "\r\n".join(x["lines"]) + '"'
        rows.append([";".join([x["d"].strftime("%d.%m.%Y"), x["d"].strftime("%d.%m.%Y"), x["kind"], txt, "", f"{-x['a']:.2f}" if x["a"] < 0 else "", f"{x['a']:.2f}" if x["a"] > 0 else "", f"{bal:.2f}"])] +
                    [";".join(["", "", "", '"' + "\r\n".join([i[1], i[2], i[3], "Schweiz", i[4]]) + '"', f"{i[0]:.2f}", "", "", ""]) for i in (x["coll"] or [])])
    out = [H]
    for r in reversed(rows): out += r
    open(os.path.join(D, fn), "wb").write("\r\n".join(out).encode("cp1252"))  # kein Zeilenende am Schluss (wie TKB)
sparkasse(de_scenario(7, "Max"), "de_sparkasse_stress.csv")
volksbank(de_scenario(11, "Lea"), "de_volksbank_stress.csv")
tkb(ch_scenario(5), "ch_tkb_stress.csv")
for f in sorted(os.listdir(D)):
    if f.endswith(".csv"): print(f, os.path.getsize(os.path.join(D, f)), "Bytes")
