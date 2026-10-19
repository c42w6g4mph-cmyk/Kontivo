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
    /// Unterbereiche (Web v218 `goMiss`: pAmt, xDate, xAmt)
    case priceAmount, extraDate, extraAmount

    /// Textfeld (bekommt den Fokus), sonst nur scrollen
    var isText: Bool {
        switch self {
        case .label, .partner, .amount, .payAccount, .cancelURL, .cancelMail, .customerNo, .contractNo, .address, .web, .tel, .mail, .note,
             .priceAmount, .extraAmount:
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

// MARK: - Abschnitt und Karte (Web `.fsec` + `.fcard` + `.fnote`)

/// Abschnitt des Formulars wie in der Web-App: Titel 13/600 Tinte 2 (22 oben, 8 unten, 2 seitlich), Karte (Fläche, Radius 16,
/// Innenabstand 0 13) mit Zeilen ab 48 pt und Trennlinien, Fussnote 12.5 Tinte 2 (8 oben). `plain`: ohne Karte (Kopf, Hinweise).
/// Ersetzt `Section` im Formular (eigene Masse statt Inset-Grouped des Systems).
struct CTSection<Content: View, Header: View, Footer: View>: View {
    var plain = false
    let content: Content
    let header: Header
    let footer: Footer

    init(plain: Bool = false, @ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header, @ViewBuilder footer: () -> Footer) {
        self.plain = plain
        self.content = content()
        self.header = header()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(KColor.ink2)
                .textCase(nil)
                .ctLine(18.85)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
                .padding(.top, 22)
                .padding(.bottom, 8)
                .modifier(CTHideIfEmpty(isEmpty: Header.self == EmptyView.self))
            if plain {
                VStack(alignment: .leading, spacing: 0) { content }
            } else {
                CTCardRows { content }
                    .padding(.horizontal, 13)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(KColor.surface))
            }
            footer
                .font(.system(size: 12.5))
                .foregroundStyle(KColor.ink2)
                .ctLines(12.5, 19.375)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
                .padding(.top, 8)
                .modifier(CTHideIfEmpty(isEmpty: Footer.self == EmptyView.self))
        }
    }
}

extension CTSection where Footer == EmptyView {
    init(plain: Bool = false, @ViewBuilder content: () -> Content, @ViewBuilder header: () -> Header) {
        self.init(plain: plain, content: content, header: header, footer: { EmptyView() })
    }
}

extension CTSection where Header == EmptyView, Footer == EmptyView {
    init(plain: Bool = false, @ViewBuilder content: () -> Content) {
        self.init(plain: plain, content: content, header: { EmptyView() }, footer: { EmptyView() })
    }
}

/// Leerer Kopf/Fuss ohne Abstand
private struct CTHideIfEmpty: ViewModifier {
    let isEmpty: Bool
    func body(content: Content) -> some View {
        if isEmpty { EmptyView() } else { content }
    }
}

/// Mindesthöhe einer Kartenzeile abweichend von 48 (Web `.fadd` 46)
struct CTRowMinHeightTrait: _ViewTraitKey {
    static let defaultValue: CGFloat? = nil
}

extension View {
    /// Mindesthöhe dieser Zeile in `CTCardRows` (inkl. Trennlinie darüber, wie Web `min-height` mit `box-sizing: border-box`)
    func ctRowMinHeight(_ h: CGFloat) -> some View {
        _trait(CTRowMinHeightTrait.self, h)
    }
}

/// Zeilen einer Karte untereinander, jede mindestens 48 pt hoch (Web `.frow` min-height 48, 4 0 + Feld 39.2), Trennlinie 1 pt
/// (Web `border-top`, zählt zur Zeilenhöhe) über der Kartenbreite (innerhalb des Innenabstands) zwischen den Zeilen
struct CTCardRows<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        _VariadicView.Tree(CTCardRowsLayout()) { content }
    }
}

private struct CTCardRowsLayout: _VariadicView_UnaryViewRoot {
    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        let first = children.first?.id
        VStack(alignment: .leading, spacing: 0) {
            ForEach(children) { child in
                let isFirst = child.id == first
                let minH = child[CTRowMinHeightTrait.self] ?? 48
                if !isFirst { Rectangle().fill(KColor.line).frame(height: 1) }
                child
                    .frame(maxWidth: .infinity, minHeight: max(0, minH - (isFirst ? 0 : 1)), alignment: .leading)
            }
        }
    }
}

/// Menü-Auswahl als Zeile (Web `.frow` mit `select`): Beschriftung links, Wert rechts 16/500 in Messing (leer: Tinte 3) mit «⌄»;
/// die Auswahl selbst ist ein `Picker` im Menü (Haken beim gewählten Wert).
struct CTMenuRow<P: View>: View {
    let title: String
    let value: String
    var muted = false
    var identifier = ""
    let picker: P
    init(_ title: String, value: String, muted: Bool = false, identifier: String = "", @ViewBuilder picker: () -> P) {
        self.title = title
        self.value = value
        self.muted = muted
        self.identifier = identifier
        self.picker = picker()
    }
    var body: some View {
        HStack(spacing: 12) {
            CTRowLabel(title)
            Spacer(minLength: 8)
            Menu {
                picker
                    .pickerStyle(.inline)
            } label: {
                CTMenuValue(text: value, muted: muted)
            }
            .accessibilityLabel(title + ", " + value)
            .accessibilityIdentifier(identifier)
        }
    }
}

/// Wert eines Auswahlfelds wie Web `select`: 16/500 Messing (leer Tinte 3), «⌄» 13 Tinte 2
struct CTMenuValue: View {
    let text: String
    var muted = false
    var body: some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(muted ? KColor.ink2 : KColor.teal)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(KColor.ink2)
        }
        .fixedSize()
        .contentShape(Rectangle())
    }
}

// MARK: - Markierung fehlender Angaben (Web v218/v219 `goMiss`, `.frow.miss`)

/// Zeile kurz als abgerundete Fläche (Radius 10, 3 oben/unten, 8 über den Rand, Rot 16 %) markieren; 40 % halten, dann bis 1.8 s
/// ausblenden. Kopffelder (`ring`) mit rotem Rahmen 2 pt.
struct CTMissMark: ViewModifier {
    let form: CTFormState
    let field: ContractFormField
    var ring = false
    var radius: CGFloat = 10
    @State private var on = 0.0

    func body(content: Content) -> some View {
        content
            .background {
                if !ring {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(KColor.alert.opacity(0.16))
                        .padding(.vertical, 3)
                        .padding(.horizontal, -8)
                        .opacity(on)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if ring {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(KColor.alert, lineWidth: 2)
                        .padding(-2)
                        .opacity(on)
                        .allowsHitTesting(false)
                }
            }
            .onChange(of: form.missToken) { _, _ in
                guard form.missField == field else { return }
                on = 1
                withAnimation(.easeOut(duration: 1.08).delay(0.72)) { on = 0 }
            }
    }
}

extension View {
    func ctMiss(_ form: CTFormState, _ field: ContractFormField, ring: Bool = false, radius: CGFloat = 10) -> some View {
        modifier(CTMissMark(form: form, field: field, ring: ring, radius: radius))
    }
}

// MARK: - Zeilen

/// Beschriftung links in einer Formularzeile (Web .frow label: grau)
struct CTRowLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(KColor.ink2)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .ctLine(21.75)
    }
}

/// Zeile «Beschriftung | Textfeld rechts» (Web .frow mit Eingabe in teal, Platzhalter «hinzufügen»)
struct CTFormTextRow: View {
    let title: String
    @Binding var text: String
    var placeholder = ContractFormRules.placeholder
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
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(KColor.ink3))
                .font(.system(size: 16, weight: .medium))
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
                // Web v217: leeres Datum zeigt «hinzufügen» wie die übrigen Felder
                Button {
                    set(fallback)
                } label: {
                    Text(ContractFormRules.placeholder)
                        .font(.system(size: 16))
                        .foregroundStyle(KColor.ink3)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(title + " wählen")
                .accessibilityIdentifier(identifier.isEmpty ? "" : identifier + ".pick")
            }
        }
        // Web `input[type=date]` 41.2 hoch (8 2 Innenabstand, 16 px) + `.frow` 4 0 → Zeile 50.2 inkl. Trennlinie
        .frame(minHeight: 41.2)
        .padding(.vertical, 4)
    }
}

/// Knopf einer Knopfzeile (Web .chip in .fchq): Rahmen, gewählt gefüllt in teal. `fill` = volle Spaltenbreite.
struct CTFormChip: View {
    let title: String
    let isOn: Bool
    var fill = true
    var enabled = true
    var identifier = ""
    /// Web `.fchq .chip` 13.5 px (Zeile 19.575); freie Chips (`.chips .chip`, z.B. Personen) nutzen `Chip`
    var fontSize: CGFloat = 13.5
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Web v164 `.chips button[aria-pressed=true]`: Fläche Tinte, Schrift Papier, Rand Messing; sonst Rand `--line`, Tinte 2
            Text(title)
                .font(.system(size: fontSize, weight: isOn ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .ctLine(fontSize * 1.45)
                .padding(.horizontal, fill ? 4 : 12).padding(.vertical, 8)
                .frame(maxWidth: fill ? .infinity : nil)
                .foregroundStyle(isOn ? KColor.paper : KColor.ink2)
                .background(Capsule().fill(isOn ? KColor.ink : Color.clear))
                .overlay(Capsule().strokeBorder(isOn ? KColor.teal : KColor.line, lineWidth: 1))
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

    /// Web `.fok` (v164): Messing `--brassFab`, Schrift `--onBrass` 15/600, 11 Innenabstand, Radius 10
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(KColor.onBrass)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.brassFab))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4).padding(.bottom, 12)
        .accessibilityIdentifier(identifier)
    }
}

/// «+ Preisänderung», «+ Sonderzahlung» (Web .fadd)
struct CTFormAddRow: View {
    let title: String
    var identifier = ""
    let action: () -> Void

    var body: some View {
        // Web `.fadd`: 15/600 Messing, «+» davor, Abstand 8
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                Text(title).font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(KColor.teal)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .ctRowMinHeight(46)
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

    /// Aus `CancelChannel.allCases` (Web v210: Online · E-Mail · Brief · Telefon). Kommt der Weg «Telefon» im Kern dazu
    /// (`webText` «Telefon»), erscheint die vierte Kachel ohne weitere Änderung.
    private static let items: [Item] = CancelChannel.allCases.map { ch in
        let t: [String: String] = ["Online / Kundenkonto": "Online", "E-Mail": "E-Mail", "Brief": "Brief", "Telefon": "Telefon"]
        return Item(value: ch, title: t[ch.webText] ?? ch.webText)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CTCancelWaySegment.items) { it in
                let on = value == it.value
                Button {
                    onTap(it.value)
                } label: {
                    // Web `.seg2 button`: 14/500 (gewählt 600), Zeile 20.3, Innenabstand 7
                    Text(it.title)
                        .font(.system(size: 14, weight: on ? .semibold : .medium))
                        .lineLimit(1)
                        .ctLine(20.3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
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
        // Web `.seg2`: Tinte 8 %
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.ink.opacity(0.08)))
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

    /// Web `#fKz`: zwei Kacheln (Abstand 8, 12 oben), Fläche `--field`, Radius 12, 10/12; Titel 12.5 Tinte 2, Wert Serif 22/500
    var body: some View {
        HStack(spacing: 8) {
            tile("pro Monat", month, id: "form.kz.month")
            tile("pro Jahr", year, id: "form.kz.year")
        }
        .padding(.top, 12)
        .padding(.bottom, 0)
    }

    private func tile(_ title: String, _ value: String, id: String) -> some View {
        // Web: `small` 12.5 (Zeile 18.125), Wert als Zeile 31.9 (22 × 1.45), Währung Serif 13 mit 3 Abstand → Kachel 70
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(KColor.ink2)
                .ctLine(18.125)
            (Text(verbatim: value).font(KFont.serif(22, .medium)).tracking(-0.22)
             + Text(verbatim: " " + currency).font(KFont.serif(13, .medium)).foregroundColor(KColor.ink2))
                .foregroundStyle(KColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .ctLineExact(31.9)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KColor.field))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}
