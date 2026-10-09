import SwiftUI
import UIKit
import UserNotifications
import KontivoCore

/// Gruppe unter «Mehr»: Erinnerungen vor Fristen (Schalter, «Tage vorher») und App-Sperre.
/// Einstellungen gelten nur für dieses Gerät (`NativePrefs`, nicht im Backup).
struct NativeMoreGroup: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(NativePrefs.remindKey, store: NativePrefs.defaults) private var remindOn = false
    @AppStorage(NativePrefs.leadKey, store: NativePrefs.defaults) private var lead = Reminders.defaultLead
    @AppStorage(NativePrefs.lockKey, store: NativePrefs.defaults) private var lockOn = false

    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var busy = false
    @State private var lockMessage: String?

    var body: some View {
        MoreGroup(title: "Erinnerungen und Sicherheit") {
            Toggle(isOn: remindBinding) {
                label("Erinnerungen", "Mitteilung vor jeder Kündigungsfrist und am letzten Tag, um 9 Uhr")
            }
            .tint(KColor.teal)
            .disabled(busy)
            .padding(.top, 2)
            .padding(.bottom, 12)
            .accessibilityIdentifier("native.remind")
            if remindOn && status == .denied {
                deniedHint
            }
            MoreLine()
            HStack(spacing: 12) {
                label("Tage vorher", "Zusätzliche Erinnerung vor dem letzten Tag")
                Spacer(minLength: 8)
                Picker("Tage vorher", selection: leadBinding) {
                    ForEach(Reminders.leadChoices, id: \.self) { n in
                        Text(n == 1 ? "1 Tag" : "\(n) Tage").tag(n)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(KColor.teal)
                .accessibilityLabel("Tage vorher")
                .accessibilityIdentifier("native.lead")
            }
            .padding(.vertical, 8)
            .disabled(!remindOn)
            .opacity(remindOn ? 1 : 0.5)
            MoreLine()
            Toggle(isOn: lockBinding) {
                label("App-Sperre", AppLock.methodName == "Code"
                      ? "Gerätecode beim Öffnen und nach 30 Sekunden im Hintergrund"
                      : AppLock.methodName + " oder Gerätecode beim Öffnen und nach 30 Sekunden im Hintergrund")
            }
            .tint(KColor.teal)
            .disabled(busy)
            .padding(.top, 12)
            .accessibilityIdentifier("native.lock")
        }
        .task { await refreshStatus() }
        .onChange(of: scenePhase) { _, p in
            if p == .active { Task { await refreshStatus() } }
        }
        .alert("App-Sperre", isPresented: Binding(get: { lockMessage != nil }, set: { if !$0 { lockMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(lockMessage ?? "")
        }
    }

    private func label(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KColor.ink)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(KColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Mitteilungen in den Systemeinstellungen ausgeschaltet
    private var deniedHint: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Mitteilungen sind für Kontivo in den Einstellungen ausgeschaltet.")
                .font(.caption)
                .foregroundStyle(KColor.warn)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Einstellungen") { openSettings() }
                .font(.caption.weight(.semibold))
                .foregroundStyle(KColor.teal)
                .buttonStyle(.plain)
                .fixedSize()
        }
        .padding(.bottom, 10)
        .accessibilityIdentifier("native.denied")
    }

    // MARK: Bindungen

    private var remindBinding: Binding<Bool> {
        Binding(get: { remindOn }, set: { on in
            on ? enableReminders() : disableReminders()
        })
    }

    private var leadBinding: Binding<Int> {
        Binding(get: { Reminders.leadChoices.contains(lead) ? lead : Reminders.defaultLead }, set: { n in
            guard n != lead else { return }
            lead = n
            ReminderScheduler.shared.reschedule(model, force: true)
        })
    }

    private var lockBinding: Binding<Bool> {
        Binding(get: { lockOn }, set: { on in
            if on {
                busy = true
                Task { @MainActor in
                    if let msg = await AppLock.shared.enable() { lockMessage = msg }
                    lockOn = NativePrefs.lockOn
                    busy = false
                }
            } else {
                AppLock.shared.disable()
                lockOn = false
            }
        })
    }

    // MARK: Aktionen

    private func enableReminders() {
        busy = true
        NativePrefs.asked = true
        let m = model
        Task { @MainActor in
            let before = await ReminderScheduler.status()
            let ok = await ReminderScheduler.requestPermission()
            status = await ReminderScheduler.status()
            busy = false
            if ok {
                remindOn = true
                ReminderScheduler.shared.reschedule(m, force: true)
            } else {
                remindOn = false
                // früher abgelehnt: der Systemdialog erscheint nicht mehr → auf die Einstellungen verweisen
                if before == .denied { openSettingsAsk() }
            }
        }
    }

    private func disableReminders() {
        remindOn = false
        ReminderScheduler.shared.removeAll()
    }

    private func refreshStatus() async {
        status = await ReminderScheduler.status()
        // Erlaubt und eingeschaltet: Plan abgleichen (z.B. nach Erlauben in den Einstellungen)
        if remindOn { ReminderScheduler.shared.reschedule(model, force: true) }
    }

    private func openSettingsAsk() {
        model.ask(title: "Mitteilungen erlauben?",
                  message: "Damit Kontivo vor Fristen erinnern kann, erlaube Mitteilungen in den Einstellungen.",
                  ok: "Einstellungen") {
            openSettings()
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}
