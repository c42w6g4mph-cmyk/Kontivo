"""ZIP-basierte Formate des Kontoauszug-Imports: xlsx (Standard und mit Präfixen x:/Sheet1.xml), ODS, ZIP mit CSV, ZIP ohne Auszug.
Erzeugt die Dateien aus samples/de_deutschebank.csv. Braucht openpyxl und LibreOffice (soffice) für ODS.
Aufruf im Repo-Ordner:  python3 -m http.server 8765 &  python3 tests/bank/zipfmt.py"""
import base64, csv, datetime, io, os, re, shutil, subprocess, sys, tempfile, zipfile
import openpyxl
from playwright.sync_api import sync_playwright
D = os.path.dirname(os.path.abspath(__file__)); URL = os.environ.get("KONTIVO_URL", "http://localhost:8765/index.html")
T = tempfile.mkdtemp(); src = open(os.path.join(D, "samples", "de_deutschebank.csv"), encoding="latin-1").read()
rows = list(csv.reader(io.StringIO(src), delimiter=";"))
def num(v):
    try: return float(v.replace(".", "").replace(",", "."))
    except ValueError: return v or None
def dat(v):
    try: return datetime.datetime.strptime(v, "%d.%m.%Y")
    except ValueError: return v
wb = openpyxl.Workbook(); ws = wb.active
for i, r in enumerate(rows):
    ws.append([dat(r[0]), dat(r[1])] + r[2:15] + [num(x) for x in r[15:17]] + r[17:] if i > 3 else r)
P = lambda n: os.path.join(T, n); wb.save(P("std.xlsx"))
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
z = zipfile.ZipFile(P("leer.zip"), "w"); z.writestr("readme.pdf", b"%PDF"); z.close()
F = {"std.xlsx": 202, "ns.xlsx": 202, "csv.zip": 202, "leer.zip": "zip"}
if shutil.which("soffice"):
    subprocess.run(["soffice", "--headless", "--convert-to", "ods", "--outdir", T, P("std.xlsx")], capture_output=True, timeout=180); F["std.ods"] = 202
ok = True
with sync_playwright() as p:
    pg = p.chromium.launch().new_page(); pg.goto(URL); pg.wait_for_timeout(1500)
    for f, want in F.items():
        b = open(P(f), "rb").read()
        r = pg.evaluate("""async(b64)=>{var bin=atob(b64),u=new Uint8Array(bin.length);for(var i=0;i<bin.length;i++)u[i]=bin.charCodeAt(i);
          var res=await window.KontivoBank().readFile(new File([u],"x"));return res.r?res.r.tx.length:res.diag;}""", base64.b64encode(b).decode())
        good = r == want; ok &= good; print("✓" if good else "✗", f.ljust(10), r)
print("Alles gut" if ok else "FEHLER"); sys.exit(0 if ok else 1)
