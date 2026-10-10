import SwiftUI
import PhotosUI
import KontivoCore

extension String {
    /// Getrimmt (Leerzeichen und Zeilenumbrüche)
    var ctTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Entwurf des Vertragsformulars (draft der Web-App). Alle Formularfelder als Werte, gesichert über `saveContract`.
@MainActor
@Observable
final class CTFormState {
    /// Art des Vertrags (Web `termMode`, Kacheln): Flexibel, Mindestlaufzeit, Probeabo, Nicht kündbar (= `noCancel`)
    enum TermMode: String, Hashable, CaseIterable { case open, fixed, trial, tax }

    let context: ContractFormContext
    /// Ausgangsvertrag (bestehend, Entwurf, Kopie); Felder ausserhalb des Formulars bleiben unverändert
    let base: Contract
    /// Vertrag existiert schon (bearbeiten)
    let isExisting: Bool
    let title: String
    /// Stichtag beim Öffnen (für Probeabo-Chips ohne Vertragsbeginn)
    let today0: Day

    // Hauptseite
    var label: String
    var partnerName: String
    var categoryID: UUID?
    var holderIDs: [UUID]
    /// Individuelle Aufteilung (leer = gleich; Web `draft.split`)
    var split: [SplitShare]
    var amountText: String
    var currency: Currency
    var cycle: Int
    var due: Day
    var termMode: TermMode
    /// Kachel «Nicht kündbar» durch die Kategorie «Steuern & Gebühren» erzwungen (Web `draft.taxForced`)
    var taxForced = false
    var start: Day?
    var end: Day?
    var noticeText: String
    var noticeUnit: NoticeUnit
    var cancelTerm: CancelTerm
    var renewMonths: Int

    // Weitere Angaben
    var prices: [PriceChange]
    var extras: [ExtraPayment]
    /// «Pflichtvertrag» und «Nicht an Frist erinnern» (Weitere Angaben → Erinnerung und Wechsel)
    var mandatory: Bool
    var noWatch: Bool
    var isRent: Bool?
    var cancelChannel: CancelChannel?
    var trial: Day?
    var cancelURL: String
    var customerNo: String
    var contractNo: String
    var payMethod: String
    var payAccount: String
    var web: String
    var tel: String
    var mail: String
    var note: String
    var address: PostalAddress
    var documents: [Attachment]

    // Logo und Farbe
    var colorHex: String?
    var logoID: String?
    var logoBg: String?
    /// Logo in diesem Formular gewählt oder entfernt
    var logoTouched = false
    /// «Kündigungsfrist prüfen»: Fokus ins Fristfeld setzen (Hauptseite)
    var focusNotice = false
    /// «Erfassen/Ändern» beim Kündigungsweg Brief: Weitere Angaben bei der Adresse öffnen
    var focusAddress = false
    /// Gewählter Chip der Probeabo-Dauer (Web `trialD`): "", 7d, 14d, 1m, 3m, date
    var trialChoice = ""

    // Vorlagen und Vorschläge
    /// Name der übernommenen Katalog-Vorlage
    var tplHint = ""
    /// Vorschlag «übliche Frist» aus dem Internet-Treffer
    var stdTpl: CatalogEntry?
    var stdDone = false
    /// Zuletzt gewählter Vorschlag (Liste ausblenden, solange der Text gleich ist)
    var pSugSel = ""
    /// Katalog-Zusammenfassung: Stand vor/nach dem Übernehmen, Liste der Änderungen, vorgeschlagenes Logo (Web tplUndo/tplAfter/tplSum/tplLogo)
    var tplUndo: CTTplSnap?
    var tplAfter: CTTplSnap?
    var tplSum: [String]?
    var tplLogoID: String?

    // Eingaben auf «Weitere Angaben»
    var priceFrom: Day?
    var priceAmountText = ""
    var extraCredit = false
    var extraDate: Day?
    var extraAmountText = ""
    var extraNote = ""

    // Fenster und Auswahl
    var showCategoryPicker = false
    var showCatalog = false
    var showLogoSearch = false
    var logoOpen = false
    /// Panel «Dokumente» (Chip neben dem Logo)
    var docsOpen = false
    /// Hinweis nach «Google» («So geht’s …»)
    var googleHint = false
    var cropItem: CTImageItem?
    var logoPhoto: PhotosPickerItem?
    var docPhoto: PhotosPickerItem?
    var showFileImporter = false
    /// Formular geschlossen (laufende Netzabfragen verwerfen)
    var closed = false

    private let initialPartnerID: UUID?
    private let initialWeb: String
    private let initialAddress: PostalAddress
    @ObservationIgnored private var initialSnapshot: CTFormSnapshot?

    init(context: ContractFormContext, data: AppData, today: Day) {
        self.context = context
        today0 = today
        var c: Contract
        var blankAmount = false
        var useHomeCurrency = false
        switch context {
        case .new(let prefill):
            c = prefill ?? Contract()
            if c.holderIDs.isEmpty { c.holderIDs = data.defaultHolderIDs }
            if c.due == nil { c.due = today }
            blankAmount = !(c.amount > 0)
            useHomeCurrency = !(c.amount > 0)
            title = "Neuer Vertrag"
        case .edit(let id):
            c = data.contract(id) ?? Contract()
            title = "Bearbeiten"
        case .duplicate(let id):
            c = data.duplicateDraft(id) ?? Contract()
            title = "Duplizieren"
        case .newProvider(let draft):
            c = draft
            title = "Neuer Anbieter"
        }
        base = c
        isExisting = data.contract(c.id) != nil
        let partner = data.partner(c.partnerID)
        label = c.label
        partnerName = partner?.name ?? ""
        categoryID = data.category(c.categoryID) != nil ? c.categoryID : nil
        let personIDs = Set(data.persons.map { $0.id })
        holderIDs = c.holderIDs.filter { personIDs.contains($0) }
        split = c.validSplit != nil ? c.split : []
        let cur0 = useHomeCurrency ? data.settings.homeCurrency : c.currency
        currency = cur0
        amountText = blankAmount ? "" : CTNumber.field(c.amount, cur0)
        cycle = c.cycle == 0 ? 1 : c.cycle
        due = c.due ?? today
        if c.noCancel {
            termMode = .tax
        } else if c.end != nil || c.renewMonths != 0 {
            termMode = .fixed
        } else if let tr = c.trial, c.trialKept == nil, tr >= today {
            termMode = .trial
        } else {
            termMode = .open
        }
        start = c.start
        end = c.end
        noticeText = c.notice > 0 ? "\(c.notice)" : ""
        noticeUnit = c.noticeUnit
        cancelTerm = c.cancelTerm
        renewMonths = c.renewMonths
        prices = c.prices
        extras = c.extras.filter { $0.amount.isFinite && $0.amount != 0 }.ctStableSorted { $0.date < $1.date }
        mandatory = c.mandatory
        noWatch = c.noWatch
        isRent = c.isRent
        cancelChannel = c.cancelChannel
        trial = c.trial
        cancelURL = c.cancelURL
        customerNo = c.customerNo
        contractNo = c.contractNo
        payMethod = c.payMethod
        payAccount = c.payAccount
        web = partner?.web ?? ""
        tel = c.tel
        mail = c.mail
        note = c.note
        address = partner?.address ?? PostalAddress()
        documents = c.documents
        colorHex = c.colorHex
        logoID = c.logoID
        logoBg = c.logoBg
        initialPartnerID = partner?.id
        initialWeb = partner?.web ?? ""
        initialAddress = partner?.address ?? PostalAddress()
        initialSnapshot = nil
        if termMode == .trial { syncTrialChoice() }
        // Steuern & Gebühren: immer «Nicht kündbar» (Web paintCats)
        categoryChanged(data)
        initialSnapshot = snapshot()
    }

    // MARK: Änderungen erkennen

    func snapshot() -> CTFormSnapshot {
        CTFormSnapshot(label: label, partnerName: partnerName, categoryID: categoryID, holderIDs: holderIDs, split: split, amountText: amountText,
                       currency: currency, cycle: cycle, due: due, termMode: termMode, start: start, end: end, noticeText: noticeText,
                       noticeUnit: noticeUnit, cancelTerm: cancelTerm, renewMonths: renewMonths, prices: prices, extras: extras,
                       mandatory: mandatory, noWatch: noWatch, isRent: isRent, cancelChannel: cancelChannel, trial: trial, cancelURL: cancelURL,
                       customerNo: customerNo, contractNo: contractNo, payMethod: payMethod, payAccount: payAccount,
                       web: web, tel: tel, mail: mail, note: note, address: address, documents: documents,
                       colorHex: colorHex, logoID: logoID, logoBg: logoBg, logoTouched: logoTouched)
    }

    /// Wurde etwas geändert (auch angefangene Eingaben auf «Weitere Angaben»)?
    var isDirty: Bool {
        if snapshot() != initialSnapshot { return true }
        return !priceAmountText.ctTrimmed.isEmpty || !extraAmountText.ctTrimmed.isEmpty || !extraNote.ctTrimmed.isEmpty
    }

    // MARK: Vertragspartner

    /// Eingabe im Feld Vertragspartner (nur Tippen, nicht programmatisch)
    func userTypedPartner(_ v: String) {
        partnerName = v
        if !pSugSel.isEmpty && v.ctTrimmed != pSugSel { pSugSel = "" }
        tplHint = ""
        stdTpl = nil
    }

    /// Eigenen Vertragspartner übernehmen (pickOwnPartner): nur leere Felder füllen
    func pickOwn(_ g: Partners.Group, data: AppData) {
        partnerName = g.partner.name
        pSugSel = g.partner.name
        if web.ctTrimmed.isEmpty && !g.partner.web.isEmpty { web = g.partner.web }
        if address.isEmpty && !g.partner.address.isEmpty { address = g.partner.address }
        if let c0 = data.contract(g.contractIDs.first) {
            if !categoryValid(data), let cid = c0.categoryID, data.category(cid) != nil { categoryID = cid }
            if tel.ctTrimmed.isEmpty && !c0.tel.isEmpty { tel = c0.tel }
            if mail.ctTrimmed.isEmpty && !c0.mail.isEmpty { mail = c0.mail }
        }
    }

    /// Internet-Treffer übernehmen (pickWebPartner, ohne Logo): nur leere Felder füllen. Rückgabe: übernommene Angaben für den Toast.
    func pickWeb(_ w: WebPartnerHit, data: AppData) -> [String] {
        partnerName = w.name
        pSugSel = w.name
        tplHint = ""
        var got: [String] = []
        if !w.dom.isEmpty && web.ctTrimmed.isEmpty { web = w.dom; got.append("Website") }
        if !w.tel.isEmpty && tel.ctTrimmed.isEmpty { tel = w.tel; got.append("Telefon") }
        if !w.mail.isEmpty && mail.ctTrimmed.isEmpty { mail = w.mail; got.append("E-Mail") }
        var t: CatalogEntry?
        if var k = Catalog.entry(forDomain: w.dom) {
            k.name = w.name
            t = k
        } else {
            t = Catalog.standardRule(for: w, categoryNames: data.categories.map { $0.name })
        }
        stdDone = false
        if let tt = t, !tt.category.isEmpty, !categoryValid(data), let cid = CTFormState.categoryID(for: tt.category, data: data) {
            categoryID = cid
            got.append("Kategorie")
        }
        if let tt = t, !tt.label.isEmpty, label.ctTrimmed.isEmpty { label = tt.label }
        if let tt = t, tt.hint.isEmpty { t = nil }
        stdTpl = t
        if let tt = t, tt.notice > 0 || tt.cancelTerm != .anytime || tt.mandatory,
           noticeText.ctTrimmed.isEmpty, cancelTerm == .anytime {
            applyTemplate(tt, keepName: true, onlyEmpty: true, data: data)
            stdTpl = tt
            stdDone = true
            got.append("übliche Frist")
        }
        let cc = (t?.country.isEmpty == false) ? (t?.country ?? "") : w.cc
        if !cc.isEmpty && amountText.ctTrimmed.isEmpty { currency = cc == "DE" ? .EUR : .CHF }
        return got
    }

    /// Vorlage übernehmen (applyTpl). `onlyEmpty`: nur leere Felder füllen (Internet-Vorschlag, «Übliche Frist übernehmen»).
    /// Sonst (Katalog) mit Zusammenfassung und «Rückgängig» (tplUndo/tplAfter/tplSum).
    func applyTemplate(_ t: CatalogEntry, keepName: Bool, onlyEmpty: Bool, data: AppData) {
        let snap = tplSnapshot()
        if !keepName {
            partnerName = t.name
            pSugSel = t.name
        }
        if label.ctTrimmed.isEmpty { label = t.label }
        if !t.category.isEmpty, let cid = CTFormState.categoryID(for: t.category, data: data) {
            if !onlyEmpty || !categoryValid(data) {
                categoryID = cid
                categoryChanged(data)
            }
        }
        if onlyEmpty {
            if t.notice > 0 && noticeText.ctTrimmed.isEmpty {
                noticeText = "\(t.notice)"
                noticeUnit = t.noticeUnit
            }
        } else {
            // Vorlage gilt vollständig: ohne Frist (z.B. Banken) wird das Feld geleert
            noticeText = t.notice > 0 ? "\(t.notice)" : ""
            if t.notice > 0 { noticeUnit = t.noticeUnit }
        }
        if termMode != .fixed && (!onlyEmpty || cancelTerm == .anytime) { cancelTerm = t.cancelTerm }
        if let ch = t.cancelChannel, !onlyEmpty || cancelChannel == nil { cancelChannel = ch }
        if !t.web.isEmpty && web.ctTrimmed.isEmpty { web = t.web }
        // Kündigungslink aus dem Katalog nur, wenn noch keiner eingetragen ist (Web `applyTpl`)
        if !t.cancelURL.isEmpty && cancelURL.ctTrimmed.isEmpty { cancelURL = t.cancelURL }
        if !t.tel.isEmpty && tel.ctTrimmed.isEmpty { tel = t.tel }
        if !t.mail.isEmpty && mail.ctTrimmed.isEmpty { mail = t.mail }
        // Kontaktdaten aus dem Katalog nur in leere Felder (Web b520636)
        if !t.address.isEmpty && address.isEmpty { address = WebImport.addrSplit(t.address, partnerName: partnerName) }
        // Katalog «Steuern & Gebühren» (Serafe, Rundfunkbeitrag): nicht kündbar statt Pflichtvertrag
        let tFix = t.isFixed
        if onlyEmpty {
            if tFix && !mandatory && !noWatch {
                setTermMode(.tax)
            } else if t.mandatory && !tFix && !mandatory && !noWatch && termMode != .tax {
                mandatory = true
            }
        } else {
            if tFix {
                setTermMode(.tax)
            } else if termMode == .tax {
                setTermMode(.open)
            }
            mandatory = t.mandatory && !tFix
            if t.mandatory || tFix { noWatch = false }
        }
        if amountText.ctTrimmed.isEmpty, let cur = t.suggestedCurrency { currency = cur }
        tplHint = t.name
        if !onlyEmpty {
            let after = tplSnapshot()
            tplUndo = snap
            tplAfter = after
            tplSum = CTFormState.tplSumItems(snap, after, data: data)
            tplLogoID = nil
        }
    }

    // MARK: Katalog-Zusammenfassung und «Rückgängig» (Web tplSnap, tplSumItems, tplUndo)

    func tplSnapshot() -> CTTplSnap {
        CTTplSnap(partnerName: partnerName, label: label, noticeText: noticeText, noticeUnit: noticeUnit, cancelTerm: cancelTerm,
                  cancelChannel: cancelChannel, web: web, cancelURL: cancelURL, tel: tel, mail: mail, address: address,
                  currency: currency, noCancel: termMode == .tax, mandatory: mandatory, noWatch: noWatch, categoryID: categoryID,
                  termMode: termMode, end: end, renewMonths: renewMonths, trial: trial,
                  logoID: logoID, logoBg: logoBg, logoTouched: logoTouched)
    }

    /// Was hat der Katalog geändert? (Web tplSumItems)
    static func tplSumItems(_ a: CTTplSnap, _ b: CTTplSnap, data: AppData) -> [String] {
        var items: [String] = []
        if a.categoryID != b.categoryID, let c = data.category(b.categoryID) { items.append(c.name) }
        let nt = b.noticeText.ctTrimmed
        if (a.noticeText != b.noticeText || a.noticeUnit != b.noticeUnit) && !nt.isEmpty {
            let n = Int(nt) ?? 0
            switch b.noticeUnit {
            case .dayOfMonth: items.append("Frist bis zum \(n).")
            case .months: items.append("Frist \(n) " + (n == 1 ? "Monat" : "Monate"))
            case .weeks: items.append("Frist \(n) " + (n == 1 ? "Woche" : "Wochen"))
            case .days: items.append("Frist \(n) " + (n == 1 ? "Tag" : "Tage"))
            }
        }
        if a.cancelTerm != b.cancelTerm && b.cancelTerm != .anytime { items.append("per " + CTFormState.termOptionText(b.cancelTerm)) }
        if a.cancelChannel != b.cancelChannel, let ch = b.cancelChannel {
            let w: [CancelChannel: String] = [.online: "online", .email: "per E-Mail", .letter: "per Brief", .registered: "per Einschreiben"]
            items.append("Kündigung " + (w[ch] ?? ch.webText))
        }
        var k: [String] = []
        if a.web != b.web && !b.web.ctTrimmed.isEmpty { k.append("Website") }
        if a.cancelURL != b.cancelURL && !b.cancelURL.ctTrimmed.isEmpty { k.append("Kündigungslink") }
        if a.tel != b.tel && !b.tel.ctTrimmed.isEmpty { k.append("Telefon") }
        if a.mail != b.mail && !b.mail.ctTrimmed.isEmpty { k.append("E-Mail") }
        if a.address != b.address && !b.address.isEmpty { k.append("Adresse") }
        if !k.isEmpty { items.append(k.count > 2 ? "Kontaktdaten" : k.joined(separator: ", ")) }
        if !a.mandatory && b.mandatory { items.append("Pflichtvertrag") }
        if !a.noCancel && b.noCancel { items.append("nicht kündbar") }
        return items
    }

    /// Optionstext «Kündbar per» (für «per Jahresende» usw.)
    static func termOptionText(_ t: CancelTerm) -> String {
        switch t {
        case .anytime: return "jederzeit"
        case .period: return "Ende Periode"
        case .monthEnd: return "Monatsende"
        case .quarterEnd: return "Quartalsende"
        case .halfYearEnd: return "Halbjahresende"
        case .yearEnd: return "Jahresende"
        case .contractYear: return "Ende Vertragsjahr"
        }
    }

    /// Karte «Aus dem Katalog übernommen» sichtbar?
    var showsTplSummary: Bool { tplUndo != nil && tplSum != nil }

    /// Vom Katalog vorgeschlagenes Logo übernehmen (nur in den offenen Entwurf; gilt erst mit «Sichern»)
    func applyCatalogLogo(id: String, bg: String) {
        logoID = id
        logoBg = bg
        logoTouched = true
        tplLogoID = id
        if var s = tplSum, !s.contains("Logo") {
            s.insert("Logo", at: 0)
            tplSum = s
        }
    }

    /// «Rückgängig»: nur zurücksetzen, was seit dem Übernehmen nicht von Hand geändert wurde (Web tplUndo)
    func tplUndoApply(data: AppData) {
        guard let o = tplUndo else { return }
        let a = tplAfter ?? o
        let cur = tplSnapshot()
        if cur.partnerName == a.partnerName { partnerName = o.partnerName; pSugSel = "" }
        if cur.label == a.label { label = o.label }
        if cur.noticeText == a.noticeText { noticeText = o.noticeText }
        if cur.noticeUnit == a.noticeUnit { noticeUnit = o.noticeUnit }
        if cur.cancelTerm == a.cancelTerm { cancelTerm = o.cancelTerm }
        if cur.cancelChannel == a.cancelChannel { cancelChannel = o.cancelChannel }
        if cur.web == a.web { web = o.web }
        if cur.cancelURL == a.cancelURL { cancelURL = o.cancelURL }
        if cur.tel == a.tel { tel = o.tel }
        if cur.mail == a.mail { mail = o.mail }
        if cur.address == a.address { address = o.address }
        if cur.currency == a.currency { currency = o.currency }
        if cur.mandatory == a.mandatory { mandatory = o.mandatory }
        if cur.noWatch == a.noWatch { noWatch = o.noWatch }
        if cur.categoryID == a.categoryID { categoryID = o.categoryID }
        if let l = tplLogoID, logoID == l {
            logoID = o.logoID
            logoBg = o.logoBg
            logoTouched = o.logoTouched
        }
        tplLogoID = nil
        tplUndo = nil
        tplAfter = nil
        tplSum = nil
        tplHint = ""
        // Reihenfolge wie Web: zuerst Kategorie (paintCats), dann die Art des Vertrags
        categoryChanged(data)
        if cur.termMode == a.termMode { setTermMode(o.termMode) }
        if cur.end == a.end { end = o.end }
        if cur.renewMonths == a.renewMonths { renewMonths = o.renewMonths }
        if cur.trial == a.trial {
            trial = o.trial
            trialChoice = ""
            if termMode == .trial { syncTrialChoice() }
        }
    }

    /// Kategorie zu einem Namen der Vorbelegung (gleicher Name, sonst gleiche Art)
    static func categoryID(for name: String, data: AppData) -> UUID? {
        if name.isEmpty { return nil }
        if let c = data.category(named: name) { return c.id }
        if let k = KCategory.defaultKind(forName: name), let c = data.categories.first(where: { $0.kind == k }) { return c.id }
        return nil
    }

    func categoryValid(_ data: AppData) -> Bool {
        guard let id = categoryID else { return false }
        return data.category(id) != nil
    }

    /// Vorschläge unter dem Vertragspartner (paintSugg)
    enum Suggest {
        case none
        case hint(String, standardChip: Bool)
        case chips([CatalogEntry])
        /// Exakter Katalog-Treffer (z.B. «CSS», «O2»), noch nicht übernommen: Chip «‹Name› übernehmen»
        case exact(CatalogEntry)
        /// Katalog übernommen: Karte «Aus dem Katalog übernommen» mit Liste und «Rückgängig»
        case summary(CatalogEntry, items: [String])
    }

    var suggest: Suggest {
        let pn = partnerName.ctTrimmed
        if let st = stdTpl, st.name == pn {
            return .hint(st.hintFull, standardChip: !stdDone && (st.notice > 0 || st.cancelTerm != .anytime || st.mandatory))
        }
        let cur = Catalog.find(pn)
        if let c = cur, tplHint == c.name, showsTplSummary { return .summary(c, items: tplSum ?? []) }
        if let c = cur { return tplHint == c.name ? .hint(c.hintFull, standardChip: false) : .exact(c) }
        let q = (pn.isEmpty ? label : pn).ctTrimmed.lowercased()
        if q.count < 2 { return .none }
        let hits = Catalog.suggestions(q)
        return hits.isEmpty ? .none : .chips(hits)
    }

    /// «Übliche Frist übernehmen»: wie Web nur leere Felder füllen (bewusst gewählte Werte bleiben)
    func applyStandard(data: AppData) {
        guard let st = stdTpl else { return }
        applyTemplate(st, keepName: true, onlyEmpty: true, data: data)
        stdTpl = st
        stdDone = true
    }

    // MARK: Inhaber

    func toggleHolder(_ id: UUID, persons: [Person]) {
        var set = Set(holderIDs)
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        holderIDs = persons.map { $0.id }.filter { set.contains($0) }
        syncSplit()
    }

    // MARK: Aufteilung (Web paintSplit)

    var splitIndividual: Bool { !split.isEmpty && holderIDs.count >= 2 }

    /// Unter 2 Inhabern keine Aufteilung; fehlt ein Inhaber in der Aufteilung, wieder gleichmässig vorbelegen.
    func syncSplit() {
        if holderIDs.count < 2 { split = []; return }
        if split.isEmpty { return }
        if !holderIDs.allSatisfy({ h in split.contains { $0.personID == h } }) { split = AppData.equalSplit(holders: holderIDs) }
    }

    func setSplitIndividual(_ on: Bool) {
        split = on ? AppData.equalSplit(holders: holderIDs) : []
    }

    /// Anteil in Prozent (4 Nachkommastellen).
    func splitPercent(_ id: UUID) -> Double { split.first { $0.personID == id }?.percent ?? 0 }

    /// Betrag pro Zahlung zum aktuellen Preis (Anfangspreis + Preisänderungen bis heute), Basis der Aufteilung (Web spTotal).
    func splitTotal(today: Day) -> Double {
        var a = CTNumber.parse(amountText) ?? 0
        for p in sortedPrices where p.from <= today { a = p.amount }
        return a
    }

    /// Betrag einer Person auf den Rappen.
    func splitAmount(_ id: UUID, total: Double) -> Double { (total * splitPercent(id)).rounded() / 100 }

    /// Betrag setzen (Web v82–v84): 2 Inhaber → die andere Person bekommt den Rest; ab 3 zuerst vom letzten (Rest) nehmen,
    /// reicht das nicht, von den übrigen von hinten.
    func setSplitAmount(_ id: UUID, _ x: Double, total: Double) {
        guard holderIDs.count >= 2, total > 0 else { return }
        let v = AppData.roundPercent(max(0, min(total, x)) / total * 100)
        var o: [UUID: Double] = [:]
        for s in split { o[s.personID] = s.percent }
        if holderIDs.count == 2 {
            let other = holderIDs[0] == id ? holderIDs[1] : holderIDs[0]
            o[id] = v
            o[other] = AppData.roundPercent(100 - v)
        } else {
            guard let last = holderIDs.last, id != last else { return }
            o[id] = v
            let mids = holderIDs.dropLast()
            func sum() -> Double { mids.reduce(0.0) { $0 + (o[$1] ?? 0) } }
            for y in mids.reversed() where y != id && sum() > 100 { o[y] = max(0, (o[y] ?? 0) - (sum() - 100)) }
            o[last] = max(0, AppData.roundPercent(100 - sum()))
        }
        split = holderIDs.map { SplitShare(personID: $0, percent: o[$0] ?? 0) }
    }

    /// Adresse aus der Zwischenablage auf die Felder verteilen (Web «Einfügen», v86). false = nichts Brauchbares.
    @discardableResult
    func pasteAddress(_ text: String) -> Bool {
        guard let a = WebImport.addrFromPaste(text, partnerName: partnerName), !a.isEmpty else { return false }
        address = a
        return true
    }

    // MARK: Logo und Farbe

    /// Angezeigtes Logo: im Formular gewählt, sonst Logo des Vertragspartners, sonst eigenes Logo des Vertrags
    func effectiveLogo(_ data: AppData) -> (id: String, bg: String)? {
        if logoTouched {
            guard let l = logoID, !l.isEmpty else { return nil }
            return (l, logoBg ?? "#FFFFFF")
        }
        let n = Format.collapseSpaces(partnerName)
        if !n.isEmpty, let p = Partners.find(n, in: data), let l = p.logoID, !l.isEmpty {
            return (l, p.logoBg ?? "#FFFFFF")
        }
        if let l = logoID, !l.isEmpty { return (l, logoBg ?? "#FFFFFF") }
        return nil
    }

    /// Farbe der Kachel ohne Logo: gewählte Farbe → Kategorie → Hash über Vertragspartner/Bezeichnung
    func markColor(_ data: AppData) -> String {
        if let c = colorHex, !c.isEmpty { return c }
        if let cat = data.category(categoryID) { return cat.colorHex }
        let pn = partnerName.ctTrimmed
        return AppData.hashColor(pn.isEmpty ? label : pn)
    }

    /// Name für die Logo-Suche: Vertragspartner, sonst Bezeichnung
    var logoSearchName: String {
        let pn = partnerName.ctTrimmed
        return pn.isEmpty ? label.ctTrimmed : pn
    }

    func setLogo(_ png: Data, background: String, model: AppModel) {
        guard let id = model.storeFile(png, type: "image/png") else { return }
        logoID = id
        logoBg = background
        logoTouched = true
        model.toast("Logo gesetzt")
    }

    func removeLogo() {
        logoID = nil
        logoBg = nil
        logoTouched = true
    }

    // MARK: Hinweise

    /// Hinweis «Mögliches Duplikat …» (nicht blockierend)
    func duplicateHint(_ data: AppData, today: Day) -> String? {
        let amt = CTNumber.parse(amountText)
        guard let hit = Partners.possibleDuplicate(partnerName: partnerName, label: label, amount: amt, currency: currency,
                                                   in: data, today: today, excluding: isExisting ? base.id : nil) else { return nil }
        return Partners.duplicateHint(hit, in: data, today: today)
    }

    // MARK: Art des Vertrags (Web setTermMode, Kacheln)

    /// Art wählen. Jede Art zeigt nur ihre Felder (siehe Ansicht); «Nicht kündbar» = `noCancel`.
    func setTermMode(_ m: TermMode) {
        termMode = m
        if m == .trial && trialChoice.isEmpty { syncTrialChoice() }
    }

    /// Kategorie geändert (Web paintCats): «Steuern & Gebühren» erzwingt «Nicht kündbar», danach zurück auf «Flexibel»
    func categoryChanged(_ data: AppData) {
        let tx = data.category(categoryID)?.kind == .taxes
        if tx && termMode != .tax {
            taxForced = true
            setTermMode(.tax)
        } else if !tx && taxForced {
            taxForced = false
            if termMode == .tax { setTermMode(.open) }
        }
    }

    /// Kachel nur wählbar, wenn die Kategorie nicht «Steuern & Gebühren» ist (dann nur «Nicht kündbar»)
    func termModeEnabled(_ m: TermMode, data: AppData) -> Bool {
        data.category(categoryID)?.kind != .taxes || m == .tax
    }

    // MARK: Probeabo-Dauer (Web trialFrom, paintTrialD)

    static let trialKeys = ["7d", "14d", "1m", "3m"]

    /// Ende des Probeabos ab Vertragsbeginn (sonst heute)
    func trialFrom(_ k: String, today: Day) -> Day {
        let b = start ?? today
        switch k {
        case "7d": return b.addingDays(7)
        case "14d": return b.addingDays(14)
        case "3m": return b.addingMonths(3)
        default: return b.addingMonths(1)
        }
    }

    /// Passenden Chip zum gespeicherten Datum bestimmen (nur wenn noch keiner gewählt ist)
    func syncTrialChoice() {
        guard trialChoice.isEmpty, let tr = trial else { return }
        trialChoice = CTFormState.trialKeys.first { trialFrom($0, today: today0) == tr } ?? "date"
    }

    /// Chip «7 Tage» … «Datum …» gewählt
    func pickTrial(_ k: String, today: Day) {
        trialChoice = k
        if k != "date" {
            trial = trialFrom(k, today: today)
        } else if trial == nil {
            trial = (start ?? today).addingMonths(1)
        }
    }

    /// Vertragsbeginn geändert: im Probeabo mit Dauer-Chip das Enddatum nachführen
    func startChanged(today: Day) {
        if termMode == .trial && CTFormState.trialKeys.contains(trialChoice) { trial = trialFrom(trialChoice, today: today) }
    }

    // MARK: Hinweise zur Laufzeit und Zahlung

    /// Hinweis zur Laufzeit (updTermHint)
    func termHint(_ data: AppData, today: Day) -> String {
        switch termMode {
        case .tax:
            return "Gebühren und Abgaben wie Serafe: keine Fristen, kein Kündigen. Zählt in Kosten und Budget."
        case .trial:
            guard let tv = trial else { return "Wie lange läuft das Probeabo?" }
            return "Endet am " + Format.fmtD(tv) + ". Kontivo erinnert dich unter «Fristen»."
        case .fixed, .open:
            break
        }
        let calc = Calc(data: data, today: today)
        var tmp = Contract()
        tmp.amount = 1
        tmp.cycle = cycle
        tmp.due = due
        tmp.start = start
        tmp.notice = CTNumber.int(noticeText, unit: noticeUnit)
        tmp.noticeUnit = noticeUnit
        if termMode == .fixed {
            tmp.end = end
            tmp.renewMonths = renewMonths
            tmp.cancelTerm = .anytime
            guard let E = calc.effEnd(tmp) else {
                return "Vertragsende angeben, dann rechnet die App den Kündigungstermin aus."
            }
            if let te = calc.termEnd(tmp), te > E {
                return "Frist für " + Format.fmtD(E) + " verpasst · nächster Termin " + Format.fmtD(te) + ", kündigen bis "
                    + Format.fmtD(calc.noticeDeadline(for: tmp, end: te)) + "."
            }
            let rn = renewMonths
            return "Kündigen bis " + Format.fmtD(calc.noticeDeadline(for: tmp, end: E))
                + (rn > 0 ? ", sonst +\(rn)" + (rn == 1 ? " Monat." : " Monate.") : ", Vertrag endet dann.")
        }
        if cancelTerm == .anytime {
            if cycle >= 3 {
                let w = [3: "quartalsweiser", 6: "halbjährlicher", 12: "jährlicher", 24: "zweijährlicher"][cycle] ?? "seltener"
                return "Achtung: Bei " + w + " Zahlung ist ein Abo meist nur auf Ende der bezahlten Periode kündbar. Dann «Kündbar per: Ende Periode» wählen."
            }
            return "Ohne Mindestlaufzeit: kündbar mit der angegebenen Frist."
        }
        tmp.end = nil
        tmp.cancelTerm = cancelTerm
        guard let T = calc.nextTerm(tmp) else {
            return cancelTerm == .contractYear ? "Für «Ende Vertragsjahr» bitte den Vertragsbeginn angeben." : ""
        }
        let periodic = cancelTerm == .period && cycle > 1
        let per = periodic ? (cycle == 12 ? "Das Abo-Jahr" : "Die bezahlte Periode") + " endet " : "per "
        return (periodic ? per : "Nächster Termin: " + per) + Format.fmtD(T) + " · kündigen bis "
            + Format.fmtD(calc.noticeDeadline(for: tmp, end: T)) + (tmp.notice > 0 ? "" : " (keine Frist erfasst)") + "."
    }

    /// Live-Hinweis unter «Zahlung am» (Web updPayHint): «Zahlung monatlich am 15. · nächste am 15.10.26»
    func payHint(_ data: AppData, today: Day) -> String {
        let r = Calc.payRule(cycle: cycle, due: due)
        if r.isEmpty { return "" }
        var tmp = Contract()
        tmp.amount = 1
        tmp.cycle = cycle
        tmp.due = due
        tmp.start = start
        let n = Calc(data: data, today: today).nextDue(tmp)
        return "Zahlung " + r + (n.map { " · nächste am " + Format.fmtShort($0) } ?? "")
    }

    /// Zahlungsrhythmus geändert: in «Flexibel»/«Probeabo» ohne «Kündbar per» ab halbjährlich «Ende Periode» vorschlagen
    func cycleChanged() -> String? {
        if (termMode == .open || termMode == .trial) && cancelTerm == .anytime && cycle >= 6 {
            cancelTerm = .period
            return "Kündbar per «Ende Periode» vorgeschlagen"
        }
        return nil
    }

    // MARK: Kündigungsweg (Kacheln, Web fCancT/syncCancUrl)

    /// Kachel antippen; nochmals tippen hebt die Wahl auf
    func toggleCancelChannel(_ ch: CancelChannel) {
        cancelChannel = cancelChannel == ch ? nil : ch
    }

    /// Adresse des Vertragspartners in einer Zeile (Strasse, PLZ Ort); leer = noch keine
    var addressLine: String {
        let t = { (x: String) in x.ctTrimmed }
        let zc = [t(address.zip), t(address.city)].filter { !$0.isEmpty }.joined(separator: " ")
        return [t(address.street), zc].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Zusammenfassung der Zeile «Weitere Angaben» (paintOptCounts); nil = Platzhaltertext
    var moreSummary: String? {
        func n(_ k: Int, _ one: String, _ many: String) -> String { k > 0 ? "\(k) " + (k == 1 ? one : many) : "" }
        let parts = [
            n(prices.count, "Preisänderung", "Preisänderungen"),
            n(extras.count, "Sonderzahlung", "Sonderzahlungen"),
            customerNo.ctTrimmed.isEmpty ? "" : "Kundennummer",
            contractNo.ctTrimmed.isEmpty ? "" : "Vertragsnummer",
            payMethod.isEmpty ? "" : "Zahlungsart",
            payAccount.ctTrimmed.isEmpty ? "" : "Belastet über",
            address.isEmpty ? "" : "Adresse",
            web.ctTrimmed.isEmpty ? "" : "Website",
            tel.ctTrimmed.isEmpty ? "" : "Telefon",
            mail.ctTrimmed.isEmpty ? "" : "E-Mail",
            note.ctTrimmed.isEmpty ? "" : "Notiz",
            mandatory ? "Pflichtvertrag" : "",
            noWatch ? "Ohne Erinnerung" : "",
        ].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Preisänderungen und Sonderzahlungen

    /// Ergebnis von «Preisänderung hinzufügen»
    enum PriceAddResult {
        /// Meldung (lang = 4 s)
        case toast(String, long: Bool)
        /// Preis bleibt gleich: nicht blockierend nachfragen («Trotzdem hinzufügen»)
        case confirmSame(title: String, message: String)
    }

    /// Preisänderung vormerken (Web pAdd). `force`: Rückfrage «Preis bleibt gleich» wurde bestätigt.
    func addPrice(force: Bool = false) -> PriceAddResult {
        guard let f = priceFrom else { return .toast("Datum für die Preisänderung fehlt", long: false) }
        if let s0 = start, f <= s0 { return .toast("Datum muss nach dem Vertragsbeginn liegen", long: false) }
        guard let a = CTNumber.parse(priceAmountText), a >= 0 else { return .toast("Neuen Betrag prüfen", long: false) }
        // Falle: «Betrag» oben schon auf den neuen Preis gesetzt → Änderung ohne Wirkung
        var pv = CTNumber.parse(amountText) ?? 0
        for p in sortedPrices where p.from < f { pv = p.amount }
        if abs(Format.round2(a) - pv) < 0.005 && !force {
            let cur = currency.rawValue
            return .confirmSame(title: "Preis bleibt gleich",
                                message: "Vor dem " + Format.fmtD(f) + " gilt schon " + Format.money(pv, currency) + " " + cur
                                    + ". Steht oben unter «Kosten» bereits der neue Preis? Dort gehört der Anfangspreis hin – also der Preis bei Vertragsbeginn.")
        }
        prices.removeAll { $0.from == f }
        prices.append(PriceChange(from: f, amount: Format.round2(a)))
        priceFrom = nil
        priceAmountText = ""
        var prevA = CTNumber.parse(amountText) ?? 0
        for p in sortedPrices where p.from < f { prevA = p.amount }
        if a > prevA && prevA > 0 { return .toast("Preiserhöhung vorgemerkt. Tipp: oft gilt ein Sonderkündigungsrecht.", long: true) }
        return .toast("Preisänderung ab " + Format.fmtD(f) + " vorgemerkt", long: false)
    }

    func removePrice(_ from: Day) {
        prices.removeAll { $0.from == from }
    }

    var sortedPrices: [PriceChange] {
        prices.filter { $0.amount.isFinite }.ctStableSorted { $0.from < $1.from }
    }

    /// Sonderzahlung vormerken; Rückgabe = Toast
    func addExtra() -> String {
        guard let d = extraDate else { return "Datum der Sonderzahlung fehlt" }
        guard let a0 = CTNumber.parse(extraAmountText), a0 > 0 else { return "Betrag prüfen" }
        let a = Format.round2(abs(a0))
        let credit = extraCredit
        extras.append(ExtraPayment(date: d, amount: credit ? -a : a, note: String(extraNote.ctTrimmed.prefix(60))))
        extras = extras.ctStableSorted { $0.date < $1.date }
        extraDate = nil
        extraAmountText = ""
        extraNote = ""
        extraCredit = false
        return (credit ? "Gutschrift" : "Sonderzahlung") + " am " + Format.fmtD(d) + " vorgemerkt"
    }

    // MARK: Dokumente

    func attach(_ data: Data, name: String, type: String, model: AppModel) {
        guard let id = model.storeFile(data, type: type) else { return }
        documents.append(Attachment(id: id, name: name, type: type))
        model.toast("Angehängt")
    }

    // MARK: Sichern

    /// Formularwerte als Vertrag (ohne Vertragspartner; Betrag und geprüfte Frist separat)
    func makeContract(amount: Double, notice: Int? = nil) -> Contract {
        var c = base
        c.label = label.ctTrimmed
        c.categoryID = categoryID
        c.holderIDs = holderIDs
        c.split = AppData.normalizedSplit(split, holders: holderIDs)
        c.amount = amount
        c.currency = currency
        c.cycle = cycle
        c.due = due
        c.start = start
        c.end = termMode == .fixed ? end : nil
        c.notice = notice ?? CTNumber.int(noticeText, unit: noticeUnit)
        c.noticeUnit = noticeUnit
        c.renewMonths = termMode == .fixed ? renewMonths : 0
        c.cancelTerm = (termMode == .open || termMode == .trial) ? cancelTerm : .anytime
        c.mandatory = mandatory
        c.noWatch = noWatch
        c.noCancel = termMode == .tax
        c.isRent = isRent
        c.cancelChannel = cancelChannel
        // Link nur löschen, wenn bewusst ein anderer Weg gewählt ist (E-Mail, Brief, Einschreiben; Web saveForm)
        let otherWay: Set<CancelChannel> = [.email, .letter, .registered]
        c.cancelURL = cancelChannel.map { otherWay.contains($0) } == true ? "" : cancelURL.ctTrimmed
        // Probeabo-Datum nur in «Probeabo»; Wechsel auf «Flexibel» entfernt es. Bei fester Laufzeit oder bereits
        // behaltenem Probeabo bleibt der alte Wert (nur beim Bearbeiten).
        if termMode == .trial {
            c.trial = trial
        } else if isExisting, base.trial != nil, termMode == .fixed || base.trialKept != nil {
            c.trial = base.trial
        } else {
            c.trial = nil
        }
        c.customerNo = customerNo.ctTrimmed
        c.contractNo = contractNo.ctTrimmed
        c.payMethod = payMethod
        c.payAccount = payAccount.ctTrimmed
        c.tel = tel.ctTrimmed
        c.mail = mail.ctTrimmed
        c.note = note.ctTrimmed
        c.colorHex = (colorHex ?? "").isEmpty ? nil : colorHex
        c.prices = sortedPrices
        c.extras = extras
        c.documents = documents
        return c
    }

    /// Prüfen und sichern (saveForm). Gibt true zurück, wenn gesichert wurde.
    func save(model: AppModel) -> Bool {
        let data = model.data
        let pname = Format.collapseSpaces(partnerName)
        if pname.isEmpty && label.ctTrimmed.isEmpty {
            model.toast("Bezeichnung fehlt")
            return false
        }
        guard let cid = categoryID, data.category(cid) != nil else {
            model.toast("Bitte eine Kategorie wählen")
            showCategoryPicker = true
            return false
        }
        guard let amt = CTNumber.parse(amountText), amt >= 0 else {
            model.toast("Betrag prüfen")
            return false
        }
        guard let notice = CTNumber.noticeValue(noticeText, unit: noticeUnit) else {
            model.toast("Kündigungsfrist prüfen")
            focusNotice = true
            return false
        }
        if termMode == .trial && trial == nil {
            model.toast("Wie lange läuft das Probeabo?")
            return false
        }
        var c = makeContract(amount: amt, notice: notice)
        c.categoryID = cid
        let today = model.today
        let webT = web.ctTrimmed
        let t = { (x: String) in Format.collapseSpaces(x) }
        let addr = PostalAddress(company: t(address.company), extra: t(address.extra), street: t(address.street),
                                 zip: t(address.zip), city: t(address.city), country: t(address.country))
        let touched = logoTouched
        let lid = logoID
        let lbg = logoBg
        let iPID = initialPartnerID
        let iWeb = initialWeb.ctTrimmed
        let iAddr = PostalAddress(company: t(initialAddress.company), extra: t(initialAddress.extra), street: t(initialAddress.street),
                                  zip: t(initialAddress.zip), city: t(initialAddress.city), country: t(initialAddress.country))
        return model.update { d in
            var pid: UUID?
            // Vertragspartner gewechselt: unveränderte Website/Adresse des bisherigen nicht auf den neuen übertragen
            var webInherited = false
            var addrInherited = false
            if !pname.isEmpty, let old = iPID, Partners.find(pname, in: d)?.id != old {
                webInherited = !iWeb.isEmpty && webT == iWeb
                addrInherited = !iAddr.isEmpty && addr == iAddr
            }
            if !pname.isEmpty { pid = d.partnerID(forName: pname, web: webInherited ? "" : webT) }
            c.partnerID = pid
            if let p = pid {
                if touched {
                    d.setPartnerLogo(p, logoID: lid, background: lbg)
                    c.logoID = nil
                    c.logoBg = nil
                }
                let curWeb = d.partner(p)?.web ?? ""
                if webInherited {
                    // nichts übernehmen
                } else if !webT.isEmpty {
                    if webT != curWeb { d.setPartnerWeb(p, webT) }
                } else if !curWeb.isEmpty && p == iPID && !iWeb.isEmpty {
                    d.setPartnerWeb(p, "")
                }
                let curAddr = d.partner(p)?.address ?? PostalAddress()
                if addrInherited {
                    // nichts übernehmen
                } else if !addr.isEmpty {
                    if addr != curAddr { d.setPartnerAddress(p, addr) }
                } else if !curAddr.isEmpty && p == iPID && !iAddr.isEmpty {
                    d.setPartnerAddress(p, PostalAddress())
                }
            } else if touched {
                c.logoID = lid
                c.logoBg = lbg
            }
            try d.saveContract(c, today: today)
        }
    }
}

/// Vergleichswerte für «Änderungen verwerfen?»
struct CTFormSnapshot: Hashable {
    var label: String
    var partnerName: String
    var categoryID: UUID?
    var holderIDs: [UUID]
    var split: [SplitShare]
    var amountText: String
    var currency: Currency
    var cycle: Int
    var due: Day
    var termMode: CTFormState.TermMode
    var start: Day?
    var end: Day?
    var noticeText: String
    var noticeUnit: NoticeUnit
    var cancelTerm: CancelTerm
    var renewMonths: Int
    var prices: [PriceChange]
    var extras: [ExtraPayment]
    var mandatory: Bool
    var noWatch: Bool
    var isRent: Bool?
    var cancelChannel: CancelChannel?
    var trial: Day?
    var cancelURL: String
    var customerNo: String
    var contractNo: String
    var payMethod: String
    var payAccount: String
    var web: String
    var tel: String
    var mail: String
    var note: String
    var address: PostalAddress
    var documents: [Attachment]
    var colorHex: String?
    var logoID: String?
    var logoBg: String?
    var logoTouched: Bool
}

/// Stand der Felder, die eine Katalog-Vorlage ändern kann (Web tplSnap), für Zusammenfassung und «Rückgängig»
struct CTTplSnap: Hashable {
    var partnerName: String
    var label: String
    var noticeText: String
    var noticeUnit: NoticeUnit
    var cancelTerm: CancelTerm
    var cancelChannel: CancelChannel?
    var web: String
    var cancelURL: String
    var tel: String
    var mail: String
    var address: PostalAddress
    var currency: Currency
    var noCancel: Bool
    var mandatory: Bool
    var noWatch: Bool
    var categoryID: UUID?
    var termMode: CTFormState.TermMode
    var end: Day?
    var renewMonths: Int
    var trial: Day?
    // Logo nur zum Zurücksetzen eines vorgeschlagenen Katalog-Logos
    var logoID: String?
    var logoBg: String?
    var logoTouched: Bool
}
