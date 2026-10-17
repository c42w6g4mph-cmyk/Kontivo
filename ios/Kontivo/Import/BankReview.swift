import SwiftUI
import KontivoCore

/// Logo eines Vorschlags (Web `it.logo = {id, bg}`): Datei-ID im Dateispeicher und Kachelfarbe
struct BankLogo: Equatable {
    var id: String
    var bg: String
}

/// Zustand des Fensters «Kontoauszug» (Web `bk`, v177–v223): geführte Schritte Fixkosten → Einnahmen → Fristen.
/// `items` = neue Verträge, `prices` = neuer Preis bei erfassten Verträgen, `inc` = Einnahmen. Bearbeiten öffnet das normale
/// Vertrags- bzw. Einnahmenformular (Titel «Vorschlag», `BankFormBridge`); «Sichern» schreibt zurück in den Vorschlag (`over`).
@MainActor
@Observable
final class BankReview {
    enum Step: String { case fix, inc, term }

    /// Werte eines Vertragsvorschlags (Web `ed`)
    struct Edit: Equatable {
        var name: String
        var label: String
        var amount: Double
        var cycle: Int
        var categoryID: UUID?
        var holderIDs: [UUID]
        var due: Day
    }

    struct Item: Identifiable {
        var s: BankSuggestion
        var on: Bool
        var logo: BankLogo?
        /// Schnellwahl Kündigungsfrist (Schritt 3): "1", "3", "x" (nicht kündbar) oder "" (weiss nicht)
        var term: String = ""
        var ed: Edit
        /// Im Formular gesichert (Web `it.over`)
        var over: BankFormDraft?
        var id: String { s.id }
    }

    /// Werte eines Einnahmenvorschlags (Web `ed` der Einnahme)
    struct IncEdit: Equatable {
        var label: String
        var name: String
        var amount: Double
        var cycle: Int
        var kind: IncomeKind
        var holderIDs: [UUID]
        var due: Day
    }

    struct IncItem: Identifiable {
        var s: BankIncomeSuggestion
        var on: Bool
        var logo: BankLogo?
        var ed: IncEdit
        var over: Income?
        var id: String { s.key }
    }

    struct PriceRow: Identifiable {
        var m: BankPriceMatch
        var on: Bool
        var id: String { m.contractID.uuidString + "|" + m.from.iso }
    }

    let file: BankFile
    let result: BankFindResult
    let incResult: BankIncomeResult
    let label: String
    var items: [Item]
    var prices: [PriceRow]
    var inc: [IncItem]
    var step: Step = .fix
    var showIgnored = false
    var showKnown = false
    /// Kontoinhaber laut Auszug, Treffer einer Person, Gemeinschaftskonto (mehrere Personen im Namen)
    let owner: String
    let ownerHit: UUID?
    let joint: Bool
    /// Logosuche im Hintergrund (Web `logoRun`)
    var logoDone = 0
    var logoTotal = 0

    init(file: BankFile, result: BankFindResult, income: BankIncomeResult, label: String, data: AppData) {
        self.file = file
        self.result = result
        self.incResult = income
        self.label = label
        let home = data.settings.homeCurrency.rawValue
        let persons = data.persons
        // Vorbelegung: genau eine Person (zuletzt gewählte einzelne, sonst die erste); Kontoinhaber im Auszug gewinnt
        var H = BankReview.defaultHolders(data)
        let ow = BankImport.who(file.owner, persons: persons)
        if ow.count == 1 { H = ow }
        owner = file.owner
        ownerHit = ow.count == 1 ? ow[0] : nil
        joint = ow.count > 1
        items = result.items.map { s0 in
            var s = s0
            // unbekannte Währung → Hauptwährung (Web BK_CUR)
            if Currency(rawValue: s.currency) == nil { s.currency = home }
            let ed = Edit(name: s.name, label: BankImport.label(s), amount: s.amount, cycle: s.cycle,
                          categoryID: data.category(named: s.category)?.id, holderIDs: H, due: s.due)
            return Item(s: s, on: s.confidence != .low && !s.ignored, ed: ed)
        }
        prices = result.prices.map { PriceRow(m: $0, on: true) }
        inc = income.items.map { s in
            let w = BankImport.who(s.text + " " + s.raw, persons: persons)
            let ed = IncEdit(label: s.label, name: s.name, amount: s.amount, cycle: s.cycle, kind: s.kind,
                             holderIDs: w.count == 1 ? w : H, due: s.due)
            return IncItem(s: s, on: s.confidence == .high, ed: ed)
        }
        if fixCount == 0 && prices.isEmpty && !inc.isEmpty { step = .inc }
    }

    /// Web `bkHolders`: zuletzt gewählte einzelne Person, sonst die erste
    static func defaultHolders(_ d: AppData) -> [UUID] {
        let ids = Set(d.persons.map { $0.id })
        let lh = d.settings.lastHolderIDs.filter { ids.contains($0) }
        if lh.count == 1 { return lh }
        return d.persons.first.map { [$0.id] } ?? []
    }

    // MARK: Ablauf (Web bkFixCount, bkTermList, bkSteps)

    var fixCount: Int { items.filter { showIgnored || !$0.s.ignored }.count }

    func categoryName(_ it: Item, _ d: AppData) -> String {
        d.category(it.ed.categoryID)?.name ?? (d.otherCategory?.name ?? "Sonstiges")
    }

    /// Steuern & Gebühren: nicht kündbar, keine Frist nötig (Web `bkNoCancel`)
    func noCancel(_ it: Item, _ d: AppData) -> Bool {
        guard let tax = d.categories.first(where: { $0.kind == .taxes }) else { return false }
        return it.ed.categoryID == tax.id
    }

    /// Kündigungsregel bekannt: Katalog-Anbieter (auch «jederzeit»), nicht kündbar, oder im Formular erfasst (Web `bkHasTermBase`)
    func hasTermBase(_ it: Item, _ d: AppData) -> Bool {
        if let o = it.over { return BankReview.overTerm(o.contract) }
        return noCancel(it, d) || it.s.catalog != nil
    }

    func hasTerm(_ it: Item, _ d: AppData) -> Bool {
        hasTermBase(it, d) || it.term == "1" || it.term == "3" || it.term == "x"
    }

    /// Im Formular steht schon eine Kündigungsregel (Web `bkOverTerm`)
    static func overTerm(_ c: Contract) -> Bool { c.noCancel || c.notice > 0 || c.end != nil || c.mandatory }

    func termList(_ d: AppData) -> [Int] {
        items.indices.filter { i in
            let it = items[i]
            return it.on && !(it.s.ignored && !showIgnored) && !hasTermBase(it, d)
        }
    }

    func steps(_ d: AppData) -> [Step] {
        var l: [Step] = []
        if fixCount > 0 || !prices.isEmpty || inc.isEmpty { l.append(.fix) }
        if !inc.isEmpty { l.append(.inc) }
        if !termList(d).isEmpty { l.append(.term) }
        return l
    }

    /// Aktueller Schritt (fällt ein Schritt weg, gilt der erste)
    func currentStep(_ d: AppData) -> Step {
        let st = steps(d)
        return st.contains(step) ? step : (st.first ?? .fix)
    }

    func stepIndex(_ d: AppData) -> Int { steps(d).firstIndex(of: currentStep(d)) ?? 0 }
    func isLastStep(_ d: AppData) -> Bool { currentStep(d) == steps(d).last }

    /// «Weiter» (Web bkGo mode next)
    func next(_ d: AppData) {
        let st = steps(d)
        let i = st.firstIndex(of: currentStep(d)) ?? 0
        step = i + 1 < st.count ? st[i + 1] : (st.last ?? .fix)
    }

    /// «‹ Zurück» (Web bkBack): false = schon im ersten Schritt
    func back(_ d: AppData) -> Bool {
        let st = steps(d)
        let i = st.firstIndex(of: currentStep(d)) ?? 0
        if i > 0 {
            step = st[i - 1]
            return true
        }
        return false
    }

    // MARK: Zählen (Web bkCounts, bkFoot)

    var counts: (n: Int, p: Int, i: Int) {
        (items.filter { $0.on && (showIgnored || !$0.s.ignored) }.count, prices.filter { $0.on }.count, inc.filter { $0.on }.count)
    }

    func footerTitle(_ d: AppData) -> String {
        if !isLastStep(d) { return "Weiter" }
        let k = counts
        let all = k.n + k.p + k.i
        if all == 0 { return "Nichts ausgewählt" }
        return all == 1 ? "1 Eintrag übernehmen" : "\(all) Einträge übernehmen"
    }

    func footerEnabled(_ d: AppData) -> Bool {
        if !isLastStep(d) { return true }
        let k = counts
        return k.n + k.p + k.i > 0
    }

    // MARK: Texte (Web bkTitle, bkSub, bkPer, bkDay)

    func title(_ it: Item) -> String {
        let l = it.ed.label
        return !l.isEmpty && Partners.lnorm(l) != Partners.lnorm(it.ed.name) ? l : it.ed.name
    }

    /// Zweite Zeile: Vertragspartner (falls oben die Bezeichnung steht) · Beleg; Hinweis in Messing separat
    func sub(_ it: Item) -> (text: String, em: String?) {
        let s = it.s, e = it.ed
        var t: [String] = []
        if !e.label.isEmpty && Partners.lnorm(e.label) != Partners.lnorm(e.name) { t.append(e.name) }
        t.append(s.confidence == .low ? "einmal am " + Self.day(s.last) : "\(s.count)× im Auszug")
        var em: String? = nil
        if let ch = s.change, Swift.abs(e.amount - ch.amount) < 0.005 {
            em = "neuer Preis ab " + Self.day(ch.from)
        } else if s.varies {
            em = "Betrag schwankt"
        }
        return (t.joined(separator: " · "), em)
    }

    func incTitle(_ it: IncItem) -> String { it.ed.label.isEmpty ? it.ed.name : it.ed.label }

    func incSub(_ it: IncItem) -> (text: String, em: String?) {
        var t: [String] = []
        if !it.ed.label.isEmpty && Partners.lnorm(it.ed.label) != Partners.lnorm(it.ed.name) { t.append(it.ed.name) }
        t.append("\(it.s.count)× im Auszug")
        return (t.joined(separator: " · "), it.s.varies ? "Betrag schwankt" : nil)
    }

    static let periods: [Int: String] = [1: "pro Monat", 2: "alle 2 Monate", 3: "pro Quartal", 6: "pro Halbjahr", 12: "pro Jahr", 24: "alle 2 Jahre"]
    static func per(_ c: Int) -> String { periods[c] ?? "alle \(c) Monate" }

    /// «5.9.26» (Web `bkDay`)
    static func day(_ d: Day) -> String {
        "\(d.day).\(d.month)." + String(format: "%02d", d.year % 100)
    }

    // MARK: Ändern

    func index(_ id: String) -> Int? { items.firstIndex { $0.id == id } }
    func incIndex(_ id: String) -> Int? { inc.firstIndex { $0.id == id } }

    func toggle(_ id: String) {
        guard let i = index(id) else { return }
        items[i].on.toggle()
    }

    func setOn(_ id: String, _ on: Bool) {
        guard let i = index(id) else { return }
        items[i].on = on
    }

    func toggleInc(_ id: String) {
        guard let i = incIndex(id) else { return }
        inc[i].on.toggle()
    }

    func togglePrice(_ id: String) {
        guard let i = prices.firstIndex(where: { $0.id == id }) else { return }
        prices[i].on.toggle()
    }

    func setTerm(_ id: String, _ v: String) {
        guard let i = index(id) else { return }
        items[i].term = v
    }

    /// «Zuordnen an» für alle Einträge (Web `data-bkall`)
    func assignAll(_ p: UUID) {
        for i in items.indices { items[i].ed.holderIDs = [p] }
        for i in inc.indices { inc[i].ed.holderIDs = [p] }
    }

    /// Person, wenn alle Einträge genau dieselbe eine Person haben (Web `bkWhoBar` cur)
    var commonHolder: UUID? {
        let all = items.map { $0.ed.holderIDs } + inc.map { $0.ed.holderIDs }
        guard let f = all.first, f.count == 1 else { return nil }
        return all.allSatisfy { $0.count == 1 && $0[0] == f[0] } ? f[0] : nil
    }

    /// «Zuordnen an» zeigen: mindestens zwei Personen und etwas zum Zuordnen
    func showsWhoBar(_ d: AppData) -> Bool {
        d.persons.count >= 2 && items.filter({ !$0.s.ignored }).count + inc.count > 0
    }

    func whoReason(_ d: AppData) -> String {
        if ownerHit != nil { return "Kontoinhaber laut Auszug: " + owner }
        if joint { return "Gemeinschaftskonto – bitte je Eintrag prüfen" }
        return "Im Eintrag einzeln änderbar"
    }

    /// «Nie mehr vorschlagen» (Web `fBankIgn`)
    func ignore(_ id: String, model: AppModel) {
        guard let i = index(id) else { return }
        let s = items[i].s, name = items[i].ed.name
        model.update { d in BankBridge.ignore(s, in: &d) }
        items[i].s.ignored = true
        items[i].on = false
        model.toast("«\(name)» wird nicht mehr vorgeschlagen")
    }

    // MARK: Formular (Web bkContractOf, bkOpenForm, bkFormDone, bkOpenInc, bkIncFormDone)

    /// Vorschlag mit den Werten aus der Liste (Betrag ggf. als neuer Preis)
    private func edited(_ it: Item, _ d: AppData) -> BankSuggestion {
        var s = it.s
        s.name = it.ed.name
        s.cycle = it.ed.cycle
        s.category = categoryName(it, d)
        s.due = it.ed.due
        if let ch = s.change, Swift.abs(it.ed.amount - ch.amount) > 0.004 {
            if Swift.abs(it.ed.amount - ch.prev) < 0.005 { s.change = nil } else { s.change?.amount = it.ed.amount }
        }
        s.amount = it.ed.amount
        return s
    }

    /// Schnellwahl Kündigungsfrist anwenden (Web: jederzeit kündbar mit 1 bzw. 3 Monaten Frist, oder nicht kündbar)
    private static func applyTerm(_ term: String, to c: inout Contract, full: Bool) {
        if term == "1" || term == "3" {
            c.notice = Int(term) ?? 0
            c.noticeUnit = .months
            c.cancelTerm = .anytime
        } else if term == "x" {
            c.noCancel = true
            if full {
                c.mandatory = false
                c.cancelTerm = .anytime
            }
        }
    }

    /// Entwurf für das Vertragsformular (Web `bkContractOf`)
    func draft(_ it: Item, _ d: AppData, today: Day) -> BankFormDraft {
        if let o = it.over { return o }
        let s = edited(it, d)
        var c = BankImport.toContract(s, persons: [], data: d, today: today)
        c.holderIDs = it.ed.holderIDs
        c.categoryID = it.ed.categoryID ?? d.otherCategory?.id
        c.label = it.ed.label
        c.cycle = it.ed.cycle
        c.due = it.ed.due
        c.currency = Currency(rawValue: s.currency) ?? d.settings.homeCurrency
        if let l = it.logo {
            c.logoID = l.id
            c.logoBg = l.bg
        }
        if !hasTermBase(it, d) { Self.applyTerm(it.term, to: &c, full: true) }
        let t = s.catalogEntry
        let p = d.partner(c.partnerID)
        let addrText = (t?.address ?? "").replacingOccurrences(of: "\r\n", with: "\n")
        let addr = p?.address.isEmpty == false ? p!.address
            : (addrText.isEmpty ? PostalAddress() : WebImport.addrSplit(addrText, partnerName: it.ed.name))
        let web = !(p?.web ?? "").isEmpty ? p!.web : (t?.web ?? "")
        return BankFormDraft(contract: c, partnerName: it.ed.name, web: web, address: addr, logoID: it.logo?.id, logoBg: it.logo?.bg)
    }

    /// Formular gesichert: Werte in den Vorschlag übernehmen (Web `bkFormDone`)
    func formDone(_ id: String, _ r: BankFormDraft, model: AppModel) {
        guard let i = index(id) else { return }
        let c = r.contract
        items[i].over = r
        items[i].on = true
        items[i].ed.name = r.partnerName.isEmpty ? items[i].ed.name : r.partnerName
        items[i].ed.label = c.label
        items[i].ed.amount = model.calc.curPrice(c)
        items[i].ed.cycle = c.cycle == 0 ? 1 : c.cycle
        items[i].ed.categoryID = c.categoryID
        items[i].ed.holderIDs = c.holderIDs
        if let due = c.due { items[i].ed.due = due }
        if let old = items[i].logo, old.id != r.logoID { BankLogos.drop(old.id, model: model) }
        items[i].logo = r.logoID.map { BankLogo(id: $0, bg: r.logoBg ?? "#FFFFFF") }
        if Self.overTerm(c) { items[i].term = "" }
    }

    /// Entwurf für das Einnahmenformular
    func incomeDraft(_ it: IncItem) -> Income {
        if let o = it.over { return o }
        let e = it.ed
        return Income(name: e.name, label: e.label, kind: e.kind, amount: e.amount, currency: Currency(rawValue: it.s.currency) ?? .CHF,
                      cycle: e.cycle, due: e.due, holderID: e.holderIDs.first, logoID: it.logo?.id, logoBg: it.logo?.bg)
    }

    func incFormDone(_ id: String, _ x: Income, model: AppModel) {
        guard let i = incIndex(id) else { return }
        inc[i].over = x
        inc[i].on = true
        inc[i].ed.name = x.name
        inc[i].ed.label = x.label
        inc[i].ed.amount = x.amount
        inc[i].ed.cycle = x.cycle == 0 ? 1 : x.cycle
        inc[i].ed.kind = x.kind
        inc[i].ed.holderIDs = x.holderID.map { [$0] } ?? []
        if let due = x.due { inc[i].ed.due = due }
        if let old = inc[i].logo, old.id != x.logoID { BankLogos.drop(old.id, model: model) }
        inc[i].logo = x.logoID.map { BankLogo(id: $0, bg: x.logoBg ?? "#FFFFFF") }
    }

    /// Abbrechen: gefundene Logos wieder löschen (Web `bkCancel`)
    func cancel(model: AppModel) {
        for it in items { if let l = it.logo { BankLogos.drop(l.id, model: model) } }
        for it in inc { if let l = it.logo { BankLogos.drop(l.id, model: model) } }
    }

    // MARK: Übernehmen (Web bkGo)

    struct Outcome {
        var created: [UUID] = []
        var priced = 0
        var incomes = 0
    }

    func apply(model: AppModel) -> Outcome {
        var out = Outcome()
        let today = model.today
        let data0 = model.data
        var drop: [String] = []
        // Werte vorab berechnen (Zugriff auf self ausserhalb des Datenblocks)
        struct NewC {
            var c: Contract
            var name: String
            var catalog: CatalogEntry?
            var web: String
            var address: PostalAddress
            var logo: BankLogo?
            var learn: (BankSuggestion, String, String)?
        }
        var newCs: [NewC] = []
        for it in items {
            if !it.on || (it.s.ignored && !showIgnored) {
                if let l = it.logo { drop.append(l.id) }
                continue
            }
            if let o = it.over {
                var c = o.contract
                if !Self.overTerm(c) { Self.applyTerm(it.term, to: &c, full: false) }
                newCs.append(NewC(c: c, name: o.partnerName, catalog: nil, web: o.web, address: o.address,
                                  logo: o.logoID.map { BankLogo(id: $0, bg: o.logoBg ?? "#FFFFFF") }, learn: nil))
                continue
            }
            let f = draft(it, data0, today: today)
            let cat = categoryName(it, data0)
            let learn: (BankSuggestion, String, String)? = (it.ed.name != it.s.name || cat != it.s.category) ? (it.s, it.ed.name, cat) : nil
            newCs.append(NewC(c: f.contract, name: it.ed.name, catalog: it.s.catalogEntry, web: "", address: PostalAddress(),
                              logo: it.logo, learn: learn))
        }
        let chosenPrices = prices.filter { $0.on }
        var newIncomes: [Income] = []
        for it in inc {
            if !it.on {
                if let l = it.logo { drop.append(l.id) }
                continue
            }
            var x = incomeDraft(it)
            x.id = UUID()
            newIncomes.append(x)
        }
        let firstHolders = items.first { $0.on }?.ed.holderIDs
        model.update { d in
            for n in newCs {
                var c = n.c
                c.id = UUID()
                if n.catalog != nil || n.web.isEmpty {
                    c.partnerID = BankImport.partnerID(named: n.name, current: c.partnerID, catalog: n.catalog, in: &d)
                } else {
                    c.partnerID = d.partnerID(forName: n.name, web: n.web)
                }
                if let pid = c.partnerID, let pi = d.partnerIndex(pid) {
                    if d.partners[pi].address.isEmpty && !n.address.isEmpty { d.setPartnerAddress(pid, n.address) }
                    // Logo gehört zum Vertragspartner; ein vorhandenes bleibt
                    if let l = n.logo, (d.partners[pi].logoID ?? "").isEmpty {
                        d.setPartnerLogo(pid, logoID: l.id, background: l.bg)
                        c.logoID = nil
                        c.logoBg = nil
                    }
                }
                if let l = n.learn { BankBridge.learn(l.0, name: l.1, category: l.2, in: &d) }
                if let id = try? d.saveContract(c, today: today) { out.created.append(id) }
            }
            for p in chosenPrices {
                BankImport.applyPrice(p.m, to: &d)
                out.priced += 1
            }
            for x in newIncomes {
                if (try? d.saveIncome(x, today: today)) != nil { out.incomes += 1 }
            }
            if let h = firstHolders, h.count == 1, d.persons.count > 1 { d.settings.lastHolderIDs = h }
        }
        for id in drop { BankLogos.drop(id, model: model) }
        return out
    }

    /// Neue Verträge, bei denen noch Angaben fehlen – Anlass für «Fast fertig!» (Web `vkNeeds().per` der neuen Verträge)
    static func incompleteCount(_ ids: [UUID], data: AppData, today: Day) -> Int {
        let r = Completeness.report(data, today: today)
        return ids.filter { !(r.per[$0] ?? []).isEmpty }.count
    }
}
