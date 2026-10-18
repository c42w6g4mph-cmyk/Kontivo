import SwiftUI
import KontivoCore

/// Wechselkurse automatisch (Frankfurter/EZB, Rückfall open.er-api). Bis zum Tageskurs alle 3 h erneut prüfen, bei offener App
/// stündlich (Web v162, Regel in `RatePolicy`).
/// Wie `autoRate`/`fetchRate` der Web-App: Quellen der Reihe nach, je 8 s Zeitlimit, Plausibilität EUR zwischen 0.5 und 2 CHF.
/// Gespeichert wird `settings.rates` = CHF pro Einheit (Kehrwert der Quelle), dazu `rateDate`, `rateChecked` und `rateSource` («ezb»/«er»).
enum RateService {
    /// Läuft gerade ein Abruf? (verhindert parallele Abrufe)
    @MainActor private static var busy = false

    /// Kurse laden, wenn heute noch nicht geprüft wurde (oder USD fehlt) bzw. immer mit `force`.
    /// Mit `force` gibt es Rückmeldungen als Toast; ohne `force` läuft alles still.
    @MainActor static func refreshIfNeeded(_ model: AppModel, force: Bool) async {
        if busy {
            if force { model.toast("Kurse werden geladen …") }
            return
        }
        // Demo-/Testmodus: feste Kurse, damit Bildschirmfotos und UI-Tests nicht vom Tageskurs abhängen
        if model.uiTestMode && !force { return }
        let today = model.today
        let s = model.data.settings
        if !force, !RatePolicy.needsFetch(s, today: today) { return }

        busy = true
        if force { model.toast("Lade Kurse…") }
        let outcome = await fetchRates()
        busy = false

        switch outcome {
        case .offline:
            if force { model.toast("Keine Internetverbindung") }
        case .failed:
            if force { model.toast("Kurse konnten nicht geladen werden") }
        case .success(let r):
            let day = model.today
            model.update { d in
                var rates: [String: Double] = [:]
                if let eur = r.rates["EUR"] { rates["EUR"] = (eur * 10_000).rounded() / 10_000 }
                for c in ["USD", "GBP", "TRY"] {
                    if let v = r.rates[c], v > 0 { rates[c] = (v * 1_000_000).rounded() / 1_000_000 }
                }
                d.settings.rates = rates
                d.settings.rateDate = r.date ?? day
                RatePolicy.markChecked(&d.settings, today: day)
                d.settings.rateSource = r.source
            }
            if force { model.toast("Kurse aktualisiert") }
        }
    }

    /// Stündlich prüfen, solange die App offen ist (Web v162 `setInterval(…, 3600e3)` bei sichtbarem Fenster).
    /// Mehrfacher Aufruf startet keinen zweiten Takt.
    @MainActor private static var hourly: Task<Void, Never>?

    @MainActor static func startHourly(_ model: AppModel) {
        if hourly != nil { return }
        hourly = Task { @MainActor [weak model] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(RatePolicy.foregroundInterval * 1_000_000_000))
                guard let m = model else { break }
                if UIApplication.shared.applicationState == .active {
                    await refreshIfNeeded(m, force: false)
                }
            }
            hourly = nil
        }
    }

    /// Text unter der Hauptwährung: «Kurse der EZB, täglich automatisch · Stand 2. Oktober 2026».
    static func stampText(_ s: KontivoCore.Settings) -> String {
        let src = s.rateSource == "er" ? "Kurse von open.er-api.com" : "Kurse der EZB"
        return src + ", täglich automatisch" + (s.rateDate != nil ? " · Stand " + Format.fmtD(s.rateDate) : "")
    }

    // MARK: - Abruf

    /// Ergebnis einer Quelle: CHF pro Einheit, Datum der Quelle, Quelle («ezb» = Frankfurter/EZB, «er» = open.er-api)
    struct RateResult: Sendable {
        var rates: [String: Double]
        var date: Day?
        var source: String
    }

    enum Outcome: Sendable {
        case success(RateResult)
        case offline
        case failed
    }

    private enum Source: Sendable {
        case frankfurterDev, frankfurterApp, openER

        var url: URL? {
            switch self {
            case .frankfurterDev: return URL(string: "https://api.frankfurter.dev/v1/latest?base=CHF&symbols=EUR,USD,GBP,TRY")
            case .frankfurterApp: return URL(string: "https://api.frankfurter.app/latest?from=CHF&to=EUR,USD,GBP,TRY")
            case .openER: return URL(string: "https://open.er-api.com/v6/latest/CHF")
            }
        }

        var code: String { self == .openER ? "er" : "ezb" }
    }

    /// Eigene Sitzung ohne Cache, Zeitlimit 8 s bis die Antwort vollständig gelesen ist.
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 8
        c.timeoutIntervalForResource = 8
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCache = nil
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    /// Quellen der Reihe nach; die erste plausible gewinnt.
    static func fetchRates() async -> Outcome {
        for src in [Source.frankfurterDev, .frankfurterApp, .openER] {
            guard let url = src.url else { continue }
            do {
                var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: req)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { continue }
                guard let r = parse(data, source: src) else { continue }
                if let eur = r.rates["EUR"], eur > 0.5, eur < 2 { return .success(r) }
            } catch let e as URLError {
                switch e.code {
                case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
                    return .offline
                default:
                    continue
                }
            } catch {
                continue
            }
        }
        return .failed
    }

    /// Antwort lesen: `rates` (Einheiten pro 1 CHF) → Kehrwert (CHF pro Einheit), nur Werte > 0.
    private static func parse(_ data: Data, source: Source) -> RateResult? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let raw = obj["rates"] as? [String: Any] else { return nil }
        var rates: [String: Double] = [:]
        for c in ["EUR", "USD", "GBP", "TRY"] {
            if let v = number(raw[c]), v > 0 { rates[c] = 1 / v }
        }
        var day: Day?
        switch source {
        case .frankfurterDev, .frankfurterApp:
            if let s = obj["date"] as? String { day = Day(iso: s) }
        case .openER:
            if let t = number(obj["time_last_update_unix"]), t > 0 {
                day = Day(date: Date(timeIntervalSince1970: t), calendar: Calendar.current)
            }
        }
        return RateResult(rates: rates, date: day, source: source.code)
    }

    private static func number(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }
}
