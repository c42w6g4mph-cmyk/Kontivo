import SwiftUI
import KontivoCore

/// Mehr → Daten: «Kontoauszug einlesen» mit dem Zeitraum des letzten Imports (Web v266/v275 `#bkRow`, `paintBkRow`):
/// Zeitraum 13 pt ink2 (Tabellenziffern), darunter «vor 5 Tagen eingelesen · 2 Dateien» 12.5 pt ink3; ohne Import
/// «CSV, Excel, camt.053 oder MT940». Antippen öffnet die Dateiauswahl.
struct BankMoreRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let last = model.data.settings.lastBankImport
        Button {
            BankImportCenter.shared.pick(.file, model: model)
        } label: {
            HStack(spacing: 12) {
                MoreManageIcon(symbol: "ic.bank")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Kontoauszug einlesen")
                        .font(KFont.text(15.5, .semibold))
                        .foregroundStyle(KColor.ink)
                    if let l = last {
                        Text(l.rangeText)
                            .font(KFont.text(13).monospacedDigit())
                            .foregroundStyle(KColor.ink2)
                            .lineLimit(1)
                            .padding(.top, 2)
                        Text(l.agoLine(today: model.today))
                            .font(KFont.text(12.5))
                            .foregroundStyle(KColor.ink3)
                            .padding(.top, 2)
                    } else {
                        Text("CSV, Excel, camt.053 oder MT940")
                            .font(KFont.text(12.5))
                            .foregroundStyle(KColor.ink3)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("›")
                    .font(KFont.text(18))
                    .foregroundStyle(KColor.ink3)
                    .padding(.leading, -4)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(last.map { "Kontoauszug einlesen. Zuletzt eingelesen: " + BankImport.dot($0.from) + " bis " + BankImport.dot($0.to) + ", " + $0.agoText(today: model.today) }
                            ?? "Kontoauszug einlesen")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("bankMoreRow")
    }
}
