import os, sys, uuid, datetime as dt
from decimal import Decimal as D
from xml.sax.saxutils import escape as x
sys.path.insert(0, os.path.dirname(__file__))
from scenario import *

OUT = "/root/kontivo/tests/bank/real/ch"
TX = build()
OWN = OWN_IBAN.replace(" ", "")

BKTX = {  # ISO 20022 bank transaction codes (Domain/Family/SubFamily)
    "standing": ("PMNT", "ICDT", "STDO"),
    "lsv":      ("PMNT", "IDDT", "PMDD"),
    "ebill":    ("PMNT", "ICDT", "VCOM"),
    "ebill_qr": ("PMNT", "ICDT", "VCOM"),
    "batch":    ("PMNT", "ICDT", "DMCT"),
    "salary":   ("PMNT", "RCDT", "SALA"),
    "card":     ("PMNT", "CCRD", "POSD"),
    "atm":      ("PMNT", "CCRD", "CWDL"),
    "twint":    ("PMNT", "ICDT", "OTHR"),
}

def addr_xml(addr, v):
    if not addr:
        return ""
    street, _, city = addr.partition(", ")
    if not city:
        city, street = street, ""
    pc, _, town = city.partition(" ")
    parts = street.rsplit(" ", 1)
    s = "<PstlAdr>"
    if street and len(parts) == 2 and parts[1].isdigit():
        s += "<StrtNm>%s</StrtNm><BldgNb>%s</BldgNb>" % (x(parts[0]), parts[1])
    elif street:
        s += "<StrtNm>%s</StrtNm>" % x(street)
    s += "<PstCd>%s</PstCd><TwnNm>%s</TwnNm><Ctry>CH</Ctry></PstlAdr>" % (pc, x(town))
    return s

def pty(tag, name, addr, v):
    inner = "<Nm>%s</Nm>%s" % (x(name), addr_xml(addr, v))
    if v == 8:
        return "<%s><Pty>%s</Pty></%s>" % (tag, inner, tag)
    return "<%s>%s</%s>" % (tag, inner, tag)

def bktx(k):
    d, f, s = BKTX[k]
    return "<BkTxCd><Domn><Cd>%s</Cd><Fmly><Cd>%s</Cd><SubFmlyCd>%s</SubFmlyCd></Fmly></Domn></BkTxCd>" % (d, f, s)

def addtl(t):
    n = party(t)[0]
    return {"standing": "Dauerauftrag %s" % n, "lsv": "LSV+ Lastschrift %s" % n, "ebill": "eBill %s" % n, "ebill_qr": "eBill %s" % n,
            "batch": "E-Banking Sammelauftrag", "salary": "Gutschrift %s" % n,
            "card": "Debitkarte %s %s %s" % ("NETFLIX.COM Amsterdam" if t.party == "NETFLIX.COM" else t.party, t.date.strftime("%d.%m.%Y"), t.time[:5]),
            "atm": "Bargeldbezug Debitkarte Bancomat %s %s" % (t.city, t.date.strftime("%d.%m.%Y")),
            "twint": "TWINT Geld senden an %s" % n}[t.kind]

def txdtls(t, v, ind):
    n, addr, iban = party(t)
    s = "<TxDtls><Refs><AcctSvcrRef>%s</AcctSvcrRef>" % ("R" + t.id)
    if t.kind == "lsv":
        s += "<EndToEndId>NOTPROVIDED</EndToEndId>"
        if v == 8:
            s += "<UETR>%s</UETR>" % uuid.UUID(bytes=__import__("hashlib").md5((t.id + "u").encode()).digest(), version=4)
        s += "<MndtId>LSV-CSS-4711</MndtId>"
    else:
        s += "<EndToEndId>%s</EndToEndId>" % ("E2E" + t.id if t.kind not in ("card", "atm") else "NOTPROVIDED")
        if v == 8 and t.kind not in ("card", "atm"):
            s += "<UETR>%s</UETR>" % uuid.UUID(bytes=__import__("hashlib").md5((t.id + "u").encode()).digest(), version=4)
    s += "</Refs>"
    s += '<Amt Ccy="CHF">%s</Amt><CdtDbtInd>%s</CdtDbtInd>' % (fmt(abs(t.amount), sign=False), ind)
    s += bktx(t.kind)
    if t.kind in ("card", "atm"):
        s += "<RltdPties>%s</RltdPties>" % pty("Cdtr", "NETFLIX.COM" if t.party == "NETFLIX.COM" else (t.party if t.kind == "card" else "Bancomat " + t.city), "", v)
        s += "<RmtInf><Ustrd>%s</Ustrd></RmtInf>" % x(addtl(t))
        s += "<RltdDts><AccptncDtTm>%sT%s</AccptncDtTm></RltdDts>" % (t.date.isoformat(), t.time)
    elif t.kind == "salary":
        s += "<RltdPties>%s<DbtrAcct><Id><IBAN>%s</IBAN></Id></DbtrAcct>%s<CdtrAcct><Id><IBAN>%s</IBAN></Id></CdtrAcct></RltdPties>" % (
            pty("Dbtr", n, addr, v), iban.replace(" ", ""), pty("Cdtr", HOLDER, HOLDER_ADDR, v), OWN)
        s += "<RmtInf><Ustrd>%s</Ustrd></RmtInf>" % x(t.msg)
    elif t.kind == "twint":
        s += "<RltdPties>%s</RltdPties>" % pty("Cdtr", n, "", v)
        s += "<RmtInf><Ustrd>TWINT %s</Ustrd></RmtInf>" % x(t.msg)
    else:
        s += "<RltdPties>%s<DbtrAcct><Id><IBAN>%s</IBAN></Id></DbtrAcct>%s<CdtrAcct><Id><IBAN>%s</IBAN></Id></CdtrAcct></RltdPties>" % (
            pty("Dbtr", HOLDER, HOLDER_ADDR, v), OWN, pty("Cdtr", n, addr, v), iban.replace(" ", ""))
        if t.ref:
            s += "<RmtInf><Strd><CdtrRefInf><Tp><CdOrPrtry><Prtry>QRR</Prtry></CdOrPrtry></Tp><Ref>%s</Ref></CdtrRefInf><AddtlRmtInf>%s</AddtlRmtInf></Strd></RmtInf>" % (t.ref, x(t.msg))
        else:
            s += "<RmtInf><Ustrd>%s</Ustrd></RmtInf>" % x(t.msg)
    s += "</TxDtls>"
    return s

def entry(t, v, ntryref=True):
    ind = "CRDT" if t.amount > 0 else "DBIT"
    s = "<Ntry>"
    if ntryref and t.kind == "ebill_qr":
        s += "<NtryRef>%s</NtryRef>" % party(t)[2].replace(" ", "")   # SPS reference version 4: QR-IBAN
    s += '<Amt Ccy="CHF">%s</Amt><CdtDbtInd>%s</CdtDbtInd><RvslInd>false</RvslInd>' % (fmt(abs(t.amount), sign=False), ind)
    s += "<Sts><Cd>BOOK</Cd></Sts>" if v == 8 else "<Sts>BOOK</Sts>"
    s += "<BookgDt><Dt>%s</Dt></BookgDt><ValDt><Dt>%s</Dt></ValDt><AcctSvcrRef>%s</AcctSvcrRef>" % (t.book.isoformat(), t.date.isoformat(), "A" + t.id)
    s += bktx(t.kind)
    s += "<NtryDtls>"
    if t.subs:
        s += '<Btch><NbOfTxs>%d</NbOfTxs><TtlAmt Ccy="CHF">%s</TtlAmt><CdtDbtInd>DBIT</CdtDbtInd></Btch>' % (len(t.subs), fmt(-t.amount, sign=False))
        for st in t.subs:
            st.id = t.id + str(t.subs.index(st))
            s += txdtls(st, v, "DBIT")
    else:
        s += txdtls(t, v, ind)
    s += "</NtryDtls><AddtlNtryInf>%s</AddtlNtryInf></Ntry>" % x(addtl(t))
    return s

def bal(code, amt, d):
    return '<Bal><Tp><CdOrPrtry><Cd>%s</Cd></CdOrPrtry></Tp><Amt Ccy="CHF">%s</Amt><CdtDbtInd>%s</CdtDbtInd><Dt><Dt>%s</Dt></Dt></Bal>' % (
        code, fmt(abs(amt), sign=False), "CRDT" if amt >= 0 else "DBIT", d.isoformat())

from zoneinfo import ZoneInfo
def off(d):
    o = dt.datetime(d.year, d.month, d.day, 12, tzinfo=ZoneInfo("Europe/Zurich")).utcoffset()
    return "+%02d:00" % (o.seconds // 3600)

def months():
    m = dt.date(2025, 10, 1)
    while m <= END:
        nm = dt.date(m.year + (m.month == 12), m.month % 12 + 1, 1)
        yield m, nm - dt.timedelta(days=1)
        m = nm

def acct_xml():
    return "<Acct><Id><IBAN>%s</IBAN></Id><Ccy>CHF</Ccy><Ownr><Nm>%s</Nm></Ownr><Svcr><FinInstnId><BICFI>MUSTCHZZXXX</BICFI><Nm>Musterbank AG</Nm></FinInstnId></Svcr></Acct>" % (OWN, HOLDER)

def camt053(v, name):
    ns = "urn:iso:std:iso:20022:tech:xsd:camt.053.001.%02d" % v
    out = ['<?xml version="1.0" encoding="UTF-8"?>',
           '<Document xmlns="%s" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="%s camt.053.001.%02d.xsd">' % (ns, ns, v),
           "<BkToCstmrStmt>",
           "<GrpHdr><MsgId>MSG-20261001-053-%02d</MsgId><CreDtTm>2026-10-01T05:15:00+02:00</CreDtTm><MsgPgntn><PgNb>1</PgNb><LastPgInd>true</LastPgInd></MsgPgntn><AddtlInf>%s</AddtlInf></GrpHdr>" % (v, "SPS/2.2/PROD" if v == 8 else "SPS/1.7/PROD")]
    bal_ = OPENING
    seq = 0
    for a, b in months():
        seq += 1
        ents = [t for t in TX if a <= t.book <= b]
        op = bal_
        for t in ents:
            bal_ += t.amount
        cre = b + dt.timedelta(days=1)
        out.append("<Stmt><Id>STMT-%s-%02d</Id><ElctrncSeqNb>%d</ElctrncSeqNb><CreDtTm>%sT05:15:00%s</CreDtTm><FrToDt><FrDtTm>%sT00:00:00%s</FrDtTm><ToDtTm>%sT23:59:59%s</ToDtTm></FrToDt>" % (
            b.strftime("%Y%m"), v, seq, cre.isoformat(), off(cre), a.isoformat(), off(a), b.isoformat(), off(b)))
        out.append(acct_xml())
        out.append(bal("OPBD", op, a - dt.timedelta(days=1)) + bal("CLBD", bal_, b) + bal("CLAV", bal_, b))
        cr = [t for t in ents if t.amount > 0]; db = [t for t in ents if t.amount < 0]
        out.append('<TxsSummry><TtlNtries><NbOfNtries>%d</NbOfNtries></TtlNtries><TtlCdtNtries><NbOfNtries>%d</NbOfNtries><Sum>%s</Sum></TtlCdtNtries><TtlDbtNtries><NbOfNtries>%d</NbOfNtries><Sum>%s</Sum></TtlDbtNtries></TxsSummry>' % (
            len(ents), len(cr), fmt(sum(t.amount for t in cr) or D(0), sign=False), len(db), fmt(-sum(t.amount for t in db), sign=False)))
        for t in ents:
            out.append(entry(t, v))
        out.append("</Stmt>")
    out += ["</BkToCstmrStmt>", "</Document>"]
    with open(os.path.join(OUT, name), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")

def camt054(name):
    v = 8
    ns = "urn:iso:std:iso:20022:tech:xsd:camt.054.001.08"
    out = ['<?xml version="1.0" encoding="UTF-8"?>',
           '<Document xmlns="%s" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="%s camt.054.001.08.xsd">' % (ns, ns),
           "<BkToCstmrDbtCdtNtfctn>",
           "<GrpHdr><MsgId>MSG-20261001-054</MsgId><CreDtTm>2026-10-01T05:20:00+02:00</CreDtTm><MsgPgntn><PgNb>1</PgNb><LastPgInd>true</LastPgInd></MsgPgntn><AddtlInf>SPS/2.2/PROD</AddtlInf></GrpHdr>"]
    seq = 0
    for a, b in months():
        seq += 1
        ents = [t for t in TX if a <= t.book <= b and t.amount < 0]
        out.append("<Ntfctn><Id>NTFC-%s</Id><ElctrncSeqNb>%d</ElctrncSeqNb><CreDtTm>%sT05:20:00+02:00</CreDtTm><FrToDt><FrDtTm>%sT00:00:00</FrDtTm><ToDtTm>%sT23:59:59</ToDtTm></FrToDt><RptgSrc><Prtry>DBTN</Prtry></RptgSrc>" % (
            b.strftime("%Y%m"), seq, (b + dt.timedelta(days=1)).isoformat(), a.isoformat(), b.isoformat()))
        out.append(acct_xml())
        for t in ents:
            e = entry(t, v)
            e = e[:e.rfind("<AddtlNtryInf>")] + "</Ntry>"    # AddtlNtryInf is not used in camt.054 per SPS
            out.append(e)
        out.append("</Ntfctn>")
    out += ["</BkToCstmrDbtCdtNtfctn>", "</Document>"]
    with open(os.path.join(OUT, name), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")

if __name__ == "__main__":
    camt053(8, "ch_camt053_sps2022_v08.xml")
    camt053(4, "ch_camt053_sps2021_v04.xml")
    camt054("ch_camt054_sps2022_v08.xml")
