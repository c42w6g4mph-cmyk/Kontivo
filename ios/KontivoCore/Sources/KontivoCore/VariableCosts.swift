import Foundation

// MARK: - Variable Kosten (Web v226–v239, v256: `state.vars`)
// Geschätzter Planwert pro Monat (z.B. Benzin, Lebensmittel). Zählt in Budget (Kostenart «Alle Kosten») und Kosten
// (Kostenart «Alle Kosten» bzw. «Variable Kosten»), nie in Fixkosten, Fristen oder Kopfzahl «Fixkosten pro Monat».

/// Symbol einer variablen Ausgabe (Web `VAR_IC`): Schlüssel, Anzeigename, Farbe.
public enum VarIcon: String, Codable, CaseIterable, Hashable, Sendable {
    case benzin, essen, aus, frei, kleid, haus, ferien, gesch, tier, mobil, gesund, sonst

    public var displayName: String {
        switch self {
        case .benzin: return "Benzin"
        case .essen: return "Lebensmittel"
        case .aus: return "Auswärts essen"
        case .frei: return "Freizeit & Ausgang"
        case .kleid: return "Kleidung"
        case .haus: return "Haushalt"
        case .ferien: return "Ferien"
        case .gesch: return "Geschenke"
        case .tier: return "Haustier"
        case .mobil: return "Mobilität"
        case .gesund: return "Gesundheit"
        case .sonst: return "Sonstiges"
        }
    }

    public var colorHex: String {
        switch self {
        case .benzin: return "#4E6E8E"
        case .essen: return "#5E8A4F"
        case .aus: return "#B5654A"
        case .frei: return "#8A5A9E"
        case .kleid: return "#B03A5B"
        case .haus: return "#3F7F7A"
        case .ferien: return "#C08A2E"
        case .gesch: return "#C2536B"
        case .tier: return "#8B6B4A"
        case .mobil: return "#5F666E"
        case .gesund: return "#C0473B"
        case .sonst: return "#6E7B3A"
        }
    }

    /// Vorschläge beim Erfassen (Web `VAR_SUG`), in dieser Reihenfolge.
    public static let suggestions: [VarIcon] = [.benzin, .essen, .aus, .frei, .kleid, .haus, .ferien, .gesch, .tier]

    /// Unbekannte Werte (neuere Version, fremdes Backup) → «Sonstiges».
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = VarIcon(rawValue: raw) ?? .sonst
    }

    public init(webKey: String) { self = VarIcon(rawValue: webKey) ?? .sonst }
}

/// Variable Ausgabe als Planwert pro Monat (Web `vars[id]`, siehe main/docs/datenmodell.md Abschnitt 4).
public struct VariableCost: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// Bezeichnung (max. 60 Zeichen); leer = Name des Symbols
    public var label: String
    public var icon: VarIcon
    /// Geschätzter Betrag pro Monat (0 – 10 Mio.)
    public var amount: Double
    public var currency: Currency
    /// Personen; Anteil gleich verteilt (keine individuelle Aufteilung)
    public var holderIDs: [UUID]
    /// Gilt in Monaten, die den Zeitraum berühren; nil = offen
    public var start: Day?
    public var end: Day?
    public var logoID: String?
    public var logoBg: String?
    public var createdAt: Date

    public init(id: UUID = UUID(), label: String = "", icon: VarIcon = .sonst, amount: Double = 0, currency: Currency = .CHF,
                holderIDs: [UUID] = [], start: Day? = nil, end: Day? = nil, logoID: String? = nil, logoBg: String? = nil,
                createdAt: Date = Date()) {
        self.id = id
        self.label = label
        self.icon = icon
        self.amount = amount
        self.currency = currency
        self.holderIDs = holderIDs
        self.start = start
        self.end = end
        self.logoID = logoID
        self.logoBg = logoBg
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        label = c.value(.label, "")
        icon = c.value(.icon, VarIcon.sonst)
        amount = c.value(.amount, 0.0)
        currency = c.value(.currency, Currency.CHF)
        holderIDs = c.lossyArray(.holderIDs)
        start = c.optional(.start)
        end = c.optional(.end)
        logoID = c.optional(.logoID)
        logoBg = c.optional(.logoBg)
        createdAt = c.value(.createdAt, Date(timeIntervalSince1970: 0))
    }

    /// Titel wie Web: Bezeichnung, sonst Name des Symbols.
    public var title: String { label.isEmpty ? icon.displayName : label }
}

/// Kostenart im Tab «Kosten» (Web `settings.kArt`, `KART`).
public enum CostKind: String, Codable, CaseIterable, Hashable, Sendable {
    /// Fixkosten und geschätzte variable Kosten
    case all
    /// Verträge, Gebühren und Steuern (Standard)
    case fix
    /// nur variable Kosten
    case variable = "var"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CostKind(rawValue: raw) ?? .fix
    }
}

/// Kostenart im Budget (Web `settings.bArt`, `BART`): was von den Einnahmen abgezogen wird.
public enum BudgetKind: String, Codable, CaseIterable, Hashable, Sendable {
    /// Einnahmen minus Fixkosten und variable Kosten
    case all
    /// Einnahmen minus Fixkosten (Standard)
    case fix
    /// nur Einnahmen
    case none

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BudgetKind(rawValue: raw) ?? .fix
    }
}

extension Calc {
    /// Variable Kosten, grösster Monatsbetrag (Hauptwährung) zuerst, bei Gleichstand ältere zuerst (Web `varList`).
    public var variableCosts: [VariableCost] {
        data.variableCosts.stableSorted { a, b in
            let x = conv(b.amount, b.currency) - conv(a.amount, a.currency)
            if x != 0 { return x < 0 }
            return a.createdAt < b.createdAt
        }
    }

    /// Gibt es erfasste variable Kosten? Ohne gibt es keine Kostenart-Wahl (Web `hasVars`, v256).
    public var hasVariableCosts: Bool { !data.variableCosts.isEmpty }

    /// Wirksame Kostenart im Tab «Kosten» (Web `kArt`): ohne variable Kosten immer Fixkosten.
    public var costKind: CostKind {
        hasVariableCosts && (data.settings.costKind == .all || data.settings.costKind == .variable) ? data.settings.costKind : .fix
    }

    /// Wirksame Kostenart im Budget (Web `bArt`): ohne variable Kosten immer Fixkosten.
    public var budgetKind: BudgetKind {
        hasVariableCosts && (data.settings.budgetKind == .none || data.settings.budgetKind == .all) ? data.settings.budgetKind : .fix
    }

    /// Gilt die variable Ausgabe im Zeitraum (berührt ihn)? (Web `varActiveIn`)
    public func isActive(_ v: VariableCost, from a: Day, to b: Day) -> Bool {
        !(v.start.map { $0 > b } ?? false) && !(v.end.map { $0 < a } ?? false)
    }

    /// Anteil einer Person (Web `holderShare` ohne Aufteilung): ohne Person 1, nicht zugeordnet 0, sonst 1/n.
    public func share(_ v: VariableCost, person: UUID?) -> Double {
        guard let p = person else { return 1 }
        if !v.holderIDs.contains(p) { return 0 }
        return 1 / Double(v.holderIDs.count)
    }

    /// Summe der variablen Kosten eines Monats (`month` 1–12) in Hauptwährung, mit Personenanteil (Web `varMonth`).
    public func variableMonth(year: Int, month: Int, person: UUID?) -> Double {
        let a = Day(year, month, 1), b = Day(year, month + 1, 0)
        return variableCosts.reduce(0.0) { n, v in
            let f = share(v, person: person)
            return n + (f != 0 && isActive(v, from: a, to: b) ? conv(v.amount, v.currency) * f : 0)
        }
    }

    /// Variable Kosten je Monat eines Jahres (12 Werte, Hauptwährung, Personenanteil).
    public func variableMonths(year: Int, person: UUID?) -> [Double] {
        (1...12).map { variableMonth(year: year, month: $0, person: person) }
    }

    /// Laufende Einnahmen pro Monat in Hauptwährung (heute aktiv, mit Rhythmus; einmalige zählen nicht). Web `incMonthNow`.
    public var incomeMonthNow: Double {
        data.incomes.reduce(0.0) { s, x in
            if x.cycle == 0 { return s }
            if let e = x.end, e < today { return s }
            if let st = x.start, st > today { return s }
            return s + conv(curPrice(x), x.currency) / Double(x.cycle)
        }
    }
}

// Beschriftung der Auswahl wie Web `KART` (Kosten) und `BART` (Budget), v237/v238
public extension CostKind {
    var title: String {
        switch self {
        case .all: return "Alle Kosten"
        case .fix: return "Fixkosten"
        case .variable: return "Variable Kosten"
        }
    }

    var subtitle: String {
        switch self {
        case .all: return "Fixkosten und geschätzte variable Kosten"
        case .fix: return "Verträge, Gebühren und Steuern"
        case .variable: return "Geschätzt, z.B. Benzin oder Lebensmittel"
        }
    }
}

public extension BudgetKind {
    var title: String {
        switch self {
        case .all: return "Alle Kosten"
        case .fix: return "Fixkosten"
        case .none: return "Ohne Kosten"
        }
    }

    var subtitle: String {
        switch self {
        case .all: return "Einnahmen minus Fixkosten und variable Kosten"
        case .fix: return "Einnahmen minus Fixkosten"
        case .none: return "Nur deine Einnahmen, z.B. um starke Monate zu sehen"
        }
    }
}
