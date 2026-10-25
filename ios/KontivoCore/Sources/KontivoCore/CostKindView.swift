import Foundation

// Tab «Kosten» mit Kostenart (Web v230/v234/v237 `renderStat`, `varGroupHtml`): Fixkosten, variable Kosten (geschätzter
// Planwert pro Monat) oder beides. Variable Kosten haben keine Kategorie und keinen Vertragspartner: mit diesen Filtern
// zählen bei «Alle Kosten» nur die Verträge. Fixkosten-Summen (Kopfzahl, «Entwicklung und Preistreiber») bleiben ohne
// variable Kosten.

extension Calc {
    /// Ein Monat im Tab «Kosten» nach Kostenart (Web `m.fx`, `m.vr`, `m.tt`)
    public struct CostKindMonth: Hashable, Sendable {
        /// Fixkosten (0 bei «Variable Kosten»)
        public var fixed: Double
        /// Variable Kosten (0 bei «Fixkosten» oder mit Kategorie-/Vertragspartnerfilter)
        public var variable: Double
        public var total: Double { fixed + variable }
    }

    /// Jahr im Tab «Kosten» nach Kostenart
    public struct CostKindYear: Hashable, Sendable {
        public var year: Int
        public var kind: CostKind
        /// Variable Kosten zählen (Web `useV`)
        public var usesVariable: Bool
        public var months: [CostKindMonth]
        public var total: Double
        public var maxMonth: Double
        public var average: Double { total / 12 }

        /// Legende unter dem Diagramm (Web `.vleg`): ohne Legende bei «Fixkosten»
        public var legend: [LegendItem] {
            guard kind != .fix, usesVariable else { return [] }
            return (kind == .all ? [.fixed] : []) + [.variable]
        }

        /// «Mit Kategorie- oder Vertragspartnerfilter zählen nur die Verträge.» (nur «Alle Kosten» mit Filter)
        public var filterNote: String? {
            kind == .all && !usesVariable ? "Mit Kategorie- oder Vertragspartnerfilter zählen nur die Verträge." : nil
        }

        public enum LegendItem: String, Hashable, Sendable {
            case fixed, variable
            public var title: String { self == .fixed ? "Fixkosten" : "Variabel (geschätzt)" }
        }
    }

    /// Kosten-Jahr nach wirksamer Kostenart (`costKind`): Fixkosten aus `cy` (Filter wie oben), variable Kosten mit Personenanteil.
    public func costKindYear(_ cy: CostYear, filter: CostFilter, kind kindIn: CostKind? = nil) -> CostKindYear {
        let kind = kindIn ?? costKind
        let useV = kind == .variable || (kind == .all && filter.category == nil && filter.partner == nil)
        var months: [CostKindMonth] = []
        for i in 0..<12 {
            let vr = useV ? variableMonth(year: cy.year, month: i + 1, person: filter.person) : 0
            months.append(CostKindMonth(fixed: kind == .variable ? 0 : cy.months[i].sum, variable: vr))
        }
        let tot = months.reduce(0.0) { $0 + $1.total }
        let mx = months.reduce(0.0) { Swift.max($0, $1.total) }
        return CostKindYear(year: cy.year, kind: kind, usesVariable: useV, months: months, total: tot, maxMonth: mx)
    }

    /// Automatische Monatswahl nach Filterwechsel wie `kbAutoMonth`, aber nach Summe der Kostenart (Web `m.tt`). Rückgabe 1–12.
    public func costKindAutoMonth(_ ky: CostKindYear, current month: Int) -> Int {
        let sel = Swift.min(11, Swift.max(0, month - 1))
        if ky.months[sel].total == 0 && ky.total != 0 {
            for j in 0..<12 {
                let q = (sel + j) % 12
                if ky.months[q].total != 0 { return q + 1 }
            }
        }
        return sel + 1
    }

    /// Zeile unter der grossen Zahl bei «Alle Kosten» bzw. «Variable Kosten» (Web `.kvs`); nil bei «Fixkosten» (dort Vorjahresvergleich).
    public func costKindSubline(_ ky: CostKindYear, month: Int) -> String? {
        let m = ky.months[month - 1]
        switch ky.kind {
        case .fix: return nil
        case .variable: return "geschätzt · im Budget abgezogen"
        case .all: return "Fixkosten " + Format.money(m.fixed) + (ky.usesVariable ? " · variabel " + Format.money(m.variable) : "")
        }
    }

    /// Variable Kosten, die im Monat gelten und die Person betreffen (Web `nVar`, «Einträge»).
    public func variableCount(year: Int, month: Int, person: UUID?) -> Int {
        let a = Day(year, month, 1), b = Day(year, month + 1, 0)
        return data.variableCosts.filter { isActive($0, from: a, to: b) && share($0, person: person) > 0 }.count
    }

    /// Zeile der Liste «Variable Kosten {Monat}»
    public struct VariableCostRow: Hashable, Identifiable, Sendable {
        public var id: UUID
        public var title: String
        /// Monatsbetrag in Hauptwährung × Anteil
        public var value: Double
        /// «Sinan & Lara · Anteil 50 %», sonst «pro Monat»
        public var subline: String
    }

    /// Liste «Variable Kosten {Monat}» im Tab «Kosten» (Web `varGroupHtml`): nil ohne Einträge.
    public struct VariableCostGroup: Hashable, Sendable {
        /// «Variable Kosten Oktober»
        public var title: String
        public var total: Double
        public var rows: [VariableCostRow]
    }

    public func variableCostGroup(year: Int, month: Int, person: UUID?) -> VariableCostGroup? {
        let a = Day(year, month, 1), b = Day(year, month + 1, 0)
        let multi = data.persons.count > 1
        let list = variableCosts.filter { share($0, person: person) > 0 && isActive($0, from: a, to: b) }
        if list.isEmpty { return nil }
        var rows: [VariableCostRow] = []
        var sum = 0.0
        for v in list {
            let f = share(v, person: person)
            let am = conv(v.amount, v.currency) * f
            sum += am
            let names = v.holderIDs.compactMap { data.person($0)?.name }
            let sub = [multi && !names.isEmpty ? names.joined(separator: " & ") : "", f < 1 ? Format.shareText(f) : ""]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            rows.append(VariableCostRow(id: v.id, title: v.title, value: am, subline: sub.isEmpty ? "pro Monat" : sub))
        }
        return VariableCostGroup(title: "Variable Kosten " + Format.monthNames[month - 1], total: sum, rows: rows)
    }

    /// Leerer Zustand im Tab «Kosten» (Web `.empty`): Titel und Text; nil, wenn es etwas zu zeigen gibt.
    public func costKindEmpty(_ ky: CostKindYear, paymentCount: Int) -> (title: String, text: String)? {
        if ky.kind == .variable && ky.total == 0 {
            return ("Keine variablen Kosten in \(ky.year)", "Erfasse sie im Tab Verträge unter «Variabel».")
        }
        if paymentCount == 0 && ky.total == 0 {
            return ("Keine Zahlungen in \(ky.year)", "Für dieses Jahr sind keine Zahlungen erfasst oder berechenbar.")
        }
        return nil
    }

    /// Ganze Seite leer (Web `emptyStat`): keine Verträge und keine sichtbaren variablen Kosten.
    public var costPageEmpty: Bool {
        data.contracts.isEmpty && !(costKind != .fix && hasVariableCosts)
    }
}
