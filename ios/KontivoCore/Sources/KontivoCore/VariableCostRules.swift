import Foundation

// MARK: - Budget: variable Kosten des Monats und Summenrechnung (Web v226/v227/v238 `varGroupHtml`, `renderBudget`)

extension Calc {
    /// Zeile «Variable Kosten {Monat}»: Eintrag, der im Monat gilt, mit Anteil der Person
    public struct BudgetVariableRow: Hashable, Identifiable, Sendable {
        public var variableID: UUID
        public var title: String
        /// Personen (bei mehreren Personen) · «Anteil 50 %», sonst «pro Monat»
        public var sub: String
        /// Hauptwährung × Anteil
        public var value: Double
        public var id: UUID { variableID }
    }

    /// Variable Kosten, die im Monat gelten (Anteil > 0), grösster Betrag zuerst (Web `varGroupHtml`).
    public func budgetVariableRows(year: Int, month: Int, person: UUID?) -> [BudgetVariableRow] {
        let a = Day(year, month, 1), b = Day(year, month + 1, 0)
        let multi = data.persons.count > 1
        return variableCosts.compactMap { v in
            let f = share(v, person: person)
            guard f > 0, isActive(v, from: a, to: b) else { return nil }
            let hs = data.persons.filter { v.holderIDs.contains($0.id) }.map { $0.name }
            let sub = [multi && !hs.isEmpty ? hs.joined(separator: " & ") : "", f < 1 ? Format.shareText(f) : ""]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            return BudgetVariableRow(variableID: v.id, title: v.title, sub: sub.isEmpty ? "pro Monat" : sub, value: conv(v.amount, v.currency) * f)
        }
    }

    /// Unterzeile der Budget-Karte (Web v238): ohne Kosten, nach Fix- und variablen Kosten, nach Fixkosten
    public func budgetSubline(_ bm: BudgetMonth) -> String {
        if !bm.countsFixed { return "Einnahmen, ohne Kosten" }
        return bm.variable > 0.005 ? "verfügbar nach Fix- und variablen Kosten" : "verfügbar nach Fixkosten"
    }

    /// Zeilen der Summenrechnung unter «Ausgaben» (Web `.xsum`): mit variablen Kosten mit Zwischensumme «= Nach Fixkosten».
    /// `isTotal` = Schlusszeile (fett), `isSubtotal` = Zwischensumme.
    public struct BudgetSumLine: Hashable, Sendable {
        public var label: String
        public var value: Double
        public var isSubtotal: Bool = false
        public var isTotal: Bool = false
    }

    public func budgetSumLines(_ bm: BudgetMonth) -> [BudgetSumLine] {
        var l = [BudgetSumLine(label: "Einnahmen", value: bm.income)]
        if bm.variable > 0.005 {
            l.append(BudgetSumLine(label: Format.minus + " Fixkosten", value: bm.fixed))
            l.append(BudgetSumLine(label: "= Nach Fixkosten", value: bm.income - bm.fixed, isSubtotal: true))
            l.append(BudgetSumLine(label: Format.minus + " Variable Kosten", value: bm.variable))
        } else {
            l.append(BudgetSumLine(label: Format.minus + " Ausgaben", value: bm.fixed))
        }
        l.append(BudgetSumLine(label: "= Verfügbar", value: bm.free, isTotal: true))
        return l
    }
}

// MARK: - Ansicht und Formular (Web v227/v231 `openVarDetail`, `openVar`)

/// Inhalt der Ansicht einer variablen Ausgabe
public struct VariableDetailInfo: Hashable, Sendable {
    public var title: String
    /// «Beendet am 31.05.2026» bzw. «Ab 01.12.2026»
    public var pill: String?
    /// Betrag pro Monat in Hauptwährung (bei Fremdwährung «≈ … CHF»)
    public var amountHome: Double
    public var foreign: Bool
    /// Anteil an den laufenden Einnahmen pro Monat (Balken), nil = «geschätzt»
    public var incomePercent: Int?
    /// Anteil an allen variablen Kosten («Anteil variabel»), nil = «—»
    public var variablePercent: Int?
    public var rows: [DetailRow]
}

extension Calc {
    public func variableDetail(_ v: VariableCost) -> VariableDetailInfo {
        let a = conv(v.amount, v.currency)
        let inc = incomeMonthNow
        let vt = data.variableCosts.reduce(0.0) { $0 + conv($1.amount, $1.currency) }
        var pill: String? = nil
        if let e = v.end, e < today { pill = "Beendet am " + Format.fmtD(e) } else if let s = v.start, s > today { pill = "Ab " + Format.fmtD(s) }
        var rows = [DetailRow("Betrag", "geschätzt, monatlich")]
        if let s = v.start { rows.append(DetailRow("Ab", Format.fmtD(s))) }
        if let e = v.end { rows.append(DetailRow("Bis", Format.fmtD(e))) }
        let hs = data.persons.filter { v.holderIDs.contains($0.id) }.map { $0.name }
        if data.persons.count > 1 && !hs.isEmpty { rows.append(DetailRow("Personen", hs.joined(separator: " & "))) }
        rows.append(DetailRow("Zählt in", "Budget (nicht in Kosten und Fristen)"))
        return VariableDetailInfo(title: v.title, pill: pill, amountHome: a, foreign: v.currency != home,
                                  incomePercent: inc > 0.005 ? Int(Format.jsRound(a / inc * 100)) : nil,
                                  variablePercent: vt > 0.005 ? Int(Format.jsRound(a / vt * 100)) : nil, rows: rows)
    }

    /// Vorschläge beim Erfassen (Web `vPaint`): ohne Bezeichnungen anderer Einträge (gross/klein egal)
    public func variableSuggestions(excluding id: UUID?) -> [VarIcon] {
        let used = Set(data.variableCosts.filter { $0.id != id }.map { $0.label.lowercased() })
        return VarIcon.suggestions.filter { !used.contains($0.displayName.lowercased()) }
    }
}

public enum VariableCostForm {
    /// Prüfung beim Sichern (Web `vcSave`): Feld und Meldung der ersten fehlenden Angabe, nil = in Ordnung
    public static func missing(label: String, amountText: String, start: Day?, end: Day?) -> (field: String, message: String)? {
        if Format.collapseSpaces(label).isEmpty { return ("label", "Bezeichnung fehlt") }
        let t = amountText.trimmingCharacters(in: .whitespaces)
        guard let a = Format.parseAmount(t), a > 0 else { return ("amount", t.isEmpty ? "Betrag fehlt" : "Betrag prüfen") }
        if let s = start, let e = end, e < s { return ("end", "Bis liegt vor Ab") }
        return nil
    }

    /// Symbol zur eingetippten Bezeichnung, solange noch «Sonstiges» gewählt ist (Web `vcLabel` input)
    public static func icon(forLabel label: String, current: VarIcon) -> VarIcon {
        let l = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard current == .sonst, let m = VarIcon.suggestions.first(where: { $0.displayName.lowercased() == l }) else { return current }
        return m
    }
}
