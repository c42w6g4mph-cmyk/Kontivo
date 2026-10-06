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
    enum Watch: Hashable { case yes, mandatory, noWatch }

    let context: ContractFormContext
    /// Ausgangsvertrag (bestehend, Entwurf, Kopie); Felder ausserhalb des Formulars bleiben unverändert
    let base: Contract
    /// Vertrag existiert schon (bearbeiten)
    let isExisting: Bool
    let title: String

    // Hauptseite
    var label: String
    var partnerName: String
    var categoryID: UUID?
    var holderIDs: [UUID]
    var amountText: String
    var currency: Currency
    var cycle: Int
    var due: Day
    var termFixed: Bool
    var start: Day?
    var end: Day?
    var noticeText: String
    var noticeUnit: NoticeUnit
    var cancelTerm: CancelTerm
    var renewMonths: Int

    // Weitere Angaben
    var prices: [PriceChange]
    var extras: [ExtraPayment]
    var watch: Watch
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

    // Vorlagen und Vorschläge
    /// Name der übernommenen Katalog-Vorlage
    var tplHint = ""
    /// Vorschlag «übliche Frist» aus dem Internet-Treffer
    var stdTpl: CatalogEntry?
    var stdDone = false
    /// Zuletzt gewählter Vorschlag (Liste ausblenden, solange der Text gleich ist)
    var pSugSel = ""

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
            title = "Vertrag bearbeiten"
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
        amountText = blankAmount ? "" : CTNumber.field(c.amount)
        currency = useHomeCurrency ? data.settings.homeCurrency : c.currency
        cycle = c.cycle == 0 ? 1 : c.cycle
        due = c.due ?? today
        termFixed = c.end != nil || c.renewMonths != 0
        start = c.start
        end = c.end
        noticeText = c.notice > 0 ? "\(c.notice)" : ""
        noticeUnit = c.noticeUnit
        cancelTerm = c.cancelTerm
        renewMonths = c.renewMonths
        prices = c.prices
        extras = c.extras.filter { $0.amount.isFinite && $0.amount != 0 }.ctStableSorted { $0.date < $1.date }
        watch = c.mandatory ? .mandatory : (c.noWatch ? .noWatch : .yes)
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
        initialSnapshot = snapshot()
    }

    // MARK: Änderungen erkennen

    func snapshot() -> CTFormSnapshot {
        CTFormSnapshot(label: label, partnerName: partnerName, categoryID: categoryID, holderIDs: holderIDs, amountText: amountText,
                       currency: currency, cycle: cycle, due: due, termFixed: termFixed, start: start, end: end, noticeText: noticeText,
                       noticeUnit: noticeUnit, cancelTerm: cancelTerm, renewMonths: renewMonths, prices: prices, extras: extras,
                       watch: watch, isRent: isRent, cancelChannel: cancelChannel, trial: trial, cancelURL: cancelURL,
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

    /// Vorlage übernehmen (applyTpl). `onlyEmpty`: nur leere Felder füllen (Internet-Vorschlag, Fix N4).
    func applyTemplate(_ t: CatalogEntry, keepName: Bool, onlyEmpty: Bool, data: AppData) {
        if !keepName {
            partnerName = t.name
            pSugSel = t.name
        }
        if label.ctTrimmed.isEmpty { label = t.label }
        if !t.category.isEmpty, let cid = CTFormState.categoryID(for: t.category, data: data) {
            if !onlyEmpty || !categoryValid(data) { categoryID = cid }
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
        if !termFixed && (!onlyEmpty || cancelTerm == .anytime) { cancelTerm = t.cancelTerm }
        if let ch = t.cancelChannel, !onlyEmpty || cancelChannel == nil { cancelChannel = ch }
        if !t.web.isEmpty && web.ctTrimmed.isEmpty { web = t.web }
        // Kündigungslink aus dem Katalog nur, wenn noch keiner eingetragen ist (Web `applyTpl`)
        if !t.cancelURL.isEmpty && cancelURL.ctTrimmed.isEmpty { cancelURL = t.cancelURL }
        if onlyEmpty {
            if t.mandatory && watch == .yes { watch = .mandatory }
        } else if t.mandatory {
            watch = .mandatory
        } else if watch == .mandatory {
            watch = .yes
        }
        if amountText.ctTrimmed.isEmpty, let cur = t.suggestedCurrency { currency = cur }
        tplHint = t.name
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
    }

    var suggest: Suggest {
        let pn = partnerName.ctTrimmed
        if let st = stdTpl, st.name == pn {
            return .hint(st.hint, standardChip: !stdDone && (st.notice > 0 || st.cancelTerm != .anytime || st.mandatory))
        }
        let cur = Catalog.find(pn)
        if let c = cur { return tplHint == c.name ? .hint(c.hint, standardChip: false) : .exact(c) }
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

    /// Hinweis zur Laufzeit (updTermHint)
    func termHint(_ data: AppData, today: Day) -> String {
        let calc = Calc(data: data, today: today)
        var tmp = Contract()
        tmp.amount = 1
        tmp.cycle = cycle
        tmp.due = due
        tmp.start = start
        tmp.notice = CTNumber.int(noticeText, unit: noticeUnit)
        tmp.noticeUnit = noticeUnit
        if termFixed {
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
            return "Unbefristet — du kannst mit der angegebenen Frist jederzeit kündigen."
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

    /// Turnus geändert: im Modus «Jederzeit kündbar» ohne «Kündbar per» ab halbjährlich «Ende Periode» vorschlagen
    func cycleChanged() -> String? {
        if !termFixed && cancelTerm == .anytime && cycle >= 6 {
            cancelTerm = .period
            return "Kündbar per «Ende Periode» vorgeschlagen"
        }
        return nil
    }

    /// Zusammenfassung der Zeile «Weitere Angaben» (paintOptCounts); nil = Platzhaltertext
    var moreSummary: String? {
        func n(_ k: Int, _ one: String, _ many: String) -> String { k > 0 ? "\(k) " + (k == 1 ? one : many) : "" }
        let parts = [
            n(prices.count, "Preisänderung", "Preisänderungen"),
            n(extras.count, "Sonderzahlung", "Sonderzahlungen"),
            watch == .mandatory ? "Pflichtvertrag" : (watch == .noWatch ? "nicht in Fristen" : ""),
            cancelChannel != nil ? "Kündigungsweg" : "",
            (cancelChannel != .online || cancelURL.ctTrimmed.isEmpty) ? "" : "Kündigungslink",
            trial != nil ? "Probeabo" : "",
            customerNo.ctTrimmed.isEmpty ? "" : "Kundennummer",
            contractNo.ctTrimmed.isEmpty ? "" : "Vertragsnummer",
            payMethod.isEmpty ? "" : "Zahlungsart",
            payAccount.ctTrimmed.isEmpty ? "" : "Belastet über",
            address.isEmpty ? "" : "Adresse",
            web.ctTrimmed.isEmpty ? "" : "Website",
            tel.ctTrimmed.isEmpty ? "" : "Telefon",
            mail.ctTrimmed.isEmpty ? "" : "E-Mail",
            note.ctTrimmed.isEmpty ? "" : "Notiz",
            n(documents.count, "Datei", "Dateien"),
        ].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Preisänderungen und Sonderzahlungen

    /// Preisänderung vormerken; Rückgabe = Toast
    func addPrice() -> String {
        guard let f = priceFrom else { return "Datum für die Preisänderung fehlt" }
        guard let a = CTNumber.parse(priceAmountText), a >= 0 else { return "Neuen Betrag prüfen" }
        prices.removeAll { $0.from == f }
        prices.append(PriceChange(from: f, amount: Format.round2(a)))
        priceFrom = nil
        priceAmountText = ""
        return "Preisänderung ab " + Format.fmtD(f) + " vorgemerkt"
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
        c.amount = amount
        c.currency = currency
        c.cycle = cycle
        c.due = due
        c.start = start
        c.end = termFixed ? end : nil
        c.notice = notice ?? CTNumber.int(noticeText, unit: noticeUnit)
        c.noticeUnit = noticeUnit
        c.renewMonths = termFixed ? renewMonths : 0
        c.cancelTerm = termFixed ? .anytime : cancelTerm
        c.mandatory = watch == .mandatory
        c.noWatch = watch == .noWatch
        c.isRent = isRent
        c.cancelChannel = cancelChannel
        // Kündigungslink nur beim Weg «Online / Kundenkonto» (wie Web)
        c.cancelURL = cancelChannel == .online ? cancelURL.ctTrimmed : ""
        c.trial = trial
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
    var amountText: String
    var currency: Currency
    var cycle: Int
    var due: Day
    var termFixed: Bool
    var start: Day?
    var end: Day?
    var noticeText: String
    var noticeUnit: NoticeUnit
    var cancelTerm: CancelTerm
    var renewMonths: Int
    var prices: [PriceChange]
    var extras: [ExtraPayment]
    var watch: CTFormState.Watch
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
