import SwiftUI
import KontivoCore

/// Auswahl «Pausieren für» (openPausePick): 1, 3, 6 Monate, ohne Enddatum oder bis zu einem Datum.
struct CTPauseSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let contractID: UUID
    @State private var until: Day = Day.today(in: .current).addingMonths(1)

    init(contractID: UUID) {
        self.contractID = contractID
    }

    var body: some View {
        let today = model.today
        let options = AppData.pauseOptions(today: today)
        NavigationStack {
            List {
                Section {
                    ForEach(options.indices, id: \.self) { i in
                        let o = options[i]
                        Button {
                            apply(o.until)
                        } label: {
                            HStack {
                                Text(o.title).foregroundStyle(KColor.ink)
                                Spacer()
                                Text(o.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(KColor.ink2)
                            }
                        }
                    }
                }
                .listRowBackground(KColor.surface)
                Section {
                    DatePicker("Bis", selection: $until.ctDate, in: today.addingDays(1).date()..., displayedComponents: .date)
                    Button("Pausieren") { apply(until) }
                        .fontWeight(.semibold)
                } header: {
                    Text("Oder bis zu einem Datum")
                } footer: {
                    Text("Danach läuft der Vertrag automatisch weiter. Zahlungen während der Pause zählen nicht in die Summen.")
                }
                .listRowBackground(KColor.surface)
            }
            .scrollContentBackground(.hidden)
            .background(KColor.paper)
            .navigationTitle("Pausieren für")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
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
            dismiss()
        }
    }
}
