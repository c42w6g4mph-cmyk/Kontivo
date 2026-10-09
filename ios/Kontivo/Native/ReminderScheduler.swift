import SwiftUI
import UserNotifications
import KontivoCore

/// Lokale Mitteilungen vor Fristen (ohne Server). Der Plan (welche Verträge, Daten, Texte, Kennungen) kommt aus
/// `KontivoCore.Reminders.plan`; hier wird er beim System angemeldet. Neu geplant wird bei jeder Datenänderung,
/// bei Tageswechsel und beim Zurückkehren in die App (entprellt). Höchstens `Reminders.maxPending`, nächste zuerst.
@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    private var task: Task<Void, Never>?
    /// Zuletzt angemeldeter Plan (Kennung + Texte): gleicher Plan → nichts tun
    private var lastSignature: [String]?
    /// Für UI-Tests (`-uiNativeStub`): Plan ohne Anmeldung beim System
    private(set) var lastPlan: [ReminderNotification] = []

    /// Plan berechnen und (entprellt) anmelden. `force`: auch bei gleichem Plan neu abgleichen (Rückkehr in die App).
    func reschedule(_ model: AppModel, force: Bool = false) {
        let plan = currentPlan(model)
        task?.cancel()
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.apply(plan, force: force)
        }
    }

    /// Plan für die aktuellen Daten und Einstellungen (leer, wenn Erinnerungen aus sind).
    func currentPlan(_ model: AppModel) -> [ReminderNotification] {
        guard NativePrefs.remindOn else { return [] }
        let comps = Day.calendar.dateComponents([.hour, .minute], from: Date())
        let minute = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        return Reminders.plan(calc: model.calc, leadDays: NativePrefs.leadDays, minuteOfDay: minute)
    }

    private func apply(_ plan: [ReminderNotification], force: Bool) async {
        let sig = plan.map { $0.id + "|" + $0.title + "|" + $0.body }
        if !force && sig == lastSignature { return }
        lastPlan = plan
        if NativePrefs.stub {
            lastSignature = sig
            return
        }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(Reminders.idPrefix) }
        guard ReminderScheduler.isAllowed(settings.authorizationStatus), !plan.isEmpty else {
            if !ours.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ours) }
            lastSignature = sig
            return
        }
        let wanted = Set(plan.map(\.id))
        let stale = ours.filter { !wanted.contains($0) }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        // Gleiche Kennung ersetzt die bestehende Mitteilung (Texte können sich geändert haben)
        for n in plan {
            do {
                try await center.add(ReminderScheduler.request(n))
            } catch {
                // einzelne Mitteilung nicht angemeldet (z.B. Zeitpunkt knapp vorbei) – die übrigen weiter
            }
        }
        lastSignature = sig
    }

    /// Alle Erinnerungen von Kontivo entfernen (Erinnerungen ausgeschaltet).
    func removeAll() {
        task?.cancel()
        lastSignature = nil
        lastPlan = []
        guard !NativePrefs.stub else { return }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { reqs in
            let ids = reqs.map(\.identifier).filter { $0.hasPrefix(Reminders.idPrefix) }
            if !ids.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ids) }
        }
    }

    static func request(_ n: ReminderNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = n.title
        content.body = n.body
        content.sound = .default
        content.threadIdentifier = "kontivo.fristen"
        content.userInfo = ["contractID": n.contractID.uuidString]
        // Gregorianisch und ohne feste Zeitzone: 09:00 Ortszeit, auch nach einer Reise
        var dc = DateComponents()
        dc.calendar = Calendar(identifier: .gregorian)
        dc.year = n.fireDay.year
        dc.month = n.fireDay.month
        dc.day = n.fireDay.day
        dc.hour = n.hour
        dc.minute = n.minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: dc, repeats: false)
        return UNNotificationRequest(identifier: n.id, content: content, trigger: trigger)
    }

    // MARK: Berechtigung

    static func isAllowed(_ s: UNAuthorizationStatus) -> Bool {
        switch s {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// Aktueller Status (UI-Tests: erlaubt).
    static func status() async -> UNAuthorizationStatus {
        if NativePrefs.stub { return .authorized }
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Berechtigung anfragen (Systemdialog nur beim ersten Mal). true = Mitteilungen erlaubt.
    static func requestPermission() async -> Bool {
        if NativePrefs.stub { return true }
        let center = UNUserNotificationCenter.current()
        let s = await center.notificationSettings().authorizationStatus
        if isAllowed(s) { return true }
        if s == .denied { return false }
        // Systemdialog macht die App kurz inaktiv: dabei keine Datenschutz-Abdeckung zeigen
        AppLock.shared.suppressCover = true
        defer { AppLock.shared.suppressCover = false }
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }
}

// MARK: - Tippen auf eine Mitteilung

/// Ziel aus einer angetippten Erinnerung (wird von `NativeHooks` geöffnet, sobald die App bereit und entsperrt ist).
@MainActor
@Observable
final class NativeLinks {
    static let shared = NativeLinks()
    var openContractID: UUID?
}

/// Empfänger der Mitteilungen: Tippen öffnet den Vertrag, im Vordergrund als Banner zeigen.
/// Muss vor dem Ende des App-Starts gesetzt sein (`NativeBoot.start()` in `KontivoApp.init`).
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let req = response.notification.request
        let id = Reminders.contractID(fromIdentifier: req.identifier)
            ?? (req.content.userInfo["contractID"] as? String).flatMap { UUID(uuidString: $0) }
        if let id {
            Task { @MainActor in NativeLinks.shared.openContractID = id }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

/// Start der nativen Dienste (einmal, in `KontivoApp.init`).
enum NativeBoot {
    static func start() {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
    }
}

extension AppModel {
    /// Tippen auf eine Erinnerung: Tab «Fristen», offene Fenster schliessen, Vertragsdetail öffnen.
    func openContractFromReminder(_ id: UUID) {
        guard data.contract(id) != nil, onboarding == nil else { return }
        tab = .deadlines
        if sheets.last == .contractDetail(id) { return }
        dismissAll()
        presentAfterDismiss(.contractDetail(id))
    }
}
