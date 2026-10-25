import SwiftUI
import KontivoCore

// MARK: - Filterleiste «Kosten» in einer Zeile (Web v235 `statFilterBar`, v234 Kostenart)

/// Blätter der Filterleiste
enum KBCostSheet: Identifiable, Hashable {
    /// Werteliste (Kategorie, Vertragspartner, Person)
    case pick(Calc.FilterDimension)
    /// «Filter»: Kategorie und Vertragspartner
    case filter
    /// «Kostenart»: Alle Kosten · Fixkosten · Variable Kosten
    case kind

    var id: String {
        switch self {
        case .pick(let d): return "pick-" + d.rawValue
        case .filter: return "filter"
        case .kind: return "kind"
        }
    }
}

/// Personen als Segment (Alle · Sinan · Lara), Knopf «Kostenart» (nur mit variablen Kosten) und Filter-Symbol;
/// aktive Kategorie-/Vertragspartnerfilter darunter als Etiketten mit «×».
struct KBCostFilterRow: View {
    @Environment(AppModel.self) private var model
    @Binding var sheet: KBCostSheet?

    var body: some View {
        let calc = model.calc
        let f = model.costFilter
        let kind = calc.costKind
        let hasVars = calc.hasVariableCosts
        let persons = calc.kbCostPersons(filterPerson: f.person)
        let nOther = (f.category != nil ? 1 : 0) + (f.partner != nil ? 1 : 0)
        let namer = KBHolderNamer(names: persons.map(\.name), width: !hasVars ? 300 : (kind == .fix ? 200 : 170))
        let seg = persons.count >= 2 && namer.ok
        let segItems: [(id: UUID?, title: String)] = [(id: nil, title: "Alle")] + persons.map { (id: Optional($0.id), title: namer.display($0.name)) }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                if seg {
                    KCPersonSegment(items: segItems, selected: f.person) {
                        model.costFilter.person = $0
                    }
                    .frame(maxWidth: .infinity)
                } else if persons.count >= 2 {
                    holderSelect(f)
                }
                if hasVars {
                    kindButton(kind)
                        .frame(maxWidth: seg ? nil : .infinity)
                        .fixedSize(horizontal: seg, vertical: false)
                }
                filterButton(n: kind == .variable ? 0 : nOther, disabled: kind == .variable)
            }
            .padding(.top, 12)
            if nOther > 0 && kind != .variable {
                tagBar(f)
            }
        }
    }

    /// Auswahlknopf «Alle Personen» bzw. Name, wenn die Namen nicht ins Segment passen
    private func holderSelect(_ f: Calc.CostFilter) -> some View {
        let name = f.person.flatMap { model.data.person($0)?.name } ?? ""
        let shown = name.utf16.count > 12 ? Format.firstName(name) : name
        return KBSelectButton(title: shown.isEmpty ? "Alle Personen" : shown, isOn: f.person != nil) {
            sheet = .pick(.holder)
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("costs.filter.holder")
    }

    /// Knopf «Kostenart» (Web `.fsel.kbtn`): gewählt (nicht Fixkosten) Messing
    private func kindButton(_ kind: CostKind) -> some View {
        Button {
            sheet = .kind
        } label: {
            KBSelectLabel(title: kind.title, isOn: kind != .fix)
                .padding(.horizontal, 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Kostenart")
        .accessibilityValue(Text(verbatim: kind.title))
        .accessibilityIdentifier("costs.kind")
    }

    /// Filter-Symbol (Web `.ficon`, 40 × 38) mit Zähler; bei variablen Kosten gesperrt
    private func filterButton(n: Int, disabled: Bool) -> some View {
        Button {
            if disabled {
                model.toast("Bei variablen Kosten gibt es keine Kategorie und keinen Vertragspartner")
                return
            }
            sheet = .filter
        } label: {
            KBFilterGlyph()
                .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .frame(width: 17, height: 17)
                .foregroundStyle(n > 0 ? KColor.onBrass : KColor.ink2)
                .frame(width: 40, height: 38)
                .background(Capsule().fill(n > 0 ? KColor.tealFill : KColor.surface))
                .overlay(Capsule().strokeBorder(n > 0 ? KColor.teal : KColor.line, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if n > 0 {
                        Text(verbatim: String(n))
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(KColor.paper)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(Capsule().fill(KColor.ink))
                            .offset(x: 4, y: -4)
                    }
                }
                .opacity(disabled ? 0.35 : 1)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Filter Kategorie und Vertragspartner")
        .accessibilityValue(Text(verbatim: n > 0 ? String(n) + " aktiv" : ""))
        .accessibilityIdentifier("costs.filter.more")
    }

    /// Aktive Filter als Etiketten (Web `.ftag`): antippen entfernt den Filter
    private func tagBar(_ f: Calc.CostFilter) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let c = f.category {
                    tag(c) { model.costFilter.category = nil }
                        .accessibilityIdentifier("costs.tag.category")
                }
                if let p = f.partner {
                    tag(p) { model.costFilter.partner = nil }
                        .accessibilityIdentifier("costs.tag.partner")
                }
            }
            .padding(.horizontal, KBM.side)
            .padding(.vertical, 2)
        }
        .padding(.horizontal, -KBM.side)
        .padding(.top, 10)
    }

    private func tag(_ t: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 6) {
                Text(verbatim: t)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(verbatim: "×").font(.system(size: 16))
            }
            .foregroundStyle(KColor.teal)
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: 170)
            .background(Capsule().fill(KColor.teal.opacity(0.12)))
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "Filter " + t + " entfernen"))
    }
}

/// Personen-Segment (Web `.pseg2`): versenkte Kapsel, gewählter Teil weiss mit Schatten
struct KCPersonSegment: View {
    let items: [(id: UUID?, title: String)]
    let selected: UUID?
    let select: (UUID?) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                let on = it.id == selected
                Button {
                    select(it.id)
                } label: {
                    Text(verbatim: it.title)
                        .font(.system(size: 13.5, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? KColor.ink : KColor.ink2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)
                        .frame(height: 33.6)
                        .background(Capsule().fill(on ? KColor.surface : .clear)
                            .shadow(color: .black.opacity(on ? 0.08 : 0), radius: 1, y: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("costs.person." + it.title)
            }
        }
        .padding(3)
        .background(Capsule().fill(KColor.sunken))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Personen")
    }
}

// MARK: - Blätter «Filter» und «Kostenart» (Web `openStatFilter`, `openKArt`)

/// Kopf wie Web `#sheetPick`: Titel 22 px, rechts «×»
struct KBPickHeader: View {
    let title: String
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Text(verbatim: title)
                .font(KFont.title(22))
                .tracking(-0.264)
                .foregroundStyle(KColor.ink)
                .padding(.top, 2)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: close) {
                Text(verbatim: "×")
                    .font(.system(size: 22))
                    .foregroundStyle(KColor.ink2)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(KColor.sunken))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Schliessen")
        }
    }
}

/// «Filter»: Kategorie und Vertragspartner; Antippen öffnet die Werteliste im selben Blatt.
struct KBCostFilterSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var dim: Calc.FilterDimension?

    var body: some View {
        if let d = dim {
            KBFilterPickSheet(dim: d)
        } else {
            menu
        }
    }

    private var menu: some View {
        let f = model.costFilter
        return ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                KBPickHeader(title: "Filter") { dismiss() }
                    .padding(.bottom, 6)
                row("Kategorie", value: f.category, id: "category") { dim = .category }
                row("Vertragspartner", value: f.partner, id: "partner") { dim = .partner }
                if f.category != nil || f.partner != nil {
                    Button {
                        var nf = model.costFilter
                        nf.category = nil
                        nf.partner = nil
                        model.costFilter = nf
                        dismiss()
                    } label: {
                        Text("Filter zurücksetzen")
                            .font(.system(size: 16))
                            .foregroundStyle(KColor.alert)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13 + KBM.pad(23.2, 16))
                            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(KColor.field))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("costs.filter.reset")
                }
                if model.calc.costKind == .all {
                    Text("Variable Kosten haben keine Kategorie und keinen Vertragspartner. Mit Filter zählen nur die Verträge.")
                        .font(.system(size: 12))
                        .foregroundStyle(KColor.ink3)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, KBM.side)
            .padding(.top, 20)
            .padding(.bottom, 18)
        }
        .background(KColor.paper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ t: String, value: String?, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(verbatim: t)
                    .font(.system(size: 16))
                    .foregroundStyle(KColor.ink)
                Spacer(minLength: 8)
                Text(verbatim: (value ?? "Alle") + " ›")
                    .font(.system(size: 12.5))
                    .foregroundStyle(KColor.ink3)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13 + KBM.pad(23.2, 16))
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(KColor.field))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("costs.filter." + id)
    }
}

/// «Kostenart» (Web `KART`): gewählte Zeile Messing; wird in den Einstellungen gespeichert (`settings.kArt`).
struct KBCostKindSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Nach dem Wechsel (Monatswahl anpassen)
    var changed: () -> Void = {}

    var body: some View {
        let cur = model.calc.costKind
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                KBPickHeader(title: "Kostenart") { dismiss() }
                    .padding(.bottom, 6)
                ForEach([CostKind.all, .fix, .variable], id: \.self) { k in
                    let on = k == cur
                    Button {
                        _ = model.update { $0.settings.costKind = k }
                        changed()
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: k.title)
                                .font(.system(size: 16, weight: on ? .semibold : .regular))
                            Text(verbatim: k.subtitle)
                                .font(.system(size: 12.5))
                                .opacity(0.7)
                        }
                        .foregroundStyle(on ? Color.white : KColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(on ? KColor.tealFill : KColor.field))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("costs.kind." + k.rawValue)
                }
            }
            .padding(.horizontal, KBM.side)
            .padding(.top, 20)
            .padding(.bottom, 18)
        }
        .background(KColor.paper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
