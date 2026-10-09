import Foundation
import KontivoCore

/// Geräte-Einstellungen der nativen Funktionen (Erinnerungen, App-Sperre). Bewusst nicht in `AppData`:
/// gelten nur für dieses Gerät und gehören nicht ins Backup.
enum NativePrefs {
    static let remindKey = "kontivo.remind.on"
    static let leadKey = "kontivo.remind.days"
    /// Rückfrage «An Fristen erinnern?» schon gezeigt
    static let askedKey = "kontivo.remind.asked"
    static let lockKey = "kontivo.lock.on"

    /// Eigener Speicher in UI-Tests (bei jedem Start leer), sonst `UserDefaults.standard`.
    static let defaults: UserDefaults = {
        #if DEBUG
        if AppModel.isUITestLaunch, let d = UserDefaults(suiteName: "ch.kontivo.uitest.native") {
            d.removePersistentDomain(forName: "ch.kontivo.uitest.native")
            return d
        }
        #endif
        return .standard
    }()

    /// UI-Tests: keine Systemabfragen (Mitteilungen, Face ID), Berechtigung gilt als erteilt. Startargument `-uiNativeStub`.
    static var stub: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-uiNativeStub")
        #else
        return false
        #endif
    }

    static var remindOn: Bool {
        get { defaults.bool(forKey: remindKey) }
        set { defaults.set(newValue, forKey: remindKey) }
    }

    /// «Tage vorher» (1, 3, 7, 14, 30), Standard 7
    static var leadDays: Int {
        get {
            let v = defaults.integer(forKey: leadKey)
            return Reminders.leadChoices.contains(v) ? v : Reminders.defaultLead
        }
        set { defaults.set(newValue, forKey: leadKey) }
    }

    static var asked: Bool {
        get { defaults.bool(forKey: askedKey) }
        set { defaults.set(newValue, forKey: askedKey) }
    }

    static var lockOn: Bool {
        get { defaults.bool(forKey: lockKey) }
        set { defaults.set(newValue, forKey: lockKey) }
    }
}
