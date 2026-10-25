import Foundation

// MARK: - Erfolgskarte nach dem Übernehmen aus dem Katalog (Web v240–v243, paintSugg `.tplsum.ok`, tplSumItems, hnShort)

/// Kurzform des Katalog-Hinweises für die Erfolgskarte (Web `hnShort`, v243 + C24): nur der erste ganze Satz, Rest hinter «mehr»;
/// ist der erste Satz länger als 110 Zeichen, nur der Link «Hinweis zum Kündigen anzeigen». Nie abgeschnitten.
public struct CatalogHintShort: Hashable, Sendable {
    /// Erster Satz («;» am Ende wird zu «.»); leer bei `onlyLink`
    public var first: String
    /// Rest hinter «mehr» (leer = kein «mehr»)
    public var rest: String
    /// Erster Satz zu lang: nur «Hinweis zum Kündigen anzeigen» (zeigt `full`)
    public var onlyLink: Bool
    /// Ganzer Hinweis (für `onlyLink`)
    public var full: String
    /// Prüfhinweis bei nicht bestätigten Kontaktdaten, immer sichtbar (Web TPL_WARN), sonst leer
    public var warn: String

    public var isEmpty: Bool { first.isEmpty && !onlyLink && warn.isEmpty }
}

/// Stand der Formularfelder, die der Katalog ändern kann – nur was die Zusammenfassung braucht (Web `tplSnap`).
public struct CatalogSumSnap: Hashable, Sendable {
    /// Name der gewählten Kategorie ("" = keine)
    public var category: String
    public var noticeText: String
    public var noticeUnit: NoticeUnit
    /// Art «Mindestlaufzeit» (Web termMode fixed)
    public var fixedTerm: Bool
    /// Verlängerung in Monaten (0 = keine)
    public var renewMonths: Int
    public var cancelTerm: CancelTerm
    public var cancelChannel: CancelChannel?
    public var web: String
    public var cancelURL: String
    public var tel: String
    public var mail: String
    /// Adresszeilen
    public var address: [String]
    public var mandatory: Bool
    public var noCancel: Bool

    public init(category: String = "", noticeText: String = "", noticeUnit: NoticeUnit = .months, fixedTerm: Bool = false, renewMonths: Int = 0,
                cancelTerm: CancelTerm = .anytime, cancelChannel: CancelChannel? = nil, web: String = "", cancelURL: String = "", tel: String = "",
                mail: String = "", address: [String] = [], mandatory: Bool = false, noCancel: Bool = false) {
        self.category = category
        self.noticeText = noticeText
        self.noticeUnit = noticeUnit
        self.fixedTerm = fixedTerm
        self.renewMonths = renewMonths
        self.cancelTerm = cancelTerm
        self.cancelChannel = cancelChannel
        self.web = web
        self.cancelURL = cancelURL
        self.tel = tel
        self.mail = mail
        self.address = address
        self.mandatory = mandatory
        self.noCancel = noCancel
    }
}

/// Eine Zeile der Erfolgskarte: links das Feld, rechts der übernommene Wert (Web v241)
public struct CatalogSumItem: Hashable, Sendable {
    public var field: String
    public var value: String
    public init(_ field: String, _ value: String) {
        self.field = field
        self.value = value
    }
}

public enum CatalogCard {
    /// Titel und Fusszeile der Karte (Web v240/v242)
    public static let title = "Vertragsdaten ergänzt"
    public static let footer = "Stand 10/2026 · Änderungen vorbehalten"
    public static let undo = "Rückgängig"
    public static let more = "mehr"
    public static let showHint = "Hinweis zum Kündigen anzeigen"
    /// Prüfhinweis bei nicht offiziell bestätigten Kontaktdaten (Web TPL_WARN)
    public static let warn = "Kontaktdaten nicht offiziell bestätigt – vor dem Versand prüfen."

    /// «3 Angaben aus dem Kontivo-Katalog»
    public static func subtitle(_ n: Int) -> String {
        (n == 1 ? "1 Angabe" : "\(n) Angaben") + " aus dem Kontivo-Katalog"
    }

    /// Zeile «Logo · übernommen», wenn der Katalog auch ein Logo vorgeschlagen hat (Web tplLogo)
    public static let logoItem = CatalogSumItem("Logo", "übernommen")

    /// Optionstext «Kündbar per» (Web #fTermP)
    public static func termText(_ t: CancelTerm) -> String {
        switch t {
        case .anytime: return "jederzeit"
        case .period: return "Ende Periode"
        case .monthEnd: return "Monatsende"
        case .quarterEnd: return "Quartalsende"
        case .halfYearEnd: return "Halbjahresende"
        case .yearEnd: return "Jahresende"
        case .contractYear: return "Ende Vertragsjahr"
        }
    }

    /// Was hat der Katalog geändert? [Feldname, Wert] in der Reihenfolge der Web-App (`tplSumItems`, v241/v243);
    /// doppelte Felder (Kündigungsfrist aus Frist und «Kündbar per») werden mit « · » zusammengeführt.
    public static func items(_ a: CatalogSumSnap, _ b: CatalogSumSnap) -> [CatalogSumItem] {
        var out: [CatalogSumItem] = []
        func add(_ k: String, _ v: String) {
            if let i = out.firstIndex(where: { $0.field == k }) {
                if !v.isEmpty && !out[i].value.contains(v) { out[i].value += " · " + v }
                return
            }
            out.append(CatalogSumItem(k, v))
        }
        func sh(_ v: String) -> String {
            var s = v
            if let r = s.range(of: "^https?://", options: [.regularExpression]) { s.removeSubrange(r) }
            if s.hasPrefix("www.") { s.removeFirst(4) }
            return s
        }
        if a.category != b.category && !b.category.isEmpty { add("Kategorie", b.category) }
        let nt = b.noticeText.trimmingCharacters(in: .whitespaces)
        if (a.noticeText != b.noticeText || a.noticeUnit != b.noticeUnit) && !nt.isEmpty {
            let n = Int(Double(nt.replacingOccurrences(of: ",", with: ".")) ?? 0)
            let v: String
            switch b.noticeUnit {
            case .dayOfMonth: v = "bis zum \(n)."
            case .months: v = "\(n) " + (n == 1 ? "Monat" : "Monate")
            case .weeks: v = "\(n) " + (n == 1 ? "Woche" : "Wochen")
            case .days: v = "\(n) " + (n == 1 ? "Tag" : "Tage")
            }
            add("Kündigungsfrist", v)
        }
        if a.fixedTerm != b.fixedTerm && b.fixedTerm { add("Mindestlaufzeit", b.renewMonths > 0 ? "mit Verlängerung" : "feste Laufzeit") }
        if a.cancelTerm != b.cancelTerm && b.cancelTerm != .anytime && !b.fixedTerm { add("Kündigungsfrist", termText(b.cancelTerm)) }
        if a.cancelChannel != b.cancelChannel, let ch = b.cancelChannel {
            let w: [CancelChannel: String] = [.online: "online", .email: "per E-Mail", .letter: "per Brief", .phone: "per Telefon"]
            add("Kündigungsweg", w[ch] ?? ch.webText)
        }
        let web = b.web.trimmingCharacters(in: .whitespaces)
        if a.web != b.web && !web.isEmpty {
            let d = Format.domain(of: web)
            add("Website", sh(d.isEmpty ? web : d))
        }
        let cu = b.cancelURL.trimmingCharacters(in: .whitespaces)
        if a.cancelURL != b.cancelURL && !cu.isEmpty {
            let d = Format.domain(of: cu)
            add("Kündigungslink", d.isEmpty ? sh(cu) : d)
        }
        if a.tel != b.tel && !b.tel.trimmingCharacters(in: .whitespaces).isEmpty { add("Telefon", b.tel) }
        if a.mail != b.mail && !b.mail.trimmingCharacters(in: .whitespaces).isEmpty { add("E-Mail", sh(b.mail)) }
        if a.address != b.address, let last = b.address.last, !last.isEmpty { add("Adresse", sh(last)) }
        if !a.mandatory && b.mandatory { add("Pflichtvertrag", "ja") }
        if !a.noCancel && b.noCancel { add("Nicht kündbar", "ja") }
        return out
    }

    /// Abkürzungen, nach denen ein Punkt kein Satzende ist – nur als ganzes Wort (Web C24: nicht «Frist.»)
    private static let abbrev = try? NSRegularExpression(
        pattern: "(?:^|[^A-Za-zÄÖÜäöüß])(bzw|z\\.\\s?B|inkl|ca|u\\.\\s?a|Nr|etc|evtl|ggf|max|min|mind|vgl|d\\.\\s?h|Mo|Fr|Sa|So|St)\\.$",
        options: [.caseInsensitive])
    private static let sentenceEnd = try? NSRegularExpression(pattern: "[.;](?=\\s)", options: [])

    /// Erster ganzer Satz des Katalog-Hinweises (Web `hnShort`)
    public static func hintShort(_ hint: String, confirmed: Bool) -> CatalogHintShort {
        let h = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        let w = confirmed ? "" : warn
        if h.isEmpty { return CatalogHintShort(first: "", rest: "", onlyLink: false, full: "", warn: w) }
        let ns = h as NSString
        var cut = -1
        for m in sentenceEnd?.matches(in: h, range: NSRange(location: 0, length: ns.length)) ?? [] {
            let pre = ns.substring(to: m.range.location + 1)
            let isAbbrev = abbrev?.firstMatch(in: pre, range: NSRange(location: 0, length: (pre as NSString).length)) != nil
            if !isAbbrev {
                cut = m.range.location
                break
            }
        }
        var first = cut < 0 ? h : ns.substring(to: cut + 1)
        if first.hasSuffix(";") { first = String(first.dropLast()) + "." }
        let rest = cut < 0 ? "" : ns.substring(from: cut + 1).trimmingCharacters(in: .whitespacesAndNewlines)
        // passt der erste Satz nicht in 2 Zeilen: nur ein Link, der den ganzen Hinweis zeigt
        if first.utf16.count > 110 { return CatalogHintShort(first: "", rest: "", onlyLink: true, full: h, warn: w) }
        return CatalogHintShort(first: first, rest: rest, onlyLink: false, full: h, warn: w)
    }
}
