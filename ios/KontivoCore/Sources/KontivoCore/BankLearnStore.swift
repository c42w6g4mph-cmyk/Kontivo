import Foundation

// MARK: - Kontoauszug: lernt aus Korrekturen (Web bankLearnKey, bankLearnAssign, bankLearnSet; Web v331 ff.)
// Bewusst abgewählt → beim nächsten Import vorab abgewählt; Bezeichnung geändert → beim nächsten Import übernommen.
// Je Vertragspartner und Betrag (±35 %, Prämie ändert sich jährlich), eins zu eins: mehrere Vorschläge beim selben Vertragspartner
// (zwei Handyabos, drei Policen) – jede Korrektur gilt nur für den nächstgelegenen Betrag.

extension BankImport {
    static let rxLearnTail = BRX("#\\d+$")

    /// Schlüssel der gelernten Korrekturen (Web `bankLearnKey`): Gruppenschlüssel ohne Währung und ohne Dateizusatz «#n»
    public static func learnKey(_ s: BankSuggestion) -> String {
        rxLearnTail.replaceFirst(s.key.components(separatedBy: "|")[0], "")
    }

    /// Gelernte Korrekturen den Vorschlägen zuordnen (Web `bankLearnAssign`): setzt `learn` je Vorschlag (oder nil).
    public static func learnAssign(_ list: inout [BankSuggestion], settings: Settings) {
        let B = settings.bankLearn
        var by = BOrdered<[Int]>()
        for i in list.indices {
            list[i].learn = nil
            let k = learnKey(list[i])
            if B[k] != nil { by[k] = (by[k] ?? []) + [i] }
        }
        for k in by.orderedKeys {
            let E = B[k] ?? []
            var P: [(d: Double, e: Int, s: Int)] = []
            for (ei, e) in E.enumerated() {
                for si in by[k] ?? [] {
                    let d = Swift.abs(e.a - list[si].amount) / Swift.max(e.a, 0.01)
                    if d <= 0.35 { P.append((d, ei, si)) }
                }
            }
            P = BU.sorted(P) { a, b in a.d - b.d }
            var ue = Set<Int>()
            for x in P where !ue.contains(x.e) && list[x.s].learn == nil {
                ue.insert(x.e)
                list[x.s].learn = E[x.e]
            }
        }
    }

    /// Korrektur merken (Web `bankLearnSet`): bisherige Einträge zum selben Betrag bzw. die zugeordnete ersetzen; `entry` nil = nur
    /// entfernen. Höchstens 12 Einträge je Vertragspartner.
    public static func learnSet(_ s: BankSuggestion, _ entry: (label: String, off: Bool)?, in settings: inout Settings) {
        let k = learnKey(s)
        var L = (settings.bankLearn[k] ?? []).filter { e in e != s.learn && Swift.abs(e.a - s.amount) > 0.004 }
        if let o = entry { L.append(BankLearn(a: BU.r2(s.amount), l: o.label, x: o.off)) }
        settings.bankLearn[k] = L.isEmpty ? nil : Array(L.suffix(12))
    }

    /// Lernen beim Übernehmen (Web `bkGo`): abgewählt (selbst geändert oder schon letztes Mal abgewählt) → «abgewählt» merken;
    /// übernommen mit eigener Bezeichnung → Bezeichnung merken; sonst eine frühere Korrektur entfernen. Ausgeblendete und
    /// «Wieder aktivieren» lernen nicht. `label` = gewählte Bezeichnung (Formular oder Liste).
    public static func learn(_ s: BankSuggestion, on: Bool, touched: Bool, label: String, reactivate: Bool, in settings: inout Settings) {
        if s.ignored || reactivate { return }
        if !on {
            if touched || s.learn?.x == true { learnSet(s, ("", true), in: &settings) }
        } else if !label.isEmpty && label != BankImport.label(s) {
            learnSet(s, (label, false), in: &settings)
        } else if touched || s.learn != nil {
            learnSet(s, nil, in: &settings)
        }
    }
}
