"""ZIP-Formate für BankZipTests.swift (Web v261/v272, tests/bank/zipfmt.py): xlsx (Standard, mit Präfixen x:/Sheet1.xml,
Titelzeile + zweites Blatt), ODS (LibreOffice), ZIP mit CSV, ZIP mit zwei camt-Dateien, ZIP ohne Auszug. Ergebnis jeder Datei aus der
Web-App (window.KontivoBank().readFile) → zip/expected.json.
Aufruf:  cd <web-repo> && python3 -m http.server 8765 &   python3 -I make_zip.py [<web-repo>]   (braucht openpyxl, soffice für ODS)"""
import base64, csv, datetime, io, json, os, re, shutil, subprocess, sys, zipfile
import openpyxl
from playwright.sync_api import sync_playwright
HERE = os.path.dirname(os.path.abspath(__file__)); WEB = sys.argv[1] if len(sys.argv) > 1 else "/home/claude/kontivo"
URL = os.environ.get("KONTIVO_URL", "http://localhost:8765/index.html")
T = os.path.join(HERE, "zip"); os.makedirs(T, exist_ok=True)
src = open(os.path.join(WEB, "tests", "bank", "samples", "de_deutschebank.csv"), encoding="latin-1").read()
rows = list(csv.reader(io.StringIO(src), delimiter=";"))
def num(v):
    try: return float(v.replace(".", "").replace(",", "."))
    except ValueError: return v or None
def dat(v):
    try: return datetime.datetime.strptime(v, "%d.%m.%Y")
    except ValueError: return v
P = lambda n: os.path.join(T, n)
wb = openpyxl.Workbook(); ws = wb.active
for i, r in enumerate(rows):
    ws.append([dat(r[0]), dat(r[1])] + r[2:15] + [num(x) for x in r[15:17]] + r[17:] if i > 3 else r)
wb.save(P("std.xlsx"))
# Titelzeile, Leerblatt zuerst, Auszug im zweiten Blatt
wb2 = openpyxl.Workbook(); wb2.active.title = "Info"; wb2.active.append(["Exportiert am", "24.10.2026"]); ws2 = wb2.create_sheet("Umsätze")
ws2.append(["Kontoumsätze Girokonto"]); ws2.append([])
ch = list(csv.reader(io.StringIO(open(os.path.join(WEB, "tests", "bank", "samples", "ch_postfinance.csv"), encoding="utf-8-sig").read()), delimiter=";"))
hi = next(i for i, r in enumerate(ch) if r and r[0] == "Datum")
for i, r in enumerate(ch[hi:]):
    if not any(r): continue
    ws2.append([dat(r[0])] + [num(x) if j in (3, 4) else x for j, x in enumerate(r[1:], 1)] if i > 0 else r)
wb2.save(P("sheets.xlsx"))
zi = zipfile.ZipFile(P("std.xlsx")); zo = zipfile.ZipFile(P("ns.xlsx"), "w", zipfile.ZIP_DEFLATED)
for it in zi.infolist():
    d = zi.read(it.filename); n = it.filename
    if n == "xl/worksheets/sheet1.xml": n = "xl/worksheets/Sheet1.xml"
    if n.endswith(".xml") and ("worksheets" in n or "sharedStrings" in n):
        t = re.sub(r"<(/?)(?!\?)([A-Za-z])", r"<\1x:\2", d.decode())
        t = re.sub(r"<x:(worksheet|sst) ", r'<x:\1 xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main" ', t); d = t.encode()
    if n == "xl/_rels/workbook.xml.rels": d = d.decode().replace('Target="worksheets/sheet1.xml"', 'Target="/xl/worksheets/Sheet1.xml"').encode()
    zo.writestr(n, d)
zo.close()
z = zipfile.ZipFile(P("csv.zip"), "w", zipfile.ZIP_DEFLATED); z.writestr("Kontoumsaetze.csv", src.encode("latin-1")); z.writestr("__MACOSX/._Kontoumsaetze.csv", b"\0"); z.close()
z = zipfile.ZipFile(P("camt.zip"), "w", zipfile.ZIP_DEFLATED)
camt = open(os.path.join(WEB, "tests", "bank", "samples", "ch_camt053.xml"), "rb").read()
z.writestr("2026/auszug_1.xml", camt); z.writestr("2026/auszug_2.xml", camt); z.writestr("liesmich.txt", b"Kontoauszug"); z.close()
z = zipfile.ZipFile(P("stored.zip"), "w", zipfile.ZIP_STORED); z.writestr("umsaetze.csv", src.encode("latin-1")); z.close()
z = zipfile.ZipFile(P("leer.zip"), "w"); z.writestr("readme.pdf", b"%PDF"); z.close()
FILES = ["std.xlsx", "ns.xlsx", "sheets.xlsx", "csv.zip", "camt.zip", "stored.zip", "leer.zip"]
if shutil.which("soffice"):
    subprocess.run(["soffice", "--headless", "--convert-to", "ods", "--outdir", T, P("std.xlsx")], capture_output=True, timeout=180)
    if os.path.exists(P("std.ods")): FILES.append("std.ods")
out = {}
with sync_playwright() as p:
    pg = p.chromium.launch().new_page()
    pg.route(re.compile(r"frankfurter\.|open\.er-api\.com"), lambda r: r.abort())
    pg.goto(URL); pg.wait_for_timeout(1500)
    for f in FILES:
        b = open(P(f), "rb").read()
        out[f] = pg.evaluate("""async(b64)=>{var bin=atob(b64),u=new Uint8Array(bin.length);for(var i=0;i<bin.length;i++)u[i]=bin.charCodeAt(i);
          var res=await window.KontivoBank().readFile(new File([u],"x"));var r=res.r;
          return r?{fmt:r.fmt,bank:r.bank||"",n:r.tx.length,from:r.from,to:r.to,owner:r.owner||"",
            tx:r.tx.map(function(t){return [t.d,t.a,t.cur||"",t.name||"",t.text||"",t.type||"",t.kind||"",t.cred||"",t.mref||""];})}:{diag:res.diag||""};}""",
          base64.b64encode(b).decode())
        print(f, out[f].get("n", out[f].get("diag")))
json.dump(out, open(P("expected.json"), "w"), ensure_ascii=False, separators=(",", ":"))
