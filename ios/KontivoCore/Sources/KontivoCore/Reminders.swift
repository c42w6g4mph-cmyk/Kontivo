import Foundation

// MARK: - Erinnerungen vor Fristen (nur nativ) und Kalendereinträge
//
// Reine Funktionen: welche Verträge, welche Daten, welche Texte und Kennungen.
// Die App (Native/NotificationScheduler) macht daraus lokale Mitteilungen (UNUserNotificationCenter),
// der Bereich Fristen (Deadlines/DeadlineCalendar) daraus Kalendereinträge.

/// Art der Frist für eine Erinnerung.
public enum ReminderKind: String, Hashable, Sendable {
    /// Kündigungsfrist («Kündigen bis …», Pflichtvertrag «Wechseln bis …»)
    case notice
    /// Probeabo endet
    case trial
}

/// Nächste Frist eines Vertrags (gleiche Logik wie der Tab «Fristen»).
public struct ReminderDeadline: Hashable, Sendable {
    public var contractID: UUID
    public var kind: ReminderKind
    /// Angezeigtes Datum: Kündigungsfrist bzw. Ende des Probeabos (wie in «Fristen»)
    public var date: Day
    /// Vertragsende zum Termin (nur Kündigungsfrist)
    public var end: Day?
    /// Pflichtvertrag: «Wechseln» statt «Kündigen»
    public var mandatory: Bool

    public init(contractID: UUID, kind: ReminderKind, date: Day, end: Day?, mandatory: Bool) {
        self.contractID = contractID
        self.kind = kind
        self.date = date
        self.end = end
        self.mandatory = mandatory
    }

    /// Letzter Tag zum Handeln: Frist selbst; Probeabo: Tag vor dem Ende («Kündigung muss vor dem … sein»).
    public var lastDay: Day { kind == .trial ? date.addingDays(-1) : date }
}

/// Eine geplante Mitteilung.
public struct ReminderNotification: Hashable, Sendable {
    /// Eindeutige Kennung (`Reminders.identifier`), enthält die Vertrags-ID
    public var id: String
    public var contractID: UUID
    /// Tag der Mitteilung (Uhrzeit `hour`:`minute` Ortszeit)
    public var fireDay: Day
    public var hour: Int
    public var minute: Int
    /// Tage vor dem letzten Tag (0 = am letzten Tag)
    public var leadDays: Int
    public var title: String
    public var body: String
    public var deadline: ReminderDeadline
}

extension Calc {
    /// Nächste Frist eines Vertrags für Erinnerung und Kalender, nil = keine.
    /// Grundmenge wie «Fristen»: aktiv (auch pausiert), kündbar, beobachtet, nicht gekündigt.
    /// - Probeabo offen (Ende heute oder später, nicht behalten): Ende des Probeabos
    /// - jederzeit kündbar: keine Frist
    /// - behalten: nächste Frist nach dem behaltenen Termin (wie «Behalten · nächste Frist»)
    /// - sonst Kündigungsfrist zum nächsten Termin, sofern nicht verpasst
    public func reminderDeadline(for c: Contract) -> ReminderDeadline? {
        guard isActive(c), !isFixed(c), !c.noWatch, c.cancelPer == nil else { return nil }
        if let t = c.trial, t >= today, c.trialKept != t {
            return ReminderDeadline(contractID: c.id, kind: .trial, date: t, end: nil, mandatory: c.mandatory)
        }
        if isAnytime(c) { return nil }
        guard let T = termEnd(c) else { return nil }
        if isKept(c) {
            let T2 = c.end != nil ? renewAfter(c, T) : nextTerm(c, base: nil, after: T)
            guard let next = T2 else { return nil }
            let d2 = noticeDeadline(for: c, end: next)
            return d2 >= today ? ReminderDeadline(contractID: c.id, kind: .notice, date: d2, end: next, mandatory: c.mandatory) : nil
        }
        let dl = noticeDeadline(for: c, end: T)
        guard dl >= today else { return nil }
        return ReminderDeadline(contractID: c.id, kind: .notice, date: dl, end: T, mandatory: c.mandatory)
    }

    /// Alle Fristen nach Datum (bei gleichem Datum Speicherreihenfolge).
    public func reminderDeadlines() -> [ReminderDeadline] {
        data.contracts.compactMap { reminderDeadline(for: $0) }.stableSorted { $0.lastDay < $1.lastDay }
    }
}

public enum Reminders {
    /// Auswahl «Tage vorher»
    public static let leadChoices = [1, 3, 7, 14, 30]
    public static let defaultLead = 7
    /// Uhrzeit der Mitteilungen (Ortszeit)
    public static let hour = 9
    public static let minute = 0
    /// iOS behält höchstens 64 geplante Mitteilungen je App; etwas Reserve
    public static let maxPending = 60
    /// Präfix aller Kennungen (nur diese werden beim Neuplanen ersetzt)
    public static let idPrefix = "kontivo.frist."

    /// «kontivo.frist.<Vertrags-ID>.<notice|trial>.<JJJJ-MM-TT>.<Tage vorher>»
    public static func identifier(_ d: ReminderDeadline, leadDays: Int) -> String {
        idPrefix + d.contractID.uuidString + "." + d.kind.rawValue + "." + d.date.iso + "." + String(leadDays)
    }

    /// Vertrags-ID aus einer Kennung (Tippen auf die Mitteilung öffnet den Vertrag).
    public static func contractID(fromIdentifier id: String) -> UUID? {
        guard id.hasPrefix(idPrefix) else { return nil }
        let rest = id.dropFirst(idPrefix.count)
        guard let first = rest.split(separator: ".").first else { return nil }
        return UUID(uuidString: String(first))
    }

    /// Plan aller Mitteilungen: je Frist eine `leadDays` Tage vor dem letzten Tag und eine am letzten Tag, je um 09:00.
    /// Vergangene Zeitpunkte entfallen (heute nach 09:00 ebenfalls). Nächste zuerst, höchstens `limit`.
    /// - Parameters:
    ///   - leadDays: «Tage vorher» (≤ 0: nur am letzten Tag)
    ///   - minuteOfDay: aktuelle Uhrzeit in Minuten seit Mitternacht (für heute)
    public static func plan(calc: Calc, leadDays: Int, minuteOfDay: Int, limit: Int = Reminders.maxPending) -> [ReminderNotification] {
        let today = calc.today
        let fireMinute = hour * 60 + minute
        var out: [ReminderNotification] = []
        for d in calc.reminderDeadlines() {
            guard let c = calc.data.contract(d.contractID) else { continue }
            let last = d.lastDay
            var leads: [Int] = []
            if leadDays > 0 { leads.append(leadDays) }
            leads.append(0)
            for n in leads {
                let fire = last.addingDays(-n)
                if fire < today { continue }
                if fire == today && minuteOfDay >= fireMinute { continue }
                out.append(ReminderNotification(id: identifier(d, leadDays: n), contractID: d.contractID, fireDay: fire,
                                                hour: hour, minute: minute, leadDays: n,
                                                title: title(d, contract: c, data: calc.data, today: today),
                                                body: body(d, leadDays: n, today: today),
                                                deadline: d))
            }
        }
        let sorted = out.stableSorted { $0.fireDay < $1.fireDay }
        return Array(sorted.prefix(max(0, limit)))
    }

    // MARK: Texte

    /// «Handy (Nimbo Mobile)»: Titel, Vertragspartner in Klammern, wenn er nicht schon der Titel ist.
    public static func contractName(_ c: Contract, data: AppData) -> String {
        let t = data.title(of: c)
        let m = data.meta(of: c)
        return m.isEmpty ? t : t + " (" + m + ")"
    }

    /// «5. November», in einem anderen Jahr «5. November 2027».
    public static func dateText(_ d: Day, today: Day) -> String {
        "\(d.day). " + Format.monthNames[d.month - 1] + (d.year == today.year ? "" : " \(d.year)")
    }

    /// Titel der Mitteilung: «Kündigen bis 5. November: Handy (Nimbo Mobile)», Pflichtvertrag «Wechseln bis …»,
    /// Probeabo «Probeabo endet am 15. Oktober: Netflix».
    public static func title(_ d: ReminderDeadline, contract c: Contract, data: AppData, today: Day) -> String {
        let name = contractName(c, data: data)
        switch d.kind {
        case .trial:
            return "Probeabo endet am " + dateText(d.date, today: today) + ": " + name
        case .notice:
            return (d.mandatory ? "Wechseln bis " : "Kündigen bis ") + dateText(d.date, today: today) + ": " + name
        }
    }

    /// Text der Mitteilung: vorher «Noch 7 Tage. …», am letzten Tag «Heute ist der letzte Tag. …».
    public static func body(_ d: ReminderDeadline, leadDays n: Int, today: Day) -> String {
        let head = n == 0 ? "Heute ist der letzte Tag." : (n == 1 ? "Noch 1 Tag." : "Noch \(n) Tage.")
        switch d.kind {
        case .trial:
            return head + " Die Kündigung muss vor dem " + dateText(d.date, today: today) + " beim Vertragspartner sein, sonst läuft das Abo weiter."
        case .notice:
            let when = n == 0 ? "heute" : "bis " + dateText(d.date, today: today)
            return head + " Die Kündigung muss " + when + " beim Vertragspartner sein." + (d.mandatory ? " Wechseln oder behalten?" : " Behalten oder kündigen?")
        }
    }

    /// Titel des Kalendereintrags (ganztägig am angezeigten Datum).
    public static func calendarTitle(_ d: ReminderDeadline, contract c: Contract, data: AppData) -> String {
        let name = contractName(c, data: data)
        switch d.kind {
        case .trial: return "Probeabo endet: " + name
        case .notice: return (d.mandatory ? "Letzter Tag zum Wechseln: " : "Letzter Tag zum Kündigen: ") + name
        }
    }

    /// Notiz des Kalendereintrags: Vertragspartner, Kündigungsweg mit Link/E-Mail/Adresse, Nummern, Frist.
    public static func calendarNotes(_ d: ReminderDeadline, contract c: Contract, calc: Calc) -> String {
        let data = calc.data
        var lines: [String] = []
        let partner = data.partner(c.partnerID)
        let pn = (partner?.name ?? "").trimmingCharacters(in: .whitespaces)
        if !pn.isEmpty { lines.append("Vertragspartner: " + pn) }
        let via = calc.cancVia(c)
        var way = c.cancelChannel?.webText ?? ""
        if way.isEmpty || calc.isRent(c) {
            switch via {
            case .online: way = CancelChannel.online.webText
            case .mail: way = CancelChannel.email.webText
            case .post: way = c.cancelChannel == .registered ? CancelChannel.registered.webText : CancelChannel.letter.webText
            case .none: way = ""
            }
        }
        if !way.isEmpty { lines.append("Kündigungsweg: " + way) }
        switch via {
        case .online:
            let link = calc.cancLink(c)
            if !link.isEmpty { lines.append("Link: " + link) }
        case .mail:
            let m = c.mail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !m.isEmpty { lines.append("E-Mail: " + m) }
        case .post:
            if let a = partner?.address, !a.isEmpty { lines.append("Adresse: " + a.lines.joined(separator: ", ")) }
        case .none:
            break
        }
        let cust = c.customerNo.trimmingCharacters(in: .whitespaces)
        if !cust.isEmpty { lines.append("Kundennummer: " + cust) }
        let contr = c.contractNo.trimmingCharacters(in: .whitespaces)
        if !contr.isEmpty { lines.append("Vertragsnummer: " + contr) }
        switch d.kind {
        case .trial:
            lines.append("Kündigung muss vor dem " + Format.fmtD(d.date) + " sein.")
        case .notice:
            lines.append("Kündigung muss bis " + Format.fmtD(d.date) + " beim Vertragspartner sein.")
            if let e = d.end { lines.append("Vertragsende: " + Format.fmtD(e)) }
        }
        lines.append(d.mandatory ? "In Kontivo unter «Fristen» mit einem Tipp wechseln." : "In Kontivo unter «Fristen» mit einem Tipp kündigen.")
        return lines.joined(separator: "\n")
    }
}
