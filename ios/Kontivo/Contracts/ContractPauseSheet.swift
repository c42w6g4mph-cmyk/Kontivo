import SwiftUI
import KontivoCore

/// Auswahl «Pausieren für» (openPausePick): 1, 3, 6 Monate, ohne Enddatum oder bis zu einem Datum.
struct CTPauseSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let contractID: UUID
    /// Nach dem Pausieren statt nur dieses Fenster zu schliessen (Detail: alle Fenster schliessen wie Web)
    var onPaused: (() -> Void)? = nil
    @State private var until: Day = Day.today(in: .current).addingMonths(1)

    init(contractID: UUID, onPaused: (() -> Void)? = nil) {
        self.contractID = contractID
        self.onPaused = onPaused
    }

    var body: some View {
        let today = model.today
        let options = AppData.pauseOptions(today: today)
        // Web `openPausePick`: Auswahlblatt mit Zeilen `.pick`, «Oder bis zu einem Datum» (Datum + Knopf), Hinweis
        CTPickSheet(title: "Pausieren für") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(options.indices, id: \.self) { i in
                    let o = options[i]
                    CTPickRow(title: o.title, detail: o.detail) { apply(o.until) }
                }
                Text("Oder bis zu einem Datum")
                    .font(.system(size: 12.5))
                    .foregroundStyle(KColor.ink2)
                    .padding(.top, 6)
                HStack(spacing: 8) {
                    DatePicker("Bis", selection: $until.ctDate, in: today.addingDays(1).date()..., displayedComponents: .date)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        apply(until)
                    } label: {
                        Text("Pausieren")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.tealFill))
                    }
                    .buttonStyle(.plain)
                }
                Text("Danach läuft der Vertrag automatisch weiter. Zahlungen während der Pause zählen nicht in die Summen.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(KColor.ink2)
                    .lineSpacing(4.4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .presentationDetents([.medium, .large])
        .environment(\.locale, Locale(identifier: "de_CH"))
    }

    private func apply(_ u: Day?) {
        let t = model.today
        let id = contractID
        if let u, u <= t {
            model.toast("Bitte ein Datum in der Zukunft wählen")
            return
        }
        if model.update({ try $0.pause(id, until: u, today: t) }) {
            model.toast(AppData.pauseToast(until: u))
            if let onPaused { onPaused() } else { dismiss() }
        }
    }
}
