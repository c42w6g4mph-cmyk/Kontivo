import SwiftUI
import PhotosUI
import KontivoCore

extension String {
    /// Getrimmt (Leerzeichen und Zeilenumbrüche)
    var ctTrimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Entwurf des Vertragsformulars (draft der Web-App, Stand v160). Alle Formularfelder als Werte, gesichert über `saveContract`.
/// Regeln und Texte kommen aus dem Kern (`ContractFormRules`, `ContractTermMode`, `Calc`), hier nur der Ablauf der Bedienung.
@MainActor
@Observable
final class CTFormState {
    /// Art des Vertrags (Kern `ContractTermMode`): Flexibel, Mindestlaufzeit, Probeabo, Nicht kündbar (= `noCancel`)
    typealias TermMode = ContractTermMode

    let context: ContractFormContext
    /// Ausgangsvertrag (bestehend, Entwurf, Kopie); Felder ausserhalb des Formulars bleiben unverändert
    let base: Contract
    /// Vertrag existiert schon (bearbeiten; Web `editId`)
    let isExisting: Bool
    let title: String
    /// Stichtag beim Öffnen (für Probeabo-Chips ohne Vertragsbeginn)
    let today0: Day

    // Kopf
    var label: String
    var partnerName: String

    // Kosten
    var amountText: String
    var currency: Currency
    var cycle: Int
    var due: Day
    var prices: [PriceChange]
    var payMethod: String
    var payAccount: String

    // Sonderzahlungen
    var extras: [ExtraPayment]

    // Laufzeit & Kündigung
    var termMode: TermMode
    /// Kachel «Nicht kündbar» durch die Kategorie «Steuern & Gebühren» erzwungen (Web `draft.taxForced`)
    var taxForced = false
    var start: Day?
    var end: Day?
    /// Mindestlaufzeit in Monaten (Web #fTermM); gespeichert wird nur das Vertragsende
    var termMonths: Int?
    var noticeText: String
    var noticeUnit: NoticeUnit
    var cancelTerm: CancelTerm
    var renewMonths: Int
    var trial: Day?
    /// Gewählter Chip der Probeabo-Dauer (Web `trialD`): "", 7d, 14d, 1m, 3m, date
    var trialChoice = ""
    /// «Nur Anbieter wechseln» (`mand`) und «An Frist erinnern» (= nicht `noWatch`)
    var mandatory: Bool
    var noWatch: Bool
    var isRent: Bool?
    var cancelChannel: CancelChannel?
    var cancelURL: String
    /// Gekündigte Verträge: «Gekündigt am» / «Läuft bis» korrigierbar (Web v145, nur beim Bearbeiten)
    let showsCancelDates: Bool
    var cancelledOn: Day?
    var cancelPer: Day?

    // Zuordnung
    var categoryID: UUID?
    var holderIDs: [UUID]
    /// Individuelle Aufteilung (leer = gleich; Web `draft.split`)
    var split: [SplitShare]
    var customerNo: String
    var contractNo: String

    // Kontakt und Notiz
    var address: PostalAddress
    /// Adressfelder aufgeklappt (Web `fAddrShow`): leer nur Zeile «hinzufügen»
    var addressShown: Bool
    var web: String
    var tel: String
    var mail: String
    var note: String
    var documents: [Attachment]

    // Logo und Farbe
    var colorHex: String?
    var logoID: String?
    var logoBg: String?
    /// Logo in diesem Formular gewählt oder entfernt
    var logoTouched = false

    // Bedienung (nicht Teil des Vertrags)
    /// Drehrad Kündigungsfrist offen (Web `noticeOpen`) und vorläufige Wahl (Web `nPend`)
    var noticeOpen = false
    var noticePendN = 1
    var noticePendU: NoticeUnit = .months
    /// Drehrad Mindestlaufzeit offen (Web `tmOpen`) und vorläufige Wahl (Web `tmPend`)
    var termMonthsOpen = false
    var termMonthsPend = 24
    /// Tagesraster «Zahlung am» offen (Web `dueOpen`); Zahlung am von Hand gewählt (Web `draft.dueSet`)
    var dueOpen = false
    var dueSet = false
    /// «Ende Periode» automatisch vorgeschlagen (Web `draft.autoP`)
    var autoP = false
    /// Unterbereiche «+ Preisänderung» / «+ Sonderzahlung» offen (Web `openSub`); angetippte Preisänderung (Web `pBak`)
    var priceOpen = false
    var priceBackup: PriceChange?
    var extraOpen = false
    /// Sprung zu einem Feld (Web `formGo`), wird von der Seite ausgeführt und zurückgesetzt
    var goTo: ContractFormField?

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
    /// Vorschläge unter dem Kopf erst nach einer Eingabe (Web: `openForm` leert #fSugg, `paintSugg` erst bei «input»)
    var sugActive = false

    // Vorschläge unter dem Vertragspartner (Web #pSug): eigene Vertragspartner und Internet
    var sugVisible = false
    var webHits: [WebPartnerHit] = []
    var webLoading = false
    @ObservationIgnored var searchToken = 0
    @ObservationIgnored var searchTask: Task<Void, Never>?

    // Eingaben in den Unterbereichen
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
    /// Panel «Dokumente» (Knopf rechts im Kopf)
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
        var editing = false
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
            editing = true
        case .duplicate(let id):
            c = data.duplicateDraft(id) ?? Contract()
            title = "Duplizieren"
        case .newProvider(let draft):
            c = draft
            title = CancelResult.replacementFormTitle
        case .bankSuggestion(let b):
            // Bereich import: Vorschlag aus dem Kontoauszug (Web `openForm(c, false, "Vorschlag")`)
            c = b.contract
            title = "Vorschlag"
        }
        base = c
        let existing = data.contract(c.id) != nil
        isExisting = existing
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
        termMode = ContractTermMode(contract: c, today: today)
        start = c.start
        end = c.end
        termMonths = ContractFormRules.termMonths(start: c.start, end: c.end)
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
        // Gekündigt (nicht bei Kopie/Entwurf): Daten der Kündigung korrigierbar
        let fixCancel = editing && existing && c.cancelPer != nil
        showsCancelDates = fixCancel
        cancelledOn = fixCancel ? c.cancelledOn : nil
        cancelPer = fixCancel ? c.cancelPer : nil
        customerNo = c.customerNo
        contractNo = c.contractNo
        payMethod = c.payMethod
        payAccount = c.payAccount
        web = partner?.web ?? ""
        tel = c.tel
        mail = c.mail
        note = c.note
        address = partner?.address ?? PostalAddress()
        addressShown = !(partner?.address ?? PostalAddress()).isEmpty
        documents = c.documents
        colorHex = c.colorHex
        logoID = c.logoID
        logoBg = c.logoBg
        if case .bankSuggestion(let b) = context {
            // Bereich import: Vertragspartner gibt es evtl. noch nicht – Name, Website, Adresse aus dem Vorschlag
            partnerName = b.partnerName
            web = b.web
            address = b.address
            addressShown = !b.address.isEmpty
        }
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
                       cancelledOn: cancelledOn, cancelPer: cancelPer,
                       customerNo: customerNo, contractNo: contractNo, payMethod: payMethod, payAccount: payAccount,
                       web: web, tel: tel, mail: mail, note: note, address: address, documents: documents,
                       colorHex: colorHex, logoID: logoID, logoBg: logoBg, logoTouched: logoTouched)
    }

    /// Eingetippt, aber noch nicht «hinzufügen» gedrückt (Preisänderung, Sonderzahlung)
    var hasPendingInputs: Bool {
        priceFrom != nil || !priceAmountText.ctTrimmed.isEmpty || extraDate != nil || !extraAmountText.ctTrimmed.isEmpty
            || !extraNote.ctTrimmed.isEmpty
    }

    /// Wurde etwas geändert (auch angefangene Eingaben in den Unterbereichen)? (Web `formDirty`)
    var isDirty: Bool {
        snapshot() != initialSnapshot || hasPendingInputs
    }

    // MARK: Vertragspartner

    /// Eingabe im Feld Vertragspartner (nur Tippen, nicht programmatisch)
    func userTypedPartner(_ v: String) {
        // SwiftUI setzt den Wert beim Schliessen der Tastatur erneut: nur echte Änderungen zählen (sonst verschwindet die Katalog-Karte)
        guard v != partnerName else { return }
        partnerName = v
        sugActive = true
        if !pSugSel.isEmpty && v.ctTrimmed != pSugSel { pSugSel = "" }
        tplHint = ""
        stdTpl = nil
    }

    /// Vertragspartner fertig eingegeben (Web `fPartner` «change», v156): neuer Vertrag ohne Betrag übernimmt die Währung
    /// eines bekannten Vertragspartners (alle eigenen Verträge in derselben Währung).
    func partnerCommitted(data: AppData) {
        guard !isExisting, amountText.ctTrimmed.isEmpty else { return }
        if let cur = data.knownPartnerCurrency(name: partnerName), cur != currency { currency = cur }
    }

    /// Eigenen Vertragspartner übernehmen (pickOwnPartner): nur leere Felder füllen
    func pickOwn(_ g: Partners.Group, data: AppData) {
        partnerName = g.partner.name
        pSugSel = g.partner.name
        sugActive = true
        if web.ctTrimmed.isEmpty && !g.partner.web.isEmpty { web = g.partner.web }
        if address.isEmpty && !g.partner.address.isEmpty { address = g.partner.address }
        if let c0 = data.contract(g.contractIDs.first) {
            if !categoryValid(data), let cid = c0.categoryID, data.category(cid) != nil {
                categoryID = cid
                categoryChanged(data)
            }
            if tel.ctTrimmed.isEmpty && !c0.tel.isEmpty { tel = c0.tel }
            if mail.ctTrimmed.isEmpty && !c0.mail.isEmpty { mail = c0.mail }
        }
        partnerCommitted(data: data)
    }

    /// Internet-Treffer übernehmen (pickWebPartner, ohne Logo): nur leere Felder füllen. Rückgabe: übernommene Angaben für den Toast.
    func pickWeb(_ w: WebPartnerHit, data: AppData) -> [String] {
        partnerName = w.name
        pSugSel = w.name
        tplHint = ""
        sugActive = true
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
            categoryChanged(data)
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
        sugActive = true
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
        noticeOpen = false
        if termMode != .fixed && (!onlyEmpty || cancelTerm == .anytime) { cancelTerm = t.cancelTerm }
        if let ch = t.cancelChannel, !onlyEmpty || cancelChannel == nil { cancelChannel = ch }
        if !t.web.isEmpty && web.ctTrimmed.isEmpty { web = t.web }
        // Kündigungslink aus dem Katalog nur, wenn noch keiner eingetragen ist (Web `applyTpl`)
        if !t.cancelURL.isEmpty && cancelURL.ctTrimmed.isEmpty { cancelURL = t.cancelURL }
        if !t.tel.isEmpty && tel.ctTrimmed.isEmpty { tel = t.tel }
        if !t.mail.isEmpty && mail.ctTrimmed.isEmpty { mail = t.mail }
        // Kontaktdaten aus dem Katalog nur in leere Felder (Web b520636)
        if !t.address.isEmpty && address.isEmpty { address = WebImport.addrSplit(t.address, partnerName: partnerName) }
        // Katalog «Steuern & Gebühren» (Rundfunkgebühr): nicht kündbar statt «Nur Anbieter wechseln»
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
            let w: [CancelChannel: String] = [.online: "online", .email: "per E-Mail", .letter: "per Brief"]
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

    /// Optionstext «Kündbar per» (Web #fTermP)
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
        noticeOpen = false
        // Reihenfolge wie Web: zuerst Kategorie (paintCats), dann die Art des Vertrags
        categoryChanged(data)
        if cur.termMode == a.termMode { setTermMode(o.termMode) }
        if cur.end == a.end {
            end = o.end
            termMonths = ContractFormRules.termMonths(start: start, end: end)
        }
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
        if !sugActive { return .none }
        let pn = partnerName.ctTrimmed
        if let st = stdTpl, st.name == pn {
            return .hint(st.hintFull, standardChip: !stdDone && (st.notice > 0 || st.cancelTerm != .anytime || st.mandatory))
        }
        let cur = Catalog.find(pn, currency: currency)
        if let c = cur, tplHint == c.name, showsTplSummary { return .summary(c, items: tplSum ?? []) }
        if let c = cur { return tplHint == c.name ? .hint(c.hintFull, standardChip: false) : .exact(c) }
        let q = (pn.isEmpty ? label : pn).ctTrimmed.lowercased()
        if q.count < 2 { return .none }
        let hits = Catalog.suggestions(q, currency: currency)
        return hits.isEmpty ? .none : .chips(hits)
    }

    /// «Übliche Frist übernehmen»: wie Web nur leere Felder füllen (bewusst gewählte Werte bleiben)
    func applyStandard(data: AppData) {
        guard let st = stdTpl else { return }
        applyTemplate(st, keepName: true, onlyEmpty: true, data: data)
        stdTpl = st
        stdDone = true
    }

    // MARK: Personen

    func toggleHolder(_ id: UUID, persons: [Person]) {
        var set = Set(holderIDs)
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        holderIDs = persons.map { $0.id }.filter { set.contains($0) }
        syncSplit()
    }

    // MARK: Aufteilung (Web paintSplit)

    var splitIndividual: Bool { !split.isEmpty && holderIDs.count >= 2 }

    /// Unter 2 Personen keine Aufteilung; fehlt eine Person in der Aufteilung, wieder gleichmässig vorbelegen.
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

    /// Betrag setzen (Web v82–v84): 2 Personen → die andere Person bekommt den Rest; ab 3 zuerst vom letzten (Rest) nehmen,
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

    // MARK: Adresse

    /// Adressfelder sichtbar (aufgeklappt oder schon mit Inhalt)
    var addressVisible: Bool { addressShown || !address.isEmpty }

    /// «hinzufügen» bzw. «Erfassen» beim Brief: Felder aufklappen und hinspringen (Web `fAddrShow(true)` + Fokus)
    func showAddress() {
        addressShown = true
        goTo = .address
    }

    /// Adresse aus der Zwischenablage auf die Felder verteilen (Web «Einfügen», v86). false = nichts Brauchbares.
    @discardableResult
    func pasteAddress(_ text: String) -> Bool {
        guard let a = WebImport.addrFromPaste(text, partnerName: partnerName), !a.isEmpty else { return false }
        address = a
        addressShown = true
        return true
    }

    /// Adresse des Vertragspartners in einer Zeile (Strasse, PLZ Ort); leer = noch keine
    var addressLine: String {
        let t = { (x: String) in x.ctTrimmed }
        let zc = [t(address.zip), t(address.city)].filter { !$0.isEmpty }.joined(separator: " ")
        return [t(address.street), zc].filter { !$0.isEmpty }.joined(separator: ", ")
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

    /// Kacheln «pro Monat | pro Jahr» (Web `paintKz`, aus `draftPC`): nil ohne Betrag und ohne Preisänderung
    func keyTiles(calc: Calc) -> (month: String, year: String)? {
        let amt = CTNumber.parse(amountText) ?? 0
        if !(amt > 0) && prices.isEmpty { return nil }
        var tmp = Contract()
        tmp.amount = amt
        tmp.currency = currency
        tmp.cycle = cycle
        tmp.start = start
        tmp.prices = prices
        let mon = calc.curPrice(tmp) / Double(max(1, cycle))
        return (Format.money(mon, currency), Format.money0(mon * 12, currency))
    }

    /// Preisverlauf des Entwurfs (Web `priceChart(draftPC())`, ab 1 Preisänderung)
    func priceChart(calc: Calc) -> PriceChart? {
        calc.priceChart(amount: CTNumber.parse(amountText) ?? 0, prices: prices, start: start, currency: currency, income: false)
    }

    /// Beschriftung der Vertragsnummer (Web `contrLbl`): Rufnummer, Versichertennummer, Policennummer oder Vertragsnummer
    func contractNumberLabel(_ data: AppData) -> String {
        let cat = data.category(categoryID)
        return Letter.contractNumberLabel(label: label, partner: partnerName, categoryName: cat?.name ?? "", categoryKind: cat?.kind)
    }

    // MARK: Art des Vertrags (Web termSeg, setTermMode)

    /// Knopf der Vertragsart angetippt (Web `termSeg` click): beim Wechsel auf «Mindestlaufzeit» die leere Verlängerung mit
    /// 1 Monat vorbelegen (v156, sonst endete der Vertrag still).
    func pickTermMode(_ m: TermMode) {
        if m == .fixed && termMode != .fixed && renewMonths == 0 { renewMonths = ContractFormRules.defaultRenewOnFixed }
        setTermMode(m)
    }

    /// Art setzen (auch durch Kategorie oder Vorlage). Jede Art zeigt nur ihre Felder; «Nicht kündbar» = `noCancel`.
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

    /// Knopf nur wählbar, wenn die Kategorie nicht «Steuern & Gebühren» ist (dann nur «Nicht kündbar»)
    func termModeEnabled(_ m: TermMode, data: AppData) -> Bool {
        data.category(categoryID)?.kind != .taxes || m == .tax
    }

    // MARK: Vertragsbeginn, Vertragsende, Mindestlaufzeit (Web v145/v146/v149)

    /// Vertragsbeginn geändert (Web `fStart` change, gleiche Reihenfolge): Zahlung am ab Beginn, Mindestlaufzeit → Vertragsende
    /// (bzw. Monate aus dem Ende), Probeabo-Ende nach Dauer-Chip. Rückgabe: Toast (Mindestlaufzeit ohne Beginn).
    @discardableResult
    func setStart(_ d: Day?, today: Day) -> String? {
        start = d
        dueFromStart(today: today)
        var msg: String?
        if termMonths != nil && termMode == .fixed {
            msg = termEndFromMonths()
        } else {
            termMonths = ContractFormRules.termMonths(start: start, end: end)
        }
        if termMode == .trial && CTFormState.trialKeys.contains(trialChoice) {
            trial = trialFrom(trialChoice, today: today)
            trialDue()
        }
        return msg
    }

    /// Vertragsende geändert (Web `termMFromEnd`): Mindestlaufzeit zurückrechnen (oder keine)
    func setEnd(_ d: Day?) {
        end = d
        termMonths = ContractFormRules.termMonths(start: start, end: end)
    }

    /// Mindestlaufzeit nicht aus der Schnellwahl (Knopf «Andere …» zeigt den Wert)
    var termMonthsIsOther: Bool {
        guard let n = termMonths else { return false }
        return !ContractFormRules.termMonthsQuick.contains(n)
    }

    /// Vertragsende = Beginn + n Monate − 1 Tag (Web `termEndFromM`). Ohne Beginn: Toast-Text und Sprung zum Beginn.
    @discardableResult
    func termEndFromMonths() -> String? {
        guard let n = termMonths, n > 0, n <= 600 else { return nil }
        guard let s = start else {
            goTo = .start
            return ContractFormRules.missingStartText
        }
        end = ContractFormRules.termEnd(start: s, months: n)
        return nil
    }

    /// Schnellwahl 1/2/3 Jahre (Web `fTermMC`)
    @discardableResult
    func pickTermMonths(_ n: Int) -> String? {
        termMonthsOpen = false
        termMonths = n
        return termEndFromMonths()
    }

    /// «Andere …»: Drehrad auf- bzw. zuklappen (vorgewählt: bisheriger Wert, sonst 24)
    func toggleTermMonthsWheel() {
        termMonthsOpen.toggle()
        if termMonthsOpen { termMonthsPend = termMonths ?? 24 }
    }

    /// Werte des Drehrads «Mindestlaufzeit» (1 … Max); ein grösserer gespeicherter Wert kommt dazu (wie `noticeWheelValues`),
    /// damit Rad und Knopf «… übernehmen» denselben Wert zeigen.
    var termMonthsWheelValues: [Int] {
        var v = Array(1...ContractFormRules.termMonthsWheelMax)
        if let t = termMonths, t > ContractFormRules.termMonthsWheelMax { v.append(t) }
        return v
    }

    /// «… übernehmen» im Drehrad (Web `fTermMOk`)
    @discardableResult
    func applyTermMonthsWheel() -> String? {
        termMonths = termMonthsPend
        termMonthsOpen = false
        return termEndFromMonths()
    }

    // MARK: Kündigungsfrist (Web v149/v153/v156)

    /// Zahl der Frist (leer = 0 = keine)
    var noticeN: Int { Int(noticeText.ctTrimmed) ?? 0 }

    /// Frist nicht aus der Schnellwahl 1/2/3 Monate (Knopf «Andere …» zeigt den Wert, Web `noticeOther`)
    var noticeIsOther: Bool {
        guard !noticeText.ctTrimmed.isEmpty else { return false }
        return !(noticeUnit == .months && ContractFormRules.noticeQuick.contains(noticeN))
    }

    /// Schnellwahl 1/2/3 Monate (Web `fNoticeC`, v156: nochmals tippen löst nicht mehr)
    func pickNotice(_ n: Int) {
        noticeOpen = false
        noticeText = "\(n)"
        noticeUnit = .months
    }

    /// «Andere …»: Drehrad auf- bzw. zuklappen (Web `nPend`: bisheriger Wert, ohne Frist 1)
    func toggleNoticeWheel() {
        noticeOpen.toggle()
        if noticeOpen {
            noticePendN = noticeN > 0 ? noticeN : 1
            noticePendU = noticeUnit
            noticePendN = ContractFormRules.clampNotice(noticePendN, noticePendU)
        }
    }

    /// Drehrad bewegt: Zahl bzw. Einheit; «. im Monat» höchstens 28 (Web v153)
    func setNoticePending(n: Int? = nil, unit: NoticeUnit? = nil) {
        if let u = unit { noticePendU = u }
        if let x = n { noticePendN = x }
        noticePendN = ContractFormRules.clampNotice(noticePendN, noticePendU)
    }

    /// Werte der Zahlenspalte: 0 («keine») bis 90, dazu ein grösserer bisheriger Wert (Web `fNoticeWh`)
    var noticeWheelValues: [Int] {
        var v = Array(0...ContractFormRules.noticeWheelMax)
        if noticeN > ContractFormRules.noticeWheelMax { v.append(noticeN) }
        return v
    }

    /// «… übernehmen» (Web `fNoticeOk`): 0 = keine Frist
    func applyNoticeWheel() {
        noticeOpen = false
        if noticePendN == 0 {
            noticeText = ""
            noticeUnit = .months
        } else {
            noticeText = "\(noticePendN)"
            noticeUnit = noticePendU
        }
    }

    // MARK: Probeabo-Dauer (Web trialFrom, paintTrialD, trialDue)

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

    /// Chip «7 Tage» … «Datum …» gewählt; erste Zahlung = erster kostenpflichtiger Tag
    func pickTrial(_ k: String, today: Day) {
        trialChoice = k
        if k != "date" { trial = trialFrom(k, today: today) }
        trialDue()
    }

    /// Datum «Probeabo endet am» geändert
    func setTrial(_ d: Day?) {
        trial = d
        trialDue()
    }

    /// Probeabo: «Zahlung am» = erster kostenpflichtiger Tag (Web `trialDue`, v156)
    func trialDue() {
        guard termMode == .trial, let v = ContractFormRules.trialDue(trial: trial) else { return }
        due = v
    }

    // MARK: Zahlung am (Web v151/v156/v159)

    /// Neuer Vertrag, «Zahlung am» nicht selbst gewählt: bei Rhythmus ≥ 2 Monate ab Vertragsbeginn (Web `dueFromStart`).
    /// Nicht beim Bearbeiten, nicht nach eigener Wahl, nicht im Probeabo.
    func dueFromStart(today: Day) {
        if isExisting || dueSet || termMode == .trial { return }
        if let x = ContractFormRules.dueFromStart(start: start, cycle: cycle, today: today) { due = x }
    }

    /// Text der Zeile «Zahlung am» (Web `dueTxt`)
    var dueText: String { ContractFormRules.dueText(due, cycle: cycle) }

    /// Tag im Raster angetippt: übernehmen und zuklappen
    func pickDueDay(_ d: Int, today: Day) {
        due = ContractFormRules.dueFrom(day: d, month: due.month, cycle: cycle, today: today)
        dueSet = true
        dueOpen = false
    }

    /// Monat im Raster angetippt: übernehmen, Raster bleibt offen
    func pickDueMonth(_ m: Int, today: Day) {
        due = ContractFormRules.dueFrom(day: due.day, month: m, cycle: cycle, today: today)
        dueSet = true
    }

    /// Zahlungsrhythmus geändert (Web `fCycle` change): Raster zu, Zahlung am ab Beginn; in «Flexibel»/«Probeabo» ohne
    /// «Kündbar per» ab halbjährlich «Ende Periode» vorschlagen, beim Zurückstellen wieder entfernen (`autoP`, v153).
    /// Rückgabe: Toast.
    @discardableResult
    func setCycle(_ v: Int, today: Day) -> String? {
        cycle = v
        dueOpen = false
        dueFromStart(today: today)
        if (termMode == .open || termMode == .trial) && cancelTerm == .anytime && v >= 6 {
            cancelTerm = .period
            autoP = true
            return "Kündbar per «Ende Periode» vorgeschlagen"
        }
        if autoP && cancelTerm == .period && v < 6 {
            cancelTerm = .anytime
            autoP = false
        }
        return nil
    }

    /// Live-Hinweis unter «Kosten» (Web updPayHint): «Zahlung monatlich am 15. · nächste am 15.10.26»
    func payHint(calc: Calc) -> String {
        let r = Calc.payRule(cycle: cycle, due: due)
        if r.isEmpty { return "" }
        var tmp = Contract()
        tmp.amount = 1
        tmp.cycle = cycle
        tmp.due = due
        tmp.start = start
        let n = calc.nextDue(tmp)
        return "Zahlung " + r + (n.map { " · nächste am " + Format.fmtShort($0) } ?? "")
    }

    /// Laufzeit-Hinweis (Kern `ContractFormRules.termHint`, Web `updTermHint` v160)
    func termHint(calc: Calc) -> String {
        ContractFormRules.termHint(TermHintInput(mode: termMode, cycle: cycle, due: due, start: start, end: end, renewMonths: renewMonths,
                                                 notice: noticeN, noticeUnit: noticeUnit, cancelTerm: cancelTerm, trial: trial,
                                                 currency: currency), calc: calc)
    }

    /// «An Frist erinnern» sichtbar (Web `syncRemind`)
    var showsRemindToggle: Bool {
        ContractFormRules.showsRemindToggle(mode: termMode, cancelTerm: cancelTerm, cycle: cycle)
    }

    // MARK: Kündigungsweg (Web fCancT/syncCancUrl)

    /// Knopf antippen; nochmals tippen hebt die Wahl auf
    func toggleCancelChannel(_ ch: CancelChannel) {
        cancelChannel = cancelChannel == ch ? nil : ch
    }

    // MARK: Preisänderungen und Sonderzahlungen

    /// Ergebnis von «Preisänderung hinzufügen»
    enum PriceAddResult {
        /// Meldung (lang = 4 s); `added` = vorgemerkt
        case toast(String, long: Bool, added: Bool)
        /// Preis bleibt gleich: nicht blockierend nachfragen («Trotzdem hinzufügen»)
        case confirmSame(title: String, message: String)
    }

    /// «+ Preisänderung»
    func openPriceForm() {
        priceOpen = true
    }

    /// «Abbrechen» im Unterbereich: angetippte Preisänderung zurücklegen (Web `pCancel`)
    func cancelPriceForm() {
        if let b = priceBackup {
            prices.append(b)
            priceBackup = nil
        }
        priceFrom = nil
        priceAmountText = ""
        priceOpen = false
    }

    /// Zeile der Preisliste angetippt: zum Ändern in den Unterbereich laden (Web `data-pedit`). Rückgabe: Toast.
    func editPrice(_ p: PriceChange) -> String {
        // eine schon geladene Zeile nicht verlieren
        if let b = priceBackup { prices.append(b) }
        prices.removeAll { $0.from == p.from }
        priceBackup = p
        priceFrom = p.from
        priceAmountText = CTNumber.field(p.amount, currency)
        priceOpen = true
        return "Ändern und «hinzufügen» tippen"
    }

    /// Preisänderung vormerken (Web pAdd). `force`: Rückfrage «Preis bleibt gleich» wurde bestätigt.
    func addPrice(force: Bool = false) -> PriceAddResult {
        guard let f = priceFrom else { return .toast("Datum für die Preisänderung fehlt", long: false, added: false) }
        if let s0 = start, f <= s0 { return .toast("Datum muss nach dem Vertragsbeginn liegen", long: false, added: false) }
        guard let a = CTNumber.parse(priceAmountText), a >= 0 else { return .toast("Neuen Betrag prüfen", long: false, added: false) }
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
        priceBackup = nil
        priceOpen = false
        var prevA = CTNumber.parse(amountText) ?? 0
        for p in sortedPrices where p.from < f { prevA = p.amount }
        if a > prevA && prevA > 0 { return .toast("Preiserhöhung vorgemerkt. Tipp: oft gilt ein Sonderkündigungsrecht.", long: true, added: true) }
        return .toast("Preisänderung ab " + Format.fmtD(f) + " vorgemerkt", long: false, added: true)
    }

    func removePrice(_ from: Day) {
        prices.removeAll { $0.from == from }
    }

    var sortedPrices: [PriceChange] {
        prices.filter { $0.amount.isFinite }.ctStableSorted { $0.from < $1.from }
    }

    /// Sonderzahlung vormerken (Web xAdd); Rückgabe = Toast
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
        extraOpen = false
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
        // Nicht kündbar: keine Frist (Web v153)
        c.notice = termMode == .tax ? 0 : (notice ?? noticeN)
        c.noticeUnit = noticeUnit
        c.renewMonths = termMode == .fixed ? renewMonths : 0
        c.cancelTerm = (termMode == .open || termMode == .trial) ? cancelTerm : .anytime
        c.mandatory = mandatory
        // Probeabo immer beobachtet (Web v153)
        c.noWatch = ContractFormRules.noWatchOnSave(mode: termMode, toggleNoWatch: noWatch)
        c.noCancel = termMode == .tax
        c.isRent = isRent
        c.cancelChannel = cancelChannel
        // Link nur löschen, wenn bewusst ein anderer Weg gewählt ist (E-Mail, Brief; Web saveForm)
        let otherWay: Set<CancelChannel> = [.email, .letter]
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

    /// Eingetippte Preisänderung bzw. Sonderzahlung beim Sichern übernehmen (Web v143). false = Sichern abbrechen
    /// (Fehler oder Rückfrage «Preis bleibt gleich»; der Unterbereich bleibt offen).
    private func commitPendingInputs(model: AppModel) -> Bool {
        if priceFrom != nil || !priceAmountText.ctTrimmed.isEmpty {
            switch addPrice() {
            case .toast(let t, let long, let added):
                model.toast(t, seconds: long ? 4 : 2.4)
                if !added {
                    priceOpen = true
                    goTo = .prices
                    return false
                }
            case .confirmSame(let title, let message):
                priceOpen = true
                goTo = .prices
                let f = self
                model.ask(title: title, message: message, ok: "Trotzdem hinzufügen") {
                    if case .toast(let t, let long, _) = f.addPrice(force: true) { model.toast(t, seconds: long ? 4 : 2.4) }
                }
                return false
            }
        }
        if extraDate != nil || !extraAmountText.ctTrimmed.isEmpty {
            let t = addExtra()
            model.toast(t)
            if extraDate != nil || !extraAmountText.ctTrimmed.isEmpty {
                extraOpen = true
                goTo = .extras
                return false
            }
        }
        return true
    }

    /// Prüfen und sichern (Web saveForm, Reihenfolge wie dort). Gibt true zurück, wenn gesichert wurde.
    func save(model: AppModel) -> Bool {
        let data = model.data
        if !commitPendingInputs(model: model) { return false }
        let pname = Format.collapseSpaces(partnerName)
        if pname.isEmpty && label.ctTrimmed.isEmpty {
            model.toast("Bezeichnung fehlt")
            goTo = .label
            return false
        }
        guard let cid = categoryID, data.category(cid) != nil else {
            model.toast("Bitte eine Kategorie wählen")
            goTo = .category
            showCategoryPicker = true
            return false
        }
        guard let amt = CTNumber.parse(amountText), amt >= 0 else {
            model.toast("Betrag prüfen")
            goTo = .amount
            return false
        }
        guard let notice = CTNumber.noticeValue(noticeText, unit: noticeUnit) else {
            model.toast("Kündigungsfrist prüfen")
            goTo = .notice
            return false
        }
        if termMode == .fixed && end == nil {
            model.toast(ContractFormRules.missingEndText)
            goTo = .end
            return false
        }
        if termMode == .trial && trial == nil {
            model.toast(ContractFormRules.missingTrialText)
            goTo = .trial
            return false
        }
        if showsCancelDates, let err = ContractFormRules.checkCancellation(per: cancelPer, on: cancelledOn) {
            model.toast(err)
            goTo = cancelPer == nil ? .cancelPer : .cancelOn
            return false
        }
        var c = makeContract(amount: amt, notice: notice)
        c.categoryID = cid
        let today = model.today
        let webT = web.ctTrimmed
        let t = { (x: String) in Format.collapseSpaces(x) }
        let addr = PostalAddress(company: t(address.company), extra: t(address.extra), street: t(address.street),
                                 zip: t(address.zip), city: t(address.city), country: t(address.country))
        if case .bankSuggestion(var b) = context {
            // Bereich import: zurück in den Vorschlag statt sichern (Web `bkFormDone`)
            c.id = b.contract.id
            b.contract = c
            b.partnerName = pname
            b.web = webT
            b.address = addr
            b.logoID = logoID
            b.logoBg = logoBg
            BankFormBridge.shared.contractDone(b)
            return true
        }
        let touched = logoTouched
        let lid = logoID
        let lbg = logoBg
        let iPID = initialPartnerID
        let iWeb = initialWeb.ctTrimmed
        let iAddr = PostalAddress(company: t(initialAddress.company), extra: t(initialAddress.extra), street: t(initialAddress.street),
                                  zip: t(initialAddress.zip), city: t(initialAddress.city), country: t(initialAddress.country))
        let fixCancel = showsCancelDates
        let cPer = cancelPer
        let cOn = cancelledOn
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
            let id = try d.saveContract(c, today: today)
            // Gekündigt: «Gekündigt am» / «Läuft bis» übernehmen (Web v145; oben geprüft)
            if fixCancel { d.correctCancellation(id, per: cPer, on: cOn) }
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
    var cancelledOn: Day?
    var cancelPer: Day?
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
