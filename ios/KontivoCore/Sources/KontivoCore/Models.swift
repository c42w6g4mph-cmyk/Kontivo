import Foundation

// MARK: - Aufzählungen

public enum Currency: String, Codable, CaseIterable, Hashable, Sendable {
    case CHF, EUR, USD, GBP, TRY

    /// Anzeigename wie in der Einführung («Euro», «Franken» …).
    public var displayName: String {
        switch self {
        case .EUR: return "Euro"
        case .CHF: return "Franken"
        case .USD: return "US-Dollar"
        case .GBP: return "Pfund"
        case .TRY: return "Lira"
        }
    }
}

/// Einheit der Kündigungsfrist. `dayOfMonth` = «bis zum n. des Monats».
public enum NoticeUnit: String, Codable, CaseIterable, Hashable, Sendable {
    case months = "m", weeks = "w", days = "d", dayOfMonth = "k"
}

/// Kündbar per (unbefristete Verträge).
public enum CancelTerm: String, Codable, CaseIterable, Hashable, Sendable {
    case anytime = "", period = "p", monthEnd = "m", quarterEnd = "q", halfYearEnd = "h", yearEnd = "y", contractYear = "a"
}

/// Kündigungsweg am Vertrag (Web: Text in `cancF`).
public enum CancelChannel: String, Codable, CaseIterable, Hashable, Sendable {
    case online, email, letter, registered

    /// Text wie in der Web-App («Online / Kundenkonto», «E-Mail», «Brief», «Einschreiben»).
    public var webText: String {
        switch self {
        case .online: return "Online / Kundenkonto"
        case .email: return "E-Mail"
        case .letter: return "Brief"
        case .registered: return "Einschreiben"
        }
    }

    /// Umkehrung von `webText` (leer oder unbekannt → nil).
    public init?(webText: String) {
        switch webText.trimmingCharacters(in: .whitespaces) {
        case "Online / Kundenkonto": self = .online
        case "E-Mail": self = .email
        case "Brief": self = .letter
        case "Einschreiben": self = .registered
        default: return nil
        }
    }
}

/// Ergebnis von `cancVia()`: wie wird gekündigt.
public enum CancelVia: String, Hashable, Sendable {
    case online, mail, post, none

    /// Wert wie in der Web-App ("online" | "mail" | "post" | "").
    public var jsValue: String { self == .none ? "" : rawValue }
}

/// Fachliche Art einer Standardkategorie. Bleibt beim Umbenennen erhalten
/// (taxes → keine Frist, insurance → Brief, housing → Miete-Heuristik).
public enum CategoryKind: String, Codable, CaseIterable, Hashable, Sendable {
    case housing, energy, insurance, health, telecom, media, mobility, family, leisure, taxes, finance, other
}

/// Art einer Einnahme (fest, nicht verwaltbar). `sonstiges` entspricht «Sonstiges» der Web-App.
public enum IncomeKind: String, Codable, CaseIterable, Hashable, Sendable {
    case lohn, nebeneinkommen, bonus, kapitalertraege, vermietung, rente, sonstiges

    public var displayName: String {
        switch self {
        case .lohn: return "Lohn"
        case .nebeneinkommen: return "Nebeneinkommen"
        case .bonus: return "Bonus"
        case .kapitalertraege: return "Kapitalerträge"
        case .vermietung: return "Vermietung"
        case .rente: return "Rente"
        case .sonstiges: return "Sonstiges"
        }
    }

    /// Farbe wie CAT_COLOR der Web-App.
    public var colorHex: String {
        switch self {
        case .lohn: return "#2E6A4E"
        case .nebeneinkommen: return "#0E5A5E"
        case .bonus: return "#8A6A1F"
        case .kapitalertraege: return "#1F4E8C"
        case .vermietung: return "#6B4E9E"
        case .rente: return "#B0562A"
        case .sonstiges: return "#5F666E"
        }
    }

    /// Symbol-Schlüssel wie CAT_ICON der Web-App (= Anzeigename).
    public var icon: String { displayName }

    /// Aus dem Namen der Web-App («Lohn» … «Sonstiges»).
    public init?(webName: String) {
        guard let k = IncomeKind.allCases.first(where: { $0.displayName == webName }) else { return nil }
        self = k
    }
}

public enum ContractStatus: String, Codable, CaseIterable, Hashable, Sendable {
    /// laufend (auch gekündigt per Datum, pausiert, noch nicht begonnen)
    case active
    /// «Als gekündigt ins Archiv» (Web: status "cancelled")
    case cancelled
}

public enum Theme: String, Codable, CaseIterable, Hashable, Sendable {
    case auto, light, dark
}

public enum ContractSort: String, Codable, CaseIterable, Hashable, Sendable {
    case due, cost, partner, category, holder

    /// Wert der Web-App (`settings.sort`).
    public var webValue: String { self == .category ? "cat" : rawValue }

    public init(webValue: String) {
        switch webValue {
        case "due": self = .due
        case "cost": self = .cost
        case "partner": self = .partner
        case "holder": self = .holder
        default: self = .category
        }
    }

    /// Beschriftung «Sortiert / …»
    public var shortLabel: String {
        switch self {
        case .category: return "Kategorie"
        case .cost: return "Kosten"
        case .partner: return "Vertragspartner"
        case .due: return "Fälligkeit"
        case .holder: return "Inhaber"
        }
    }

    /// Option im Auswahlblatt «Sortieren nach»
    public var optionLabel: String {
        switch self {
        case .due: return "Fälligkeit"
        case .cost: return "Kosten, höchste zuerst"
        case .partner: return "Vertragspartner, A–Z"
        case .category: return "Kategorie"
        case .holder: return "Inhaber"
        }
    }

    /// Reihenfolge im Auswahlblatt
    public static let pickerOrder: [ContractSort] = [.due, .cost, .partner, .category, .holder]
}

// MARK: - Adressen

/// Postadresse eines Vertragspartners. Leere Felder = "".
public struct PostalAddress: Codable, Hashable, Sendable {
    public var company: String
    public var extra: String
    public var street: String
    public var zip: String
    public var city: String
    public var country: String

    public init(company: String = "", extra: String = "", street: String = "", zip: String = "", city: String = "", country: String = "") {
        self.company = company
        self.extra = extra
        self.street = street
        self.zip = zip
        self.city = city
        self.country = country
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        company = c.value(.company, "")
        extra = c.value(.extra, "")
        street = c.value(.street, "")
        zip = c.value(.zip, "")
        city = c.value(.city, "")
        country = c.value(.country, "")
    }

    /// Alle Felder leer?
    public var isEmpty: Bool { lines.isEmpty }

    /// Zeilen wie `addrJoin`: Firma, Zusatz, Strasse, «PLZ Ort», Land (leere weg).
    public var lines: [String] {
        let zipCity = [zip, city].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        return [company, extra, street, zipCity, country]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Mehrzeiliger Text (wie `c.addr` der Web-App).
    public var text: String { lines.joined(separator: "\n") }
}

/// Absender einer Person (Kündigungsschreiben).
public struct SenderAddress: Codable, Hashable, Sendable {
    public var first: String
    public var last: String
    public var street: String
    public var zip: String
    public var city: String
    public var country: String

    public init(first: String = "", last: String = "", street: String = "", zip: String = "", city: String = "", country: String = "") {
        self.first = first
        self.last = last
        self.street = street
        self.zip = zip
        self.city = city
        self.country = country
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        first = c.value(.first, "")
        last = c.value(.last, "")
        street = c.value(.street, "")
        zip = c.value(.zip, "")
        city = c.value(.city, "")
        country = c.value(.country, "")
    }

    /// Alle Felder leer?
    public var isEmpty: Bool {
        [first, last, street, zip, city, country].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// «Vorname Nachname» (leer, wenn beides fehlt)
    public var fullName: String {
        [first, last].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Adresszeilen wie `sndAddr`: [Strasse, «PLZ Ort», Land], leere weg.
    public var addressLines: [String] {
        let zipCity = [zip, city].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        return [street.trimmingCharacters(in: .whitespaces), zipCity, country.trimmingCharacters(in: .whitespaces)].filter { !$0.isEmpty }
    }

    /// Vollständig für einen Brief (`sndOk`): (Vor- oder Nachname) und Strasse und Ort.
    public var isComplete: Bool {
        let t = { (s: String) in !s.trimmingCharacters(in: .whitespaces).isEmpty }
        return (t(first) || t(last)) && t(street) && t(city)
    }

    /// Mit der Adresse (Strasse, PLZ, Ort, Land) einer anderen Person, Name bleibt.
    public func withAddress(of other: SenderAddress) -> SenderAddress {
        SenderAddress(first: first, last: last, street: other.street, zip: other.zip, city: other.city, country: other.country)
    }
}

// MARK: - Stammdaten

/// Person im Haushalt (Inhaber, Empfänger von Einnahmen, Absender von Kündigungen).
public struct Person: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var sender: SenderAddress
    /// «Gleiche Adresse wie»: Strasse, PLZ, Ort, Land kommen von dieser Person (eine Stufe).
    public var sameAddressAs: UUID?
    /// Unterschrift als JPEG (weisser Grund).
    public var signatureJPEG: Data?
    /// Bild (Datei-ID im Dateispeicher).
    public var avatarID: String?

    public init(id: UUID = UUID(), name: String, sender: SenderAddress = SenderAddress(), sameAddressAs: UUID? = nil, signatureJPEG: Data? = nil, avatarID: String? = nil) {
        self.id = id
        self.name = name
        self.sender = sender
        self.sameAddressAs = sameAddressAs
        self.signatureJPEG = signatureJPEG
        self.avatarID = avatarID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        name = c.value(.name, "")
        sender = c.value(.sender, SenderAddress())
        sameAddressAs = c.optional(.sameAddressAs)
        signatureJPEG = c.optional(.signatureJPEG)
        avatarID = c.optional(.avatarID)
    }
}

/// Kategorie (Reihenfolge in `AppData.categories` = Anzeige).
public struct Category: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    /// Symbol-Schlüssel wie in der Web-App: Name einer Standardkategorie oder "tag" (Etikett).
    public var icon: String
    /// Standardkategorie (Fachregeln); eigene Kategorien nil.
    public var kind: CategoryKind?

    public init(id: UUID = UUID(), name: String, colorHex: String, icon: String = "tag", kind: CategoryKind? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
        self.kind = kind
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        name = c.value(.name, "")
        colorHex = c.value(.colorHex, Category.fallbackColor)
        icon = c.value(.icon, "tag")
        kind = c.optional(.kind)
    }

    /// Standardkategorien (CATS), Reihenfolge fix.
    public static let standardNames: [String] = ["Wohnen", "Energie & Wasser", "Versicherung", "Gesundheit", "Mobilfunk & Internet", "Abos & Medien",
                                                 "Mobilität", "Familie & Bildung", "Freizeit & Sport", "Steuern & Gebühren", "Finanzen", "Sonstiges"]

    /// Art je Standardname.
    public static let standardKinds: [String: CategoryKind] = [
        "Wohnen": .housing, "Energie & Wasser": .energy, "Versicherung": .insurance, "Gesundheit": .health,
        "Mobilfunk & Internet": .telecom, "Abos & Medien": .media, "Mobilität": .mobility, "Familie & Bildung": .family,
        "Freizeit & Sport": .leisure, "Steuern & Gebühren": .taxes, "Finanzen": .finance, "Sonstiges": .other,
    ]

    /// Farben (CAT_COLOR) der Standardkategorien und Einnahmearten.
    public static let standardColors: [String: String] = [
        "Wohnen": "#6B4E9E", "Energie & Wasser": "#B0562A", "Versicherung": "#0E5A5E", "Gesundheit": "#B03A5B",
        "Mobilfunk & Internet": "#1F4E8C", "Abos & Medien": "#A93227", "Mobilität": "#3F4A55", "Familie & Bildung": "#2F86A6",
        "Freizeit & Sport": "#2E6A4E", "Steuern & Gebühren": "#6E7B3A", "Finanzen": "#8A6A1F", "Sonstiges": "#5F666E",
        "Lohn": "#2E6A4E", "Nebeneinkommen": "#0E5A5E", "Bonus": "#8A6A1F", "Kapitalerträge": "#1F4E8C", "Vermietung": "#6B4E9E", "Rente": "#B0562A",
    ]

    /// Hash-Farben für Marken ohne Kategorie (COLORS); auch Startfarbe neuer Kategorien.
    public static let palette: [String] = ["#0E5A5E", "#A93227", "#1F4E8C", "#6B4E9E", "#8A6A1F", "#2E6A4E", "#B0562A", "#3F4A55"]

    /// Farbauswahl in der Kategorie-Bearbeitung (CE_COL).
    public static let editColors: [String] = palette + ["#B03A5B", "#2F86A6", "#6E7B3A", "#5F666E"]

    /// Symbolauswahl (CE_ICONS): die 12 Standardnamen + "tag".
    public static let iconKeys: [String] = standardNames + ["tag"]

    /// Farbe ohne Eintrag (#5F666E).
    public static let fallbackColor = "#5F666E"

    /// Alte Kategorienamen (CAT_MIG).
    public static let legacyNames: [String: String] = [
        "Energie": "Energie & Wasser", "Streaming & Software": "Abos & Medien", "Fitness & Freizeit": "Freizeit & Sport",
        "Steuern": "Steuern & Gebühren", "Kinderbetreuung": "Familie & Bildung",
    ]

    /// Art für einen Kategorienamen: Standardname → dessen Art; Name beginnt mit «Steuern» (wie `isTax` der Web-App) → taxes; sonst nil.
    public static func defaultKind(forName name: String) -> CategoryKind? {
        if let k = standardKinds[name] { return k }
        if name.lowercased().hasPrefix("steuern") { return .taxes }
        return nil
    }

    /// Art für einen neuen oder umbenannten Namen (Web `catKey` + `isTax`): Standardname → dessen Art, sofern keine andere
    /// Kategorie diese Art schon trägt; Name beginnt mit «Steuern» → taxes; sonst nil.
    public static func kind(forName name: String, among others: [Category]) -> CategoryKind? {
        if let k = standardKinds[name], !others.contains(where: { $0.kind == k }) { return k }
        return name.lowercased().hasPrefix("steuern") ? .taxes : nil
    }

    /// Art beim Übernehmen eines Web-Eintrags `{n, k}`: Fachschlüssel `k` (bleibt beim Umbenennen), sonst Standardname,
    /// solange kein anderer Eintrag diesen Schlüssel trägt (`takenKeys`), sonst «Steuern…»-Regel.
    public static func importKind(name: String, key: String, takenKeys: Set<String>) -> CategoryKind? {
        if let k = standardKinds[key] { return k }
        if let k = standardKinds[name], !takenKeys.contains(name) { return k }
        return name.lowercased().hasPrefix("steuern") ? .taxes : nil
    }

    /// Startfarbe für eine neue Kategorie bei `count` vorhandenen (COLORS[(n+3) % 8]).
    public static func newColor(existingCount count: Int) -> String {
        palette[(count + 3) % palette.count]
    }

    /// Die 12 Standardkategorien mit neuen IDs.
    public static func standard() -> [Category] {
        standardNames.map { Category(name: $0, colorHex: standardColors[$0] ?? fallbackColor, icon: $0, kind: standardKinds[$0]) }
    }
}

/// Vertragspartner (Firma). Logo und Adresse gelten für alle seine Verträge.
public struct Partner: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var web: String
    public var logoID: String?
    public var logoBg: String?
    public var address: PostalAddress

    public init(id: UUID = UUID(), name: String, web: String = "", logoID: String? = nil, logoBg: String? = nil, address: PostalAddress = PostalAddress()) {
        self.id = id
        self.name = name
        self.web = web
        self.logoID = logoID
        self.logoBg = logoBg
        self.address = address
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        name = c.value(.name, "")
        web = c.value(.web, "")
        logoID = c.optional(.logoID)
        logoBg = c.optional(.logoBg)
        address = c.value(.address, PostalAddress())
    }
}

// MARK: - Verträge und Einnahmen

/// Preisstufe ab Datum.
public struct PriceChange: Codable, Hashable, Sendable {
    public var from: Day
    public var amount: Double

    public init(from: Day, amount: Double) {
        self.from = from
        self.amount = amount
    }
}

/// Einmalige Sonderzahlung (Gutschrift negativ). Zählt nach Datum, nie in den Monatskosten.
public struct ExtraPayment: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var date: Day
    public var amount: Double
    public var note: String

    public init(id: UUID = UUID(), date: Day, amount: Double, note: String = "") {
        self.id = id
        self.date = date
        self.amount = amount
        self.note = note
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        date = try c.decode(Day.self, forKey: .date)
        amount = c.value(.amount, 0.0)
        note = c.value(.note, "")
    }
}

/// Pause [from, until) ohne Zahlungen; until nil = offen («bis du fortsetzt»).
public struct Pause: Codable, Hashable, Sendable {
    public var from: Day
    public var until: Day?

    public init(from: Day, until: Day? = nil) {
        self.from = from
        self.until = until
    }

    /// Gilt die Pause an diesem Tag?
    public func contains(_ d: Day) -> Bool {
        d >= from && (until == nil || d < until!)
    }
}

/// Anteil einer Person an einem gemeinsamen Vertrag in Prozent (Web `c.split`). Nur gültig, wenn alle Inhaber vorkommen
/// und die Summe 100 ist (`Calc.splitOf`); sonst gilt die Gleichverteilung.
public struct SplitShare: Codable, Hashable, Sendable {
    public var personID: UUID
    /// Prozent mit bis zu 4 Nachkommastellen (Web seit v82: Eingabe als Betrag auf den Rappen).
    public var percent: Double

    public init(personID: UUID, percent: Double) {
        self.personID = personID
        self.percent = percent
    }
}

/// Entscheid im Quartals-Check (Web `c.review = {v, at}`): «Brauche ich» bzw. «Weg damit» (landet in «Fristen» unter
/// «Zum Kündigen vorgemerkt»). Älter als 90 Tage gilt im nächsten Check als nicht beantwortet.
public enum ReviewVerdict: String, Codable, Hashable, Sendable {
    case keep, kill
}

public struct ContractReview: Codable, Hashable, Sendable {
    public var verdict: ReviewVerdict
    public var at: Day

    public init(verdict: ReviewVerdict, at: Day) {
        self.verdict = verdict
        self.at = at
    }
}

/// Angehängtes Dokument (Datei mit derselben ID im Dateispeicher).
public struct Attachment: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var type: String

    public init(id: String, name: String, type: String) {
        self.id = id
        self.name = name
        self.type = type
    }
}

public struct Contract: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    public var partnerID: UUID?
    public var categoryID: UUID?
    /// Anfangspreis in Vertragswährung (Preisstufen in `prices`).
    public var amount: Double
    public var currency: Currency
    /// Turnus in Monaten: 1, 2, 3, 6, 12, 24; 0 = einmalig.
    public var cycle: Int
    /// «Nächste Zahlung am» (Anker aller Zahlungstermine).
    public var due: Day?
    public var start: Day?
    /// Vertragsende (befristet); nil = unbefristet.
    public var end: Day?
    public var notice: Int
    public var noticeUnit: NoticeUnit
    /// Automatische Verlängerung in Monaten (0 = keine).
    public var renewMonths: Int
    public var cancelTerm: CancelTerm
    /// Pflichtvertrag (nur Wechsel möglich).
    public var mandatory: Bool
    /// Frist nicht beobachten.
    public var noWatch: Bool
    /// Nicht kündbar (z.B. Serafe, Rundfunkbeitrag); Steuern & Gebühren gelten automatisch als nicht kündbar (`Calc.isFixed`).
    public var noCancel: Bool
    /// Mietvertrag (Schriftform). nil = Heuristik `Letter.isRentHeuristic`.
    public var isRent: Bool?
    public var customerNo: String
    public var contractNo: String
    public var holderIDs: [UUID]
    public var payMethod: String
    public var payAccount: String
    public var cancelChannel: CancelChannel?
    public var cancelURL: String
    /// Probeabo endet am
    public var trial: Day?
    /// Probeabo behalten (= trial, wenn entschieden)
    public var trialKept: Day?
    public var tel: String
    public var mail: String
    public var note: String
    public var colorHex: String?
    /// Logo nur ohne Vertragspartner; sonst `Partner.logoID`.
    public var logoID: String?
    public var logoBg: String?
    public var prices: [PriceChange]
    public var documents: [Attachment]
    public var extras: [ExtraPayment]
    public var status: ContractStatus
    /// Datum «ins Archiv» (status cancelled)
    public var cancelledAt: Day?
    /// Gekündigt per (läuft bis)
    public var cancelPer: Day?
    /// Gekündigt am
    public var cancelledOn: Day?
    /// Für diesen Termin behalten (= termEnd)
    public var keptFor: Day?
    public var pauses: [Pause]
    public var createdAt: Date
    /// Individuelle Aufteilung (leer = gleich verteilt)
    public var split: [SplitShare]
    /// Entscheid im Quartals-Check
    public var review: ContractReview?

    public init(id: UUID = UUID(), label: String = "", partnerID: UUID? = nil, categoryID: UUID? = nil,
                amount: Double = 0, currency: Currency = .CHF, cycle: Int = 1,
                due: Day? = nil, start: Day? = nil, end: Day? = nil,
                notice: Int = 0, noticeUnit: NoticeUnit = .months, renewMonths: Int = 0, cancelTerm: CancelTerm = .anytime,
                mandatory: Bool = false, noWatch: Bool = false, noCancel: Bool = false, isRent: Bool? = nil,
                customerNo: String = "", contractNo: String = "", holderIDs: [UUID] = [],
                payMethod: String = "", payAccount: String = "", cancelChannel: CancelChannel? = nil, cancelURL: String = "",
                trial: Day? = nil, trialKept: Day? = nil,
                tel: String = "", mail: String = "", note: String = "",
                colorHex: String? = nil, logoID: String? = nil, logoBg: String? = nil,
                prices: [PriceChange] = [], documents: [Attachment] = [], extras: [ExtraPayment] = [],
                status: ContractStatus = .active, cancelledAt: Day? = nil, cancelPer: Day? = nil, cancelledOn: Day? = nil,
                keptFor: Day? = nil, pauses: [Pause] = [], createdAt: Date = Date(), split: [SplitShare] = [], review: ContractReview? = nil) {
        self.id = id
        self.label = label
        self.partnerID = partnerID
        self.categoryID = categoryID
        self.amount = amount
        self.currency = currency
        self.cycle = cycle
        self.due = due
        self.start = start
        self.end = end
        self.notice = notice
        self.noticeUnit = noticeUnit
        self.renewMonths = renewMonths
        self.cancelTerm = cancelTerm
        self.mandatory = mandatory
        self.noWatch = noWatch
        self.noCancel = noCancel
        self.isRent = isRent
        self.customerNo = customerNo
        self.contractNo = contractNo
        self.holderIDs = holderIDs
        self.payMethod = payMethod
        self.payAccount = payAccount
        self.cancelChannel = cancelChannel
        self.cancelURL = cancelURL
        self.trial = trial
        self.trialKept = trialKept
        self.tel = tel
        self.mail = mail
        self.note = note
        self.colorHex = colorHex
        self.logoID = logoID
        self.logoBg = logoBg
        self.prices = prices
        self.documents = documents
        self.extras = extras
        self.status = status
        self.cancelledAt = cancelledAt
        self.cancelPer = cancelPer
        self.cancelledOn = cancelledOn
        self.keptFor = keptFor
        self.pauses = pauses
        self.createdAt = createdAt
        self.split = split
        self.review = review
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        label = c.value(.label, "")
        partnerID = c.optional(.partnerID)
        categoryID = c.optional(.categoryID)
        amount = c.value(.amount, 0.0)
        currency = c.value(.currency, Currency.CHF)
        cycle = c.value(.cycle, 1)
        due = c.optional(.due)
        start = c.optional(.start)
        end = c.optional(.end)
        notice = c.value(.notice, 0)
        noticeUnit = c.value(.noticeUnit, NoticeUnit.months)
        renewMonths = c.value(.renewMonths, 0)
        cancelTerm = c.value(.cancelTerm, CancelTerm.anytime)
        mandatory = c.value(.mandatory, false)
        noWatch = c.value(.noWatch, false)
        noCancel = c.value(.noCancel, false)
        isRent = c.optional(.isRent)
        customerNo = c.value(.customerNo, "")
        contractNo = c.value(.contractNo, "")
        holderIDs = c.value(.holderIDs, [UUID]())
        payMethod = c.value(.payMethod, "")
        payAccount = c.value(.payAccount, "")
        cancelChannel = c.optional(.cancelChannel)
        cancelURL = c.value(.cancelURL, "")
        trial = c.optional(.trial)
        trialKept = c.optional(.trialKept)
        tel = c.value(.tel, "")
        mail = c.value(.mail, "")
        note = c.value(.note, "")
        colorHex = c.optional(.colorHex)
        logoID = c.optional(.logoID)
        logoBg = c.optional(.logoBg)
        prices = c.lossyArray(.prices)
        documents = c.lossyArray(.documents)
        extras = c.lossyArray(.extras)
        status = c.value(.status, ContractStatus.active)
        cancelledAt = c.optional(.cancelledAt)
        cancelPer = c.optional(.cancelPer)
        cancelledOn = c.optional(.cancelledOn)
        keptFor = c.optional(.keptFor)
        pauses = c.lossyArray(.pauses)
        createdAt = c.value(.createdAt, Date(timeIntervalSince1970: 0))
        split = c.lossyArray(.split)
        review = c.optional(.review)
    }

    /// Turnus für Rechnungen (JS `+c.cycle||1`).
    public var cycleForCalc: Int { cycle == 0 ? 1 : cycle }

    /// Gültige individuelle Aufteilung (Web `splitOf`): ab 2 Inhabern, jeder Inhaber mit Anteil ≥ 0, Summe 100 (±0.6). Sonst nil = gleich.
    public var validSplit: [UUID: Double]? {
        if holderIDs.count < 2 || split.isEmpty { return nil }
        var o: [UUID: Double] = [:]
        for s in split { o[s.personID] = s.percent }
        var sum = 0.0
        for h in holderIDs {
            guard let v = o[h], v >= 0 else { return nil }
            sum += v
        }
        return abs(sum - 100) < 0.6 ? o.filter { holderIDs.contains($0.key) } : nil
    }
}

public struct Income: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// Quelle (z.B. Arbeitgeber)
    public var name: String
    public var label: String
    public var kind: IncomeKind
    public var amount: Double
    public var currency: Currency
    /// 0 = einmalig, sonst Monate
    public var cycle: Int
    public var due: Day?
    public var start: Day?
    public var end: Day?
    /// Genau ein Empfänger
    public var holderID: UUID?
    public var prices: [PriceChange]
    public var note: String
    public var logoID: String?
    public var logoBg: String?
    public var colorHex: String?
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String = "", label: String = "", kind: IncomeKind = .lohn, amount: Double = 0, currency: Currency = .CHF,
                cycle: Int = 1, due: Day? = nil, start: Day? = nil, end: Day? = nil, holderID: UUID? = nil, prices: [PriceChange] = [],
                note: String = "", logoID: String? = nil, logoBg: String? = nil, colorHex: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.label = label
        self.kind = kind
        self.amount = amount
        self.currency = currency
        self.cycle = cycle
        self.due = due
        self.start = start
        self.end = end
        self.holderID = holderID
        self.prices = prices
        self.note = note
        self.logoID = logoID
        self.logoBg = logoBg
        self.colorHex = colorHex
        self.createdAt = createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, UUID())
        name = c.value(.name, "")
        label = c.value(.label, "")
        kind = c.value(.kind, IncomeKind.lohn)
        amount = c.value(.amount, 0.0)
        currency = c.value(.currency, Currency.CHF)
        cycle = c.value(.cycle, 1)
        due = c.optional(.due)
        start = c.optional(.start)
        end = c.optional(.end)
        holderID = c.optional(.holderID)
        prices = c.lossyArray(.prices)
        note = c.value(.note, "")
        logoID = c.optional(.logoID)
        logoBg = c.optional(.logoBg)
        colorHex = c.optional(.colorHex)
        createdAt = c.value(.createdAt, Date(timeIntervalSince1970: 0))
    }

    /// Titel wie `label || name || «Einnahme»`.
    public var title: String {
        if !label.isEmpty { return label }
        if !name.isEmpty { return name }
        return "Einnahme"
    }
}

// MARK: - Einstellungen und Gesamtdaten

public struct Settings: Codable, Hashable, Sendable {
    public var homeCurrency: Currency
    /// CHF pro Einheit, Schlüssel EUR/USD/GBP/TRY
    public var rates: [String: Double]
    public var rateDate: Day?
    public var rateChecked: Day?
    public var rateSource: String
    public var theme: Theme
    public var sort: ContractSort
    /// Version der gesehenen Einführung (0 = noch nie)
    public var onboarded: Int
    public var lastHolderIDs: [UUID]
    /// Ignorierte Datenqualitäts-Schlüssel («c:<id>:holder» …)
    public var qualityIgnored: [String]
    public var lastReview: Day?
    public var reviewSnooze: Day?
    public var dataVersion: Int

    /// Aktuelle Datenversion der nativen App.
    public static let currentDataVersion = 2

    public init(homeCurrency: Currency = .CHF, rates: [String: Double] = [:], rateDate: Day? = nil, rateChecked: Day? = nil, rateSource: String = "",
                theme: Theme = .auto, sort: ContractSort = .category, onboarded: Int = 0, lastHolderIDs: [UUID] = [], qualityIgnored: [String] = [],
                lastReview: Day? = nil, reviewSnooze: Day? = nil, dataVersion: Int = Settings.currentDataVersion) {
        self.homeCurrency = homeCurrency
        self.rates = rates
        self.rateDate = rateDate
        self.rateChecked = rateChecked
        self.rateSource = rateSource
        self.theme = theme
        self.sort = sort
        self.onboarded = onboarded
        self.lastHolderIDs = lastHolderIDs
        self.qualityIgnored = qualityIgnored
        self.lastReview = lastReview
        self.reviewSnooze = reviewSnooze
        self.dataVersion = dataVersion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        homeCurrency = c.value(.homeCurrency, Currency.CHF)
        rates = c.value(.rates, [String: Double]())
        rateDate = c.optional(.rateDate)
        rateChecked = c.optional(.rateChecked)
        rateSource = c.value(.rateSource, "")
        theme = c.value(.theme, Theme.auto)
        sort = c.value(.sort, ContractSort.category)
        onboarded = c.value(.onboarded, 0)
        lastHolderIDs = c.lossyArray(.lastHolderIDs)
        qualityIgnored = c.lossyArray(.qualityIgnored)
        lastReview = c.optional(.lastReview)
        reviewSnooze = c.optional(.reviewSnooze)
        dataVersion = c.value(.dataVersion, Settings.currentDataVersion)
    }
}

/// Alle Daten der App. Reihenfolgen sind Arrays (Einfügereihenfolge).
public struct AppData: Codable, Hashable, Sendable {
    public var settings: Settings
    public var persons: [Person]
    /// Reihenfolge = Anzeige
    public var categories: [Category]
    public var partners: [Partner]
    public var contracts: [Contract]
    public var incomes: [Income]

    public init(settings: Settings = Settings(), persons: [Person] = [], categories: [Category] = [], partners: [Partner] = [],
                contracts: [Contract] = [], incomes: [Income] = []) {
        self.settings = settings
        self.persons = persons
        self.categories = categories
        self.partners = partners
        self.contracts = contracts
        self.incomes = incomes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = c.value(.settings, Settings())
        // Listen elementweise (COD-1): ein defekter Eintrag geht verloren, nicht die ganze Liste; ist eine vorhandene Liste
        // gar nicht lesbar, wirft das Lesen (die App darf dann nicht mit leeren Daten überschreiben)
        persons = try c.lossyArrayStrict(.persons)
        categories = try c.lossyArrayStrict(.categories)
        partners = try c.lossyArrayStrict(.partners)
        contracts = try c.lossyArrayStrict(.contracts)
        incomes = try c.lossyArrayStrict(.incomes)
    }

    /// Startzustand: Person «Ich», 12 Standardkategorien, Hauptwährung CHF.
    public static func initial(homeCurrency: Currency = .CHF) -> AppData {
        AppData(settings: Settings(homeCurrency: homeCurrency), persons: [Person(name: "Ich")], categories: Category.standard())
    }

    // MARK: Nachschlagen

    public func person(_ id: UUID?) -> Person? {
        guard let id = id else { return nil }
        return persons.first { $0.id == id }
    }

    public func category(_ id: UUID?) -> Category? {
        guard let id = id else { return nil }
        return categories.first { $0.id == id }
    }

    public func partner(_ id: UUID?) -> Partner? {
        guard let id = id else { return nil }
        return partners.first { $0.id == id }
    }

    public func contract(_ id: UUID?) -> Contract? {
        guard let id = id else { return nil }
        return contracts.first { $0.id == id }
    }

    public func income(_ id: UUID?) -> Income? {
        guard let id = id else { return nil }
        return incomes.first { $0.id == id }
    }

    public func personIndex(_ id: UUID) -> Int? { persons.firstIndex { $0.id == id } }
    public func categoryIndex(_ id: UUID) -> Int? { categories.firstIndex { $0.id == id } }
    public func partnerIndex(_ id: UUID) -> Int? { partners.firstIndex { $0.id == id } }
    public func contractIndex(_ id: UUID) -> Int? { contracts.firstIndex { $0.id == id } }
    public func incomeIndex(_ id: UUID) -> Int? { incomes.firstIndex { $0.id == id } }

    /// Person mit diesem Namen (exakt).
    public func person(named name: String) -> Person? { persons.first { $0.name == name } }

    /// Kategorie mit diesem Namen (exakt).
    public func category(named name: String) -> Category? { categories.first { $0.name == name } }

    /// Kategorie «Sonstiges» (Art other), sonst nach Name.
    public var otherCategory: Category? {
        categories.first { $0.kind == .other } ?? categories.first { $0.name == "Sonstiges" }
    }

    /// Absender einer Person mit aufgelöster «gleiche Adresse wie» (eine Stufe, `sndOf`), Felder getrimmt.
    public func resolvedSender(_ personID: UUID) -> SenderAddress {
        guard let p = person(personID) else { return SenderAddress() }
        var s = p.sender
        if let o = p.sameAddressAs, o != p.id, let other = person(o) {
            s = s.withAddress(of: other.sender)
        }
        let t = { (x: String) in x.trimmingCharacters(in: .whitespaces) }
        return SenderAddress(first: t(s.first), last: t(s.last), street: t(s.street), zip: t(s.zip), city: t(s.city), country: t(s.country))
    }

    /// Anzeigename für Briefe (`sndName`): «Vorname Nachname», sonst Personenname.
    public func senderName(_ personID: UUID) -> String {
        let n = resolvedSender(personID).fullName
        return n.isEmpty ? (person(personID)?.name ?? "") : n
    }

    /// Titel eines Vertrags (`titleOf`): Bezeichnung → Vertragspartner → «Ohne Namen».
    public func title(of c: Contract) -> String {
        if !c.label.isEmpty { return c.label }
        if let p = partner(c.partnerID), !p.name.isEmpty { return p.name }
        return "Ohne Namen"
    }

    /// Zweitzeile Vertragspartner (`metaOf`): nur wenn Bezeichnung vorhanden und Vertragspartner davon verschieden.
    public func meta(of c: Contract) -> String {
        let pt = (partner(c.partnerID)?.name ?? "").trimmingCharacters(in: .whitespaces)
        let dup = c.label.isEmpty || pt.lowercased() == c.label.trimmingCharacters(in: .whitespaces).lowercased()
        return (!dup && !pt.isEmpty) ? pt : ""
    }

    /// Name des Vertragspartners oder "".
    public func partnerName(of c: Contract) -> String { partner(c.partnerID)?.name ?? "" }

    /// Namen der Inhaber in Reihenfolge der Zuordnung.
    public func holderNames(of c: Contract) -> [String] { c.holderIDs.compactMap { person($0)?.name } }

    /// Inhaber mit Anteilen (Web `holdersText`): «Sinan 70 % & Lara 30 %», ohne Aufteilung «Sinan & Lara».
    public func holdersText(of c: Contract) -> String {
        guard let sp = c.validSplit else { return holderNames(of: c).joined(separator: " & ") }
        return c.holderIDs.compactMap { h in person(h).map { $0.name + " " + String(Int((sp[h] ?? 0).rounded())) + "\u{00A0}%" } }.joined(separator: " & ")
    }

    /// Markenfarbe (`colorFor`): eigene Farbe → Kategorie → Hash über Vertragspartner/Bezeichnung.
    public func color(of c: Contract) -> String {
        if let col = c.colorHex, !col.isEmpty { return col }
        if let cat = category(c.categoryID) { return cat.colorHex }
        let pn = partner(c.partnerID)?.name ?? ""
        return AppData.hashColor(pn.isEmpty ? c.label : pn)
    }

    /// Logo (Datei-ID und Hintergrund) eines Vertrags: Vertragspartner, sonst eigenes.
    public func logo(of c: Contract) -> (id: String, background: String)? {
        if let p = partner(c.partnerID), let l = p.logoID, !l.isEmpty { return (l, p.logoBg ?? "#FFFFFF") }
        if let l = c.logoID, !l.isEmpty { return (l, c.logoBg ?? "#FFFFFF") }
        return nil
    }

    /// Hash-Farbe wie `colorFor` der Web-App: h = (h·31 + Zeichencode) mod 8.
    public static func hashColor(_ s: String) -> String {
        var h = 0
        for u in s.utf16 { h = (h * 31 + Int(u)) % Category.palette.count }
        return Category.palette[h]
    }

    /// Alle referenzierten Datei-IDs (Logos, Dokumente, Bilder).
    public var referencedFileIDs: [String] {
        var out: [String] = []
        var seen = Set<String>()
        func add(_ s: String?) {
            guard let s = s, !s.isEmpty, !seen.contains(s) else { return }
            seen.insert(s)
            out.append(s)
        }
        for c in contracts {
            add(c.logoID)
            for d in c.documents { add(d.id) }
        }
        for i in incomes { add(i.logoID) }
        for p in partners { add(p.logoID) }
        for p in persons { add(p.avatarID) }
        return out
    }
}

// MARK: - JSON

/// Encoder/Decoder für das native Format (Datum als ms seit 1970, Daten als Base64).
public enum KontivoJSON {
    public static func makeEncoder(pretty: Bool = false) -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.dataEncodingStrategy = .base64
        e.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted] : [.sortedKeys]
        return e
    }

    public static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        d.dataDecodingStrategy = .base64
        return d
    }
}

extension AppData {
    /// JSON der Daten (für `data.json`).
    public func encoded(pretty: Bool = false) throws -> Data {
        try KontivoJSON.makeEncoder(pretty: pretty).encode(self)
    }

    /// Liest `data.json`.
    public static func decode(_ data: Data) throws -> AppData {
        try KontivoJSON.makeDecoder().decode(AppData.self, from: data)
    }
}

// MARK: - Decoding-Hilfen (fehlende Felder → Standardwert)

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: @autoclosure () -> T) -> T {
        if let v = try? decodeIfPresent(T.self, forKey: key) { return v }
        return fallback()
    }

    func optional<T: Decodable>(_ key: Key) -> T? {
        if let v = try? decodeIfPresent(T.self, forKey: key) { return v }
        return nil
    }

    /// Liste elementweise lesen: defekte Elemente werden übersprungen, statt die ganze Liste zu verwerfen (COD-1).
    /// Fehlt der Schlüssel oder ist er keine Liste → leer.
    func lossyArray<T: Decodable>(_ key: Key) -> [T] {
        guard var arr = try? nestedUnkeyedContainer(forKey: key) else { return [] }
        var out: [T] = []
        while !arr.isAtEnd {
            if let v = try? arr.decode(T.self) {
                out.append(v)
            } else if (try? arr.decode(LossySkip.self)) == nil {
                break
            }
        }
        return out
    }

    /// Wie `lossyArray`, aber eine vorhandene Liste, die gar nicht lesbar ist (keine Liste oder kein Element lesbar), wirft.
    func lossyArrayStrict<T: Decodable>(_ key: Key) throws -> [T] {
        if !contains(key) { return [] }
        if (try? decodeNil(forKey: key)) == true { return [] }
        var arr = try nestedUnkeyedContainer(forKey: key)
        var out: [T] = []
        var bad = 0
        while !arr.isAtEnd {
            if let v = try? arr.decode(T.self) {
                out.append(v)
            } else {
                bad += 1
                if (try? arr.decode(LossySkip.self)) == nil { break }
            }
        }
        if out.isEmpty && bad > 0 {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Keine Einträge lesbar")
        }
        return out
    }
}

/// Überspringt ein beliebiges Element einer Liste.
struct LossySkip: Decodable {
    init(from decoder: Decoder) throws {}
}
