import os, sys, datetime as dt
from decimal import Decimal as D
sys.path.insert(0, os.path.dirname(__file__))
from scenario import *

OUT = "/root/kontivo/tests/bank/real/ch"
os.makedirs(OUT, exist_ok=True)

def write(name, lines, enc="utf-8", bom=False, eol="\n", final_eol=True):
    text = eol.join(lines) + (eol if final_eol else "")
    data = text.encode(enc)
    if bom:
        data = b"\xef\xbb\xbf" + data
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(data)

def d_dmy(d): return d.strftime("%d.%m.%Y")
def d_dmy2(d): return d.strftime("%d.%m.%y")
def d_iso(d): return d.strftime("%Y-%m-%d")
def q(s): return '"' + s.replace('"', '""') + '"'

TX = build()
TXB = with_balance(TX)
TXB_NB = with_balance(build(with_batch=False))   # neobanks: no collective orders
CARD = card_txs()
CLOSING = TXB[-1][1]

def eod_flags(rows):
    """True for the last booking of each booking day (chronological order)."""
    flags = []
    for i, (t, b) in enumerate(rows):
        flags.append(i == len(rows) - 1 or rows[i + 1][0].book != t.book)
    return flags

def short(t):
    return party(t)[0]

# ---------------------------------------------------------------- PostFinance
def pf_text(t):
    n, addr, iban = party(t)
    if t.kind == "card":
        if t.party == "NETFLIX.COM":
            return "KAUF/ONLINE-SHOPPING VOM %s KARTEN NR. XXXX1234 NETFLIX.COM AMSTERDAM NIEDERLANDE" % d_dmy(t.date)
        return "KAUF/DIENSTLEISTUNG VOM %s KARTEN NR. XXXX1234 %s KREUZLINGEN SCHWEIZ" % (d_dmy(t.date), t.party.upper())
    if t.kind == "atm":
        return "BARGELDBEZUG VOM %s KARTEN NR. XXXX1234 POSTOMAT %s" % (d_dmy(t.date), t.city.upper())
    if t.kind == "standing":
        return "LASTSCHRIFT DAUERAUFTRAG: %s %s MITTEILUNGEN: %s" % (n.upper(), addr.upper().replace(",", ""), t.msg.upper())
    if t.kind == "lsv":
        return "LASTSCHRIFT %s %s" % (n.upper(), t.msg.upper())
    if t.kind in ("ebill", "ebill_qr"):
        return "ZAHLUNG EBILL BEGÜNSTIGTER: %s %s REFERENZEN: %s" % (n.upper(), addr.upper().replace(",", ""), qrr_fmt(t.ref))
    if t.kind == "batch":
        return "SAMMELAUFTRAG E-FINANCE 2 ZAHLUNGEN"
    if t.kind == "salary":
        return "GUTSCHRIFT AUFTRAGGEBER: %s %s MITTEILUNGEN: %s" % (n.upper(), addr.upper().replace(",", ""), t.msg.upper())
    if t.kind == "twint":
        return "TWINT GELD SENDEN VOM %s AN %s %s MITTEILUNGEN: %s" % (d_dmy(t.date), n.upper(), "+417900000XX", t.msg.upper())
    return t.kind

def pf_cat(t):
    return {"card": "Einkaufen // Supermärkte", "atm": "Bargeld // Bargeldbezug", "standing": "Wohnen // Miete und Hypothek",
            "lsv": "Finanzen // Versicherungen", "ebill": "Wohnen // Kommunikation", "ebill_qr": "Wohnen // Nebenkosten",
            "batch": "Sonstige Ausgaben", "salary": "Einnahmen // Lohn", "twint": "Sonstige Ausgaben"}[t.kind] if not (t.kind == "card" and t.party == "NETFLIX.COM") else "Freizeit // Unterhaltung"

def pf_efinance():
    L = ['Datum von:;="01.10.2025"', 'Datum bis:;="30.09.2026"', 'Kategorie:;="Alle"',
         'Konto:;="%s"' % OWN_IBAN.replace(" ", ""), 'Währung:;="CHF"', "",
         "Datum;Bewegungstyp;Avisierungstext;Gutschrift in CHF;Lastschrift in CHF;Label;Kategorie", ""]
    for t, b in reversed(TXB):
        cr = fmt(t.amount, strip=True) if t.amount > 0 else ""
        db = fmt(t.amount, strip=True) if t.amount < 0 else ""
        L.append(";".join([d_dmy(t.book), "Buchung", q(pf_text(t)), cr, db, "", pf_cat(t)]))
    L += ["", "Disclaimer:", "Der Dokumentinhalt wurde durch Filtereinstellungen der Kund:innen generiert. PostFinance ist für den Inhalt und die Vollständigkeit nicht verantwortlich."]
    write("ch_postfinance.csv", L, bom=True)

def pf_efinance_saldo():
    L = ['Datum von:;="01.10.2025"', 'Datum bis:;="30.09.2026"', 'Kategorie:;="Alle"',
         'Konto:;="%s"' % OWN_IBAN.replace(" ", ""), 'Währung:;="CHF"', "",
         "Datum;Avisierungstext;Gutschrift in CHF;Lastschrift in CHF;Label;Kategorie;Valuta;Saldo in CHF", ""]
    fl = eod_flags(TXB)
    for (t, b), last in reversed(list(zip(TXB, fl))):
        cr = fmt(t.amount, strip=True) if t.amount > 0 else ""
        db = fmt(t.amount, strip=True) if t.amount < 0 else ""
        L.append(";".join([d_dmy(t.book), q(pf_text(t)), cr, db, "", pf_cat(t), d_dmy(t.date), fmt(b, strip=True) if last else ""]))
    L += ["", "Disclaimer:", "Der Dokumentinhalt wurde durch Filtereinstellungen der Kund:innen generiert. PostFinance ist für den Inhalt und die Vollständigkeit nicht verantwortlich."]
    write("ch_postfinance_saldo.csv", L, bom=True)

def pf_legacy():
    pad = ";;;;"
    L = ["Datum von:;01.10.25" + pad, "Datum bis:;30.09.26" + pad, "Buchungsart:;Alle Buchungen" + pad,
         "Konto:;%s" % OWN_IBAN.replace(" ", "") + pad, "Währung:;CHF" + pad, "Buchungsdetails:;Ja" + pad,
         "Buchungsdatum;Avisierungstext;Gutschrift;Lastschrift;Valuta;Saldo"]
    fl = eod_flags(TXB)
    for (t, b), last in reversed(list(zip(TXB, fl))):
        cr = fmt(t.amount, strip=True) if t.amount > 0 else ""
        db = fmt(t.amount, strip=True) if t.amount < 0 else ""
        L.append(";".join([d_dmy2(t.book), pf_text(t), cr, db, d_dmy2(t.date), fmt(b) if last else ""]))
    L += [";;;;;", "Disclaimer:;;;;;", "Dies ist kein durch PostFinance AG erstelltes Dokument. PostFinance AG ist nicht verantwortlich für den Inhalt.;;;;;"]
    write("ch_postfinance_legacy.csv", L, enc="cp1252")

def card_periods():
    """Billing periods 28th..27th, label like PostFinance ('dd.mm.yyyy − dd.mm.yyyy', U+2212)."""
    def per(d):
        if d.day >= 28:
            s = dt.date(d.year, d.month, 28)
        else:
            pm = dt.date(d.year - (d.month == 1), (d.month - 2) % 12 + 1, 28)
            s = pm
        e_m = dt.date(s.year + (s.month == 12), s.month % 12 + 1, 27)
        return s, e_m
    return per

def pf_visa():
    per = card_periods()
    L = ["Kartenkonto:;0000 0000 0000 0000;;;;", "Karte:;XXXX XXXX XXXX 4321 PostFinance Visa Classic Card;;;;",
         "Karteninhaber:;MAX MUSTER;;;;", 'Bewegungsart:;"=""Alle""";;;;', "",
         "Rechnungsperiode;Buchungsdatum;Einkaufsdatum;Buchungsdetails;Gutschrift in CHF;Lastschrift in CHF"]
    for t in reversed(CARD):
        s, e = per(t.book)
        label = "Aktuelle Rechnungsperiode" if e >= dt.date(2026, 9, 27) and t.book >= dt.date(2026, 9, 28) else "%s − %s" % (d_dmy(s), d_dmy(e))
        if t.kind == "cardpay":
            det, cr, db = "IHRE ZAHLUNG - BESTEN DANK", fmt(t.amount, strip=True), ""
        else:
            det = "NETFLIX.COM Amsterdam NLD" if t.party == "NETFLIX.COM" else t.party
            cr, db = "", fmt(t.amount, strip=True)
        L.append(";".join([label, d_dmy(t.book), d_dmy(t.date), det, cr, db]))
    L += ["Disclaimer:;;;;;", "Der Dokumentinhalt wurde durch Filtereinstellungen der Kund:innen generiert. PostFinance ist für den Inhalt und die Vollständigkeit nicht verantwortlich.;;;;;"]
    write("ch_postfinance_visa.csv", L, bom=True, final_eol=False)

# ---------------------------------------------------------------- UBS
def ubs_desc(t, txid):
    """Beschreibung1/2/3 like the UBS e-banking export since 11.2022."""
    n, addr, iban = party(t)
    if t.kind == "card":
        if t.party == "NETFLIX.COM":
            return "NETFLIX.COM,Amsterdam", "12345678-0 07/27, Zahlung Debitkarte", "Transaktions-Nr. %s" % txid
        return "%s,8280 Kreuzlingen" % t.party, "12345678-0 07/27, Zahlung Debitkarte", "Transaktions-Nr. %s" % txid
    if t.kind == "atm":
        return "Bancomat %s" % t.city, "12345678-0 07/27, Bezug Bancomat", "Transaktions-Nr. %s" % txid
    if t.kind == "standing":
        return "%s,%s" % (n, addr), "Dauerauftrag", "Mitteilungen: %s, Konto-Nr. IBAN: %s, Kosten: Dauerauftrag CHF Inland, Transaktions-Nr. %s" % (t.msg, iban, txid)
    if t.kind == "lsv":
        return "%s,%s" % (n, addr), "Lastschrift", "Mitteilungen: %s, Transaktions-Nr. %s" % (t.msg, txid)
    if t.kind in ("ebill", "ebill_qr"):
        return "%s,%s" % (n, addr), "e-banking-Vergütungsauftrag", "Referenz-Nr. QRR: %s, Konto-Nr. IBAN: %s, Kosten: E-Banking CHF Inland, Transaktions-Nr. %s" % (qrr_fmt(t.ref), iban, txid)
    if t.kind == "batch":
        return "e-banking-Sammelauftrag", "2 Zahlungen", "Transaktions-Nr. %s" % txid
    if t.kind == "salary":
        return "%s,%s" % (n, addr), "Gutschrift", "Mitteilungen: %s, Konto-Nr. IBAN: %s, Transaktions-Nr. %s" % (t.msg, iban, txid)
    if t.kind == "twint":
        return "TWINT %s" % n, "Geld senden TWINT", "Mitteilungen: %s, Transaktions-Nr. %s" % (t.msg, txid)

def ubs_txid(t):
    return ("99%s%sBN%07d" % (t.book.strftime("%y"), t.book.strftime("%j"), int(t.id))) if t.kind in ("card", "atm", "twint") else ("%s%sTO%07d" % (t.book.strftime("%y"), t.book.strftime("%j"), int(t.id)))

def ubs_new():
    L = ["Kontonummer:;0230 00123456.40;", "IBAN:;CH00 0023 0230 1234 5640 X;", "Von:;2025-10-01;", "Bis:;2026-09-30;",
         "Anfangssaldo:;%s;" % fmt(OPENING), "Schlusssaldo:;%s;" % fmt(CLOSING), "Bewertet in:;CHF;",
         "Anzahl Transaktionen in diesem Zeitraum:;%d;" % len(TXB), "",
         "Abschlussdatum;Abschlusszeit;Buchungsdatum;Valutadatum;Währung;Belastung;Gutschrift;Einzelbetrag;Saldo;Transaktions-Nr.;Beschreibung1;Beschreibung2;Beschreibung3;Fussnoten;"]
    pending_cut = dt.date(2026, 9, 26)
    for t, b in reversed(TXB):
        txid = ubs_txid(t)
        d1, d2, d3 = ubs_desc(t, txid)
        time = t.time if t.kind in ("card", "atm", "twint") else ""
        book = d_iso(t.book)
        if t.kind in ("card", "twint") and t.date >= pending_cut:
            book = ""            # not yet booked: UBS leaves Buchungsdatum empty
        deb = fmt(t.amount) if t.amount < 0 else ""
        cre = fmt(t.amount) if t.amount > 0 else ""
        L.append(";".join([d_iso(t.date), time, book, d_iso(t.date), "CHF", deb, cre, "", fmt(b), txid, q(d1), q(d2), q(d3), ""]) + ";")
        for s in t.subs:
            n, addr, iban = party(s)
            L.append(";".join(["", "", "", "", "CHF", "", "", fmt(-s.amount), "", txid, q("%s,%s" % (n, addr)), "",
                               q("Referenz-Nr. QRR: %s, Konto-Nr. IBAN: %s" % (qrr_fmt(s.ref), iban)), ""]) + ";")
    write("ch_ubs.csv", L, bom=True, final_eol=False)

def ubs_signed():
    """Short-lived UBS layout (09.2022): one signed amount + direction word."""
    L = ["Kontonummer:;0230 00123456.40;", "IBAN:;CH00 0023 0230 1234 5640 X;", "Von:;2025-10-01;", "Bis:;2026-09-30;",
         "Anfangssaldo:;%s;" % fmt(OPENING), "Schlusssaldo:;%s;" % fmt(CLOSING), "Bewertet in:;CHF;",
         "Anzahl Transaktionen in diesem Zeitraum:;%d;" % len(TXB), "",
         "Abschlussdatum;Abschlusszeit;Buchungsdatum;Valutadatum;Währung;Transaktionsbetrag;Belastung/Gutschrift;Saldo;Transaktions-Nr.;Beschreibung1;Beschreibung2;Beschreibung3;Fussnoten;"]
    for t, b in reversed(TXB):
        txid = ubs_txid(t)
        d1, d2, d3 = ubs_desc(t, txid)
        time = t.time if t.kind in ("card", "atm", "twint") else ""
        L.append(";".join([d_iso(t.date), time, d_iso(t.book), d_iso(t.book), "CHF", fmt(t.amount),
                           "Belastung" if t.amount < 0 else "Gutschrift", fmt(b), txid, q(d1), q(d2), q(d3), ""]) + ";")
    write("ch_ubs_signed.csv", L, final_eol=False)

def ubs_legacy():
    """Pre-2022 UBS e-banking export (21 cols, positive Belastung, apostrophes, footer with balances)."""
    hdr = "Bewertungsdatum;Bankbeziehung;Portfolio;Produkt;IBAN;Whrg.;Datum von;Datum bis;Beschreibung;Abschluss;Buchungsdatum;Valuta;Beschreibung 1;Beschreibung 2;Beschreibung 3;Transaktions-Nr.;Devisenkurs zum Originalbetrag in Abrechnungswährung;Einzelbetrag;Belastung;Gutschrift;Saldo"
    L = [hdr]
    fixed = ["03.10.2026", "0230 00123456", "", "0230 00123456.40", "CH00 0023 0230 1234 5640 X", "CHF", "01.10.2025", "30.09.2026", "UBS Privatkonto"]
    fl = eod_flags(TXB)
    tot_d = tot_c = D(0)
    for (t, b), last in reversed(list(zip(TXB, fl))):
        txid = ubs_txid(t)
        n, addr, iban = party(t)
        if t.kind == "card":
            d1, d2, d3 = "Zahlung Debitkarte", "%s %s" % (t.party.upper(), t.city.upper() if t.city else ""), "Karten-Nr. 12345678-0, %s %s" % (d_dmy(t.date), t.time[:5])
        elif t.kind == "atm":
            d1, d2, d3 = "Bezug Bancomat", "BANCOMAT %s" % t.city.upper(), "Karten-Nr. 12345678-0, %s %s" % (d_dmy(t.date), t.time[:5])
        elif t.kind == "salary":
            d1, d2, d3 = "Gutschrift", "%s, %s" % (n.upper(), addr.upper()), t.msg.upper()
        elif t.kind == "batch":
            d1, d2, d3 = "e-banking-Sammelauftrag", "", ""
        elif t.kind == "twint":
            d1, d2, d3 = "TWINT Geld senden", n.upper(), t.msg
        else:
            d1 = {"standing": "Dauerauftrag", "lsv": "LSV Belastung", "ebill": "e-banking-Vergütungsauftrag", "ebill_qr": "e-banking-Vergütungsauftrag"}[t.kind]
            d2 = "%s, %s" % (n.upper(), addr.upper())
            d3 = ("REFERENZ-NR. %s" % qrr_fmt(t.ref)) if t.ref else t.msg.upper()
        deb = fmt(-t.amount, thousands="'") if t.amount < 0 else ""
        cre = fmt(t.amount, thousands="'") if t.amount > 0 else ""
        tot_d += -t.amount if t.amount < 0 else 0
        tot_c += t.amount if t.amount > 0 else 0
        L.append(";".join(fixed + [d_dmy(t.date), d_dmy(t.book), d_dmy(t.book), d1, d2, d3, txid, "", "", deb, cre, fmt(b, thousands="'") if last else ""]))
        for s in t.subs:
            sn, saddr, siban = party(s)
            L.append(";".join(fixed + [d_dmy(t.date), d_dmy(t.book), d_dmy(t.book), "e-banking-Vergütungsauftrag", "%s, %s" % (sn.upper(), saddr.upper()),
                                       "REFERENZ-NR. %s" % qrr_fmt(s.ref), txid, "", fmt(s.amount, thousands=""), "", "", ""]))
    L += [";" * 20, "Schlusssaldo;Anfangssaldo" + ";" * 19, "%s;%s" % (fmt(CLOSING, 9), fmt(OPENING, 9)) + ";" * 19]
    write("ch_ubs_legacy.csv", L, enc="latin-1")

def ubs_cc():
    L = ["sep=;", "Kontonummer;Kartennummer;Konto-/Karteninhaber;Einkaufsdatum;Buchungstext;Branche;Betrag;Originalwährung;Kurs;Währung;Belastung;Gutschrift;Buchung",
         "0000 1234 5678;;MUSTER MAX;30.09.2025;Saldovortrag;;;;;CHF;;0.00;"]
    for t in reversed(CARD):
        pend = t.date >= dt.date(2026, 9, 26) and t.kind != "cardpay"
        if t.kind == "cardpay":
            L.append(";".join(["0000 1234 5678", "", "MUSTER MAX", d_dmy(t.date), "Ihre Zahlung - Besten Dank", "", "", "", "", "CHF", "", fmt(t.amount), d_dmy(t.book)]))
            continue
        if t.party == "NETFLIX.COM":
            txt, br = "NETFLIX.COM              Amsterdam    NLD", "Video-/Streamingdienste"
        else:
            txt, br = "%-25s%-13sCHE" % (t.party.upper()[:24], "KREUZLINGEN"), "Lebensmittelgeschäfte"
        amt = fmt(-t.amount)
        L.append(";".join(["0000 1234 5678", "XXXX XXXX XXXX 9876", "MUSTER MAX", d_dmy(t.date), txt, br, amt, "CHF", "",
                           "" if pend else "CHF", "" if pend else amt, "", "" if pend else d_dmy(t.book)]))
    L.append("")
    write("ch_ubs_creditcard.csv", L, enc="cp1252", eol="\r\n")

# ---------------------------------------------------------------- Credit Suisse (legacy, now UBS)
def cs():
    L = ["Erstellt am 01.10.2026 07:12:44 CEST", "Buchungen suchen",
         'Konto,"Privatkonto,CH00 0483 5012 3456 7100 0,Muster Max, Kreuzlingen"', "Saldo,%s CHF" % fmt(CLOSING, thousands="'"),
         "Buchungen", "Buchungsdatum,Text,Belastung,Gutschrift,Valutadatum,Saldo,Valutasaldo,Buchungszeitpunkt"]
    fl = eod_flags(TXB)
    td = tc = D(0)
    for (t, b), last in reversed(list(zip(TXB, fl))):
        n, addr, iban = party(t)
        if t.kind == "card":
            txt = "Einkauf Debit Mastercard ,%s %s %s ,Karten-Nr. 5368 17XX XXXX 1234 " % (d_dmy(t.date), t.time[:5], t.party)
        elif t.kind == "atm":
            txt = "Bargeldbezug Debit Mastercard ,%s %s Bancomat %s ,Karten-Nr. 5368 17XX XXXX 1234 " % (d_dmy(t.date), t.time[:5], t.city)
        elif t.kind == "standing":
            txt = "Dauerauftrag                                   ,%s ,%s " % (n, t.msg)
        elif t.kind == "lsv":
            txt = "Belastung LSV ,%s ,%s " % (n, t.msg)
        elif t.kind in ("ebill", "ebill_qr"):
            txt = "Zahlung QR-Rechnung ,%s ,QR-Referenz: %s " % (n, t.ref)
        elif t.kind == "batch":
            txt = "Sammelauftrag Direct Net ,2 Zahlungen "
        elif t.kind == "salary":
            txt = "Gutschrift ,%s ,%s " % (n, t.msg)
        elif t.kind == "twint":
            txt = "TWINT Geld senden ,%s ,%s " % (n, t.msg)
        deb = fmt(-t.amount) if t.amount < 0 else ""
        cre = fmt(t.amount) if t.amount > 0 else ""
        td += -t.amount if t.amount < 0 else 0
        tc += t.amount if t.amount > 0 else 0
        sal = fmt(b) if last else ""
        L.append(",".join([d_dmy(t.book), q(txt), deb, cre, d_dmy(t.date), sal, fmt(b), "%s %s" % (d_dmy(t.book), "04:%02d:%02d" % (int(t.id) % 60, int(t.id) * 7 % 60))]))
    L.append("Total Spalte,,%s,%s,,,," % (fmt(td), fmt(tc)))
    write("ch_creditsuisse_legacy.csv", L, enc="cp1252", final_eol=False)

# ---------------------------------------------------------------- ZKB
def zkb_bt(t):
    n, addr, iban = party(t)
    if t.kind == "card":
        return "Einkauf ZKB Visa Debit Card Nr. xxxx 1234, %s" % ("NETFLIX.COM Amsterdam" if t.party == "NETFLIX.COM" else t.party)
    if t.kind == "atm":
        return "Bezug ZKB Visa Debit Card Nr. xxxx 1234, Bancomat %s" % t.city
    if t.kind == "standing": return "Dauerauftrag: %s" % n
    if t.kind == "lsv": return "LSV: %s" % n
    if t.kind in ("ebill", "ebill_qr"): return "E-Rechnung: %s" % n
    if t.kind == "batch": return "eBanking: Belastungen (%d)" % len(t.subs)
    if t.kind == "salary": return "Gutschrift: %s" % n
    if t.kind == "twint": return "TWINT Geld senden: %s" % n

def zkb():
    hdr = ["Datum", "Buchungstext", "Whg", "Betrag Detail", "ZKB-Referenz", "Referenznummer", "Belastung CHF", "Gutschrift CHF", "Valuta", "Saldo CHF", "Zahlungszweck", "Details"]
    L = [";".join(q(h) for h in hdr)]
    for t, b in reversed(TXB):
        n, addr, iban = party(t)
        ref = ("H%s%07d" % (t.book.strftime("%y%m%d"), int(t.id))) if t.kind in ("card", "atm", "twint") else ("Z%s%07d" % (t.book.strftime("%y%m%d"), int(t.id)))
        refnr = t.ref if t.ref else ""
        zweck = t.msg if t.kind in ("standing", "lsv", "salary", "twint") else ""
        det = "%s, %s" % (n, addr) if t.kind in ("standing", "lsv", "salary", "ebill", "ebill_qr") else ""
        row = [d_dmy(t.book), zkb_bt(t), "", "", ref, refnr, fmt(-t.amount) if t.amount < 0 else "", fmt(t.amount) if t.amount > 0 else "",
               d_dmy(t.date), fmt(b), zweck, det]
        L.append(";".join(q(c) for c in row))
        for s in t.subs:
            sn, saddr, siban = party(s)
            L.append(";".join(q(c) for c in ["", sn, "CHF", fmt(-s.amount), "", s.ref, "", "", "", "", s.msg, "%s, %s" % (sn, saddr)]))
    write("ch_zkb.csv", L, bom=True)

def zkb_simple():
    """Older/short ZKB layout (also 'Erweiterte Suche'): Datum;Buchungstext;Konto;Whg;Belastung;Gutschrift."""
    L = ";".join(q(h) for h in ["Datum", "Buchungstext", "Konto", "Whg", "Belastung", "Gutschrift"]),
    L = list(L)
    for t, b in reversed(TXB):
        n, addr, iban = party(t)
        txt = zkb_bt(t)
        if t.kind in ("standing", "lsv", "salary", "ebill", "ebill_qr"):
            txt = "%s, %s" % (txt, addr)
        L.append(";".join(q(c) for c in [d_dmy(t.book), txt, OWN_IBAN, "CHF", fmt(-t.amount) if t.amount < 0 else "", fmt(t.amount) if t.amount > 0 else ""]))
    write("ch_zkb_simple.csv", L, enc="cp1252")

# ---------------------------------------------------------------- Raiffeisen
def raif():
    L = ["IBAN;Booked At;Text;Details;Credit/Debit Amount;Balance;Valuta Date"]
    ib = "CH0080808001234567890"
    for t, b in TXB:
        n, addr, iban = party(t)
        if t.kind == "card":
            txt = "Einkauf %s %s, %s, Karte Debitkarte-Nr. 520000xxxxxx1234" % ("NETFLIX.COM Amsterdam" if t.party == "NETFLIX.COM" else t.party, d_dmy(t.date), t.time[:5])
            det = ""
        elif t.kind == "atm":
            txt = "Bargeldbezug Bancomat %s %s, %s, Karte Debitkarte-Nr. 520000xxxxxx1234" % (t.city, d_dmy(t.date), t.time[:5]); det = ""
        elif t.kind == "standing":
            txt = "E-Banking Dauerauftrag %s" % n; det = "%s CH Zahlung für: %s CHF %s -" % (addr.replace(",", ""), t.msg, fmt(-t.amount, thousands="'"))
        elif t.kind == "lsv":
            txt = "Lastschrift (LSV+) %s" % n; det = "%s CH Zahlung für: %s CHF %s -" % (addr.replace(",", ""), t.msg, fmt(-t.amount, thousands="'"))
        elif t.kind in ("ebill", "ebill_qr"):
            txt = "E-Banking Auftrag (eBill) %s" % n; det = "%s CH QR-Referenz: %s CHF %s -" % (addr.replace(",", ""), t.ref, fmt(-t.amount, thousands="'"))
        elif t.kind == "batch":
            txt = "E-Banking Sammelauftrag mit Einzelbuchungen"
            det = " ".join("%s %s CH CHF %s -" % (party(s)[0], party(s)[1].replace(",", ""), fmt(-s.amount, thousands="'")) for s in t.subs)
        elif t.kind == "salary":
            txt = "Gutschrift %s, %s" % (n, iban.replace(" ", "")); det = "%s CH Zahlung für: %s CHF %s -" % (addr.replace(",", ""), t.msg, fmt(t.amount, thousands="'"))
        elif t.kind == "twint":
            txt = "Zahlung TWINT, %s +417900000XX" % n.upper(); det = "Mitteilung: %s CHF %s -" % (t.msg, fmt(-t.amount))
        L.append(";".join([ib, t.book.strftime("%Y-%m-%d 00:00:00.0"), txt, det, fmt(t.amount, strip=True), fmt(b, strip=True), t.date.strftime("%Y-%m-%d 00:00:00.0")]))
    write("ch_raiffeisen.csv", L, enc="cp1252", final_eol=False)

# ---------------------------------------------------------------- BEKB
def bekb():
    L = ["Gutschrift / Belastung;Datum;Valuta;Buchungstext;Zusatzinfos Buchung;Name Auftraggeber / Begünstigter;Adresse Auftraggeber / Begünstigter;Konto / Bank;Mitteilung / Referenz;Zusatzinfos Transaktion;Betrag;Saldo"]
    for t, b in reversed(TXB):
        n, addr, iban = party(t)
        dirw = ("Gutschrift per %s" if t.amount > 0 else "Belastung per %s") % d_dmy(t.book)
        bt = {"card": "Verkaufspunkt/Debitkarte", "atm": "Bancomat/Debitkarte", "standing": "Dauerauftrag", "lsv": "Lastschrift LSV+",
              "ebill": "eBill", "ebill_qr": "eBill", "batch": "Ihr E-Banking-Sammelauftrag", "salary": "Zahlungseingang", "twint": "TWINT"}[t.kind]
        if t.kind in ("card", "atm"):
            nm, ad, kb, mr, zi = ("NETFLIX.COM" if t.party == "NETFLIX.COM" else t.party), (t.city or ""), "", "", "%s %s" % (d_dmy(t.date), t.time[:5])
        elif t.kind == "batch":
            nm, ad, kb, mr, zi = "", "", "", "", "%d Zahlungen" % len(t.subs)
        elif t.kind == "twint":
            nm, ad, kb, mr, zi = n, "", "+417900000XX", t.msg, ""
        else:
            nm, ad, kb = n, addr, iban.replace(" ", "")
            mr = ("%s -%s" % (t.ref, t.msg)) if t.ref else t.msg
            zi = ""
        L.append(";".join([dirw, d_dmy(t.book), d_dmy(t.date), bt, "", nm, ad, kb, mr, zi, fmt(t.amount), fmt(b)]))
    write("ch_bekb.csv", L, enc="cp1252")

# ---------------------------------------------------------------- Luzerner KB
def lukb():
    L = ["Buchung;Valuta;Buchungstext;Detail;Gutschrift;Belastung;Saldo (CHF)"]
    for t, b in reversed(TXB):
        n, addr, iban = party(t)
        r = int(t.id) * 7919 % 9000000000 + 1000000000
        if t.kind == "card":
            txt = "Warenbezug/Dienstleistung / %d Bezugsort: %s Transaktionsdatum: %s / %s Karten-Nr.: 5368 XXXX XXXX 1234 Betrag: CHF %s" % (r, "NETFLIX.COM Amsterdam" if t.party == "NETFLIX.COM" else t.party, d_dmy2(t.date), t.time, fmt(-t.amount))
        elif t.kind == "atm":
            txt = "Bargeldbezug / %d Bezugsort: Bancomat %s Transaktionsdatum: %s / %s Karten-Nr.: 5368 XXXX XXXX 1234" % (r, t.city, d_dmy2(t.date), t.time)
        elif t.kind == "standing": txt = "Dauerauftrag / %d %s %s Mitteilung: %s" % (r, n, addr, t.msg)
        elif t.kind == "lsv": txt = "Lastschrift / %d %s %s" % (r, n, t.msg)
        elif t.kind in ("ebill", "ebill_qr"): txt = "eBill / %d %s Referenz: %s" % (r, n, t.ref)
        elif t.kind == "batch": txt = "Sammelbelastung / %d" % r
        elif t.kind == "salary": txt = "Gutschrift / %d %s %s Mitteilung: %s" % (r, n, addr, t.msg)
        elif t.kind == "twint": txt = "TWINT Geld senden / %d %s Mitteilung: %s" % (r, n, t.msg)
        cr = fmt(t.amount, strip=True) if t.amount > 0 else " "
        db = fmt(-t.amount, strip=True) if t.amount < 0 else " "
        L.append(";".join([d_dmy(t.book), d_dmy(t.date), txt, " ", cr, db, fmt(b, strip=True)]))
        for s in t.subs:
            sn, saddr, siban = party(s)
            L.append(";".join([" ", " ", "Sammelbelastung / %d %s Referenz: %s" % (r, sn, s.ref), fmt(-s.amount, strip=True), " ", " ", " "]))
    write("ch_lukb.csv", L)

# ---------------------------------------------------------------- Thurgauer KB
def tkb():
    L = ["Buchungsdatum;Valutadatum;Auftragsart;Buchungstext;Betrag Einzelzahlung (CHF);Belastung (CHF);Gutschrift (CHF);Saldo in (CHF)"]
    for t, b in reversed(TXB):
        n, addr, iban = party(t)
        r = int(t.id) * 7919 % 9000000000 + 1000000000
        street, _, city = addr.partition(", ")
        if t.kind == "card":
            art = "Debitkarte"
            txt = "Warenbezug Debitkarte / Ref.-Nr. %d\n%s\n%s %s" % (r, "NETFLIX.COM Amsterdam" if t.party == "NETFLIX.COM" else t.party, d_dmy(t.date), t.time[:5])
        elif t.kind == "atm":
            art = "Debitkarte"; txt = "Bargeldbezug Debitkarte / Ref.-Nr. %d\nBancomat %s\n%s %s" % (r, t.city, d_dmy(t.date), t.time[:5])
        elif t.kind == "salary":
            art = "Vergütung"; txt = "Gutschrift / Ref.-Nr. %d\n%s\n%s\n%s\nSchweiz\nMitteilung: %s" % (r, n, street, city, t.msg)
        elif t.kind == "batch":
            art = "Sammelbelastung"; txt = "Sammelbelastung e-banking\n(Anzahl Zahlungen: %d / Ref.-Nr. %d)" % (len(t.subs), r)
        elif t.kind == "twint":
            art = "TWINT"; txt = "TWINT Geld senden / Ref.-Nr. %d\n%s\nMitteilung: %s" % (r, n, t.msg)
        else:
            art = {"standing": "Dauerauftrag", "lsv": "Lastschrift", "ebill": "eBill", "ebill_qr": "eBill"}[t.kind]
            txt = "Belastung e-banking / Ref.-Nr. %d\n%s\n%s\n%s\nSchweiz\n%s" % (r, n, street or n, city or "", ("Referenz: " + t.ref) if t.ref else "Mitteilung: " + t.msg)
        L.append(";".join([d_dmy(t.book), d_dmy(t.date), art, q(txt), "", fmt(-t.amount) if t.amount < 0 else "", fmt(t.amount) if t.amount > 0 else "", fmt(b)]))
        for s in t.subs:
            sn, saddr, siban = party(s)
            st, _, ci = saddr.partition(", ")
            L.append(";".join(["", "", "", q("%s\n%s\n%s\nSchweiz" % (sn, st or sn, ci)), fmt(-s.amount), "", "", ""]))
    write("ch_tkb.csv", L, enc="cp1252", final_eol=False)

# ---------------------------------------------------------------- Aargauische KB
def akb():
    L = ["Buchung;Buchungstext;Belastung;Gutschrift;Saldo CHF;"]
    for t, b in reversed(TXB):
        n, addr, iban = party(t)
        r = int(t.id) * 7919 % 900000000 + 100000000
        if t.kind == "card":
            txt = "Warenbezug und Dienstleistungen Debitkarte Kartennummer ********1234 %s %s %s" % (d_dmy(t.date), t.time[:5], "NETFLIX.COM" if t.party == "NETFLIX.COM" else t.party.upper())
        elif t.kind == "atm":
            txt = "Bargeldbezug Debitkarte Kartennummer ********1234 %s %s BANCOMAT %s" % (d_dmy(t.date), t.time[:5], t.city.upper())
        elif t.kind == "salary": txt = '" Zahlungseingang / Ref.-Nr. %d %s %s Mitteilung: %s "' % (r, n.upper(), addr.upper().replace(",", ""), t.msg)
        elif t.kind == "batch": txt = "Sammelbelastung e-banking / Ref.-Nr. %d" % r
        elif t.kind == "twint": txt = '" TWINT Geld senden / Ref.-Nr. %d %s %s "' % (r, n.upper(), t.msg)
        else: txt = '" Belastung e-banking / Ref.-Nr. %d %s %s "' % (r, n.upper(), addr.upper().replace(",", ""))
        L.append(";".join([d_dmy(t.book), txt, fmt(-t.amount, thousands="'") if t.amount < 0 else "", fmt(t.amount, thousands="'") if t.amount > 0 else "", fmt(b, thousands="'")]) + ";")
    write("ch_akb.csv", L, bom=True, final_eol=False)

# ---------------------------------------------------------------- Basler KB / Bank Cler (same platform)
def bkb_like(name, with_valuta, tag):
    cols = ["Buchungsdatum"] + (["Valutadatum"] if with_valuta else []) + ["Auftragsart", "Buchungstext" if tag == "bkb" else "Text", "Belastungsbetrag (CHF)", "Gutschriftsbetrag (CHF)", "Saldo (CHF)"]
    L = [";".join(cols)]
    for t, b in reversed(TXB):
        n, addr, iban = party(t)
        street, _, city = addr.partition(", ")
        if t.kind == "card":
            art = "Zahlung Debitkarte"; txt = "%s\n%s %s\nKarten-Nr. XXXX XXXX XXXX 1234" % ("NETFLIX.COM Amsterdam" if t.party == "NETFLIX.COM" else t.party, d_dmy(t.date), t.time[:5])
        elif t.kind == "atm":
            art = "Bargeldbezug"; txt = "Bancomat %s\n%s %s\nKarten-Nr. XXXX XXXX XXXX 1234" % (t.city, d_dmy(t.date), t.time[:5])
        elif t.kind == "salary":
            art = "Gutschrift"; txt = "%s\n%s\n%s\nSchweiz\n%s" % (n, street, city, t.msg)
        elif t.kind in ("ebill", "ebill_qr"):
            art = "QR-Rechnung"; txt = "%s\n%s\n%s\nSchweiz\nQR-Ref.: %s" % (n, street or n, city, t.ref)
        elif t.kind == "batch":
            art = "Sammelauftrag"; txt = "\n".join("%s CHF %s" % (party(s)[0], fmt(-s.amount)) for s in t.subs)
        elif t.kind == "twint":
            art = "TWINT"; txt = "%s\n+417900000XX\n%s" % (n, t.msg)
        elif t.kind == "standing":
            art = "Dauerauftrag"; txt = "%s\n%s\n%s\nSchweiz\nPers. Ref.: %s" % (n, street, city, t.msg)
        elif t.kind == "lsv":
            art = "Lastschrift"; txt = "%s\n%s\n%s\nSchweiz\n%s" % (n, street, city, t.msg)
        row = [d_dmy(t.book)] + ([d_dmy(t.date)] if with_valuta else []) + [art, q(txt), fmt(-t.amount) if t.amount < 0 else "", fmt(t.amount) if t.amount > 0 else "", fmt(b)]
        L.append(";".join(row))
    write(name, L, enc="cp1252", final_eol=(tag == "cler"))

# ---------------------------------------------------------------- Migros Bank
def migros():
    L = ['"Kontoauszug von:";"2025-10-01"', '"Kontoauszug bis:";"2026-09-30"', ";", '"Vertrag:";"12345678"',
         '"Kontonummer / IBAN:";"123.456.78 / CH00 0840 1000 1234 5678 9"', '"Bezeichnung:";"Privatkonto"', '"Saldo:";"%s"' % fmt(CLOSING), ";",
         '"Max Muster"', '"Seestrasse 12"', '"8280 Kreuzlingen"', ";", ";",
         '"Datum";"Buchungstext";"Mitteilung";"Referenznummer";"Betrag";"Saldo";"Valuta"']
    for t, b in TXB:
        n, addr, iban = party(t)
        if t.kind == "card":
            txt = "Einkauf Debitkarte %s %s, %s" % (d_dmy(t.date), t.time[:5], "NETFLIX.COM Amsterdam" if t.party == "NETFLIX.COM" else t.party)
        elif t.kind == "atm": txt = "Bargeldbezug Debitkarte %s %s, Bancomat %s" % (d_dmy(t.date), t.time[:5], t.city)
        elif t.kind == "salary": txt = "Zahlungseingang %s, %s, %s" % (n, addr, iban.replace(" ", ""))
        elif t.kind == "batch": txt = "Sammelauftrag E-Banking (%d Zahlungen)" % len(t.subs)
        elif t.kind == "twint": txt = "TWINT Geld senden an %s" % n
        else: txt = "%s %s, %s" % ({"standing": "Dauerauftrag an", "lsv": "Lastschrift", "ebill": "eBill-Zahlung an", "ebill_qr": "eBill-Zahlung an"}[t.kind], n, addr)
        msg = t.msg if t.kind in ("standing", "salary", "twint", "lsv") else ""
        refn = q(t.ref) if t.ref else ""
        L.append(";".join([q(d_dmy(t.book)), q(txt), q(msg), refn, q(fmt(t.amount)), q(fmt(b)), q(d_dmy(t.date))]))
    write("ch_migrosbank.csv", L, bom=True)

def migros_card():
    L = ["TransactionId,CardId,Date,ValutaDate,Amount,Currency,OriginalAmount,OriginalCurrency,MerchantName,MerchantPlace,MerchantCountry,StateType,Details,Type,Exchange Rate", ""]
    for t in reversed(CARD):
        tid = "TRX%s%010d" % (t.book.strftime("%Y%m%d"), int(t.id) * 1301)
        if t.kind == "cardpay":
            row = [tid, "", "%s 08:00:00" % d_iso(t.date), "%s 00:00:00" % d_iso(t.book), fmt(-t.amount, 3), "CHF", fmt(-t.amount, 3), "CHF", "", "", "", "BOOKED", "Zahlung - Besten Dank", "merchant", "1.000000"]
        else:
            mn, mp, mc = ("NETFLIX.COM", "Amsterdam", "NLD") if t.party == "NETFLIX.COM" else (t.party, "Kreuzlingen", "CHE")
            row = [tid, "012345ABCDEF1234", "%s %s" % (d_iso(t.date), t.time), "%s 00:00:00" % d_iso(t.book), fmt(-t.amount, 3), "CHF", fmt(-t.amount, 3), "CHF", mn, mp, mc, "BOOKED", mn, "merchant", "1.000000"]
        L.append(",".join(row))
        L.append("")
    write("ch_migrosbank_card.csv", L, bom=True)

# ---------------------------------------------------------------- Valiant
def valiant():
    L = ["Kontoauszug bis: 30.09.2026 ;;;", ";;;", "Kontonummer: 123456-7890;;;", "Bezeichnung: Privatkonto;;;",
         "Saldo: CHF %s;;;" % fmt(CLOSING), ";;;", "Max Muster;;;", "Seestrasse 12;;;", "8280 Kreuzlingen;;;", ";;;", ";;;",
         "Datum;Buchungstext;Betrag;Valuta"]
    for t, b in reversed(TXB):
        n, addr, iban = party(t)
        if t.kind == "card": txt = "Einkauf Debitkarte %s %s" % ("NETFLIX.COM Amsterdam" if t.party == "NETFLIX.COM" else t.party, d_dmy(t.date))
        elif t.kind == "atm": txt = "Bargeldbezug Bancomat %s %s" % (t.city, d_dmy(t.date))
        elif t.kind == "salary": txt = "Zahlungseingang %s %s" % (n, t.msg)
        elif t.kind == "batch": txt = "Sammelauftrag E-Banking"
        elif t.kind == "twint": txt = "TWINT %s %s" % (n, t.msg)
        else: txt = "%s %s" % ({"standing": "Dauerauftrag", "lsv": "Lastschrift", "ebill": "eBill", "ebill_qr": "eBill"}[t.kind], n + (" " + t.msg if t.kind == "lsv" else ""))
        L.append(";".join([d_dmy2(t.book), txt, fmt(t.amount), d_dmy2(t.date)]))
    write("ch_valiant.csv", L, enc="cp1252", final_eol=False)

# ---------------------------------------------------------------- neon / Yuh / Revolut / Wise / Swissquote
def neon():
    L = [";".join(q(h) for h in ["Date", "Amount", "Original amount", "Original currency", "Exchange rate", "Description", "Subject", "Category", "Tags", "Wise", "Spaces"])]
    cat = {"card": "groceries", "atm": "cash", "standing": "housing", "lsv": "insurance", "ebill": "bills", "ebill_qr": "bills", "batch": "bills", "salary": "income", "twint": "transfers"}
    for t, b in reversed(TXB_NB):
        n = party(t)[0]
        desc = {"atm": "Bancomat %s" % t.city, "twint": "TWINT %s" % n, "batch": "Sammelzahlung"}.get(t.kind, n if t.kind != "card" else ("Netflix" if t.party == "NETFLIX.COM" else t.party))
        subj = t.msg if t.kind in ("standing", "lsv", "salary", "twint") else (t.ref if t.ref else "")
        c = "entertainment" if t.party == "NETFLIX.COM" else cat[t.kind]
        L.append(";".join(q(x) for x in [d_iso(t.book), fmt(t.amount), "", "", "", desc, subj, c, "", "no", "no"]))
    write("ch_neon.csv", L, final_eol=False)

def yuh():
    L = ["DATE;ACTIVITY TYPE;ACTIVITY NAME;DEBIT;DEBIT CURRENCY;CREDIT;CREDIT CURRENCY;CARD NUMBER;LOCALITY;RECIPIENT;SENDER;FEES/COMMISSION;BUY/SELL;QUANTITY;ASSET;PRICE PER UNIT"]
    for t, b in TXB_NB:
        n = party(t)[0]
        typ = {"card": "Card payment", "atm": "Cash withdrawal", "standing": "Standing order", "lsv": "Direct debit", "ebill": "eBill payment",
               "ebill_qr": "eBill payment", "batch": "Payment", "salary": "Incoming payment", "twint": "TWINT"}[t.kind]
        name = "NETFLIX.COM" if t.party == "NETFLIX.COM" else (t.party if t.kind == "card" else ("Bancomat %s" % t.city if t.kind == "atm" else n))
        deb = fmt(t.amount) if t.amount < 0 else ""
        cre = fmt(t.amount) if t.amount > 0 else ""
        card = "XXXX XXXX XXXX 1234" if t.kind in ("card", "atm") else ""
        loc = (t.city or "") if t.kind in ("card", "atm") else ""
        rec = q(q(n)) if t.amount < 0 and t.kind not in ("card", "atm") else ""
        snd = q(q(n)) if t.amount > 0 else ""
        L.append(";".join([t.book.strftime("%d/%m/%Y"), typ, q(q(name)), deb, "CHF" if deb else "", cre, "CHF" if cre else "", card, loc, rec, snd, "0", "", "", "", ""]))
    write("ch_yuh.csv", L, bom=True)

def revolut():
    L = ["Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance"]
    for t, b in TXB_NB:
        n = party(t)[0]
        typ = {"card": "CARD_PAYMENT", "atm": "ATM", "salary": "TOPUP", "twint": "TRANSFER"}.get(t.kind, "TRANSFER")
        if t.kind == "card": desc = "Netflix" if t.party == "NETFLIX.COM" else t.party.split(" ")[0]
        elif t.kind == "atm": desc = "Cash at Bancomat %s" % t.city
        elif t.kind == "salary": desc = "Payment from %s" % n
        elif t.kind == "batch": desc = "To Swisscom (Schweiz) AG, Energie Kreuzlingen"
        else: desc = "To %s" % n
        st = "%s %s" % (d_iso(t.date), t.time if t.kind in ("card", "atm", "twint") else "08:%02d:%02d" % (int(t.id) % 60, int(t.id) * 3 % 60))
        ct = "%s %s" % (d_iso(t.book), t.time if t.kind in ("card", "atm", "twint") else st[11:])
        pend = t.date >= dt.date(2026, 9, 26) and t.kind == "card"
        fee = "0.00"
        L.append(",".join([typ, "Current", st, "" if pend else ct, desc, fmt(t.amount), fee, "CHF", "PENDING" if pend else "COMPLETED", "" if pend else fmt(b)]))
    write("ch_revolut.csv", L)

def wise():
    L = ['"TransferWise ID",Date,Amount,Currency,Description,"Payment Reference","Running Balance","Exchange From","Exchange To","Exchange Rate","Payer Name","Payee Name","Payee Account Number",Merchant,"Card Last Four Digits","Card Holder Full Name",Attachment,Note,"Total fees"']
    for t, b in reversed(TXB_NB):
        n, addr, iban = party(t)
        if t.kind in ("card", "atm"):
            mer = "Netflix.com" if t.party == "NETFLIX.COM" else (t.party if t.kind == "card" else "Bancomat %s" % t.city)
            wid = "CARD-%d" % (1800000000 + int(t.id))
            desc = ("Card transaction of %s CHF issued by %s" % (fmt(-t.amount), mer)) if t.kind == "card" else "Cash withdrawal of %s CHF at %s" % (fmt(-t.amount), mer)
            row = [wid, t.book.strftime("%d-%m-%Y"), fmt(t.amount), "CHF", q(desc), "", fmt(b), "", "", "", "", "", "", q(mer), "1234", q("MAX MUSTER"), "", "", "0.00"]
        elif t.amount > 0:
            row = ["TRANSFER-%d" % (900000000 + int(t.id)), t.book.strftime("%d-%m-%Y"), fmt(t.amount), "CHF", q("Received money from %s with reference %s" % (n, t.msg)), q(t.msg), fmt(b), "", "", "", q(n), "", "", "", "", "", "", "", "0.00"]
        else:
            ref = t.ref if t.ref else t.msg
            payee = "Swisscom (Schweiz) AG" if t.kind == "batch" else n
            acct = "" if t.kind == "twint" else iban.replace(" ", "")
            row = ["TRANSFER-%d" % (900000000 + int(t.id)), t.book.strftime("%d-%m-%Y"), fmt(t.amount), "CHF", q("Sent money to %s" % payee), q(ref), fmt(b), "", "", "", "", q(payee), acct, "", "", "", "", "", "0.00"]
        L.append(",".join(row))
    write("ch_wise.csv", L)

def swissquote():
    L = ["Datum;Auftrag #;Transaktionen;Symbol;Name;ISIN;Anzahl;Stückpreis;Kosten;Aufgelaufene Zinsen;Nettobetrag;Saldo;Währung"]
    for t, b in reversed(TXB_NB):
        n = party(t)[0]
        tr = {"card": "Debitkarte", "atm": "Bargeldbezug", "salary": "Zahlungseingang", "twint": "TWINT"}.get(t.kind, "Zahlung")
        name = ("NETFLIX.COM" if t.party == "NETFLIX.COM" else t.party) if t.kind == "card" else ("Bancomat %s" % t.city if t.kind == "atm" else n)
        L.append(";".join(["%s %s" % (t.book.strftime("%d-%m-%Y"), t.time if t.kind in ("card", "atm", "twint") else "00:00:00"), "%d" % (300000000 + int(t.id)), tr, "", name, "", "0.0", "0.0", "0.0", "0.0", fmt(t.amount), fmt(b), "CHF"]))
    write("ch_swissquote.csv", L)

# ---------------------------------------------------------------- Card issuers
def swisscard():
    L = ["Transaktionsdatum,Beschreibung,Händler,Kartennummer,Währung,Betrag,Fremdwährung,Betrag in Fremdwährung,Debit/Kredit,Status,Händlerkategorie,Registrierte Kategorie"]
    for t in reversed(CARD):
        if t.kind == "cardpay":
            row = [d_dmy(t.date), "IHRE ZAHLUNG – BESTEN DANK", "", "3776 62**** *4927", "CHF", fmt(-t.amount), "", "", "Gutschrift", "Gebucht", "Zahlungen", ""]
        else:
            pend = t.date >= dt.date(2026, 9, 26)
            if t.party == "NETFLIX.COM":
                desc, mer, cat, reg = "NETFLIX.COM, AMSTERDAM", "Netflix", "Unterhaltung", "VIDEO TAPE RENTAL STORES"
            else:
                desc, mer, cat, reg = "%s, KREUZLINGEN" % t.party.upper(), t.party.split(" ")[0], "Lebensmittel", "GROCERY STORES, SUPERMARKETS"
            row = [d_dmy(t.date), desc, mer, "3776 62**** *4927", "CHF", fmt(-t.amount), "", "", "Belastung", "Ausstehend" if pend else "Gebucht", cat, reg]
        L.append(",".join(q(c) for c in row))
    write("ch_swisscard.csv", L)

def viseca():
    L = ["TransactionId,CardId,Date,ValutaDate,Amount,Currency,OriginalAmount,OriginalCurrency,MerchantName,MerchantPlace,MerchantCountry,StateType,Details,Type"]
    for t in reversed(CARD):
        tid = "TRX%s%010d" % (t.book.strftime("%Y%m%d"), int(t.id) * 977)
        if t.kind == "cardpay":
            row = [tid, "", "%s 07:30:12" % d_iso(t.date), "%s 00:00:00" % d_iso(t.book), fmt(-t.amount, 3), "CHF", fmt(-t.amount, 3), "CHF", "", "", "", "BOOKED", "Ihre Zahlung", "merchant"]
        else:
            mn, mp, mc = ("NETFLIX.COM", "Amsterdam", "NL") if t.party == "NETFLIX.COM" else (t.party, "Kreuzlingen", "CH")
            row = [tid, "001", "%s %s" % (d_iso(t.date), t.time), "%s 00:00:00" % d_iso(t.book), fmt(-t.amount, 3), "CHF", fmt(-t.amount, 3), "CHF", mn, mp, mc, "BOOKED", mn, "merchant"]
        L.append(",".join(row))
    write("ch_viseca.csv", L, bom=True, final_eol=False)

if __name__ == "__main__":
    for f in [pf_efinance, pf_efinance_saldo, pf_legacy, pf_visa, ubs_new, ubs_signed, ubs_legacy, ubs_cc, cs, zkb, zkb_simple,
              raif, bekb, lukb, tkb, akb, migros, migros_card, valiant, neon, yuh, revolut, wise, swissquote, swisscard, viseca]:
        f()
    bkb_like("ch_bkb.csv", True, "bkb")
    bkb_like("ch_cler.csv", False, "cler")
    print("closing", CLOSING, "n", len(TXB), "card", len(CARD))
