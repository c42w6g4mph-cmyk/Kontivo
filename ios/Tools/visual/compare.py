#!/usr/bin/env python3
"""Web und Swift nebeneinander (links Web, rechts Swift, Name oben) plus grobe Abweichungs-Kennzahl.

Aufruf:
    python3 ios/Tools/visual/compare.py --web /home/claude/visual/web --swift /home/claude/visual/swift --out /home/claude/visual/side [--only a,b]

Kennzahl «diff %»: Anteil der Pixel, deren Graustufe nach leichtem Weichzeichnen (Gauss, Radius 2 px)
um mehr als --thr (Standard 24 von 255) abweicht. Die Statusleiste (oben 62 pt) und der Home-Indikator
(unten 34 pt) werden nicht mitgezählt. Grob: schon 1 pt Versatz ganzer Blöcke erhöht den Wert stark.
Ergebnis zusätzlich als <out>/_scores.json und _scores.txt (absteigend).
"""
import argparse
import json
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HEAD = 44
GAP = 16


def font(size):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def score(web, swift, thr, top_pt, bottom_pt, pt_h):
    a = web.convert("L").filter(ImageFilter.GaussianBlur(2))
    b = swift.convert("L").filter(ImageFilter.GaussianBlur(2))
    if a.size != b.size:
        a = a.resize(b.size)
    w, h = b.size
    s = h / pt_h
    y0, y1 = int(top_pt * s), int(h - bottom_pt * s)
    d = ImageChops.difference(a, b).crop((0, y0, w, y1))
    hist = d.histogram()
    bad = sum(hist[thr + 1:])
    return 100.0 * bad / max(1, d.size[0] * d.size[1])


def side(name, web, swift, pct, out):
    w, h = swift.size
    if web is None:
        web = Image.new("RGB", (w, h), (235, 235, 235))
        ImageDraw.Draw(web).text((20, h // 2), "kein Web-Gegenstück", fill=(120, 0, 0), font=font(26))
    elif web.size != swift.size:
        web = web.resize(swift.size)
    im = Image.new("RGB", (w * 2 + GAP, h + HEAD), (255, 255, 255))
    im.paste(web.convert("RGB"), (0, HEAD))
    im.paste(swift.convert("RGB"), (w + GAP, HEAD))
    d = ImageDraw.Draw(im)
    f = font(22)
    d.text((10, 10), name + ("   diff %.1f %%" % pct if pct is not None else ""), fill=(0, 0, 0), font=f)
    d.text((w - 70, 12), "Web", fill=(150, 30, 30), font=font(18))
    d.text((2 * w + GAP - 80, 12), "Swift", fill=(30, 30, 150), font=font(18))
    im.save(os.path.join(out, name + ".png"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--web", default="/home/claude/visual/web")
    ap.add_argument("--swift", default="/home/claude/visual/swift")
    ap.add_argument("--out", default="/home/claude/visual/side")
    ap.add_argument("--only", default="")
    ap.add_argument("--thr", type=int, default=24)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    names = sorted(f[:-4] for f in os.listdir(a.swift) if f.endswith(".png"))
    if a.only:
        names = [n for n in names if n in a.only.split(",")]
    scores = {}
    for n in names:
        sw = Image.open(os.path.join(a.swift, n + ".png")).convert("RGB")
        wp = os.path.join(a.web, n + ".png")
        web = Image.open(wp).convert("RGB") if os.path.exists(wp) else None
        pad = "ipad" in n
        pct = score(web, sw, a.thr, 24 if pad else 62, 20 if pad else 34, 1376 if pad else 874) if web else None
        side(n, web, sw, pct, a.out)
        scores[n] = None if pct is None else round(pct, 2)
        print("%-32s %s" % (n, "-" if pct is None else "%.1f %%" % pct))
    path = os.path.join(a.out, "_scores.json")
    if a.only and os.path.exists(path):  # Teillauf: bisherige Werte behalten
        old = json.load(open(path))
        old.update(scores)
        scores = old
    with open(path, "w") as f:
        json.dump(scores, f, indent=1)
    with open(os.path.join(a.out, "_scores.txt"), "w") as f:
        for n, v in sorted(scores.items(), key=lambda x: -(x[1] if x[1] is not None else -1)):
            f.write("%-32s %s\n" % (n, "kein Web-Bild" if v is None else "%.1f %%" % v))


if __name__ == "__main__":
    main()
