"""Erzeugt fiktive Kontoauszüge im Format gängiger CH- und DE-Banken (nur Testdaten, keine echten Personen/Konten).
Aufruf:  python3 tests/bank/make_samples.py   → Dateien in tests/bank/samples/
Die Formate sind aus öffentlich dokumentierten Exporten nachgebaut; Spaltennamen und Eigenheiten
(Vorspann, getrennte Belastung/Gutschrift, Datums- und Zahlenformate, Kodierung) entsprechen den Vorbildern,
sind aber nicht gegen echte Dateien aller Banken geprüft."""
import os, random, datetime as dt
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "samples")
os.makedirs(D, exist_ok=True)
R = random.Random(42)
S, E = dt.date(2025, 10, 1), dt.date(2026, 9, 30)

def months(day, start=S, end=E, step=1):
    y, m = start.year, start.month
    while True:
        last = (dt.date(y + (m // 12), m % 12 + 1, 1) - dt.timedelta(days=1)).day
        d = dt.date(y, m, min(day, last))
        if d > end: break
        if d >= start: yield d
        m += step
        while m > 12: m -= 12; y += 1

# ---------- Buchungen Schweiz (CHF) ----------
CH = []
def ch(d, amt, name, text, kind, cred=""):
    CH.append(dict(d=d, a=amt, name=name, text=text, kind=kind, cred=cred))
for d in months(1):
    ch(d, -1850.00, "Immo Seeblick AG", "Miete Wohnung 3.OG Seestrasse 12", "Dauerauftrag")
    ch(d, -(389.60 if d < dt.date(2026, 1, 1) else 412.30), "CSS Kranken-Versicherung AG", "Prämie Grundversicherung Police 1234567", "Lastschrift")
for d in months(20):
    ch(d, -(82.35 if d.month == 2 else 79.00), "Swisscom (Schweiz) AG", "Rechnung Kundennummer 9876543", "eBill")
for d in months(12):
    ch(d, -18.90, "NETFLIX.COM", "NETFLIX.COM LOS GATOS", "Karte")
for d in months(5):
    ch(d, -13.95, "Spotify", "Spotify P2F4C8 Stockholm", "Karte")
for d in months(25, step=3):
    ch(d, -180.50, "Energie Kreuzlingen", "Akontorechnung Strom Messpunkt 4711", "eBill")
for d in months(28, start=dt.date(2026, 2, 1)):
    ch(d, -600.00, "Steuerverwaltung des Kantons Thurgau", "Staats- und Gemeindesteuern 2026 Rate", "Zahlung")
ch(dt.date(2026, 1, 31), -335.00, "SERAFE AG", "Radio- und TV-Abgabe 2026", "eBill")
ch(dt.date(2026, 3, 15), -486.70, "Die Mobiliar Versicherungsgesellschaft AG", "Hausrat und Privathaftpflicht Police 55-123", "eBill")
for d in months(3, end=dt.date(2026, 3, 31)):
    ch(d, -79.00, "Update Fitness AG", "Mitgliedschaft Monatsbeitrag", "Lastschrift")
for d in months(25):
    ch(d, 6850.00, "Muster Pharma AG", "Lohn", "Gutschrift")
d = S
while d <= E:
    ch(d, -round(R.uniform(38, 135), 2), "MIGROS KREUZLINGEN", "MIGROS KREUZLINGEN", "Karte")
    if R.random() < .5: ch(d + dt.timedelta(days=3), -round(R.uniform(12, 70), 2), "Coop-1234 Kreuzlingen", "Coop-1234 Kreuzlingen", "Karte")
    d += dt.timedelta(days=7)
for d in months(8):
    ch(d, -200.00, "BANCOMAT", "BARGELDBEZUG BANCOMAT KREUZLINGEN", "Bargeld")
for i, d in enumerate(months(16)):
    ch(d, -round(R.uniform(15, 60), 2), "TWINT an Lara", "TWINT AN +41790000000", "TWINT")
ch(dt.date(2026, 4, 9), -249.00, "Galaxus", "Digitec Galaxus AG Zürich", "Karte")
CH.sort(key=lambda x: x["d"])

# ---------- Buchungen Deutschland (EUR) ----------
DE = []
def de(d, amt, name, text, kind, cred="", mref=""):
    DE.append(dict(d=d, a=amt, name=name, text=text, kind=kind, cred=cred, mref=mref))
for d in months(1):
    de(d, -1180.00, "Wohnbau Konstanz GmbH", "Miete Wohnung Musterweg 5", "Dauerauftrag")
    de(d, -24.90, "McFit GmbH", "Mitgliedsbeitrag 123456", "Folgelastschrift", "DE43ZZZ00000441233", "MF-123456")
for d in months(3):
    de(d, -39.95, "Telekom Deutschland GmbH", "Festnetz Kundenkonto 1234567890 Rechnung", "Folgelastschrift", "DE93ZZZ00000078611", "TK-998877")
for d in months(15):
    de(d, -(95.00 if d < dt.date(2026, 3, 1) else 102.00), "Stadtwerke Konstanz GmbH", "Abschlag Strom Vertrag 300123", "Folgelastschrift", "DE52ZZZ00000123456", "SWK-300123")
for d in months(7):
    de(d, -13.99, "Netflix International B.V.", "Netflix Monatsabo", "Folgelastschrift", "NL05ZZZ000000000001", "NF-1")
for d in months(22):
    de(d, -(10.99 if d < dt.date(2026, 7, 1) else 11.99), "Spotify AB", "Spotify Premium", "Folgelastschrift", "SE12ZZZ0000000002", "SP-77")
for d in months(15, step=3):
    pass
for d in [dt.date(2025, 10, 15), dt.date(2026, 1, 15), dt.date(2026, 4, 15), dt.date(2026, 7, 15)]:
    de(d, -55.08, "Rundfunk ARD, ZDF, DRadio", "Rundfunkbeitrag Beitragsnummer 123 456 789", "Folgelastschrift", "DE13ZZZ00000006114", "RB-123456789")
for d in months(10):
    de(d, -(58.00 if d < dt.date(2026, 1, 1) else 63.00), "DB Vertrieb GmbH", "Deutschlandticket Abo", "Folgelastschrift", "DE14ZZZ00000077001", "DT-5551")
de(dt.date(2026, 2, 1), -89.40, "Allianz Versicherungs-AG", "Privathaftpflicht Vertrag AS-123456", "Folgelastschrift", "DE51ZZZ00000017444", "AS-123456")
for d in months(28):
    de(d, 3920.00, "Muster Pharma GmbH", "Gehalt", "Gutschrift")
d = S + dt.timedelta(days=1)
while d <= E:
    de(d, -round(R.uniform(25, 110), 2), "REWE Markt GmbH", "REWE SAGT DANKE 4711", "Kartenzahlung")
    if R.random() < .4: de(d + dt.timedelta(days=2), -round(R.uniform(8, 60), 2), "EDEKA Baur", "EDEKA BAUR KONSTANZ", "Kartenzahlung")
    if R.random() < .3: de(d + dt.timedelta(days=4), -round(R.uniform(9, 140), 2), "AMAZON PAYMENTS EUROPE S.C.A.", "Amazon .Mktp DE 303-1234567", "Folgelastschrift", "LU96ZZZ0000000000000000058", "AMZ-1")
    d += dt.timedelta(days=7)
for d in months(6):
    de(d, -150.00, "Sparkasse Bodensee", "GA 1234 Bargeldauszahlung", "Bargeldauszahlung")
DE.sort(key=lambda x: x["d"])

# ---------- Formatierung ----------
def ch_num(v, apos=False):
    s = f"{v:.2f}"
    if apos:
        neg = s.startswith("-"); s = s.lstrip("-"); i, f = s.split(".")
        i = "{:,}".format(int(i)).replace(",", "'"); s = ("-" if neg else "") + i + "." + f
    return s
def de_num(v, dots=True):
    neg = v < 0; s = f"{abs(v):,.2f}" if dots else f"{abs(v):.2f}"
    s = s.replace(",", "X").replace(".", ",").replace("X", ".")
    return ("-" if neg else "") + s
def q(x): return '"' + str(x).replace('"', '""') + '"'
def write(name, text, enc="utf-8"):
    with open(os.path.join(D, name), "w", encoding=enc, newline="") as f: f.write(text)
dmy = lambda d: d.strftime("%d.%m.%Y"); dmy2 = lambda d: d.strftime("%d.%m.%y"); ymd = lambda d: d.isoformat()

def pf_text(t):
    k = t["kind"]
    if k == "Karte": return f"KAUF/DIENSTLEISTUNG VOM {dmy(t['d'])} KARTEN NR. XXXX1234 {t['text']}"
    if k == "Lastschrift": return f"LASTSCHRIFT {t['name'].upper()} {t['text']}"
    if k == "eBill": return f"E-RECHNUNG {t['name']}, {t['text']}"
    if k == "Dauerauftrag": return f"DAUERAUFTRAG {t['name']} MITTEILUNGEN: {t['text']}"
    if k == "Zahlung": return f"GIRO POST {t['name']} MITTEILUNGEN: {t['text']}"
    if k == "Bargeld": return f"BARGELDBEZUG VOM {dmy(t['d'])} {t['text']}"
    if k == "TWINT": return f"{t['text']}"
    return f"GUTSCHRIFT VON {t['name']} {t['text']}"

# 1 PostFinance (E-Finance, Format 2024), neueste zuerst, UTF-8 mit BOM
rows = ["Datum von:;01.10.2025", "Datum bis:;30.09.2026", "Bewegungstyp:;Alle Buchungen", "Konto:;CH00 0000 0000 0000 0000 0", "Währung:;CHF", "",
        "Datum;Bewegungstyp;Avisierungstext;Gutschrift in CHF;Lastschrift in CHF;Label;Kategorie"]
for t in sorted(CH, key=lambda x: x["d"], reverse=True):
    rows.append(";".join([dmy(t["d"]), "Gutschrift" if t["a"] > 0 else "Lastschrift", q(pf_text(t)),
                          ch_num(t["a"]) if t["a"] > 0 else "", ch_num(t["a"]) if t["a"] < 0 else "", "", ""]))
rows += ["", "Disclaimer:", "Dies ist kein durch PostFinance AG erstelltes Dokument."]
write("ch_postfinance.csv", "﻿" + "\r\n".join(rows) + "\r\n")

# 2 UBS (E-Banking, Belastung/Gutschrift getrennt, Beschreibung1 mit Adresse in Anführungszeichen)
rows = ["Kontonummer:;0000 00000000.0", "IBAN:;CH00 0000 0000 0000 0000 0", "Von:;2025-10-01", "Bis:;2026-09-30", "Anfangssaldo:;12345.60",
        "Schlusssaldo:;14321.05", "Bewertet in:;CHF", f"Anzahl Transaktionen in diesem Zeitraum:;{len(CH)}", "",
        "Abschlussdatum;Abschlusszeit;Buchungsdatum;Valutadatum;Währung;Belastung;Gutschrift;Einzelbetrag;Saldo;Transaktions-Nr.;Beschreibung1;Beschreibung2;Beschreibung3;Fussnoten"]
UBS_K = {"Karte": "Debitkarte", "Lastschrift": "Lastschriftverfahren", "eBill": "e-Banking-Auftrag (eBill)", "Dauerauftrag": "Dauerauftrag",
         "Zahlung": "e-Banking-Auftrag", "Bargeld": "Bargeldbezug", "TWINT": "TWINT", "Gutschrift": "Zahlungseingang"}
for i, t in enumerate(sorted(CH, key=lambda x: x["d"], reverse=True)):
    nm = t["name"] if t["kind"] != "Karte" else f"{t['text']}"
    b1 = q(f"{nm};Musterstrasse 1;8000 Ort") if t["kind"] in ("eBill", "Lastschrift", "Dauerauftrag", "Zahlung", "Gutschrift") else q(nm)
    rows.append(";".join([ymd(t["d"]), "", ymd(t["d"]), ymd(t["d"]), "CHF", ch_num(t["a"]) if t["a"] < 0 else "", ch_num(t["a"]) if t["a"] > 0 else "", "", "",
                          f"98{i:010d}", b1, q(UBS_K[t["kind"]]), q(f"Zahlungsgrund: {t['text']}; Transaktions-Nr. 98{i:010d}"), ""]))
write("ch_ubs.csv", "\r\n".join(rows) + "\r\n")

# 3 ZKB (alle Felder in Anführungszeichen, Belastung positiv)
ZKB_K = {"Karte": "Einkauf ZKB Visa Debit Card Nr. xxxx 1234, ", "Lastschrift": "LSV: ", "eBill": "eBill: ", "Dauerauftrag": "Dauerauftrag: ",
         "Zahlung": "Zahlung: ", "Bargeld": "Bargeldbezug ", "TWINT": "", "Gutschrift": "Gutschrift: "}
rows = [";".join(map(q, ["Datum", "Buchungstext", "Whg", "Betrag Detail", "ZKB-Referenz", "Referenznummer", "Belastung CHF", "Gutschrift CHF", "Valuta", "Saldo CHF", "Zahlungszweck", "Details"]))]
for i, t in enumerate(CH):
    nm = t["text"] if t["kind"] in ("Karte", "TWINT", "Bargeld") else t["name"]
    rows.append(";".join(map(q, [dmy(t["d"]), ZKB_K[t["kind"]] + nm, "", "", f"Z{i:08d}", "", f"{-t['a']:.2f}" if t["a"] < 0 else "",
                                 f"{t['a']:.2f}" if t["a"] > 0 else "", dmy(t["d"]), "", t["text"] if t["kind"] not in ("Karte",) else "", ""])))
write("ch_zkb.csv", "\r\n".join(rows) + "\r\n", "windows-1252")

# 4 Raiffeisen (englische Spalten, ein Betrag mit Vorzeichen, Datum mit Uhrzeit)
rows = ["IBAN;Booked At;Text;Credit/Debit Amount;Balance;Valuta Date"]
for t in CH:
    rows.append(";".join(["CH0000000000000000000", t["d"].strftime("%Y-%m-%d 00:00:00.0"), pf_text(t).replace(";", ","), f"{t['a']:.2f}", "", t["d"].strftime("%Y-%m-%d 00:00:00.0")]))
write("ch_raiffeisen.csv", "\r\n".join(rows) + "\r\n")

# 5 neon (App-Bank)
rows = [";".join(map(q, ["Date", "Amount", "Original amount", "Original currency", "Exchange rate", "Description", "Subject", "Category", "Tags", "Wise", "Spaces"]))]
for t in sorted(CH, key=lambda x: x["d"], reverse=True):
    desc = t["name"].title() if t["kind"] == "Karte" else t["name"]
    rows.append(";".join(map(q, [ymd(t["d"]), f"{t['a']:.2f}", "", "", "", desc, t["text"] if t["kind"] != "Karte" else "", "", "", "no", "no"])))
write("ch_neon.csv", "\r\n".join(rows) + "\r\n")

# 6 Kantonalbank-Layout (Migros Bank, Valiant, TKB …): Vorspann, ein Betrag mit Apostroph-Tausendern
rows = ["Kontonummer:;CH00 0000 0000 0000 0000 0", "Bezeichnung:;Privatkonto", "Saldo:;CHF 14'321.05", "", "Datum;Buchungstext;Betrag;Valuta"]
for t in CH:
    rows.append(";".join([dmy(t["d"]), pf_text(t).replace(";", ","), ch_num(t["a"], apos=True), dmy(t["d"])]))
write("ch_kantonalbank.csv", "\r\n".join(rows) + "\r\n", "windows-1252")

# 7 camt.053.001.08 (alle CH-Banken), Sammelbuchung am Monatsersten (Miete + CSS)
def camt(entries, cur, ver, pty):
    out = [f'<?xml version="1.0" encoding="UTF-8"?>', f'<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.{ver}">',
           "<BkToCstmrStmt><GrpHdr><MsgId>M1</MsgId><CreDtTm>2026-10-01T06:00:00</CreDtTm></GrpHdr><Stmt><Id>S1</Id>",
           f"<Acct><Id><IBAN>{'CH' if cur=='CHF' else 'DE'}00000000000000000000</IBAN></Id><Ccy>{cur}</Ccy></Acct>"]
    for e in entries:
        tot = sum(abs(x["a"]) for x in e); ind = "DBIT" if e[0]["a"] < 0 else "CRDT"
        sts = "<Sts><Cd>BOOK</Cd></Sts>" if ver == "08" else "<Sts>BOOK</Sts>"
        out.append(f'<Ntry><Amt Ccy="{cur}">{tot:.2f}</Amt><CdtDbtInd>{ind}</CdtDbtInd>{sts}<BookgDt><Dt>{ymd(e[0]["d"])}</Dt></BookgDt><ValDt><Dt>{ymd(e[0]["d"])}</Dt></ValDt>')
        out.append(f"<AddtlNtryInf>{'Sammelauftrag' if len(e) > 1 else e[0]['kind']}</AddtlNtryInf><NtryDtls>")
        for x in e:
            role = "Cdtr" if x["a"] < 0 else "Dbtr"
            nm = x["name"].replace("&", "&amp;")
            party = f"<{role}><Pty><Nm>{nm}</Nm></Pty></{role}>" if pty else f"<{role}><Nm>{nm}</Nm></{role}>"
            cred = f"<CdtrSchmeId><Id><PrvtId><Othr><Id>{x['cred']}</Id></Othr></PrvtId></Id></CdtrSchmeId>" if x.get("cred") else ""
            amt = f'<Amt Ccy="{cur}">{abs(x["a"]):.2f}</Amt>' if len(e) > 1 else ""
            out.append(f"<TxDtls>{amt}<RltdPties>{party}{cred}</RltdPties><RmtInf><Ustrd>{x['text']}</Ustrd></RmtInf></TxDtls>")
        out.append("</NtryDtls></Ntry>")
    out.append("</Stmt></BkToCstmrStmt></Document>")
    return "\n".join(out)
ent = []; grp = {}
for t in CH:
    if t["d"].day == 1 and t["kind"] in ("Dauerauftrag", "Lastschrift") and t["name"] != "Update Fitness AG":
        grp.setdefault(t["d"], []).append(t)
    else: ent.append([t])
ent += list(grp.values()); ent.sort(key=lambda e: e[0]["d"])
write("ch_camt053.xml", camt(ent, "CHF", "08", True))

# ---------- Deutschland ----------
# 8 Sparkasse CSV-CAMT V2 (Windows-1252, alle Felder in Anführungszeichen, Datum TT.MM.JJ)
SPK_K = {"Dauerauftrag": "DAUERAUFTRAG", "Folgelastschrift": "FOLGELASTSCHRIFT", "Kartenzahlung": "KARTENZAHLUNG", "Gutschrift": "GUTSCHR. UEBERWEISUNG", "Bargeldauszahlung": "BARGELDAUSZAHLUNG"}
rows = [";".join(map(q, ["Auftragskonto", "Buchungstag", "Valutadatum", "Buchungstext", "Verwendungszweck", "Glaeubiger ID", "Mandatsreferenz", "Kundenreferenz (End-to-End)",
                         "Sammlerreferenz", "Lastschrift Ursprungsbetrag", "Auslagenersatz Ruecklastschrift", "Beguenstigter/Zahlungspflichtiger", "Kontonummer/IBAN", "BIC (SWIFT-Code)", "Betrag", "Waehrung", "Info"]))]
for t in sorted(DE, key=lambda x: x["d"], reverse=True):
    rows.append(";".join(map(q, ["DE00000000000000000000", dmy2(t["d"]), dmy2(t["d"]), SPK_K[t["kind"]], t["text"], t["cred"], t["mref"], "", "", "", "",
                                 t["name"], "DE00000000000000000000", "XXXXDEXX", de_num(t["a"], dots=False), "EUR", "Umsatz gebucht"])))
write("de_sparkasse.csv", "\r\n".join(rows) + "\r\n", "windows-1252")

# 9 ING (Vorspann, doppelte Spalte «Währung», Tausenderpunkte)
rows = ["Umsatzanzeige;Datei erstellt am: 01.10.2026 08:00", "", "IBAN;DE00 0000 0000 0000 0000 00", "Kontoname;Girokonto", "Bank;ING", "Kunde;Max Muster",
        "Zeitraum;01.10.2025 - 30.09.2026", "Saldo;2.345,67;EUR", "", "Sortierung;Datum absteigend", "",
        "In der CSV-Datei finden Sie alle bereits gebuchten Umsätze. Die vorgemerkten Umsätze werden nicht aufgenommen, auch wenn sie in Ihrem Internetbanking angezeigt werden.", "",
        "Buchung;Wertstellungsdatum;Auftraggeber/Empfänger;Buchungstext;Verwendungszweck;Saldo;Währung;Betrag;Währung"]
ING_K = {"Dauerauftrag": "Dauerauftrag / Terminueberweisung", "Folgelastschrift": "Lastschrift", "Kartenzahlung": "Lastschrift", "Gutschrift": "Gehalt/Rente", "Bargeldauszahlung": "Abschluss"}
for t in sorted(DE, key=lambda x: x["d"], reverse=True):
    rows.append(";".join([dmy(t["d"]), dmy(t["d"]), t["name"], ING_K[t["kind"]], t["text"], "2.345,67", "EUR", de_num(t["a"]), "EUR"]))
write("de_ing.csv", "\r\n".join(rows) + "\r\n", "windows-1252")

# 10 DKB (Format 2023: Zahlungspflichtige*r und Zahlungsempfänger*in getrennt)
rows = [";".join(map(q, ["Girokonto", "DE00 0000 0000 0000 0000 00"])), q(""), ";".join(map(q, ["Kontostand vom 30.09.2026:", "2.345,67 €"])), q(""),
        ";".join(map(q, ["Buchungsdatum", "Wertstellung", "Status", "Zahlungspflichtige*r", "Zahlungsempfänger*in", "Verwendungszweck", "Umsatztyp", "IBAN", "Betrag (€)", "Gläubiger-ID", "Mandatsreferenz", "Kundenreferenz"]))]
for t in sorted(DE, key=lambda x: x["d"], reverse=True):
    payer, payee = ("Max Muster", t["name"]) if t["a"] < 0 else (t["name"], "Max Muster")
    rows.append(";".join(map(q, [dmy2(t["d"]), dmy2(t["d"]), "Gebucht", payer, payee, t["text"], "Ausgang" if t["a"] < 0 else "Eingang",
                                 "DE00000000000000000000", de_num(t["a"]), t["cred"], t["mref"], ""])))
write("de_dkb.csv", "﻿" + "\n".join(rows) + "\n")

# 11 comdirect (nur 90 Tage, Name nur im Buchungstext, Semikolon am Zeilenende)
rows = [";", q("Umsätze Girokonto") + ";" + q("Zeitraum: 90 Tage") + ";", q("Neuer Kontostand") + ";" + q("2.345,67 EUR") + ";", "",
        ";".join(map(q, ["Buchungstag", "Wertstellung (Valuta)", "Vorgang", "Buchungstext", "Umsatz in EUR"])) + ";"]
for t in sorted([x for x in DE if x["d"] >= dt.date(2026, 7, 2)], key=lambda x: x["d"], reverse=True):
    who = "Empfänger" if t["a"] < 0 else "Auftraggeber"
    bt = f"{who}: {t['name']} Kto/IBAN: DE00000000000000000000 BLZ/BIC: XXXXDEXX Buchungstext: {t['text']}"
    if t["kind"] == "Kartenzahlung": bt = f"{t['text']} Buchungstext: {t['name']} Karte Nr. 4871 78XX XXXX 1234"
    rows.append(";".join(map(q, [dmy(t["d"]), dmy(t["d"]), {"Kartenzahlung": "Visa-Umsatz"}.get(t["kind"], "Lastschrift / Belastung" if t["a"] < 0 else "Übertrag / Überweisung"), bt, de_num(t["a"])])) + ";")
rows += ["", q("Alter Kontostand") + ";" + q("1.234,56 EUR") + ";"]
write("de_comdirect.csv", "\r\n".join(rows) + "\r\n", "windows-1252")

# 12 N26 (Komma, englische Spalten)
rows = ['"Booking Date","Value Date","Partner Name","Partner Iban","Type","Payment Reference","Account Name","Amount (EUR)","Original Amount","Original Currency","Exchange Rate"']
for t in DE:
    rows.append(",".join(map(q, [ymd(t["d"]), ymd(t["d"]), t["name"], "DE00000000000000000000", "Debit Transfer" if t["a"] < 0 else "Credit Transfer", t["text"], "Hauptkonto", f"{t['a']:.2f}", "", "", ""])))
write("de_n26.csv", "\n".join(rows) + "\n")

# 13 Deutsche Bank (Soll/Haben getrennt, Fusszeile «Kontostand»)
rows = ["Umsätze Girokonto;Zeitraum: 01.10.2025 - 30.09.2026;", "Letzter Kontostand;;;;2.345,67;EUR", "Vorgemerkte und noch nicht gebuchte Umsätze sind nicht Bestandteil dieser Übersicht.",
        "Buchungstag;Wert;Umsatzart;Begünstigter / Auftraggeber;Verwendungszweck;IBAN;BIC;Kundenreferenz;Mandatsreferenz ;Gläubiger ID;Fremde Gebühren;Betrag;Abweichender Empfänger;Anzahl der Aufträge;Anzahl der Schecks;Soll;Haben;Währung"]
for t in sorted(DE, key=lambda x: x["d"], reverse=True):
    rows.append(";".join([dmy(t["d"]), dmy(t["d"]), "SEPA-Lastschrift" if t["a"] < 0 else "SEPA-Gutschrift", t["name"], t["text"], "DE00000000000000000000", "XXXXDEXX",
                          "", t["mref"], t["cred"], "", "", "", "", "", de_num(t["a"]) if t["a"] < 0 else "", de_num(t["a"]) if t["a"] > 0 else "", "EUR"]))
rows.append("Kontostand;30.09.2026;;;2.345,67;EUR")
write("de_deutschebank.csv", "\r\n".join(rows) + "\r\n", "windows-1252")

# 14 Volksbank / Raiffeisenbank (VR-NetWorld)
rows = ["Bezeichnung Auftragskonto;IBAN Auftragskonto;BIC Auftragskonto;Bankname Auftragskonto;Buchungstag;Valutadatum;Name Zahlungsbeteiligter;IBAN Zahlungsbeteiligter;BIC (SWIFT-Code) Zahlungsbeteiligter;Buchungstext;Verwendungszweck;Betrag;Waehrung;Saldo nach Buchung;Bemerkung;Kategorie;Steuerrelevant;Glaeubiger ID;Mandatsreferenz"]
for t in sorted(DE, key=lambda x: x["d"], reverse=True):
    rows.append(";".join(["Girokonto", "DE00000000000000000000", "GENODE61XXX", "Volksbank eG", dmy(t["d"]), dmy(t["d"]), t["name"], "DE00000000000000000000", "XXXXDEXX",
                          t["kind"], t["text"], de_num(t["a"], dots=False), "EUR", "", "", "Sonstiges", "", t["cred"], t["mref"]]))
write("de_volksbank.csv", "\r\n".join(rows) + "\r\n", "windows-1252")

# 15 MT940 (Commerzbank u.a.)
out = [":20:STARTUMS", ":25:00000000/0000000000", ":28C:00001/001", ":60F:C250930EUR1234,56"]
for t in DE:
    sign = "D" if t["a"] < 0 else "C"; amt = f"{abs(t['a']):.2f}".replace(".", ",")
    out.append(f":61:{t['d'].strftime('%y%m%d%m%d')}{sign}{amt}NDDTNONREF")
    p = [f"?20EREF+NOTPROVIDED", f"?21MREF+{t['mref']}" if t["mref"] else "?21", f"?22CRED+{t['cred']}" if t["cred"] else "?22", f"?23SVWZ+{t['text'][:27]}", f"?24{t['text'][27:54]}"]
    nm = t["name"]; n1, n2 = nm[:27], nm[27:54]
    out.append(":86:105?00" + {"Folgelastschrift": "FOLGELASTSCHRIFT", "Dauerauftrag": "DAUERAUFTRAG"}.get(t["kind"], "SEPA") + "".join(p[:2]))
    out.append("".join(p[2:]) + f"?30XXXXDEXX?31DE00000000000000000000?32{n1}" + (f"?33{n2}" if n2 else ""))
out += [":62F:C260930EUR2345,67", "-"]
write("de_commerzbank.sta", "\r\n".join(out) + "\r\n", "windows-1252")

# 16 camt.053.001.02 (DE, Name direkt unter Cdtr)
write("de_camt053.xml", camt([[t] for t in DE], "EUR", "02", False))
print("Musterdateien:", len(os.listdir(D)), "→", D)
