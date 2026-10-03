import SwiftUI
import KontivoCore

// Gemeinsame Bausteine der Tabs «Kosten» und «Budget» (Präfix KB = Kosten/Budget).

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
        let ny = model.selectedYear + delta
        model.selectedYear = ny
        model.selectedMonth = ny == now.year ? now.month : 1
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

/// «‹ 2026 ›» in der Navigationsleiste
struct KBYearNav: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let y = model.selectedYear
        let maxed = y >= model.today.year + 5
        HStack(spacing: 6) {
            Button {
                withAnimation(.snappy) { KBMonthNav.changeYear(model, by: -1) }
            } label: {
                Image(systemName: "chevron.left").fontWeight(.semibold)
            }
            .accessibilityLabel("Vorjahr")
            Text(verbatim: String(y))
                .font(.headline.monospacedDigit())
                .foregroundStyle(KColor.ink)
                .accessibilityLabel(Text(verbatim: "Jahr " + String(y)))
            Button {
                withAnimation(.snappy) { KBMonthNav.changeYear(model, by: 1) }
            } label: {
                Image(systemName: "chevron.right").fontWeight(.semibold)
            }
            .disabled(maxed)
            .accessibilityLabel("Folgejahr")
        }
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
}

private enum KBDragLock { case none, vertical, scrub, page }

/// Weisse Karte des Monats. Finger auf den Balken: Monat folgt dem Finger. Sonst zieht die Karte mit,
/// beim Loslassen wechselt sie in den Nachbarmonat (auch über den Jahreswechsel).
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

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        KCard(padding: 18) { content }
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
            dragX = v.translation.width
        case .vertical, .none:
            break
        }
    }

    private func dragEnded(_ v: DragGesture.Value) {
        let l = lock
        lock = .none
        gestureStart = nil
        guard l == .page else {
            if dragX != 0 { withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) { dragX = 0 } }
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
        Task { @MainActor in
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

/// Kopf der Monatskarte: «OKTOBER 2026» | Filter
struct KBCardHeader: View {
    let year: Int
    let month: Int
    var trailing: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: (Format.monthNames[month - 1] + " " + String(year)).uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(KColor.ink3)
                .lineLimit(1)
            Spacer(minLength: 8)
            if !trailing.isEmpty {
                Text(verbatim: trailing)
                    .font(.caption)
                    .foregroundStyle(KColor.ink3)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

/// Grosse Zahl mit kleinen Nachkommastellen und Währung («1’284.50 CHF»)
struct KBBigAmount: View {
    let value: Double
    let currency: String
    /// rot (negativ verfügbar im Budget)
    var alert: Bool = false
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 40

    var body: some View {
        let s = Format.money(value)
        let parts = KBBigAmount.split(s)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            (Text(verbatim: parts.0)
                .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(alert ? KColor.alert : KColor.ink)
             + Text(verbatim: parts.1)
                .font(.system(size: size * 0.55, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(KColor.ink2))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(verbatim: currency)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(KColor.ink3)
        }
        .padding(.top, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: s + " " + currency))
    }

    static func split(_ s: String) -> (String, String) {
        if let k = s.lastIndex(of: ".") { return (String(s[s.startIndex..<k]), String(s[k...])) }
        return (s, "")
    }
}

/// Vergleich mit dem Vorjahresmonat; ohne Pfeil bei «gleich wie»
struct KBCompareLine: View {
    let text: String
    let arrow: String?
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            if let a = arrow {
                Text(verbatim: a)
                    .font(.caption2.weight(.heavy))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(color.opacity(0.16)))
                    .accessibilityHidden(true)
            }
            Text(verbatim: text)
                .font(.footnote.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
        .padding(.top, 11)
    }
}

/// Zelle «Bezeichnung / Betrag» (Bezahlt, Offen, Ø pro Monat …)
struct KBStatCell: View {
    let label: String
    let value: String
    var trailing: Bool = false
    var dot: Color? = nil
    var check: Bool = false
    /// blass (Wert < 0.005)
    var muted: Bool = false
    var valueColor: Color? = nil

    var body: some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let d = dot { Circle().fill(d).frame(width: 8, height: 8) }
                Text(verbatim: label)
                if check {
                    Text(verbatim: "✓").fontWeight(.heavy).foregroundStyle(KColor.ok)
                }
            }
            .font(.caption)
            .foregroundStyle(KColor.ink3)
            .lineLimit(1)
            Text(verbatim: value)
                .font(Font.headline.weight(muted ? .medium : .semibold).monospacedDigit())
                .foregroundStyle(muted ? KColor.ink3 : (valueColor ?? KColor.ink))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Zeile mit Trennlinie oben (krow der Web-App)
struct KBCardRow<Content: View>: View {
    var top: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(KColor.line).frame(height: 0.5)
            content.padding(.top, 14)
        }
        .padding(.top, top)
    }
}

/// Monatsnamen unter dem Diagramm; gewählter fett, aktueller Monat mit Punkt
struct KBMonthLabels: View {
    let year: Int
    let selected: Int
    let today: Day

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { i in
                VStack(spacing: 3) {
                    Text(verbatim: Format.monthShort[i])
                        .font(.caption2.weight(i + 1 == selected ? .bold : .regular))
                        .foregroundStyle(i + 1 == selected ? KColor.ink : KColor.ink3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Circle()
                        .fill(KColor.teal)
                        .frame(width: 4, height: 4)
                        .opacity(year == today.year && i + 1 == today.month ? 1 : 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 7)
    }
}

// MARK: - Listen und Kopfzeilen

/// Gruppenkopf (grphead): links Titel, rechts optional Summe
struct KBGroupHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(verbatim: title)
                .font(.footnote)
                .foregroundStyle(KColor.ink2)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 4)
        .padding(.top, 22)
        .padding(.bottom, 6)
    }
}

extension KBGroupHeader where Trailing == Text {
    init(title: String, amount: String) {
        self.title = title
        self.trailing = Text(verbatim: amount).font(.footnote.monospacedDigit()).foregroundStyle(KColor.ink2)
    }
}

/// Weisser Listenblock mit Rundung (mrows2)
struct KBListBlock<Content: View>: View {
    var horizontal: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: KMetric.radius, style: .continuous).fill(KColor.surface))
            .overlay(RoundedRectangle(cornerRadius: KMetric.radius, style: .continuous).strokeBorder(KColor.line, lineWidth: 0.5))
    }
}

/// Trennlinie zwischen Zeilen
struct KBRowDivider: View {
    var body: some View {
        Rectangle().fill(KColor.line).frame(height: 0.5)
    }
}

/// Auf-/Zuklappen («Bereits bezahlt (3)», «Alle 9 anzeigen»)
struct KBFoldButton: View {
    let title: String
    let expanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(verbatim: title).font(.subheadline).foregroundStyle(KColor.ink2)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KColor.ink3)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(expanded ? Text("aufgeklappt") : Text("zugeklappt"))
    }
}

// MARK: - Filter-Bedienelemente

/// Auswahlknopf (fsel): Wert oder Platzhalter, gewählt in Teal
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
                .font(.subheadline.weight(isOn ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.tail)
            if chevron {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .opacity(0.7)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .foregroundStyle(isOn ? Color.white : KColor.ink)
        .background(Capsule().fill(isOn ? KColor.teal : KColor.surface))
        .overlay(Capsule().strokeBorder(isOn ? KColor.teal : KColor.line, lineWidth: 1))
        .contentShape(Capsule())
    }
}

/// Runder «×»-Knopf zum Zurücksetzen
struct KBClearButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(KColor.ink2)
                .frame(width: 34, height: 34)
                .background(Circle().fill(KColor.sunken))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
    }
}

/// Personen-Chip mit gleicher Breite (fsel fh)
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
