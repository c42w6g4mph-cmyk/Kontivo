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
        NavigationStack {
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
            .background(KColor.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schliessen") { dismiss() }
                        .accessibilityIdentifier("incomeDetail.close")
                }
                ToolbarItem(placement: .principal) {
                    Text(verbatim: model.data.income(incomeID)?.title ?? "")
                        .font(.headline)
                        .lineLimit(1)
                        .opacity(scrolled ? 1 : 0)
                        .animation(.easeInOut(duration: 0.15), value: scrolled)
                        .accessibilityHidden(!scrolled)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if model.data.income(incomeID) != nil {
                        actionsMenu
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bearbeiten") {
                        model.present(.incomeForm(incomeID))
                    }
                    .disabled(model.data.income(incomeID) == nil)
                    .accessibilityIdentifier("incomeDetail.edit")
                }
            }
        }
        .alert("Einnahme löschen?", isPresented: $askDelete) {
            Button("Löschen", role: .destructive) { delete() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(verbatim: "«" + deleteName + "» wird endgültig gelöscht.")
        }
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
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                } else {
                    Color.clear.frame(height: 10)
                }
                KBIncomeKeyFigures(income: i, info: info, home: calc.home)
                SectionHead(title: "Einnahme")
                if let ch = calc.priceChart(i) {
                    KBIncomeChart(chart: ch)
                        .padding(.bottom, 8)
                }
                if !info.rows.isEmpty {
                    KCard {
                        ForEach(Array(info.rows.enumerated()), id: \.offset) { k, r in
                            if k > 0 { Divider().padding(.leading, 14) }
                            KBIncomeDetailRow(row: r)
                        }
                    }
                    .accessibilityIdentifier("incomeDetail.rows")
                }
                if !i.note.isEmpty {
                    SectionHead(title: "Notiz")
                    Text(verbatim: i.note)
                        .font(.body)
                        .foregroundStyle(KColor.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: KMetric.radius, style: .continuous).fill(KColor.surface))
                }
            }
            .padding(.horizontal, KMetric.gutter)
            .padding(.bottom, 32)
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
        HStack(alignment: .center, spacing: 14) {
            MarkView(income: i, size: 76)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: info.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(KColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !info.subtitle.isEmpty {
                    Text(verbatim: info.subtitle)
                        .font(.footnote)
                        .foregroundStyle(KColor.ink2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
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
            Image(systemName: "ellipsis.circle")
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
                .font(.subheadline)
                .foregroundStyle(KColor.ink2)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: row.value)
                    .font(.body)
                    .foregroundStyle(KColor.ink)
                    .multilineTextAlignment(.trailing)
                if !row.sub.isEmpty {
                    Text(verbatim: row.sub)
                        .font(.caption)
                        .foregroundStyle(KColor.ink3)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .accessibilityElement(children: .combine)
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
                    .font(.caption.weight(.medium))
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
                                Capsule().fill(KColor.ok)
                                    .frame(width: g.size.width * CGFloat(max(2, min(100, pc))) / 100)
                            }
                        }
                        .frame(height: 6)
                        .padding(.top, 7)
                        .accessibilityHidden(true)
                        Text(verbatim: "\(pc) % deiner Einnahmen")
                            .font(.caption).foregroundStyle(KColor.ink2)
                            .padding(.top, 3)
                    } else if let n = info.note {
                        Text(verbatim: n)
                            .font(.caption).foregroundStyle(KColor.ink2)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(KColor.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        return (Text(verbatim: parts.whole).font(.system(size: 34, weight: .bold))
            + Text(verbatim: parts.fraction).font(.system(size: 19, weight: .semibold))
            + Text(verbatim: " " + currency.rawValue).font(.caption.weight(.semibold)).foregroundStyle(KColor.ink2))
            .foregroundStyle(KColor.ink)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func tile(_ label: String, value: String, currency: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: label)
                .font(.caption.weight(.medium))
                .foregroundStyle(KColor.ink2)
            (Text(verbatim: value).font(.system(size: 20, weight: .bold))
                + Text(verbatim: currency.isEmpty ? "" : " " + currency).font(.caption.weight(.semibold)).foregroundStyle(KColor.ink2))
                .foregroundStyle(KColor.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(KColor.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
