import Foundation

// MARK: - Regeln und Texte des Vertragsformulars (Web v145–v160)
//
// Reine Funktionen für das Formular «Vertrag erfassen/bearbeiten» (Web `openForm`, `setTermMode`, `updTermHint`, `dueFrom`,
// `dueFromStart`, `trialDue`, `termEndFromM`/`termMFromEnd`, `syncRemind`, `noticeTxt`, `tmTxt`, `dueTxt`, `dgHtml`).
// Die Oberfläche (App, Contracts/ContractForm*) bindet nur noch an diese Werte.

/// Art des Vertrags im Formular (Web `termMode`, Knöpfe «Flexibel · Mindestlaufzeit · Probeabo · Nicht kündbar»).
public enum ContractTermMode: String, Hashable, Sendable, CaseIterable {
    case open, fixed, trial, tax

    /// Beschriftung der Knöpfe (Web v151, volle Wörter)
    public var title: String {
        switch self {
        case .open: return "Flexibel"
        case .fixed: return "Mindestlaufzeit"
        case .trial: return "Probeabo"
        case .tax: return "Nicht kündbar"
        }
    }

    /// Art beim Öffnen (Web `openForm`): nicht kündbar → tax, Vertragsende oder Verlängerung → fixed,
    /// Probeabo noch nicht behalten und nicht vorbei (≥ heute) → trial, sonst open.
    public init(contract c: Contract, today: Day) {
        if c.noCancel {
            self = .tax
        } else if c.end != nil || c.renewMonths != 0 {
            self = .fixed
        } else if let tr = c.trial, c.trialKept == nil, tr >= today {
            self = .trial
        } else {
            self = .open
        }
    }
}

/// Eingaben für den Laufzeit-Hinweis (Web `updTermHint`).
public struct TermHintInput: Hashable, Sendable {
    public var mode: ContractTermMode
    public var cycle: Int
    public var due: Day?
    public var start: Day?
    public var end: Day?
    public var renewMonths: Int
    /// Kündigungsfrist (0 = keine)
    public var notice: Int
    public var noticeUnit: NoticeUnit
    /// Kündbar per (Flexibel/Probeabo)
    public var cancelTerm: CancelTerm
    /// Probeabo: erster kostenpflichtiger Tag
    public var trial: Day?
    /// Währung im Formular (§ 309 BGB-Hinweis nur bei EUR)
    public var currency: Currency

    public init(mode: ContractTermMode, cycle: Int, due: Day?, start: Day?, end: Day?, renewMonths: Int, notice: Int, noticeUnit: NoticeUnit,
                cancelTerm: CancelTerm, trial: Day?, currency: Currency) {
        self.mode = mode
        self.cycle = cycle
        self.due = due
        self.start = start
        self.end = end
        self.renewMonths = renewMonths
        self.notice = notice
        self.noticeUnit = noticeUnit
        self.cancelTerm = cancelTerm
        self.trial = trial
        self.currency = currency
    }
}

public enum ContractFormRules {
    // MARK: Texte

    /// Info-Knopf bei «Steuern & Gebühren» (Web `TAX_INFO`, v158)
    public static let taxInfo = "Steuern und Gebühren (z.B. Rundfunkgebühr, Motorfahrzeugsteuer) gelten als nicht kündbar: keine Fristen, kein Kündigen, nicht unter «Fristen». Andere nicht kündbare Verträge: unter «Laufzeit & Kündigung» die Kachel «Nicht kündbar» wählen."

    /// Laufzeit-Hinweis bei «Nicht kündbar» (Web v158)
    public static let taxHint = "Gebühren und Abgaben wie die Rundfunkgebühr: keine Fristen, kein Kündigen. Zählt in Kosten und Budget."

    /// Sichern bei «Mindestlaufzeit» ohne Vertragsende (Web v218: «… fehlt», danach direkt ins Feld)
    public static let missingEndText = "Vertragsende fehlt"
    /// Sichern bei «Probeabo» ohne Dauer
    public static let missingTrialText = "Wie lange läuft das Probeabo?"
    /// Mindestlaufzeit ohne Vertragsbeginn (Web v146: danach zum Beginn springen)
    public static let missingStartText = "Zuerst den Vertragsbeginn eintragen"
    /// Gekündigt: «Läuft bis» leer bzw. «Gekündigt am» danach (Web v145)
    public static let missingCancelPerText = "Bitte eintragen, bis wann der Vertrag läuft"
    public static let cancelOrderText = "«Gekündigt am» liegt nach «Läuft bis»"
    /// Abbrechen mit Änderungen (Web v143)
    public static let discardTitle = "Änderungen verwerfen?"
    public static let discardText = "Deine Eingaben in diesem Formular gehen verloren."
    public static let discardOK = "Verwerfen"
    public static let discardKeep = "Weiter bearbeiten"
    /// Schalter «Pflichtvertrag» mit Infoknopf (Web v202, ersetzt «Nur Anbieter wechseln»)
    public static let mandatoryTitle = "Pflichtvertrag"
    public static let mandatorySubtitle = "Kündigen nur mit neuem Anbieter"
    /// Infoknopf «i» beim Schalter (Web `MAND_INFO`, v210 ohne «Strom»): Hinweis mit Titel `mandatoryInfoTitle`, nur «OK»
    public static let mandatoryInfoTitle = "Pflichtvertrag"
    public static let mandatoryInfo = "Pflichtverträge sind Verträge, die du haben musst. Du kannst sie nicht ersatzlos kündigen, sondern nur zu einem anderen Anbieter wechseln.\n\nBeispiele: Krankenkasse, Autohaftpflicht."
    public static let mandatoryInfoAccessibility = "Info: Pflichtvertrag"
    /// Einheitlicher Platzhalter leerer Felder (Web v216/v217): Beträge, Datumsfelder, Notiz/E-Mail bei Sonderzahlung und Kündigung
    public static let placeholder = "hinzufügen"
    /// Schalter «An Frist erinnern» (positive Anzeige von `noWatch`, Web v145)
    public static let remindTitle = "An Frist erinnern"
    public static let remindSubtitle = "Erscheint unter «Fristen»"

    /// Verlängerung, die beim Wechsel auf «Mindestlaufzeit» leer mit 1 Monat vorbelegt wird (Web v156: danach monatlich kündbar,
    /// sonst endete der Vertrag still)
    public static let defaultRenewOnFixed = 1

    // MARK: Fehlende Angaben beim Sichern (Web v218 `goMiss`)

    /// Feld, in das die App bei einer fehlenden Angabe springt (Fokus, Datumsauswahl öffnen, Zeile kurz markieren).
    public enum FormField: String, Hashable, Sendable {
        case label, category, amount, notice, end, trial
        case priceFrom, priceAmount, extraDate, extraAmount
        case incomeLabel, incomeAmount, incomePriceFrom, incomePriceAmount
    }

    /// Fehlende bzw. ungültige Angabe: Toast-Text und Zielfeld.
    public struct Missing: Hashable, Sendable {
        public var field: FormField
        public var message: String
        public init(_ field: FormField, _ message: String) {
            self.field = field
            self.message = message
        }
    }

    /// «Betrag fehlt» bei leerem Feld, sonst «Betrag prüfen» (Web v218).
    public static func amountMessage(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Betrag fehlt" : "Betrag prüfen"
    }

    /// Vertrag sichern (Web `saveForm`, Reihenfolge wie dort): Bezeichnung (ohne Vertragspartner), Kategorie, Betrag,
    /// Kündigungsfrist, Vertragsende bei «Mindestlaufzeit», Dauer beim Probeabo. nil = alles da.
    public static func checkContract(partner: String, label: String, hasCategory: Bool, amountText: String, noticeValid: Bool,
                                     mode: ContractTermMode, end: Day?, trial: Day?) -> Missing? {
        if partner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Missing(.label, "Bezeichnung fehlt")
        }
        if !hasCategory { return Missing(.category, "Bitte eine Kategorie wählen") }
        if (Format.parseAmount(amountText) ?? -1) < 0 { return Missing(.amount, amountMessage(amountText)) }
        if !noticeValid { return Missing(.notice, "Kündigungsfrist prüfen") }
        if mode == .fixed && end == nil { return Missing(.end, missingEndText) }
        if mode == .trial && trial == nil { return Missing(.trial, missingTrialText) }
        return nil
    }

    /// Preisänderung hinzufügen (Web `pAdd`): Datum, nach dem Vertragsbeginn, neuer Betrag («Neuer Betrag fehlt» / «Neuen Betrag prüfen»).
    public static func checkPriceChange(from: Day?, start: Day?, amountText: String) -> Missing? {
        guard let f = from else { return Missing(.priceFrom, "Datum für die Preisänderung fehlt") }
        if let s0 = start, f <= s0 { return Missing(.priceFrom, "Datum muss nach dem Vertragsbeginn liegen") }
        let a = Format.parseAmount(amountText)
        if a == nil || a! < 0 {
            let empty = a == nil && amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return Missing(.priceAmount, empty ? "Neuer Betrag fehlt" : "Neuen Betrag prüfen")
        }
        return nil
    }

    /// Sonderzahlung hinzufügen (Web `xAdd`): Datum, Betrag > 0.
    public static func checkExtra(date: Day?, amountText: String) -> Missing? {
        if date == nil { return Missing(.extraDate, "Datum der Sonderzahlung fehlt") }
        if let a = Format.parseAmount(amountText), a > 0 { return nil }
        return Missing(.extraAmount, amountMessage(amountText))
    }

    /// Einnahme sichern (Web `iSave`): Bezeichnung (ohne Quelle), Betrag.
    public static func checkIncome(name: String, label: String, amountText: String) -> Missing? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Missing(.incomeLabel, "Bezeichnung fehlt")
        }
        if let a = Format.parseAmount(amountText), a >= 0 { return nil }
        return Missing(.incomeAmount, amountMessage(amountText))
    }

    /// Änderung einer Einnahme hinzufügen (Web `iPAdd`): Datum, Betrag.
    public static func checkIncomePrice(from: Day?, amountText: String) -> Missing? {
        if from == nil { return Missing(.incomePriceFrom, "Datum fehlt") }
        if let a = Format.parseAmount(amountText), a >= 0 { return nil }
        return Missing(.incomePriceAmount, amountMessage(amountText))
    }

    // MARK: Strom Schweiz und Leasing (Web v210/v214/v215)

    /// Strom in der Schweiz (Web `isChPowerD`, v210/v215): Haushalte können den Anbieter nicht wählen (Grundversorgung) →
    /// neue Verträge standardmässig «Nicht kündbar», kein Pflichtvertrag. Gewählter Katalogeintrag «Strom» CH gilt immer
    /// (auch «Energie Wasser Bern»); sonst CHF, Kategorie «Energie & Wasser» und Bezeichnung/Vertragspartner ohne Wasser, Gas,
    /// Fernwärme, Heizung, Öl, Pellets, Holz, Solar, Abwasser, Kehricht.
    public static func isSwissPower(currency: Currency, categoryKind: CategoryKind?, label: String, partner: String,
                                    catalogEntry: CatalogEntry? = nil) -> Bool {
        if let t = catalogEntry, t.isSwissPower { return true }
        let t = label + " " + partner
        return currency == .CHF && categoryKind == .energy
            && !RX.test("wasser|gas|fernw|wärme|waerme|heiz|öl|oel|pellet|holz|solar|abwasser|kehricht", t, ignoreCase: true)
    }

    /// Was der Vorschlag «Strom CH» im Formular tun soll (Web `chPowerDefault`).
    public enum SwissPowerStep: Hashable, Sendable {
        /// nichts ändern
        case keep
        /// Art «Nicht kündbar» wählen (falls nicht schon), Pflichtvertrag aus; Merker «vom Vorschlag gesetzt» an
        case setNotCancellable
        /// früher vom Vorschlag gesetzt, passt nicht mehr: zurück auf «Flexibel» (falls «Nicht kündbar»), Merker aus
        case revert
    }

    /// Nur bei neuen Verträgen, solange die Art nicht von Hand gewählt wurde und eine Kategorie gesetzt ist. Aufrufen bei
    /// Änderung von Währung, Bezeichnung, Vertragspartner, Kategorie und nach einer Katalog-Vorlage.
    /// `appliedBefore`: Merker `draft.chPower`.
    public static func swissPowerStep(isNew: Bool, kindTouched: Bool, hasCategory: Bool, isSwissPower: Bool, appliedBefore: Bool) -> SwissPowerStep {
        if !isNew || kindTouched || !hasCategory { return .keep }
        if isSwissPower { return .setNotCancellable }
        return appliedBefore ? .revert : .keep
    }

    // MARK: Laufzeit-Hinweis

    /// Hinweis unter «Laufzeit & Kündigung» (Web `updTermHint`, Stand v160). `today` ist der Stichtag.
    public static func termHint(_ i: TermHintInput, calc: Calc) -> String {
        let today = calc.today
        switch i.mode {
        case .tax:
            return taxHint
        case .trial:
            guard let tv = i.trial else { return missingTrialText }
            return "Gratis bis " + Format.fmtD(tv.addingDays(-1)) + ", ab " + Format.fmtD(tv) + " kostenpflichtig. Kontivo erinnert dich unter «Fristen»."
        case .fixed:
            var fx = Contract()
            fx.end = i.end
            fx.renewMonths = i.renewMonths
            fx.notice = i.notice
            fx.noticeUnit = i.noticeUnit
            guard let E = calc.effEnd(fx) else { return "Vertragsende angeben, dann rechnet die App den Kündigungstermin aus." }
            let rn = i.renewMonths
            if let te = calc.termEnd(fx), te > E {
                return "Frist für " + Format.fmtD(E) + " verpasst · nächster Termin " + Format.fmtD(te) + ", kündigen bis "
                    + Format.fmtD(calc.noticeDeadline(for: fx, end: te)) + "."
            }
            if rn == 0 && E < today {
                return "Dieser Vertrag ist am " + Format.fmtD(E) + " ausgelaufen. Beim Sichern kommt er ins Archiv – Vertragsende prüfen."
            }
            if rn == 0 {
                return "Endet am " + Format.fmtD(E) + " von selbst – ohne Verlängerung ist keine Kündigung nötig."
            }
            return "Kündigen bis " + Format.fmtD(calc.noticeDeadline(for: fx, end: E)) + ", sonst +\(rn)" + (rn == 1 ? " Monat" : " Monate") + "."
                + (rn > 1 && i.currency == .EUR ? " Hinweis Deutschland: Verbraucherverträge verlängern sich seit 03/2022 meist nur noch monatlich (§ 309 BGB)." : "")
        case .open:
            break
        }
        let cyc = i.cycle > 0 ? i.cycle : 1
        if i.cancelTerm == .anytime {
            if cyc >= 3 {
                let w = [3: "quartalsweiser", 6: "halbjährlicher", 12: "jährlicher", 24: "zweijährlicher"][cyc] ?? "seltener"
                return "Achtung: Bei " + w + " Zahlung ist ein Abo meist nur auf Ende der bezahlten Periode kündbar. Dann «Kündbar per: Ende Periode» wählen."
            }
            return i.notice > 0 ? "Ohne Mindestlaufzeit: kündbar mit der angegebenen Frist." : "Ohne Mindestlaufzeit und ohne Frist: jederzeit kündbar."
        }
        if i.cancelTerm == .contractYear && i.start == nil { return "Für «Ende Vertragsjahr» bitte den Vertragsbeginn angeben." }
        var tmp = Contract()
        tmp.amount = 1
        tmp.cancelTerm = i.cancelTerm
        tmp.notice = i.notice
        tmp.noticeUnit = i.noticeUnit
        tmp.start = i.start
        tmp.due = i.due
        tmp.cycle = cyc
        guard let T = calc.nextTerm(tmp) else {
            return i.cancelTerm == .contractYear ? "Für «Ende Vertragsjahr» bitte den Vertragsbeginn angeben." : ""
        }
        let periodic = i.cancelTerm == .period && cyc > 1
        let per = periodic ? (cyc == 12 ? "Das Abo-Jahr" : "Die bezahlte Periode") + " endet " : "per "
        return (periodic ? per : "Nächster Termin: " + per) + Format.fmtD(T) + " · kündigen bis "
            + Format.fmtD(calc.noticeDeadline(for: tmp, end: T)) + (tmp.notice > 0 ? "" : " (keine Frist erfasst)") + "."
    }

    // MARK: Schalter und Auswahl

    /// «An Frist erinnern» nur, wenn es eine Frist gibt (Web `syncRemind`, v152/v153): nicht bei «Nicht kündbar», nicht beim
    /// Probeabo (dort gilt noWatch = false), nicht bei Flexibel und jederzeit/Monatsende/Ende Periode monatlich (wie `isAnytime`).
    public static func showsRemindToggle(mode: ContractTermMode, cancelTerm: CancelTerm, cycle: Int) -> Bool {
        if mode == .tax || mode == .trial { return false }
        if mode == .open && (cancelTerm == .anytime || cancelTerm == .monthEnd || (cancelTerm == .period && (cycle > 0 ? cycle : 1) <= 1)) {
            return false
        }
        return true
    }

    /// Wert von `noWatch` beim Sichern (Web v153): Probeabo immer beobachtet.
    public static func noWatchOnSave(mode: ContractTermMode, toggleNoWatch: Bool) -> Bool {
        mode == .trial ? false : toggleNoWatch
    }

    /// Schnellwahl Kündigungsfrist (Web v149/v156): 1/2/3 Monate, «Andere …» mit Drehrad 0 («keine»)…90 und Einheit
    public static let noticeQuick = [1, 2, 3]
    public static let noticeWheelMax = 90
    /// «. im Monat» höchstens am 28. (Web v153)
    public static let dayOfMonthMax = 28
    /// Einheiten im Drehrad (Web `NU`): Wert, Einzahl, Mehrzahl
    public static let noticeUnits: [(unit: NoticeUnit, one: String, many: String)] = [
        (.months, "Monat", "Monate"), (.weeks, "Woche", "Wochen"), (.days, "Tag", "Tage"), (.dayOfMonth, ". im Monat", ". im Monat"),
    ]

    /// Beschriftung einer Einheit passend zur Zahl (Web `nUnitLbl`/`nUnitWh`): 1 → «Monat», sonst «Monate».
    public static func noticeUnitLabel(_ u: NoticeUnit, count n: Int) -> String {
        guard let e = noticeUnits.first(where: { $0.unit == u }) else { return "" }
        return n == 1 ? e.one : e.many
    }

    /// Text einer gewählten Frist (Web `noticeTxt`): «bis 15. im Monat», «1 Monat», «2 Wochen».
    public static func noticeChoiceText(_ n: Int, _ u: NoticeUnit) -> String {
        if u == .dayOfMonth { return "bis \(n). im Monat" }
        return "\(n) " + noticeUnitLabel(u, count: n)
    }

    /// Knopf «… übernehmen» im Drehrad (Web `nOk`): 0 → «Keine Frist übernehmen».
    public static func noticeApplyTitle(_ n: Int, _ u: NoticeUnit) -> String {
        (n == 0 ? "Keine Frist" : noticeChoiceText(n, u)) + " übernehmen"
    }

    /// Drehrad-Wert begrenzen: «. im Monat» höchstens 28 (Web v153).
    public static func clampNotice(_ n: Int, _ u: NoticeUnit) -> Int {
        u == .dayOfMonth ? Swift.min(n, dayOfMonthMax) : n
    }

    /// Schnellwahl Mindestlaufzeit (Web v151): 1/2/3 Jahre, «Andere …» mit Drehrad 1–120 Monate
    public static let termMonthsQuick = [12, 24, 36]
    public static let termMonthsWheelMax = 120

    /// «1 Jahr», «2 Jahre», «18 Monate», «1 Monat» (Web `tmTxt`).
    public static func termMonthsText(_ v: Int) -> String {
        if v % 12 == 0 { return "\(v / 12)" + (v == 12 ? " Jahr" : " Jahre") }
        return "\(v)" + (v == 1 ? " Monat" : " Monate")
    }

    /// Knopf «Andere …» mit gewähltem Wert (Web `paintTermM`): ganze Jahre «2 Jahre», sonst «18 Mt.».
    public static func termMonthsButtonText(_ v: Int) -> String {
        v % 12 == 0 ? termMonthsText(v) : "\(v) Mt."
    }

    // MARK: Mindestlaufzeit ↔ Vertragsende (Web v145)

    /// Vertragsende aus Beginn + n Monaten (Web `termEndFromM`): Ende = Beginn + n Monate − 1 Tag; nur 1…600 Monate.
    public static func termEnd(start: Day, months n: Int) -> Day? {
        guard n > 0 && n <= 600 else { return nil }
        return start.addingMonths(n).addingDays(-1)
    }

    /// Mindestlaufzeit in Monaten aus Beginn und Ende (Web `termMFromEnd`), nil wenn das Ende kein solcher Termin ist.
    public static func termMonths(start: Day?, end: Day?) -> Int? {
        guard let st = start, let en = end, en > st else { return nil }
        for n in 1...600 {
            let e = st.addingMonths(n).addingDays(-1)
            if e == en { return n }
            if e > en { break }
        }
        return nil
    }

    // MARK: Zahlung am (Web v151/v153/v156/v159)

    /// Nächste Zahlung zu «Tag d (1–31) und Monat m (1–12)» ab heute (Web `dueFrom`, v153): monatlich in diesem bzw. nächstem
    /// Monat, sonst ab Monat m im Rhythmus bis ≥ heute. Anker = Datum mit genau diesem Tag (29.–31.: in einem Monat, der den
    /// Tag hat, notfalls vor heute), damit kürzere Monate aufs Monatsende fallen statt den Tag dauerhaft zu kürzen.
    public static func dueFrom(day d: Int, month m: Int, cycle: Int, today t: Day) -> Day {
        let cy = cycle > 0 ? cycle : 1
        // mo 0-basiert wie JS; Überlauf in Folgejahre wie `new Date(y, mo, …)`
        func at(_ mo: Int) -> Day {
            let dim = Day(t.year, mo + 2, 0).day
            return Day(t.year, mo + 1, Swift.min(d, dim))
        }
        var mo = cy == 1 ? t.month - 1 : m - 1
        var x = at(mo)
        if cy > 1 {
            var g = 0
            while x < t && g < 1200 {
                g += 1
                mo += cy
                x = at(mo)
            }
        } else if x < t {
            mo += 1
            x = at(mo)
        }
        var g = 0
        while g < 12 && x.day < d {
            g += 1
            mo -= cy
            x = at(mo)
        }
        return x
    }

    /// Einnahme (Web `iDueFrom`, v159): gleiche Regel (einmalig wie monatlich).
    public static func incomeDueFrom(day d: Int, month m: Int, cycle: Int, today t: Day) -> Day {
        dueFrom(day: d, month: m, cycle: cycle, today: t)
    }

    /// Neuer Vertrag, «Zahlung am» nicht selbst gewählt (Web `dueFromStart`, v156): bei Rhythmus ≥ 2 Monate ab Vertragsbeginn
    /// im Rhythmus bis ≥ heute (Jahresabo ab 15.3. → 15.3.). nil = nichts ändern (monatlich, ohne Beginn).
    /// Nicht anwenden beim Bearbeiten, nach eigener Wahl («Zahlung am» angetippt) und im Probeabo.
    public static func dueFromStart(start s: Day?, cycle: Int, today t: Day) -> Day? {
        let cy = cycle > 0 ? cycle : 1
        guard cy >= 2, let s = s else { return nil }
        var x = s
        var k = 0
        while x < t && k < 400 {
            k += 1
            x = s.addingMonths(cy * k)
        }
        return x
    }

    /// Probeabo (Web `trialDue`, v156): erste Zahlung = erster kostenpflichtiger Tag.
    public static func trialDue(trial: Day?) -> Day? { trial }

    /// Text der Zeile «Zahlung am» (Web `dueTxt`/`iDueTxt`): «27. im Monat», «27. Jan, Apr, Jul, Okt», «27. Juni»,
    /// «27. Juni (alle 2 Jahre)»; einmalig (Rhythmus 0, nur Einnahmen) das Datum; ohne Datum «wählen».
    public static func dueText(_ v: Day?, cycle: Int) -> String {
        guard let v = v else { return "wählen" }
        if cycle == 0 { return Format.fmtD(v) }
        let cy = cycle
        let d = "\(v.day)."
        if cy == 1 { return d + " im Monat" }
        if cy < 12 {
            let ms = dueGridMonths(month: v.month, cycle: cy).sorted()
            return d + " " + ms.map { Format.monthShort[$0 - 1] }.joined(separator: ", ")
        }
        return d + " " + Format.monthNames[v.month - 1] + (cy == 24 ? " (alle 2 Jahre)" : "")
    }

    /// Markierte Monate im Tagesraster (Web `dgHtml`, v159): bei Rhythmus 2–11 die ganze Reihe (z.B. Jan/Apr/Jul/Okt),
    /// ab jährlich nur der Monat; monatlich keine Monatsreihe. Monate 1–12.
    public static func dueGridMonths(month m: Int, cycle cy: Int) -> Set<Int> {
        if cy <= 1 { return [] }
        if cy >= 12 { return [m] }
        var on = Set<Int>()
        var k = 0
        while k < 12 {
            on.insert((m - 1 + k) % 12 + 1)
            k += cy
        }
        return on
    }

    /// Monatsreihe im Tagesraster nur bei Rhythmus ≥ 2 Monate (Web `dgHtml`).
    public static func dueGridShowsMonths(cycle: Int) -> Bool { cycle > 1 }

    // MARK: Gekündigte Verträge korrigieren (Web v145)

    /// Prüfung «Gekündigt am» / «Läuft bis» beim Sichern: nil = in Ordnung, sonst Toast-Text.
    public static func checkCancellation(per: Day?, on: Day?) -> String? {
        guard let p = per else { return missingCancelPerText }
        if let o = on, o > p { return cancelOrderText }
        return nil
    }
}

extension AppData {
    /// Kündigungsdaten eines gekündigten Vertrags korrigieren (Web v145, Formular «Gekündigt am»/«Läuft bis»).
    /// Ohne «Gekündigt am» bleibt das bisherige Datum. Fehler: Toast-Text aus `ContractFormRules.checkCancellation`.
    @discardableResult
    public mutating func correctCancellation(_ id: UUID, per: Day?, on: Day?) -> String? {
        guard let i = contractIndex(id), contracts[i].cancelPer != nil else { return nil }
        if let err = ContractFormRules.checkCancellation(per: per, on: on) { return err }
        contracts[i].cancelPer = per
        if let o = on { contracts[i].cancelledOn = o }
        return nil
    }
}
