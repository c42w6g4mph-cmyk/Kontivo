import Foundation

// MARK: - Kontoauszug-Import: öffentliche Typen (Web «Kontoauszug-Import», bankRead/bankFind)
// Alles lokal, die Datei wird nicht gespeichert. Ergebnis sind nur Vorschläge, Verträge entstehen erst nach Bestätigung.

/// Zahlungsart einer Buchung (Web `t.kind`): Lastschrift/eBill, Dauerauftrag, Karte, Überweisung, unbekannt ("").
public enum BankKind: String, Codable, Hashable, Sendable {
    case dd, so, card, tr
    case unknown = ""

    /// Text wie Web `BKKIND` (leer bei unbekannt).
    public var displayName: String {
        switch self {
        case .dd: return "Lastschrift / eBill"
        case .so: return "Dauerauftrag"
        case .card: return "Kartenzahlung"
        case .tr: return "Überweisung"
        case .unknown: return ""
        }
    }

    init(web: String) { self = BankKind(rawValue: web) ?? .unknown }
}

/// Eine Buchung (Web `{d, a, cur, name, text, type, kind, cred, mref}`).
public struct BankTx: Equatable, Hashable, Sendable {
    public var date: Day
    /// Belastung negativ
    public var amount: Double
    /// ISO-Code («CHF», «EUR» …) oder "" (dann gilt die Hauptwährung)
    public var currency: String
    public var name: String
    public var text: String
    public var type: String
    public var kind: BankKind
    /// Gläubiger-ID (SEPA)
    public var cred: String
    /// Mandatsreferenz (SEPA)
    public var mref: String
    /// Einzelposten einer Sammelbuchung (Web `t.sub`; Einnahmen-Suche überspringt sie)
    public var sub: Bool
    /// Mitteilung eines Einzelpostens im Sammelauftrag («Vollkasko Audi», Web v272 `t.memo`): eigene Gruppe und Bezeichnung
    public var memo: String
    /// Name, unter dem die Buchung gruppiert wurde (intern, Web `t._nm`)
    var groupName: String = ""

    public init(date: Day, amount: Double, currency: String = "", name: String = "", text: String = "", type: String = "",
                kind: BankKind = .unknown, cred: String = "", mref: String = "", sub: Bool = false, memo: String = "") {
        self.sub = sub
        self.memo = memo
        self.date = date
        self.amount = amount
        self.currency = currency
        self.name = name
        self.text = text
        self.type = type
        self.kind = kind
        self.cred = cred
        self.mref = mref
    }
}

/// Gelesene Datei (Web `bankRead` → `{fmt, bank, tx, from, to}`).
public struct BankFile: Equatable, Sendable {
    /// Bank, falls am Spaltenkopf erkannt («PostFinance», «UBS» …), sonst ""
    public var bank: String
    /// Buchungen nach Datum sortiert
    public var tx: [BankTx]
    public var from: Day?
    public var to: Day?
    /// «CSV», «camt.053», «MT940», «Text» … (mehrere Dateien: durch «, » getrennt)
    public var format: String
    /// Anzahl zusammengeführter Dateien (1 = eine Datei)
    public var files: Int
    /// Kontoinhaber laut Datei (Web v180 `r.owner`: CSV-Vorspann «Kontoinhaber;…», konstante zweite Namensspalte, camt `Acct/Ownr/Nm`), sonst ""
    public var owner: String
    /// Eigenes Konto (IBAN aus Vorspann, camt `Acct/Id/IBAN`, MT940 `:25:`), Web v272 `acct`; für das Zusammenführen mehrerer Dateien
    public var account: String

    public init(bank: String = "", tx: [BankTx], from: Day? = nil, to: Day? = nil, format: String = "", files: Int = 1, owner: String = "",
                account: String = "") {
        self.account = account
        self.bank = bank
        self.tx = tx
        self.from = from ?? tx.first?.date
        self.to = to ?? tx.last?.date
        self.format = format
        self.files = files
        self.owner = owner
    }
}

/// Grund, wenn eine Datei nichts ergab (Web v272 `bkLastDiag`, für die Fehlermeldung).
public enum BankReadDiag: String, Equatable, Sendable {
    /// keine Kopfzeile mit Datum und Betrag erkannt
    case noHeader = "nohead"
    /// Kopfzeile erkannt, aber kein Datum lesbar («Datumsformat nicht erkannt»)
    case dateFormat = "date"
    /// Kopfzeile erkannt, keine Buchungen
    case noBookings = "empty"
    case none = ""
}

/// Datei nicht lesbar. `notRecognized`: mit Grund (Web `bkLastDiag`).
public enum BankReadError: Error, Equatable {
    case notRecognized(BankReadDiag)
    case tooBig
    case empty
}

/// Sicherheit eines Vorschlags (Web `conf`).
public enum BankConfidence: String, Codable, Hashable, Sendable {
    case high = "hoch", medium = "mittel", low = "niedrig"

    /// Rang für die Sortierung (hoch zuerst).
    var rank: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}

/// Preisänderung innerhalb des Auszugs (Web `change`): alter Preis `prev`, neuer Preis `amount` ab `from`.
public struct BankPriceChange: Equatable, Hashable, Sendable {
    public var from: Day
    public var prev: Double
    public var amount: Double

    public init(from: Day, prev: Double, amount: Double) {
        self.from = from
        self.prev = prev
        self.amount = amount
    }
}

/// Gelernte Korrektur (Web `settings.bankAlias[key] = {n, c}`): Vertragspartner und Kategorie beim letzten Import geändert.
public struct BankAlias: Codable, Hashable, Sendable {
    /// Vertragspartner
    public var n: String
    /// Kategorie (Name)
    public var c: String

    public init(n: String, c: String = "") {
        self.n = n
        self.c = c
    }

    public init(from decoder: Decoder) throws {
        let k = try decoder.container(keyedBy: CodingKeys.self)
        n = (try? k.decode(String.self, forKey: .n)) ?? ""
        c = (try? k.decode(String.self, forKey: .c)) ?? ""
    }
}

/// Vorschlag aus wiederkehrenden Belastungen (Web `bankEval` → `s`).
public struct BankSuggestion: Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    /// Gruppenschlüssel («tpl:Netflix|CHF», «cred:DE…|EUR», «immo seeblick|CHF» …)
    public var key: String
    /// Vertragspartner (Katalogname, sonst aufbereiteter Name aus dem Auszug, gelernte Korrektur gewinnt)
    public var name: String
    /// Name wie im Auszug (letzte Buchung)
    public var raw: String
    /// Buchungstext der letzten Buchung
    public var text: String
    public var currency: String
    /// Betrag pro Zahlung, positiv (bei Preisänderung der neue Preis)
    public var amount: Double
    /// Zahlungsrhythmus in Monaten
    public var cycle: Int
    /// Nächste Zahlung (ab letzter Buchung im Rhythmus bis heute)
    public var due: Day
    public var first: Day
    public var last: Day
    /// Anzahl Zahlungen (Web `n`)
    public var count: Int
    public var dates: [Day]
    public var amounts: [Double]
    public var confidence: BankConfidence
    /// Betrag schwankt (Rechnung), `amount` ist dann der Median
    public var varies: Bool
    public var change: BankPriceChange?
    /// Katalogeintrag, falls Treffer (seit Web v210 gibt es gleiche Namen mit verschiedener Bezeichnung, z.B. CSS
    /// Krankenkasse/Zusatzversicherung – daher der Eintrag selbst statt nur des Namens)
    public var catalog: CatalogEntry?
    /// Kategorie (Name)
    public var category: String
    public var kind: BankKind
    /// Gläubiger-ID / Mandat der letzten Buchung
    public var cred: String
    public var mref: String
    /// Gelernte Korrektur angewendet («Name wie beim letzten Import übernommen»)
    public var alias: BankAlias?
    /// Vom Benutzer ausgeblendet («Nie mehr vorschlagen»)
    public var ignored: Bool
    /// Mitteilung der letzten Buchung (Einzelposten im Sammelauftrag, Web v272 `memo`): wird zur Bezeichnung
    public var memo: String = ""
    /// Gleicher Betrag und Rhythmus wie dieser erfasste Vertrag, aber anderer Name (Web v272 `same`): nachfragen statt doppelt anlegen
    public var sameAs: UUID? = nil
    /// Gekündigter/beendeter Vertrag beim selben Vertragspartner (Web v272 `arch`)
    public var archived: UUID? = nil
    /// Beginn des Auszugs (Web `stFrom`): Vertragsbeginn nur, wenn die erste Zahlung deutlich danach liegt
    public var statementFrom: Day? = nil

    /// Name des Katalogeintrags, falls Treffer (Web `s.tpl[0]`)
    public var catalogName: String? { catalog?.name }
    /// Katalogeintrag (für Kündigungsfrist und Kontaktdaten beim Anlegen).
    public var catalogEntry: CatalogEntry? { catalog }
}

/// Vorschlag aus wiederkehrenden Gutschriften (Web v177 `bankFindInc` → `s`): Lohn, Rente, Zulagen …
public struct BankIncomeSuggestion: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { key }
    /// Gruppenschlüssel («cred:…|CHF», «muster ag|CHF»)
    public var key: String
    /// Quelle (häufigster Name, aufbereitet)
    public var name: String
    /// Bezeichnung: Art («Lohn», «Rente» …), bei «Sonstiges» leer
    public var label: String
    /// Art (Web `cat`): «Lohn», «Rente», «Zulagen», «Vermietung» oder «Sonstiges»
    public var category: String
    public var currency: String
    /// Typischer Betrag (Median der letzten drei Eingänge ohne Ausreisser nach oben)
    public var amount: Double
    public var cycle: Int
    public var due: Day
    public var count: Int
    public var first: Day
    public var last: Day
    public var dates: [Day]
    public var amounts: [Double]
    public var lo: Double
    public var hi: Double
    public var varies: Bool
    /// Nicht mitgerechnete höhere Eingänge (13. Monatslohn, Bonus)
    public var skipped: Int
    public var raw: String
    public var text: String
    /// Nur eine Gutschrift im Auszug (Web v272 `once`): unsicherer Vorschlag
    public var once: Bool = false
    public var confidence: BankConfidence

    /// Art als `IncomeKind` (Web-Namen der Einnahmearten)
    public var kind: IncomeKind {
        IncomeKind.allCases.first { $0.displayName == category } ?? .sonstiges
    }
}

/// Bereits erfasste Einnahme, die im Auszug gefunden wurde (Web `inc.known`).
public struct BankIncomeKnown: Equatable, Sendable {
    public var incomeID: UUID
    public var suggestion: BankIncomeSuggestion
}

/// Ergebnis von `BankImport.findIncome` (Web `bankFindInc` → `{sugg, known}`).
public struct BankIncomeResult: Sendable {
    public var items: [BankIncomeSuggestion]
    public var known: [BankIncomeKnown]

    public init(items: [BankIncomeSuggestion] = [], known: [BankIncomeKnown] = []) {
        self.items = items
        self.known = known
    }
}

/// Bereits erfasster Vertrag, der im Auszug gefunden wurde (Web `known`).
public struct BankKnown: Equatable, Sendable {
    public var contractID: UUID
    public var suggestion: BankSuggestion
    /// Nur über den Namen und einen ungefähr passenden Betrag erkannt (Web `loose`: «im Auszug gefunden» statt «unverändert»)
    public var loose: Bool
    /// Gekündigter Vertrag, letzte Abbuchung vor dem Kündigungstermin (Web v272 `match.arch`): als «gekündigt» zeigen
    public var archived: Bool = false
}

/// Gekündigter Vertrag, der nach seinem Ende noch abgebucht wurde (Web v272 `after`): Hinweis statt neuer Vorschlag.
public struct BankAfterEnd: Equatable, Sendable {
    public var contractID: UUID
    /// Anzahl Abbuchungen nach dem Ende
    public var count: Int
    public var last: Day
    public var amount: Double
    public var currency: String
}

/// Neuer Preis für einen erfassten Vertrag (Web `match.kind === "price"`).
public struct BankPriceMatch: Equatable, Sendable {
    public var contractID: UUID
    public var from: Day
    /// Neuer Preis (im Rhythmus des Vertrags)
    public var amount: Double
    /// Bisheriger Preis (Web `match.old`)
    public var old: Double
    public var suggestion: BankSuggestion
}

/// Ergebnis von `BankImport.find` (Web `bankFind` → `{sugg, known, from, to, n}`).
public struct BankFindResult: Sendable {
    /// Neue Vorschläge (ohne Treffer bei erfassten Verträgen), sortiert wie Web; ausgeblendete mit `ignored = true`
    public var items: [BankSuggestion]
    /// Bereits erfasst
    public var known: [BankKnown]
    /// Preisänderungen erfasster Verträge
    public var prices: [BankPriceMatch]
    /// Anzahl ausgeblendeter Vorschläge
    public var ignoredCount: Int
    /// Gekündigte Verträge, die nach ihrem Ende noch abgebucht wurden
    public var after: [BankAfterEnd] = []
    /// Alle Vorschläge in Web-Reihenfolge (Preisänderungen zuerst), wie `sugg`
    public var all: [BankSuggestion]
    public var from: Day?
    public var to: Day?
    /// Anzahl Buchungen
    public var count: Int
    public var bank: String
    public var format: String
}
