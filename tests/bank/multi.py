"""Mehrere Dateien auf einmal: gleiche Datei doppelt (überlappender Export) zählt nur einmal; Konto + Kreditkarte ergänzen sich.
Aufruf im Repo-Ordner:  python3 -m http.server 8765 &  python3 tests/bank/multi.py"""
import base64, json, os, sys, re
from playwright.sync_api import sync_playwright
D = os.path.dirname(os.path.abspath(__file__)); URL = os.environ.get("KONTIVO_URL", "http://localhost:8765/index.html")
def b64(p): return base64.b64encode(open(os.path.join(D, p), "rb").read()).decode()
JS = """(fs)=>{var B=window.KontivoBank(),rs=fs.map(function(b){var bin=atob(b),u=new Uint8Array(bin.length);for(var i=0;i<bin.length;i++)u[i]=bin.charCodeAt(i);return B.read(u.buffer);});
  var r=B.merge(rs),f=B.find(r,[]);return {n:r.tx.length,s:f.sugg.map(function(s){return [s.name,s.cycle,s.amount,s.n];})};}"""
fails = 0
with sync_playwright() as p:
    b = p.chromium.launch(); ctx = b.new_context(); ctx.add_init_script("window.__KONTIVO_TODAY='2026-10-08';")
    ctx.route(re.compile(r"frankfurter\.|open\.er-api\.com"), lambda r: r.abort())  # kein Live-Kursabruf: feste Testkurse
    pg = ctx.new_page(); pg.goto(URL)
    st = {"settings": {"home": "CHF", "onboarded": 9, "holders": ["Max"], "rateCheckedAt": 9999999999999}, "contracts": {}, "incomes": {}}
    pg.evaluate("s=>localStorage.setItem('vertraege.v1',s)", json.dumps(st)); pg.reload(); pg.wait_for_timeout(400)
    one = pg.evaluate(JS, [b64("samples/ch_postfinance.csv")])
    two = pg.evaluate(JS, [b64("samples/ch_postfinance.csv"), b64("samples/ch_postfinance.csv")])
    ok = one == two; print(("✓" if ok else "✗"), "gleiche Datei doppelt = einmal", "" if ok else (one["n"], two["n"])); fails += not ok
    acc = pg.evaluate(JS, [b64("real/de/de_sparkasse_camt_v2.csv")]); card = pg.evaluate(JS, [b64("real/de/de_sparkasse_kreditkarte.csv")])
    both = pg.evaluate(JS, [b64("real/de/de_sparkasse_camt_v2.csv"), b64("real/de/de_sparkasse_kreditkarte.csv")])
    names = lambda r: sorted(x[0] for x in r["s"])
    ok = both["n"] == acc["n"] + card["n"] and set(names(acc)) | set(names(card)) == set(names(both))
    print(("✓" if ok else "✗"), "Konto + Kreditkarte ergänzen sich", "" if ok else (names(acc), names(card), names(both))); fails += not ok
    # Review 25.10.2026: derselbe Vertragspartner gleichzeitig auf zwei Konten (zwei Handyabos) = zwei Verträge, nicht einer mit schwankendem Betrag
    H = "Datum;Buchungstext;Betrag\n"
    ka = H + "".join(f"{d}.2026;LASTSCHRIFT Muster Mobil AG;-27.95\n" for d in ["25.06", "27.07", "26.08", "25.09"])
    kb = H + "".join(f"{d}.2026;LASTSCHRIFT Muster Mobil AG;-28.95\n" for d in ["28.07", "31.08", "30.09"])
    enc = lambda t: base64.b64encode(t.encode()).decode()
    par = pg.evaluate(JS, [enc(ka), enc(kb)])
    mm = sorted(x[2] for x in par["s"] if x[0].startswith("Muster Mobil"))
    ok = mm == [27.95, 28.95]; print(("✓" if ok else "✗"), "zwei Konten, gleicher Vertragspartner = zwei Verträge", "" if ok else par["s"]); fails += not ok
    # Review 25.10.2026: Steuerraten über zwei Konten (Vorjahr + Januar auf dem einen, Rest auf dem anderen) = ein Vertrag, nicht zusätzlich ein Jahresvertrag
    T = "DAUERAUFTRAG Stadtverwaltung Musterstadt Mitteilung: Staats- und Gemeindesteuern Steuerperiode {y};-{a}\n"
    sa = H + "".join(f"28.{m:02d}.2025;" + T.format(y=2025, a="900.00") for m in range(1, 7)) + "".join(f"28.{m:02d}.2025;" + T.format(y=2025, a="410.00") for m in (10, 11)) + "28.01.2026;" + T.format(y=2026, a="760.00")
    sb = H + "".join(f"28.{m:02d}.2025;" + T.format(y=2025, a="410.00") for m in (7, 8, 9)) + "".join(f"27.{m:02d}.2026;" + T.format(y=2026, a="760.00") for m in range(2, 7)) + "".join(f"27.{m:02d}.2026;" + T.format(y=2026, a="340.00") for m in range(7, 10))
    st = pg.evaluate(JS, [enc(sa), enc(sb)])
    sv = [x for x in st["s"] if x[0].startswith("Stadtverwaltung")]
    ok = len(sv) == 1 and sv[0][2] == 340; print(("✓" if ok else "✗"), "Steuerraten über zwei Konten = ein Vertrag", "" if ok else st["s"]); fails += not ok
    # Review 25.10.2026 (B-H5): zwei Konten zahlen am selben Tag denselben Betrag an denselben Anbieter = zwei Verträge (mit und ohne IBAN in der Datei)
    mob = lambda: "".join(f"28.{m:02d}.2026;LASTSCHRIFT Muster Mobil AG;-29.90\n" for m in range(1, 10))
    xa = H + mob() + "".join(f"{d:02d}.03.2026;KARTENZAHLUNG Laden Nord;-{d+3}.50\n" for d in range(1, 20))
    xb = H + mob() + "".join(f"{d:02d}.04.2026;KARTENZAHLUNG Laden Sued;-{d+7}.20\n" for d in range(1, 20))
    two = pg.evaluate(JS, [enc(xa), enc(xb)]); mm = [x for x in two["s"] if x[0].startswith("Muster Mobil")]
    ok = len(mm) == 2; print(("✓" if ok else "✗"), "zwei Konten, gleicher Betrag am selben Tag = zwei Verträge", "" if ok else two["s"]); fails += not ok
    one = pg.evaluate(JS, [enc(xa), enc(xa)]); mm1 = [x for x in one["s"] if x[0].startswith("Muster Mobil")]
    ok = len(mm1) == 1 and mm1[0][3] == 9; print(("✓" if ok else "✗"), "gleiche Datei zweimal bleibt ein Vertrag", "" if ok else one["s"]); fails += not ok
    # B-H6: Unterreihen (mehrere Policen) haben verschiedene Schlüssel für «nicht mehr vorschlagen»
    import json as _j
    C = _j.load(open(os.path.join(D, "edge_cases.json")))
    keys = pg.evaluate("(t)=>{var B=window.KontivoBank(),f=B.find(B.read(t),[]);return f.sugg.filter(function(s){return /Muster Versicherung/.test(s.name)}).map(function(s){return B.ignKey(s)});}", C["jahresreihe"]["txt"])
    ok = len(keys) >= 2 and len(set(keys)) == len(keys); print(("✓" if ok else "✗"), "Policen: eigene Schlüssel zum Ausblenden", "" if ok else keys); fails += not ok
    b.close()
print("Alles gut" if not fails else f"{fails} Fehler"); sys.exit(1 if fails else 0)
