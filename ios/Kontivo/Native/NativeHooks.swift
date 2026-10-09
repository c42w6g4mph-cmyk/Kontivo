import SwiftUI
import KontivoCore

extension View {
    /// Native Dienste an der Hauptansicht (ein Aufruf in `KontivoApp`): Erinnerungen neu planen, Tippen auf eine
    /// Erinnerung öffnet den Vertrag, App-Sperre und Datenschutz-Abdeckung.
    func kontivoNative() -> some View {
        modifier(NativeHooks())
    }
}

struct NativeHooks: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    private var links: NativeLinks { NativeLinks.shared }
    private var lock: AppLock { AppLock.shared }

    func body(content: Content) -> some View {
        content
            .onAppear {
                lock.appStarted(phase: scenePhase)
                ReminderScheduler.shared.reschedule(model, force: true)
                openPendingLink()
            }
            .onChange(of: scenePhase) { _, phase in
                lock.phaseChanged(phase)
                if phase == .active {
                    ReminderScheduler.shared.reschedule(model, force: true)
                    openPendingLink()
                }
            }
            // Jede Datenänderung und jeder Tageswechsel: Plan neu (entprellt; gleicher Plan → nichts)
            .onChange(of: model.data) { _, _ in dataChanged() }
            .onChange(of: model.today) { _, _ in ReminderScheduler.shared.reschedule(model) }
            .onChange(of: links.openContractID) { _, _ in openPendingLink() }
            .onChange(of: lock.locked) { _, locked in
                if !locked { openPendingLink() }
            }
    }

    private func dataChanged() {
        ReminderScheduler.shared.reschedule(model)
        offerReminders()
    }

    /// Erinnerung antippen: erst öffnen, wenn entsperrt und die Einführung zu ist.
    private func openPendingLink() {
        guard let id = links.openContractID, !lock.locked, model.onboarding == nil else { return }
        links.openContractID = nil
        model.openContractFromReminder(id)
    }

    /// Nach dem ersten Vertrag mit Frist einmal fragen, ob Kontivo erinnern soll (dann Systemabfrage).
    private func offerReminders() {
        guard !model.uiTestMode, !NativePrefs.asked, !NativePrefs.remindOn, model.onboarding == nil else { return }
        guard !model.calc.reminderDeadlines().isEmpty else { return }
        NativePrefs.asked = true
        let m = model
        Task { @MainActor in
            // Schon entschieden (z.B. in den Systemeinstellungen ausgeschaltet): nicht fragen
            guard await ReminderScheduler.status() == .notDetermined else { return }
            m.ask(title: "An Fristen erinnern?",
                  message: "Kontivo meldet sich \(Reminders.defaultLead) Tage vor jeder Kündigungsfrist und am letzten Tag – als Mitteilung auf diesem Gerät. Ändern kannst du das unter «Mehr».",
                  ok: "Erinnern", cancel: "Nicht jetzt") {
                Task { @MainActor in
                    if await ReminderScheduler.requestPermission() {
                        NativePrefs.remindOn = true
                        ReminderScheduler.shared.reschedule(m, force: true)
                        m.toast("Erinnerungen eingeschaltet")
                    }
                }
            }
        }
    }
}
