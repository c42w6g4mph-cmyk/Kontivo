import SwiftUI
import KontivoCore

/// Daten für das Fenster «Was dir bleibt» (Web state._fq)
struct BudgetShareInfo: Identifiable, Hashable {
    let percent: Int
    let average: Int?
    let year: Int
    let monthLabel: String
    let personName: String
    let person: UUID?
    /// Einnahmen und Verfügbar des Monats (für «ohne: x %» in den Tipps)
    let income: Double
    let free: Double
    var id: String { "\(year)-\(monthLabel)-\(person?.uuidString ?? "")" }
}

/// «x % der Einnahmen ⓘ» hinter «verfügbar nach Fixkosten»; öffnet die Einordnung. Web: .kfq / openFq
struct KBBudgetSubline: View {
    let bm: Calc.BudgetMonth
    let info: BudgetShareInfo?
    @State private var shown: BudgetShareInfo?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) { base; if info != nil { Text(" · "); link } }
            VStack(alignment: .leading, spacing: 2) { base; if info != nil { link } }
        }
        .font(.footnote)
        .foregroundStyle(KColor.ink3)
        .padding(.top, 6)
        .sheet(item: $shown) { BudgetShareSheet(info: $0) }
    }

    private var base: some View { Text("verfügbar nach Fixkosten").lineLimit(1) }

    @ViewBuilder private var link: some View {
        if let i = info {
            Button { shown = i } label: {
                HStack(spacing: 4) {
                    Text(verbatim: BudgetShare.percentText(i.percent) + " der Einnahmen")
                    Image(systemName: "info.circle")
                }
                .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: BudgetShare.percentText(i.percent) + " der Einnahmen, Einordnung anzeigen"))
            .accessibilityIdentifier("budget.share")
        }
    }
}

/// Fenster «Was dir bleibt»: grosse Zahl, Balken mit üblichem Bereich, Monat (Punkt) und Jahresschnitt (Ring),
/// Einordnung, Richtwert, bei wenig Spielraum «Wo du ansetzen kannst». SwiftUI-Sheet sperrt den Hintergrund und schliesst per Wisch.
struct BudgetShareSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let info: BudgetShareInfo

    var body: some View {
        let range = BudgetShare.range(BudgetShare.land(model.calc.home))
        let level = BudgetShare.level(info.percent, range)
        let head = BudgetShare.headline(level)
        let showAvg = BudgetShare.showAverage(month: info.percent, average: info.average)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(spacing: 2) {
                        Text(verbatim: info.monthLabel + (info.personName.isEmpty ? "" : " · " + info.personName))
                            .font(.subheadline).foregroundStyle(KColor.ink2)
                        Text(verbatim: BudgetShare.percentText(info.percent))
                            .font(.system(size: 34, weight: .semibold, design: .rounded)).foregroundStyle(KColor.ink)
                        Text("deiner Einnahmen bleiben nach den Fixkosten")
                            .font(.subheadline).foregroundStyle(KColor.ink2)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 18)

                    ShareBar(range: range, value: info.percent, average: showAvg ? info.average : nil)

                    VStack(spacing: 4) {
                        Text(verbatim: head.title).font(.body).foregroundStyle(KColor.ink)
                        if let s = head.sub { Text(verbatim: s).font(.subheadline).foregroundStyle(KColor.ink2) }
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: range.note).padding(.vertical, 11)
                        Divider().overlay(KColor.line)
                        Text("Entscheidend ist der Betrag, der dir am Ende bleibt.").padding(.vertical, 11)
                    }
                    .font(.subheadline).foregroundStyle(KColor.ink2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .background(KColor.field, in: RoundedRectangle(cornerRadius: 12))

                    if BudgetShare.showsTips(level) { TipsSection(info: info) }

                    VStack(alignment: .leading, spacing: 3) {
                        if showAvg, let a = info.average {
                            HStack(spacing: 6) {
                                Circle().strokeBorder(KColor.teal, lineWidth: 2).frame(width: 10, height: 10)
                                Text(verbatim: "Jahresschnitt " + String(info.year) + ": " + String(a) + "\u{00A0}%")
                            }
                            .font(.caption.weight(.semibold)).foregroundStyle(KColor.teal)
                            .padding(.bottom, 1)
                        }
                        Text("Richtwerte von Budgetberatungen, keine feste Norm.")
                        Text("Genauigkeit abhängig von deinen erfassten Verträgen.")
                    }
                    .font(.caption).foregroundStyle(KColor.ink3)
                    .padding(.top, 16).padding(.horizontal, 4)
                }
                .padding(.horizontal, KMetric.gutter)
                .padding(.bottom, 24)
            }
            .background(KColor.surface)
            .navigationTitle("Was dir bleibt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").symbolRenderingMode(.hierarchical) }
                        .accessibilityLabel("Schliessen")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// Balken 0–100 % mit üblichem Bereich, Monat als Punkt, Jahresschnitt als Ring (SwiftUI: eigene Form statt Gauge, zwei Marker)
private struct ShareBar: View {
    let range: BudgetShare.Range
    let value: Int
    let average: Int?

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { g in
                let w = g.size.width
                let x: (Int) -> CGFloat = { CGFloat(min(100, max(0, $0))) / 100 * w }
                ZStack(alignment: .leading) {
                    Capsule().fill(KColor.line).frame(height: 10)
                    Capsule().fill(KColor.teal.opacity(0.32))
                        .frame(width: x(range.hi) - x(range.lo), height: 10).offset(x: x(range.lo))
                    if let a = average {
                        Circle().fill(KColor.surface).overlay(Circle().strokeBorder(KColor.teal, lineWidth: 3))
                            .frame(width: 14, height: 14).offset(x: x(a) - 7)
                    }
                    Circle().fill(KColor.ink).overlay(Circle().strokeBorder(KColor.surface, lineWidth: 3))
                        .frame(width: 18, height: 18).offset(x: x(value) - 9)
                }
                .frame(height: 18)
            }
            .frame(height: 18)
            GeometryReader { g in
                let mid = CGFloat(range.lo + range.hi) / 200 * g.size.width
                ZStack(alignment: .leading) {
                    HStack { Text("0\u{00A0}%"); Spacer(); Text("100\u{00A0}%") }
                    Text("üblich").foregroundStyle(KColor.teal).fixedSize().position(x: mid, y: 8)
                }
            }
            .frame(height: 16)
            .font(.caption2).foregroundStyle(KColor.ink3)
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Üblich " + String(range.lo) + " bis " + String(range.hi) + " Prozent, du " + String(value) + " Prozent"))
    }
}

/// «Wo du ansetzen kannst»: grösste Fixkosten, bald kündbare Verträge, Abos
private struct TipsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let info: BudgetShareInfo

    var body: some View {
        let t = BudgetShare.tips(model.calc, person: info.person)
        let home = model.calc.home.rawValue
        if !t.top.isEmpty {
            HStack {
                Text("Wo du ansetzen kannst").fontWeight(.semibold)
                Spacer()
                Text("pro Monat")
            }
            .font(.footnote).foregroundStyle(KColor.ink3)
            .padding(.top, 20).padding(.bottom, 8).padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(t.top.enumerated()), id: \.offset) { i, x in
                    if let c = model.data.contract(x.contractID) {
                        if i > 0 { Divider().overlay(KColor.line) }
                        Button { go { model.present(.contractDetail(c.id)) } } label: {
                            HStack(spacing: 11) {
                                MarkView(contract: c, data: model.data, size: 32)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: model.data.title(of: c)).font(.subheadline.weight(.medium)).foregroundStyle(KColor.ink).lineLimit(1)
                                    if info.income > 0.005 {
                                        ViewThatFits {
                                            Text(verbatim: pct(x.monthly) + "\u{00A0}% der Einnahmen")
                                            Text(verbatim: pct(x.monthly) + "\u{00A0}%")
                                        }
                                        .font(.caption).foregroundStyle(KColor.ink3)
                                    } else if let cat = model.data.category(c.categoryID) {
                                        Text(verbatim: cat.name).font(.caption).foregroundStyle(KColor.ink3)
                                    }
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 1) {
                                    (Text(verbatim: Format.money(x.monthly)).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundColor(KColor.ink)
                                     + Text(verbatim: " " + home).font(.caption2).foregroundColor(KColor.ink3))
                                        .lineLimit(1)
                                    // Anteil ohne diesen Vertrag (Web «ohne: x %»)
                                    if let wo = BudgetShare.withoutPercent(free: info.free, income: info.income, monthly: x.monthly) {
                                        Text(verbatim: "ohne: " + BudgetShare.percentText(wo)).font(.caption2.monospacedDigit()).foregroundStyle(KColor.teal)
                                    }
                                }
                                .layoutPriority(1)
                            }
                            .padding(.vertical, 10).padding(.horizontal, 13).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .background(KColor.field, in: RoundedRectangle(cornerRadius: 12))

            if t.soonCount > 0 || t.aboCount > 0 {
                VStack(spacing: 0) {
                    if t.soonCount > 0 {
                        action(title: String(t.soonCount) + (t.soonCount == 1 ? " Vertrag" : " Verträge") + " bald kündbar",
                               sub: "Frist in den nächsten 3 Monaten") { go { model.tab = .deadlines } }
                    }
                    if t.soonCount > 0 && t.aboCount > 0 { Divider().overlay(KColor.line) }
                    if t.aboCount > 0, let cat = t.aboCategory {
                        action(title: String(t.aboCount) + " Abos: " + Format.money(t.aboMonthly) + " " + home + "/Mt.",
                               sub: "Nutzt du alle noch regelmässig?") {
                            go { model.costFilter = Calc.CostFilter(category: cat); model.tab = .contracts }
                        }
                    }
                }
                .background(KColor.field, in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 8)
            }
        }
    }

    private func pct(_ v: Double) -> String { String(Int(Format.jsRound(v / info.income * 100))) }

    /// Fenster schliessen, danach Ziel öffnen
    private func go(_ then: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.async { then() }
    }

    private func action(title: String, sub: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title).font(.subheadline.weight(.semibold)).foregroundStyle(KColor.ink)
                    Text(verbatim: sub).font(.caption).foregroundStyle(KColor.ink3)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(KColor.ink3)
            }
            .padding(.vertical, 11).padding(.horizontal, 14).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
