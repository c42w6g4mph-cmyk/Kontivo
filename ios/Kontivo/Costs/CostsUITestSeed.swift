import Foundation
import KontivoCore

#if DEBUG
/// Bildschirmfotos/UI-Tests im Tab «Kosten» (nur Debug): «-uiCostSeed vars[,all|var]» spielt drei variable Kosten ein
/// (Benzin 180 CHF Sinan, Lebensmittel 650 CHF Sinan & Lara, Auswärts essen 120 EUR Lara – wie Tools/visual für die Web-Fotos)
/// und setzt optional die Kostenart («all» = Alle Kosten, «var» = Variable Kosten); «flt» setzt den Kategoriefilter «Wohnen».
/// «-uiCostOpen kind|filter|categories|cat» öffnet das Blatt Kostenart/Filter, den Donut bzw. die erste Kategorie in «Was sich verändert hat».
@MainActor
enum KBUITestSeed {
    private static var done = false

    /// Wert von «-uiCostOpen» (einmalig)
    static var openArg: String? {
        guard !openDone else { return nil }
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiCostOpen"), i + 1 < args.count else { return nil }
        openDone = true
        return args[i + 1]
    }
    private static var openDone = false

    static func applyIfNeeded(_ model: AppModel) {
        guard !done, model.uiTestMode else { return }
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiCostSeed"), i + 1 < args.count else { return }
        done = true
        let seeds = Set(args[i + 1].split(separator: ",").map { String($0) })
        if seeds.contains("flt") { model.costFilter.category = "Wohnen" }
        guard seeds.contains("vars") else { return }
        _ = model.update { d in
            let s = d.persons.first { $0.name == "Sinan" }?.id
            let l = d.persons.first { $0.name == "Lara" }?.id
            let t0 = Date(timeIntervalSince1970: 1_760_000_000)
            // feste Testmenge statt der variablen Kosten aus den Beispieldaten (Beträge in UI-Tests und Fotos bleiben gleich)
            d.variableCosts = []
            _ = d.putVariableCost(VariableCost(label: "", icon: .benzin, amount: 180, holderIDs: [s].compactMap { $0 }, createdAt: t0))
            _ = d.putVariableCost(VariableCost(label: "Lebensmittel", icon: .essen, amount: 650, holderIDs: [s, l].compactMap { $0 },
                                               createdAt: t0.addingTimeInterval(1)))
            _ = d.putVariableCost(VariableCost(label: "Auswärts essen", icon: .aus, amount: 120, currency: .EUR, holderIDs: [l].compactMap { $0 },
                                               createdAt: t0.addingTimeInterval(2)))
            if seeds.contains("all") { d.settings.costKind = .all }
            if seeds.contains("var") { d.settings.costKind = .variable }
        }
    }
}
#endif
