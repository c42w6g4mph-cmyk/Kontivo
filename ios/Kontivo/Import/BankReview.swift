import SwiftUI
import KontivoCore

/// Logo eines Vorschlags (Web `it.logo = {id, bg}`): Datei-ID im Dateispeicher und Kachelfarbe
struct BankLogo: Equatable {
    var id: String
    var bg: String
}

/// Zustand des Fensters «Kontoauszug» (Web `bk`, Stand v330): geführte Schritte Fixkosten → Einnahmen → Fristen.
/// `items` = neue Verträge, `prices` = neuer Preis bei erfassten Verträgen, `inc` = Einnahmen. Bearbeiten öffnet das normale
/// Vertrags- bzw. Einnahmenformular (Titel «Vorschlag», `BankFormBridge`); «Sichern» schreibt zurück in den Vorschlag (`over`).
/// Formular und Übernehmen: `BankReviewApply.swift`.
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
        /// Zahlungen aufgeklappt bzw. alle gezeigt (Web `it.pay`, `it.payAll`)
        var pay = false
        var payAll = false
        /// Antwort auf die Rückfrage «Derselbe Vertrag?» / «Im Archiv»: "y", "n" oder "" (Web `it.q`)
        var q = ""
        /// «Wieder aktivieren»: archivierter Vertrag (Web `it.react`)
        var react: UUID?
        /// Haken bzw. Ja/Nein selbst angetippt (Web `it.touched`): «abgewählt» wird für den nächsten Import gelernt
        var touched = false
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
        var pay = false
        var payAll = false
        /// «Neuer Lohn» statt «Einmalig» bei abweichender letzter Gutschrift (Web `it.nl`)
        var nl = false
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
        // gelernte Korrekturen (Web v331 ff. `bankLearnAssign`): letztes Mal abgewählt → vorab abgewählt, Bezeichnung übernehmen
        var sugg = result.items
        BankImport.learnAssign(&sugg, settings: data.settings)
        items = sugg.map { s0 in
            var s = s0
            // unbekannte Währung → Hauptwährung (Web BK_CUR)
            if Currency(rawValue: s.currency) == nil { s.currency = home }
            let lr = s.learn
            let ed = Edit(name: s.name, label: !(lr?.l ?? "").isEmpty ? lr!.l : BankImport.label(s), amount: s.amount, cycle: s.cycle,
                          categoryID: data.category(named: s.category)?.id, holderIDs: H, due: s.due)
            // Rückfrage (gleicher Betrag / im Archiv) offen: erst nach der Antwort übernehmen
            return Item(s: s, on: s.confidence != .low && !s.ignored && s.sameAs == nil && s.archived == nil && lr?.x != true, ed: ed)
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

    /// Schon erfasste Einnahmen (Web `res.inc.known`)
    var incKnown: [BankIncomeKnown] { incResult.known }

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

    /// Im Formular steht schon eine Kündigungsregel (Web `bkOverTerm`)
    static func overTerm(_ c: Contract) -> Bool { c.noCancel || c.notice > 0 || c.end != nil || c.mandatory }

    func termList(_ d: AppData) -> [Int] {
        items.indices.filter { i in
            let it = items[i]
            return it.on && !(it.s.ignored && !showIgnored) && !hasTermBase(it, d)
        }
    }

    /// Fixkosten-Schritt auch ohne neue Vorschläge, wenn es Hinweise gibt (weiter abgebucht, schon erfasst); Einnahmen-Schritt auch,
    /// wenn alle Einnahmen schon erfasst sind (Web v281)
    func steps(_ d: AppData) -> [Step] {
        var l: [Step] = []
        let hasInc = !inc.isEmpty || !incKnown.isEmpty
        if fixCount > 0 || !prices.isEmpty || !result.after.isEmpty || !result.known.isEmpty || !hasInc { l.append(.fix) }
        if hasInc { l.append(.inc) }
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

    /// Etwas gefunden, das beim Schliessen verloren ginge (Web: Rückfrage «Import abbrechen?»)
    var hasResults: Bool { !items.isEmpty || !inc.isEmpty || !prices.isEmpty }

    // MARK: Zählen (Web bkCounts, bkFoot)

    var counts: (n: Int, p: Int, i: Int) {
        (items.filter { $0.on && (showIgnored || !$0.s.ignored) }.count, prices.filter { $0.on }.count, inc.filter { $0.on }.count)
    }

    /// Nichts Neues gefunden (alles schon erfasst): «Fertig» schliesst nur
    func isDoneOnly(_ d: AppData) -> Bool { isLastStep(d) && fixCount == 0 && inc.isEmpty && prices.isEmpty }

    func footerTitle(_ d: AppData) -> String {
        if !isLastStep(d) {
            let st = steps(d)
            let nx = st[Swift.min(stepIndex(d) + 1, st.count - 1)]
            return nx == .inc ? "Weiter zu Einnahmen" : nx == .term ? "Weiter zu Kündigungsfristen" : "Weiter"
        }
        if isDoneOnly(d) { return "Fertig" }
        let k = counts
        let all = k.n + k.p + k.i
        if all == 0 { return "Nichts ausgewählt" }
        return all == 1 ? "1 Eintrag übernehmen" : "\(all) Einträge übernehmen"
    }

    func footerEnabled(_ d: AppData) -> Bool {
        if !isLastStep(d) || isDoneOnly(d) { return true }
        let k = counts
        return k.n + k.p + k.i > 0
    }

    // MARK: Ändern

    func index(_ id: String) -> Int? { items.firstIndex { $0.id == id } }
    func incIndex(_ id: String) -> Int? { inc.firstIndex { $0.id == id } }

    func toggle(_ id: String) {
        guard let i = index(id) else { return }
        items[i].on.toggle()
        items[i].touched = true
    }

    func setOn(_ id: String, _ on: Bool) {
        guard let i = index(id) else { return }
        items[i].on = on
        items[i].touched = true
    }

    func toggleInc(_ id: String) {
        guard let i = incIndex(id) else { return }
        inc[i].on.toggle()
    }

    func setNewLevel(_ id: String, _ nl: Bool) {
        guard let i = incIndex(id) else { return }
        inc[i].nl = nl
    }

    func togglePrice(_ id: String) {
        guard let i = prices.firstIndex(where: { $0.id == id }) else { return }
        prices[i].on.toggle()
    }

    func setTerm(_ id: String, _ v: String) {
        guard let i = index(id) else { return }
        items[i].term = v
    }

    /// Zahlungen auf-/zuklappen bzw. alle zeigen (Web `data-bkpay`, `data-bkpayall`)
    func togglePay(_ id: String) {
        if let i = index(id) {
            items[i].pay.toggle()
            items[i].payAll = false
        } else if let i = incIndex(id) {
            inc[i].pay.toggle()
            inc[i].payAll = false
        }
    }

    func showAllPay(_ id: String) {
        if let i = index(id) { items[i].payAll = true } else if let i = incIndex(id) { inc[i].payAll = true }
    }

    /// Antwort auf die Rückfrage in der Zeile (Web `data-bkdupy` / `data-bkdupn`): Archiv → «Wieder aktivieren» / «Neu anlegen»;
    /// gleicher Betrag → «Ja, schon erfasst» (nicht anlegen, Zuordnung merken) / «Nein, neu»
    func answerDup(_ id: String, yes: Bool, model: AppModel) {
        guard let i = index(id) else { return }
        items[i].q = yes ? "y" : "n"
        let s = items[i].s
        if let a = s.archived {
            items[i].on = true
            items[i].react = yes ? a : nil
            return
        }
        items[i].on = !yes
        guard let sid = s.sameAs, let cc = model.data.contract(sid) else { return }
        let k = BankImport.ignoreKey(s), pn = model.data.partnerName(of: cc), cn = model.data.category(cc.categoryID)?.name ?? ""
        model.update { d in
            if yes {
                d.settings.bankAlias[k] = BankAlias(n: pn, c: cn)
            } else if let a = d.settings.bankAlias[k], a.n == pn {
                d.settings.bankAlias[k] = nil
            }
        }
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

    /// Kürzerer Auszug als 11 Monate: Jahresverträge fehlen womöglich (Web `.bkspan`)
    var shortSpanText: String? {
        guard let f = file.from, let t = file.to else { return nil }
        let m = Int((Double(f.days(to: t)) / 30.4).rounded())
        // Web: `spanM && spanM < 11` (0 Monate zeigt nichts)
        guard m > 0 && m < 11 else { return nil }
        return "Der Auszug umfasst nur " + (m < 1 ? "wenige Wochen" : "\(m) Monate")
            + ". Jahresbeiträge (Versicherungen, Steuern, Mitgliedschaften) fehlen womöglich – am besten die letzten 12 Monate exportieren."
    }
}
