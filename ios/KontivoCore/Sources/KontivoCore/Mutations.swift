import Foundation

/// Fehler bei Fachaktionen; `message` ist der Toast-Text der Web-App.
public enum MutationError: Error, Equatable {
    case notFound
    /// Name leer
    case emptyName
    /// Name gibt es schon (ID des vorhandenen Eintrags, z.B. zum Zusammenführen)
    case duplicateName(UUID)
    /// Kategorie mit diesem Namen gibt es schon
    case duplicateCategory(UUID)
    /// Neuer Inhaber: Namen gibt es schon
    case duplicatePerson(UUID)
    /// Mindestens ein Inhaber ist nötig
    case lastPerson
    /// «Sonstiges» lässt sich weder umbenennen noch löschen
    case fixedCategory
    /// Vertragspartner und Bezeichnung leer
    case missingTitle
    /// Keine Kategorie
    case missingCategory
    /// Betrag fehlt, ist ungültig oder negativ
    case invalidAmount
    /// Pause bis: Datum nicht in der Zukunft
    case dateNotInFuture
    /// Kündigungsfrist ungültig (negativ bzw. bei «. im Monat» nicht 1–28)
    case invalidNotice

    public var message: String {
        switch self {
        case .notFound: return "Nicht gefunden."
        case .emptyName: return "Name darf nicht leer sein"
        case .duplicateName: return "Diesen Namen gibt es schon"
        case .duplicateCategory: return "Diese Kategorie gibt es schon"
        case .duplicatePerson: return "Diese Person gibt es schon"
        case .lastPerson: return "Mindestens eine Person ist nötig"
        case .fixedCategory: return "«Sonstiges» fängt alles ohne Kategorie auf und lässt sich weder umbenennen noch löschen."
        case .missingTitle: return "Bezeichnung fehlt"
        case .missingCategory: return "Bitte eine Kategorie wählen"
        case .invalidAmount: return "Betrag prüfen"
        case .dateNotInFuture: return "Bitte ein Datum in der Zukunft wählen"
        case .invalidNotice: return "Kündigungsfrist prüfen"
        }
    }
}

/// Zuordnung in «Verträge zuordnen»: eine Person oder alle.
public enum HolderChoice: Hashable, Sendable {
    case person(UUID)
    case all
}

/// Ergebnis von «Als gekündigt markieren».
public struct CancelResult: Hashable, Sendable {
    /// Gekündigt per (läuft bis)
    public var cancelPer: Day
    /// «Gekündigt — läuft bis 30. November 2026»
    public var toast: String
    /// Pflichtvertrag: Entwurf für den neuen Anbieter (noch nicht gespeichert; Formular «Neuer Anbieter»)
    public var replacement: Contract?
    /// «Neuen Anbieter erfassen — ab 1. Dezember 2026»
    public var replacementToast: String?
    public static let replacementFormTitle = "Neuer Anbieter"
}

/// Personen mit Anzahl Verträgen (alle, auch gekündigte) und Einnahmen (`holderStats`).
public struct PersonStat: Hashable, Sendable {
    public var person: Person
    public var contracts: Int
    public var incomes: Int
}

/// Fachaktionen auf den Daten. Ansichten ändern `AppData` nur über diese Funktionen.
extension AppData {
    // MARK: Verträge

    /// Als gekündigt markieren: läuft bis termEnd (Probeabo: Tag vor Probeabo-Ende, sonst heute) und wandert danach ins Archiv.
    /// Pflichtvertrag: zusätzlich ein Entwurf für den neuen Anbieter ab dem Folgetag, ohne Kontaktdaten des alten (Fix M4).
    @discardableResult
    public mutating func markCancelled(_ id: UUID, trial: Bool, today: Day, now: Date = Date()) -> CancelResult? {
        guard let i = contractIndex(id) else { return nil }
        let calc = Calc(data: self, today: today)
        var c = contracts[i]
        let per = calc.cancelEnd(c, trial: trial) ?? today
        c.cancelPer = per
        c.cancelledOn = today
        c.review = nil
        contracts[i] = c
        var res = CancelResult(cancelPer: per, toast: "Gekündigt — läuft bis " + Format.fmtD(per), replacement: nil, replacementToast: nil)
        if c.mandatory {
            var nc = c
            nc.id = UUID()
            nc.cancelPer = nil
            nc.cancelledOn = nil
            nc.keptFor = nil
            nc.partnerID = nil
            nc.logoID = nil
            nc.logoBg = nil
            let start = per.addingDays(1)
            nc.start = start
            nc.due = start
            nc.customerNo = ""
            nc.contractNo = ""
            nc.documents = []
            nc.prices = []
            nc.extras = []
            nc.tel = ""
            nc.mail = ""
            nc.cancelURL = ""
            nc.cancelChannel = nil
            nc.note = ""
            nc.trial = nil
            nc.trialKept = nil
            nc.pauses = []
            if let e = nc.end, e <= per {
                nc.end = nil
                nc.renewMonths = 0
            }
            nc.status = .active
            nc.cancelledAt = nil
            nc.createdAt = now
            res.replacement = nc
            res.replacementToast = "Neuen Anbieter erfassen — ab " + Format.fmtD(start)
        }
        return res
    }

    /// Kündigung zurücknehmen.
    public mutating func undoCancel(_ id: UUID) {
        guard let i = contractIndex(id) else { return }
        contracts[i].cancelPer = nil
        contracts[i].cancelledOn = nil
    }

    /// «Als gekündigt ins Archiv».
    public mutating func archive(_ id: UUID, today: Day) {
        guard let i = contractIndex(id) else { return }
        contracts[i].status = .cancelled
        contracts[i].cancelledAt = today
    }

    /// «Wieder aktiv setzen».
    public mutating func reactivate(_ id: UUID) {
        guard let i = contractIndex(id) else { return }
        contracts[i].status = .active
        contracts[i].cancelledAt = nil
    }

    /// Behalten: Probeabo (`trialKept = trial`) bzw. für den aktuellen Termin (`keptFor = termEnd`).
    public mutating func keep(_ id: UUID, trial: Bool, today: Day) {
        guard let i = contractIndex(id) else { return }
        if trial {
            contracts[i].trialKept = contracts[i].trial
        } else {
            contracts[i].keptFor = Calc(data: self, today: today).termEnd(contracts[i])
        }
    }

    public static let keepToast = "Behalten — erledigt bis zum nächsten Termin"

    /// Entscheid «Behalten» zurücksetzen.
    public mutating func unkeep(_ id: UUID) {
        guard let i = contractIndex(id) else { return }
        contracts[i].keptFor = nil
    }

    /// Pausieren ab heute bis `until` (nil = bis zum Fortsetzen). Eine laufende Pause wird angepasst, nicht neu begonnen.
    public mutating func pause(_ id: UUID, until: Day?, today: Day) throws {
        guard let i = contractIndex(id) else { throw MutationError.notFound }
        if let u = until, u <= today { throw MutationError.dateNotInFuture }
        if let pi = contracts[i].pauses.lastIndex(where: { $0.contains(today) }) {
            contracts[i].pauses[pi].until = until
        } else {
            contracts[i].pauses.append(Pause(from: today, until: until))
        }
    }

    /// Toast nach dem Pausieren.
    public static func pauseToast(until: Day?) -> String {
        until.map { "Pausiert bis " + Format.fmtD($0) } ?? "Pausiert — bis du fortsetzt"
    }

    /// Auswahl «Pausieren für»: 1, 3, 6 Monate und ohne Enddatum.
    public static func pauseOptions(today: Day) -> [(title: String, detail: String, until: Day?)] {
        var out: [(title: String, detail: String, until: Day?)] = []
        for n in [1, 3, 6] {
            let u = today.addingMonths(n)
            out.append((title: n == 1 ? "1 Monat" : "\(n) Monate", detail: "bis " + Format.fmtD(u), until: u))
        }
        out.append((title: "Ohne Enddatum", detail: "bis du fortsetzt", until: nil))
        return out
    }

    /// Fortsetzen: laufende Pause endet heute (bleibt als Verlauf erhalten; leer → entfernt).
    public mutating func resume(_ id: UUID, today: Day) {
        guard let i = contractIndex(id) else { return }
        var out: [Pause] = []
        for p in contracts[i].pauses {
            if p.contains(today) {
                if p.from < today { out.append(Pause(from: p.from, until: today)) }
            } else {
                out.append(p)
            }
        }
        contracts[i].pauses = out
    }

    /// Entwurf «Duplizieren»: gleiche Formularfelder, ohne Sonderzahlungen, Dokumente, Status und Quartals-Check. Noch nicht gespeichert.
    public func duplicateDraft(_ id: UUID, now: Date = Date()) -> Contract? {
        guard var c = contract(id) else { return nil }
        c.id = UUID()
        c.extras = []
        c.documents = []
        c.status = .active
        c.cancelledAt = nil
        c.cancelPer = nil
        c.cancelledOn = nil
        c.keptFor = nil
        c.trialKept = nil
        c.pauses = []
        c.review = nil
        c.createdAt = now
        return c
    }

    /// Vertrag löschen (Dateien bleiben im Speicher).
    public mutating func deleteContract(_ id: UUID) {
        contracts.removeAll { $0.id == id }
    }

    /// Kündigungsweg speichern.
    public mutating func setCancelChannel(_ id: UUID, _ ch: CancelChannel?) {
        guard let i = contractIndex(id) else { return }
        contracts[i].cancelChannel = ch
    }

    /// Formular sichern. Bestehender Vertrag: nur die Formularfelder übernehmen (Status, Kündigung, Behalten, Pausen,
    /// Probeabo-Entscheid und Erfassungsdatum bleiben; Fix F1). Neuer Vertrag: anhängen, «zuletzt gewählte Inhaber» merken.
    @discardableResult
    public mutating func saveContract(_ draft: Contract, today: Day) throws -> UUID {
        let label = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let pn = partner(draft.partnerID)?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if label.isEmpty && pn.isEmpty { throw MutationError.missingTitle }
        guard let cid = draft.categoryID, category(cid) != nil else { throw MutationError.missingCategory }
        if !draft.amount.isFinite || draft.amount < 0 { throw MutationError.invalidAmount }
        // wie Web `noticeVal`: ganze Zahl ≥ 0, bei «. im Monat» 1–28 (0 = keine Frist)
        if draft.notice < 0 || (draft.noticeUnit == .dayOfMonth && draft.notice != 0 && !(1...28).contains(draft.notice)) {
            throw MutationError.invalidNotice
        }
        var d = draft
        // Inhaber in der Reihenfolge der Personenliste (Web `holdersSorted`)
        d.holderIDs = persons.map { $0.id }.filter { draft.holderIDs.contains($0) }
            + draft.holderIDs.filter { id in !persons.contains { $0.id == id } }
        // Kündigungslink nur bei «Online / Kundenkonto»
        if d.cancelChannel != .online { d.cancelURL = "" }
        d.label = label
        d.categoryID = cid
        d.amount = Format.round2(draft.amount)
        d.due = draft.due ?? today
        d.customerNo = d.customerNo.trimmingCharacters(in: .whitespacesAndNewlines)
        d.contractNo = d.contractNo.trimmingCharacters(in: .whitespacesAndNewlines)
        d.payAccount = d.payAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        d.cancelURL = d.cancelURL.trimmingCharacters(in: .whitespacesAndNewlines)
        d.tel = d.tel.trimmingCharacters(in: .whitespacesAndNewlines)
        d.mail = d.mail.trimmingCharacters(in: .whitespacesAndNewlines)
        d.note = d.note.trimmingCharacters(in: .whitespacesAndNewlines)
        d.extras = d.extras.filter { $0.amount.isFinite && $0.amount != 0 }.stableSorted { $0.date < $1.date }
        if d.end == nil { d.renewMonths = 0 } else { d.cancelTerm = .anytime }
        d.split = AppData.normalizedSplit(d.split, holders: d.holderIDs)
        if let i = contractIndex(d.id) {
            var c = contracts[i]
            c.label = d.label
            c.partnerID = d.partnerID
            c.categoryID = d.categoryID
            c.amount = d.amount
            c.currency = d.currency
            c.cycle = d.cycle
            c.due = d.due
            c.start = d.start
            c.end = d.end
            c.notice = d.notice
            c.noticeUnit = d.noticeUnit
            c.renewMonths = d.renewMonths
            c.cancelTerm = d.cancelTerm
            c.mandatory = d.mandatory
            c.noWatch = d.noWatch
            c.noCancel = d.noCancel
            c.isRent = d.isRent
            c.customerNo = d.customerNo
            c.contractNo = d.contractNo
            c.holderIDs = d.holderIDs
            c.payMethod = d.payMethod
            c.payAccount = d.payAccount
            c.cancelChannel = d.cancelChannel
            c.cancelURL = d.cancelURL
            c.trial = d.trial
            c.tel = d.tel
            c.mail = d.mail
            c.note = d.note
            c.colorHex = d.colorHex
            c.logoID = d.logoID
            c.logoBg = d.logoBg
            c.prices = d.prices
            c.documents = d.documents
            c.extras = d.extras
            c.split = d.split
            contracts[i] = c
        } else {
            d.status = .active
            d.cancelledAt = nil
            d.cancelPer = nil
            d.cancelledOn = nil
            d.keptFor = nil
            d.trialKept = nil
            d.pauses = []
            contracts.append(d)
            if persons.count > 1 && !d.holderIDs.isEmpty && d.holderIDs != settings.lastHolderIDs {
                settings.lastHolderIDs = d.holderIDs
            }
        }
        return d.id
    }

    /// Prozent auf 4 Nachkommastellen (Web `Math.round(x*1e4)/1e4`).
    public static func roundPercent(_ v: Double) -> Double { (v * 10_000).rounded() / 10_000 }

    /// Aufteilung fürs Speichern (Web `saveForm`): ab 2 Inhabern, jeder mit Anteil; letzter Inhaber = 100 − übrige (≥ 0);
    /// Summe ≠ 100 oder unvollständig → leer (= gleich); Gleichverteilung → leer. Prozent mit 4 Nachkommastellen.
    public static func normalizedSplit(_ split: [SplitShare], holders: [UUID]) -> [SplitShare] {
        if holders.count < 2 || split.isEmpty { return [] }
        var o: [UUID: Double] = [:]
        for s in split { o[s.personID] = roundPercent(Swift.max(0, Swift.min(100, s.percent))) }
        for h in holders where o[h] == nil { return [] }
        let others = holders.dropLast().reduce(0.0) { $0 + (o[$1] ?? 0) }
        if others > 100.0001 { return [] }
        o[holders[holders.count - 1]] = Swift.max(0, roundPercent(100 - others))
        let eq = 100.0 / Double(holders.count)
        if holders.allSatisfy({ abs((o[$0] ?? 0) - eq) < 0.001 }) { return [] }
        return holders.map { SplitShare(personID: $0, percent: o[$0] ?? 0) }
    }

    /// Gleichmässige Vorbelegung für «Individuell» (Web `paintSplit`): 100 / n für alle.
    public static func equalSplit(holders: [UUID]) -> [SplitShare] {
        if holders.count < 2 { return [] }
        let eq = 100.0 / Double(holders.count)
        return holders.map { SplitShare(personID: $0, percent: eq) }
    }

    // MARK: Quartals-Check

    /// Antwort im Quartals-Check setzen (gleiche Antwort nochmals → zurücknehmen).
    public mutating func setReview(_ id: UUID, _ v: ReviewVerdict, today: Day) {
        guard let i = contractIndex(id) else { return }
        if contracts[i].review?.verdict == v && Calc(data: self, today: today).freshReview(contracts[i]) == v {
            contracts[i].review = nil
        } else {
            contracts[i].review = ContractReview(verdict: v, at: today)
        }
    }

    /// «Doch behalten» in «Fristen».
    public mutating func clearReview(_ id: UUID) {
        guard let i = contractIndex(id) else { return }
        contracts[i].review = nil
    }

    /// Inhaber-Vorbelegung für einen neuen Vertrag: zuletzt gewählte (sofern vorhanden), sonst erste Person.
    public var defaultHolderIDs: [UUID] {
        let ids = Set(persons.map { $0.id })
        let last = settings.lastHolderIDs.filter { ids.contains($0) }
        if !last.isEmpty { return last }
        return persons.first.map { [$0.id] } ?? []
    }

    // MARK: Einnahmen

    /// Einnahme sichern (Quelle oder Bezeichnung nötig, Betrag ≥ 0).
    @discardableResult
    public mutating func saveIncome(_ draft: Income, today: Day) throws -> UUID {
        var d = draft
        d.name = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
        d.label = d.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.name.isEmpty && d.label.isEmpty { throw MutationError.missingTitle }
        if !d.amount.isFinite || d.amount < 0 { throw MutationError.invalidAmount }
        d.amount = Format.round2(d.amount)
        d.due = d.due ?? today
        d.note = d.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = incomeIndex(d.id) {
            d.createdAt = incomes[i].createdAt
            if d.colorHex == nil { d.colorHex = incomes[i].colorHex }
            incomes[i] = d
        } else {
            incomes.append(d)
        }
        return d.id
    }

    public mutating func deleteIncome(_ id: UUID) {
        incomes.removeAll { $0.id == id }
    }

    /// Empfänger einer Einnahme setzen (genau eine Person).
    @discardableResult
    public mutating func setIncomeRecipient(_ id: UUID, person: UUID?) -> Bool {
        guard let i = incomeIndex(id), incomes[i].holderID != person else { return false }
        incomes[i].holderID = person
        return true
    }

    // MARK: Personen

    /// Personen mit Zählern (Reihenfolge der Liste).
    public func personStats() -> [PersonStat] {
        persons.map { p in
            PersonStat(person: p, contracts: contracts.filter { $0.holderIDs.contains(p.id) }.count,
                       incomes: incomes.filter { $0.holderID == p.id }.count)
        }
    }

    /// Neue Person (Name getrimmt, eindeutig ohne Gross/Klein).
    @discardableResult
    public mutating func addPerson(_ name: String) throws -> UUID {
        let n = Format.collapseSpaces(name)
        if n.isEmpty { throw MutationError.emptyName }
        if let ex = persons.first(where: { $0.name.lowercased() == n.lowercased() }) { throw MutationError.duplicatePerson(ex.id) }
        let p = Person(name: n)
        persons.append(p)
        return p.id
    }

    /// Umbenennen. Gibt es den Namen schon, kommt `duplicateName(id)` (die App fragt dann nach `mergePerson`).
    public mutating func renamePerson(_ id: UUID, to name: String) throws {
        guard let i = personIndex(id) else { throw MutationError.notFound }
        let n = Format.collapseSpaces(name)
        if n.isEmpty { throw MutationError.emptyName }
        if n == persons[i].name { return }
        if let ex = persons.first(where: { $0.id != id && $0.name.lowercased() == n.lowercased() }) { throw MutationError.duplicateName(ex.id) }
        persons[i].name = n
    }

    /// Zusammenführen: alle Einträge von `from` gehen an `to`, `from` wird entfernt. Absender, Unterschrift und Bild wandern mit,
    /// wenn `to` noch keine eigenen hat (`sndRename`/`avMove`). Wer «gleiche Adresse wie from» hatte, zeigt auf `to`.
    public mutating func mergePerson(_ from: UUID, into to: UUID) {
        guard from != to, let fi = personIndex(from), let ti = personIndex(to) else { return }
        let src = persons[fi]
        var target = persons[ti]
        if target.sender.isEmpty && target.sameAddressAs == nil {
            target.sender = src.sender
            target.sameAddressAs = src.sameAddressAs == to ? nil : src.sameAddressAs
        }
        if target.signatureJPEG == nil { target.signatureJPEG = src.signatureJPEG }
        if target.avatarID == nil { target.avatarID = src.avatarID }
        persons[ti] = target
        for k in persons.indices where persons[k].sameAddressAs == from {
            if persons[k].id == to {
                persons[k].sameAddressAs = nil
                persons[k].sender = persons[k].sender.withAddress(of: src.sender)
            } else {
                persons[k].sameAddressAs = to
            }
        }
        for i in contracts.indices where contracts[i].holderIDs.contains(from) {
            var arr: [UUID] = []
            for h in contracts[i].holderIDs {
                let r = h == from ? to : h
                if !arr.contains(r) { arr.append(r) }
            }
            // Aufteilung: Namen mitführen; fallen zwei Inhaber zusammen, gilt wieder «gleich» (Web `mapHolders`)
            if arr.count == contracts[i].holderIDs.count {
                contracts[i].split = contracts[i].split.map { SplitShare(personID: $0.personID == from ? to : $0.personID, percent: $0.percent) }
            } else {
                contracts[i].split = []
            }
            contracts[i].holderIDs = arr
        }
        for i in incomes.indices where incomes[i].holderID == from { incomes[i].holderID = to }
        settings.lastHolderIDs.removeAll { $0 == from }
        let prefix = "h:" + from.uuidString + ":"
        settings.qualityIgnored.removeAll { $0.hasPrefix(prefix) }
        persons.removeAll { $0.id == from }
    }

    /// Person löschen: mit Ziel zusammenführen, sonst aus allen Einträgen entfernen (gemeinsame behalten die übrigen Inhaber).
    /// Wer «gleiche Adresse wie» diese Person hatte, bekommt die Adresse als eigene Kopie (`sndDrop`).
    public mutating func deletePerson(_ id: UUID, transferTo: UUID?) throws {
        guard let i = personIndex(id) else { throw MutationError.notFound }
        if persons.count <= 1 { throw MutationError.lastPerson }
        if let to = transferTo, to != id {
            mergePerson(id, into: to)
            return
        }
        let src = persons[i]
        for k in persons.indices where persons[k].sameAddressAs == id {
            persons[k].sameAddressAs = nil
            persons[k].sender = persons[k].sender.withAddress(of: src.sender)
        }
        for k in contracts.indices where contracts[k].holderIDs.contains(id) {
            contracts[k].holderIDs.removeAll { $0 == id }
            contracts[k].split = []
        }
        for k in incomes.indices where incomes[k].holderID == id { incomes[k].holderID = nil }
        settings.lastHolderIDs.removeAll { $0 == id }
        let prefix = "h:" + id.uuidString + ":"
        settings.qualityIgnored.removeAll { $0.hasPrefix(prefix) }
        persons.removeAll { $0.id == id }
        if persons.isEmpty { persons.append(Person(name: "Ich")) }
    }

    /// Absender speichern. Ein ungültiges «gleich wie» (auf sich selbst oder eine Person, die selbst auf eine andere «gleich wie» ist)
    /// wird entfernt (Fix M1). Wie Web `setSnd`: Zeigt die Person neu auf Y, zeigen alle, die auf sie zeigten, direkt auf Y
    /// (keine Ketten); zeigte Y selbst auf sie, bekommt Y ihre bisherige Adresse.
    public mutating func setSender(_ id: UUID, _ s: SenderAddress, sameAs: UUID?) {
        guard let i = personIndex(id) else { return }
        let old = persons[i].sender
        let t = { (x: String) in Format.collapseSpaces(x) }
        persons[i].sender = SenderAddress(first: t(s.first), last: t(s.last), street: t(s.street), zip: t(s.zip), city: t(s.city), country: t(s.country))
        guard let o = sameAs, o != id, let other = person(o), other.sameAddressAs == nil || other.sameAddressAs == id else {
            persons[i].sameAddressAs = nil
            return
        }
        persons[i].sameAddressAs = o
        for k in persons.indices where k != i && persons[k].sameAddressAs == id {
            if persons[k].id == o {
                persons[k].sameAddressAs = nil
                persons[k].sender.street = old.street
                persons[k].sender.zip = old.zip
                persons[k].sender.city = old.city
                persons[k].sender.country = old.country
            } else {
                persons[k].sameAddressAs = o
            }
        }
    }

    /// Personen, deren Adresse man mit «Gleich wie» übernehmen kann (eigene Adresse, selbst nicht «gleich wie»).
    public func sameAddressCandidates(for id: UUID) -> [Person] {
        persons.filter { $0.id != id && $0.sameAddressAs == nil && !$0.sender.addressLines.isEmpty }
    }

    public mutating func setSignature(_ id: UUID, _ jpeg: Data?) {
        guard let i = personIndex(id) else { return }
        persons[i].signatureJPEG = jpeg
    }

    public mutating func setAvatar(_ id: UUID, _ fileID: String?) {
        guard let i = personIndex(id) else { return }
        persons[i].avatarID = (fileID ?? "").isEmpty ? nil : fileID
    }

    /// «Verträge zuordnen» (`hSet`): alle; bei 2 Personen genau diese; ab 3 Personen umschalten (Reihenfolge der Personenliste).
    /// Rückgabe: geändert?
    @discardableResult
    public mutating func applyHolderChoice(contract id: UUID, choice: HolderChoice) -> Bool {
        guard let i = contractIndex(id) else { return false }
        let all = persons.map { $0.id }
        let cur = contracts[i].holderIDs
        var arr: [UUID]
        switch choice {
        case .all:
            arr = all
        case .person(let p):
            if all.count == 2 {
                arr = [p]
            } else {
                var a = cur
                if let k = a.firstIndex(of: p) { a.remove(at: k) } else { a.append(p) }
                arr = all.filter { a.contains($0) }
            }
        }
        if arr == cur { return false }
        contracts[i].holderIDs = arr
        contracts[i].split = []
        return true
    }

    /// Toast nach dem Zuordnen: «Handy → Beide» (2 Personen) bzw. «→ Alle» (ab 3, Fix N5), «→ Lara, Sinan», «→ ohne Person».
    public func holderChoiceToast(title: String, holderIDs: [UUID]) -> String {
        if holderIDs.count == persons.count && persons.count > 1 { return title + " → " + (persons.count == 2 ? "Beide" : "Alle") }
        if holderIDs.isEmpty { return title + " → ohne Person" }
        return title + " → " + holderIDs.compactMap { person($0)?.name }.joined(separator: ", ")
    }

    /// «Alle Einträge einer Person übertragen» (Web `mapHolders`): `from` → `to`. Einträge, die beiden gehören, gehören danach
    /// nur noch `to` (keine Doppelnennung, Reihenfolge bleibt). `from` bleibt als Person bestehen. Rückgabe: Anzahl geänderter Einträge.
    @discardableResult
    public mutating func transferAll(from: UUID, to: UUID) -> Int {
        if from == to { return 0 }
        var n = 0
        for i in contracts.indices where contracts[i].holderIDs.contains(from) {
            var arr: [UUID] = []
            for h in contracts[i].holderIDs {
                let r = h == from ? to : h
                if !arr.contains(r) { arr.append(r) }
            }
            if arr != contracts[i].holderIDs {
                if arr.count == contracts[i].holderIDs.count {
                    contracts[i].split = contracts[i].split.map { SplitShare(personID: $0.personID == from ? to : $0.personID, percent: $0.percent) }
                } else {
                    contracts[i].split = []
                }
                contracts[i].holderIDs = arr
                n += 1
            }
        }
        for i in incomes.indices where incomes[i].holderID == from {
            incomes[i].holderID = to
            n += 1
        }
        return n
    }

    /// Einträge (Verträge und Einnahmen), die `a` und `b` gemeinsam gehören (Hinweis beim Übertragen: «… gehören danach nur noch «B».»).
    public func sharedEntryCount(_ a: UUID, _ b: UUID) -> Int {
        contracts.filter { $0.holderIDs.contains(a) && $0.holderIDs.contains(b) }.count
    }

    // MARK: Kategorien

    /// Verträge einer Kategorie (alle Status).
    public func contractCount(category id: UUID) -> Int {
        contracts.filter { $0.categoryID == id }.count
    }

    /// Neue Kategorie (Name eindeutig ohne Gross/Klein; Farbe Standard COLORS[(n+3)%8], Symbol «tag»).
    @discardableResult
    public mutating func addCategory(_ name: String, colorHex: String? = nil, icon: String = "tag") throws -> UUID {
        let n = Format.collapseSpaces(name)
        if n.isEmpty { throw MutationError.emptyName }
        if let ex = categories.first(where: { $0.name.lowercased() == n.lowercased() }) { throw MutationError.duplicateCategory(ex.id) }
        let c = Category(name: n, colorHex: colorHex ?? Category.newColor(existingCount: categories.count), icon: icon,
                         kind: Category.kind(forName: n, among: categories))
        categories.append(c)
        return c.id
    }

    /// Umbenennen. Standard-Arten (Fachschlüssel) bleiben; die Art eigener Kategorien folgt dem neuen Namen
    /// (M-6: «Steuern…»-Regel wie Web `isTax`). «Sonstiges» ist fest.
    public mutating func renameCategory(_ id: UUID, to name: String) throws {
        guard let i = categoryIndex(id) else { throw MutationError.notFound }
        if categories[i].kind == .other { throw MutationError.fixedCategory }
        let n = Format.collapseSpaces(name)
        if n.isEmpty { throw MutationError.emptyName }
        if n == categories[i].name { return }
        if let ex = categories.first(where: { $0.id != id && $0.name.lowercased() == n.lowercased() }) { throw MutationError.duplicateCategory(ex.id) }
        let old = categories[i]
        let others = categories.filter { $0.id != id }
        // Art nur aus der Namensregel: keine Art, oder «Steuern…» ohne Standardnamen, während es eine andere Steuern-Kategorie gibt
        let byName = old.kind == nil || (old.kind == .taxes && Category.standardKinds[old.name] == nil
            && old.name.lowercased().hasPrefix("steuern") && others.contains { $0.kind == .taxes })
        categories[i].name = n
        if byName {
            let k = Category.kind(forName: n, among: others)
            categories[i].kind = k == .other ? nil : k
        }
    }

    /// Farbe oder Symbol ändern (auch bei «Sonstiges»).
    public mutating func updateCategory(_ id: UUID, colorHex: String? = nil, icon: String? = nil) {
        guard let i = categoryIndex(id) else { return }
        if let c = colorHex { categories[i].colorHex = c }
        if let ic = icon { categories[i].icon = ic }
    }

    /// Kategorie löschen; ihre Verträge gehen an `moveTo` (Standard «Sonstiges»). «Sonstiges» ist fest.
    public mutating func deleteCategory(_ id: UUID, moveTo: UUID? = nil) throws {
        guard let i = categoryIndex(id) else { throw MutationError.notFound }
        if categories[i].kind == .other { throw MutationError.fixedCategory }
        let target = (moveTo != nil && moveTo != id && category(moveTo) != nil) ? moveTo : otherCategory?.id
        for k in contracts.indices where contracts[k].categoryID == id { contracts[k].categoryID = target }
        categories.remove(at: i)
    }

    /// Reihenfolge ändern (wie `List.onMove`).
    public mutating func moveCategories(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().filter { $0 >= 0 && $0 < categories.count }.map { categories[$0] }
        var rest: [Category] = []
        for (k, c) in categories.enumerated() where !source.contains(k) { rest.append(c) }
        let at = destination - source.filter { $0 < destination }.count
        rest.insert(contentsOf: moving, at: Swift.max(0, Swift.min(at, rest.count)))
        categories = rest
    }

    /// Eine Kategorie von Position `from` an Position `to` verschieben (Ziehgriff der Web-App).
    public mutating func moveCategory(from: Int, to: Int) {
        guard from >= 0, from < categories.count, from != to else { return }
        let c = categories.remove(at: from)
        categories.insert(c, at: Swift.max(0, Swift.min(to, categories.count)))
    }

    // MARK: Vertragspartner

    /// Vertragspartner für einen eingegebenen Namen: vorhandener (gleicher Name ohne Gross/Klein) oder neu angelegt.
    /// Ähnliche Namen werden nicht still zusammengelegt (M-2, wie Web); Hinweis über `Partners.similar`.
    @discardableResult
    public mutating func partnerID(forName name: String, web: String = "") -> UUID? {
        let n = Format.collapseSpaces(name)
        if n.isEmpty { return nil }
        if let p = Partners.find(n, in: self) {
            if let i = partnerIndex(p.id), partners[i].web.isEmpty, !web.isEmpty { partners[i].web = web }
            return p.id
        }
        let p = Partner(name: n, web: web)
        partners.append(p)
        return p.id
    }

    /// Umbenennen. Gibt es den Namen (ohne Gross/Klein) schon, kommt `duplicateName(id)` → `mergePartners`.
    public mutating func renamePartner(_ id: UUID, to name: String) throws {
        guard let i = partnerIndex(id) else { throw MutationError.notFound }
        let n = Format.collapseSpaces(name)
        if n.isEmpty { throw MutationError.emptyName }
        if n == partners[i].name { return }
        if let ex = partners.first(where: { $0.id != id && $0.name.lowercased() == n.lowercased() }) { throw MutationError.duplicateName(ex.id) }
        partners[i].name = n
    }

    /// Zusammenführen: Verträge der Quellen laufen danach unter dem Ziel. Fehlende Website, Logo und Adresse des Ziels
    /// werden aus den Quellen ergänzt (Fix N1). Rückgabe: Anzahl umgehängter Verträge.
    @discardableResult
    public mutating func mergePartners(_ sources: [UUID], into target: UUID) -> Int {
        guard let ti = partnerIndex(target) else { return 0 }
        var n = 0
        var removed = Set<UUID>()
        for s in sources where s != target {
            guard let src = partner(s) else { continue }
            if partners[ti].web.isEmpty { partners[ti].web = src.web }
            if (partners[ti].logoID ?? "").isEmpty, let l = src.logoID, !l.isEmpty {
                partners[ti].logoID = l
                partners[ti].logoBg = src.logoBg
            }
            if partners[ti].address.isEmpty { partners[ti].address = src.address }
            for k in contracts.indices where contracts[k].partnerID == s {
                contracts[k].partnerID = target
                n += 1
            }
            let prefix = "p:" + s.uuidString + ":"
            settings.qualityIgnored.removeAll { $0.hasPrefix(prefix) }
            removed.insert(s)
        }
        partners.removeAll { removed.contains($0.id) }
        return n
    }

    /// Adresse des Vertragspartners setzen (gilt für alle seine Verträge).
    public mutating func setPartnerAddress(_ id: UUID, _ a: PostalAddress) {
        guard let i = partnerIndex(id) else { return }
        let t = { (x: String) in Format.collapseSpaces(x) }
        partners[i].address = PostalAddress(company: t(a.company), extra: t(a.extra), street: t(a.street), zip: t(a.zip), city: t(a.city), country: t(a.country))
    }

    /// Logo des Vertragspartners setzen oder entfernen (nil).
    public mutating func setPartnerLogo(_ id: UUID, logoID: String?, background: String?) {
        guard let i = partnerIndex(id) else { return }
        if let l = logoID, !l.isEmpty {
            partners[i].logoID = l
            partners[i].logoBg = background ?? "#FFFFFF"
        } else {
            partners[i].logoID = nil
            partners[i].logoBg = nil
        }
    }

    public mutating func setPartnerWeb(_ id: UUID, _ web: String) {
        guard let i = partnerIndex(id) else { return }
        partners[i].web = web.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Vertragspartner ohne Verträge entfernen. Rückgabe: Anzahl.
    @discardableResult
    public mutating func pruneUnusedPartners() -> Int {
        let used = Set(contracts.compactMap { $0.partnerID })
        let before = partners.count
        partners.removeAll { !used.contains($0.id) }
        return before - partners.count
    }

    // MARK: Datenqualität, Quartals-Check

    public mutating func ignoreQuality(_ keys: [String]) {
        for k in keys where !settings.qualityIgnored.contains(k) { settings.qualityIgnored.append(k) }
    }

    public mutating func resetQualityIgnored() {
        settings.qualityIgnored = []
    }

    /// «Alles geprüft»
    public mutating func markReviewed(today: Day) {
        settings.lastReview = today
        settings.reviewSnooze = nil
    }

    public static let reviewedToast = "Geprüft — nächste Erinnerung in drei Monaten"

    /// «Später»: in 7 Tagen wieder.
    public mutating func snoozeReview(today: Day) {
        settings.reviewSnooze = today.addingDays(7)
    }

    /// «Alle Daten löschen»: Verträge, Einnahmen, eigene Kategorien, Inhaber und Absender weg; Darstellung, Währung,
    /// Kurse, Sortierung und Einführung bleiben (Fix L4).
    public mutating func wipeAll() {
        let s = settings
        self = AppData.initial(homeCurrency: s.homeCurrency)
        settings.rates = s.rates
        settings.rateDate = s.rateDate
        settings.rateChecked = s.rateChecked
        settings.rateSource = s.rateSource
        settings.theme = s.theme
        settings.sort = s.sort
        settings.onboarded = s.onboarded
    }
}

// MARK: - Kontaktdaten aus dem Katalog ergänzen (Web «Kontaktdaten ergänzen», tplFillPlan, b520636)

public struct CatalogFillItem: Hashable, Sendable {
    public var contractID: UUID
    public var entryName: String
    public var confirmed: Bool
    /// Fehlende Partner-Adresse (nil = nichts zu ergänzen)
    public var address: PostalAddress?
    public var mail: String?
    public var tel: String?
    /// Fehlende Website des Vertragspartners
    public var web: String?
    /// Fehlender Kündigungsweg (nur Vollständigkeit, Web `vkAutoPlan`)
    public var cancelChannel: CancelChannel?
}

extension AppData {
    /// Plan über alle nicht ins Archiv verschobenen Verträge: nur leere Felder (Adresse/Website am Vertragspartner, E-Mail/Telefon am Vertrag).
    public func catalogFillPlan() -> [CatalogFillItem] {
        var out: [CatalogFillItem] = []
        var addrDone = Set<UUID>()
        for c in contracts where c.status != .cancelled {
            let p = partner(c.partnerID)
            guard let t = Catalog.match(names: [p?.name ?? "", c.label], currency: c.currency) else { continue }
            var it = CatalogFillItem(contractID: c.id, entryName: t.name, confirmed: t.confirmed)
            if let p = p, p.address.isEmpty, !t.address.isEmpty, !addrDone.contains(p.id) {
                it.address = WebImport.addrSplit(t.address, partnerName: p.name)
                addrDone.insert(p.id)
            }
            if c.mail.isEmpty && !t.mail.isEmpty { it.mail = t.mail }
            if c.tel.isEmpty && !t.tel.isEmpty { it.tel = t.tel }
            if let p = p, p.web.isEmpty, !t.web.isEmpty { it.web = t.web }
            if it.address != nil || it.mail != nil || it.tel != nil || it.web != nil { out.append(it) }
        }
        return out
    }

    /// Plan anwenden (nur leere Felder; Adresse/Website am Vertragspartner).
    public mutating func applyCatalogFill(_ plan: [CatalogFillItem]) {
        for it in plan {
            guard let i = contracts.firstIndex(where: { $0.id == it.contractID }) else { continue }
            if let m = it.mail, contracts[i].mail.isEmpty { contracts[i].mail = m }
            if let t = it.tel, contracts[i].tel.isEmpty { contracts[i].tel = t }
            if let ch = it.cancelChannel, contracts[i].cancelChannel == nil { contracts[i].cancelChannel = ch }
            if let pid = contracts[i].partnerID, let pi = partners.firstIndex(where: { $0.id == pid }) {
                if let a = it.address, partners[pi].address.isEmpty { partners[pi].address = a }
                if let w = it.web, partners[pi].web.isEmpty { partners[pi].web = w }
            }
        }
    }
}
