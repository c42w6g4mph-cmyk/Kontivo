import SwiftUI
import UIKit
import KontivoCore

// Gemeinsame Bausteine der Tabs «Kosten» und «Budget» (Präfix KB = Kosten/Budget).
// Masse = berechnete Styles der Web-App v224 (Viewport 402 pt, CSS-px = pt).

// MARK: - Masse und Farben (Web v224)

enum KBM {
    /// Seitenrand der Web-App (17 px bei 402 px Breite)
    static let side: CGFloat = 17
    /// Karten «kcard», «mrows2», «dcard»
    static let cardRadius: CGFloat = 16
    /// Listen «ilist», «fgcard», «xsum», «ptcard» (Web `--r`)
    static let listRadius: CGFloat = 13
    /// Web `.wrap{max-width:580px; padding:0 17px}` (Breite inkl. Seitenrand → Inhalt 546 pt auf dem iPad)
    static let wrapWidth: CGFloat = 580

    /// Zusätzlicher Abstand oben/unten, damit eine Textzeile die CSS-Zeilenhöhe `lh` erreicht (SF ≈ 1.193 × Schriftgrösse).
    static func pad(_ lh: CGFloat, _ size: CGFloat) -> CGFloat { max(0, (lh - size * 1.193) / 2) }
}

enum KBColor {
    /// CSS `color-mix(in srgb, a p%, b)` – je Erscheinungsbild aufgelöst
    static func mix(_ a: Color, _ p: CGFloat, _ b: Color) -> Color {
        Color(UIColor { tc in
            let x = UIColor(a).resolvedColor(with: tc), y = UIColor(b).resolvedColor(with: tc)
            var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
            var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
            x.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            y.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            return UIColor(red: r1 * p + r2 * (1 - p), green: g1 * p + g2 * (1 - p), blue: b1 * p + b2 * (1 - p), alpha: a1 * p + a2 * (1 - p))
        })
    }

    static func dyn(_ light: Color, _ dark: Color) -> Color {
        Color(UIColor { tc in UIColor(tc.userInterfaceStyle == .dark ? dark : light) })
    }

    /// Balken vergangener Monat (Kosten `.col .pd`): hell Messing 22 %, dunkel Tinte 14 %
    static let barPast = dyn(mix(KColor.brass, 0.22, KColor.surface), mix(KColor.ink, 0.14, KColor.surface))
    /// Balken vergangener Monat im Budget (`.bcol .bp`): hell Messing 18 %, dunkel Tinte 14 %
    static let budgetPast = dyn(mix(KColor.brass, 0.18, KColor.surface), mix(KColor.ink, 0.14, KColor.surface))
    /// Balken künftiger Monat (`.kcard .col i.op`): Tinte 12 %
    static let barFuture = mix(KColor.ink, 0.12, KColor.surface)
    /// Gewählter künftiger Monat im Budget (`.bcol.on i.bo`): Tinte 72 %
    static let budgetFutureOn = mix(KColor.ink, 0.72, KColor.surface)
    /// Defizit (Budget): Warnfarbe 22 % / 62 % / 45 % (Legende)
    static let negFuture = mix(KColor.alert, 0.22, KColor.surface)
    static let negFutureOn = mix(KColor.alert, 0.62, KColor.surface)
    static let negLegend = mix(KColor.alert, 0.45, KColor.surface)
    /// Punkt «Offen» (`.kcard .pdot.op`): Tinte 38 %
    static let openDot = mix(KColor.ink, 0.38, KColor.surface)
    /// Säulen «Entwicklung»: Vergangenheit Messing 22 %, Zukunft Tinte 12 %
    static let ptPast = mix(KColor.brass, 0.22, KColor.surface)
    /// Rand des Bericht-Knopfs (`.ynrep`): Akzent 35 % mit Linie
    static let reportEdge = mix(KColor.teal, 0.35, KColor.line)
}

// MARK: - Monat und Jahr wechseln

@MainActor
enum KBMonthNav {
    static func month(_ model: AppModel) -> Int { min(12, max(1, model.selectedMonth)) }

    static func canShift(_ model: AppModel, _ step: Int) -> Bool {
        KBMonthMath.canShift(year: model.selectedYear, month: model.selectedMonth, step: step, currentYear: model.today.year)
    }

    /// Nachbarmonat, über Dezember/Januar ins Nachbarjahr
    static func shift(_ model: AppModel, _ step: Int) {
        guard canShift(model, step) else { return }
        let r = KBMonthMath.shifted(year: model.selectedYear, month: model.selectedMonth, step: step)
        if model.selectedYear != r.year { model.selectedYear = r.year }
        model.selectedMonth = r.month
    }

    /// Jahr ± 1: im aktuellen Jahr der aktuelle Monat, sonst Januar
    static func changeYear(_ model: AppModel, by delta: Int) {
        let now = model.today
        if delta > 0 && model.selectedYear >= now.year + 5 { return }
        setYear(model, model.selectedYear + delta)
    }

    /// Jahr setzen (Säule in «Entwicklung» antippen): im aktuellen Jahr der aktuelle Monat, sonst Januar
    static func setYear(_ model: AppModel, _ ny: Int) {
        model.selectedYear = ny
        model.selectedMonth = ny == model.today.year ? model.today.month : 1
    }

    /// Monat im gewählten Jahr setzen; true, wenn er sich geändert hat
    @discardableResult
    static func select(_ model: AppModel, month: Int) -> Bool {
        let m = min(12, max(1, month))
        guard model.selectedMonth != m else { return false }
        model.selectedMonth = m
        return true
    }
}

// MARK: - Seitenkopf (Web `.top`: Titel 30 px, Jahr ‹ 2026 ›, Bericht) und Minileiste beim Scrollen

/// Runder Knopf 36 × 36 mit Linie (Web `.yearnav.ynt button`)
struct KBRoundButton<Label: View>: View {
    var tint: Color = KColor.ink2
    var edge: Color = KColor.line
    var fill: Color = .clear
    let action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) {
            label
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(Circle().fill(fill))
                .overlay(Circle().strokeBorder(edge, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Symbol «Teilen» der Web-App (Pfeil aus der Schale, 17 px, Strich 1.9)
struct KBShareGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 24
        var p = Path()
        p.move(to: CGPoint(x: 12 * s, y: 15 * s)); p.addLine(to: CGPoint(x: 12 * s, y: 4 * s))
        p.move(to: CGPoint(x: 7.5 * s, y: 8.5 * s)); p.addLine(to: CGPoint(x: 12 * s, y: 4 * s)); p.addLine(to: CGPoint(x: 16.5 * s, y: 8.5 * s))
        p.move(to: CGPoint(x: 6 * s, y: 11 * s)); p.addLine(to: CGPoint(x: 6 * s, y: 19 * s)); p.addLine(to: CGPoint(x: 18 * s, y: 19 * s))
        p.addLine(to: CGPoint(x: 18 * s, y: 11 * s))
        return p.offsetBy(dx: r.minX, dy: r.minY)
    }
}

/// Symbol «Weitere Filter» der Web-App (drei kürzer werdende Striche)
struct KBFilterGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 24
        var p = Path()
        p.move(to: CGPoint(x: 4 * s, y: 6 * s)); p.addLine(to: CGPoint(x: 20 * s, y: 6 * s))
        p.move(to: CGPoint(x: 7 * s, y: 12 * s)); p.addLine(to: CGPoint(x: 17 * s, y: 12 * s))
        p.move(to: CGPoint(x: 10 * s, y: 18 * s)); p.addLine(to: CGPoint(x: 14 * s, y: 18 * s))
        return p.offsetBy(dx: r.minX, dy: r.minY)
    }
}

/// «‹ 2026 ›» mit optionalem Bericht-Knopf (Web `setTopYear`)
struct KBYearNav: View {
    @Environment(AppModel.self) private var model
    var report: (() -> Void)? = nil

    var body: some View {
        let y = model.selectedYear
        let maxed = y >= model.today.year + 5
        HStack(spacing: 4) {
            KBRoundButton(action: { withAnimation(.snappy) { KBMonthNav.changeYear(model, by: -1) } }) {
                Text(verbatim: "‹").font(.system(size: 16))
            }
            .accessibilityLabel("Vorjahr")
            Text(verbatim: String(y))
                .font(.system(size: 18, weight: .semibold))
                .tracking(-0.216)
                .monospacedDigit()
                .foregroundStyle(KColor.ink)
                .frame(minWidth: 50)
                .accessibilityLabel(Text(verbatim: "Jahr " + String(y)))
            KBRoundButton(action: { withAnimation(.snappy) { KBMonthNav.changeYear(model, by: 1) } }) {
                Text(verbatim: "›").font(.system(size: 16))
            }
            .disabled(maxed)
            .opacity(maxed ? 0.3 : 1)
            .accessibilityLabel("Folgejahr")
            if let report {
                KBRoundButton(tint: KColor.teal, edge: KBColor.reportEdge, action: report) {
                    KBShareGlyph()
                        .stroke(style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                        .frame(width: 17, height: 17)
                }
                .padding(.leading, 6)
                .accessibilityLabel("Fixkosten-Bericht als PDF")
                .accessibilityIdentifier("costs.report")
            }
        }
    }
}

/// Oberkante des sichtbaren Bereichs (global, ohne Neuzeichnen der Seite) – für «Bereich bleibt an derselben Bildschirmstelle»
@Observable
final class KBMiniState {
    var viewportTop: CGFloat = 0
}

private struct KBMiniKey: EnvironmentKey {
    static let defaultValue: KBMiniState? = nil
}

extension EnvironmentValues {
    var kbMini: KBMiniState? {
        get { self[KBMiniKey.self] }
        set { self[KBMiniKey.self] = newValue }
    }
}

/// Scrollseite eines Tabs (Kosten, Budget): Titelzeile `KTabHeader` im Inhalt, Mini-Kopfzeile «Kosten · 2026» über `.kTabPage`.
enum KBPageSpace {
    static let name = "kbPage"
}

struct KBPage<Content: View>: View {
    let title: String
    let miniTitle: String
    @ViewBuilder var content: Content
    @State private var miniState = KBMiniState()
    @State private var viewport: CGFloat = 800

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("kbTop")
                    content
                }
                .padding(.horizontal, KBM.side)
                // Web `.wrap` padding-bottom 104 + Sicherheitsabstand (138 pt ab Bildschirmunterkante); die Tableiste
                // (83 pt) rechnet SwiftUI schon ein
                .padding(.bottom, 55)
                .kbWrapWidth()
            }
            .coordinateSpace(name: KBPageSpace.name)
            #if DEBUG
            .task {
                // Bildschirmfotos: «-uiScrollTo <id>» scrollt nach dem Start zu einem Bereich (kbList, kbDrivers, kbIncomes)
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-uiScrollTo"), i + 1 < args.count {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    proxy.scrollTo(args[i + 1], anchor: .top)
                }
            }
            #endif
            .environment(\.kbScroll, KBScrollContext(proxy: proxy, height: viewport))
            .environment(\.kbMini, miniState)
            .background(GeometryReader { g in
                let top = g.frame(in: .global).minY + g.safeAreaInsets.top
                Color.clear
                    .onAppear { viewport = g.size.height; miniState.viewportTop = top }
                    .onChange(of: g.size.height) { _, h in viewport = h }
                    .onChange(of: top) { _, t in miniState.viewportTop = t }
            })
        }
        .kTabPage(title: title, miniTitle: miniTitle)
    }
}

/// Scrollsteuerung der Seite (für «Bereich bleibt an derselben Bildschirmstelle»)
struct KBScrollContext {
    var proxy: ScrollViewProxy?
    var height: CGFloat

    /// Ansicht `id`, deren Oberkante vorher bei `top` (im sichtbaren Bereich) lag, wieder dorthin scrollen.
    func keep(_ id: String, top: CGFloat, viewHeight: CGFloat) {
        guard let proxy else { return }
        let free = height - viewHeight
        guard free > 1 else { return }
        let k = min(1, max(0, top / free))
        proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: k))
    }
}

private struct KBScrollKey: EnvironmentKey {
    static let defaultValue = KBScrollContext(proxy: nil, height: 800)
}

extension EnvironmentValues {
    var kbScroll: KBScrollContext {
        get { self[KBScrollKey.self] }
        set { self[KBScrollKey.self] = newValue }
    }
}

// MARK: - Monatskarte mit Wischen (Paging) und Scrubbing über die Balken

enum KBCardSpace {
    static let name = "kbMonthCard"
    static var space: NamedCoordinateSpace { .named(name) }
}

struct KBScrubFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let n = nextValue()
        if n != .zero { value = n }
    }
}

extension View {
    /// Markiert Balken und Monatslabels als Bereich für Scrubbing und Antippen.
    func kbScrubArea() -> some View {
        background(
            GeometryReader { g in
                Color.clear.preference(key: KBScrubFrameKey.self, value: g.frame(in: KBCardSpace.space))
            }
        )
    }

    /// VoiceOver: Monat mit Wischen nach oben/unten wechseln
    func kbMonthAdjustable(_ model: AppModel, label: String, value: String) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: label))
            .accessibilityValue(Text(verbatim: value))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: KBMonthNav.shift(model, 1)
                case .decrement: KBMonthNav.shift(model, -1)
                @unknown default: break
                }
            }
    }

    /// Breite wie Web `.wrap` (580 inkl. Seitenrand), mittig
    func kbWrapWidth() -> some View {
        frame(maxWidth: KBM.wrapWidth).frame(maxWidth: .infinity)
    }

    /// Weisse Fläche mit Rundung (Web `.kcard`, `.mrows2`: 16 pt, ohne Rand)
    func kbSurface(_ radius: CGFloat = KBM.cardRadius) -> some View {
        background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(KColor.surface))
    }
}

private enum KBDragLock { case none, vertical, scrub, page }

/// Weisse Karte des Monats (Web `.kcard`, Innenabstand 14/16). Finger auf den Balken: Monat folgt dem Finger. Sonst zieht die
/// Karte mit, beim Loslassen wechselt sie in den Nachbarmonat (auch über den Jahreswechsel).
struct KBPagingCard<Content: View>: View {
    @Environment(AppModel.self) private var model
    private let content: Content
    @State private var dragX: CGFloat = 0
    @State private var lock: KBDragLock = .none
    @State private var gestureStart: CGPoint?
    @State private var scrubFrame: CGRect = .zero
    @State private var cardWidth: CGFloat = 320
    /// Haptik nur bei Monatswechsel durch Finger (Scrubbing, Antippen, Wischen)
    @State private var feedbackTick = 0
    /// Geste läuft; setzt sich auch bei vom System abgebrochener Geste zurück (dann fehlt `onEnded`)
    @GestureState private var gestureActive = false
    /// Monatswechsel-Animation läuft (Wischen dann ignorieren, sonst springt die Karte)
    @State private var paging = false

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kbSurface()
            .coordinateSpace(KBCardSpace.space)
            .onPreferenceChange(KBScrubFrameKey.self) { f in scrubFrame = f }
            .background(
                GeometryReader { g in
                    Color.clear
                        .onAppear { cardWidth = g.size.width }
                        .onChange(of: g.size.width) { _, w in cardWidth = w }
                }
            )
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture)
            .simultaneousGesture(tapGesture)
            .offset(x: dragX)
            .opacity(1 - Double(min(abs(dragX) / max(cardWidth, 1), 1)) * 0.45)
            .sensoryFeedback(.selection, trigger: feedbackTick)
            .onChange(of: gestureActive) { _, on in
                if !on { checkCancelled() }
            }
    }

    /// Abgebrochene Geste (Kontrollzentrum, Anruf …): `onEnded` kommt nicht → Karte zurücksetzen (Web `pointercancel`).
    private func checkCancelled() {
        DispatchQueue.main.async {
            guard gestureStart != nil else { return }
            lock = .none
            gestureStart = nil
            if dragX != 0 && !paging {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) { dragX = 0 }
            }
        }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture(coordinateSpace: KBCardSpace.space)
            .onEnded { v in
                guard scrubFrame.width > 0, scrubFrame.contains(v.location) else { return }
                if KBMonthNav.select(model, month: index(at: v.location.x) + 1) { feedbackTick += 1 }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: KBCardSpace.space)
            .updating($gestureActive) { _, st, _ in st = true }
            .onChanged { v in dragChanged(v) }
            .onEnded { v in dragEnded(v) }
    }

    private func index(at x: CGFloat) -> Int {
        guard scrubFrame.width > 0 else { return KBMonthNav.month(model) - 1 }
        let i = Int(((x - scrubFrame.minX) / scrubFrame.width * 12).rounded(.down))
        return min(11, max(0, i))
    }

    private func dragChanged(_ v: DragGesture.Value) {
        if gestureStart != v.startLocation {
            // neue Geste (falls die vorige ohne Ende abgebrochen wurde)
            gestureStart = v.startLocation
            lock = .none
        }
        if lock == .none {
            let dx = v.translation.width
            let dy = v.translation.height
            if abs(dy) > abs(dx) {
                lock = .vertical
                return
            }
            lock = (scrubFrame.width > 0 && scrubFrame.contains(v.startLocation)) ? .scrub : .page
        }
        switch lock {
        case .scrub:
            if KBMonthNav.select(model, month: index(at: v.location.x) + 1) { feedbackTick += 1 }
        case .page:
            if !paging { dragX = v.translation.width }
        case .vertical, .none:
            break
        }
    }

    private func dragEnded(_ v: DragGesture.Value) {
        let l = lock
        lock = .none
        gestureStart = nil
        guard l == .page, !paging else {
            if dragX != 0 && !paging { withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) { dragX = 0 } }
            return
        }
        let w = max(cardWidth, 1)
        let dx = v.translation.width
        let fling = v.predictedEndTranslation.width - dx
        let fast = abs(dx) > 30 && abs(fling) > 80 && (fling < 0) == (dx < 0)
        let go = abs(dx) > w * 0.22 || fast
        let step = dx < 0 ? 1 : -1
        guard go, KBMonthNav.canShift(model, step) else {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) { dragX = 0 }
            return
        }
        withAnimation(.easeIn(duration: 0.16)) { dragX = step > 0 ? -w : w }
        let m = model
        paging = true
        Task { @MainActor in
            defer { paging = false }
            try? await Task.sleep(nanoseconds: 150_000_000)
            KBMonthNav.shift(m, step)
            feedbackTick += 1
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { dragX = step > 0 ? w * 0.3 : -w * 0.3 }
            try? await Task.sleep(nanoseconds: 16_000_000)
            withAnimation(.easeOut(duration: 0.28)) { dragX = 0 }
        }
    }
}

// MARK: - Teile der Monatskarte

/// Kopf der Monatskarte: «Oktober 2026» (11 px Semibold, ohne Versalien seit v166) | Filter (12 px)
struct KBCardHeader: View {
    let year: Int
    let month: Int
    var trailing: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: Format.monthNames[month - 1] + " " + String(year))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(KColor.ink2)
                .lineLimit(1)
            Spacer(minLength: 0)
            if !trailing.isEmpty {
                Text(verbatim: trailing)
                    .font(.system(size: 12))
                    .foregroundStyle(KColor.ink3)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, KBM.pad(15.95, 11))
    }
}

/// Grosse Zahl in Serif mit kleinen Nachkommastellen und Währung («2’759.07 CHF», Web `.kbig`)
struct KBBigAmount: View {
    let value: Double
    let currency: String
    /// rot (negativ verfügbar im Budget)
    var alert: Bool = false
    /// Minuszeichen vor dem Betrag (Budget)
    var signed: Bool = false

    var body: some View {
        let s = Format.money(signed ? abs(value) : value, Currency(rawValue: currency))
        let parts = KBBigAmount.split(s)
        let sign = signed && value < 0 ? Format.minus : ""
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            (Text(verbatim: sign + parts.0)
                .font(KFont.serif(40, .medium))
                .foregroundStyle(alert ? KColor.alert : KColor.ink)
             + Text(verbatim: parts.1)
                .font(KFont.serif(22, .semibold))
                .foregroundStyle(alert ? KColor.alert : KColor.ink2))
                .tracking(-0.4)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(verbatim: currency)
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.26)
                .foregroundStyle(KColor.ink3)
                .padding(.leading, 8)
        }
        .frame(height: 40)
        .padding(.top, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: sign + s + " " + currency))
    }

    static func split(_ s: String) -> (String, String) {
        if s.contains(".") || s.contains(",") { let p = Format.decimalSplit(s); return (p.whole, p.fraction) }
        return (s, "")
    }
}

/// Vergleich mit dem Vorjahresmonat (Web `.kvs`): Text immer Tinte 2, Pfeil Messing auf Grün/Warn 16 %
struct KBCompareLine: View {
    let text: String
    let arrow: String?
    /// Kreisfläche: grün (weniger Kosten / mehr verfügbar), warn, sonst versenkt
    let tone: Calc.Trend

    var body: some View {
        HStack(spacing: 7) {
            if let a = arrow {
                Text(verbatim: a)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(KColor.brass)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(fill))
                    .accessibilityHidden(true)
            }
            Text(verbatim: text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(KColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Web `.kvs`: 13/18.85, margin-top 11
        .frame(minHeight: 18.85)
        .padding(.top, 11)
    }

    private var fill: Color {
        switch tone {
        case .down: return KColor.ok.opacity(0.16)
        case .up: return KColor.warn.opacity(0.16)
        case .same: return KColor.sunken
        }
    }
}

/// Zelle «Bezeichnung / Betrag» (Web `.kc`): 11.5 px Tinte 3, Betrag Serif 17
struct KBStatCell: View {
    let label: String
    let value: String
    var trailing: Bool = false
    var dot: Color? = nil
    var check: Bool = false
    /// blass (Wert < 0.005, Web `.kc.nil`)
    var muted: Bool = false
    var valueColor: Color? = nil

    var body: some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 4) {
            HStack(spacing: 0) {
                if let d = dot { Circle().fill(d).frame(width: 8, height: 8).padding(.trailing, 6) }
                Text(verbatim: label)
                if check {
                    Text(verbatim: "✓").fontWeight(.heavy).foregroundStyle(KColor.ok).padding(.leading, 5)
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(KColor.ink3)
            .lineLimit(1)
            .padding(.vertical, KBM.pad(16.675, 11.5))
            // Zeilenhöhe 24.65 fest (Serif hat andere Masse als SF, KBM.pad passt nur für SF)
            Text(verbatim: value)
                .font(KFont.serif(17, .medium))
                .tracking(-0.17)
                .foregroundStyle(muted ? KColor.ink3 : (valueColor ?? KColor.ink))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 24.65)
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Zeile mit Trennlinie oben (Web `.krow`: margin 18, padding 14, 2 Spalten mit 12 pt Abstand)
struct KBCardRow<Content: View>: View {
    var top: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(KColor.line).frame(height: 1)
            content.padding(.top, 14)
        }
        .padding(.top, top)
    }
}

/// Monatsnamen unter dem Diagramm (Web `.mlabels`): gewählter in Akzentfarbe 800, aktueller Monat mit Punkt
struct KBMonthLabels: View {
    let year: Int
    let selected: Int
    let today: Day

    var body: some View {
        HStack(alignment: .top, spacing: 3) {
            ForEach(0..<12, id: \.self) { i in
                let on = i + 1 == selected
                VStack(spacing: 3) {
                    Text(verbatim: Format.monthShort[i])
                        .font(.system(size: 11, weight: on ? .heavy : .regular))
                        .foregroundStyle(on ? KColor.teal : KColor.ink3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(height: 15.95)
                    Circle()
                        .fill(KColor.teal)
                        .frame(width: 4, height: 4)
                        .opacity(year == today.year && i + 1 == today.month ? 1 : 0)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 26.9, alignment: .top)
            }
        }
        .padding(.top, 7)
    }
}

/// «Ø» gestrichelte Linie mit Beschriftung rechts (Web `.kcard .avg`)
struct KBAverageLine: View {
    /// 0…1 von unten
    let fraction: CGFloat

    var body: some View {
        GeometryReader { g in
            let y = g.size.height * (1 - fraction)
            Path { p in
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: g.size.width, y: y))
            }
            .stroke(KColor.ink2, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .opacity(0.8)
            Text(verbatim: "Ø")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(KColor.ink3)
                .fixedSize()
                .position(x: g.size.width + 8 + 3.9, y: y)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Listen und Kopfzeilen

/// Gruppenkopf (Web `.grp` 20 pt oben + `.grphead` 12 px): links Titel Semibold Tinte, rechts Tinte 2
struct KBGroupHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(verbatim: title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(KColor.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, KBM.pad(17.4, 12))
        .padding(.top, 20)
        .padding(.bottom, 6)
    }
}

extension KBGroupHeader where Trailing == Text {
    init(title: String, amount: String) {
        self.title = title
        self.trailing = Text(verbatim: amount).font(.system(size: 12).monospacedDigit()).foregroundStyle(KColor.ink2)
    }
}

/// Weisser Listenblock (Web `.mrows2`: 16 pt Rundung, 14 pt Innenrand; `.ilist`: 13 pt, ohne Innenrand)
struct KBListBlock<Content: View>: View {
    var horizontal: CGFloat = 14
    var radius: CGFloat = KBM.cardRadius
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kbSurface(radius)
    }
}

/// Trennlinie zwischen Zeilen (1 px Linie)
struct KBRowDivider: View {
    var body: some View {
        Rectangle().fill(KColor.line).frame(height: 1)
    }
}

/// Winkel der Web-App (Rahmen rechts/unten um 45° gedreht, `.tfold i`)
struct KBChevronDown: View {
    var expanded: Bool
    var color: Color = KColor.ink3

    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addLine(to: CGPoint(x: 5.66, y: 5.66))
            p.addLine(to: CGPoint(x: 11.31, y: 0))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .butt, lineJoin: .miter))
        .frame(width: 11.31, height: 5.66)
        .rotationEffect(.degrees(expanded ? 180 : 0))
        .padding(.trailing, 6)
    }
}

/// Auf-/Zuklappen («Bereits bezahlt (3)», «Alle 9 anzeigen», Web `.tfold.pfold`)
struct KBFoldButton: View {
    let title: String
    let expanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(verbatim: title).font(.system(size: 14)).foregroundStyle(KColor.ink2)
                Spacer()
                KBChevronDown(expanded: expanded)
            }
            .padding(.vertical, 12 + KBM.pad(20.3, 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(expanded ? Text("aufgeklappt") : Text("zugeklappt"))
    }
}

/// Umschalter «Datum | Betrag» (Web `.pseg.msort`)
struct KBSegment: View {
    let options: [String]
    @Binding var selected: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, t in
                let on = i == selected
                Button {
                    selected = i
                } label: {
                    Text(verbatim: t)
                        .font(.system(size: 11, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? KColor.ink : KColor.ink2)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6 + KBM.pad(15.95, 11))
                        .background(Capsule().fill(on ? KColor.surface : .clear)
                            .shadow(color: .black.opacity(on ? 0.1 : 0), radius: 1, y: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(KColor.sunken))
        .fixedSize()
    }
}

// MARK: - Filter-Bedienelemente

/// Auswahlknopf (Web `.fsel`): 36 pt hoch, Rundung 10, 12.5 px; gewählt Messing mit weisser Schrift
struct KBSelectButton: View {
    let title: String
    let isOn: Bool
    var chevron: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            KBSelectLabel(title: title, isOn: isOn, chevron: chevron)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct KBSelectLabel: View {
    let title: String
    let isOn: Bool
    var chevron: Bool = true

    var body: some View {
        HStack(spacing: 5) {
            Text(verbatim: title)
                .font(.system(size: 12.5, weight: isOn ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
            if chevron {
                // Web `.fsel::after`: Winkel 6 × 6, Strich 1.5
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 4.24, y: 4.24)); p.addLine(to: CGPoint(x: 8.49, y: 0))
                }
                .stroke(style: StrokeStyle(lineWidth: 1.5))
                .frame(width: 8.49, height: 4.24)
                .padding(.top, -1)
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, 9)
        .frame(maxWidth: .infinity)
        .frame(height: 36.125)
        .foregroundStyle(isOn ? Color.white : KColor.ink2)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isOn ? KColor.tealFill : KColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(isOn ? KColor.teal : KColor.line, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Runder «×»-Knopf zum Zurücksetzen (Web `.fclr`)
struct KBClearButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        KBRoundButton(fill: KColor.surface, action: action) {
            Text(verbatim: "×").font(.system(size: 19)).padding(.bottom, 2)
        }
        .accessibilityLabel(Text(verbatim: label))
    }
}

/// Personen-Chip mit gleicher Breite (Web `.fsel.fh`)
struct KBPersonChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            KBSelectLabel(title: title, isOn: isOn, chevron: false)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Hilfen

extension Day {
    /// Für DatePicker
    var kbDate: Date { date() }
}

extension Calc.Trend {
    /// Pfeil des Vorjahresvergleichs (kein Pfeil bei «gleich wie»)
    var kbArrow: String? {
        switch self {
        case .up: return "↑"
        case .down: return "↓"
        case .same: return nil
        }
    }
}
