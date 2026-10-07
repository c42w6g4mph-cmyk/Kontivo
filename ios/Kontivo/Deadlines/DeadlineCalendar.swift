import SwiftUI
import UIKit
import EventKit
import EventKitUI
import KontivoCore

/// Kalendereintrag für eine Entscheidungskarte: ganztägig am letzten Kündigungstag bzw. am Ende des Probeabos,
/// Erinnerungen 7 Tage und 1 Tag vorher um 09:00, Notiz mit Vertragspartner, Kündigungsweg und Kundennummer.
@MainActor
enum DeadlineCalendar {
    static let store = EKEventStore()

    struct EventInfo {
        var title: String
        var date: Day
        var notes: String
        var url: URL?
    }

    /// Angaben für den Eintrag aus der Entscheidungskarte.
    static func info(trial: Bool, date: Day, contract c: Contract, calc: Calc, data: AppData) -> EventInfo {
        let title = (trial ? "Probeabo endet: " : "Kündigungsfrist: ") + data.title(of: c)
        var lines: [String] = []
        let pn = data.partnerName(of: c).trimmingCharacters(in: .whitespaces)
        if !pn.isEmpty { lines.append("Vertragspartner: " + pn) }
        let via = calc.cancVia(c)
        var way = c.cancelChannel?.webText ?? ""
        if way.isEmpty || calc.isRent(c) {
            switch via {
            case .online: way = CancelChannel.online.webText
            case .mail: way = CancelChannel.email.webText
            case .post: way = c.cancelChannel == .registered ? CancelChannel.registered.webText : CancelChannel.letter.webText
            case .none: way = ""
            }
        }
        if !way.isEmpty { lines.append("Kündigungsweg: " + way) }
        let cust = c.customerNo.trimmingCharacters(in: .whitespaces)
        if !cust.isEmpty { lines.append("Kundennummer: " + cust) }
        if trial {
            lines.append("Kündigung muss vor dem " + Format.fmtD(date) + " sein.")
        } else {
            lines.append("Kündigung muss bis " + Format.fmtD(date) + " beim Vertragspartner sein.")
        }
        let url = via == .online ? CancelLinks.web(calc.cancLink(c)) : nil
        return EventInfo(title: title, date: date, notes: lines.joined(separator: "\n"), url: url)
    }

    /// Termin vorbereiten. Keine Berechtigungsabfrage: der Systemdialog «Termin hinzufügen»
    /// (EKEventEditViewController) läuft ab iOS 17 ausserhalb der App und braucht keinen Kalenderzugriff.
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
