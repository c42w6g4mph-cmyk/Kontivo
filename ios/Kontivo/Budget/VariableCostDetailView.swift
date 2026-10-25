import SwiftUI
import KontivoCore

extension MarkView {
    /// Kachel für variable Kosten: eigenes Logo, sonst Symbol in der Farbe des Symbols (Web `varMarkOf`)
    init(variable v: VariableCost, size: CGFloat = 40) {
        self.init(logoID: v.logoID, logoBg: v.logoBg, colorHex: v.icon.colorHex, symbol: "ic.var." + v.icon.rawValue, size: size)
    }

    /// Kachel nur für ein Symbol (Symbolauswahl im Formular)
    init(varIcon ic: VarIcon, size: CGFloat = 40) {
        self.init(logoID: nil, logoBg: nil, colorHex: ic.colorHex, symbol: "ic.var." + ic.rawValue, size: size)
    }
}

/// Variable Kosten ansehen (Web v227 `openVarDetail`): Kopf mit Symbol, Pille («Beendet am …» / «Ab …»), Kachel «pro Monat»
/// mit Anteil an den Einnahmen, «pro Jahr», «Anteil variabel», Angaben, Hinweis. «Bearbeiten» öffnet das Formular,
/// Menü ••• Duplizieren / Löschen. Regeln: `Calc.variableDetail`.
struct VariableCostDetailView: View {
    let variableID: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var askDelete = false
    /// Löschen/Duplizieren läuft (Doppeltippen)
    @State private var closed = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if let v = model.data.variableCost(variableID) {
                content(v)
            } else {
                Text("Dieser Eintrag existiert nicht mehr.")
                    .font(.subheadline)
                    .foregroundStyle(KColor.ink2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(KColor.paper.ignoresSafeArea())
        .alert("Löschen?", isPresented: $askDelete) {
            Button("Löschen", role: .destructive) { delete() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(verbatim: "«" + (model.data.variableCost(variableID)?.title ?? "") + "» wird aus den variablen Kosten entfernt.")
        }
    }

    /// Web `detailBar`: «Schliessen» | ••• | «Bearbeiten»
    private var topBar: some View {
        HStack(spacing: 10) {
            Button("Schliessen") { dismiss() }
                .font(.system(size: 16))
                .foregroundStyle(KColor.ink2)
                .padding(.vertical, 6)
                .accessibilityIdentifier("varDetail.close")
            Spacer()
            if model.data.variableCost(variableID) != nil {
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
                    HStack(spacing: 3.6) {
                        ForEach(0..<3, id: \.self) { _ in Circle().fill(KColor.teal).frame(width: 3.6, height: 3.6) }
                    }
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(KColor.sunken))
                    .accessibilityLabel("Aktionen")
                }
                .accessibilityIdentifier("varDetail.menu")
            }
            Button("Bearbeiten") {
                model.present(.variableForm(variableID))
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(KColor.teal)
            .padding(.vertical, 6)
            .disabled(model.data.variableCost(variableID) == nil)
            .accessibilityIdentifier("varDetail.edit")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, KBM.side)
        .padding(.top, 6 + 14)
        .padding(.bottom, 10)
        .background(KColor.surface.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Rectangle().fill(KColor.line).frame(height: 1) }
    }

    private func content(_ v: VariableCost) -> some View {
        let calc = model.calc
        let info = calc.variableDetail(v)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 15) {
                    MarkView(variable: v, size: 76)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: info.title)
                            .font(KFont.title(22))
                            .tracking(-0.264)
                            .foregroundStyle(KColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Variable Kosten · geschätzt")
                            .font(.system(size: 13))
                            .foregroundStyle(KColor.ink2)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                }
                .padding(.top, 14)
                if let p = info.pill {
                    HStack {
                        Pill(text: p, tone: .neutral)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                } else {
                    Color.clear.frame(height: 10)
                }
                keyFigures(v, info: info, home: calc.home)
                KBDetailSection("Variable Kosten")
                VStack(spacing: 0) {
                    ForEach(Array(info.rows.enumerated()), id: \.offset) { k, r in
                        if k > 0 { KBRowDivider() }
                        KBIncomeDetailRow(row: r)
                    }
                }
                .padding(.horizontal, 13)
                .kbSurface()
                .accessibilityIdentifier("varDetail.rows")
                // Web `.vhint`
                Text("Planwert für schwankende Ausgaben. Kontivo erfasst keine einzelnen Ausgaben.")
                    .font(.system(size: 12.5))
                    .kLineHeight(12.5, 17.5)
                    .foregroundStyle(KColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .padding(.horizontal, 2)
            }
            .padding(.horizontal, KBM.side)
            .padding(.bottom, 18)
            .kContentWidth()
        }
        .accessibilityIdentifier("varDetail")
    }

    /// Web `.kz`: grosse Kachel «pro Monat» (Anteil an den Einnahmen als Balken), rechts «pro Jahr» und «Anteil variabel»
    private func keyFigures(_ v: VariableCost, info: VariableDetailInfo, home: Currency) -> some View {
        let cu = v.currency
        return KBRatioRow().callAsFunction {
            VStack(alignment: .leading, spacing: 0) {
                Text("pro Monat")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(KColor.ink2)
                    .frame(height: 17.4)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 0) {
                    let parts = Format.decimalSplit(Format.money(v.amount, cu))
                    (Text(verbatim: parts.whole).font(KFont.serif(34, .medium))
                        + Text(verbatim: parts.fraction).font(KFont.serif(18.7, .semibold))
                        + Text(verbatim: " " + cu.rawValue).font(.system(size: 12, weight: .semibold)).foregroundStyle(KColor.ink2))
                        .tracking(-0.34)
                        .foregroundStyle(KColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(height: 37.4)
                    if info.foreign {
                        Text(verbatim: "≈ " + Format.money0(info.amountHome) + " " + home.rawValue)
                            .font(.caption).foregroundStyle(KColor.ink2)
                            .padding(.top, 3)
                    }
                    if let pc = info.incomePercent {
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
                            .frame(height: 17.4)
                            .padding(.top, 6)
                    } else {
                        Text("geschätzt")
                            .font(.system(size: 12)).foregroundStyle(KColor.ink2)
                            .frame(minHeight: 17.4)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(KColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("varDetail.kz.month")
            VStack(spacing: 8) {
                tile("pro Jahr", Format.money0(v.amount * 12, cu), cu.rawValue)
                tile("Anteil variabel", info.variablePercent.map { "\($0) %" } ?? "—", "")
                    .accessibilityIdentifier("varDetail.kz.share")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 2)
    }

    /// Web `.kzt`: Bezeichnung 12/17.4, Wert Serif 20
    private func tile(_ label: String, _ value: String, _ currency: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(KColor.ink2)
                .frame(height: 17.4)
            (Text(verbatim: value).font(KFont.serif(20, .medium))
                + Text(verbatim: currency.isEmpty ? "" : " " + currency).font(.system(size: 12, weight: .semibold)).foregroundStyle(KColor.ink2))
                .tracking(-0.2)
                .foregroundStyle(KColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: 22)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(KColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Web: Kopie anlegen, Ansicht schliessen, Formular der Kopie öffnen, Toast «Dupliziert»
    private func duplicate() {
        guard !closed else { return }
        var nid: UUID?
        let id = variableID
        guard model.update({ d in nid = d.duplicateVariableCost(id) }), let n = nid else { return }
        closed = true
        model.dismissTop()
        model.presentAfterDismiss(.variableForm(n))
        model.toast("Dupliziert")
    }

    private func delete() {
        guard !closed else { return }
        closed = true
        let id = variableID
        model.update { $0.deleteVariableCost(id) }
        model.dismissTop()
        model.toast("Gelöscht")
    }
}
