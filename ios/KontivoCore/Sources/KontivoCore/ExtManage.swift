import Foundation

// Fachaktionen des Bereichs «Verwalten» (Einfeld-Editoren der Datenqualität, Kategorien, Vertragspartner).
// Vorher im App-Target (ManageComponents.swift); hier testbar mit `swift test`.

/// Auswahl «Kündbar auf …» im Editor Frist/Laufzeit (qMulti «notice»)
public enum MDTermChoice: Hashable, Sendable {
    case unset
    case anytime
    case term(CancelTerm)
    case fixed

    /// Optionen wie die Web-App (Reihenfolge und Texte wörtlich)
    public static let options: [(title: String, value: MDTermChoice)] = [
        ("Kündbar auf … wählen", .unset),
        ("jederzeit (mit Frist)", .anytime),
        ("auf Monatsende", .term(.monthEnd)),
        ("auf Quartalsende", .term(.quarterEnd)),
        ("auf Halbjahresende", .term(.halfYearEnd)),
        ("auf Jahresende", .term(.yearEnd)),
        ("auf Ende Vertragsjahr", .term(.contractYear)),
        ("auf Ende Zahlungsperiode", .term(.period)),
        ("Feste Laufzeit bis …", .fixed),
    ]

    /// Vorbelegung wie Web: `fx = !!(c.end || c.renew)`, sonst der Termin bzw. «jederzeit», wenn eine Frist ohne Termin steht (anyNotice)
    public static func initial(for c: Contract) -> MDTermChoice {
        if c.end != nil || c.renewMonths > 0 { return .fixed }
        if c.cancelTerm != .anytime { return .term(c.cancelTerm) }
        return c.notice > 0 ? .anytime : .unset
    }
}

/// Ergebnis der Prüfung im Editor Frist/Laufzeit
public enum MDNoticeCheck: Equatable, Sendable {
    /// gültige Frist (ganze Zahl ≥ 0)
    case ok(Int)
    /// ungültig: Text für den Toast
    case invalid(String)
}

extension AppData {
    /// Kündigungsfrist lesen wie `noticeVal` der Web-App (leitet auf `Format.noticeValue`)
    public static func mdNoticeValue(_ raw: String, unit: NoticeUnit) -> Int? {
        Format.noticeValue(raw, unit: unit)
    }

    /// Prüfung vor dem Speichern (qMultiSave «notice»), Reihenfolge wie Web: Frist → Vertragsende → Termin
    public static func mdCheckNotice(_ raw: String, unit: NoticeUnit, choice: MDTermChoice, end: Day?) -> MDNoticeCheck {
        guard let n = mdNoticeValue(raw, unit: unit) else { return .invalid("Kündigungsfrist prüfen") }
        switch choice {
        case .fixed where end == nil: return .invalid("Bitte das Vertragsende eingeben")
        case .unset: return .invalid("Bitte wählen, worauf kündbar")
        default: return .ok(n)
        }
    }

    /// Toast nach dem Speichern von Frist/Laufzeit (wie Web)
    public func mdNoticeSavedToast(_ id: UUID, today: Day) -> String {
        guard let c = contract(id) else { return "" }
        let calc = Calc(data: self, today: today)
        let anyNotice = c.end == nil && c.cancelTerm == .anytime && c.notice > 0
        if calc.noticeDeadline(c) != nil || anyNotice { return title(of: c) + ": gespeichert" }
        if c.cancelTerm == .contractYear { return "Gespeichert. Für «Ende Vertragsjahr» fehlt noch das Startdatum im Vertrag" }
        if c.cancelTerm == .anytime && c.end == nil { return "Gespeichert. Für «jederzeit» bitte eine Frist eintragen" }
        return "Gespeichert, Termin noch nicht berechenbar"
    }

    /// Inhaber setzen (Reihenfolge der Personenliste)
    public mutating func mdSetHolders(contract id: UUID, _ ids: [UUID]) {
        guard let i = contractIndex(id) else { return }
        let arr = persons.map { $0.id }.filter { ids.contains($0) }
        if arr != contracts[i].holderIDs { contracts[i].split = [] }
        contracts[i].holderIDs = arr
    }

    public mutating func mdSetContractAmount(_ id: UUID, _ v: Double) {
        guard let i = contractIndex(id) else { return }
        contracts[i].amount = Format.round2(v)
    }

    public mutating func mdSetContractCategory(_ id: UUID, _ cat: UUID) {
        guard let i = contractIndex(id), category(cat) != nil else { return }
        contracts[i].categoryID = cat
    }

    public mutating func mdSetContractCycle(_ id: UUID, _ months: Int) {
        guard let i = contractIndex(id) else { return }
        contracts[i].cycle = months
    }

    public mutating func mdSetContractDue(_ id: UUID, _ d: Day) {
        guard let i = contractIndex(id) else { return }
        contracts[i].due = d
    }

    public mutating func mdSetCustomerNo(_ id: UUID, _ s: String) {
        guard let i = contractIndex(id) else { return }
        contracts[i].customerNo = s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public mutating func mdSetCancelURL(_ id: UUID, _ s: String) {
        guard let i = contractIndex(id) else { return }
        contracts[i].cancelURL = s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public mutating func mdSetContractMail(_ id: UUID, _ s: String) {
        guard let i = contractIndex(id) else { return }
        contracts[i].mail = s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Frist und Laufzeit (qMultiSave «notice»). Bei einem Termin werden Vertragsende und Verlängerung geleert (Fund N1).
    public mutating func mdSetNotice(_ id: UUID, notice: Int, unit: NoticeUnit, choice: MDTermChoice, end: Day?, renew: Int) {
        guard let i = contractIndex(id) else { return }
        contracts[i].notice = Swift.max(0, notice)
        contracts[i].noticeUnit = unit
        switch choice {
        case .fixed:
            contracts[i].end = end
            contracts[i].renewMonths = end == nil ? 0 : renew
            contracts[i].cancelTerm = .anytime
        case .anytime:
            contracts[i].cancelTerm = .anytime
            contracts[i].end = nil
            contracts[i].renewMonths = 0
        case .term(let t):
            contracts[i].cancelTerm = t
            contracts[i].end = nil
            contracts[i].renewMonths = 0
        case .unset:
            break
        }
    }

    public mutating func mdSetIncomeAmount(_ id: UUID, _ v: Double) {
        guard let i = incomeIndex(id) else { return }
        incomes[i].amount = Format.round2(v)
    }

    /// Adresse für einen Vertrag: mit Vertragspartner dort, ohne Vertragspartner wird einer mit dem Firmennamen
    /// angelegt bzw. gefunden und zugeordnet (der Brief nimmt die Adresse immer vom Vertragspartner).
    @discardableResult
    public mutating func mdSetContractAddress(_ id: UUID, company: String, address: PostalAddress) -> UUID? {
        guard let i = contractIndex(id) else { return nil }
        if let pid = contracts[i].partnerID, partner(pid) != nil {
            setPartnerAddress(pid, address)
            return pid
        }
        let c = Format.collapseSpaces(company)
        let name = c.isEmpty ? title(of: contracts[i]) : c
        guard let pid = partnerID(forName: name) else { return nil }
        contracts[i].partnerID = pid
        var a = address
        if a.company.trimmingCharacters(in: .whitespaces).isEmpty { a.company = name }
        setPartnerAddress(pid, a)
        return pid
    }

    /// Verträge einer Kategorie (alle Status); ohne bzw. mit unbekannter Kategorie zählt als «Sonstiges» (catCount)
    public func mdContracts(inCategory id: UUID) -> [Contract] {
        let isOther = otherCategory?.id == id
        return contracts.filter { c in
            if c.categoryID == id { return true }
            if isOther { return c.categoryID == nil || category(c.categoryID) == nil }
            return false
        }
    }

    /// Monatskosten (Hauptwährung) laufender, nicht pausierter Verträge (perMonth)
    public func mdPerMonth(_ list: [Contract], today: Day) -> Double {
        let calc = Calc(data: self, today: today)
        return list.reduce(0.0) { s, c in s + ((calc.isActive(c) && !calc.isPaused(c)) ? calc.monthlyCost(c) : 0) }
    }
}
