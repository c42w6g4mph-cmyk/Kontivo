import Foundation

/// Zustand des iCloud-Sync für die Anzeige unter «Mehr → Daten».
public enum SyncStatus: String, Equatable, Sendable {
    /// Build ohne iCloud-Berechtigung (kostenloses Apple-Konto)
    case unavailableBuild
    /// Vom Nutzer ausgeschaltet
    case off
    /// Startet, prüft das Konto
    case starting
    /// Gleicht gerade ab
    case syncing
    /// Abgeglichen
    case upToDate
    /// Kein Netz: wird später abgeglichen
    case offline
    /// Kein iCloud-Konto angemeldet
    case noAccount
    /// iCloud eingeschränkt (Bildschirmzeit, Verwaltung)
    case restricted
    /// iCloud-Speicher voll
    case quotaFull
    /// Anderes iCloud-Konto als beim letzten Abgleich: angehalten, bis der Nutzer entscheidet
    case accountChanged
    /// Daten in iCloud wurden (auf einem anderen Gerät oder in den Einstellungen) gelöscht: hier ausgeschaltet
    case deletedElsewhere
    /// Daten noch nicht sicher geladen (Gerät gesperrt, Rückfrage offen)
    case waiting
    /// Anderer Fehler, wird erneut versucht
    case failed

    /// Läuft der Abgleich (Rückfragen sagen dann «auch in iCloud»)?
    public var isRunning: Bool {
        switch self {
        case .starting, .syncing, .upToDate, .offline, .quotaFull, .failed: return true
        default: return false
        }
    }
}

/// Texte des iCloud-Sync (Schweizer Rechtschreibung, Nutzen statt Technik).
public enum SyncTexts {
    public static let title = "iCloud-Sync"
    public static let explanation = "Deine Verträge sind auf iPhone und iPad gleich und sicher in deiner iCloud. Nur du hast Zugriff."
    /// Graue Zeile im Debug-Build ohne iCloud-Berechtigung
    public static let buildOff = "iCloud-Sync: in diesem Build aus (Apple Developer Program nötig)"

    public static let offTitle = "iCloud-Sync ausschalten?"
    public static let offMessage = "Deine Daten bleiben auf diesem Gerät. Änderungen werden nicht mehr mit deinen anderen Geräten abgeglichen."
    public static let offButton = "Ausschalten"
    public static let offDeleteButton = "Ausschalten und aus iCloud löschen"
    public static let deleteTitle = "Auch aus iCloud löschen?"
    public static let deleteMessage = "Deine Kontivo-Daten werden aus deiner iCloud entfernt. Auf diesem Gerät bleiben sie erhalten. Auf deinen anderen Geräten bleiben sie ebenfalls, dort wird der Abgleich ausgeschaltet.\n\nDas lässt sich nicht rückgängig machen."
    public static let deleteButton = "Aus iCloud löschen"
    public static let deletedToast = "Aus iCloud gelöscht"
    public static let deleteFailedToast = "Löschen in iCloud nicht möglich – bitte später erneut versuchen"
    public static let offToast = "iCloud-Sync ausgeschaltet"

    public static let accountButton = "Mit diesem iCloud-Konto abgleichen …"
    public static let accountTitle = "Mit diesem iCloud-Konto abgleichen?"
    public static let accountMessage = "Auf diesem Gerät ist ein anderes iCloud-Konto angemeldet als beim letzten Abgleich. Deine Daten auf diesem Gerät werden mit den Kontivo-Daten dieses Kontos zusammengeführt."
    public static let accountOK = "Zusammenführen"

    /// Toast, wenn ein neues Gerät die Daten aus iCloud übernommen hat
    public static let adoptedToast = "Deine Daten aus iCloud sind da"
    /// Meldung, wenn die iCloud-Daten anderswo gelöscht wurden
    public static let deletedElsewhereToast = "Die Kontivo-Daten in iCloud wurden gelöscht – iCloud-Sync ist hier aus, deine Daten bleiben"

    /// Zusatz zur Rückfrage «Alle Daten löschen?», wenn der Abgleich läuft
    public static let wipeNote = "\n\niCloud-Sync ist an: Gelöscht wird auch in iCloud und auf deinen anderen Geräten."
    /// Zusatz zur Rückfrage «Backup einspielen?», wenn der Abgleich läuft
    public static let replaceNote = " Auch in iCloud und auf deinen anderen Geräten."

    /// Untertitel unter «iCloud-Sync».
    public static func status(_ s: SyncStatus, lastSync: Date?, now: Date = Date(), calendar: Calendar = Day.calendar) -> String {
        switch s {
        case .unavailableBuild: return buildOff
        case .off: return "Aus – Daten nur auf diesem Gerät"
        case .starting, .syncing: return "Wird abgeglichen …"
        case .upToDate:
            let base = "Auf allen deinen Geräten aktuell"
            guard let t = lastSync else { return base }
            return base + " · zuletzt " + when(t, now: now, calendar: calendar)
        case .offline: return "Offline – wird später abgeglichen"
        case .noAccount: return "Nicht bei iCloud angemeldet"
        case .restricted: return "iCloud ist auf diesem Gerät nicht verfügbar"
        case .quotaFull: return "iCloud-Speicher voll"
        case .accountChanged: return "Anderes iCloud-Konto – Abgleich angehalten"
        case .deletedElsewhere: return "In iCloud gelöscht – Abgleich ist aus"
        case .waiting: return "Wartet, bis die Daten geladen sind"
        case .failed: return "Abgleich gestört – wird erneut versucht"
        }
    }

    /// «14:32», «gestern 09:05» oder «3.10.2026»
    static func when(_ t: Date, now: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: t)
        let h = c.hour ?? 0
        let m = c.minute ?? 0
        let time = (h < 10 ? "0" : "") + String(h) + ":" + (m < 10 ? "0" : "") + String(m)
        let day = Day(date: t, calendar: calendar)
        let today = Day(date: now, calendar: calendar)
        if day == today { return time }
        if day == today.addingDays(-1) { return "gestern " + time }
        return Format.shortNumericDate(day)
    }
}
