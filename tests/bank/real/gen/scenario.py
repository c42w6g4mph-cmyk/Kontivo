"""Shared fictional scenario (Oct 2025 - Sep 2026) for Swiss bank fixtures.
All names, IBANs, references are invented."""
import datetime as dt
import random
from decimal import Decimal as D

START = dt.date(2025, 10, 1)
END = dt.date(2026, 9, 30)
OPENING = D("8420.35")          # balance on 30.09.2025
HOLDER = "Max Muster"
HOLDER_ADDR = "Seestrasse 12, 8280 Kreuzlingen"

def qr_check(ref26: str) -> str:
    table = [0, 9, 4, 6, 8, 2, 7, 1, 3, 5]
    carry = 0
    for ch in ref26:
        carry = table[(carry + int(ch)) % 10]
    return str((10 - carry) % 10)

def qrr(seed: str) -> str:
    base = ("21" + seed.zfill(24))[:26]
    return base + qr_check(base)

def qrr_fmt(r: str) -> str:   # "21 00000 00000 ..." grouping as printed on QR bills
    return r[:2] + " " + " ".join(r[2 + i:2 + i + 5] for i in range(0, 25, 5))

def next_bday(d):
    d = d + dt.timedelta(days=1)
    while d.weekday() >= 5:
        d += dt.timedelta(days=1)
    return d

class Tx:
    def __init__(self, date, amount, kind, party, msg="", ref="", city="", iban="", time="12:00:00"):
        self.date = date                  # transaction / execution date
        self.amount = D(amount)           # signed, account holder view
        self.kind = kind
        self.party = party
        self.msg = msg
        self.ref = ref                    # QR reference (27 digits) if any
        self.city = city
        self.iban = iban
        self.time = time
        self.subs = []                    # (party, amount, msg, ref, iban) for batch bookings
        if kind in ("card", "atm", "twint"):
            self.book = next_bday(date)
        else:
            self.book = date
        self.id = ""

PARTIES = {
    "rent":   ("Immo Seeblick AG", "Hafenstrasse 3, 8280 Kreuzlingen", "CH00 0078 4000 1111 2222 3"),
    "css":    ("CSS Kranken-Versicherung AG", "Tribschenstrasse 21, 6005 Luzern", "CH00 0900 0000 6000 1234 5"),
    "scom":   ("Swisscom (Schweiz) AG", "3050 Bern", "CH00 3000 0001 3001 2345 6"),
    "energ":  ("Energie Kreuzlingen", "Hauptstrasse 7, 8280 Kreuzlingen", "CH00 3078 4000 5555 6666 7"),
    "serafe": ("SERAFE AG", "Postfach, 8010 Zürich", "CH00 3000 0001 8500 9999 0"),
    "salary": ("Muster Pharma AG", "Industriestrasse 50, 8590 Romanshorn", "CH00 0483 5099 8877 6655 4"),
    "twint":  ("Laura Beispiel", "", "+41 79 000 00 12"),
}
OWN_IBAN = "CH00 0000 0000 0000 0000 0"

def build(with_batch=True):
    rnd = random.Random(20251001)
    txs = []
    m = dt.date(2025, 10, 1)
    k = 0
    while m <= END:
        y, mo = m.year, m.month
        txs.append(Tx(dt.date(y, mo, 1), "-1850.00", "standing", "rent", "Miete Wohnung 3.OG"))
        css = "-389.60" if (y, mo) <= (2025, 12) else "-412.30"
        txs.append(Tx(dt.date(y, mo, 1), css, "lsv", "css", "Prämie %02d.%d Police 4711.0815" % (mo, y)))
        if mo in (10, 1, 4, 7):
            txs.append(Tx(dt.date(y, mo, 20), "-180.50", "ebill_qr", "energ", "Strom Quartal",
                          ref=qrr("%04d%02d%010d" % (y, mo, 4711))))
        txs.append(Tx(dt.date(y, mo, 20), "-79.00", "ebill", "scom", "Rechnung %02d.%d" % (mo, y),
                      ref=qrr("%04d%02d%010d" % (y, mo, 900123))))
        txs.append(Tx(dt.date(y, mo, 12), "-18.90", "card", "NETFLIX.COM", city="Amsterdam", time="03:14:07"))
        txs.append(Tx(dt.date(y, mo, 25), "6850.00", "salary", "salary", "Lohn %02d.%d" % (mo, y)))
        if (y, mo) == (2026, 1):
            txs.append(Tx(dt.date(2026, 1, 31), "-335.00", "ebill_qr", "serafe", "Haushaltabgabe 2026",
                          ref=qrr("2026010000099887")))
        # TWINT to a person, twice a month
        for day in (8, 22):
            amt = D(rnd.choice([15, 20, 25, 30, 35, 40, 50, 60])).quantize(D("0.01"))
            txs.append(Tx(dt.date(y, mo, day), -amt, "twint", "twint",
                          rnd.choice(["Pizza", "Kino", "Geschenk", "Znacht", "Konzert"]),
                          time="%02d:%02d:%02d" % (rnd.randint(17, 22), rnd.randint(0, 59), rnd.randint(0, 59))))
        # ATM 1-2 per month
        txs.append(Tx(dt.date(y, mo, 6), "-200.00", "atm", "Bancomat", city="Kreuzlingen", time="17:42:10"))
        if mo % 2 == 1:
            txs.append(Tx(dt.date(y, mo, 17), "-100.00", "atm", "Bancomat", city="Konstanz Grenze", time="11:05:33"))
        nm = dt.date(y + (mo == 12), mo % 12 + 1, 1)
        m = nm
    # weekly groceries on Saturdays
    d = dt.date(2025, 10, 4)
    i = 0
    while d <= END:
        shop = "MIGROS" if i % 2 == 0 else "COOP"
        amt = D(rnd.randint(2400, 14500)) / 100
        amt = (amt * 20).quantize(D("1")) / 20      # Swiss 5-Rappen rounding
        amt = amt.quantize(D("0.01"))
        name = "Migros Kreuzlingen" if shop == "MIGROS" else "Coop Kreuzlingen Bodensee"
        txs.append(Tx(d, -amt, "card", name, city="Kreuzlingen",
                      time="%02d:%02d:%02d" % (rnd.randint(9, 17), rnd.randint(0, 59), rnd.randint(0, 59))))
        d += dt.timedelta(days=7)
        i += 1
    order = {"standing": 0, "lsv": 1, "salary": 2, "ebill_qr": 3, "ebill": 4, "card": 5, "atm": 6, "twint": 7}
    txs.sort(key=lambda t: (t.book, order[t.kind], t.party))
    if with_batch:
        txs = make_batch(txs)
    for n, t in enumerate(txs):
        t.id = "%07d" % (1000 + n)
    return [t for t in txs if t.book <= END]

def make_batch(txs):
    """20.01.2026: Swisscom + Energie paid as one e-banking collective order (Sammelauftrag)."""
    sel = [t for t in txs if t.date == dt.date(2026, 1, 20) and t.kind in ("ebill", "ebill_qr")]
    if len(sel) != 2:
        return txs
    b = Tx(dt.date(2026, 1, 20), sum(t.amount for t in sel), "batch", "Sammelauftrag", "")
    b.subs = sel
    out = []
    for t in txs:
        if t in sel:
            if t is sel[0]:
                out.append(b)
            continue
        out.append(t)
    return out

def with_balance(txs, opening=OPENING):
    bal = opening
    res = []
    for t in txs:
        bal += t.amount
        res.append((t, bal))
    return res

def party(t):
    return PARTIES.get(t.party, (t.party, "", ""))

def fmt(v, dec=2, thousands="", strip=False, sign=True):
    v = D(v)
    s = f"{abs(v):,.{dec}f}".replace(",", thousands)
    if strip:
        if "." in s:
            s = s.rstrip("0").rstrip(".")
    if sign and v < 0:
        s = "-" + s
    return s

def card_txs():
    """Credit-card scenario: Netflix + weekly groceries + monthly payment of previous period."""
    txs = [t for t in build(with_batch=False) if t.kind == "card"]
    pays = []
    m = dt.date(2025, 11, 1)
    while m <= dt.date(2026, 9, 1):
        prev = dt.date(m.year - (m.month == 1), (m.month - 2) % 12 + 1, 1)
        tot = -sum(t.amount for t in txs if prev <= t.date < m)
        p = Tx(dt.date(m.year, m.month, 24 if m.month != 5 else 26), tot, "cardpay", "IHRE ZAHLUNG")
        p.book = p.date
        pays.append(p)
        m = dt.date(m.year + (m.month == 12), m.month % 12 + 1, 1)
    allt = txs + pays
    allt.sort(key=lambda t: (t.book, t.kind))
    for n, t in enumerate(allt):
        t.id = "%07d" % (5000 + n)
    return allt
