"""Erfundene, erweiterte Kontoauszüge (UBS-Konto + Swisscard) für Max Muster, 15.09.2025–27.10.2026.
Formate wie die Originale; alle Namen von Personen, IBAN, Telefonnummern und Kartennummern sind erfunden."""
import random, calendar
from datetime import date, timedelta
R = random.Random(42)
START, END = date(2025, 9, 15), date(2026, 10, 27)
def months(a=START, b=END):
    y, m = a.year, a.month
    while (y, m) <= (b.year, b.month):
        yield y, m
        m += 1
        if m > 12: y, m = y + 1, 1
def d(y, m, dd): return date(y, m, min(dd, calendar.monthrange(y, m)[1]))
def wd(x):  # Wochenende → nächster Montag (Buchung)
    while x.weekday() >= 5: x += timedelta(days=1)
    return x
def ok(x): return START <= x <= END
def trx(): return "".join(R.choice("0123456789ABCDEFGHJKLMNPQRSTUVWXYZ") for _ in range(16))

# ---------------- UBS ----------------
U = []   # (date, amount (+/-), b1, b2, b3)
def u(x, a, b1, b2, b3=""):
    if ok(x): U.append((x, round(a, 2), b1, b2, b3))
ADR = {"lohn": "Muster Engineering AG;Technoparkstrasse 2; 8406 Winterthur; CH"}
# Einnahmen
for y, m in months():
    lohn = 8450.0 if (y, m) < (2026, 4) else 8700.0
    x = wd(d(y, m, 25))
    u(x, lohn, ADR["lohn"], "Gutschrift", "Zahlungsgrund: Lohn %02d/%d; Kosten: Zahlungseingang SIC; Transaktions-Nr. %s" % (m, y, trx()))
    if m == 11: u(x, lohn, ADR["lohn"], "Gutschrift", "Zahlungsgrund: 13. Monatslohn %d; Transaktions-Nr. %s" % (y, trx()))
    u(wd(d(y, m, 10)), 215.0, "SVA Zuerich Familienausgleichskasse;Roentgenstrasse 17; 8005 Zuerich; CH", "Gutschrift", "Zahlungsgrund: Kinderzulage Muster Lena %02d/%d; Transaktions-Nr. %s" % (m, y, trx()))
u(date(2026, 3, 25), 4200.0, ADR["lohn"], "Gutschrift", "Zahlungsgrund: Bonus 2025; Transaktions-Nr. %s" % trx())
for x in [date(2025, 10, 14), date(2026, 1, 20), date(2026, 5, 12), date(2026, 8, 18)]:
    u(x, round(R.uniform(45, 260), 2), ADR["lohn"], "Gutschrift", "Zahlungsgrund: Spesenabrechnung; Transaktions-Nr. %s" % trx())
u(date(2026, 6, 15), 312.40, "Muster Immobilien AG;Stadthausstrasse 4; 8400 Winterthur; CH", "Gutschrift", "Zahlungsgrund: Nebenkostenabrechnung 2025 Guthaben; Transaktions-Nr. %s" % trx())
u(date(2026, 9, 2), 1180.0, "Steueramt der Stadt Winterthur;Pionierstrasse 7; 8403 Winterthur; CH", "Gutschrift", "Zahlungsgrund: Rueckzahlung Staats- und Gemeindesteuern 2025; Transaktions-Nr. %s" % trx())
for x in [date(2025, 11, 4), date(2026, 2, 17), date(2026, 7, 9), date(2026, 10, 19)]:
    u(x, round(R.uniform(80, 420), 2), "CSS Kranken-Versicherung AG;Tribschenstrasse 21; 6005 Luzern; CH", "Gutschrift", "Zahlungsgrund: Leistungsabrechnung Beleg-Nr. %d zu Gunsten Muster Max; Transaktions-Nr. %s" % (R.randint(10**9, 10**10), trx()))
u(date(2026, 4, 30), 150.0, "Muster Anna;Haldenstrasse 9; 8400 Winterthur; CH", "Gutschrift", "Zahlungsgrund: Anteil Ferienhaus; Transaktions-Nr. %s" % trx())
# Fixkosten (Dauerauftrag / LSV / eBill)
for y, m in months():
    u(wd(d(y, m, 28)) - timedelta(days=3), -2150.0, "Muster Immobilien AG;Stadthausstrasse 4; 8400 Winterthur; CH", "Dauerauftrag", "Zahlungsgrund: Miete Wohnung 3.5 Zi inkl. NK-Akonto; Transaktions-Nr. %s" % trx())
    kk = 812.40 if y == 2025 else 845.10
    u(wd(d(y, m, 1)), -kk, "CSS Kranken-Versicherung AG;Tribschenstrasse 21; 6005 Luzern; CH", "Lastschriftverfahren", "Zahlungsgrund: Praemie %02d/%d Familie Muster; Transaktions-Nr. %s" % (m, y, trx()))
    u(wd(d(y, m, 3)), -59.90, "Sunrise GmbH;Postfach; 8050 Zuerich; CH", "eBill", "Zahlungsgrund: Rechnung Internet & TV; Transaktions-Nr. %s" % trx())
    u(wd(d(y, m, 6)), -(29.95 if (y, m) >= (2026, 2) else 34.95), "Salt Mobile SA;Rue du Caudray 4; 1020 Renens; CH", "Lastschriftverfahren", "Zahlungsgrund: Abo Salt Mobile; Transaktions-Nr. %s" % trx())
    u(wd(d(y, m, 15)), -389.0, "AMAG Leasing AG;Aarauerstrasse 20; 5116 Schinznach-Bad; CH", "Lastschriftverfahren", "Zahlungsgrund: Leasingrate Vertrag 4471-22; Transaktions-Nr. %s" % trx())
    u(wd(d(y, m, 2)), -89.0, "Genossenschaft Migros Zuerich Fitnesspark;Pfingstweidstrasse 101; 8005 Zuerich; CH", "Lastschriftverfahren", "Zahlungsgrund: Mitgliedschaft Fitnesspark; Transaktions-Nr. %s" % trx())
    u(wd(d(y, m, 5)), -1260.0, "Kita Sonnenschein GmbH;Wartstrasse 31; 8400 Winterthur; CH", "Dauerauftrag", "Zahlungsgrund: Betreuung Lena Muster; Transaktions-Nr. %s" % trx())
    u(wd(d(y, m, 27)), -500.0, "VIAC Vorsorgestiftung 3a;Postfach; 8022 Zuerich; CH", "Dauerauftrag", "Zahlungsgrund: Einzahlung Saeule 3a; Transaktions-Nr. %s" % trx())
    u(wd(d(y, m, 26)), -300.0, "Max Muster;Sparkonto UBS", "Dauerauftrag", "Zahlungsgrund: Sparen; Transaktions-Nr. %s" % trx())
    # Steuerraten Feb–Nov
    if 2 <= m <= 11 and y == 2026:
        u(wd(d(y, m, 20)), -900.0, "Steueramt der Stadt Winterthur;Pionierstrasse 7; 8403 Winterthur; CH", "Dauerauftrag", "Zahlungsgrund: Staats- und Gemeindesteuern 2026 Rate; Transaktions-Nr. %s" % trx())
    if 2 <= m <= 11 and y == 2025:
        u(wd(d(y, m, 20)), -850.0, "Steueramt der Stadt Winterthur;Pionierstrasse 7; 8403 Winterthur; CH", "Dauerauftrag", "Zahlungsgrund: Staats- und Gemeindesteuern 2025 Rate; Transaktions-Nr. %s" % trx())
    # Kreditkartenrechnung (Saldo der Swisscard) – kein Vertrag
    u(wd(d(y, m, 18)), -round(R.uniform(650, 1900), 2), "Swisscard AECS GmbH;Neugasse 18; 8810 Horgen; CH", "Lastschriftverfahren", "Zahlungsgrund: Kreditkartenabrechnung; Transaktions-Nr. %s" % trx())
# Strom quartalsweise
for y, m, a in [(2025, 10, 214.35), (2026, 1, 268.90), (2026, 4, 241.10), (2026, 7, 172.55), (2026, 10, 205.80)]:
    u(wd(d(y, m, 22)), -a, "Stadtwerk Winterthur;Untere Schoeneggstrasse 65; 8403 Winterthur; CH", "eBill", "Zahlungsgrund: Rechnung Strom Kunden-Nr. 77120; Transaktions-Nr. %s" % trx())
# Jahresrechnungen
u(date(2026, 1, 12), -1184.50, "AXA Versicherungen AG;General-Guisan-Strasse 40; 8400 Winterthur; CH", "e-banking-Vergütungsauftrag", "Referenz-Nr. QRR: 21 00000 00003 13947 14300 09017; Zahlungsgrund: Motorfahrzeugversicherung Police 17.442.118; Transaktions-Nr. %s" % trx())
u(date(2026, 1, 28), -412.0, "Strassenverkehrsamt des Kantons Zuerich;Uetlibergstrasse 301; 8045 Zuerich; CH", "e-banking-Vergütungsauftrag", "Zahlungsgrund: Verkehrsabgaben 2026 ZH 512 334; Transaktions-Nr. %s" % trx())
u(date(2026, 2, 24), -486.30, "Schweizerische Mobiliar Versicherungsgesellschaft AG;Bundesgasse 35; 3001 Bern; CH", "e-banking-Vergütungsauftrag", "Zahlungsgrund: Hausrat- und Privathaftpflicht Police 3.218.774; Transaktions-Nr. %s" % trx())
u(date(2025, 9, 29), -312.0, "Protekta Rechtsschutz-Versicherung AG;Monbijoustrasse 5; 3011 Bern; CH", "e-banking-Vergütungsauftrag", "Zahlungsgrund: Rechtsschutz Privat und Verkehr; Transaktions-Nr. %s" % trx())
u(date(2026, 9, 28), -318.0, "Protekta Rechtsschutz-Versicherung AG;Monbijoustrasse 5; 3011 Bern; CH", "e-banking-Vergütungsauftrag", "Zahlungsgrund: Rechtsschutz Privat und Verkehr; Transaktions-Nr. %s" % trx())
u(date(2026, 4, 14), -335.0, "SERAFE AG;Summelenweg 91; 8808 Pfaeffikon SZ; CH", "e-banking-Vergütungsauftrag", "Zahlungsgrund: Abgabeperiode 01.04.2026 - 31.03.2027; Transaktions-Nr. %s" % trx())
u(date(2026, 4, 2), -160.0, "Stadtpolizei Winterthur Hundekontrolle;Obertor 17; 8400 Winterthur; CH", "e-banking-Vergütungsauftrag", "Zahlungsgrund: Hundetaxe 2026; Transaktions-Nr. %s" % trx())
u(date(2026, 3, 9), -1240.0, "Kantonales Steueramt Zuerich;Baenderstrasse 9; 8090 Zuerich; CH", "e-banking-Vergütungsauftrag", "Zahlungsgrund: Direkte Bundessteuer 2025; Transaktions-Nr. %s" % trx())
u(date(2025, 9, 22), -280.0, "FC Winterthur Junioren;Postfach; 8401 Winterthur; CH", "e-banking-Vergütungsauftrag", "Zahlungsgrund: Mitgliederbeitrag 2025/26 Noah Muster; Transaktions-Nr. %s" % trx())
u(date(2026, 8, 31), -290.0, "FC Winterthur Junioren;Postfach; 8401 Winterthur; CH", "e-banking-Vergütungsauftrag", "Zahlungsgrund: Mitgliederbeitrag 2026/27 Noah Muster; Transaktions-Nr. %s" % trx())
for x in [date(2025, 9, 30), date(2026, 2, 26), date(2026, 8, 27)]:
    u(x, -640.0, "Musikschule Konservatorium Winterthur;Tössertobelstrasse 1; 8400 Winterthur; CH", "e-banking-Vergütungsauftrag", "Zahlungsgrund: Schulgeld Semester Klavier Lena Muster; Transaktions-Nr. %s" % trx())
# Einmalige Rechnungen
for x, a, n, z in [(date(2025, 11, 20), -184.60, "Zahnarztpraxis Dr. Muster;Marktgasse 12; 8400 Winterthur; CH", "Dentalhygiene"),
                   (date(2026, 5, 19), -184.60, "Zahnarztpraxis Dr. Muster;Marktgasse 12; 8400 Winterthur; CH", "Dentalhygiene"),
                   (date(2026, 10, 19), -600.0, "Muster Optik GmbH;Bahnhofplatz 3; 8400 Winterthur; CH", "Brille"),
                   (date(2026, 3, 30), -1450.0, "Malergeschaeft Pinsel AG;Industriestrasse 4; 8404 Winterthur; CH", "Rechnung 2026-118"),
                   (date(2026, 6, 8), -86.0, "Stadtpolizei Winterthur;Obertor 17; 8400 Winterthur; CH", "Ordnungsbusse 26-4471"),
                   (date(2026, 1, 7), -228.35, "CSS Kranken-Versicherung AG;Tribschenstrasse 21; 6005 Luzern; CH", "Kostenbeteiligung Rechnung 2615235386"),
                   (date(2026, 7, 21), -96.10, "CSS Kranken-Versicherung AG;Tribschenstrasse 21; 6005 Luzern; CH", "Kostenbeteiligung Rechnung 2615871102")]:
    u(x, a, n, "e-banking-Vergütungsauftrag", "Zahlungsgrund: %s; Transaktions-Nr. %s" % (z, trx()))
# Twint, Bancomat, Kleinkram
TW = [("SBB MOBILE", 3, 24), ("PARKINGPAY APP", 2, 18), ("COOP PRONTO", 6, 45), ("MIGROS", 8, 90), ("PARCANDI AG", 4, 15), ("Muster Anna", 20, 80), ("BAECKEREI KUHN", 4, 16)]
x = START
while x <= END:
    if R.random() < 0.55:
        nm, lo, hi = R.choice(TW); a = round(R.uniform(lo, hi), 2)
        if nm == "Muster Anna": u(x, -a, "Muster Anna; Zahlung UBS TWINT", "", "Zahlungsgrund: Geld senden; TWINT-Acc.:+41790000000; Transaktions-Nr. %s" % trx())
        else: u(x, -a, "%s; Zahlung UBS TWINT" % nm, "", "Zahlungsgrund: - na; TWINT-Acc.:+41790000000; Transaktions-Nr. %s" % trx())
    if R.random() < 0.05: u(x, -R.choice([100, 200, 300]), "Bancomat UBS Winterthur Bahnhof", "Bargeldbezug", "Transaktions-Nr. %s" % trx())
    x += timedelta(days=1)
# Ausland (EUR)
u(date(2026, 7, 14), -33.19, "A1 HRVATSKA D.O.O.;VRTNI PUT 1; 10000 ZAGREB; HR", "e-banking-Vergütungsauftrag", "Zahlungsgrund: 260009108547-A-1; Vergueteter Betrag: -35.27 EUR; Devisenkurs: 0.941153; Kosten: E-Banking SEPA; Transaktions-Nr. %s" % trx())

U.sort(key=lambda r: r[0])
bal, rows = 6400.0, []
for x, a, b1, b2, b3 in U:
    bal = round(bal + a, 2)
    rows.append((x, a, b1, b2, b3, bal))
rows.reverse()
L = ["Kontonummer:;0230 00123456.01K;;;;;;;;;;;;", "IBAN:;CH00 0023 0230 0012 3456 0;;;;;;;;;;;;", "Von:;15.09.2025;;;;;;;;;;;;", "Bis:;27.10.2026;;;;;;;;;;;;",
     "Anfangssaldo:;6400;;;;;;;;;;;;", "Schlusssaldo:;%s;;;;;;;;;;;;" % rows[0][5], "Bewertet in:;CHF;;;;;;;;;;;;", "Anzahl Transaktionen in diesem Zeitraum:;%d;;;;;;;;;;;;" % len(rows), ";;;;;;;;;;;;;",
     "Abschlussdatum;Abschlusszeit;Buchungsdatum;Valutadatum;Währung;Belastung;Gutschrift;Einzelbetrag;Saldo;Transaktions-Nr.;Beschreibung1;Beschreibung2;Beschreibung3;Fussnoten"]
fmt = lambda v: ("%.2f" % v).rstrip("0").rstrip(".")
for x, a, b1, b2, b3, bal in rows:
    ds = x.strftime("%d.%m.%Y"); bk = wd(x).strftime("%d.%m.%Y")
    L.append(";".join([ds, "", bk, ds, "CHF", fmt(a) if a < 0 else "", fmt(a) if a > 0 else "", "", fmt(bal), trx(), '"%s"' % b1, b2, '"%s"' % b3 if b3 else "", ""]))
open("UBS_erweitert.csv", "w", encoding="utf-8-sig").write("\n".join(L) + "\n")

# ---------------- Swisscard ----------------
S = []  # (date, beschreibung, haendler, karte, betrag CHF, fw, fwbetrag, art, status, kat, mcc)
K1, K2 = "4731 04** **** 3003", "3776 62**** *3744"
def s(x, b, h, a, kat, mcc, karte=K1, fw="", fwa="", art="Belastung"):
    if ok(x): S.append((x, b, h, karte, round(a, 2), fw, fwa, art, "Gebucht", kat, mcc))
for y, m in months():
    s(d(y, m, 12), "NETFLIX.COM, LOS GATOS", "Netflix", 20.90, "Unterhaltung", "CABLE AND OTHER PAY TELEVISION SERVICES")
    s(d(y, m, 3), "SPOTIFY P2F1C9A7B3, STOCKHOLM", "Spotify", 25.95 if (y, m) >= (2026, 5) else 22.95, "Unterhaltung", "DIGITAL GOODS MEDIA")
    e = 9.99; r = R.uniform(0.93, 0.97)
    s(d(y, m, 22), "KINDLE SVCS*%s, 4.4-2012E+11" % "".join(R.choice("ABCDEFGHJK0123456789") for _ in range(9)), "Amazon Kindle", e * r, "Shopping", "RECORD STORES", K2, "EUR", "%.2f" % e)
    s(d(y, m, 17), "APPLE.COM/BILL, ITUNES.COM", "Apple", 3.00, "Unterhaltung", "DIGITAL GOODS GAMES", K2)
    if R.random() < 0.3: s(d(y, m, R.randint(1, 28)), "APPLE.COM/BILL, ITUNES.COM", "Apple", R.choice([1.0, 4.0, 6.0, 12.0]), "Unterhaltung", "DIGITAL GOODS GAMES", K2)
    s(d(y, m, 7), "GOOGLE *YouTubePremium, G.CO/HELPPAY#", "YouTube Premium", 15.90, "Unterhaltung", "DIGITAL GOODS MEDIA")
    if (2026, 3) <= (y, m) <= (2026, 8): s(d(y, m, 9), "DISNEYPLUS, AMSTERDAM", "Disney+", 15.90, "Unterhaltung", "CABLE AND OTHER PAY TELEVISION SERVICES")
s(date(2026, 1, 5), "MICROSOFT*365 FAMILY, MSBILL.INFO", "Microsoft", 99.00, "Shopping", "COMPUTER SOFTWARE STORES")
s(date(2026, 3, 18), "AMAZON PRIME*2K4LP90, AMAZON.DE", "Amazon Prime", 89.90 * 0.945, "Shopping", "DIRECT MARKETING", K2, "EUR", "89.90")
s(date(2025, 11, 2), "DUOLINGO, PITTSBURGH", "Duolingo", 89.00, "Bildung", "DIGITAL GOODS APPLICATIONS")
s(date(2026, 10, 20), "DUOLINGO, PITTSBURGH", "Duolingo", 89.00, "Bildung", "DIGITAL GOODS APPLICATIONS")
s(date(2026, 6, 1), "SBB CFF FFS HALBTAX, BERN", "SBB Halbtax", 190.00, "Reisen", "PASSENGER RAILWAYS")
SH = [("MIGROS %s, WINTERTHUR", "Migros", 8, 140, "Lebensmittel", "GROCERY STORES, SUPERMARKETS"), ("COOP-%d WINTERTHUR, WINTERTHUR", "Coop", 6, 120, "Lebensmittel", "GROCERY STORES, SUPERMARKETS"),
      ("LIDL FIL. 255, WINTERTHUR", "Lidl", 20, 160, "Lebensmittel", "GROCERY STORES, SUPERMARKETS"), ("DIGITEC GALAXUS AG, ZUERICH", "Digitec Galaxus", 15, 420, "Shopping", "ELECTRONICS STORES"),
      ("ZALANDO SE, BERLIN", "Zalando", 30, 180, "Shopping", "FAMILY CLOTHING STORES"), ("SHELL WINTERTHUR, WINTERTHUR", "Shell", 40, 95, "Mobilität", "SERVICE STATIONS"),
      ("RESTAURANT OBERTOR, WINTERTHUR", "Restaurant Obertor", 25, 160, "Gastronomie", "EATING PLACES, RESTAURANTS"), ("FELFEL AG, ZUERICH", "FELFEL", 8, 16, "Gastronomie", "CATERERS"),
      ("TENNIS UND SQUASH CENTER, WINTERTHUR", "Tennis und Squash Center Auwiesen", 25, 25, "Unterhaltung", "AMUSEMENT AND RECREATION SERVICES"), ("IKEA AG, DIETLIKON", "IKEA", 20, 380, "Familie & Haushalt", "HOME FURNISHING STORES"),
      ("APOTHEKE ZUR ROSE, WINTERTHUR", "Apotheke", 9, 70, "Gesundheit", "DRUG STORES AND PHARMACIES")]
x = START
while x <= END:
    for _ in range(R.choice([0, 1, 1, 2, 3])):
        b, h, lo, hi, kat, mcc = R.choice(SH)
        bb = b % R.randint(1000, 9999) if "%d" in b else (b % R.choice(["DEUTWEG", "NEUWIESEN", "ROSENBERG"]) if "%s" in b else b)
        s(x, bb, h, R.uniform(lo, hi), kat, mcc, R.choice([K1, K2]))
    x += timedelta(days=1)
# Ferien im Ausland (EUR)
for x, b, h, e, kat, mcc in [(date(2026, 7, 11), "PIZZERIA-FOCULUS, LJUBLJANA", "Pizzeria FoculuS", 147.90, "Gastronomie", "EATING PLACES, RESTAURANTS"),
                             (date(2026, 7, 12), "SUMUP*LOCANDA AL SOLE SRL, CASTELLO DI G", "SUMUP*LOCANDA AL SOLE SRL", 210.50, "Reisen", "LODGING NOT SPECIFIED"),
                             (date(2026, 7, 9), "BOOKING.COM, AMSTERDAM", "Booking.com", 684.00, "Reisen", "TRAVEL AGENCIES"),
                             (date(2026, 7, 8), "EASYJET, LUTON", "easyJet", 312.40, "Reisen", "AIRLINES")]:
    s(x, b, h, e * R.uniform(0.94, 0.96), kat, mcc, K1, "EUR", "%.2f" % e)
s(date(2026, 3, 2), "ZALANDO SE, BERLIN", "Zalando", 79.95, "Shopping", "FAMILY CLOTHING STORES", K1, art="Gutschrift")
s(date(2026, 4, 21), "KLEINTIERPRAXIS ACR, WINTERTHUR", "Kleintierpraxis ACR", 255.70, "Familie & Haushalt", "VETERINARY SERVICES")
S.sort(key=lambda r: r[0], reverse=True)
H = "Transaktionsdatum,Beschreibung,Händler,Kartennummer,Währung,Betrag,Fremdwährung,Betrag in Fremdwährung,Debit/Kredit,Status,Händlerkategorie,Registrierte Kategorie"
out = [H]
for x, b, h, k, a, fw, fwa, art, st, kat, mcc in S:
    if x >= END - timedelta(days=1): st = "Ausstehend"
    f = [x.strftime("%d.%m.%Y"), b, h, k, "CHF", "%.2f" % a, fw, fwa, art, st, kat, mcc]
    out.append('"' + ",".join(f[0:1] + ['""%s""' % v for v in f[1:]]) + '"')
open("Swisscard_erweitert.csv", "w", encoding="utf-8").write("\n".join(out) + "\n")
print(len(rows), "UBS-Buchungen,", len(S), "Swisscard-Buchungen")
