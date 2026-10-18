"""Glyphen «ntivo» der Wortmarke (brand/kontivo-wortmarke-hell.svg) → Swift-Pfadcode (Einheit: 1/1000 em, Ursprung links oben)."""
import re, sys
s = open(sys.argv[1]).read()
OX, OY = 50.0, 134.0
glyphs = []
for m in re.finditer(r'<path transform="translate\(([\d.]+) ([\d.]+)\) scale\(([\d.]+) -([\d.]+)\)" d="([^"]+)"', s):
    tx, ty, sc = float(m.group(1)), float(m.group(2)), float(m.group(3))
    d = m.group(5); out = []
    toks = re.findall(r'[MLHVCQZ]|-?\d*\.?\d+', d)
    i = 0; cmd = None; x = y = 0.0
    def P(px, py): return "CGPoint(x: %.2f, y: %.2f)" % (tx + sc * px - OX, ty - sc * py - OY)
    while i < len(toks):
        t = toks[i]
        if t.isalpha(): cmd = t; i += 1
        if cmd == 'Z': out.append("p.closeSubpath()"); continue
        n = {'M': 2, 'L': 2, 'H': 1, 'V': 1, 'C': 6, 'Q': 4}[cmd]
        a = [float(v) for v in toks[i:i + n]]; i += n
        if cmd == 'M': x, y = a; out.append("p.move(to: %s)" % P(x, y))
        elif cmd == 'L': x, y = a; out.append("p.addLine(to: %s)" % P(x, y))
        elif cmd == 'H': x = a[0]; out.append("p.addLine(to: %s)" % P(x, y))
        elif cmd == 'V': y = a[0]; out.append("p.addLine(to: %s)" % P(x, y))
        elif cmd == 'C': out.append("p.addCurve(to: %s, control1: %s, control2: %s)" % (P(a[4], a[5]), P(a[0], a[1]), P(a[2], a[3]))); x, y = a[4], a[5]
        elif cmd == 'Q': out.append("p.addQuadCurve(to: %s, control: %s)" % (P(a[2], a[3]), P(a[0], a[1]))); x, y = a[2], a[3]
    glyphs.append(out)


names = ["n", "t", "i", "v", "o"]
for nm, g in zip(names, glyphs):
    print("    /// «%s»" % nm)
    print("    static func %s(_ p: inout Path) {" % ("glyph" + nm.upper()))
    print("\n".join("        " + l for l in g))
    print("    }")
