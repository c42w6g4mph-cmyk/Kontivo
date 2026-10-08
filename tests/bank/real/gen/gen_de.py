# Generator for German bank export fixtures (invented data only).
import datetime as dt, random, os, sys
from decimal import Decimal as D

OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)

START, END = dt.date(2025, 10, 1), dt.date(2026, 9, 30)
OWN_NAME = "Max Mustermann"
OWN_IBAN = "DE00120300000012345678"
OWN_BIC = "TESTDEFFXXX"
OPEN_BAL = D("2450.00")

CI_TEL, MR_TEL = "DE12ZZZ00000012345", "TK-0045123987-01"
CI_PP, MR_PP = "LU12ZZZ0000000000000000099", "5MUSTER2258ABCD"
CI_ARD, MR_ARD = "DE34ZZZ00000077001", "ARD-4711-0815-42"
CI_ALZ, MR_ALZ = "DE55ZZZ00000033333", "AZ-VS-123456789"

P = dict(
    rent=("Wohnbau Konstanz GmbH", "DE00690500010000123401", "TESTDEKKXXX"),
    tel=("Telekom Deutschland GmbH", "DE00300000000000123402", "TESTDEBBXXX"),
    pp=("PayPal Europe S.a.r.l. et Cie S.C.A", "LU000000000000000403", "PPLXLUL2"),
    ard=("ARD ZDF Deutschlandradio Beitragsservice", "DE00370000000000123404", "TESTDECCXXX"),
    alz=("Allianz Versicherungs-AG", "DE00700000000000123405", "TESTDEMMXXX"),
    sal=("Muster Pharma GmbH", "DE00660000000000123406", "TESTDESSXXX"),
)
STORES = [("REWE", "REWE Markt GmbH", "REWE SAGT DANKE"),
          ("EDEKA", "EDEKA Muster Konstanz", "EDEKA MUSTER KONSTANZ"),
          ("ALDI", "ALDI SUED", "ALDI SUED SAGT DANKE")]

def bday(d):
    while d.weekday() >= 5:
        d += dt.timedelta(days=1)
    return d

def months():
    y, m = 2025, 10
    for _ in range(12):
        yield y, m
        m += 1
        if m == 13:
            y, m = y + 1, 1

rnd = random.Random(42)
T = []  # transactions
def add(kind, date, amount, name, iban, bic, purpose, typ, **kw):
    t = dict(kind=kind, date=date, book=bday(date), amount=D(amount), name=name,
             iban=iban, bic=bic, purpose=purpose, typ=typ, ci="", mr="", eref="", pending=False, card=False)
    t.update(kw)
    T.append(t)

seq = 0
for y, m in months():
    mm = f"{m:02d}/{y}"
    add("rent", dt.date(y, m, 1), "-1180.00", *P["rent"], "Miete Whg 3.OG Seestraße 12 inkl. NK", "standing")
    add("tel", dt.date(y, m, 3), "-39.95", *P["tel"], f"Kundenkonto 0045123987 Rechnung {mm}", "debit",
        ci=CI_TEL, mr=MR_TEL, eref=f"TK{y}{m:02d}0045123987")
    add("pp", dt.date(y, m, 5), "-11.99", *P["pp"], f"10450{y}{m:02d}8812 PP.5512.PP . Spotify AB, Ihr Einkauf bei Spotify AB", "debit",
        ci=CI_PP, mr=MR_PP, eref=f"10450{y}{m:02d}8812 PP.5512.PP PAYPAL", spotify=True)
    add("netflix", dt.date(y, m, 12), "-13.99", "NETFLIX.COM", "", "", "NETFLIX.COM Los Gatos", "card", card=True, city="Los Gatos", cc="US")
    add("atm", dt.date(y, m, 8), "-100.00", "Geldautomat Sparkasse Konstanz", "", "", "GA 69050001 Konstanz Marktstätte", "atm", card=True, city="Konstanz", cc="DE")
    add("atm", dt.date(y, m, 22), "-200.00", "Geldautomat Sparkasse Konstanz", "", "", "GA 69050001 Konstanz Bahnhof", "atm", card=True, city="Konstanz", cc="DE")
    if m in (1, 4, 7, 10):
        add("ard", dt.date(y, m, 15), "-55.08", *P["ard"], f"Rundfunk {m:02d}.{y} - {(m+2):02d}.{y} Beitragsnr. 123456789", "debit",
            ci=CI_ARD, mr=MR_ARD, eref=f"RB{y}{m:02d}123456789")
    if m == 3:
        add("alz", dt.date(y, m, 1), "-89.40", *P["alz"], f"Hausrat VS-Nr. 123456789 Beitrag {y}", "debit",
            ci=CI_ALZ, mr=MR_ALZ, eref=f"AZ{y}0301123456789")
    add("sal", dt.date(y, m, 28), "3920.00", *P["sal"], f"Lohn/Gehalt {mm} PersNr 4711", "credit", eref="NOTPROVIDED")

d = dt.date(2025, 10, 4)
i = 0
while d <= END:
    s = STORES[i % 3]
    amt = D(rnd.randint(1850, 9600)) / 100
    add("grocery", d, -amt, s[1], "", "", s[2], "card", card=True, store=s[0], city="Konstanz", cc="DE")
    i += 1
    d += dt.timedelta(days=7)
# one pending card purchase
add("grocery", dt.date(2026, 9, 30), "-23.47", "REWE Markt GmbH", "", "", "REWE SAGT DANKE", "card",
    card=True, store="REWE", city="Konstanz", cc="DE", pending=True)

T.sort(key=lambda t: (t["book"], t["date"], -t["amount"]))
bal = OPEN_BAL
for n, t in enumerate(T):
    t["id"] = n + 1
    if not t["pending"]:
        bal += t["amount"]
        t["bal"] = bal
    else:
        t["bal"] = None
CLOSE_BAL = bal
BOOKED = [t for t in T if not t["pending"]]

# ---------- formatting helpers ----------
def de(a, thousands=True, minimal=False, plus=False):
    a = D(a)
    s = f"{abs(a):,.2f}"
    if minimal:
        s = s.rstrip("0").rstrip(".") if "." in s else s
    s = s.replace(",", "X").replace(".", ",").replace("X", "." if thousands else "")
    sign = "-" if a < 0 else ("+" if plus and a > 0 else "")
    return sign + s
def en(a):
    return f"{D(a):.2f}"
def d8(x): return x.strftime("%d.%m.%Y")
def d6(x): return x.strftime("%d.%m.%y")
def iso(x): return x.isoformat()
def dnz(x): return f"{x.day}.{x.month}.{x.year}"
def q(v): return '"' + str(v).replace('"', '""') + '"'

def write(name, lines, enc="utf-8", nl="\n", bom=False, final_nl=True):
    data = nl.join(lines) + (nl if final_nl else "")
    b = data.encode(enc)
    if bom:
        b = b"\xef\xbb\xbf" + b
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(b)
    print(name, len(lines))

def desc(rows): return sorted(rows, key=lambda t: (t["book"], t["id"]), reverse=True)

def card_ref(t): return f"{t['date'].strftime('%Y%m%d')}{t['id']:06d}"

# ---------- Sparkasse ----------
SPK_BT_V2 = dict(standing="DAUERAUFTRAG", debit="FOLGELASTSCHRIFT", card="KARTENZAHLUNG",
                 atm="BARGELDAUSZAHLUNG", credit="GUTSCHR. UEBERWEISUNG")
def spk_name(t):
    if t["kind"] == "netflix": return "NETFLIX.COM"
    if t["kind"] == "atm": return "GA NR00001234 BLZ69050001 0"
    if t["kind"] == "grocery": return t["name"]
    return t["name"]
def spk_purpose_plain(t):
    if t["card"] and t["kind"] != "atm":
        return f"{t['purpose']}//{t['city']}/{t['cc']} {t['date'].isoformat()}T12:34:56 KFN 1 VJ 2912"
    if t["kind"] == "atm":
        return f"{t['purpose']} {t['date'].isoformat()}T10:15:00 KFN 1 VJ 2912"
    return t["purpose"]

def sparkasse_camt(fname, bt, own_iban=OWN_IBAN, unver=False):
    H = ["Auftragskonto","Buchungstag","Valutadatum","Buchungstext","Verwendungszweck","Glaeubiger ID","Mandatsreferenz","Kundenreferenz (End-to-End)","Sammlerreferenz","Lastschrift Ursprungsbetrag","Auslagenersatz Ruecklastschrift","Beguenstigter/Zahlungspflichtiger","Kontonummer/IBAN","BIC (SWIFT-Code)","Betrag","Waehrung","Info"]
    L = [";".join(q(h) for h in H)]
    for t in desc(T):
        L.append(";".join(q(v) for v in [own_iban, d6(t["book"]), d6(t["date"]), bt[t["typ"]], spk_purpose_plain(t),
              t["ci"], t["mr"], t["eref"], "", "", "", spk_name(t), t["iban"], t["bic"], de(t["amount"], thousands=False),
              "EUR", "Umsatz vorgemerkt" if t["pending"] else "Umsatz gebucht"]))
    write(fname, L, enc="cp1252")

sparkasse_camt("de_sparkasse_camt_v2.csv", SPK_BT_V2)
sparkasse_camt("de_sparkasse_camt_v8.csv", dict(SPK_BT_V2, credit="GUTSCHRIFT UEBERWEISUNG"))
sparkasse_camt("de_1822direkt.csv", SPK_BT_V2, own_iban="DE00500502010001822001")

def sepa_tags(t):
    s = ""
    if t["eref"]: s += "EREF+" + t["eref"]
    if t["mr"]: s += "MREF+" + t["mr"]
    if t["ci"]: s += "CRED+" + t["ci"]
    return s + "SVWZ+" + spk_purpose_plain(t)

H = ["Auftragskonto","Buchungstag","Valutadatum","Buchungstext","Verwendungszweck","Beguenstigter/Zahlungspflichtiger","Kontonummer","BLZ","Betrag","Waehrung","Info"]
L = [";".join(q(h) for h in H)]
for t in desc(T):
    L.append(";".join(q(v) for v in [OWN_IBAN, d6(t["book"]), d6(t["date"]), SPK_BT_V2[t["typ"]], sepa_tags(t),
          spk_name(t), t["iban"], t["bic"], de(t["amount"], thousands=False), "EUR",
          "Umsatz vorgemerkt" if t["pending"] else "Umsatz gebucht"]))
write("de_sparkasse_mt940.csv", L, enc="cp1252")

# Sparkasse credit card (CSV export of Sparkasse Kreditkarte)
H = ["Umsatz getätigt von","Belegdatum","Buchungsdatum","Originalbetrag","Originalwährung","Umrechnungskurs","Buchungsbetrag","Buchungswährung","Transaktionsbeschreibung","Transaktionsbeschreibung Zusatz","Buchungsreferenz","Gebührenschlüssel","Länderkennzeichen","BAR-Entgelt+Buchungsreferenz","AEE+Buchungsreferenz","Abrechnungskennzeichen"]
CARD = [t for t in BOOKED if t["card"] or t.get("spotify")]
L = [";".join(q(h) for h in H)]
holder = "51_5 0000 0000 0001234"
for t in desc(CARD):
    a = de(t["amount"], thousands=False)
    txt = "SPOTIFY P2A1B3C4D5 STOCKHOLM SE" if t.get("spotify") else (
        "NETFLIX.COM LOS GATOS US" if t["kind"] == "netflix" else (
        "BARGELDAUSZAHLUNG KONSTANZ DE" if t["kind"] == "atm" else f"{t['purpose']} KONSTANZ DE"))
    L.append(";".join(q(v) for v in [holder, d6(t["date"]), d6(t["book"]), a, "EUR", "1,00", a, "EUR", txt, "",
          f"0510{t['id']:07d}", "AE" if t["kind"] == "atm" else "", "", "", "", "202600000"]))
write("de_sparkasse_kreditkarte.csv", L, enc="cp1252", final_nl=False)

# Sparkasse camt.052 XML
def camt052():
    x = ['<?xml version="1.0" encoding="UTF-8"?>',
         '<Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.052.001.08" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="urn:iso:std:iso:20022:tech:xsd:camt.052.001.08 camt.052.001.08.xsd">',
         '  <BkToCstmrAcctRpt>',
         '    <GrpHdr>', '      <MsgId>camt52_20261001_000000001</MsgId>', '      <CreDtTm>2026-10-01T06:12:44.0+02:00</CreDtTm>', '    </GrpHdr>',
         '    <Rpt>', '      <Id>camt052_0001</Id>', '      <ElctrncSeqNb>1</ElctrncSeqNb>', '      <CreDtTm>2026-10-01T06:12:44.0+02:00</CreDtTm>',
         '      <FrToDt><FrDtTm>2025-10-01T00:00:00.0+02:00</FrDtTm><ToDtTm>2026-09-30T23:59:59.0+02:00</ToDtTm></FrToDt>',
         '      <Acct>', f'        <Id><IBAN>{OWN_IBAN}</IBAN></Id>', '        <Ccy>EUR</Ccy>',
         f'        <Ownr><Nm>{OWN_NAME}</Nm></Ownr>', '        <Svcr><FinInstnId><BICFI>TESTDE61XXX</BICFI><Nm>Sparkasse Musterstadt</Nm></FinInstnId></Svcr>', '      </Acct>']
    for cd, amt, date in (("PRCD", OPEN_BAL, "2025-09-30"), ("CLBD", CLOSE_BAL, "2026-09-30")):
        x += ['      <Bal>', f'        <Tp><CdOrPrtry><Cd>{cd}</Cd></CdOrPrtry></Tp>',
              f'        <Amt Ccy="EUR">{abs(amt):.2f}</Amt>', f'        <CdtDbtInd>{"CRDT" if amt >= 0 else "DBIT"}</CdtDbtInd>',
              f'        <Dt><Dt>{date}</Dt></Dt>', '      </Bal>']
    BT = dict(standing=("PMNT","ICDT","STDO","NSTO+117+00900","DAUERAUFTRAG"),
              debit=("PMNT","IDDT","PMDD","NDDT+105+00931","FOLGELASTSCHRIFT"),
              card=("PMNT","CCRD","POSD","NMSC+106+00931","KARTENZAHLUNG"),
              atm=("PMNT","CCRD","CWDL","NMSC+083+00931","BARGELDAUSZAHLUNG"),
              credit=("PMNT","RCDT","ESCT","NTRF+166+00931","GUTSCHR. UEBERWEISUNG"))
    def esc(s): return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    for t in T:
        dom, fam, sub, prop, addtl = BT[t["typ"]]
        crdt = t["amount"] > 0
        x += ['      <Ntry>', f'        <Amt Ccy="EUR">{abs(t["amount"]):.2f}</Amt>', f'        <CdtDbtInd>{"CRDT" if crdt else "DBIT"}</CdtDbtInd>',
              f'        <Sts><Cd>{"PDNG" if t["pending"] else "BOOK"}</Cd></Sts>',
              f'        <BookgDt><Dt>{t["book"].isoformat()}</Dt></BookgDt>', f'        <ValDt><Dt>{t["date"].isoformat()}</Dt></ValDt>',
              f'        <AcctSvcrRef>2026{t["id"]:010d}</AcctSvcrRef>',
              f'        <BkTxCd><Domn><Cd>{dom}</Cd><Fmly><Cd>{fam}</Cd><SubFmlyCd>{sub}</SubFmlyCd></Fmly></Domn><Prtry><Cd>{prop}</Cd><Issr>DK</Issr></Prtry></BkTxCd>',
              '        <NtryDtls><TxDtls>']
        refs = []
        if t["eref"]: refs.append(f'<EndToEndId>{esc(t["eref"])}</EndToEndId>')
        if t["mr"]: refs.append(f'<MndtId>{esc(t["mr"])}</MndtId>')
        if refs: x.append('          <Refs>' + "".join(refs) + '</Refs>')
        x.append(f'          <Amt Ccy="EUR">{abs(t["amount"]):.2f}</Amt>')
        if t["name"]:
            party = "Dbtr" if crdt else "Cdtr"
            acct = "DbtrAcct" if crdt else "CdtrAcct"
            rp = [f'<{party}><Pty><Nm>{esc(spk_name(t))}</Nm></Pty></{party}>']
            if t["ci"]:
                rp.append(f'<Cdtr><Pty><Nm>{esc(spk_name(t))}</Nm><Id><PrvtId><Othr><Id>{t["ci"]}</Id><SchmeNm><Prtry>SEPA</Prtry></SchmeNm></Othr></PrvtId></Id></Pty></Cdtr>')
                rp = rp[1:]
            if t["iban"]: rp.append(f'<{acct}><Id><IBAN>{t["iban"]}</IBAN></Id></{acct}>')
            x.append('          <RltdPties>' + "".join(rp) + '</RltdPties>')
        if t["bic"]:
            ag = "DbtrAgt" if crdt else "CdtrAgt"
            x.append(f'          <RltdAgts><{ag}><FinInstnId><BICFI>{t["bic"]}</BICFI></FinInstnId></{ag}></RltdAgts>')
        x.append(f'          <RmtInf><Ustrd>{esc(spk_purpose_plain(t))}</Ustrd></RmtInf>')
        x += ['        </TxDtls></NtryDtls>', f'        <AddtlNtryInf>{addtl}</AddtlNtryInf>', '      </Ntry>']
    x += ['    </Rpt>', '  </BkToCstmrAcctRpt>', '</Document>']
    write("de_sparkasse_camt052.xml", x)
camt052()

# ---------- Atruvia (VR / Sparda / PSD / GLS) ----------
def atruvia(fname, acct_name, bank, bic, umlaut, minimal, crlf, bt):
    H = ["Bezeichnung Auftragskonto","IBAN Auftragskonto","BIC Auftragskonto","Bankname Auftragskonto","Buchungstag","Valutadatum",
         "Name Zahlungsbeteiligter","IBAN Zahlungsbeteiligter","BIC (SWIFT-Code) Zahlungsbeteiligter","Buchungstext","Verwendungszweck",
         "Betrag", "Währung" if umlaut else "Waehrung", "Saldo nach Buchung","Bemerkung","Gekennzeichneter Umsatz",
         "Gläubiger ID" if umlaut else "Glaeubiger ID","Mandatsreferenz"]
    L = [";".join(H)]
    for t in desc(BOOKED):
        p = t["purpose"]
        if t["card"]:
            p = f"{t['purpose']}//{t['city']}/{t['cc']} {t['date'].strftime('%d.%m.%Y')} 12:34 Debitk. 1 {t['date'].strftime('%m')}/2029"
        elif t["typ"] == "debit":
            p = f"{t['purpose']} EREF: {t['eref']} MREF: {t['mr']} CRED: {t['ci']} IBAN: {t['iban']} BIC: {t['bic']}"
        elif t["typ"] in ("standing", "credit"):
            p = f"{t['purpose']} EREF: {t['eref'] or 'NOTPROVIDED'} IBAN: {t['iban']} BIC: {t['bic']}"
        name = t["name"] if t["kind"] != "atm" else ""
        L.append(";".join([acct_name, OWN_IBAN, bic, bank, d8(t["book"]), d8(t["date"]), name, t["iban"], t["bic"],
              bt[t["typ"]], p, de(t["amount"], thousands=False, minimal=minimal), "EUR",
              de(t["bal"], thousands=False, minimal=minimal), "", "", t["ci"], t["mr"]]))
    write(fname, L, enc="utf-8", bom=True, nl="\r\n" if crlf else "\n")
ATR_BT = dict(standing="Dauerauftragsbelast", debit="Basislastschrift", card="Kartenzahlung girocard",
              atm="Auszahlung girocard", credit="Überweisungsgutschr.")
atruvia("de_vr_atruvia.csv", "GiroKonto Online", "Volksbank Musterland eG", "GENODEF1XXX", False, False, True, ATR_BT)
atruvia("de_sparda.csv", "SpardaGiro Online", "Sparda-Bank Musterland eG", "GENODEF1S99", True, True, False, ATR_BT)
atruvia("de_gls.csv", "GLS Girokonto", "GLS Gemeinschaftsbank eG", "GENODEM1GLS", False, True, True, ATR_BT)
atruvia("de_psd.csv", "PSD GiroDirekt", "PSD Bank Musterland eG", "GENODEF1P99", False, False, True, ATR_BT)

# old VR/Fiducia format (cp1252, preamble, S/H, multiline fields, footer)
FID_BT = dict(standing="DAUERAUFTRAG", debit="BASISLASTSCHRIFT", card="KARTENZAHLUNG", atm="AUSZAHLUNG GA", credit="GUTSCHRIFT")
L = ['"Volksbank Musterland eG"', '', '"Umsatzanzeige"', '',
     '"BLZ:";"69000000";;"Datum:";"01.10.2026"', '"Konto:";"12345678";;"Uhrzeit:";"08:15:02"',
     f'"Abfrage von:";"{OWN_NAME}";;"Kontoinhaber:";"{OWN_NAME}"', '',
     '"Zeitraum:";"Alle Umsätze";"von:";"01.10.2025";"bis:";"30.09.2026"', '"Betrag in EUR:";;"von:";" ";"bis:";" "',
     '"Sortiert nach:";"Buchungstag";"absteigend"', '',
     '"Buchungstag";"Valuta";"Auftraggeber/Zahlungsempfänger";"Empfänger/Zahlungspflichtiger";"Konto-Nr.";"IBAN";"BLZ";"BIC";"Vorgang/Verwendungszweck";"Kundenreferenz";"Währung";"Umsatz";" "']
for t in desc(BOOKED):
    other = t["name"] if t["kind"] != "atm" else "GA NR00001234"
    a_from, a_to = (other, OWN_NAME) if t["amount"] > 0 else (OWN_NAME, other)
    lines = [FID_BT[t["typ"]]] + [c for c in (t["purpose"][:27], t["purpose"][27:54]) if c]
    if t["ci"]:
        lines.append(f"EREF: {t['eref']} MREF: {t['mr']}")
        lines.append(f"CRED: {t['ci']}")
    if t["iban"]:
        lines.append(f"IBAN: {t['iban']} BIC: {t['bic']}")
    vz = "\n".join(lines)
    L.append(";".join([q(d8(t["book"])), q(d8(t["date"])), q(a_from), q(a_to), "", q(t["iban"]) if t["iban"] else "", "",
             q(t["bic"]) if t["bic"] else "", q(vz), "", q("EUR"), q(de(abs(t["amount"]))), q("H" if t["amount"] > 0 else "S")]))
L += ["", f'"01.10.2025";;;;;;;;;"Anfangssaldo";"EUR";"{de(abs(OPEN_BAL))}";"H"', f'"30.09.2026";;;;;;;;;"Endsaldo";"EUR";"{de(abs(CLOSE_BAL))}";"H"']
write("de_vr_fiducia_alt.csv", L, enc="cp1252", nl="\r\n")

# VR MT940 (.sta)
GVC = dict(standing=("117", "Dauerauftragsbelast", "NSTO"), debit=("105", "Basislastschrift", "NDDT"),
           card=("106", "Kartenzahlung girocard", "NMSC"), atm=("083", "Auszahlung girocard", "NMSC"),
           credit=("166", "Gutschrift", "NTRF"))
def translit(s):
    for a, b in (("ä","ae"),("ö","oe"),("ü","ue"),("Ä","AE"),("Ö","OE"),("Ü","UE"),("ß","ss")):
        s = s.replace(a, b)
    return s
def chunks(s, n=27):
    return [s[i:i+n] for i in range(0, len(s), n)] or [""]
def mt940(fname, blz="69000000", kto="0012345678"):
    L = []
    bal = OPEN_BAL
    days = sorted({t["book"] for t in BOOKED})
    for n, day in enumerate(days):
        rows = [t for t in BOOKED if t["book"] == day]
        L += [":20:STARTUMS", f":25:{blz}/{kto}", f":28C:{n+1:05d}/001",
              f":60F:{'C' if bal >= 0 else 'D'}{day.strftime('%y%m%d')}EUR{de(abs(bal), thousands=False)}"]
        for t in rows:
            code, txt, swift = GVC[t["typ"]]
            cd = "CR" if t["amount"] > 0 else "DR"
            L.append(f":61:{t['date'].strftime('%y%m%d')}{t['book'].strftime('%m%d')}{cd}{de(abs(t['amount']), thousands=False)}{swift}{(t['eref'] or 'NONREF').replace(' ', '')[:16]}")
            sub = [f"?00{txt}", "?10931"]
            parts = []
            if t["eref"]: parts.append("EREF+" + t["eref"])
            if t["mr"]: parts.append("MREF+" + t["mr"])
            if t["ci"]: parts.append("CRED+" + t["ci"])
            parts.append("SVWZ+" + t["purpose"])
            vz = [c for p in parts for c in chunks(translit(p))][:10]
            for k, c in enumerate(vz):
                sub.append(f"?{20+k}{c}")
            if t["bic"]: sub.append(f"?30{t['bic']}")
            if t["iban"]: sub.append(f"?31{t['iban']}")
            nm = t["name"] if t["kind"] != "atm" else "GA NR00001234"
            nmc = chunks(translit(nm))
            sub.append(f"?32{nmc[0]}")
            if len(nmc) > 1: sub.append(f"?33{nmc[1]}")
            sub.append("?34992" if t["typ"] == "debit" else "?34000")
            body = f":86:{code}" + "".join(sub)
            L += [body[i:i+65] for i in range(0, len(body), 65)]
            bal += t["amount"]
        L += [f":62F:{'C' if bal >= 0 else 'D'}{day.strftime('%y%m%d')}EUR{de(abs(bal), thousands=False)}", "-"]
    write(fname, L, enc="cp1252", nl="\r\n")
mt940("de_vr_mt940.sta")

# ---------- ING ----------
def ing_fields(t):
    if t["kind"] == "netflix":
        return "VISA NETFLIX.COM", "Lastschrift", f"NR XXXX 1234 LOS GATOS US KAUFUMSATZ {t['date'].strftime('%d.%m')} 13.99 {t['id']:06d} ARN74{t['id']:018d}"
    if t["kind"] == "grocery":
        return f"VISA {t['name'].upper()}", "Lastschrift", f"NR XXXX 1234 KONSTANZ DE KAUFUMSATZ {t['date'].strftime('%d.%m')} {abs(t['amount']):.2f} {t['id']:06d} ARN74{t['id']:018d}"
    if t["kind"] == "atm":
        return "Bargeldauszahlung VISA Card SPARKASSE ATM", "Lastschrift", f"NR XXXX 1234 KONSTANZ DE BARGELDAUSZAHLUNG {t['date'].strftime('%d.%m')} {abs(t['amount']):.2f} {t['id']:06d} ARN74{t['id']:018d}"
    bt = {"standing": "Dauerauftrag / Terminueberweisung", "debit": "Lastschrift", "credit": "Gehalt/Rente"}[t["typ"]]
    return t["name"], bt, t["purpose"]
def ing_pre(old):
    L = ["Umsatzanzeige;Datei erstellt am: 01.10.2026 08:15"]
    if old: L.append(";Letztes Update: aktuell")
    L += ["", f"IBAN;{' '.join(OWN_IBAN[i:i+4] for i in range(0, 22, 4))}", "Kontoname;Girokonto", "Bank;ING", f"Kunde;{OWN_NAME}",
          "Zeitraum;01.10.2025 - 30.09.2026", f"Saldo;{de(CLOSE_BAL)};EUR", "", "Sortierung;Datum absteigend", "",
          "In der CSV-Datei finden Sie alle bereits gebuchten Umsätze. Die vorgemerkten Umsätze werden nicht aufgenommen, auch wenn sie in Ihrem Internetbanking angezeigt werden.", ""]
    return L
L = ing_pre(False) + ["Buchung;Wertstellungsdatum;Auftraggeber/Empfänger;Buchungstext;Verwendungszweck;Betrag;Währung"]
for t in desc(BOOKED):
    n, b, p = ing_fields(t)
    L.append(";".join([d8(t["book"]), d8(t["date"]), n, b, p, de(t["amount"]), "EUR"]))
write("de_ing.csv", L, enc="cp1252")
L = ing_pre(True) + ["Buchung;Valuta;Auftraggeber/Empfänger;Buchungstext;Verwendungszweck;Saldo;Währung;Betrag;Währung"]
for t in desc(BOOKED):
    n, b, p = ing_fields(t)
    L.append(";".join([d8(t["book"]), d8(t["date"]), n, b, p, de(t["bal"]), "EUR", de(t["amount"]), "EUR"]))
write("de_ing_alt.csv", L, enc="cp1252")

# ---------- DKB ----------
def dkb_new():
    L = [f'"Girokonto";"{OWN_IBAN}"', '""', f'"Kontostand vom 30.09.2026:";"{de(CLOSE_BAL)} €"', '""',
         ";".join(q(h) for h in ["Buchungsdatum","Wertstellung","Status","Zahlungspflichtige*r","Zahlungsempfänger*in","Verwendungszweck","Umsatztyp","IBAN","Betrag (€)","Gläubiger-ID","Mandatsreferenz","Kundenreferenz"])]
    for t in desc(T):
        if t["card"]:
            payer = "ISSUER"
            rec = {"netflix": "NETFLIX.COM//Los Gatos/US", "atm": "Sparkasse Konstanz//Konstanz/DE"}.get(t["kind"], f"{t['name'].upper()}//Konstanz/DE")
            vz = f"{t['date'].isoformat()} Debitk.12 VISA Debit"
            kref = f"{t['id']:015d}"
        else:
            payer, rec = (t["name"], OWN_NAME) if t["amount"] > 0 else (OWN_NAME, t["name"])
            vz, kref = t["purpose"], t["eref"]
        L.append(";".join(q(v) for v in [d6(t["book"]), d6(t["date"]), "Vorgemerkt" if t["pending"] else "Gebucht", payer, rec, vz,
              "Eingang" if t["amount"] > 0 else "Ausgang", t["iban"], de(t["amount"], minimal=True), t["ci"], t["mr"], kref]))
    write("de_dkb.csv", L, enc="utf-8", bom=True)
dkb_new()
DKB_OLD_BT = dict(standing="DAUERAUFTRAG", debit="FOLGELASTSCHRIFT", card="Kartenzahlung", atm="Kartenzahlung/-abrechnung", credit="Lohn, Gehalt, Rente")
L = [f'"Kontonummer:";"{OWN_IBAN} / Girokonto";', '', '"Von:";"01.10.2025";', '"Bis:";"30.09.2026";', f'"Kontostand vom 30.09.2026:";"{de(CLOSE_BAL)} EUR";', '',
     ";".join(q(h) for h in ["Buchungstag","Wertstellung","Buchungstext","Auftraggeber / Begünstigter","Verwendungszweck","Kontonummer","BLZ","Betrag (EUR)","Gläubiger-ID","Mandatsreferenz","Kundenreferenz"]) + ";"]
for t in desc(BOOKED):
    nm = t["name"] if not t["card"] else ("NETFLIX.COM" if t["kind"] == "netflix" else ("GA Sparkasse Konstanz" if t["kind"] == "atm" else t["name"]))
    L.append(";".join(q(v) for v in [d8(t["book"]), d8(t["date"]), DKB_OLD_BT[t["typ"]], nm, t["purpose"], t["iban"], t["bic"],
             de(t["amount"]), t["ci"], t["mr"], t["eref"]]) + ";")
write("de_dkb_alt.csv", L, enc="cp1252")

# DKB Visa (new) – credit card: purchases negative, settlement positive
def cc_rows():
    rows = []
    for t in T:
        if t["card"] or t.get("spotify"):
            r = dict(t)
            if t.get("spotify"):
                r.update(name="Spotify", purpose="Spotify P2A1B3C4D5", card=True, kind="spotify", typ="card", ci="", mr="", eref="")
            rows.append(r)
    # monthly settlement on 2nd business day of next month
    out = list(rows)
    for y, m in months():
        s = -sum(r["amount"] for r in rows if r["date"].year == y and r["date"].month == m and not r["pending"])
        ny, nm = (y + 1, 1) if m == 12 else (y, m + 1)
        if (ny, nm) > (2026, 9):
            continue
        dd = bday(dt.date(ny, nm, 2))
        out.append(dict(kind="settle", date=dd, book=dd, amount=s, name="Ausgleich Kreditkarte gem. Abrechnung", purpose="Ausgleich Kreditkarte gem. Abrechnung",
                        typ="settle", card=False, pending=False, id=900000 + ny * 100 + nm, iban="", bic="", ci="", mr="", eref=""))
    out.sort(key=lambda t: (t["book"], t["id"]))
    return out
CC = cc_rows()
L = ['"Karte";"Visa Kreditkarte";"4930 •••• •••• 1234"', '""', f'"Saldo vom 30.09.2026:";"{de(-sum(r["amount"] for r in CC if r["date"].month == 9 and r["date"].year == 2026 and not r["pending"]))} €"', '""',
     ";".join(q(h) for h in ["Belegdatum","Wertstellung","Status","Beschreibung","Umsatztyp","Betrag (€)","Fremdwährungsbetrag"])]
for r in sorted(CC, key=lambda t: (t["book"], t["id"]), reverse=True):
    if r["kind"] == "settle": b, ty = r["name"], "Lastschrift"
    elif r["kind"] == "atm": b, ty = "Sparkasse Konstanz", "Bargeldabhebung"
    elif r["kind"] in ("netflix", "spotify"): b, ty = ("NETFLIX.COM" if r["kind"] == "netflix" else "Spotify P2A1B3C4D5"), "Online"
    else: b, ty = f"{r['name']} Konstanz", "Im Geschäft"
    L.append(";".join(q(v) for v in [d6(r["date"]), d6(r["book"]), "Vorgemerkt" if r["pending"] else "Gebucht", b, ty, de(r["amount"]) + " €", ""]))
write("de_dkb_visa.csv", L, enc="utf-8", bom=True)

# ---------- comdirect ----------
CD_V = dict(standing="Übertrag / Überweisung", debit="Lastschrift / Belastung", card="Kartenverfügung", atm="Auszahlung GAA", credit="Übertrag / Überweisung")
L = [";", '"Umsätze Girokonto";"Zeitraum: 01.10.2025 - 30.09.2026";', f'"Neuer Kontostand";"{de(CLOSE_BAL)} EUR";', "",
     '"Buchungstag";"Wertstellung (Valuta)";"Vorgang";"Buchungstext";"Umsatz in EUR";']
for t in desc(T):
    if t["amount"] > 0:
        bt = f"Auftraggeber: {t['name']} Buchungstext: {t['purpose']} Ref. {t['eref']}"
    elif t["card"]:
        bt = f"Buchungstext: {t['purpose']} {t['city']} DE Karte Nr. 4871 78XX XXXX 1234 Debitkarte {t['date'].strftime('%d.%m.%Y')} Ref. {card_ref(t)}"
    else:
        bt = f"Empfänger: {t['name']} Kto/IBAN: {t['iban']} BLZ/BIC: {t['bic']} Buchungstext: {t['purpose']} Ref. {t['eref'] or card_ref(t)}"
        if t["ci"]:
            bt += f" Gläubiger-ID: {t['ci']} Mandat: {t['mr']}"
    L.append(";".join(q(v) for v in ["offen" if t["pending"] else d8(t["book"]), "--" if t["pending"] else d8(t["date"]), CD_V[t["typ"]], bt, de(t["amount"])]) + ";")
L += [f'"Alter Kontostand";"{de(OPEN_BAL)} EUR";', ""]
write("de_comdirect.csv", L, enc="iso-8859-15", final_nl=False)

# ---------- Commerzbank ----------
CB_U = dict(standing="Dauerauftrag", debit="Lastschrift", card="Lastschrift", atm="Lastschrift", credit="Gutschrift")
def cb_text(t):
    if t["card"]:
        if t["kind"] == "atm":
            return f"Auszahlung Geldautomat Sparkasse Konstanz//Konstanz/DE {t['date'].isoformat()}T10:15:00 KFN 1 VJ 2912"
        return f"Kartenzahlung {t['purpose']}//{t['city']}/{t['cc']} {t['date'].isoformat()}T12:34:56 KFN 1 VJ 2912"
    s = f"{t['name']} {t['purpose']}"
    if t["eref"]: s += f" End-to-End-Ref.: {t['eref']}"
    if t["ci"]: s += f" Mandatsref: {t['mr']} Gläubiger-ID: {t['ci']} SEPA-BASISLASTSCHRIFT wiederholend"
    return s
L = ["Buchungstag;Wertstellung;Umsatzart;Buchungstext;Betrag;Währung;IBAN Kontoinhaber;Kategorie"]
for t in BOOKED:
    L.append(";".join([d8(t["book"]), d8(t["date"]), CB_U[t["typ"]], cb_text(t), de(t["amount"], thousands=False, minimal=True), "EUR", OWN_IBAN, ""]))
write("de_commerzbank.csv", L, enc="utf-8", bom=True, nl="\r\n")
L = [";".join(["Buchungstag","Wertstellung","Umsatzart","Buchungstext","Betrag","Währung","Auftraggeberkonto","Bankleitzahl Auftraggeberkonto","IBAN Auftraggeberkonto","Kategorie"])]
for t in BOOKED:
    L.append(";".join([d8(t["book"]), d8(t["date"]), CB_U[t["typ"]], q(cb_text(t)), de(t["amount"], thousands=False), "EUR", "12345678", "20040000", OWN_IBAN,
                       "Lebensmittel" if t["kind"] == "grocery" else "Unkategorisierte Ausgaben" if t["amount"] < 0 else "Unkategorisierte Einnahmen"]))
write("de_commerzbank_alt.csv", L, enc="utf-8", bom=True)

# ---------- Postbank / Deutsche Bank / Norisbank (same platform) ----------
PB_U = dict(standing="SEPA Dauerauftrag", debit="SEPA Lastschrift", card="Kartenzahlung", atm="Bargeldauszahlung (Geldautomat)", credit="SEPA Überweisung")
def pb_like(fname, konto, kontonr):
    pad = lambda cells: ";".join(cells + [""] * (18 - len(cells)))
    L = [pad(["Umsätze"]), pad(["Konto", "Filial-/Kontonummer", "IBAN", "Währung"]), pad([konto, kontonr, OWN_IBAN, "EUR"]), pad([]),
         pad(["1.10.2025 - 30.9.2026"]), pad(["Letzter Kontostand", "", "", "", de(CLOSE_BAL, thousands=False, minimal=True), "EUR"]),
         pad(["Vorgemerkte und noch nicht gebuchte Umsätze sind nicht Bestandteil dieser Übersicht."]),
         "Buchungstag;Wert;Umsatzart;Begünstigter / Auftraggeber;Verwendungszweck;IBAN / Kontonummer;BIC;Kundenreferenz;Mandatsreferenz;Gläubiger ID;Fremde Gebühren;Betrag;Abweichender Empfänger;Anzahl der Aufträge;Anzahl der Schecks;Soll;Haben;Währung"]
    for t in desc(BOOKED):
        a = de(t["amount"], thousands=False, minimal=True)
        if t["card"]:
            nm = {"netflix": "NETFLIX.COM", "atm": "Sparkasse Konstanz"}.get(t["kind"], t["name"])
            vz = f"{t['purpose']}//{t['city']}/{t['cc']} {t['date'].strftime('%d-%m-%Y')}T12:34:56 Folgenr. 01 Verfalld. 2912"
        else:
            nm, vz = t["name"], t["purpose"]
        L.append(";".join([dnz(t["book"]), dnz(t["date"]), PB_U[t["typ"]], nm, vz, t["iban"], t["bic"], t["eref"], t["mr"], t["ci"], "", a, "", "", "",
                           a if t["amount"] < 0 else "", a if t["amount"] > 0 else "", "EUR"]))
    L.append(pad(["Kontostand", dnz(END), "", "", de(CLOSE_BAL, thousands=False, minimal=True), "EUR"]))
    write(fname, L, enc="utf-8", bom=True, nl="\r\n")
pb_like("de_postbank.csv", "Postbank Giro plus", "123 4567890 00")
pb_like("de_deutschebank.csv", "AktivKonto", "100 1234567 00")
pb_like("de_norisbank.csv", "Top-Girokonto", "100 7654321 00")

# ---------- Targobank (no header) ----------
TG = dict(standing="Dauerauftrag", debit="Lastschrift", card="Kartenzahlung", atm="Bargeldauszahlung", credit="Gutschrift")
L = []
for t in BOOKED:
    if t["card"]:
        txt = f"{TG[t['typ']]}   {t['name'].upper()}   {t['city'].upper()} 74026606   Kartennummer: 439556XXXXXX012X"
    else:
        txt = f"{TG[t['typ']]}   {t['name']}   {t['iban']}   {t['purpose']}"
        if t["ci"]: txt += f"   {t['eref']}   {t['ci']}   {t['mr']}"
    deb, cre = (de(t["amount"], thousands=False), "") if t["amount"] < 0 else ("", de(t["amount"], thousands=False))
    L.append(";".join([d8(t["book"]), txt, deb, cre, "", "", f"'{OWN_IBAN}'"]))
write("de_targobank.csv", L, enc="utf-8")

# ---------- N26 ----------
N26_T = dict(standing="Debit Transfer", debit="Direct Debit", card="Presentment", atm="Presentment", credit="Credit Transfer")
L = [",".join(q(h) for h in ["Booking Date","Value Date","Partner Name","Partner Iban","Type","Payment Reference","Account Name","Amount (EUR)","Original Amount","Original Currency","Exchange Rate"])]
for t in BOOKED:
    nm = {"netflix": "NETFLIX.COM", "atm": "Sparkasse Konstanz ATM"}.get(t["kind"], t["name"])
    L.append(",".join(q(v) for v in [iso(t["book"]), iso(t["date"]), nm, t["iban"], N26_T[t["typ"]], "" if t["card"] else t["purpose"], "Main Account", en(t["amount"]), "", "", ""]))
write("de_n26.csv", L)
N26_A = dict(standing="Überweisung", debit="Lastschrift", card="MasterCard Zahlung", atm="MasterCard Zahlung", credit="Gutschrift")
L = [",".join(q(h) for h in ["Datum","Empfänger","Kontonummer","Transaktionstyp","Verwendungszweck","Kategorie","Betrag (EUR)","Betrag (Fremdwährung)","Fremdwährung","Wechselkurs"])]
for t in BOOKED:
    nm = {"netflix": "NETFLIX.COM", "atm": "Sparkasse Konstanz ATM"}.get(t["kind"], t["name"])
    cat = {"grocery": "Lebensmittel & Supermärkte", "atm": "Bargeld", "sal": "Gehalt", "rent": "Miete & Wohnen", "netflix": "Medien & Elektronik"}.get(t["kind"], "Sonstiges")
    fx = [en(t["amount"]), "EUR", "1.0"] if t["card"] else ["", "", ""]
    L.append(",".join(q(v) if "," in v else v for v in [iso(t["date"]), nm, t["iban"], N26_A[t["typ"]], "" if t["card"] else t["purpose"], cat, en(t["amount"])] + fx))
write("de_n26_alt.csv", L)

# ---------- Revolut ----------
L = ["Type,Product,Started Date,Completed Date,Description,Amount,Fee,Currency,State,Balance"]
for t in T:
    typ = {"card": "CARD_PAYMENT", "atm": "ATM", "standing": "TRANSFER", "debit": "TRANSFER", "credit": "TRANSFER"}[t["typ"]]
    if t["kind"] == "netflix": ds = "Netflix"
    elif t["kind"] == "atm": ds = "Cash at Sparkasse Konstanz"
    elif t["kind"] == "grocery": ds = {"REWE": "Rewe", "EDEKA": "Edeka", "ALDI": "Aldi Sued"}[t["store"]]
    elif t["typ"] == "credit": ds = f"Payment from {t['name']}"
    elif t["typ"] == "standing": ds = f"To {t['name'].upper()}"
    else: ds = t["name"]
    st = f"{iso(t['date'])} {9 + t['id'] % 10:02d}:{t['id'] % 60:02d}:{(t['id'] * 7) % 60:02d}"
    co = "" if t["pending"] else f"{iso(t['book'])} {10 + t['id'] % 10:02d}:{(t['id'] * 3) % 60:02d}:{(t['id'] * 11) % 60:02d}"
    L.append(",".join([typ, "Current", st, co, ds, en(t["amount"]), "0.00", "EUR", "PENDING" if t["pending"] else "COMPLETED", "" if t["pending"] else en(t["bal"])]))
write("de_revolut.csv", L)

# ---------- Vivid ----------
L = ["Completed date,Counterparty name,Reference,Payment amount,Payment currency"]
for t in BOOKED:
    nm = {"netflix": "Netflix", "atm": "ATM Sparkasse Konstanz"}.get(t["kind"], t["name"])
    ref = t["purpose"] if not t["card"] else ""
    if "," in ref: ref = q(ref)
    L.append(",".join([d8(t["book"]), q(nm) if "," in nm else nm, ref, en(t["amount"]), "EUR"]))
write("de_vivid.csv", L)

# ---------- Tomorrow ----------
TM = dict(standing="Standing Order", debit="Direct Debit", card="Card Transaction", atm="ATM Withdrawal", credit="Incoming Transfer")
L = ["account_type,booking_date,valuta_date,sender_or_recipient,iban,booking_type,description,category,amount,currency"]
for t in BOOKED:
    nm = {"netflix": "NETFLIX.COM", "atm": "Sparkasse Konstanz"}.get(t["kind"], t["name"])
    cat = {"grocery": "Groceries", "atm": "Cash", "sal": "Income", "rent": "Housing", "netflix": "Entertainment"}.get(t["kind"], "Other")
    L.append(",".join([q("Personal Account"), q(iso(t["book"])), q(iso(t["date"])), q(nm), q(t["iban"]), q(TM[t["typ"]]),
                       q("" if t["card"] else t["purpose"]), q(cat), q(de(t["amount"], thousands=False)), q("EUR")]))
write("de_tomorrow.csv", L)

# ---------- bunq ----------
L = [",".join(q(h) for h in ["Date","Amount","Account","Counterparty","Name","Description"])]
for t in BOOKED:
    nm = {"netflix": "NETFLIX.COM", "atm": "Sparkasse Konstanz"}.get(t["kind"], t["name"])
    dsc = f"{nm} Konstanz, DE" if t["card"] else t["purpose"]
    L.append(",".join(q(v) for v in [iso(t["book"]), de(t["amount"], thousands=False), "DE00100000000098765432", t["iban"], nm, dsc]))
write("de_bunq.csv", L)

# ---------- Wise ----------
H = ["TransferWise ID","Date","Amount","Currency","Description","Payment Reference","Running Balance","Exchange From","Exchange To","Exchange Rate","Payer Name","Payee Name","Payee Account Number","Merchant","Card Last Four Digits","Card Holder Full Name","Attachment","Note","Total fees"]
L = [",".join(H)]
for t in desc(BOOKED):
    if t["card"]:
        mer = {"netflix": "Netflix.com", "atm": "Sparkasse Konstanz"}.get(t["kind"], t["name"])
        dsc = (f"Cash withdrawal of {abs(t['amount']):.2f} EUR issued by {mer} Konstanz" if t["kind"] == "atm"
               else f"Card transaction of {abs(t['amount']):.2f} EUR issued by {mer} {t['city'].upper()}")
        row = [f"CARD-{2100000000 + t['id']}", t["date"].strftime("%d-%m-%Y"), en(t["amount"]), "EUR", dsc, "", en(t["bal"]), "", "", "", "", "", "", mer, "1234", OWN_NAME, "", "", "0.00"]
    elif t["amount"] > 0:
        row = [f"TRANSFER-{1500000000 + t['id']}", t["date"].strftime("%d-%m-%Y"), en(t["amount"]), "EUR", f"Received money from {t['name']} with reference {t['purpose']}", t["purpose"], en(t["bal"]), "", "", "", t["name"], "", "", "", "", "", "", "", "0.00"]
    else:
        row = [f"TRANSFER-{1500000000 + t['id']}", t["date"].strftime("%d-%m-%Y"), en(t["amount"]), "EUR",
               (f"Direct debit payment to {t['name']}" if t["typ"] == "debit" else f"Sent money to {t['name']}"), t["purpose"], en(t["bal"]), "", "", "", "", t["name"], t["iban"], "", "", "", "", "", "0.00"]
    L.append(",".join(q(v) if ("," in v or " " in v) else v for v in row))
write("de_wise.csv", L)

# ---------- Credit cards: Barclays, Amex ----------
L = ["Barclays Kreditkarte", "", f"Kartennummer;4567 XXXX XXXX 1234", f"Karteninhaber;{OWN_NAME}", "", "Umsätze", "Zeitraum;01.10.2025 - 30.09.2026",
     f"Saldo;{de(sum(r['amount'] for r in CC if not r['pending']))} €", "", "", "", "",
     "Referenznummer;Buchungsdatum;Buchungsdatum;Betrag;Beschreibung;Typ;Status;Kartennummer;Originalbetrag;Mögliche Zahlpläne;Land;Name des Karteninhabers;Kartennetzwerk;Kontaktlose Bezahlung;Händlerdetails"]
for r in sorted(CC, key=lambda t: (t["book"], t["id"]), reverse=True):
    nm = {"settle": "Gutschrift Lastschrift", "netflix": "NETFLIX.COM", "spotify": "Spotify", "atm": "Bargeldauszahlung Sparkasse Konstanz"}.get(r["kind"], r["name"])
    typ = "Gutschrift" if r["amount"] > 0 else ("Bargeldauszahlung" if r["kind"] == "atm" else "Belastung")
    L.append(";".join([f"0{7400000000 + r['id']}", d8(r["date"]), "" if r["pending"] else d8(r["book"]), de(r["amount"]) + " €", nm, typ,
                       "Vorgemerkt" if r["pending"] else "Abgerechnet", "4567 XXXX XXXX 1234" if r["kind"] != "settle" else "",
                       de(r["amount"]) + " €" if r["kind"] != "settle" else "", "", "US" if r["kind"] == "netflix" else ("SE" if r["kind"] == "spotify" else "DE"),
                       OWN_NAME, "Visa", "Ja" if r["kind"] == "grocery" else "Nein", f"{nm} {r.get('city', '')}".strip()]))
write("de_barclays.csv", L, enc="utf-8")

L = ["Datum,Beschreibung,Betrag,Erweiterte Details,Erscheint auf Ihrer Abrechnung als,Adresse,Stadt,PLZ,Land,Betreff"]
for r in sorted([r for r in CC if not r["pending"]], key=lambda t: (t["book"], t["id"]), reverse=True):
    if r["kind"] == "settle": nm, stmt, city, cc = "ZAHLUNG ERHALTEN. BESTEN DANK.", "ZAHLUNG ERHALTEN. BESTEN DANK.", "", ""
    elif r["kind"] == "netflix": nm, stmt, city, cc = "NETFLIX.COM LOS GATOS", "NETFLIX.COM", "LOS GATOS", "USA"
    elif r["kind"] == "spotify": nm, stmt, city, cc = "SPOTIFY STOCKHOLM", "SPOTIFY", "STOCKHOLM", "SCHWEDEN"
    elif r["kind"] == "atm": nm, stmt, city, cc = "BARGELD SPARKASSE KONSTANZ", "BARGELD", "KONSTANZ", "DEUTSCHLAND"
    else: nm, stmt, city, cc = f"{r['name'].upper()} KONSTANZ", r["name"].upper(), "KONSTANZ", "DEUTSCHLAND"
    amt = de(-r["amount"], thousands=False)  # Amex: charges positive, payments negative
    L.append(",".join([r["date"].strftime("%d/%m/%Y"), q(nm), q(amt), q(""), q(stmt), q(""), q(city), q("78462" if city == "KONSTANZ" else ""), q(cc), q(f"'AT{2600000000 + r['id']}'")]))
write("de_amex.csv", L)

# ---------- Consorsbank / HVB (unverified) ----------
CS = dict(standing="Dauerauftrag", debit="Lastschrift", card="Kartenzahlung", atm="Barauszahlung", credit="Gutschrift")
L = ["Buchung;Valuta;Sender / Empfänger;IBAN / Konto-Nr.;BIC / BLZ;Buchungstext;Verwendungszweck;Betrag in EUR"]
for t in desc(BOOKED):
    L.append(";".join([d8(t["book"]), d8(t["date"]), t["name"], t["iban"], t["bic"], CS[t["typ"]], t["purpose"], de(t["amount"])]))
write("de_consorsbank.csv", L, enc="cp1252")
L = ["Kontonummer;Buchungsdatum;Valuta;Empfänger 1;Empfänger 2;Verwendungszweck;Betrag;Währung"]
for t in desc(BOOKED):
    L.append(";".join(q(v) for v in ["1234567890", d8(t["book"]), d8(t["date"]), t["name"], "", f"{CS[t['typ']]} {t['purpose']}", de(t["amount"]), "EUR"]))
write("de_hvb.csv", L, enc="cp1252")

print("closing balance", CLOSE_BAL, "rows", len(T))
