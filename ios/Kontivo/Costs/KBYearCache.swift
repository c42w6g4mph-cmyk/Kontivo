import Foundation
import KontivoCore

/// Ein-Eintrag-Zwischenspeicher: Wert gilt, solange Datenstand und Schlüssel gleich bleiben.
/// Der Vergleich der Daten ist dank Copy-on-Write meist sofort entschieden (gleicher Speicher der Arrays).
@MainActor
final class KBMemo<Key: Equatable, Value> {
    private var key: Key?
    private var data: AppData?
    private var value: Value?

    func get(_ data: AppData, _ key: Key, compute: () -> Value) -> Value {
        if let v = value, self.key == key, self.data == data { return v }
        let v = compute()
        self.key = key
        self.data = data
        value = v
        return v
    }
}

/// Zwischenspeicher für Kosten- und Budgetjahr (Review S3 Teil B 2): Beim Monatswechsel (Wischen, Scrubbing)
/// werden Jahr und Vorjahresvergleich nicht jedes Mal neu über alle Zahlungen gerechnet.
@MainActor
enum KBYearCache {
    private struct CostKey: Equatable {
        var today: Day
        var year: Int
        var filter: Calc.CostFilter
        var split: Calc.FilterDimension
    }

    private struct CostCompareKey: Equatable {
        var today: Day
        var year: Int
        var month: Int
        var filter: Calc.CostFilter
    }

    private struct BudgetKey: Equatable {
        var today: Day
        var year: Int
        var person: UUID?
    }

    private struct BudgetCompareKey: Equatable {
        var today: Day
        var year: Int
        var month: Int
        var person: UUID?
        var free: Double
    }

    private static let costYears = KBMemo<CostKey, Calc.CostYear>()
    private static let costCompares = KBMemo<CostCompareKey, (text: String, trend: Calc.Trend)?>()
    private static let budgetYears = KBMemo<BudgetKey, Calc.BudgetYear>()
    private static let budgetCompares = KBMemo<BudgetCompareKey, (text: String, trend: Calc.Trend)?>()

    /// `Calc.costYear` zwischengespeichert
    static func costYear(_ calc: Calc, year: Int, filter: Calc.CostFilter, split: Calc.FilterDimension) -> Calc.CostYear {
        costYears.get(calc.data, CostKey(today: calc.today, year: year, filter: filter, split: split)) {
            calc.costYear(year, filter: filter, split: split)
        }
    }

    /// Vorjahresmonat in «Kosten» (`Calc.monthComparison`) zwischengespeichert
    static func monthComparison(_ calc: Calc, year: Int, month: Int, filter: Calc.CostFilter,
                                monthSum: Double, items: [Calc.CostItem]) -> (text: String, trend: Calc.Trend)? {
        costCompares.get(calc.data, CostCompareKey(today: calc.today, year: year, month: month, filter: filter)) {
            calc.monthComparison(year: year, month: month, filter: filter, monthSum: monthSum, items: items)
        }
    }

    /// `Calc.budgetYear` zwischengespeichert
    static func budgetYear(_ calc: Calc, year: Int, person: UUID?) -> Calc.BudgetYear {
        budgetYears.get(calc.data, BudgetKey(today: calc.today, year: year, person: person)) {
            calc.budgetYear(year, person: person)
        }
    }

    /// Vorjahresvergleich «verfügbar» (`kbBudgetComparison`) zwischengespeichert
    static func budgetComparison(_ calc: Calc, year: Int, month: Int, person: UUID?, free: Double) -> (text: String, trend: Calc.Trend)? {
        budgetCompares.get(calc.data, BudgetCompareKey(today: calc.today, year: year, month: month, person: person, free: free)) {
            calc.kbBudgetComparison(year: year, month: month, person: person, free: free)
        }
    }
}
