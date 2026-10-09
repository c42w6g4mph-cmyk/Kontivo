import Foundation

/// Gruppe der Datenqualität.
public enum QualityGroup: String, CaseIterable, Hashable, Sendable {
    case A, B, C, D

    public var title: String {
        switch self {
        case .A: return "Kosten und Budget"
        case .B: return "Fristen"
        case .C: return "Vertragspartner"
        case .D: return "Kündigen"
        }
    }
}

/// Geprüftes Kriterium (letztes Segment des Schlüssels).
public enum QualityCriterion: String, CaseIterable, Hashable, Sendable {
    case holder, amount, cat, cycle, due, notice, via, ref, link, mail, addr, sender, logo
}

/// Betroffener Eintrag.
public enum QualitySubject: Hashable, Sendable {
    case contract(UUID)
    case income(UUID)
    case partner(UUID)
    case person(UUID)

    /// Kürzel im Schlüssel: c, i, p, h
    public var code: String {
        switch self {
        case .contract: return "c"
        case .income: return "i"
        case .partner: return "p"
        case .person: return "h"
        }
    }

    public var id: UUID {
        switch self {
        case .contract(let u), .income(let u), .partner(let u), .person(let u): return u
        }
    }
}

/// Ein offener Punkt.
public struct QualityIssue: Hashable, Sendable, Identifiable {
    public var group: QualityGroup
    public var criterion: QualityCriterion
    public var subject: QualitySubject
    /// Schlüssel für «Ignorieren»: «c:<UUID>:holder», «i:…», «p:<UUID>:logo|addr», «h:<UUID>:sender»
    public var key: String
    /// Anzeigename (Vertrag: Bezeichnung → Vertragspartner → «Ohne Namen»)
    public var name: String
    /// Zusatz (Vertragspartner, «Einnahme», «n Verträge», «Person · für Kündigung per Brief»)
    public var subtitle: String
    /// Grund («Keine Person» …)
    public var reason: String
    /// Absender-Bedarf: 2 = Adresse (Brief), 1 = nur Name (E-Mail); sonst 0
    public var senderLevel: Int

    public var id: String { key }

    /// Logo-Suche möglich
    public var canSearchLogo: Bool { criterion == .logo }
}

public struct QualityReport: Hashable, Sendable {
    public var A: [QualityIssue]
    public var B: [QualityIssue]
    public var C: [QualityIssue]
    public var D: [QualityIssue]
    /// Anzahl ignorierter Punkte
    public var ignoredCount: Int
    /// Geprüfte (laufende) Verträge
    public var contractCount: Int
    public var incomeCount: Int

    public func issues(_ g: QualityGroup) -> [QualityIssue] {
        switch g {
        case .A: return A
        case .B: return B
        case .C: return C
        case .D: return D
        }
    }

    /// Alle Punkte in der Reihenfolge A, B, C, D.
    public var all: [QualityIssue] { A + B + C + D }

    /// Anzahl Punkte
    public var totalCount: Int { A.count + B.count + C.count + D.count }

    /// Betroffene Einträge (jeder Vertrag, jede Einnahme, jeder Vertragspartner, jede Person einmal) (`qualOpenContracts`).
    public var affectedCount: Int {
        var s = Set<String>()
        for i in all { s.insert(i.subject.code + i.subject.id.uuidString) }
        return s.count
    }

    /// Punkte einer Checklisten-Zeile (`qSel`): «inc» = alle Einnahmen der Gruppe, sonst Kriterium; in A nur Verträge.
    public func select(_ g: QualityGroup, field: String) -> [QualityIssue] {
        issues(g).filter { o in
            if field == "inc" {
                if case .income = o.subject { return true }
                return false
            }
            guard o.criterion.rawValue == field else { return false }
            if g == .A {
                if case .contract = o.subject { return true }
                return false
            }
            return true
        }
    }
}

/// Zeile der Checkliste «Was geprüft wird».
public struct QualityChecklistRow: Hashable, Sendable {
    /// Kriterium oder «inc»
    public var field: String
    public var title: String
}

public struct QualityChecklistGroup: Hashable, Sendable {
    public var group: QualityGroup
    public var title: String
    public var rows: [QualityChecklistRow]
}

public enum Quality {
    /// Checkliste (Reihenfolge der Anzeige: A, B, D, C).
    public static let checklist: [QualityChecklistGroup] = [
        QualityChecklistGroup(group: .A, title: "Kosten und Budget", rows: [
            QualityChecklistRow(field: "holder", title: "Person"), QualityChecklistRow(field: "amount", title: "Betrag"),
            QualityChecklistRow(field: "cat", title: "Kategorie"), QualityChecklistRow(field: "cycle", title: "Zahlungsrhythmus"),
            QualityChecklistRow(field: "inc", title: "Einnahmen: Betrag, Person"),
        ]),
        QualityChecklistGroup(group: .B, title: "Fristen", rows: [
            QualityChecklistRow(field: "due", title: "Fälligkeit"), QualityChecklistRow(field: "notice", title: "Kündigungsfrist und Laufzeit"),
        ]),
        QualityChecklistGroup(group: .D, title: "Kündigen", rows: [
            QualityChecklistRow(field: "via", title: "Kündigungsweg gewählt"), QualityChecklistRow(field: "ref", title: "Kunden- oder Vertragsnummer"),
            QualityChecklistRow(field: "link", title: "Link (Online)"), QualityChecklistRow(field: "mail", title: "E-Mail-Adresse (E-Mail)"),
            QualityChecklistRow(field: "addr", title: "Adresse des Vertragspartners (Brief)"), QualityChecklistRow(field: "sender", title: "Absender der Personen"),
        ]),
        QualityChecklistGroup(group: .C, title: "Vertragspartner", rows: [
            QualityChecklistRow(field: "logo", title: "Logo"),
        ]),
    ]

    public static let checklistTitle = "Was geprüft wird"
    public static let completeBadge = "vollständig"
    public static let footnote = "Tippe auf «offen», um die Einträge zu sehen. Gekündigte und abgelaufene Verträge sowie ignorierte Hinweise zählen nicht. Nicht überwachte Verträge, Pflichtverträge und Steuern brauchen keine Frist. Adresse, E-Mail und Link werden nur für den gewählten Kündigungsweg verlangt."
    public static let emptyText = "Noch keine laufenden Verträge. Sobald du welche erfasst, siehst du hier, was fehlt."

    /// Offene Punkte (Regeln der Web-App mit den Fixes M5 (nur laufende Verträge), N2 («jederzeit» mit Frist ist vollständig)
    /// und N4 (Brief ohne Vertragspartner braucht eine Adresse)). `hasFile` prüft, ob eine Logo-Datei vorhanden ist.
    public static func report(_ data: AppData, today: Day, hasFile: (String) -> Bool = { _ in true }) -> QualityReport {
        let calc = Calc(data: data, today: today)
        let ignored = Set(data.settings.qualityIgnored)
        var out: [QualityGroup: [QualityIssue]] = [.A: [], .B: [], .C: [], .D: []]
        var nIg = 0
        var hUsed: [UUID: Int] = [:]
        var hOrder: [UUID] = []
        var pNeed = Set<UUID>()
        var relevantPartners = Set<UUID>()
        let catIDs = Set(data.categories.map { $0.id })

        func add(_ g: QualityGroup, _ subject: QualitySubject, _ crit: QualityCriterion, name: String, sub: String, why: String, level: Int = 0) {
            let key = subject.code + ":" + subject.id.uuidString + ":" + crit.rawValue
            if ignored.contains(key) {
                nIg += 1
                return
            }
            out[g, default: []].append(QualityIssue(group: g, criterion: crit, subject: subject, key: key, name: name, subtitle: sub, reason: why, senderLevel: level))
        }

        let considered = data.contracts.filter { calc.isActive($0) }
        for c in considered {
            let pn = data.partnerName(of: c)
            let nm = !c.label.isEmpty ? c.label : (!pn.isEmpty ? pn : "Ohne Namen")
            let sub = (!pn.isEmpty && !c.label.isEmpty) ? pn : ""
            let s = QualitySubject.contract(c.id)
            if c.holderIDs.isEmpty { add(.A, s, .holder, name: nm, sub: sub, why: "Keine Person") }
            if !(c.amount > 0) { add(.A, s, .amount, name: nm, sub: sub, why: "Betrag fehlt oder ist 0") }
            if let cid = c.categoryID {
                if !catIDs.contains(cid) {
                    add(.A, s, .cat, name: nm, sub: sub, why: "Kategorie gibt es nicht mehr")
                } else if data.category(cid)?.name == "Sonstiges" {
                    // wie Web: wörtlich der Name «Sonstiges»
                    add(.A, s, .cat, name: nm, sub: sub, why: "Kategorie «Sonstiges»")
                }
            } else {
                add(.A, s, .cat, name: nm, sub: sub, why: "Keine Kategorie")
            }
            if !(c.cycle > 0) { add(.A, s, .cycle, name: nm, sub: sub, why: "Zahlungsrhythmus fehlt") }
            if c.due == nil { add(.B, s, .due, name: nm, sub: sub, why: "Kein Fälligkeitsdatum") }
            if c.cancelPer == nil, let pid = c.partnerID { relevantPartners.insert(pid) }
            // Kündigen: je nach Kündigungsweg (nicht bei Steuern und bereits gekündigten)
            if !calc.isFixed(c) && c.cancelPer == nil {
                let via = calc.cancVia(c)
                if via == .none {
                    add(.D, s, .via, name: nm, sub: sub, why: "Kündigungsweg festlegen")
                } else {
                    if c.customerNo.isEmpty && c.contractNo.isEmpty { add(.D, s, .ref, name: nm, sub: sub, why: "Kundennummer fehlt") }
                    if via == .online && calc.cancLink(c).isEmpty { add(.D, s, .link, name: nm, sub: sub, why: "Kündigungslink fehlt") }
                    if via == .mail && c.mail.trimmingCharacters(in: .whitespaces).isEmpty { add(.D, s, .mail, name: nm, sub: sub, why: "E-Mail-Adresse fehlt") }
                    if via == .post {
                        if let pid = c.partnerID {
                            pNeed.insert(pid)
                        } else {
                            add(.D, s, .addr, name: nm, sub: sub, why: "Adresse fehlt (Kündigung per Brief)")
                        }
                    }
                    let lv = via == .post ? 2 : (via == .mail ? 1 : 0)
                    for h in c.holderIDs {
                        if hUsed[h] == nil { hOrder.append(h) }
                        hUsed[h] = Swift.max(hUsed[h] ?? 0, lv)
                    }
                }
            }
            // Frist: nur bei überwachten Verträgen; fehlt die Frist oder lässt sich kein Termin berechnen.
            // Frist 0 bei Termin auf Quartal/Halbjahr/Jahr/Vertragsjahr oder fester Laufzeit: Kündigung am letzten Tag ist kaum je richtig
            if c.cancelPer == nil && !c.noWatch && !c.mandatory && !calc.isFixed(c) {
                let anytimeWithNotice = c.end == nil && c.cancelTerm == .anytime && c.notice > 0
                if calc.noticeDeadline(c) == nil {
                    if !anytimeWithNotice {
                        add(.B, s, .notice, name: nm, sub: sub, why: (c.notice == 0 && c.cancelTerm == .anytime) ? "Keine Kündigungsfrist" : "Laufzeit oder Rhythmus fehlt")
                    }
                } else if c.notice == 0 && (c.end != nil || [CancelTerm.contractYear, .yearEnd, .quarterEnd, .halfYearEnd].contains(c.cancelTerm)) {
                    add(.B, s, .notice, name: nm, sub: sub, why: "Keine Kündigungsfrist")
                }
            }
        }
        for i in data.incomes {
            let s = QualitySubject.income(i.id)
            if i.holderID == nil { add(.A, s, .holder, name: i.title, sub: "Einnahme", why: "Keine Person") }
            if !(i.amount > 0) { add(.A, s, .amount, name: i.title, sub: "Einnahme", why: "Betrag fehlt oder ist 0") }
        }
        let partners = data.partners.filter { relevantPartners.contains($0.id) }.stableSorted { Format.lessDE($0.name, $1.name) }
        for p in partners {
            let n = data.contracts.filter { $0.partnerID == p.id }.count
            let s = QualitySubject.partner(p.id)
            let sub = Format.count(n, "Vertrag", "Verträge")
            let hasLogo = (p.logoID.map { !$0.isEmpty && hasFile($0) }) ?? false
            if !hasLogo { add(.C, s, .logo, name: p.name, sub: sub, why: "Kein Logo") }
            if p.address.isEmpty && pNeed.contains(p.id) { add(.D, s, .addr, name: p.name, sub: sub, why: "Adresse fehlt (Kündigung per Brief)") }
        }
        for h in hOrder {
            guard let person = data.person(h) else { continue }
            let lv = hUsed[h] ?? 0
            let o = data.resolvedSender(h)
            let s = QualitySubject.person(h)
            if lv >= 2 && !o.isComplete {
                add(.D, s, .sender, name: person.name, sub: "Person · für Kündigung per Brief", why: "Absender unvollständig", level: 2)
            } else if lv == 1 && o.first.isEmpty && o.last.isEmpty {
                add(.D, s, .sender, name: person.name, sub: "Person · für Kündigung per E-Mail", why: "Name des Absenders fehlt", level: 1)
            }
        }
        return QualityReport(A: out[.A] ?? [], B: out[.B] ?? [], C: out[.C] ?? [], D: out[.D] ?? [], ignoredCount: nIg,
                             contractCount: considered.count, incomeCount: data.incomes.count)
    }

    /// Kopf der Seite: «3 offene Punkte.» bzw. «Sauber gepflegt. Alle 12 Verträge sind vollständig.»
    public static func headline(_ r: QualityReport) -> (title: String, text: String, clean: Bool)? {
        if r.contractCount == 0 { return nil }
        if r.totalCount > 0 {
            return (Format.count(r.totalCount, "offener Punkt", "offene Punkte") + ".", "Tippe unten auf «offen», um sie zu erledigen.", false)
        }
        return ("Sauber gepflegt. " + (r.contractCount == 1 ? "Dein Vertrag ist" : "Alle \(r.contractCount) Verträge sind") + " vollständig.",
                "Kosten, Budget, Fristen und Kündigungen stimmen.", true)
    }

    /// Kopf der Checkliste: «12 Verträge, 2 Einnahmen».
    public static func checklistSubtitle(_ r: QualityReport) -> String {
        Format.count(r.contractCount, "Vertrag", "Verträge") + (r.incomeCount > 0 ? ", " + Format.count(r.incomeCount, "Einnahme", "Einnahmen") : "")
    }

    /// Übersicht in «Verwalten»: «–», «3 Einträge offen» oder «Sauber gepflegt ✓».
    public static func summary(_ r: QualityReport) -> String {
        if r.contractCount == 0 { return "–" }
        let n = r.affectedCount
        return n > 0 ? Format.count(n, "Eintrag offen", "Einträge offen") : "Sauber gepflegt ✓"
    }

    /// «2 ignoriert»
    public static func ignoredText(_ r: QualityReport) -> String? {
        r.ignoredCount > 0 ? "\(r.ignoredCount) ignoriert" : nil
    }
}
