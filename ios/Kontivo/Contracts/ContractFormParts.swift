import SwiftUI
import UIKit
import KontivoCore

// Bausteine des Vertragsformulars (Web v145–v160 «Vertrag bearbeiten wie die Ansicht»): Sprungziele (formGo),
// Datumszeile mit sichtbar leerem Feld, Knopfzeilen (Chips), Drehrad mit «… übernehmen», Tagesraster «Zahlung am»,
// Segment «Kündigungsweg», Zeilen «Beschriftung links, Wert rechts».

// MARK: - Sprungziele (Web formGo)

/// Felder, zu denen das Formular springen kann (Web `formGo(id)`): scrollt zur Zeile und setzt bei Textfeldern den Fokus.
enum ContractFormField: String, Hashable {
    case label, partner, amount, prices, payAccount, extras
    case start, end, termMonths, notice, trial, cancelWay, cancelURL, cancelMail, cancelOn, cancelPer
    case category, customerNo, contractNo, address, web, tel, mail, note

    /// Textfeld (bekommt den Fokus), sonst nur scrollen
    var isText: Bool {
        switch self {
        case .label, .partner, .amount, .payAccount, .cancelURL, .cancelMail, .customerNo, .contractNo, .address, .web, .tel, .mail, .note:
            return true
        default:
            return false
        }
    }
}

/// Formular von aussen an einem Feld öffnen (Web `openForm(c); formGo(id)`), z.B. «Nummer eintragen» → Kundennummer,
/// «Wieder aktiv» → Vertragsende, «Kein Link hinterlegt» → Kündigungslink/Website:
/// vor `model.present(.contractForm(.edit(id)))` `ContractFormGo.request(id, .customerNo)` aufrufen. Gilt einmal, nur für diesen Vertrag.
@MainActor
enum ContractFormGo {
    static var pending: (id: UUID, field: ContractFormField)?

    static func request(_ id: UUID, _ field: ContractFormField) {
        pending = (id, field)
    }

    /// Ziel für diesen Vertrag abholen und löschen (gilt einmal).
    static func take(for id: UUID) -> ContractFormField? {
        guard let p = pending, p.id == id else { return nil }
        pending = nil
        return p.field
    }
}

// MARK: - Zeilen

/// Beschriftung links in einer Formularzeile (Web .frow label: grau)
struct CTRowLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .foregroundStyle(KColor.ink2)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }
}

/// Zeile «Beschriftung | Textfeld rechts» (Web .frow mit Eingabe in teal, Platzhalter «hinzufügen»)
struct CTFormTextRow: View {
    let title: String
    @Binding var text: String
    var placeholder = "hinzufügen"
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .never
    var autocorrect = false
    var contentType: UITextContentType? = nil
    var limit: Int? = nil
    var identifier = ""
    let field: ContractFormField
    var focus: FocusState<ContractFormField?>.Binding

    var body: some View {
        HStack(spacing: 12) {
            CTRowLabel(title)
                .layoutPriority(1)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(!autocorrect)
                .textContentType(contentType)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(KColor.teal)
                .focused(focus, equals: field)
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
                .onChange(of: text) { _, v in
                    if let l = limit, v.count > l { text = String(v.prefix(l)) }
                }
        }
        .id(field)
    }
}

/// Datumszeile, die leer sein darf (Web input[type=date] mit Markierung `.emp`, v146): leer → Knopf «wählen» auf getöntem
/// Grund (setzt `fallback`), sonst kompakter DatePicker und × zum Leeren.
struct CTFormDateRow: View {
    let title: String
    let day: Day?
    var fallback: Day
    var clearable = true
    var identifier = ""
    let set: (Day?) -> Void

    var body: some View {
        HStack(spacing: 8) {
            CTRowLabel(title)
            Spacer(minLength: 4)
            if let d = day {
                DatePicker(title, selection: Binding(get: { d.date() }, set: { set(Day(date: $0)) }), displayedComponents: .date)
                    .labelsHidden()
                    .accessibilityIdentifier(identifier)
                if clearable {
                    Button {
                        set(nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(KColor.ink3)
                            .imageScale(.large)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(title + " entfernen")
                }
            } else {
                Button {
                    set(fallback)
                } label: {
                    Text("wählen")
                        .foregroundStyle(KColor.teal)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(KColor.teal.opacity(0.12)))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(title + " wählen")
                .accessibilityIdentifier(identifier.isEmpty ? "" : identifier + ".pick")
            }
        }
    }
}

/// Knopf einer Knopfzeile (Web .chip in .fchq): Rahmen, gewählt gefüllt in teal. `fill` = volle Spaltenbreite.
struct CTFormChip: View {
    let title: String
    let isOn: Bool
    var fill = true
    var enabled = true
    var identifier = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isOn ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 8).padding(.vertical, 8)
                .frame(maxWidth: fill ? .infinity : nil)
                // Text in der Flächenfarbe: hell auf dunklem Petrol, im Dunkelmodus dunkel auf hellem Petrol (Kontrast)
                .foregroundStyle(isOn ? KColor.surface : KColor.ink2)
                .background(Capsule().fill(isOn ? KColor.teal : Color.clear))
                .overlay(Capsule().strokeBorder(isOn ? Color.clear : KColor.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// Knopf unten in einem Unterbereich («Preisänderung hinzufügen», «… übernehmen»): volle Breite, gefüllt
struct CTFormOKButton: View {
    let title: String
    var identifier = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(KColor.surface)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.teal))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// «+ Preisänderung», «+ Sonderzahlung» (Web .fadd)
struct CTFormAddRow: View {
    let title: String
    var identifier = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
                .font(.body.weight(.semibold))
                .foregroundStyle(KColor.teal)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier(identifier)
    }
}

/// Kleine Prozent-Plakette in der Preisliste (Web .fpc: teurer = warn, günstiger = ok)
struct CTPctPill: View {
    let text: String
    /// 1 teurer, −1 günstiger, 0 gleich
    let tone: Int
    var body: some View {
        let c = tone > 0 ? KColor.warn : (tone < 0 ? KColor.ok : KColor.ink2)
        Text(verbatim: text)
            .font(.footnote.weight(.semibold).monospacedDigit())
            .foregroundStyle(c)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(c.opacity(0.14)))
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - Segment Kündigungsweg

/// «Online · E-Mail · Brief» als Segment (Web .seg2 #fCancT): nochmals tippen hebt die Wahl auf (darum kein Picker(.segmented)).
struct CTCancelWaySegment: View {
    let value: CancelChannel?
    let onTap: (CancelChannel) -> Void
    @Environment(\.colorScheme) private var scheme

    private struct Item: Identifiable {
        let value: CancelChannel
        let title: String
        var id: CancelChannel { value }
    }

    private static let items: [Item] = [Item(value: .online, title: "Online"), Item(value: .email, title: "E-Mail"), Item(value: .letter, title: "Brief"),
                                        Item(value: .phone, title: "Telefon")]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CTCancelWaySegment.items) { it in
                let on = value == it.value
                Button {
                    onTap(it.value)
                } label: {
                    Text(it.title)
                        .font(.subheadline.weight(on ? .semibold : .medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(on ? KColor.ink : KColor.ink2)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(on ? (scheme == .dark ? KColor.ink3.opacity(0.45) : KColor.surface) : Color.clear)
                                .shadow(color: on ? KColor.ink.opacity(0.08) : .clear, radius: 2, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(it.title)
                .accessibilityAddTraits(on ? .isSelected : [])
                .accessibilityIdentifier("cancelWay." + it.value.rawValue)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.field))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kündigungsweg")
    }
}

// MARK: - Drehrad

/// Drehrad mit einer oder mehreren Spalten (Web `whFill`, SwiftUI-Entsprechung `Picker(.wheel)`): eine gemeinsame
/// UIPickerView mit Spalten wie der iOS-Timer – zwei `Picker(.wheel)` nebeneinander überlappen sich beim Antippen.
/// Erst der Knopf «… übernehmen» darunter setzt den Wert (Web v149/v151).
struct CTWheelPicker: UIViewRepresentable {
    /// Texte je Spalte
    var columns: [[String]]
    /// Gewählte Zeile je Spalte
    var selection: [Int]
    /// Breitenanteile je Spalte (Summe ≤ 1)
    var widths: [CGFloat] = []
    var accessibilityLabels: [String] = []
    var onChange: (_ column: Int, _ row: Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIPickerView {
        let p = UIPickerView()
        p.dataSource = context.coordinator
        p.delegate = context.coordinator
        p.setContentHuggingPriority(.defaultLow, for: .horizontal)
        p.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        p.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        for (i, r) in selection.enumerated() where i < columns.count && r >= 0 && r < columns[i].count {
            p.selectRow(r, inComponent: i, animated: false)
        }
        return p
    }

    func updateUIView(_ p: UIPickerView, context: Context) {
        let old = context.coordinator.parent.columns
        context.coordinator.parent = self
        if old != columns { p.reloadAllComponents() }
        for (i, r) in selection.enumerated() where i < columns.count && r >= 0 && r < columns[i].count {
            if p.selectedRow(inComponent: i) != r { p.selectRow(r, inComponent: i, animated: true) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewAccessibilityDelegate {
        var parent: CTWheelPicker

        init(_ parent: CTWheelPicker) {
            self.parent = parent
        }

        func numberOfComponents(in pickerView: UIPickerView) -> Int { parent.columns.count }

        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
            component < parent.columns.count ? parent.columns[component].count : 0
        }

        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            guard component < parent.columns.count, row < parent.columns[component].count else { return nil }
            return parent.columns[component][row]
        }

        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat {
            let w = max(pickerView.bounds.width, 240)
            let n = max(1, parent.columns.count)
            let f = component < parent.widths.count ? parent.widths[component] : 1 / CGFloat(n)
            return max(60, w * f - 8)
        }

        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { 40 }

        func pickerView(_ pickerView: UIPickerView, accessibilityLabelForComponent component: Int) -> String? {
            component < parent.accessibilityLabels.count ? parent.accessibilityLabels[component] : nil
        }

        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            parent.onChange(component, row)
        }
    }
}

// MARK: - Tagesraster «Zahlung am»

/// Tagesraster (Web `dgHtml`, v159; SwiftUI LazyVGrid 7 Spalten): Tag antippen übernimmt und klappt zu; bei Rhythmus ≥ 2 Monate
/// darüber 12 Monate, die ganze Reihe markiert (z.B. Jan/Apr/Jul/Okt), Monat antippen übernimmt und bleibt offen.
struct CTDueGrid: View {
    let day: Int
    /// Monat 1–12 der gewählten Zahlung
    let month: Int
    let cycle: Int
    let onDay: (Int) -> Void
    let onMonth: (Int) -> Void

    var body: some View {
        VStack(spacing: 12) {
            if ContractFormRules.dueGridShowsMonths(cycle: cycle) {
                let on = ContractFormRules.dueGridMonths(month: month, cycle: cycle)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                    ForEach(1...12, id: \.self) { m in
                        let sel = on.contains(m)
                        Button {
                            onMonth(m)
                        } label: {
                            Text(Format.monthShort[m - 1])
                                .font(.subheadline.weight(sel ? .semibold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .foregroundStyle(sel ? KColor.surface : KColor.ink)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(sel ? KColor.teal : KColor.surface))
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(sel ? Color.clear : KColor.line, lineWidth: 1))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Format.monthNames[m - 1])
                        .accessibilityAddTraits(sel ? .isSelected : [])
                        .accessibilityIdentifier("due.month.\(m)")
                    }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(1...31, id: \.self) { d in
                    let sel = d == day
                    Button {
                        onDay(d)
                    } label: {
                        Text(verbatim: "\(d)")
                            .font(.body.weight(sel ? .semibold : .regular).monospacedDigit())
                            .frame(width: 38, height: 38)
                            .foregroundStyle(sel ? KColor.surface : KColor.ink)
                            .background(Circle().fill(sel ? KColor.teal : Color.clear))
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(d).")
                    .accessibilityAddTraits(sel ? .isSelected : [])
                    .accessibilityIdentifier("due.day.\(d)")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Kacheln «pro Monat | pro Jahr»

/// Kacheln über «Kosten» (Web #fKz, `paintKz`), live aus dem Entwurf
struct CTFormKeyTiles: View {
    let month: String
    let year: String
    let currency: String

    var body: some View {
        HStack(spacing: 10) {
            tile("pro Monat", month, id: "form.kz.month")
            tile("pro Jahr", year, id: "form.kz.year")
        }
    }

    private func tile(_ title: String, _ value: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(KColor.ink2)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(KColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(verbatim: currency)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(KColor.ink2)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: KMetric.radius, style: .continuous).fill(KColor.surface))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}
