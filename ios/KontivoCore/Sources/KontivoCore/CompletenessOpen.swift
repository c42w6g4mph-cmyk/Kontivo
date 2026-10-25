import Foundation

// Vollständigkeit unter 100 % (Web 01b0f3d `vkOpenList`, 23.10.2026): offene Punkte direkt ergänzbar – zuerst die Adresse
// (einmal, betrifft mehrere Verträge), dann je Vertrag die fehlende Frist. «Keine Erinnerung nötig» setzt `noWatch`.

/// Offener Punkt im Abschluss der Vollständigkeit
public struct CompletenessOpenItem: Hashable, Identifiable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// Adresse (Absender) der Personen in `CompletenessReport.senderPersons`
        case sender
        /// Kündigungsfrist eines Vertrags
        case term(UUID)
    }

    public var kind: Kind
    /// «Deine Adresse» / «Adresse von Lara» bzw. Vertrag
    public var title: String
    /// «für Kündigungsbriefe · 2 Verträge» bzw. «Kündigungsfrist fehlt · Swisscom»
    public var subtitle: String
    public var id: String {
        switch kind {
        case .sender: return "snd"
        case .term(let u): return u.uuidString
        }
    }
}

extension Completeness {
    /// Knopf unter «Weiss ich nicht · überspringen»: keine Fristerinnerung für diesen Vertrag (Web `termnowatch`)
    public static let termNoWatch = "Keine Erinnerung nötig"
    /// Abschluss unter 100 %: alles nochmals durchgehen bzw. schliessen
    public static let againTitle = "Jetzt ergänzen"

    /// Offene Punkte bis 100 % (Web `vkOpenList`)
    public static func openItems(_ r: CompletenessReport, data: AppData) -> [CompletenessOpenItem] {
        var out: [CompletenessOpenItem] = []
        if !r.senderPersons.isEmpty {
            let ns = r.per.values.filter { $0.contains(.sender) }.count
            let names = r.senderPersons.compactMap { data.person($0)?.name }
            out.append(CompletenessOpenItem(kind: .sender,
                                            title: data.persons.count > 1 ? "Adresse von " + names.joined(separator: ", ") : "Deine Adresse",
                                            subtitle: "für Kündigungsbriefe · " + Format.count(ns, "Vertrag", "Verträge")))
        }
        for id in r.termContracts {
            guard let c = data.contract(id) else { continue }
            let p = data.partnerName(of: c)
            let extra = !c.label.isEmpty && !p.isEmpty && Partners.lnorm(c.label) != Partners.lnorm(p) ? " · " + p : ""
            out.append(CompletenessOpenItem(kind: .term(id), title: data.title(of: c), subtitle: "Kündigungsfrist fehlt" + extra))
        }
        return out
    }
}

extension AppData {
    /// «Keine Erinnerung nötig»: Frist nicht überwachen (Web `noWatch`), zählt damit als startklar
    public mutating func setNoWatch(_ id: UUID) {
        guard let i = contractIndex(id) else { return }
        contracts[i].noWatch = true
    }
}
