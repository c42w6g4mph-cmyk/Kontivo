import Foundation

// MARK: - Vollständigkeit (Web c8a6e62 / 9b5dc06, v120–v134)
//
// Ein zentraler Ablauf statt Prüfliste: 1 Logos (Raster), 2 Fristen (eine Frage pro Vertrag), 3 Absender (pro Person).
// Kündigungsweg und Kontaktdaten kommen still aus dem Katalog (beim Start bestätigt), Kundennummer/Partneradresse fragt erst der Brief.
// «Startklar» = Logo (oder bewusst keins), berechenbare Frist (wenn überwacht), Absender der Personen (ausser Kündigung online).

/// Was einem Vertrag noch fehlt (Web `vkNeeds().per[id]`: "logo", "term", "snd").
public enum CompletenessNeed: String, Hashable, Sendable, CaseIterable {
    case logo, term, sender

    /// Bezeichnung im Hinweis des Vertragsdetails
    public var label: String {
        switch self {
        case .logo: return "Logo"
        case .term: return "Kündigungsfrist"
        case .sender: return "Absender-Adresse"
        }
    }
}

/// Ergebnis von `Completeness.report` (Web `vkNeeds`).
public struct CompletenessReport: Hashable, Sendable {
    /// Fehlende Angaben je laufendem, nicht gekündigtem Vertrag (Reihenfolge logo, term, sender)
    public var per: [UUID: [CompletenessNeed]]
    /// Vertragspartner ohne Logo (nicht bewusst «Ohne Logo»), Reihenfolge des ersten Vertrags
    public var logoPartners: [UUID]
    /// Verträge, deren Frist sich nicht berechnen lässt
    public var termContracts: [UUID]
    /// Personen ohne vollständigen Absender (Reihenfolge der Personenliste)
    public var senderPersons: [UUID]
    /// Geprüfte Verträge
    public var total: Int
    /// davon startklar
    public var ready: Int

    public var open: Int { total - ready }

    /// Prozent startklar (`vkPct`): ohne Verträge 100
    public var percent: Int {
        total > 0 ? Int(Format.jsRound(Double(ready) / Double(total) * 100)) : 100
    }

    /// Anzahl Fragen: Logos zählen als eine (`vkQCount` beim Start)
    public var questionCount: Int { (logoPartners.isEmpty ? 0 : 1) + termContracts.count + senderPersons.count }

    /// Alle startklar (oder keine Verträge)
    public var isComplete: Bool { ready == total }
}

/// Eingaben der Fristen-Frage (Web `vk.tdraft` + `vk.tmode`).
public struct CompletenessTermDraft: Hashable, Sendable {
    public enum Mode: String, Hashable, Sendable {
        /// «Jederzeit kündbar»
        case open
        /// «Feste Laufzeit»
        case fixed
        /// «Nicht kündbar» (speichert sofort)
        case tax
    }

    /// nil = noch nichts gewählt
    public var mode: Mode?
    /// Text des Eingabefelds «Kündigungsfrist»
    public var notice: String
    public var noticeUnit: NoticeUnit
    /// «Kündbar» (nur jederzeit kündbar)
    public var cancelTerm: CancelTerm
    /// «Läuft bis» (nur feste Laufzeit)
    public var end: Day?
    /// «Verlängert sich danach»: 0 = nicht automatisch, sonst Monate (1, 12, 24)
    public var renew: Int

    public init(mode: Mode? = nil, notice: String = "", noticeUnit: NoticeUnit = .months, cancelTerm: CancelTerm = .anytime,
                end: Day? = nil, renew: Int = 12) {
        self.mode = mode
        self.notice = notice
        self.noticeUnit = noticeUnit
        self.cancelTerm = cancelTerm
        self.end = end
        self.renew = renew
    }
}

/// Ausgang von «Weiter» bei der Fristen-Frage.
public enum CompletenessTermOutcome: Equatable, Sendable {
    /// gespeichert, weiter zur nächsten Frage
    case saved
    /// nichts gespeichert, Toast zeigen
    case invalid(String)
    /// gespeichert, aber die Frist lässt sich noch nicht berechnen (Toast, auf der Frage bleiben)
    case stillMissing(String)
}

public enum Completeness {
    // MARK: Regeln

    /// Frist fehlt (Web `vkTermNeed`): nur überwachte, kündbare, nicht gekündigte Verträge; ignorierter Datenqualitäts-Hinweis
    /// «Kündigungsfrist» zählt als erledigt; feste Laufzeit ohne Verlängerung läuft einfach aus.
    public static func termNeed(_ c: Contract, calc: Calc) -> Bool {
        if c.cancelPer != nil || c.noWatch || c.mandatory || calc.isFixed(c) { return false }
        if calc.data.settings.qualityIgnored.contains("c:" + c.id.uuidString + ":notice") { return false }
        if c.end != nil && c.renewMonths == 0 { return false }
        if calc.noticeDeadline(c) == nil {
            let anyNotice = c.end == nil && c.cancelTerm == .anytime && c.notice > 0
            return !anyNotice
        }
        return c.notice == 0 && (c.end != nil || [CancelTerm.contractYear, .yearEnd, .quarterEnd, .halfYearEnd].contains(c.cancelTerm))
    }

    /// Schlüssel für «Ohne Logo» (Web: Name klein, ohne Leerzeichen am Rand)
    public static func logoSkipKey(_ partnerName: String) -> String { Partners.sameNameKey(partnerName) }

    /// Was fehlt (Web `vkNeeds(only)`). `only`: nur dieser Vertrag (Hinweis im Detail, Ablauf für einen Vertrag).
    /// `hasFile` prüft, ob eine Logo-Datei vorhanden ist.
    public static func report(_ data: AppData, today: Day, only: UUID? = nil, hasFile: (String) -> Bool = { _ in true }) -> CompletenessReport {
        let calc = Calc(data: data, today: today)
        let skip = Set(data.settings.logoSkip)
        var per: [UUID: [CompletenessNeed]] = [:]
        var logos: [UUID] = []
        var terms: [UUID] = []
        var senders = Set<UUID>()
        var total = 0, ready = 0
        for c in data.contracts {
            if !calc.isActive(c) || c.cancelPer != nil { continue }
            if let o = only, c.id != o { continue }
            var r: [CompletenessNeed] = []
            if let p = data.partner(c.partnerID), !p.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let hasLogo = (p.logoID.map { !$0.isEmpty && hasFile($0) }) ?? false
                if !hasLogo && !skip.contains(logoSkipKey(p.name)) {
                    r.append(.logo)
                    if !logos.contains(p.id) { logos.append(p.id) }
                }
            }
            if termNeed(c, calc: calc) {
                r.append(.term)
                terms.append(c.id)
            }
            if !calc.isFixed(c) && calc.cancVia(c) != .online {
                for h in c.holderIDs where !data.resolvedSender(h).isComplete {
                    if !r.contains(.sender) { r.append(.sender) }
                    senders.insert(h)
                }
            }
            total += 1
            if r.isEmpty { ready += 1 }
            per[c.id] = r
        }
        let snd = data.persons.map { $0.id }.filter { senders.contains($0) }
        return CompletenessReport(per: per, logoPartners: logos, termContracts: terms, senderPersons: snd, total: total, ready: ready)
    }

    /// Katalog-Ergänzungen beim Start (Web `vkAutoPlan`): Kontaktdaten wie «Kontaktdaten ergänzen» plus Kündigungsweg,
    /// nur leere Felder.
    public static func autoPlan(_ data: AppData, today: Day) -> [CatalogFillItem] {
        let calc = Calc(data: data, today: today)
        var plan = data.catalogFillPlan()
        for c in data.contracts {
            if c.status == .cancelled || c.cancelChannel != nil || calc.isFixed(c) { continue }
            guard let t = Catalog.match(names: [data.partnerName(of: c), c.label], currency: c.currency), let ch = t.cancelChannel else { continue }
            if let i = plan.firstIndex(where: { $0.contractID == c.id }) {
                plan[i].cancelChannel = ch
            } else {
                var it = CatalogFillItem(contractID: c.id, entryName: t.name, confirmed: t.confirmed)
                it.cancelChannel = ch
                plan.append(it)
            }
        }
        return plan
    }

    // MARK: Texte

    public static let title = "Vollständigkeit"

    /// Zeile unter «Mehr → Verwalten»: Plakette («3 offen» bzw. «Startklar»; ohne Verträge leer)
    public static func badge(_ r: CompletenessReport) -> String {
        if r.total == 0 { return "" }
        return r.open > 0 ? "\(r.open) offen" : "Startklar"
    }

    /// Vorlesetext der Zeile unter «Mehr»
    public static func accessibilityLabel(_ r: CompletenessReport) -> String {
        "Vollständigkeit: " + (r.total == 0 ? "keine Verträge"
            : (r.open > 0 ? Format.count(r.open, "Vertrag", "Verträge") + " noch nicht startklar" : "alle Verträge startklar"))
    }

    /// Startseite: Überschrift unter dem Ring
    public static func startHeadline(percent p: Int) -> String {
        p >= 75 ? "Fast geschafft!" : (p >= 40 ? "Gute Basis!" : "Los geht’s!")
    }

    /// Startseite: «Noch **2 kurze Fragen**, dann …» (fett markiert für AttributedString/Markdown)
    public static func startText(questions q: Int) -> String {
        q > 0 ? "Noch **" + Format.count(q, "kurze Frage", "kurze Fragen") + "**, dann behält Kontivo jede Frist im Blick und bereitet Kündigungen für dich vor."
            : "Kontivo kann die fehlenden Angaben selbst ergänzen."
    }

    /// «✓ 7 Verträge ergänzt Kontivo aus dem Anbieter-Katalog»
    public static func autoText(_ n: Int) -> String {
        "✓ " + Format.count(n, "Vertrag", "Verträge") + " ergänzt Kontivo aus dem Anbieter-Katalog"
    }

    /// Geschätzte Minuten (15 s je Frist, 30 s je Absender, 20 s für die Logos), mindestens 1
    public static func minutes(_ r: CompletenessReport) -> Int {
        let s = Double(r.termContracts.count * 15 + r.senderPersons.count * 30 + (r.logoPartners.isEmpty ? 0 : 20))
        return Swift.max(1, Int(Format.jsRound(s / 60)))
    }

    /// Hauptknopf der Startseite: «Los geht’s · ca. 1 Minute» bzw. «Ergänzen»
    public static func goTitle(_ r: CompletenessReport) -> String {
        if r.questionCount == 0 { return "Ergänzen" }
        let m = minutes(r)
        return "Los geht’s · ca. \(m)" + (m == 1 ? " Minute" : " Minuten")
    }

    public static let emptyTitle = "Noch keine Verträge"
    public static let emptyText = "Sobald du Verträge erfasst, zeigt Kontivo hier, was noch fehlt."
    public static let laterTitle = "Später"
    public static let detailLink = "Alle Prüfungen im Detail"

    /// Fortschritt rechts: einzelner Vertrag «startklar»/«fast startklar», sonst «60 % startklar» (ab 1 %)
    public static func gainText(_ r: CompletenessReport, single: Bool) -> String? {
        if single { return r.isComplete ? "startklar" : "fast startklar" }
        return r.percent > 0 ? "\(r.percent) % startklar" : nil
    }

    // Logos
    public static let logoStepLabel = "Schritt 1 · Logos"
    public static let logoQuestionFound = "Passen diese Logos?"
    public static let logoQuestionNone = "Logos ergänzen"
    public static let logoTextFound = "Tippe ein Logo an, um es zu ändern. Falsche abwählen geht auch."
    public static let logoTextNone = "Für diese Vertragspartner hat Kontivo nichts gefunden. Tippe an, um selbst zu suchen."
    public static let logoTextOffline = "Ohne Internet findet Kontivo keine Logos. Du kannst den Schritt überspringen."
    public static let logoSearching = "Kontivo sucht Logos …"

    /// «1 Logo übernehmen», «3 Logos übernehmen», ohne Auswahl «Weiter»
    public static func logoApplyTitle(_ n: Int) -> String {
        n == 0 ? "Weiter" : (n == 1 ? "1 Logo übernehmen" : "\(n) Logos übernehmen")
    }

    /// «Frage 2 von 4»
    public static func questionLabel(_ i: Int, of n: Int) -> String { "Frage \(i) von \(n)" }

    // Fristen
    public static func termQuestion(_ name: String) -> String { "Wie ist «" + name + "» kündbar?" }

    /// Unterzeile «Damit Kontivo dich rechtzeitig … Üblich bei Swisscom: 2 Monate auf Monatsende.»
    public static func termText(catalog t: CatalogEntry?) -> String {
        var s = "Damit Kontivo dich rechtzeitig vor der Frist erinnert."
        if let h = catalogHint(t) { s += " " + h + "." }
        return s
    }

    /// «Üblich bei Swisscom: 60 Tage auf Monatsende» (nur mit Frist im Katalog)
    public static func catalogHint(_ t: CatalogEntry?) -> String? {
        guard let t = t, t.notice > 0 else { return nil }
        let one = t.notice == 1
        let units: [NoticeUnit: String] = [.months: one ? "Monat" : "Monate", .weeks: one ? "Woche" : "Wochen", .days: one ? "Tag" : "Tage", .dayOfMonth: ". im Monat"]
        let terms: [CancelTerm: String] = [.monthEnd: "auf Monatsende", .quarterEnd: "auf Quartalsende", .yearEnd: "auf Jahresende",
                                           .contractYear: "auf Ende Vertragsjahr", .period: "auf Ende Periode", .halfYearEnd: "auf Halbjahresende"]
        var s = "Üblich bei " + t.name + ": \(t.notice) " + (units[t.noticeUnit] ?? "")
        if t.cancelTerm != .anytime { s += " " + (terms[t.cancelTerm] ?? "") }
        return s
    }

    /// Name in der Frage: Vertragspartner, sonst Titel
    public static func termName(_ c: Contract, data: AppData) -> String {
        let p = data.partnerName(of: c).trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty ? data.title(of: c) : p
    }

    /// Unterzeile neben dem Logo: «Handy · 59.90 CHF monatlich»
    public static func termWho(_ c: Contract, calc: Calc) -> String {
        let nm = termName(c, data: calc.data)
        return (!c.label.isEmpty && c.label != nm ? c.label + " · " : "") + Format.money(calc.curPrice(c), c.currency) + " "
            + c.currency.rawValue + " " + (Format.cycleText(c.cycle) ?? "")
    }

    /// Kacheln: Symbol, Titel, Untertitel
    public static let termModes: [(mode: CompletenessTermDraft.Mode, icon: String, title: String, subtitle: String)] = [
        (.open, "↺", "Jederzeit kündbar", "z.B. Abo, Handy ohne Mindestlaufzeit"),
        (.fixed, "▦", "Feste Laufzeit", "läuft bis zu einem Datum, verlängert sich oft"),
        (.tax, "✕", "Nicht kündbar", "z.B. Steuern, Gebühren"),
    ]
    /// Auswahl «Kündbar»
    public static let termOptions: [(value: CancelTerm, title: String)] = [
        (.anytime, "jederzeit"), (.monthEnd, "auf Monatsende"), (.quarterEnd, "auf Quartalsende"), (.yearEnd, "auf Jahresende"),
        (.contractYear, "auf Ende Vertragsjahr"), (.period, "auf Ende Zahlungsperiode"),
    ]
    /// Auswahl «Verlängert sich danach»
    public static let renewOptions: [(value: Int, title: String)] = [(0, "nicht automatisch"), (1, "um 1 Monat"), (12, "um 12 Monate"), (24, "um 24 Monate")]
    /// Einheiten der Frist
    public static let unitOptions: [(value: NoticeUnit, title: String)] = [(.months, "Monate"), (.weeks, "Wochen"), (.days, "Tage")]
    public static let termSkip = "Weiss ich nicht · überspringen"
    public static let noticeMissing = "Bitte die Kündigungsfrist eintragen"
    public static let endMissing = "Bitte das Datum eintragen, bis wann der Vertrag läuft"
    public static let stillMissing = "Damit lässt sich noch keine Frist berechnen – bitte prüfen"

    /// Vorbelegung aus dem Vertrag bzw. dem Katalog (Web `vkTermInit`)
    public static func termDraft(_ c: Contract, data: AppData) -> CompletenessTermDraft {
        let t = Catalog.match(names: [data.partnerName(of: c), c.label], currency: c.currency)
        var d = CompletenessTermDraft()
        let n = c.notice > 0 ? c.notice : (t?.notice ?? 0)
        d.notice = n > 0 ? String(n) : ""
        d.noticeUnit = c.notice > 0 ? c.noticeUnit : (t.map { $0.notice > 0 ? $0.noticeUnit : c.noticeUnit } ?? c.noticeUnit)
        d.cancelTerm = c.cancelTerm != .anytime ? c.cancelTerm : (t?.cancelTerm ?? .anytime)
        d.end = c.end
        // feste Laufzeit ohne Verlängerung bleibt ohne
        d.renew = c.renewMonths > 0 ? c.renewMonths : (c.end != nil ? 0 : 12)
        if c.end != nil {
            d.mode = .fixed
        } else if c.notice > 0 || c.cancelTerm != .anytime || (t.map { $0.notice > 0 || $0.cancelTerm != .anytime } ?? false) {
            d.mode = .open
        }
        return d
    }

    // Absender
    public static func senderQuestion(name: String, personCount: Int) -> String {
        personCount > 1 ? "Adresse von " + name : "Deine Adresse"
    }

    public static let senderText = "Kommt als Absender in jeden Kündigungsbrief. Einmal eintragen, fertig."
    public static let senderSkip = "Später eintragen"
    public static let senderMissing = "Bitte Name, Strasse und Ort eintragen"

    // Abschluss
    public static func endTitle(single: Bool) -> String { single ? "Startklar" : "Vollständigkeit" }

    public static func endHeadline(_ r: CompletenessReport, single: Bool) -> String {
        r.isComplete ? (single ? "Startklar!" : "100 % – alles komplett!") : "\(r.percent) % – gut gemacht!"
    }

    public static func endText(_ r: CompletenessReport) -> String {
        r.isComplete ? "Deine Verträge sind bereit." : "Den Rest kannst du jederzeit unter Mehr → Vollständigkeit ergänzen."
    }

    public static let endList = ["Kontivo erinnert dich vor jeder Frist", "Kündigungen sind mit einem Tipp vorbereitet", "Kosten und Budget stimmen"]

    // Hinweis im Vertragsdetail (Web `vkHintHtml`)
    public struct Hint: Hashable, Sendable {
        /// «1 Angabe fehlt noch» / «2 Angaben fehlen noch»
        public var title: String
        /// «Logo · Kündigungsfrist – dann erinnert Kontivo rechtzeitig»
        public var detail: String
        /// «Ergänzen ›»
        public var action: String
    }

    /// Hinweis für einen laufenden, nicht gekündigten Vertrag; nil, wenn nichts fehlt.
    public static func hint(contract id: UUID, data: AppData, today: Day, hasFile: (String) -> Bool = { _ in true }) -> Hint? {
        let calc = Calc(data: data, today: today)
        guard let c = data.contract(id), calc.isActive(c), c.cancelPer == nil else { return nil }
        let r = report(data, today: today, only: id, hasFile: hasFile).per[id] ?? []
        if r.isEmpty { return nil }
        let why = r.contains(.term) ? "dann erinnert Kontivo rechtzeitig"
            : (r.contains(.sender) ? "dann ist die Kündigung startklar" : "dann sieht der Vertrag komplett aus")
        return Hint(title: r.count == 1 ? "1 Angabe fehlt noch" : "\(r.count) Angaben fehlen noch",
                    detail: r.map { $0.label }.joined(separator: " · ") + " – " + why, action: "Ergänzen ›")
    }
}

// MARK: - Fachaktionen

extension AppData {
    /// Katalog-Ergänzungen anwenden (Kontaktdaten und Kündigungsweg, nur leere Felder).
    public mutating func applyCompletenessAuto(_ plan: [CatalogFillItem]) {
        applyCatalogFill(plan)
    }

    /// Vertragspartner bewusst ohne Logo (Web «Ohne Logo»: `settings.logoSkip[pkey] = 1`).
    public mutating func skipLogo(partner id: UUID) {
        guard let p = partner(id) else { return }
        let k = Completeness.logoSkipKey(p.name)
        if !k.isEmpty && !settings.logoSkip.contains(k) { settings.logoSkip.append(k) }
    }

    /// Fristen-Frage speichern (Web `vkTermSave`). «Nicht kündbar» setzt `noCancel` (und entfernt «Pflichtvertrag»).
    /// Fehlt die Frist (ausser bei fester Laufzeit ohne Verlängerung) oder das Enddatum, wird nichts gespeichert.
    public mutating func saveCompletenessTerm(_ id: UUID, _ d: CompletenessTermDraft, today: Day) -> CompletenessTermOutcome {
        guard let i = contractIndex(id), let mode = d.mode else { return .invalid(Completeness.noticeMissing) }
        var nc = contracts[i]
        if mode == .tax {
            nc.noCancel = true
            nc.mandatory = false
            contracts[i] = nc
            return .saved
        }
        let nv = Format.parseNum(d.notice)
        let runsOut = mode != .open && d.renew == 0
        if !((nv ?? 0) > 0) && !runsOut { return .invalid(Completeness.noticeMissing) }
        if let v = nv, v > 0 { nc.notice = Int(Swift.min(1e6, Format.jsRound(v))) } else { nc.notice = 0 }
        nc.noticeUnit = d.noticeUnit
        nc.noCancel = false
        if mode == .open {
            nc.cancelTerm = d.cancelTerm
            nc.end = nil
            nc.renewMonths = 0
        } else {
            guard let e = d.end else { return .invalid(Completeness.endMissing) }
            nc.end = e
            nc.renewMonths = d.renew
            nc.cancelTerm = .anytime
        }
        contracts[i] = nc
        if Completeness.termNeed(nc, calc: Calc(data: self, today: today)) { return .stillMissing(Completeness.stillMissing) }
        return .saved
    }

    /// Absender aus der Frage speichern (Web `vkSndSave`): Name, Strasse, PLZ, Ort; «gleich wie» entfällt. nil = gespeichert,
    /// sonst Toast-Text.
    public mutating func saveCompletenessSender(_ id: UUID, first: String, last: String, street: String, zip: String, city: String) -> String? {
        guard let p = person(id) else { return nil }
        let t = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        let s = SenderAddress(first: t(first), last: t(last), street: t(street), zip: t(zip), city: t(city), country: p.sender.country)
        if !s.isComplete { return Completeness.senderMissing }
        setSender(id, s, sameAs: nil)
        return nil
    }

    /// «Gleich wie X»: Adresse von X übernehmen (Kette aufgelöst, Name bleibt).
    public mutating func setCompletenessSenderSame(_ id: UUID, as other: UUID) {
        guard let p = person(id), let o = person(other) else { return }
        var target = o.id
        if let s = o.sameAddressAs, s != id, person(s) != nil { target = s }
        setSender(id, p.sender, sameAs: target)
    }

    /// Personen, deren Adresse man mit «Gleich wie» übernehmen kann (Absender vollständig).
    public func completenessSameCandidates(for id: UUID) -> [Person] {
        persons.filter { $0.id != id && resolvedSender($0.id).isComplete }
    }
}
