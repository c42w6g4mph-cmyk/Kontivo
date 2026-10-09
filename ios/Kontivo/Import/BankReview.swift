import SwiftUI
import KontivoCore

/// Zustand des Fensters «Vorschläge» (Web `bk`: items mit on/ed, price, open, showIgn, showKnown).
@MainActor
@Observable
final class BankReview {
    /// Bearbeitete Werte einer Zeile (Web `ed`)
    struct Edit: Equatable {
        var name: String
        var amount: Double
        var amountText: String
        var cycle: Int
        var categoryID: UUID?
        var holderIDs: [UUID]
        var due: Day
    }

    struct Row: Identifiable {
        var s: BankSuggestion
        var on: Bool
        var ed: Edit
        /// Kategoriename beim Vorschlag (für «gelernte» Korrektur)
        var categoryID0: UUID?
        var id: String { s.id }
    }

    struct PriceRow: Identifiable {
        var m: BankPriceMatch
        var on: Bool
        var id: String { m.contractID.uuidString + "|" + m.from.iso }
    }

    let file: BankFile
    let result: BankFindResult
    let label: String
    let privacy: String
    var rows: [Row]
    var prices: [PriceRow]
    /// aufgeklappte Zeile (Editor)
    var open: String?
    var showIgnored = false
    var showKnown = false

    init(file: BankFile, result: BankFindResult, label: String, privacy: String, data: AppData) {
        self.file = file
        self.result = result
        self.label = label
        self.privacy = privacy
        let home = data.settings.homeCurrency.rawValue
        let holders = data.defaultHolderIDs
        rows = result.items.map { s0 in
            var s = s0
            // unbekannte Währung → Hauptwährung (Web: BK_CUR)
            if Currency(rawValue: s.currency) == nil { s.currency = home }
            let cat = OnbQuick.category(named: s.category, in: data)?.id
            let ed = Edit(name: s.name, amount: s.amount, amountText: Format.fixed2(s.amount), cycle: s.cycle,
                          categoryID: cat, holderIDs: holders, due: s.due)
            return Row(s: s, on: s.confidence != .low && !s.ignored, ed: ed, categoryID0: cat)
        }
        prices = result.prices.map { PriceRow(m: $0, on: true) }
    }

    // MARK: Abgeleitet

    /// «PostFinance · 62 Buchungen · Okt 25 – Sep 26»
    var header: String {
        var parts = [label, "\(file.tx.count) Buchungen"]
        if let f = file.from ?? file.tx.first?.date, let t = file.to ?? file.tx.last?.date {
            parts.append(Self.mon(f) + " – " + Self.mon(t))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var visible: [Int] { rows.indices.filter { showIgnored || !rows[$0].s.ignored } }
    /// «Neu gefunden»
    var sure: [Int] { visible.filter { rows[$0].s.confidence != .low } }
    /// «Vielleicht»
    var maybe: [Int] { visible.filter { rows[$0].s.confidence == .low } }
    var ignoredCount: Int { max(rows.filter { $0.s.ignored }.count, result.ignoredCount) }
    var isEmpty: Bool { visible.isEmpty && prices.isEmpty }

    var selectedCount: Int { rows.filter { $0.on && (showIgnored || !$0.s.ignored) }.count }
    var selectedPrices: Int { prices.filter { $0.on }.count }

    /// Knopf unten (Web `bkFoot`)
    var footerTitle: String {
        let n = selectedCount, p = selectedPrices
        var t: [String] = []
        if n > 0 { t.append(n == 1 ? "1 Vertrag anlegen" : "\(n) Verträge anlegen") }
        if p > 0 { t.append((p == 1 ? "1 Preis" : "\(p) Preise") + (n > 0 ? "" : " anpassen")) }
        return t.isEmpty ? "Nichts ausgewählt" : t.joined(separator: " · ")
    }

    /// Zweite Zeile (Web `bkSub`)
    func sub(_ r: Row) -> String {
        let s = r.s, e = r.ed
        var t = (Format.cycleText(e.cycle) ?? "alle \(e.cycle) Monate")
        t += s.confidence == .low ? " (vermutet) · 1 Zahlung am " + Self.day(s.last) : " · \(s.count)× seit " + Self.mon(s.first)
        if let ch = s.change, abs(e.amount - ch.amount) < 0.005 {
            t += " · neuer Preis ab " + Self.day(ch.from)
        } else if s.varies {
            t += " · Betrag schwankt"
        }
        return t
    }

    /// Herkunft: letzte Buchungen (Web `bkProof`)
    func proofLines(_ s: BankSuggestion) -> [String] {
        var out: [String] = []
        let k = s.dates.count
        var list: [String] = []
        for j in stride(from: k - 1, through: max(0, k - 4), by: -1) where j >= 0 {
            let a = j < s.amounts.count ? s.amounts[j] : s.amount
            list.append(Self.day(s.dates[j]) + " · " + Format.money(a))
        }
        if !s.text.isEmpty && Self.norm(s.text) != Self.norm(s.raw) { out.append(String(s.text.prefix(90))) }
        if !list.isEmpty { out.append(list.joined(separator: "  ·  ") + (k > 4 ? " … (\(k) Buchungen)" : "")) }
        let meta = [Self.kindText(s.kind), s.cred.isEmpty ? "" : "Gläubiger-ID " + s.cred, s.mref.isEmpty ? "" : "Mandat " + s.mref]
            .filter { !$0.isEmpty }
        if !meta.isEmpty { out.append(meta.joined(separator: " · ")) }
        return out
    }

    static func kindText(_ k: BankKind) -> String {
        switch k {
        case .dd: return "Lastschrift / eBill"
        case .so: return "Dauerauftrag"
        case .card: return "Kartenzahlung"
        case .tr: return "Überweisung"
        case .unknown: return ""
        }
    }

    // MARK: Ändern

    func index(_ id: String) -> Int? { rows.firstIndex { $0.id == id } }

    /// Eingabe im Editor: Zeile gilt als ausgewählt (Web `bkInput`: it.on = true)
    func edit(_ id: String, _ change: (inout Edit) -> Void) {
        guard let i = index(id) else { return }
        change(&rows[i].ed)
        rows[i].on = true
    }

    func setAmountText(_ id: String, _ text: String) {
        edit(id) { e in
            e.amountText = text
            if let v = Format.parseNum(text), v >= 0 { e.amount = Format.round2(v) }
        }
    }

    func toggle(_ id: String) {
        guard let i = index(id) else { return }
        rows[i].on.toggle()
    }

    func togglePrice(_ id: String) {
        guard let i = prices.firstIndex(where: { $0.id == id }) else { return }
        prices[i].on.toggle()
    }

    /// «Nie mehr vorschlagen»
    func ignore(_ id: String, model: AppModel) {
        guard let i = index(id) else { return }
        let s = rows[i].s, name = rows[i].ed.name
        model.update { d in BankBridge.ignore(s, in: &d) }
        rows[i].s.ignored = true
        rows[i].on = false
        open = nil
        model.toast("«\(name)» wird nicht mehr vorgeschlagen")
    }

    // MARK: Anlegen (Web `bkGo`)

    struct Outcome {
        var created: [UUID] = []
        var priced = 0
    }

    func apply(model: AppModel) -> Outcome {
        var out = Outcome()
        let today = model.today
        let chosen = rows.filter { $0.on && (showIgnored || !$0.s.ignored) }
        let chosenPrices = prices.filter { $0.on }
        model.update { d in
            for r in chosen {
                var s = r.s
                let name = Format.collapseSpaces(r.ed.name).isEmpty ? r.s.name : Format.collapseSpaces(r.ed.name)
                let cat = d.category(r.ed.categoryID) ?? d.otherCategory
                s.name = name
                s.cycle = r.ed.cycle
                s.due = r.ed.due
                if let cat { s.category = cat.name }
                // Betrag geändert: bei erkannter Preisänderung ist es der neue Preis, sonst der einzige
                if let ch = s.change, abs(r.ed.amount - ch.amount) > 0.004 {
                    if abs(r.ed.amount - ch.prev) < 0.005 { s.change = nil } else { s.change?.amount = r.ed.amount }
                }
                s.amount = r.ed.amount
                var c = BankImport.toContract(s, persons: [], data: d, today: today)
                c.id = UUID()
                c.categoryID = cat?.id
                c.holderIDs = r.ed.holderIDs
                c.cycle = r.ed.cycle
                c.due = r.ed.due
                c.currency = Currency(rawValue: s.currency) ?? d.settings.homeCurrency
                c.partnerID = Self.partnerID(for: name, current: c.partnerID, catalogName: s.catalogName, in: &d)
                if name != r.s.name || r.ed.categoryID != r.categoryID0 {
                    BankBridge.learn(r.s, name: name, category: cat?.name ?? s.category, in: &d)
                }
                if let id = try? d.saveContract(c, today: today) { out.created.append(id) }
            }
            for p in chosenPrices {
                guard case let cid = p.m.contractID, let i = d.contractIndex(cid) else { continue }
                var pr = d.contracts[i].prices.filter { $0.from != p.m.from }
                pr.append(PriceChange(from: p.m.from, amount: p.m.amount))
                d.contracts[i].prices = pr.sorted { $0.from < $1.from }
                out.priced += 1
            }
            if d.persons.count > 1, let h = chosen.first?.ed.holderIDs, !h.isEmpty { d.settings.lastHolderIDs = h }
        }
        return out
    }

    /// Vertragspartner zum (ggf. geänderten) Namen: bestehender gleichen Namens, sonst neu (Website aus dem Katalog)
    private static func partnerID(for name: String, current: UUID?, catalogName: String?, in d: inout AppData) -> UUID? {
        if let cur = d.partner(current), cur.name.lowercased() == name.lowercased() { return cur.id }
        if let p = Partners.find(name, in: d) { return p.id }
        let web = catalogName.flatMap { Catalog.find($0)?.web } ?? ""
        let p = Partner(name: name, web: web)
        d.partners.append(p)
        return p.id
    }

    /// Neue Verträge, bei denen noch Angaben fehlen (Logo oder Kündigungsfrist) – Anlass für «Fast fertig!».
    /// Annäherung an Web `vkNeeds` (Kern «Vollständigkeit» kann das ersetzen).
    static func incompleteCount(_ ids: [UUID], data: AppData) -> Int {
        ids.compactMap { data.contract($0) }.filter { c in
            data.logo(of: c) == nil || (c.notice == 0 && !c.noCancel && !c.noWatch && !c.mandatory)
        }.count
    }

    // MARK: Texte

    /// «Okt 26» (Web `bkMon`)
    static func mon(_ d: Day) -> String {
        Format.monthShort[d.month - 1] + " " + String(format: "%02d", d.year % 100)
    }

    /// «5.9.26» (Web `bkDay`)
    static func day(_ d: Day) -> String {
        "\(d.day).\(d.month)." + String(format: "%02d", d.year % 100)
    }

    static func norm(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
