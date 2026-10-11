import Foundation

// MARK: - Vertragsdetail (Web `openDetail`, Stand v160)
//
// Reine Regeln und Texte der Vertragsansicht: Zustände (gekündigt/beendet/«endet von selbst»/laufendes Probeabo/behalten),
// Frist für Zeitstrahl und Kasten, Zeilen der Abschnitte, Pillen, Monatskachel, Menü •••, «Schon gekündigt …»,
// Kündigen-Auswahl und die Rückfrage nach dem Brief. Die Oberfläche (Contracts/ContractDetail*, Deadlines) zeichnet nur.

/// Ton einer Pille bzw. eines Kastens.
public enum DetailTone: String, Hashable, Sendable {
    case neutral, warn, alert
}

/// Nächste Kündigung als Zeitstrahl (Web `termLine`): heute → kündigen bis → Ende.
public struct DetailTimeline: Hashable, Sendable {
    public var deadline: Day
    public var end: Day
    public var days: Int
    /// jederzeit kündbar: ohne «noch n Tage»
    public var anytime: Bool
}

/// Zeile eines Abschnitts im Detail.
public struct DetailRow: Hashable, Sendable {
    public var label: String
    public var value: String
    /// Zusatz unter dem Wert («nächste am 15.10.26»)
    public var sub: String = ""
    /// Zeitstrahl statt Beschriftung/Wert
    public var timeline: DetailTimeline?

    public init(_ label: String, _ value: String, sub: String = "") {
        self.label = label
        self.value = value
        self.sub = sub
    }

    public init(timeline: DetailTimeline) {
        label = ""
        value = ""
        self.timeline = timeline
    }
}

/// Pille unter dem Kopf.
public struct DetailPill: Hashable, Sendable {
    public var text: String
    public var tone: DetailTone
}

/// Kasten oben (Frist ≤ 60 Tage bzw. Probeabo endet bald) mit Kündigen/Wechseln und Behalten.
public struct DetailDeadlineBox: Hashable, Sendable {
    /// «Kündigen bis 30. November», «Wechseln bis 31. März 2027», «Probeabo bis 19. Oktober»
    public var title: String
    /// «sonst verlängert bis 31.12.27 · noch 50 Tage», «danach kostenpflichtig · noch 8 Tage»
    public var subtitle: String
    public var tone: DetailTone
    /// Probeabo-Kasten: Kündigen gilt fürs Probeabo, Behalten setzt `trialKept`
    public var trial: Bool
    /// «Kündigen» bzw. «Wechseln»
    public var cancelTitle: String
    public let keepTitle = "Behalten"
}

/// Monatskachel: Anteil an den Fixkosten oder Status statt Leerfläche (Web v154/v157).
public struct DetailMonthTile: Hashable, Sendable {
    /// «23 % deiner Fixkosten» (Balken), nil ohne Anteil
    public var sharePercent: Int?
    /// «pausiert», «beendet» (auch gekündigt per, wie Web v160), «startet am 01.02.27» (Balken leer); nil ohne Status
    public var status: String?
    /// rechte untere Kachel: «bisher bezahlt (ca.)» (mit Beginn in der Vergangenheit) bzw. «nächste Zahlung»
    public var paidLabel: String { "bisher bezahlt (ca.)" }
    public static let nextLabel = "nächste Zahlung"
}

/// Menü ••• im Detail (Web `dMenu`).
public struct DetailMenu: Hashable, Sendable {
    /// «Kündigen»/«Wechseln» mit Weg (online/per E-Mail/per Brief/Weg wählen); nil = nicht anbieten
    public var cancel: (title: String, subtitle: String)?
    public var uncancel: Bool
    public var unkeep: Bool
    /// «Pausieren»/«Fortsetzen», nil = nicht anbieten
    public var pause: String?
    /// «Wieder aktiv setzen»
    public var reactivate: Bool
    /// «Schon gekündigt …» (Untertitel «Datum eintragen, bis wann er läuft») bzw. bei nicht kündbaren «Beendet …»
    /// («z.B. nach Umzug»); nil = nicht anbieten
    public var alreadyCancelled: (title: String, subtitle: String)?

    public static func == (a: DetailMenu, b: DetailMenu) -> Bool {
        a.cancel?.title == b.cancel?.title && a.cancel?.subtitle == b.cancel?.subtitle && a.uncancel == b.uncancel && a.unkeep == b.unkeep
            && a.pause == b.pause && a.reactivate == b.reactivate && a.alreadyCancelled?.title == b.alreadyCancelled?.title
            && a.alreadyCancelled?.subtitle == b.alreadyCancelled?.subtitle
    }

    public func hash(into h: inout Hasher) {
        h.combine(cancel?.title)
        h.combine(uncancel)
        h.combine(unkeep)
        h.combine(pause)
        h.combine(reactivate)
        h.combine(alreadyCancelled?.title)
    }
}

/// Rückfrage «Schon gekündigt» / «Vertrag beendet» (Web v154) mit Feld «Läuft bis».
public struct AlreadyCancelledPrompt: Hashable, Sendable {
    public var title: String
    public var text: String
    public let ok = "Sichern"
    public let fieldLabel = "Läuft bis"
    /// Vorbelegung: nächster Termin (nicht kündbar: heute)
    public var defaultDate: Day
    /// Chips: «heute» und ggf. «31.12.26 (Termin)»
    public var chips: [(title: String, day: Day)]

    public static func == (a: AlreadyCancelledPrompt, b: AlreadyCancelledPrompt) -> Bool {
        a.title == b.title && a.text == b.text && a.defaultDate == b.defaultDate && a.chips.map { $0.title } == b.chips.map { $0.title }
            && a.chips.map { $0.day } == b.chips.map { $0.day }
    }

    public func hash(into h: inout Hasher) {
        h.combine(title)
        h.combine(defaultDate)
    }
}

/// Auswahl «Kündigen: …» (Web `killOptions`).
public struct KillOptions: Hashable, Sendable {
    /// «Kündigen: Handy» bzw. «Wechseln: Krankenkasse»
    public var title: String
    /// «Online kündigen», «Per E-Mail kündigen», «Kündigungsschreiben erstellen», «Kündigen: Weg wählen …»
    public var startTitle: String
    /// Kündigungsweg am Vertrag («Brief») oder ""
    public var startDetail: String
    /// «Als gekündigt markieren» bzw. «Gekündigt, neuen Vertragspartner erfassen»
    public var doneTitle: String
    /// «läuft bis 31.12.26» oder ""
    public var doneDetail: String
    /// «Kündigung muss bis 30. November 2026 beim Vertragspartner sein. Nach dem Markieren …»
    public var note: String
    /// Titel der Navigation: «Kündigen» bzw. «Wechseln»
    public var navTitle: String
}

/// Alles, was die Vertragsansicht zeigt (ohne Kopf, Kontakt, Sonderzahlungen, Notiz).
public struct ContractDetailInfo: Hashable, Sendable {
    /// Archiv, «gekündigt per» oder Laufzeit vorbei: keine Frist und kein nächster Termin mehr
    public var gone: Bool
    /// Kündigung wirksam oder Laufzeit vorbei: nur noch Duplizieren/Reaktivieren/Löschen
    public var ended: Bool
    public var fixed: Bool
    /// Feste Laufzeit ohne Verlängerung (Web v160)
    public var endsSelf: Bool
    /// Laufendes Probeabo: «Kündigen» gilt fürs Probeabo (Ende = letzter Gratistag)
    public var trialRunning: Bool
    /// Frist für Zeitstrahl/Kasten (bei «Behalten» die nächste, beim Probeabo der letzte Gratistag)
    public var deadline: Day?
    public var deadlineDays: Int?
    /// Vertragsende zur Frist
    public var deadlineEnd: Day?
    /// Kasten «Kündigen bis …» oben (Frist in 0–60 Tagen)
    public var due60: Bool
    public var pills: [DetailPill]
    public var box: DetailDeadlineBox?
    public var month: DetailMonthTile
    public var costRows: [DetailRow]
    public var termRows: [DetailRow]
    public var assignmentRows: [DetailRow]
    public var menu: DetailMenu
}

extension Calc {
    /// Vertragsende in der Ansicht (Web `e`): gekündigt → «läuft bis» bzw. letzter Termin vor der Archivierung (nicht
    /// fortgeschrieben), sonst effektives Vertragsende.
    public func detailContractEnd(_ c: Contract) -> Day? {
        let gone = c.status == .cancelled || c.cancelPer != nil || endedByTerm(c)
        var e = effEnd(c)
        if gone {
            if let cp = c.cancelPer {
                e = cp
            } else if let e0 = c.end, let ca = c.cancelledAt, c.renewMonths != 0 {
                var x = e0
                var g = 0
                while x < ca && g < 400 {
                    g += 1
                    x = e0.addingMonthsE(g * c.renewMonths)
                }
                e = x
            } else if let e0 = c.end {
                e = e0
            }
        }
        return e
    }

    /// Vertragsansicht (Web `openDetail`, v143–v160).
    public func detailInfo(_ c: Contract) -> ContractDetailInfo {
        let gone = c.status == .cancelled || c.cancelPer != nil || endedByTerm(c)
        let fixd = isFixed(c)
        let selfEnd = endsSelf(c)
        let ended = endedByNotice(c) || endedByTerm(c)
        let trialRun = trialOn(c)
        // Frist (Web `u`)
        var uDate: Day? = nil, uDays: Int? = nil, uT: Day? = nil
        var lvl = UrgencyLevel.none
        if !(gone || fixd) {
            let u = urgency(c)
            uDate = u.date
            uDays = u.days
            lvl = u.level
        }
        let nd = nextDue(c)
        var rt: Day? = gone ? nil : renewTo(c)
        // «Behalten»: schon den nächsten Termin danach zeigen (Web v143)
        var kT: Day? = nil
        let kept = isKept(c)
        if !gone && !fixd && kept, let T0 = termEnd(c) {
            kT = c.end != nil ? renewAfter(c, T0) : nextTerm(c, base: nil, after: T0)
            if let k = kT {
                let kd = noticeDeadline(for: c, end: k)
                uDate = kd
                uDays = today.days(to: kd)
                uT = k
                lvl = .none
                rt = c.end != nil ? renewAfter(c, k) : nil
            }
        }
        // laufendes Probeabo: Zeitachse bis zum letzten Gratistag (Web v156)
        if !gone && trialRun, let tl0 = trialLast(c) {
            uDate = tl0
            uDays = today.days(to: tl0)
            uT = tl0
            lvl = .none
        }
        let e = detailContractEnd(c)
        let te = termEnd(c)
        var due60 = false
        if !gone && !fixd, uDate != nil, let d = uDays, d >= 0 && d <= 60 {
            due60 = !isAnytime(c) && !c.noWatch && c.cancelPer == nil && !kept && te != nil
        }
        let paid = paidSoFar(c) != nil

        // Pillen
        var main: DetailPill? = nil
        if c.status == .cancelled {
            main = DetailPill(text: "Gekündigt" + (c.cancelledAt.map { " am " + Format.fmtD($0) } ?? ""), tone: .neutral)
        } else if let cp = c.cancelPer {
            main = DetailPill(text: "Gekündigt · " + (endedByNotice(c) ? "beendet am " : "läuft bis ") + Format.fmtD(cp), tone: .neutral)
        } else if endedByTerm(c), let en = c.end {
            main = DetailPill(text: "Beendet am " + Format.fmtD(en), tone: .neutral)
        } else if reviewKill(c) {
            main = DetailPill(text: "Zum Kündigen vorgemerkt", tone: .warn)
        } else if kept {
            main = DetailPill(text: "Behalten" + (kT != nil ? " · nächste Frist " + Format.fmtShort(uDate) : ""), tone: .neutral)
        } else if lvl == .alert, let d = uDays, !due60 {
            main = DetailPill(text: "Frist " + Format.inDays(d), tone: .alert)
        } else if lvl == .warn, let d = uDays, !due60 {
            main = DetailPill(text: "Frist " + Format.inDays(d), tone: .warn)
        }
        if !gone && fixd && main == nil { main = DetailPill(text: "Nicht kündbar", tone: .neutral) }
        if !gone && isPaused(c), let p = currentPause(c) {
            let pt: String
            if let u = p.until { pt = "Pausiert bis " + Format.fmtD(u) } else { pt = "Pausiert seit " + Format.fmtD(p.from) }
            main = DetailPill(text: pt, tone: .neutral)
        }
        var pills: [DetailPill] = []
        if let m = main { pills.append(m) }
        if let n = nextChange(c) {
            let amt = Format.money(n.amount, c.currency) + " " + c.currency.rawValue
            pills.append(DetailPill(text: "Neuer Preis ab " + Format.fmtD(n.from) + ": " + amt, tone: .warn))
        }

        // Kasten oben
        var box: DetailDeadlineBox? = nil
        let kword = c.mandatory ? "Wechseln" : "Kündigen"
        if !due60 && !gone && trialNeeds(c), let tl = trialLast(c) {
            let tdn = today.days(to: tl)
            let left = Calc.daysLeftText(tdn)
            let ttl = "Probeabo bis \(tl.day). " + Format.monthNames[tl.month - 1]
            box = DetailDeadlineBox(title: ttl, subtitle: "danach kostenpflichtig · " + left,
                                    tone: tdn <= 7 ? .alert : .neutral, trial: true, cancelTitle: "Kündigen")
        }
        if due60, let D = uDate, let dn = uDays {
            let yy = D.year != today.year
            var sub: String
            if let r = rt { sub = "sonst verlängert bis " + Format.fmtShort(r) } else { sub = "Vertragsende " + Format.fmtShort(te) }
            sub += " · " + Calc.daysLeftText(dn)
            var ttl = c.mandatory ? "Wechseln bis " : "Kündigen bis "
            ttl += "\(D.day). " + Format.monthNames[D.month - 1]
            if yy { ttl += " \(D.year)" }
            box = DetailDeadlineBox(title: ttl, subtitle: sub, tone: dn <= 7 ? .alert : .neutral, trial: trialRun, cancelTitle: kword)
        }

        // Monatskachel (Anteil bzw. Status)
        var share: Int? = nil
        if !gone && !isPaused(c) && !notStarted(c) && !trialRun {
            let tot = running.filter { !notStarted($0) && !trialOn($0) }.reduce(0.0) { $0 + monthlyCost($1) }
            if tot > 0.005 { share = Int(Format.jsRound(monthlyCost(c) / tot * 100)) }
        }
        var status: String? = nil
        if share == nil {
            // 1:1 wie Web v160: dort `c.cancelPer && !gone` – nie wahr, weil `gone` «gekündigt per» einschliesst; gekündigte
            // Verträge zeigen deshalb «beendet» (gemeldet als Web-Fehler, Korrektur zuerst im Web)
            if let cp = c.cancelPer, !gone {
                status = "gekündigt, läuft bis " + Format.fmtShort(cp)
            } else if isPaused(c) {
                status = "pausiert"
            } else if gone {
                status = "beendet"
            } else if notStarted(c), let s = c.start {
                status = "startet am " + Format.fmtShort(s)
            }
        }

        // Kosten
        var cost: [DetailRow] = []
        if c.cycleForCalc != 1 { cost.append(DetailRow("Betrag", Format.money(curPrice(c), c.currency) + " " + c.currency.rawValue)) }
        let rule = payRule(c)
        if !rule.isEmpty {
            cost.append(DetailRow("Zahlung", rule, sub: c.cycleForCalc != 1 && nd != nil && paid ? "nächste am " + Format.fmtShort(nd) : ""))
        }
        let pay = [c.payMethod, c.payAccount].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !pay.isEmpty { cost.append(DetailRow("Bezahlung", pay.joined(separator: " · "))) }

        // Laufzeit & Kündigung
        var term: [DetailRow] = []
        if let s = c.start { term.append(DetailRow("Beginn", Format.fmtD(s))) }
        if c.end != nil || c.cancelPer != nil, let ee = e {
            var v = Format.fmtD(ee)
            if !gone, let t1 = te, t1 > ee { v += " · Frist verpasst" }
            term.append(DetailRow("Vertragsende", v))
        }
        if fixd {
            term.append(DetailRow("Kündigung", isTax(c) ? "nicht kündbar · Steuern & Gebühren" : "nicht kündbar"))
        } else if selfEnd {
            term.append(DetailRow("Kündigung", gone ? "nicht nötig" : "nicht nötig · endet von selbst"))
        } else {
            let nt = Format.noticeText(c)
            var v = nt.isEmpty ? "ohne Frist" : nt
            if c.end == nil { v += " · " + (c.cancelTerm != .anytime ? "auf " + Format.termText(c.cancelTerm) : "jederzeit") }
            term.append(DetailRow("Kündigung", v))
        }
        if let D = uDate, !due60 && !gone && !selfEnd {
            let T = uT ?? te
            if let dn = uDays, dn >= 0, te != nil, let T = T {
                term.append(DetailRow(timeline: DetailTimeline(deadline: D, end: T, days: dn, anytime: isAnytime(c))))
            } else {
                term.append(DetailRow("Nächster Termin", "per " + Format.fmtShort(T) + ", kündigen bis " + Format.fmtShort(D) + " (abgelaufen)"))
            }
        }
        if c.mandatory && !fixd { term.append(DetailRow("Kündigung", "nur mit neuem Anbieter")) }
        if c.noWatch && !fixd && !selfEnd { term.append(DetailRow("Frist", "wird nicht beobachtet")) }
        if !(fixd || gone) {
            if let r = rt {
                term.append(DetailRow("Sonst verlängert bis", Format.fmtD(r)))
            } else if c.renewMonths > 0 {
                term.append(DetailRow("Verlängerung", "automatisch um \(c.renewMonths)" + (c.renewMonths == 1 ? " Monat" : " Monate")))
            }
        }
        if let ch = c.cancelChannel, !ended && !selfEnd { term.append(DetailRow("Kündigungsweg", ch.webText)) }
        if c.cancelPer != nil, let on = c.cancelledOn { term.append(DetailRow("Gekündigt am", Format.fmtD(on))) }
        if trialRun, let tl = trialLast(c) { term.append(DetailRow("Probeabo", "gratis bis " + Format.fmtD(tl))) }

        // Zuordnung (Vertragspartner als Verweis zeichnet die Oberfläche)
        var assign: [DetailRow] = []
        let pn = data.partnerName(of: c)
        if !pn.isEmpty { assign.append(DetailRow("Vertragspartner", pn)) }
        if let cat = data.category(c.categoryID) { assign.append(DetailRow("Kategorie", cat.name)) }
        let hn = data.holdersText(of: c)
        if !hn.isEmpty { assign.append(DetailRow(c.holderIDs.count > 1 ? "Personen" : "Person", hn)) }
        if !c.customerNo.isEmpty { assign.append(DetailRow("Kundennummer", c.customerNo)) }
        if !c.contractNo.isEmpty { assign.append(DetailRow(Letter.contractNumberLabel(c, data: data), c.contractNo)) }

        // Menü •••
        let menu = detailMenu(c)

        return ContractDetailInfo(gone: gone, ended: ended, fixed: fixd, endsSelf: selfEnd, trialRunning: trialRun,
                                  deadline: uDate, deadlineDays: uDays, deadlineEnd: uT ?? te, due60: due60,
                                  pills: pills, box: box, month: DetailMonthTile(sharePercent: share, status: status),
                                  costRows: cost, termRows: term, assignmentRows: assign, menu: menu)
    }

    /// Menü ••• allein (Web `dMenu`, v143/v150/v154) – gleiche Regeln wie `detailInfo(_:).menu`, ohne den Rest der Ansicht zu
    /// rechnen (z.B. für Wischen/langes Drücken auf Vertragskarten).
    public func detailMenu(_ c: Contract) -> DetailMenu {
        let gone = c.status == .cancelled || c.cancelPer != nil || endedByTerm(c)
        let fixd = isFixed(c)
        let ended = endedByNotice(c) || endedByTerm(c)
        let kok = !(c.cancelPer != nil || c.status == .cancelled || fixd)
        let via: String = {
            switch cancVia(c) {
            case .online: return "online"
            case .mail: return "per E-Mail"
            case .post: return "per Brief"
            case .none: return "Weg wählen"
            }
        }()
        var menu = DetailMenu(cancel: kok ? (title: c.mandatory ? "Wechseln" : "Kündigen", subtitle: via) : nil,
                              uncancel: c.cancelPer != nil && !ended,
                              unkeep: isKept(c) && !gone,
                              pause: (c.status != .cancelled && !ended && !fixd && !c.mandatory && !isRent(c)) ? (isPaused(c) ? "Fortsetzen" : "Pausieren") : nil,
                              reactivate: c.status == .cancelled || ended,
                              alreadyCancelled: nil)
        if !menu.reactivate && c.cancelPer == nil {
            menu.alreadyCancelled = fixd ? (title: "Beendet …", subtitle: "z.B. nach Umzug")
                : (title: "Schon gekündigt …", subtitle: "Datum eintragen, bis wann er läuft")
        }
        return menu
    }

    /// «heute», «noch 1 Tag», «noch 8 Tage» (Kasten oben).
    public static func daysLeftText(_ n: Int) -> String {
        if n == 0 { return "heute" }
        return "noch \(n)" + (n == 1 ? " Tag" : " Tage")
    }

    /// «Schon gekündigt …» / «Beendet …» (Web v154): Vorbelegung nächster Termin (nicht kündbar: heute). «Sichern» →
    /// `AppData.markCancelled(id, trial: false, per: gewähltes Datum, today:)`.
    public func alreadyCancelledPrompt(_ c: Contract) -> AlreadyCancelledPrompt {
        let fixd = isFixed(c)
        let T0 = fixd ? today : (termEnd(c) ?? today)
        let name = data.title(of: c)
        var chips: [(title: String, day: Day)] = [(title: "heute", day: today)]
        if !(fixd || T0 == today) { chips.append((title: Format.fmtShort(T0) + " (Termin)", day: T0)) }
        return AlreadyCancelledPrompt(
            title: fixd ? "Vertrag beendet" : "Schon gekündigt",
            text: fixd ? "Bis wann läuft «" + name + "»? Danach zählt er nicht mehr zu deinen Kosten."
                : "Bis wann läuft «" + name + "» noch? Vorgeschlagen ist der nächste mögliche Termin. Ist er schon vorbei, wähle heute oder ein früheres Datum.",
            defaultDate: T0, chips: chips)
    }

    /// Auswahl «Kündigen: …» (Web `killOptions`, v143): Probeabo läuft bis zum letzten Gratistag.
    public func killOptions(_ c: Contract, trial: Bool) -> KillOptions {
        let T = trial ? trialLast(c) : termEnd(c)
        let start: String
        switch cancVia(c) {
        case .online: start = "Online kündigen"
        case .mail: start = "Per E-Mail kündigen"
        case .post: start = "Kündigungsschreiben erstellen"
        case .none: start = "Kündigen: Weg wählen …"
        }
        var note = ""
        if let T = T {
            let d = trial ? T : noticeDeadline(for: c, end: T)
            note = "Kündigung muss bis " + Format.fmtD(d) + (trial ? "" : " beim Vertragspartner") + " sein. "
        }
        note += "Nach dem Markieren zählt der Vertrag bis zum Ende weiter und wandert danach ins Archiv."
        return KillOptions(title: (c.mandatory ? "Wechseln: " : "Kündigen: ") + data.title(of: c),
                           startTitle: start, startDetail: c.cancelChannel?.webText ?? "",
                           doneTitle: c.mandatory ? "Gekündigt, neuen Vertragspartner erfassen" : "Als gekündigt markieren",
                           doneDetail: T.map { "läuft bis " + Format.fmtShort($0) } ?? "",
                           note: note, navTitle: c.mandatory ? "Wechseln" : "Kündigen")
    }

    /// Rückfrage nach dem Kündigungs-PDF (Web v143 `closeLetter`: «Brief verschickt?» / «Noch nicht») bzw. beim Zurückkommen
    /// nach Online/E-Mail («Gekündigt?» / «Abbrechen»): nil, wenn schon gekündigt. «Ja, gekündigt» → `markCancelled(id, trial:)`.
    public func cancelledQuestion(_ c: Contract, trial: Bool, letter: Bool) -> (title: String, text: String, ok: String, no: String)? {
        if c.cancelPer != nil || c.status == .cancelled { return nil }
        let T = cancelEnd(c, trial: trial)
        var text = "«" + data.title(of: c) + "» als gekündigt markieren"
        if let T = T { text += ", läuft bis " + Format.fmtD(T) }
        text += ". Der Vertrag zählt bis zum Ende weiter und wandert danach ins Archiv."
        return (letter ? "Brief verschickt?" : "Gekündigt?", text, "Ja, gekündigt", letter ? "Noch nicht" : "Abbrechen")
    }
}

// MARK: - Einnahme ansehen (Web v155 `openIncDetail`)

/// Kennzahlen und Angaben einer Einnahme.
public struct IncomeDetailInfo: Hashable, Sendable {
    /// «Einnahme»-Titel: Bezeichnung, sonst Quelle, sonst «Einnahme»
    public var title: String
    /// Quelle unter dem Titel (nur wenn Bezeichnung und Quelle)
    public var subtitle: String
    /// «Beendet am 31. Dezember 2026» bzw. «Ab 1. November 2026»; nil ohne Pille
    public var pill: String?
    /// «pro Monat» bzw. «einmalig»
    public var mainLabel: String
    /// Betrag in der Einnahmewährung (pro Monat bzw. einmalig)
    public var mainAmount: Double
    /// in der Hauptwährung (für «≈ … CHF» bei Fremdwährung)
    public var mainAmountHome: Double
    public var foreign: Bool
    /// «38 % deiner Einnahmen» (Balken grün), nil ohne Anteil
    public var sharePercent: Int?
    /// ohne Anteil: «beendet», «startet am 01.11.26», «netto» bzw. «einmalige Einnahme»
    public var note: String?
    /// «pro Jahr» (nur wiederkehrend), in der Einnahmewährung
    public var yearly: Double?
    /// rechte Kachel: Beschriftung «nächste Zahlung» bzw. «am», Wert «20.10.26» oder «—»
    public var nextLabel: String
    public var nextValue: String
    public var rows: [DetailRow]
}

extension Calc {
    /// Einnahme-Ansicht (Web `openIncDetail`, v155).
    public func incomeDetail(_ i: Income) -> IncomeDetailInfo {
        let t = today
        let cy = i.cycle
        let cp = curPrice(i)
        var nd: Day? = cy != 0 ? occurrences(i, from: t, to: t.addingMonths(Swift.max(13, cy + 1))).first : nil
        if let n = nd, let en = i.end, n > en { nd = nil }
        let endedI = i.end.map { $0 < t } ?? false
        let future = i.start.map { $0 > t } ?? false
        var pill: String? = nil
        if endedI { pill = "Beendet am " + Format.fmtD(i.end) } else if future { pill = "Ab " + Format.fmtD(i.start) }
        var tot = 0.0
        for x in data.incomes where x.cycle != 0 {
            if let e2 = x.end, e2 < t { continue }
            if let s2 = x.start, s2 > t { continue }
            tot += conv(curPrice(x), x.currency) / Double(x.cycle)
        }
        let mine = (cy != 0 && !endedI && !future) ? conv(cp, i.currency) / Double(cy) : 0
        let shr: Int? = (tot > 0.005 && mine != 0) ? Int(Format.jsRound(mine / tot * 100)) : nil
        let main = cy != 0 ? cp / Double(cy) : cp
        var note: String? = nil
        if shr == nil {
            if cy == 0 { note = "einmalige Einnahme" } else if endedI { note = "beendet" } else if future { note = "startet am " + Format.fmtShort(i.start) } else { note = "netto" }
        }
        var rows: [DetailRow] = []
        let pr = Calc.payRule(cycle: cy, due: i.due)
        let payText: String
        if cy == 0 { payText = "einmalig am " + Format.fmtD(i.due) } else if pr.isEmpty { payText = Format.incomeCycleTexts[cy] ?? "" } else { payText = pr }
        rows.append(DetailRow("Zahlung", payText))
        rows.append(DetailRow("Art", i.kind.displayName))
        if let h = i.holderID, let p = data.person(h) { rows.append(DetailRow("Empfänger", p.name)) }
        if let s = i.start { rows.append(DetailRow("Ab", Format.fmtD(s))) }
        if let e = i.end { rows.append(DetailRow("Bis", Format.fmtD(e))) }
        rows = rows.filter { !$0.value.isEmpty }
        return IncomeDetailInfo(title: i.title, subtitle: (!i.label.isEmpty && !i.name.isEmpty) ? i.name : "", pill: pill,
                                mainLabel: cy != 0 ? "pro Monat" : "einmalig", mainAmount: main, mainAmountHome: conv(main, i.currency),
                                foreign: i.currency != home, sharePercent: shr, note: note,
                                yearly: cy != 0 ? cp / Double(cy) * 12 : nil,
                                nextLabel: cy != 0 ? "nächste Zahlung" : "am",
                                nextValue: nd.map { Format.fmtShort($0) } ?? (cy != 0 ? "—" : Format.fmtShort(i.due)),
                                rows: rows)
    }
}
