"""Erzeugt ios/Kontivo/Resources/Assets.xcassets/Icons/ic.<name>.imageset aus den Inline-SVGs der Web-App (v224)."""
import json, os, re, sys
WEB = sys.argv[1]  # Web-Repo (main) mit index.html
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Kontivo", "Resources", "Assets.xcassets", "Icons")
html = open(os.path.join(WEB, "index.html"), encoding="utf-8").read()

def jsmap(name):
    i = html.index("var %s={" % name); j = html.index("};", i)
    return dict(re.findall(r'"?([\w &äöüÄÖÜ]+?)"?:\'(.*?)\'', html[i:j + 1]))

CAT = jsmap("CAT_ICON")
TAG = re.search(r"var TAG_ICON='(.*?)'", html).group(1)
CAT_SLUG = {"Wohnen": "wohnen", "Energie & Wasser": "energie", "Versicherung": "versicherung", "Gesundheit": "gesundheit",
            "Mobilfunk & Internet": "mobilfunk", "Abos & Medien": "abos", "Mobilität": "mobilitaet", "Familie & Bildung": "familie",
            "Freizeit & Sport": "freizeit", "Steuern & Gebühren": "steuern", "Finanzen": "finanzen", "Sonstiges": "sonstiges",
            "Lohn": "lohn", "Nebeneinkommen": "nebeneinkommen", "Bonus": "bonus", "Kapitalerträge": "kapital", "Vermietung": "vermietung",
            "Rente": "rente", "Zulagen": "zulagen", "Unterstützung": "unterstuetzung", "Rückerstattung": "rueckerstattung"}
assert set(CAT) == set(CAT_SLUG), set(CAT) ^ set(CAT_SLUG)

DOTS = '<circle cx="5" cy="12" r="1.9"/><circle cx="12" cy="12" r="1.9"/><circle cx="19" cy="12" r="1.9"/>'
# name: (body, stroke-width, viewBox, filled)
ICONS = {
    # Tabbar (.tabbar svg 24px, Strich 1.6; «Mehr» gefüllte Punkte)
    "tab.list": ('<path d="M7 3h7l5 5v13H7z"/><path d="M14 3v5h5"/><path d="M10 13h6M10 17h5"/>', 1.6),
    "tab.stat": ('<path d="M5 20v-8M10 20V5M15 20v-6M20 20V9"/>', 1.6),
    "tab.budget": ('<rect x="3" y="6" width="18" height="13" rx="3"/><path d="M3 10h18"/><path d="M15.5 14.5h2.5"/>', 1.6),
    "tab.term": ('<circle cx="12" cy="12.5" r="8"/><path d="M12 8.5v4l2.8 1.8"/><path d="M9.5 2.8h5"/>', 1.6),
    "tab.set": (DOTS, 0, "0 0 24 24", True),
    # Kopf / Suche
    "plus": ('<path d="M12 5v14M5 12h14"/>', 2.2),
    "search": ('<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/>', 1.8),
    "filter": ('<path d="M4 6h16M7 12h10M10 18h4"/>', 1.8),
    "sort": ('<path d="M8 5v14M4.5 15.5 8 19l3.5-3.5M16 19V5M12.5 8.5 16 5l3.5 3.5"/>', 1.8),
    "share": ('<path d="M12 15V4M7.5 8.5 12 4l4.5 4.5M6 11v8h12v-8"/>', 1.9),
    "more": ('<circle cx="6" cy="12" r="1.8"/><circle cx="12" cy="12" r="1.8"/><circle cx="18" cy="12" r="1.8"/>', 0, "0 0 24 24", True),
    # Mehr → Verwalten (.mgi 18px, Strich 1.6)
    "partner": ('<path d="M4 20V8l8-4 8 4v12"/><path d="M9 20v-6h6v6"/>', 1.6),
    "persons": ('<circle cx="9" cy="8" r="3.2"/><path d="M3.5 19c.8-3.2 3-5 5.5-5s4.7 1.8 5.5 5"/><circle cx="17" cy="9" r="2.5"/><path d="M15.5 14.2c2.4.2 4.2 1.9 5 4.8"/>', 1.6),
    "categories": ('<rect x="4" y="4" width="7" height="7" rx="2"/><rect x="13" y="4" width="7" height="7" rx="2"/><rect x="4" y="13" width="7" height="7" rx="2"/><rect x="13" y="13" width="7" height="7" rx="2"/>', 1.6),
    "check": ('<path d="m5 12.5 4.2 4.2L19 7"/>', 1.6),
    "check.bold": ('<path d="M5 12.5l4.5 4.5L19 7.5"/>', 3),
    "check.hook": ('<path d="m5 12.5 4.2 4.2L19 7"/>', 2.2),
    "check.done": ('<path d="m6 12.5 4 4 8-9"/>', 2),
    "check.small": ('<path d="M3.5 8.4l2.8 2.8 6.2-6.4"/>', 2, "0 0 16 16"),
    # Mehr → Daten (.tile 22px, Strich 1.8)
    "upload": ('<path d="M12 15V4M7.5 8.5 12 4l4.5 4.5M5 19h14"/>', 1.8),
    "download": ('<path d="M12 4v11M7.5 10.5 12 15l4.5-4.5M5 19h14"/>', 1.8),
    "table": ('<rect x="4" y="4" width="16" height="16" rx="2"/><path d="M4 10h16M10 4v16"/>', 1.8),
    # Plus-Menü, Formular, Detail
    "pen": ('<path d="M4 20h4L19 9l-4-4L4 16z"/>', 1.8),
    "edit": ('<path d="M4 20h4l10.5-10.5a2.1 2.1 0 0 0-3-3L5 17z"/><path d="M13.5 6.5l3 3"/>', 1.8),
    "bank": ('<path d="M3 10l9-6 9 6M5 10v8M9.5 10v8M14.5 10v8M19 10v8M3 20h18"/>', 1.8),
    "income": ('<path d="M12 4v12M7 11l5 5 5-5M5 20h14"/>', 1.8),
    "mail": ('<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3.5 7l8.5 6 8.5-6"/>', 1.8),
    "book": ('<path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H20v15H6.5A2.5 2.5 0 0 0 4 20.5z"/><path d="M4 18V5.5M8 7h8M8 10.5h6"/>', 1.8),
    "clip": ('<path d="M20 11.5l-7.8 7.8a5 5 0 0 1-7.1-7.1l8.3-8.3a3.3 3.3 0 0 1 4.7 4.7l-8.3 8.3a1.7 1.7 0 0 1-2.4-2.4l7.6-7.6"/>', 1.8),
    "lock": ('<rect x="5" y="10.5" width="14" height="10" rx="2"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5"/>', 2),
    "drag": ('<path d="M5 8h14M5 12h14M5 16h14"/>', 1.8),
    "pdf": ('<path d="M6 3h9l4 4v14H6z"/><path d="M15 3v4h4"/><path d="M9 13h6M9 17h4"/>', 1.8),
    "camera": ('<path d="M4 8h3l1.6-2.4h6.8L17 8h3v11H4z"/><circle cx="12" cy="13.2" r="3.4"/>', 1.8),
    "gift": ('<rect x="3" y="8" width="18" height="12" rx="2"/><path d="M12 8v12M3 12h18"/><path d="M12 8c-2-4-6-4-6-1s4 1 6 1c2 0 6 2 6-1s-4-3-6 1"/>', 1.8),
    "share.people": ('<circle cx="9" cy="8" r="3.2"/><path d="M3.5 19a5.5 5.5 0 0 1 11 0"/><circle cx="17" cy="9" r="2.5"/><path d="M16 14.2a4.5 4.5 0 0 1 5 4.8"/>', 1.8),
    "cloud": ('<path d="M7 18a4.5 4.5 0 0 1-.6-9 6 6 0 0 1 11.5 1.2A3.9 3.9 0 0 1 17.5 18z"/><path d="M9.5 13.5l2 2 3.5-3.5"/>', 1.8),
    "bell": ('<path d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15z"/><path d="M10 20.5a2 2 0 0 0 4 0"/>', 1.8),
    "sparkle": ('<path d="M12 3l1.8 4.6L18.5 9l-4.7 1.6L12 15l-1.8-4.4L5.5 9l4.7-1.4z"/>', 1.8),
    "shield": ('<path d="M12 3.5 5.5 6v5.5c0 4 2.8 7.2 6.5 8.8 3.7-1.6 6.5-4.8 6.5-8.8V6z"/><path d="m9.3 12 2 2 3.6-3.8"/>', 1.8),
}
for k, slug in CAT_SLUG.items():
    ICONS["cat." + slug] = (CAT[k], 1.6)
ICONS["cat.tag"] = (TAG, 1.6)

NUM = r"[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?"
ARGC = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "T": 2, "A": 7, "Z": 0}

def norm_path(d):
    """Pfad in ausgeschriebene Form (jeder Befehl explizit, Zahlen mit Leerzeichen, Bogen-Flags einzeln)."""
    out = []; i = 0; cmd = None; n = len(d)
    def skip(i):
        while i < n and d[i] in " ,\t\n": i += 1
        return i
    while True:
        i = skip(i)
        if i >= n: break
        if d[i].isalpha():
            cmd = d[i]; i += 1
            if cmd in "zZ": out.append("Z"); continue
        args = []
        for k in range(ARGC[cmd.upper()]):
            i = skip(i)
            if cmd.upper() == "A" and k in (3, 4):
                args.append(d[i]); i += 1; continue
            m = re.match(NUM, d[i:])
            if not m: raise ValueError("Pfad: %r bei %d" % (d, i))
            args.append(m.group(0)); i += len(m.group(0))
        def f(x):
            v = float(x); s = ("%.3f" % v).rstrip("0").rstrip(".")
            return "0" if s in ("-0", "") else s
        out.append(cmd + " " + " ".join(f(a) if not (cmd.upper() == "A" and j in (3, 4)) else a for j, a in enumerate(args)))
        if cmd == "M": cmd = "L"
        elif cmd == "m": cmd = "l"
    return " ".join(out)

def body_norm(b):
    return re.sub(r'd="([^"]+)"', lambda m: 'd="%s"' % norm_path(m.group(1)), b)

def svg(body, sw, vb="0 0 24 24", filled=False):
    w, h = vb.split()[2:]
    g = '<g fill="#000000" stroke="none">' if filled else \
        '<g fill="none" stroke="#000000" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round">' % sw
    return ('<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="%s">%s%s</g></svg>\n'
            % (w, h, vb, g, body_norm(body)))

os.makedirs(OUT, exist_ok=True)
json.dump({"info": {"author": "xcode", "version": 1}, "properties": {"provides-namespace": False}},
          open(os.path.join(OUT, "Contents.json"), "w"), indent=2)
for name, spec in ICONS.items():
    body, sw = spec[0], spec[1]
    vb = spec[2] if len(spec) > 2 else "0 0 24 24"
    filled = spec[3] if len(spec) > 3 else False
    d = os.path.join(OUT, "ic.%s.imageset" % name); os.makedirs(d, exist_ok=True)
    fn = "ic.%s.svg" % name
    open(os.path.join(d, fn), "w").write(svg(body, sw, vb, filled))
    json.dump({"images": [{"filename": fn, "idiom": "universal"}], "info": {"author": "xcode", "version": 1},
               "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"}},
              open(os.path.join(d, "Contents.json"), "w"), indent=2)
print(len(ICONS), "Symbole")
