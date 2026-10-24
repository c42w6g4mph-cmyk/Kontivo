import Foundation

// MARK: - Zusammenführen: Diff, Einfügen/Entfernen, Reihenfolgen, Doppelte

/// Vergleich zweier Stände je Entität (per `Equatable`/`Hashable`). Grundlage, um lokale Änderungen zu erkennen,
/// ohne jede Fachaktion anzupassen.
public enum SyncDiff {
    /// Geänderte (neue oder veränderte) und entfernte Datensätze von `old` nach `new`. Einstellungen zählen nur, wenn sich ein
    /// abgeglichenes Feld oder die Reihenfolge der Kategorien/Personen ändert. Dateien siehe `SyncCore.captureFiles`.
    public static func diff(old: AppData, new: AppData) -> (save: [SyncKey], delete: [SyncKey]) {
        var save: [SyncKey] = []
        var del: [SyncKey] = []
        func compare<T: Identifiable & Equatable>(_ kind: SyncKind, _ a: [T], _ b: [T]) where T.ID == UUID {
            var before: [UUID: T] = [:]
            for x in a { before[x.id] = x }
            var seen = Set<UUID>()
            for x in b {
                seen.insert(x.id)
                if before[x.id] != x { save.append(SyncKey(kind, x.id)) }
            }
            for x in a where !seen.contains(x.id) { del.append(SyncKey(kind, x.id)) }
        }
        if SyncSettings(old) != SyncSettings(new) { save.append(.settings) }
        compare(.person, old.persons, new.persons)
        compare(.category, old.categories, new.categories)
        compare(.partner, old.partners, new.partners)
        compare(.contract, old.contracts, new.contracts)
        compare(.income, old.incomes, new.incomes)
        compare(.variable, old.variableCosts, new.variableCosts)
        return (save, del)
    }
}

/// Weiterleitungen zusammengeführter Entitäten (Doppelte nach dem Vereinigen): alte ID → behaltene ID.
/// Später eintreffende Verträge/Einnahmen, die noch auf die alte ID zeigen, werden umgebogen.
struct SyncAliases {
    var person: [UUID: UUID] = [:]
    var category: [UUID: UUID] = [:]
    var partner: [UUID: UUID] = [:]

    init(_ map: [String: String]) {
        for (from, to) in map {
            guard let f = SyncKey(recordName: from), let t = SyncKey(recordName: to), f.kind == t.kind,
                  let fu = f.uuid, let tu = t.uuid else { continue }
            switch f.kind {
            case .person: person[fu] = tu
            case .category: category[fu] = tu
            case .partner: partner[fu] = tu
            default: break
            }
        }
    }

    var isEmpty: Bool { person.isEmpty && category.isEmpty && partner.isEmpty }

    static func resolve(_ id: UUID, _ m: [UUID: UUID]) -> UUID {
        var cur = id
        var n = 0
        while let next = m[cur], next != cur, n < 16 {
            cur = next
            n += 1
        }
        return cur
    }

    /// Verweise umbiegen. Rückgabe: Entität und ob sich etwas geändert hat.
    func rewrite(_ e: SyncEntity) -> (SyncEntity, Bool) {
        if isEmpty { return (e, false) }
        switch e {
        case .contract(let c):
            var n = c
            if let cid = c.categoryID { n.categoryID = SyncAliases.resolve(cid, category) }
            if let pid = c.partnerID { n.partnerID = SyncAliases.resolve(pid, partner) }
            var holders: [UUID] = []
            for h in c.holderIDs {
                let r = SyncAliases.resolve(h, person)
                if !holders.contains(r) { holders.append(r) }
            }
            if holders != c.holderIDs {
                // Wie `mergePerson`: fallen zwei Inhaber zusammen, gilt wieder «gleich verteilt»
                n.split = holders.count == c.holderIDs.count
                    ? c.split.map { SplitShare(personID: SyncAliases.resolve($0.personID, person), percent: $0.percent) }
                    : []
                n.holderIDs = holders
            }
            return (.contract(n), n != c)
        case .income(let i):
            var n = i
            if let h = i.holderID { n.holderID = SyncAliases.resolve(h, person) }
            return (.income(n), n != i)
        case .variable(let v):
            var n = v
            var holders: [UUID] = []
            for h in v.holderIDs {
                let r = SyncAliases.resolve(h, person)
                if !holders.contains(r) { holders.append(r) }
            }
            n.holderIDs = holders
            return (.variable(n), n != v)
        case .person(let p):
            var n = p
            if let s = p.sameAddressAs {
                let r = SyncAliases.resolve(s, person)
                n.sameAddressAs = r == p.id ? nil : r
            }
            return (.person(n), n != p)
        case .settings(let s):
            var n = s
            n.lastHolderIDs = SyncSettings.unique(s.lastHolderIDs.map { SyncAliases.resolve($0, person) })
            n.personOrder = SyncSettings.unique(s.personOrder.map { SyncAliases.resolve($0, person) })
            n.categoryOrder = SyncSettings.unique(s.categoryOrder.map { SyncAliases.resolve($0, category) })
            return (.settings(n), n != s)
        case .category, .partner:
            return (e, false)
        }
    }
}

public enum SyncMerge {
    // MARK: Unberührtes Gerät

    /// Gerät ohne eigene Daten: keine Verträge, Einnahmen und Vertragspartner, nur Standardkategorien (jede Art höchstens
    /// einmal, keine eigenen), höchstens eine Person ohne Absender, Unterschrift und Bild. Name und Hauptwährung aus der
    /// Einführung zählen nicht als eigene Daten. Ein solches Gerät übernimmt beim ersten Abgleich die iCloud-Daten,
    /// statt seine Standarddaten hochzuladen (keine doppelte «Ich» und keine doppelten Kategorien).
    public static func isUntouched(_ d: AppData) -> Bool {
        guard d.contracts.isEmpty, d.incomes.isEmpty, d.variableCosts.isEmpty, d.partners.isEmpty, d.persons.count <= 1 else { return false }
        if let p = d.persons.first {
            if !p.sender.isEmpty || p.sameAddressAs != nil || p.signatureJPEG != nil || p.avatarID != nil { return false }
        }
        var kinds = Set<CategoryKind>()
        for c in d.categories {
            guard let k = c.kind, kinds.insert(k).inserted else { return false }
        }
        return true
    }

    // MARK: Einfügen und Entfernen

    /// Neue Entitäten, die nach dem Anwenden angehängt werden (Reihenfolge siehe `appendNew`).
    struct NewItems {
        var persons: [Person] = []
        var categories: [Category] = []
        var partners: [Partner] = []
        var contracts: [Contract] = []
        var incomes: [Income] = []
        var variables: [VariableCost] = []
    }

    /// Entität ersetzen (gleiche Stelle) oder für das Anhängen vormerken.
    static func upsert(_ e: SyncEntity, into d: inout AppData, new: inout NewItems) {
        switch e {
        case .settings:
            break
        case .person(let p):
            if let i = d.personIndex(p.id) { d.persons[i] = p } else if let j = new.persons.firstIndex(where: { $0.id == p.id }) { new.persons[j] = p } else { new.persons.append(p) }
        case .category(let c):
            if let i = d.categoryIndex(c.id) { d.categories[i] = c } else if let j = new.categories.firstIndex(where: { $0.id == c.id }) { new.categories[j] = c } else { new.categories.append(c) }
        case .partner(let p):
            if let i = d.partnerIndex(p.id) { d.partners[i] = p } else if let j = new.partners.firstIndex(where: { $0.id == p.id }) { new.partners[j] = p } else { new.partners.append(p) }
        case .contract(let c):
            if let i = d.contractIndex(c.id) { d.contracts[i] = c } else if let j = new.contracts.firstIndex(where: { $0.id == c.id }) { new.contracts[j] = c } else { new.contracts.append(c) }
        case .income(let x):
            if let i = d.incomeIndex(x.id) { d.incomes[i] = x } else if let j = new.incomes.firstIndex(where: { $0.id == x.id }) { new.incomes[j] = x } else { new.incomes.append(x) }
        case .variable(let v):
            if let i = d.variableCostIndex(v.id) { d.variableCosts[i] = v } else if let j = new.variables.firstIndex(where: { $0.id == v.id }) { new.variables[j] = v } else { new.variables.append(v) }
        }
    }

    /// Neue anhängen: Verträge und Einnahmen nach Erfassungszeit, Vertragspartner nach Name (stabil auf allen Geräten);
    /// Kategorien und Personen danach nach der abgeglichenen Reihenfolge (`applyOrders`).
    static func appendNew(_ n: NewItems, to d: inout AppData) {
        d.persons += n.persons.sorted { $0.id.uuidString < $1.id.uuidString }
        d.categories += n.categories.sorted { $0.id.uuidString < $1.id.uuidString }
        d.partners += n.partners.sorted { (Partners.sameNameKey($0.name), $0.id.uuidString) < (Partners.sameNameKey($1.name), $1.id.uuidString) }
        d.contracts += n.contracts.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        d.incomes += n.incomes.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        d.variableCosts += n.variables.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    /// Entität entfernen (Einstellungen und Dateien: nichts).
    static func remove(_ key: SyncKey, from d: inout AppData) {
        guard let u = key.uuid else { return }
        switch key.kind {
        case .person: d.persons.removeAll { $0.id == u }
        case .category: d.categories.removeAll { $0.id == u }
        case .partner: d.partners.removeAll { $0.id == u }
        case .contract: d.contracts.removeAll { $0.id == u }
        case .income: d.incomes.removeAll { $0.id == u }
        case .variable: d.variableCosts.removeAll { $0.id == u }
        case .settings, .file: break
        }
    }

    // MARK: Reihenfolgen

    /// Kategorien und Personen nach der abgeglichenen Reihenfolge; nicht aufgeführte bleiben in ihrer Folge am Ende.
    public static func applyOrders(_ d: inout AppData, settings: SyncSettings?) {
        guard let s = settings else { return }
        d.categories = ordered(d.categories, by: s.categoryOrder)
        d.persons = ordered(d.persons, by: s.personOrder)
    }

    static func ordered<T: Identifiable>(_ items: [T], by order: [UUID]) -> [T] where T.ID == UUID {
        var rank: [UUID: Int] = [:]
        for (i, id) in order.enumerated() where rank[id] == nil { rank[id] = i }
        var known: [(Int, T)] = []
        var unknown: [T] = []
        for x in items {
            if let r = rank[x.id] { known.append((r, x)) } else { unknown.append(x) }
        }
        return known.sorted { $0.0 < $1.0 }.map { $0.1 } + unknown
    }

    // MARK: Doppelte zusammenführen

    /// Ergebnis einer Zusammenführung: `from` ist in `into` aufgegangen.
    public struct Merge: Hashable, Sendable {
        public var from: SyncKey
        public var into: SyncKey
    }

    /// Doppelte nach dem Vereinigen zweier Geräte zusammenführen (lokal entstehen sie nicht: Namen sind eindeutig):
    /// Standardkategorien gleicher Art, Kategorien, Personen und Vertragspartner gleichen Namens. Behalten wird immer die
    /// kleinste ID – so entscheiden alle Geräte gleich – an der vordersten Stelle der Gruppe. Verweise in Verträgen und
    /// Einnahmen werden umgebogen; Personen und Vertragspartner über die Fachaktionen (`mergePerson`, `mergePartners`).
    @discardableResult
    public static func dedupe(_ d: inout AppData) -> [Merge] {
        var out: [Merge] = []
        // 1) Standardkategorien gleicher Art. «Steuern …» kann auch eine eigene Kategorie sein (Namensregel): dort nur die
        //    mit dem Standardsymbol.
        for kind in CategoryKind.allCases {
            let group = d.categories.filter { c in
                c.kind == kind && (kind != .taxes || Category.standardKinds[c.icon] == .taxes)
            }
            if group.count > 1 { out += mergeCategories(group.map { $0.id }, &d) }
        }
        // 2) Kategorien gleichen Namens (eigene; gleiche Art bzw. ohne Art)
        let byName = Dictionary(grouping: d.categories) { nameKey($0.name) }
        for name in byName.keys.sorted() where !name.isEmpty {
            guard let group = byName[name], group.count > 1 else { continue }
            let keep = group.min { a, b in (a.kind == nil ? 1 : 0, a.id.uuidString) < (b.kind == nil ? 1 : 0, b.id.uuidString) }!
            let ids = group.filter { $0.kind == nil || $0.kind == keep.kind }.map { $0.id }
            if ids.count > 1 { out += mergeCategories(ids, &d, keep: keep.id) }
        }
        // 3) Personen gleichen Namens (z.B. «Ich» auf beiden Geräten)
        let persons = Dictionary(grouping: d.persons) { nameKey($0.name) }
        for name in persons.keys.sorted() where !name.isEmpty {
            guard let group = persons[name], group.count > 1 else { continue }
            let ids = group.map { $0.id }.sorted { $0.uuidString < $1.uuidString }
            let keep = ids[0]
            let firstPos = d.persons.firstIndex { ids.contains($0.id) } ?? 0
            for from in ids.dropFirst() {
                d.mergePerson(from, into: keep)
                out.append(Merge(from: SyncKey(.person, from), into: SyncKey(.person, keep)))
            }
            if let i = d.personIndex(keep), i != firstPos {
                let p = d.persons.remove(at: i)
                d.persons.insert(p, at: min(firstPos, d.persons.count))
            }
        }
        // 4) Vertragspartner gleichen Namens
        let partners = Dictionary(grouping: d.partners) { Partners.sameNameKey($0.name) }
        for name in partners.keys.sorted() where !name.isEmpty {
            guard let group = partners[name], group.count > 1 else { continue }
            let ids = group.map { $0.id }.sorted { $0.uuidString < $1.uuidString }
            d.mergePartners(Array(ids.dropFirst()), into: ids[0])
            for from in ids.dropFirst() { out.append(Merge(from: SyncKey(.partner, from), into: SyncKey(.partner, ids[0]))) }
        }
        return out
    }

    /// Kategorien `ids` zu einer zusammenführen (Standard: kleinste ID), an der vordersten Stelle der Gruppe.
    static func mergeCategories(_ ids: [UUID], _ d: inout AppData, keep: UUID? = nil) -> [Merge] {
        let set = Set(ids)
        guard set.count > 1, let target = keep ?? ids.min(by: { $0.uuidString < $1.uuidString }),
              let kept = d.category(target), let firstPos = d.categories.firstIndex(where: { set.contains($0.id) }) else { return [] }
        for i in d.contracts.indices {
            if let c = d.contracts[i].categoryID, set.contains(c), c != target { d.contracts[i].categoryID = target }
        }
        d.categories.removeAll { set.contains($0.id) }
        d.categories.insert(kept, at: min(firstPos, d.categories.count))
        return ids.filter { $0 != target }.sorted { $0.uuidString < $1.uuidString }
            .map { Merge(from: SyncKey(.category, $0), into: SyncKey(.category, target)) }
    }

    static func nameKey(_ s: String) -> String {
        Format.collapseSpaces(s).lowercased()
    }

    // MARK: Mindestbestand

    /// Nach einem vollständigen Abruf: mindestens eine Person und die Kategorie «Sonstiges» (Fachregeln brauchen sie).
    /// Gibt true zurück, wenn etwas ergänzt wurde.
    @discardableResult
    public static func repair(_ d: inout AppData) -> Bool {
        var changed = false
        if d.persons.isEmpty {
            d.persons.append(Person(name: "Ich"))
            changed = true
        }
        if d.categories.isEmpty {
            d.categories = Category.standard()
            changed = true
        } else if !d.categories.contains(where: { $0.kind == .other }) {
            if let std = Category.standard().first(where: { $0.kind == .other }) {
                d.categories.append(std)
                changed = true
            }
        }
        return changed
    }
}
