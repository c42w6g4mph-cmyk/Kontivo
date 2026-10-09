import SwiftUI
import UIKit
import EventKit
import EventKitUI
import KontivoCore

/// «In Kalender»: Systemdialog «Termin hinzufügen» (EKEventEditViewController) für eine Frist –
/// ganztägig am letzten Kündigungstag bzw. am Ende des Probeabos, Erinnerungen 7 Tage und 1 Tag vorher um 09:00,
/// Notiz mit Vertragspartner und Kündigungsweg (Texte aus `KontivoCore.Reminders`).
///
/// Für andere Bereiche (z.B. Vertragsdetail, Menü •••):
/// ```swift
/// @State private var calendarFor: UUID?
/// if DeadlineCalendar.canAdd(c, calc: model.calc) {
///     Button { calendarFor = c.id } label: { Label(DeadlineCalendar.menuTitle, systemImage: DeadlineCalendar.symbol) }
/// }
/// …
/// .deadlineCalendar(contractID: $calendarFor)
/// ```
@MainActor
enum DeadlineCalendar {
    static let store = EKEventStore()
    static let menuTitle = "In Kalender"
    static let symbol = "calendar.badge.plus"

    struct EventInfo: Hashable {
        var title: String
        var date: Day
        var notes: String
        var url: URL?
    }

    /// Hat der Vertrag eine Frist für den Kalender? (Menüpunkt nur dann zeigen)
    static func canAdd(_ c: Contract, calc: Calc) -> Bool {
        calc.reminderDeadline(for: c) != nil
    }

    /// Frist zu einer Zeile in «Fristen» (nil bei «Gekündigt» und «Behalten · läuft bis»: kein weiterer Termin).
    static func deadline(for item: Calc.DeadlineItem, contract c: Contract) -> ReminderDeadline? {
        switch item.kind {
        case .trial:
            return ReminderDeadline(contractID: c.id, kind: .trial, date: item.date, end: nil, mandatory: c.mandatory)
        case .open:
            return ReminderDeadline(contractID: c.id, kind: .notice, date: item.date, end: item.end, mandatory: c.mandatory)
        case .kept:
            guard item.end != nil else { return nil }
            return ReminderDeadline(contractID: c.id, kind: .notice, date: item.date, end: item.end, mandatory: c.mandatory)
        case .ended:
            return nil
        }
    }

    /// Angaben für den Eintrag.
    static func info(_ d: ReminderDeadline, contract c: Contract, calc: Calc) -> EventInfo {
        let url = calc.cancVia(c) == .online ? CancelLinks.web(calc.cancLink(c)) : nil
        return EventInfo(title: Reminders.calendarTitle(d, contract: c, data: calc.data),
                         date: d.date,
                         notes: Reminders.calendarNotes(d, contract: c, calc: calc),
                         url: url)
    }

    /// Schreibzugriff (nur Hinzufügen) einmal anfragen. Der Dialog «Termin hinzufügen» funktioniert ab iOS 17 auch ohne
    /// Zugriff (läuft ausserhalb der App); mit Zugriff bleiben die vorbereiteten Erinnerungen sicher erhalten.
    static func requestAccessIfNeeded() async {
        if NativePrefs.stub { return }
        guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else { return }
        AppLock.shared.suppressCover = true
        defer { AppLock.shared.suppressCover = false }
        _ = try? await store.requestWriteOnlyAccessToEvents()
    }

    /// Termin vorbereiten.
    static func prepare(_ info: EventInfo) -> DeadlineEventRequest {
        let ev = EKEvent(eventStore: store)
        ev.title = info.title
        ev.isAllDay = true
        let start = info.date.date(calendar: Calendar.current)
        ev.startDate = start
        ev.endDate = start
        ev.notes = info.notes.isEmpty ? nil : info.notes
        ev.url = info.url
        // Ganztägig: Versatz ab Mitternacht des Termins → 7 Tage bzw. 1 Tag vorher um 09:00
        ev.alarms = [
            EKAlarm(relativeOffset: TimeInterval(-7 * 86_400 + 9 * 3_600)),
            EKAlarm(relativeOffset: TimeInterval(-1 * 86_400 + 9 * 3_600)),
        ]
        return DeadlineEventRequest(event: ev, store: store)
    }
}

struct DeadlineEventRequest: Identifiable {
    let id = UUID()
    let event: EKEvent
    let store: EKEventStore
}

/// Was in den Kalender soll: Vertrag und (optional) eine bestimmte Frist; ohne Frist die nächste des Vertrags.
struct DeadlineCalendarTarget: Identifiable, Hashable {
    var contractID: UUID
    var deadline: ReminderDeadline?
    var id: String { contractID.uuidString + (deadline.map { "-" + $0.kind.rawValue + "-" + $0.date.iso } ?? "") }
}

extension View {
    /// Öffnet «Termin hinzufügen», sobald `target` gesetzt wird; setzt es danach wieder auf nil.
    func deadlineCalendar(_ target: Binding<DeadlineCalendarTarget?>) -> some View {
        modifier(DeadlineCalendarModifier(target: target))
    }

    /// Kurzform für das Vertragsdetail: nächste Frist des Vertrags mit dieser ID.
    func deadlineCalendar(contractID: Binding<UUID?>) -> some View {
        modifier(DeadlineCalendarModifier(target: Binding(
            get: { contractID.wrappedValue.map { DeadlineCalendarTarget(contractID: $0, deadline: nil) } },
            set: { contractID.wrappedValue = $0?.contractID }
        )))
    }
}

struct DeadlineCalendarModifier: ViewModifier {
    @Binding var target: DeadlineCalendarTarget?
    @Environment(AppModel.self) private var model
    @State private var request: DeadlineEventRequest?
    @State private var starting = false

    func body(content: Content) -> some View {
        content
            .onChange(of: target) { _, t in
                if let t { start(t) }
            }
            .sheet(item: $request, onDismiss: { target = nil }) { r in
                DeadlineEventEditor(request: r) { action in
                    request = nil
                    if action == .saved { model.toast("Termin im Kalender eingetragen") }
                }
                .ignoresSafeArea()
            }
    }

    private func start(_ t: DeadlineCalendarTarget) {
        // Doppeltippen: nur ein Kalenderdialog
        guard request == nil, !starting else { return }
        let calc = model.calc
        guard let c = model.data.contract(t.contractID), let d = t.deadline ?? calc.reminderDeadline(for: c) else {
            target = nil
            model.toast("Keine Frist für den Kalender")
            return
        }
        let info = DeadlineCalendar.info(d, contract: c, calc: calc)
        starting = true
        Task { @MainActor in
            await DeadlineCalendar.requestAccessIfNeeded()
            starting = false
            request = DeadlineCalendar.prepare(info)
        }
    }
}

/// Systemdialog «Termin hinzufügen» (EKEventEditViewController).
struct DeadlineEventEditor: UIViewControllerRepresentable {
    let request: DeadlineEventRequest
    let onDone: @MainActor (EKEventEditViewAction) -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let vc = EKEventEditViewController()
        vc.eventStore = request.store
        vc.event = request.event
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: @MainActor (EKEventEditViewAction) -> Void

        init(onDone: @escaping @MainActor (EKEventEditViewAction) -> Void) {
            self.onDone = onDone
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            let f = onDone
            Task { @MainActor in f(action) }
        }
    }
}
