import SwiftUI
import KontivoCore

/// Formular und Übernehmen der Import-Vorschläge (Web bkContractOf, bkFormDone, bkIncPrices, bkIncFormDone, bkGo)
extension BankReview {
    // MARK: Formular

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
    static func applyTerm(_ term: String, to c: inout Contract, full: Bool) {
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
        // Lohnverlauf aus den Zahlungen (Web `bkIncPrices`), bei «Neuer Lohn» ab der abweichenden Gutschrift deren Betrag;
        // Beginn = erste Gutschrift, wenn deutlich nach Auszugsbeginn (`bankStart`)
        let ip = BankImport.incomePrices(it.s, amount: e.amount, newLevel: it.nl ? deviation(it) : nil)
        return Income(name: e.name, label: e.label, kind: e.kind, amount: ip.amount, currency: Currency(rawValue: it.s.currency) ?? .CHF,
                      cycle: e.cycle, due: e.due, start: BankImport.start(it.s, statementFrom: file.from), holderID: e.holderIDs.first,
                      prices: ip.prices, logoID: it.logo?.id, logoBg: it.logo?.bg)
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
        /// «Wieder aktivieren» (zählt bei «n Verträge angelegt» mit)
        var reactivated = 0
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
        var reacts: [(UUID, Double, Day)] = []
        // Lernen (Web v331 ff.): bewusst abgewählt → nächstes Mal vorab abgewählt; Bezeichnung geändert → nächstes Mal übernommen
        let learns: [(s: BankSuggestion, on: Bool, touched: Bool, label: String, react: Bool)] = items.map { it in
            (it.s, it.on, it.touched, it.over.map { $0.contract.label } ?? it.ed.label, it.react != nil)
        }
        for it in items {
            if !it.on || (it.s.ignored && !showIgnored) {
                if let l = it.logo { drop.append(l.id) }
                continue
            }
            // «Wieder aktivieren»: archivierten Vertrag zurückholen, Betrag ggf. als neuer Preis ab der letzten Zahlung
            if let r = it.react, data0.contract(r) != nil {
                reacts.append((r, it.ed.amount, it.s.last))
                if let l = it.logo { drop.append(l.id) }
                continue
            }
            if let o = it.over {
                var c = o.contract
                if !Self.overTerm(c) { Self.applyTerm(it.term, to: &c, full: false) }
                let cat = data0.category(c.categoryID)?.name ?? ""
                let learn: (BankSuggestion, String, String)? = !o.partnerName.isEmpty && (o.partnerName != it.s.name || cat != it.s.category)
                    ? (it.s, o.partnerName, cat) : nil
                newCs.append(NewC(c: c, name: o.partnerName, catalog: nil, web: o.web, address: o.address,
                                  logo: o.logoID.map { BankLogo(id: $0, bg: o.logoBg ?? "#FFFFFF") }, learn: learn))
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
        let result = self.result, file = self.file
        model.update { d in
            for l in learns { BankImport.learn(l.s, on: l.on, touched: l.touched, label: l.label, reactivate: l.react, in: &d.settings) }
            for r in reacts {
                BankImport.reactivate(r.0, amount: r.1, from: r.2, in: &d, today: today)
                out.reactivated += 1
            }
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
            // schon erfasste Verträge: Gläubiger-ID/Mandat nachtragen (Web v273)
            BankImport.rememberCreditorIDs(result, in: &d)
            for p in chosenPrices {
                BankImport.applyPrice(p.m, to: &d)
                out.priced += 1
            }
            for x in newIncomes {
                if (try? d.saveIncome(x, today: today)) != nil { out.incomes += 1 }
            }
            if let h = firstHolders, h.count == 1, d.persons.count > 1 { d.settings.lastHolderIDs = h }
            // Zeitraum des Auszugs merken, aber nur wenn etwas übernommen wurde (Web v275, Mehr → Daten)
            if !out.created.isEmpty || out.reactivated > 0 || out.incomes > 0 || out.priced > 0, let fr = file.from, let to = file.to {
                d.settings.lastBankImport = BankImportInfo(from: fr, to: to, at: today, files: Swift.max(1, file.files))
            }
        }
        for id in drop { BankLogos.drop(id, model: model) }
        return out
    }

    /// Neue Verträge, bei denen noch Angaben fehlen – Anlass für «Fast fertig!» (Web `vkNeeds().per` der neuen Verträge)
    static func incompleteCount(_ ids: [UUID], data: AppData, today: Day) -> Int {
        let r = Completeness.report(data, today: today)
        return ids.filter { !(r.per[$0] ?? []).isEmpty }.count
    }

    // MARK: Kopfkarte (Web bkHero)

    struct Hero {
        var title: String
        var sub: String
        /// «1 Preis aktualisiert» in Messing
        var em: String
        /// Logos bzw. Kategorie-Symbole (höchstens 4, sonst 3 und «+n»)
        var marks: [Mark]
        var more: Int
    }

    struct Mark: Identifiable {
        var id: String
        var logo: BankLogo?
        var colorHex: String
        var symbol: String
    }

    /// Kopfkarte: «n Verträge erkannt» bzw. «n Einkommen erkannt», Kategorien als Satz, Logos der gefundenen Vertragspartner
    /// (mit Logo zuerst, dann nach Betrag pro Monat; je Vertragspartner einmal; ohne Logo Kategorie-Symbol)
    func hero(_ d: AppData, income: Bool) -> Hero {
        struct E {
            var id: String, name: String, cat: String, monthly: Double, logo: BankLogo?, color: String, symbol: String
        }
        let L: [E]
        if income {
            L = inc.map { it in
                E(id: it.id, name: it.ed.name, cat: it.ed.kind.displayName, monthly: it.ed.amount / Double(Swift.max(1, it.ed.cycle)),
                  logo: it.logo, color: it.ed.kind.colorHex, symbol: KIcon.symbol(forKey: it.ed.kind.icon))
            }
        } else {
            L = items.filter { showIgnored || !$0.s.ignored }.map { it in
                let c = d.category(it.ed.categoryID) ?? d.otherCategory
                return E(id: it.id, name: it.ed.name, cat: categoryName(it, d), monthly: it.ed.amount / Double(Swift.max(1, it.ed.cycle)),
                         logo: it.logo, color: c?.displayColorHex ?? KCategory.displayFallbackColor, symbol: KIcon.symbol(for: c))
            }
        }
        var cats: [String] = []
        for e in L where !cats.contains(e.cat) { cats.append(e.cat) }
        let n = L.count, np = income ? 0 : prices.count
        let word = income ? "Einkommen" : (n == 1 ? "Vertrag" : "Verträge")
        var title = n > 0 ? "\(n) \(word) erkannt" : ""
        func and(_ a: [String]) -> String { a.count < 2 ? a.joined() : a.dropLast().joined(separator: ", ") + " und " + a[a.count - 1] }
        var sub = ""
        if n == 1 {
            sub = L[0].cat + (L[0].name.isEmpty ? "" : " · " + L[0].name)
        } else {
            sub = and(cats.count > 5 ? Array(cats.prefix(4)) + ["\(cats.count - 4) weitere"] : cats)
        }
        let em = np > 0 ? (np == 1 ? "1 Preis aktualisiert" : "\(np) Preise aktualisiert") : ""
        if n == 0 { title = em }
        var seen = Set<String>()
        let U = L.enumerated().sorted { a, b in
            let la = a.element.logo != nil ? 1 : 0, lb = b.element.logo != nil ? 1 : 0
            if la != lb { return la > lb }
            if a.element.monthly != b.element.monthly { return a.element.monthly > b.element.monthly }
            return a.offset < b.offset
        }.map { $0.element }.filter { seen.insert(Partners.lnorm($0.name)).inserted }
        let shown = U.prefix(U.count > 4 ? 3 : 4).map { Mark(id: $0.id, logo: $0.logo, colorHex: $0.color, symbol: $0.symbol) }
        return Hero(title: title, sub: sub, em: em, marks: Array(shown), more: U.count > 4 ? U.count - 3 : 0)
    }
}
