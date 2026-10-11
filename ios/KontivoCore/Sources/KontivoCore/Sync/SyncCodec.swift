import Foundation

// MARK: - Kodierung Entität ↔ Nutzlast

/// Eine dekodierte Entität aus einem Datensatz.
public enum SyncEntity: Hashable, Sendable {
    case settings(SyncSettings)
    case person(Person)
    case category(Category)
    case partner(Partner)
    case contract(Contract)
    case income(Income)
}

/// Kodierung für den Abgleich: JSON mit sortierten Schlüsseln (stabil), Zeitpunkte als ganze Millisekunden (stabil über
/// beliebig viele Rundläufe), Binärdaten Base64. Gelesen wird mit `KontivoJSON` (wie `data.json`, fehlende Felder → Standard).
public enum SyncCodec {
    /// Formatversion der Nutzlast. Neuere Felder einer späteren Version gehen beim Lesen verloren, bis diese App aktualisiert ist.
    public static let formatVersion = 1

    public static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dataEncodingStrategy = .base64
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(Int64((date.timeIntervalSince1970 * 1000).rounded()))
        }
        return e
    }

    public static func encode<T: Encodable>(_ value: T, encoder: JSONEncoder? = nil) -> Data? {
        try? (encoder ?? makeEncoder()).encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? KontivoJSON.makeDecoder().decode(type, from: data)
    }

    /// Prüfsumme der Nutzlast (FNV-1a, 64 Bit, hex). Erkennt Änderungen; keine Sicherheitsfunktion.
    public static func digest(_ data: Data) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in data {
            h ^= UInt64(b)
            h = h &* 0x0000_0100_0000_01B3
        }
        return String(h, radix: 16)
    }

    // MARK: Schlüssel und Nutzlast je Entität

    /// Alle Schlüssel der Daten (Einstellungen und Entitäten, ohne Dateien).
    public static func keys(of d: AppData) -> [SyncKey] {
        var out: [SyncKey] = [.settings]
        out += d.persons.map { SyncKey(.person, $0.id) }
        out += d.categories.map { SyncKey(.category, $0.id) }
        out += d.partners.map { SyncKey(.partner, $0.id) }
        out += d.contracts.map { SyncKey(.contract, $0.id) }
        out += d.incomes.map { SyncKey(.income, $0.id) }
        return out
    }

    /// Nutzlast der Entität zu `key` (nil = gibt es nicht, Dateien immer nil).
    /// Einstellungen: `SyncSettings(d, base: settingsBase)`.
    public static func payload(_ key: SyncKey, in d: AppData, settingsBase: SyncSettings?, encoder: JSONEncoder? = nil) -> Data? {
        let enc = encoder ?? makeEncoder()
        switch key.kind {
        case .settings:
            return encode(SyncSettings(d, base: settingsBase), encoder: enc)
        case .file:
            return nil
        case .person:
            guard let u = key.uuid, let p = d.person(u) else { return nil }
            return encode(p, encoder: enc)
        case .category:
            guard let u = key.uuid, let c = d.category(u) else { return nil }
            return encode(c, encoder: enc)
        case .partner:
            guard let u = key.uuid, let p = d.partner(u) else { return nil }
            return encode(p, encoder: enc)
        case .contract:
            guard let u = key.uuid, let c = d.contract(u) else { return nil }
            return encode(c, encoder: enc)
        case .income:
            guard let u = key.uuid, let i = d.income(u) else { return nil }
            return encode(i, encoder: enc)
        }
    }

    /// Nutzlast einer Entität
    public static func payload(of e: SyncEntity, encoder: JSONEncoder? = nil) -> Data? {
        let enc = encoder ?? makeEncoder()
        switch e {
        case .settings(let s): return encode(s, encoder: enc)
        case .person(let p): return encode(p, encoder: enc)
        case .category(let c): return encode(c, encoder: enc)
        case .partner(let p): return encode(p, encoder: enc)
        case .contract(let c): return encode(c, encoder: enc)
        case .income(let i): return encode(i, encoder: enc)
        }
    }

    /// Datensatz → Entität. nil bei Dateien, unlesbarer Nutzlast oder wenn die ID in der Nutzlast nicht zum Schlüssel passt.
    public static func decodeEntity(_ r: SyncRecord) -> SyncEntity? {
        let k = r.key
        switch k.kind {
        case .file:
            return nil
        case .settings:
            return decode(SyncSettings.self, from: r.payload).map { .settings($0) }
        case .person:
            guard let p = decode(Person.self, from: r.payload), p.id.uuidString == k.id else { return nil }
            return .person(p)
        case .category:
            guard let c = decode(Category.self, from: r.payload), c.id.uuidString == k.id else { return nil }
            return .category(c)
        case .partner:
            guard let p = decode(Partner.self, from: r.payload), p.id.uuidString == k.id else { return nil }
            return .partner(p)
        case .contract:
            guard let c = decode(Contract.self, from: r.payload), c.id.uuidString == k.id else { return nil }
            return .contract(c)
        case .income:
            guard let i = decode(Income.self, from: r.payload), i.id.uuidString == k.id else { return nil }
            return .income(i)
        }
    }

    /// Datensatz einer Entität (für Tests und den In-Memory-Server)
    public static func record(_ key: SyncKey, in d: AppData, settingsBase: SyncSettings? = nil, modifiedAt: Date) -> SyncRecord? {
        payload(key, in: d, settingsBase: settingsBase).map { SyncRecord(key: key, payload: $0, modifiedAt: modifiedAt) }
    }
}

// MARK: - Abgeglichene Einstellungen

/// Die Einstellungen, die auf allen Geräten gleich sein sollen (ein Datensatz «settings.main»).
///
/// Abgeglichen: Hauptwährung und Sortierung (gehören zu den Daten, Summen sollen überall gleich sein), Reihenfolge der
/// Kategorien und Personen (Anzeige), ignorierte Datenqualitäts-Hinweise und «Ohne Logo» (bewusste Entscheide),
/// gelernte Kontoauszug-Korrekturen und ausgeblendete Vorschläge (gelten für jeden Import), Quartals-Check erledigt/
/// verschoben (sonst fragt jedes Gerät erneut), zuletzt gewählte Personen (Vorschlag im Formular).
/// Nicht abgeglichen: Wechselkurse (jedes Gerät lädt selbst), Darstellung hell/dunkel (pro Gerät), Einführung gesehen,
/// Datenversion; Erinnerungen und App-Sperre liegen ohnehin in UserDefaults.
public struct SyncSettings: Codable, Hashable, Sendable {
    public var homeCurrency: Currency
    public var sort: ContractSort
    public var categoryOrder: [UUID]
    public var personOrder: [UUID]
    public var lastHolderIDs: [UUID]
    public var qualityIgnored: [String]
    public var logoSkip: [String]
    public var bankIgn: [String]
    public var bankAlias: [String: BankAlias]
    public var lastReview: Day?
    public var reviewSnooze: Day?

    /// Aus den Daten. `base`: zuletzt abgeglichene Fassung – ihre Reihenfolgen bleiben, solange die lokale Reihenfolge dazu
    /// passt (fehlende, noch nicht eingetroffene Einträge gelten nicht als Änderung).
    public init(_ d: AppData, base: SyncSettings? = nil) {
        let s = d.settings
        homeCurrency = s.homeCurrency
        sort = s.sort
        categoryOrder = SyncSettings.order(d.categories.map { $0.id }, base: base?.categoryOrder)
        personOrder = SyncSettings.order(d.persons.map { $0.id }, base: base?.personOrder)
        lastHolderIDs = s.lastHolderIDs
        qualityIgnored = s.qualityIgnored
        logoSkip = s.logoSkip
        bankIgn = s.bankIgn
        bankAlias = s.bankAlias
        lastReview = s.lastReview
        reviewSnooze = s.reviewSnooze
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        homeCurrency = c.value(.homeCurrency, Currency.CHF)
        sort = c.value(.sort, ContractSort.category)
        categoryOrder = c.lossyArray(.categoryOrder)
        personOrder = c.lossyArray(.personOrder)
        lastHolderIDs = c.lossyArray(.lastHolderIDs)
        qualityIgnored = c.lossyArray(.qualityIgnored)
        logoSkip = c.lossyArray(.logoSkip)
        bankIgn = c.lossyArray(.bankIgn)
        bankAlias = c.value(.bankAlias, [String: BankAlias]())
        lastReview = c.optional(.lastReview)
        reviewSnooze = c.optional(.reviewSnooze)
    }

    /// Abgeglichene Felder übernehmen (Reihenfolgen: `SyncMerge.applyOrders`). Darstellung, Kurse usw. bleiben.
    public func apply(to s: inout Settings) {
        s.homeCurrency = homeCurrency
        s.sort = sort
        s.lastHolderIDs = lastHolderIDs
        s.qualityIgnored = qualityIgnored
        s.logoSkip = logoSkip
        s.bankIgn = bankIgn
        s.bankAlias = bankAlias
        s.lastReview = lastReview
        s.reviewSnooze = reviewSnooze
    }

    /// Lokale Reihenfolge oder – wenn sie zur bekannten passt – die bekannte (mit noch fehlenden Einträgen).
    static func order(_ local: [UUID], base: [UUID]?) -> [UUID] {
        guard let base else { return local }
        let baseSet = Set(base)
        if local.contains(where: { !baseSet.contains($0) }) { return local }
        let localSet = Set(local)
        return base.filter { localSet.contains($0) } == local ? base : local
    }

    /// Beim ersten Vereinigen zweier Datenbestände: Listen vereinigen, Reihenfolgen entfernt zuerst (lokale Neue hinten),
    /// Einzelwerte von der neueren Seite, Quartals-Check jeweils das spätere Datum.
    static func union(local: SyncSettings, remote: SyncSettings, preferLocal: Bool) -> SyncSettings {
        var m = preferLocal ? local : remote
        m.qualityIgnored = unique(remote.qualityIgnored + local.qualityIgnored)
        m.logoSkip = unique(remote.logoSkip + local.logoSkip)
        m.bankIgn = unique(remote.bankIgn + local.bankIgn)
        m.bankAlias = remote.bankAlias.merging(local.bankAlias) { r, l in preferLocal ? l : r }
        m.lastReview = later(local.lastReview, remote.lastReview)
        m.reviewSnooze = later(local.reviewSnooze, remote.reviewSnooze)
        m.categoryOrder = unique(remote.categoryOrder + local.categoryOrder)
        m.personOrder = unique(remote.personOrder + local.personOrder)
        return m
    }

    /// Beide Geräte haben die Einstellungen geändert (seit `base`, der letzten Fassung in iCloud): Feld für Feld zusammenführen.
    /// Lokal geänderte Felder gewinnen, sonst gilt iCloud; bei Listen werden lokale Ergänzungen und Entfernungen übernommen.
    static func merge(base: SyncSettings, local: SyncSettings, remote: SyncSettings) -> SyncSettings {
        var m = remote
        if local.homeCurrency != base.homeCurrency { m.homeCurrency = local.homeCurrency }
        if local.sort != base.sort { m.sort = local.sort }
        if local.categoryOrder != base.categoryOrder { m.categoryOrder = local.categoryOrder }
        if local.personOrder != base.personOrder { m.personOrder = local.personOrder }
        if local.lastHolderIDs != base.lastHolderIDs { m.lastHolderIDs = local.lastHolderIDs }
        if local.lastReview != base.lastReview { m.lastReview = local.lastReview }
        if local.reviewSnooze != base.reviewSnooze { m.reviewSnooze = local.reviewSnooze }
        m.qualityIgnored = mergeList(base: base.qualityIgnored, local: local.qualityIgnored, remote: remote.qualityIgnored)
        m.logoSkip = mergeList(base: base.logoSkip, local: local.logoSkip, remote: remote.logoSkip)
        m.bankIgn = mergeList(base: base.bankIgn, local: local.bankIgn, remote: remote.bankIgn)
        for k in Set(base.bankAlias.keys).union(local.bankAlias.keys) where local.bankAlias[k] != base.bankAlias[k] {
            m.bankAlias[k] = local.bankAlias[k]
        }
        return m
    }

    static func mergeList(base: [String], local: [String], remote: [String]) -> [String] {
        let b = Set(base)
        let l = Set(local)
        let removed = b.subtracting(l)
        return unique(remote.filter { !removed.contains($0) } + local.filter { !b.contains($0) })
    }

    static func unique<T: Hashable>(_ a: [T]) -> [T] {
        var seen = Set<T>()
        return a.filter { seen.insert($0).inserted }
    }

    static func later(_ a: Day?, _ b: Day?) -> Day? {
        guard let a else { return b }
        guard let b else { return a }
        return max(a, b)
    }
}
