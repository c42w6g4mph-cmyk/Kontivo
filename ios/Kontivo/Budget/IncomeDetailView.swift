import SwiftUI
import KontivoCore

/// Einnahme ansehen (Web v155 `openIncDetail`) – wie die Vertragsansicht: Kopf mit Logo, Pille («Beendet am …» / «Ab …»),
/// Kachel «pro Monat» mit Anteil an allen Einnahmen (Balken grün), «pro Jahr», «nächste Zahlung», Abschnitt «Einnahme» mit
/// Verlauf («mehr/weniger») und Angaben, Notiz. «Bearbeiten» öffnet das Formular, Menü ••• Duplizieren / Löschen.
/// Regeln und Texte: `Calc.incomeDetail(_:)`, `Calc.priceChart(_ i: Income)`.
struct IncomeDetailView: View {
    let incomeID: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var askDelete = false
    @State private var scrolled = false
    /// Löschen/Duplizieren läuft (Doppeltippen)
    @State private var closed = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Group {
                if let i = model.data.income(incomeID) {
                    content(i)
                } else {
                    Text("Diese Einnahme existiert nicht mehr.")
                        .font(.subheadline)
                        .foregroundStyle(KColor.ink2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(KColor.paper.ignoresSafeArea())
        .alert("Einnahme löschen?", isPresented: $askDelete) {
            Button("Löschen", role: .destructive) { delete() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(verbatim: "«" + deleteName + "» wird endgültig gelöscht.")
        }
    }

    /// Web `.shbar`: «Schliessen» | Titel (erscheint beim Scrollen) | ••• | «Bearbeiten»
    private var topBar: some View {
        ZStack {
            Text(verbatim: model.data.income(incomeID)?.title ?? "")
                .font(KFont.title(18))
                .tracking(-0.216)
                .foregroundStyle(KColor.ink)
                .lineLimit(1)
                .padding(.horizontal, 100)
                .opacity(scrolled ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: scrolled)
                .accessibilityHidden(!scrolled)
            HStack(spacing: 10) {
                Button("Schliessen") { dismiss() }
                    .font(.system(size: 16))
                    .foregroundStyle(KColor.ink2)
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("incomeDetail.close")
                Spacer()
                if model.data.income(incomeID) != nil {
                    actionsMenu
                }
                Button("Bearbeiten") {
                    model.present(.incomeForm(incomeID))
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(KColor.teal)
                .padding(.vertical, 6)
                .disabled(model.data.income(incomeID) == nil)
                .accessibilityIdentifier("incomeDetail.edit")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, KBM.side)
        .padding(.top, 6 + 14)
        .padding(.bottom, 10)
        .background(KColor.surface.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Rectangle().fill(KColor.line).frame(height: 1) }
    }

    // MARK: Inhalt

    private func content(_ i: Income) -> some View {
        let calc = model.calc
        let info = calc.incomeDetail(i)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(i, info: info)
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: KBIncomeScrollKey.self, value: g.frame(in: .named("incDetail")).minY)
                        }
                    )
                if let p = info.pill {
                    HStack {
                        Pill(text: p, tone: .neutral)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                } else {
                    Color.clear.frame(height: 6 + 10)
                }
                KBIncomeKeyFigures(income: i, info: info, home: calc.home)
                    .padding(.bottom, 12)
                KBDetailSection("Einnahme")
                if let ch = calc.priceChart(i) {
                    KBIncomeChart(chart: ch)
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                }
                if !info.rows.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(info.rows.enumerated()), id: \.offset) { k, r in
                            if k > 0 { KBRowDivider() }
                            KBIncomeDetailRow(row: r)
                        }
                    }
                    .padding(.horizontal, 13)
                    .kbSurface()
                    .accessibilityIdentifier("incomeDetail.rows")
                }
                if !i.note.isEmpty {
                    KBDetailSection("Notiz")
                    Text(verbatim: i.note)
                        .font(.system(size: 14.5))
                        .foregroundStyle(KColor.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, KBM.side)
            .padding(.bottom, 18)
            .kContentWidth()
        }
        .coordinateSpace(name: "incDetail")
        .onPreferenceChange(KBIncomeScrollKey.self) { y in
            let s = y < -60
            if s != scrolled { scrolled = s }
        }
        .accessibilityIdentifier("incomeDetail")
    }

    private func header(_ i: Income, info: IncomeDetailInfo) -> some View {
        HStack(alignment: .center, spacing: 15) {
            MarkView(income: i, size: 76)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: info.title)
                    .font(KFont.title(22))
                    .tracking(-0.264)
                    .foregroundStyle(KColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !info.subtitle.isEmpty {
                    Text(verbatim: info.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(KColor.ink2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.top, 14)
    }

    // MARK: Menü ••• (Web: Duplizieren, Löschen)

    private var actionsMenu: some View {
        Menu {
            Button {
                duplicate()
            } label: {
                Label("Duplizieren", systemImage: "plus.square.on.square")
            }
            Button(role: .destructive) {
                askDelete = true
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        } label: {
            // Web `.dmbtn`: 34 pt Kreis versenkt, drei Punkte in Akzentfarbe
            HStack(spacing: 3.6) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(KColor.teal).frame(width: 3.6, height: 3.6) }
            }
            .frame(width: 34, height: 34)
            .background(Circle().fill(KColor.sunken))
            .accessibilityLabel("Aktionen")
        }
        .accessibilityIdentifier("incomeDetail.menu")
    }

    private var deleteName: String {
        guard let i = model.data.income(incomeID) else { return "" }
        return i.label.isEmpty ? i.name : i.label
    }

    /// Web: Kopie anlegen, Ansicht schliessen, Formular der Kopie öffnen, Toast «Dupliziert»
    private func duplicate() {
        guard !closed, let i = model.data.income(incomeID) else { return }
        var n = i
        n.id = UUID()
        n.createdAt = Date()
        let today = model.today
        let copy = n
        guard model.update({ d in _ = try d.saveIncome(copy, today: today) }) else { return }
        closed = true
        model.dismissTop()
        model.presentAfterDismiss(.incomeForm(copy.id))
        model.toast("Dupliziert")
    }

    private func delete() {
        guard !closed else { return }
        closed = true
        let id = incomeID
        model.update { $0.deleteIncome(id) }
        model.dismissTop()
        model.toast("Gelöscht")
    }
}

private struct KBIncomeScrollKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Zeile «Zahlung · monatlich am 25.» (Web .dl)
struct KBIncomeDetailRow: View {
    let row: DetailRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: row.label)
                .font(.system(size: 12.5))
                .foregroundStyle(KColor.ink2)
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: row.value)
                    .font(.system(size: 14))
                    .foregroundStyle(KColor.ink)
                    .multilineTextAlignment(.trailing)
                if !row.sub.isEmpty {
                    Text(verbatim: row.sub)
                        .font(.caption)
                        .foregroundStyle(KColor.ink3)
                }
            }
        }
        .padding(.vertical, 11 + KBM.pad(20.3, 14))
        .accessibilityElement(children: .combine)
    }
}

/// Abschnittstitel der Ansicht (Web `h3.dsec`: 12.5 px Semibold Tinte 2, 20 oben, 2 unten)
struct KBDetailSection: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(verbatim: title)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(KColor.ink2)
            .padding(.top, 20)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Kacheln

/// Grosse Kachel «pro Monat» bzw. «einmalig» (Rappen klein, Anteil an allen Einnahmen als grüner Balken, sonst Hinweis wie
/// «netto»), rechts «pro Jahr» (nur wiederkehrend) und «nächste Zahlung» bzw. «am». Beträge in der Einnahmewährung,
/// bei Fremdwährung «≈ … CHF» in der Hauptwährung (Web `openIncDetail` .kz).
struct KBIncomeKeyFigures: View {
    let income: Income
    let info: IncomeDetailInfo
    let home: Currency

    var body: some View {
        let cu = income.currency
        KBRatioRow().callAsFunction {
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: info.mainLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(KColor.ink2)
                VStack(alignment: .leading, spacing: 3) {
                    bigAmount(info.mainAmount, currency: cu)
                    if info.foreign {
                        Text(verbatim: "≈ " + Format.money0(info.mainAmountHome) + " " + home.rawValue)
                            .font(.caption).foregroundStyle(KColor.ink2)
                    }
                    if let pc = info.sharePercent {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(KColor.line)
                                Capsule().fill(KColor.brass)
                                    .frame(width: g.size.width * CGFloat(max(2, min(100, pc))) / 100)
                            }
                        }
                        .frame(height: 6)
                        .padding(.top, 10)
                        .accessibilityHidden(true)
                        Text(verbatim: "\(pc) % deiner Einnahmen")
                            .font(.system(size: 12)).foregroundStyle(KColor.ink2)
                            .padding(.top, 6 - 3)
                    } else if let n = info.note {
                        Text(verbatim: n)
                            .font(.system(size: 12)).foregroundStyle(KColor.ink2)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(KColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("incomeDetail.kz.month")
            VStack(spacing: 8) {
                if let y = info.yearly {
                    tile("pro Jahr", value: Format.money0(y, cu), currency: cu.rawValue)
                }
                tile(info.nextLabel, value: info.nextValue, currency: "")
                    .accessibilityIdentifier("incomeDetail.kz.next")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    /// «7’600» gross, «.00» klein, Währung klein (Web decAt)
    private func bigAmount(_ v: Double, currency: Currency) -> some View {
        let parts = Format.decimalSplit(Format.money(v, currency))
        return (Text(verbatim: parts.whole).font(KFont.serif(34, .medium))
            + Text(verbatim: parts.fraction).font(KFont.serif(18.7, .semibold))
            + Text(verbatim: " " + currency.rawValue).font(.system(size: 12, weight: .semibold)).foregroundStyle(KColor.ink2))
            .tracking(-0.34)
            .foregroundStyle(KColor.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func tile(_ label: String, value: String, currency: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(KColor.ink2)
            (Text(verbatim: value).font(KFont.serif(20, .medium))
                + Text(verbatim: currency.isEmpty ? "" : " " + currency).font(.system(size: 12, weight: .semibold)).foregroundStyle(KColor.ink2))
                .tracking(-0.2)
                .foregroundStyle(KColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(KColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Zwei Spalten im Verhältnis 1.3 : 1 (Web .kz: grosse Kachel flex 1.3, rechte Spalte flex 1)
struct KBRatioRow: Layout {
    var ratio: CGFloat = 1.3
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let w = proposal.width ?? 340
        let (a, b) = widths(w)
        let h = max(subviews[0].sizeThatFits(ProposedViewSize(width: a, height: nil)).height,
                    subviews[1].sizeThatFits(ProposedViewSize(width: b, height: nil)).height)
        return CGSize(width: w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let (a, b) = widths(bounds.width)
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: a, height: bounds.height))
        subviews[1].place(at: CGPoint(x: bounds.minX + a + spacing, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: b, height: bounds.height))
    }

    private func widths(_ w: CGFloat) -> (CGFloat, CGFloat) {
        let avail = max(0, w - spacing)
        let a = (avail * ratio / (ratio + 1)).rounded(.down)
        return (a, avail - a)
    }
}
