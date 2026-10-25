import Foundation

// MARK: - Verträge-Tab, Ansichten «Einnahmen» und «Variabel» (Web v231–v233 `renderAltList`)
// Filter (Art/Quelle/Person bzw. Art/Person), Sortierung (settings.sortI/sortV), Status-Chips «aktiv»/«noch nicht aktiv»,
// Gruppen mit Summen wie bei den Verträgen, Archiv für beendete Einträge. Nur Logik; Darstellung in der App.

/// Ansicht im Verträge-Tab (Web `state.lm`: c | i | v)
public enum ListMode: String, CaseIterable, Hashable, Sendable {
    case contracts = "c", incomes = "i", variable = "v"

    /// Reiter-Beschriftung
    public var title: String {
        switch self {
        case .contracts: return "Verträge"
        case .incomes: return "Einnahmen"
        case .variable: return "Variabel"
        }
    }
}

/// Filterdimension der Ansichten Einnahmen/Variabel (Web `ALT_DIMS`)
public enum AltDimension: String, CaseIterable, Hashable, Sendable {
    case cat, partner, holder

    public func title(_ m: ListMode) -> String {
        switch self {
        case .cat: return "Art"
        case .partner: return "Quelle"
        case .holder: return "Person"
        }
    }

    /// Dimensionen je Ansicht: Einnahmen Art/Quelle/Person, Variabel Art/Person
    public static func dims(_ m: ListMode) -> [AltDimension] { m == .incomes ? [.cat, .partner, .holder] : [.cat, .holder] }
}

/// Filter je Ansicht (Web `state.fltA[m]`): Werte sind die angezeigten Schlüssel (Art, Quelle, Personenname)
public struct AltFilter: Hashable, Sendable {
    public var cat: String?
    public var partner: String?
    public var holder: String?

    public init(cat: String? = nil, partner: String? = nil, holder: String? = nil) {
        self.cat = cat
        self.partner = partner
        self.holder = holder
    }

    public subscript(_ d: AltDimension) -> String? {
        get {
            switch d {
            case .cat: return cat
            case .partner: return partner
            case .holder: return holder
            }
        }
        set {
            switch d {
            case .cat: cat = newValue
            case .partner: partner = newValue
            case .holder: holder = newValue
            }
        }
    }

    /// Anzahl aktiver Filter der Ansicht (Web `altCount`)
    public func count(_ m: ListMode) -> Int { AltDimension.dims(m).filter { self[$0] != nil }.count }
}

/// Status-Chip der Ansicht (Web `state.heroFA[m]`)
public enum AltStatus: String, Hashable, Sendable {
    case active = "act", future = "fut"

    public var label: String { self == .future ? "Noch nicht aktiv" : "Aktiv" }
}

/// Sortierung (Web `ALT_SORT`)
public enum AltSort: String, Hashable, Sendable {
    case due, cost, partner, cat, holder, name

    /// Optionen je Ansicht in Web-Reihenfolge (Schlüssel, Beschriftung im Auswahlblatt)
    public static func options(_ m: ListMode) -> [(sort: AltSort, label: String)] {
        m == .incomes
            ? [(.due, "Nächste Zahlung"), (.cost, "Betrag, höchster zuerst"), (.partner, "Quelle, A–Z"), (.cat, "Art"), (.holder, "Person")]
            : [(.cost, "Betrag, höchster zuerst"), (.name, "Bezeichnung, A–Z"), (.cat, "Art"), (.holder, "Person")]
    }

    /// Kurzbeschriftung im Knopf: Text bis zum Komma
    public func shortLabel(_ m: ListMode) -> String {
        let l = AltSort.options(m).first { $0.sort == self }?.label ?? ""
        return l.components(separatedBy: ",").first ?? l
    }
}

/// Zeile der Liste (Web `row` in `renderAltList`)
public struct AltRow: Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    /// Zweitzeile (Quelle, Personen, Anteil, «geschätzt»); "" = keine
    public var meta: String
    /// Etikett «ab …», «beendet …», «bis …»
    public var tag: String?
    /// Betrag in der Währung des Eintrags
    public var amount: Double
    public var currency: Currency
    /// Zeile unter dem Betrag: Rhythmus (Einnahmen, wenn nicht monatlich) bzw. «pro Monat»
    public var sub: String?
    /// beendet (blass)
    public var ended: Bool
}

public struct AltGroup: Hashable, Identifiable, Sendable {
    public var id: String
    /// nil = ohne Kopf (Sortierung nach Betrag)
    public var title: String?
    public var sum: String
    public var rows: [AltRow]
}

/// Inhalt der Ansicht Einnahmen bzw. Variabel
public struct AltListContent: Hashable, Sendable {
    /// Gar keine Einträge (Leerseite)
    public var isEmpty: Bool
    public var emptyTitle: String
    public var emptyText: String
    /// Kopf: Beschriftung, Summe pro Monat (Hauptwährung), Unterzeile
    public var heroLabel: String
    public var heroSum: Double
    public var heroSub: String
    /// Chips nur mit noch nicht aktiven Einträgen
    public var activeCount: Int
    public var futureCount: Int
    /// Wirksamer Status-Chip (ungültige werden zurückgesetzt)
    public var status: AltStatus?
    public var groups: [AltGroup]
    public var archive: [AltRow]
    /// «2 beendete Einnahmen» / «2 beendet»
    public var archiveText: String
    /// Keine Treffer (Text), nil wenn Gruppen da sind
    public var noHits: String?
    /// Hinweis unter der Liste (nur Variabel mit Einträgen)
    public var hint: String?

    public var showsChips: Bool { futureCount > 0 }
}

/// Wert der Auswahlliste eines Filters (Web `openAltPick`)
public struct AltFilterValue: Hashable, Identifiable, Sendable {
    public var key: String
    /// «2 aktive Einnahmen», «1 aktiver Eintrag» bzw. «nur beendete»
    public var detail: String
    public var id: String { key }
}

extension Calc {
    /// Wirksame Sortierung der Ansicht (Web `altSort`): gespeichert, sonst Art (Einnahmen) bzw. Betrag (Variabel)
    public func altSort(_ m: ListMode) -> AltSort {
        let raw = m == .incomes ? data.settings.incomeSort : data.settings.variableSort
        let k = AltSort(rawValue: raw.isEmpty ? (m == .incomes ? "cat" : "cost") : raw)
        let opts = AltSort.options(m).map { $0.sort }
        if let k, opts.contains(k) { return k }
        return opts[0]
    }

    // MARK: Einträge vereinheitlicht

    struct AltEntry {
        var id: UUID
        var label: String
        var name: String
        var catKey: String
        var holderIDs: [UUID]
        var note: String
        var start: Day?
        var end: Day?
        var currency: Currency
        var cycle: Int
        var due: Day?
        var income: Income?
        var variable: VariableCost?
    }

    private func altEntries(_ m: ListMode) -> [AltEntry] {
        if m == .incomes {
            return data.incomes.map { i in
                AltEntry(id: i.id, label: i.label, name: i.name, catKey: i.kind.displayName, holderIDs: i.holderID.map { [$0] } ?? [],
                         note: i.note, start: i.start, end: i.end, currency: i.currency, cycle: i.cycle, due: i.due, income: i, variable: nil)
            }
        }
        return variableCosts.map { v in
            AltEntry(id: v.id, label: v.label, name: "", catKey: v.icon.displayName, holderIDs: v.holderIDs, note: "",
                     start: v.start, end: v.end, currency: v.currency, cycle: 1, due: nil, income: nil, variable: v)
        }
    }

    /// Personennamen in der Reihenfolge der Personenliste
    private func altHolders(_ e: AltEntry) -> [String] {
        data.persons.filter { e.holderIDs.contains($0.id) }.map { $0.name }
    }

    private func altKeys(_ e: AltEntry, _ d: AltDimension) -> [String] {
        switch d {
        case .holder: return altHolders(e)
        case .partner:
            let n = e.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return [n.isEmpty ? "Ohne Quelle" : n]
        case .cat: return [e.catKey]
        }
    }

    private func altOver(_ e: AltEntry) -> Bool { e.end.map { $0 < today } ?? false }
    private func altAhead(_ e: AltEntry) -> Bool { e.start.map { $0 > today } ?? false }

    /// Monatsbetrag in Hauptwährung (Web `altMon`): Einnahme mit Rhythmus aufgeteilt, einmalige 0
    private func altMon(_ e: AltEntry) -> Double {
        if let i = e.income { return i.cycle != 0 ? conv(curPrice(i), i.currency) / Double(i.cycle) : 0 }
        if let v = e.variable { return conv(v.amount, v.currency) }
        return 0
    }

    private func altShare(_ e: AltEntry, _ person: UUID?) -> Double {
        if let i = e.income { return incomeShare(i, person: person) }
        if let v = e.variable { return share(v, person: person) }
        return 1
    }

    // MARK: Inhalt

    /// Ansicht Einnahmen bzw. Variabel (Web `renderAltList`). `search` = Suchtext, `status` = Chip.
    public func altList(_ m: ListMode, filter f: AltFilter, status: AltStatus?, search: String) -> AltListContent {
        let inc = m == .incomes
        let home = data.settings.homeCurrency.rawValue
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = altEntries(m)
        let dims = AltDimension.dims(m)
        let lfn = f.count(m)
        let hhID: UUID? = f.holder.flatMap { n in data.persons.first { $0.name == n }?.id }
        let hasHH = f.holder != nil
        func sh(_ e: AltEntry) -> Double { hasHH ? (hhID.map { altShare(e, $0) } ?? 0) : 1 }
        func mq(_ e: AltEntry) -> Bool {
            q.isEmpty || [e.label, e.name, inc ? e.catKey : "", altHolders(e).joined(separator: " "), e.note]
                .joined(separator: " ").lowercased().contains(q)
        }
        func fm(_ e: AltEntry) -> Bool {
            lfn == 0 || dims.allSatisfy { d in f[d].map { altKeys(e, d).contains($0) } ?? true }
        }
        let live = all.filter { !altOver($0) && fm($0) }
        let arc = all.filter { altOver($0) && fm($0) }
        let fut = live.filter { altAhead($0) }
        let act = live.filter { !altAhead($0) }
        var hf = status
        if (hf == .future && fut.isEmpty) || (hf == .active && (fut.isEmpty || act.isEmpty)) { hf = nil }
        let sl = hf == .future ? fut : act
        let sum = sl.reduce(0.0) { $0 + altMon($1) * sh($1) }
        let fl = dims.compactMap { f[$0] }.joined(separator: " · ")
        let heroLabel = hf == .future ? "Noch nicht aktiv, pro Monat" : (inc ? "Einnahmen pro Monat" : "Variable Kosten pro Monat")
        let heroSub = hf == .future ? (inc ? "Zählt ab Beginn zu deinen Einnahmen" : "Zählt ab Beginn im Budget")
            : Format.money0(sum * 12) + " " + home + " im Jahr" + (inc ? "" : " · geschätzt") + (fl.isEmpty ? "" : " – " + fl)

        let multi = data.persons.count > 1
        func row(_ e: AltEntry) -> AltRow {
            let hs = altHolders(e)
            let s = sh(e)
            let meta: [String] = inc
                ? [!e.label.isEmpty && !e.name.isEmpty ? e.name : "", multi ? hs.joined(separator: " & ") : "", s < 1 ? Format.shareText(s) : ""]
                : [multi && !hs.isEmpty ? hs.joined(separator: " & ") : "", s < 1 ? Format.shareText(s) : "", "geschätzt"]
            var tag: String? = nil
            if altAhead(e) { tag = "ab " + Format.fmtShort(e.start) } else if altOver(e) { tag = "beendet " + Format.fmtShort(e.end) } else if !inc, let en = e.end { tag = "bis " + Format.fmtShort(en) }
            let title = e.income?.title ?? e.variable?.title ?? ""
            let amt = e.income.map { curPrice($0) } ?? e.variable?.amount ?? 0
            let sub: String? = inc ? (e.cycle != 1 ? (Format.incomeCycleTexts[e.cycle] ?? "") : nil) : "pro Monat"
            return AltRow(id: e.id, title: title, meta: meta.filter { !$0.isEmpty }.joined(separator: " · "), tag: tag,
                          amount: amt, currency: e.currency, sub: sub, ended: altOver(e))
        }

        var out = AltListContent(isEmpty: all.isEmpty,
                                 emptyTitle: inc ? "Noch keine Einnahmen" : "Noch keine variablen Kosten",
                                 emptyText: inc ? "Erfasse Lohn, Rente oder Nebeneinkommen mit + oben. Im Budget siehst du dann, was dir bleibt."
                                     : "Schätze schwankende Ausgaben wie Benzin oder Lebensmittel als Betrag pro Monat. Tippe oben auf +.",
                                 heroLabel: heroLabel, heroSum: sum, heroSub: heroSub, activeCount: act.count, futureCount: fut.count,
                                 status: hf, groups: [], archive: [], archiveText: "", noHits: nil, hint: nil)
        if all.isEmpty { return out }

        var L = (hf == .future ? fut : hf == .active ? act : live).filter(mq)
        let A = arc.filter(mq)
        let srt = altSort(m)
        // Gruppierung wie bei den Verträgen (Reihenfolge des ersten Auftretens)
        var order: [String] = []
        var by: [String: [AltEntry]] = [:]
        func add(_ k: String, _ e: AltEntry) {
            if by[k] == nil { order.append(k) }
            by[k, default: []].append(e)
        }
        let byAmt: (AltEntry, AltEntry) -> Bool = { self.altMon($0) * sh($0) > self.altMon($1) * sh($1) }
        var noTitle = false
        switch srt {
        case .cost:
            L = L.stableSorted(by: byAmt)
            noTitle = true
        case .name, .partner:
            let nm: (AltEntry) -> String = { e in
                srt == .partner ? (e.name.isEmpty ? e.label : e.name) : (e.label.isEmpty ? e.name : e.label)
            }
            for e in L.stableSorted(by: { Format.lessDE(nm($0), nm($1)) }) {
                let t = nm(e).trimmingCharacters(in: .whitespacesAndNewlines)
                add(t.first.map { String($0).uppercased() } ?? "#", e)
            }
        case .due:
            var nd: [UUID: Day] = [:]
            for e in L {
                if let i = e.income {
                    if i.cycle != 0 {
                        if let d = occurrences(i, from: today, to: today.addingMonths(Swift.max(13, i.cycle + 1))).first { nd[e.id] = d }
                    } else if let d = i.due { nd[e.id] = d }
                }
            }
            for e in L.stableSorted(by: { a, b in
                switch (nd[a.id], nd[b.id]) {
                case let (x?, y?): return x < y
                case (_?, nil): return true
                default: return false
                }
            }) {
                add(nd[e.id].map { Format.monthYear($0) } ?? "Ohne Zahlungstermin", e)
            }
        case .holder:
            for e in L.stableSorted(by: byAmt) {
                let hs = altHolders(e)
                add(hs.isEmpty ? "Ohne Person" : hs.joined(separator: " & "), e)
            }
        case .cat:
            for e in L.stableSorted(by: byAmt) { add(e.catKey, e) }
        }
        if noTitle {
            if !L.isEmpty { out.groups = [AltGroup(id: "cost", title: nil, sum: "", rows: L.map(row))] }
        } else {
            for k in order {
                let list = by[k] ?? []
                let gs = list.filter { !altAhead($0) }.reduce(0.0) { $0 + altMon($1) * sh($1) }
                var st = ""
                if srt == .due {
                    let t = list.reduce(0.0) { n, e in
                        n + (e.income.map { conv(curPrice($0), $0.currency) } ?? e.variable.map { conv($0.amount, $0.currency) } ?? 0) * sh(e)
                    }
                    st = Format.money(t) + " " + home
                } else if srt != .name && srt != .partner {
                    st = list.count > 1 ? Format.money(gs) + " " + home + "/Mt." : (list.allSatisfy { altAhead($0) } ? "noch nicht aktiv" : "")
                }
                out.groups.append(AltGroup(id: srt.rawValue + "-" + k, title: k, sum: st, rows: list.map(row)))
            }
        }
        if L.isEmpty {
            out.noHits = q.isEmpty ? "Mit diesem Filter gibt es keinen Eintrag." : "Für «" + search.trimmingCharacters(in: .whitespacesAndNewlines) + "» gibt es keinen Eintrag."
        }
        out.archive = A.map(row)
        if !A.isEmpty {
            out.archiveText = "\(A.count)" + (inc ? (A.count == 1 ? " beendete Einnahme" : " beendete Einnahmen") : " beendet")
        }
        if !inc && !L.isEmpty { out.hint = "Geschätzt, keine einzelnen Ausgaben. Im Budget vom verfügbaren Betrag abgezogen." }
        return out
    }

    /// Werte einer Filterdimension aus allen Einträgen (auch beendeten), alphabetisch (Web `openAltPick`).
    public func altFilterValues(_ m: ListMode, _ d: AltDimension) -> [AltFilterValue] {
        var cnt: [String: Int] = [:]
        var act: [String: Int] = [:]
        var keys: [String] = []
        for e in altEntries(m) {
            for k in altKeys(e, d) where !k.isEmpty {
                if cnt[k] == nil { keys.append(k) }
                cnt[k, default: 0] += 1
                if !altOver(e) { act[k, default: 0] += 1 }
            }
        }
        let one = m == .incomes ? ("aktive Einnahme", "aktive Einnahmen") : ("aktiver Eintrag", "aktive Einträge")
        return keys.stableSorted { Format.lessDE($0, $1) }.map { k in
            let a = act[k] ?? 0
            return AltFilterValue(key: k, detail: a > 0 ? "\(a) " + (a == 1 ? one.0 : one.1) : "nur beendete")
        }
    }
}
