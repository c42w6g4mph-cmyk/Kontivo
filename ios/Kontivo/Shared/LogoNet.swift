import SwiftUI
import UIKit
import Network
import KontivoCore

// MARK: - Netz und Links (gemeinsam für Logo-, Adress- und Kurssuche)

/// Netzstatus wie `navigator.onLine` der Web-App: kurzer Blick auf den aktuellen Pfad (NWPathMonitor).
enum NetCheck {
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        private let cont: CheckedContinuation<Bool, Never>
        init(_ c: CheckedContinuation<Bool, Never>) { cont = c }
        func finish(_ v: Bool) {
            lock.lock(); defer { lock.unlock() }
            if done { return }
            done = true
            cont.resume(returning: v)
        }
    }

    /// true, wenn eine Verbindung besteht (im Zweifel nach 1.5 s true, damit nichts blockiert)
    static func isOnline() async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            let once = Once(c)
            let m = NWPathMonitor()
            let q = DispatchQueue(label: "ch.kontivo.netcheck")
            m.pathUpdateHandler = { p in
                once.finish(p.status == .satisfied)
                m.cancel()
            }
            m.start(queue: q)
            q.asyncAfter(deadline: .now() + 1.5) {
                once.finish(true)
                m.cancel()
            }
        }
    }
}

/// Externe Links an einer Stelle (A10)
enum WebLinks {
    /// Google-Bildersuche «<Name> logo» (logoSearch der Web-App); öffnet in Safari
    static func googleImages(_ name: String) -> URL? {
        URL(string: "https://www.google.com/search?tbm=isch&q=" + LogoFinder.enc(name.trimmingCharacters(in: .whitespacesAndNewlines) + " logo"))
    }
}

// MARK: - Kandidaten

/// Quelle eines Logo-Vorschlags (LSRC der Web-App)
enum LogoSource: String, Hashable, Sendable {
    case wiki, store, site, social, web

    var label: String {
        switch self {
        case .wiki: return "Wikipedia"
        case .web: return "Website"
        case .site: return "Website-Symbol"
        case .social: return "Profilbild"
        case .store: return "App Store"
        }
    }
}

/// Ein Logo-Vorschlag
struct LogoCandidate: Identifiable, Hashable, Sendable {
    var url: String
    var thumb: String
    var title: String
    var seller: String
    var score: Double
    var src: LogoSource
    var id: String { url }
}

/// Übernommenes Logo: PNG 512×512 und Hintergrund (Hex)
struct LogoImage: Sendable {
    var png: Data
    var background: String
}

/// Fehler bei der Übernahme (LERR)
enum LogoError: Error, Sendable {
    case small, empty, load, storage, failed

    var message: String {
        switch self {
        case .small: return "Bild zu klein oder nicht quadratisch"
        case .empty: return "Bild wirkt leer oder einfarbig"
        case .load: return "Bild konnte nicht geladen werden"
        case .storage: return "Speichern nicht möglich"
        case .failed: return "Übernahme fehlgeschlagen"
        }
    }
}
