import SwiftUI
import KontivoCore

// Gemeinsame Hilfen des Bereichs «Verträge» (Tab, Detail, Formular). Alle Typen mit Präfix CT.

// MARK: - Zahlen

enum CTNumber {
    /// Betrag aus einem Eingabefeld lesen – `Format.parseAmount` (1:1 Web `parseAmt`):
    /// «59.90», «59,90», «1’284.50», «1'284,50», «1.284,50», «1.234» = 1234. Leer oder nicht lesbar (z.B. «12abc») → nil.
    /// Negative Werte bleiben negativ (die Prüfung macht der Aufrufer).
    static func parse(_ s: String) -> Double? {
        Format.parseAmount(s)
    }

    /// Kündigungsfrist prüfen (Web `noticeVal`): leer → 0; keine ganze Zahl oder negativ → nil;
    /// bei «. im Monat» nur 1–28.
    static func noticeValue(_ s: String, unit: NoticeUnit) -> Int? {
        Format.noticeValue(s, unit: unit)
    }

    /// Ganze Zahl für Hinweise während der Eingabe (Laufzeit-Hinweis): ungültig → 0.
    static func int(_ s: String, unit: NoticeUnit = .months) -> Int {
        noticeValue(s, unit: unit) ?? 0
    }

    /// Betrag für ein Eingabefeld (Web `amtIn`): «59.90», bei EUR «59,90»
    static func field(_ v: Double, _ currency: Currency? = nil) -> String { Format.amountInput(v, currency) }

    /// Platzhalter eines Betragsfelds im Zahlenformat der Währung (Web `amtPh`): «59,90» bzw. «59.90»
    static func placeholder(_ currency: Currency?) -> String {
        Format.numberStyle(currency) == .de ? "59,90" : "59.90"
    }
}

// MARK: - Sortieren (stabil wie JS)

extension Array {
    func ctStableSorted(by less: (Element, Element) -> Bool) -> [Element] {
        enumerated().sorted { a, b in
            if less(a.element, b.element) { return true }
            if less(b.element, a.element) { return false }
            return a.offset < b.offset
        }.map { $0.element }
    }
}

// MARK: - Datum

extension Binding where Value == Day {
    /// Für DatePicker (Mitternacht im aktuellen Kalender)
    var ctDate: Binding<Date> {
        Binding<Date>(
            get: { self.wrappedValue.date() },
            set: { self.wrappedValue = Day(date: $0) }
        )
    }
}

/// Datumszeile, die leer sein darf (Vertragsbeginn, Vertragsende, Probeabo …)
struct CTOptionalDateRow: View {
    let title: String
    @Binding var day: Day?
    var fallback: Day

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(KColor.ink)
            Spacer(minLength: 4)
            if let d = day {
                DatePicker(title, selection: Binding(get: { d.date() }, set: { day = Day(date: $0) }), displayedComponents: .date)
                    .labelsHidden()
                Button {
                    day = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(KColor.ink3)
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(title + " entfernen")
            } else {
                Button("Datum wählen") { day = fallback }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(title + " wählen")
            }
        }
    }
}

// MARK: - Fliesslayout (Chips, Pillen)

struct CTFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineH: CGFloat = 0
        var widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            let w = min(s.width, maxW)
            if x > 0 && x + w > maxW {
                y += lineH + lineSpacing
                x = 0
                lineH = 0
            }
            x += w + spacing
            lineH = max(lineH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: maxW.isFinite ? maxW : widest, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            let w = min(s.width, maxW)
            if x > 0 && x + w > maxW {
                y += lineH + lineSpacing
                x = 0
                lineH = 0
            }
            v.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), anchor: .topLeading,
                    proposal: ProposedViewSize(width: w, height: s.height))
            x += w + spacing
            lineH = max(lineH, s.height)
        }
    }
}

// MARK: - Kleine Bausteine

/// Graue Etikette auf der Vertragskarte («gekündigt per 30.11.26», «pausiert»)
struct CTTag: View {
    let text: String
    var tone: Color = KColor.ink2
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(tone)
            .background(Capsule().fill(tone.opacity(0.12)))
    }
}

/// Kleine Markierung in Listen («aktuell», «geplant», «Gutschrift»)
struct CTMiniTag: View {
    let text: String
    var tone: Color = KColor.teal
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 1)
            .foregroundStyle(tone)
            .background(Capsule().fill(tone.opacity(0.13)))
    }
}

/// ID als Identifiable (für .sheet(item:))
struct CTIDItem: Identifiable, Hashable {
    let id: UUID
}

/// Bild als Identifiable (Zuschneiden)
struct CTImageItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - Texte

enum CTText {
    /// Beschriftung des Kündigungsknopfs je Kündigungsweg
    static func cancelButton(_ v: CancelVia) -> String {
        switch v {
        case .online: return "Online kündigen"
        case .mail: return "Per E-Mail kündigen"
        case .post: return "Kündigungsschreiben"
        case .none: return "Kündigen …"
        }
    }

    /// «1 Vertrag» / «3 Verträge»
    static func contracts(_ n: Int) -> String { Format.count(n, "Vertrag", "Verträge") }

    /// Dokument ist ein PDF (gespeicherter Typ oder Endung)
    static func isPDF(_ d: Attachment) -> Bool {
        d.type.lowercased() == "application/pdf" || d.name.lowercased().hasSuffix(".pdf")
    }
}

/// Sprungziel beim Öffnen des Formulars (Web `formGo(id)`): Feld, zu dem das Formular scrollt und das es fokussiert.
enum ContractFormFocus: String, Hashable {
    /// Vertragsende (Web `fEnd`, «Wieder aktiv setzen» bei abgelaufener Laufzeit)
    case end
    /// Kundennummer (Web `fCustNo`, «Kundennummer fehlt» → «Nummer eintragen»)
    case customerNo
    /// Kündigungslink (Web `fCancUrl`, «Kein Link hinterlegt» bei Kündigungsweg Online)
    case cancelURL
    /// Website (Web `fWeb`, «Kein Link hinterlegt» ohne Kündigungsweg Online)
    case web
    /// E-Mail unter «Kontakt» (Web `fMail`, «E-Mail-Adresse fehlt»)
    case mail
    /// Kündigungsadresse E-Mail (Web `fCancMail`, «E-Mail-Adresse fehlt» bei Kündigungsweg E-Mail)
    case cancelMail
    /// Personen (Web: «Wer kündigt?» → «Person eintragen» öffnet das Formular)
    case holders
}

/// Formular mit Sprungziel öffnen: vor `model.present(.contractForm(.edit(id)))` `ContractFormLaunch.focus = (id, .end)`
/// setzen; das Formular liest es beim Erscheinen mit `take(for:)` (und löscht es).
/// `openMoreFor` = alter Weg (Unterseite «Weitere Angaben»), bleibt bis zum Umbau des Formulars bestehen.
@MainActor
enum ContractFormLaunch {
    static var openMoreFor: UUID?
    static var focus: (id: UUID, field: ContractFormFocus)?

    /// Sprungziel für diesen Vertrag lesen und löschen (nil = keines).
    static func take(for id: UUID) -> ContractFormFocus? {
        guard let f = focus, f.id == id else { return nil }
        focus = nil
        return f.field
    }

    /// Formular `.edit(id)` mit Sprungziel öffnen, vorher alle Fenster schliessen (Web `closeSheets(); openForm(c); formGo(…)`).
    static func edit(_ model: AppModel, _ id: UUID, focus field: ContractFormFocus?, then done: (() -> Void)? = nil) {
        focus = field.map { (id: id, field: $0) }
        // bisheriges Formular: Felder ausserhalb der ersten Seite liegen unter «Weitere Angaben»
        if let f = field, f != .end && f != .holders { openMoreFor = id }
        model.cancelFlowPresent(.contractForm(.edit(id)), closingOthers: true, then: done)
    }
}

// MARK: - Aktionen aus Detail, Karten und Fristen

extension AppModel {
    /// «Wieder aktiv setzen» (Web v143): Archiv/Kündigung zurücknehmen; ist die Laufzeit vorbei, Formular beim Vertragsende
    /// öffnen («Wieder aktiv – bitte das neue Vertragsende eintragen»), sonst schliessen mit «Wieder aktiv».
    func ctReactivate(_ id: UUID) {
        guard update({ $0.reactivate(id) }) else { return }
        if data.reactivateNeedsEnd(id, today: today) {
            toast(AppData.reactivateEndToast)
            ContractFormLaunch.edit(self, id, focus: .end)
        } else {
            dismissAll()
            toast(AppData.reactivateToast)
        }
    }
}

#if DEBUG
/// UI-Tests: Startargument «-uiSeed a,b» passt Beispieldaten für Fälle an, die DemoData nicht hat (nichts wird gespeichert):
/// - `mailcheck`: Swisscom «Handy» mit Kündigungsweg E-Mail und Adresse, ohne Kundennummer («Kundennummer fehlt»)
/// - `endsself`: «Fitnessabo» ohne Verlängerung («Endet von selbst», Web v160)
@MainActor
enum CTUITestSeed {
    private static var done = false

    static func applyIfNeeded(_ model: AppModel) {
        guard !done, model.uiTestMode else { return }
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiSeed"), i + 1 < args.count else { return }
        done = true
        let seeds = Set(args[i + 1].split(separator: ",").map { String($0) })
        func contract(label: String) -> UUID? { model.data.contracts.first { $0.label == label }?.id }
        model.update { d in
            if seeds.contains("mailcheck"), let id = contract(label: "Handy"), let k = d.contractIndex(id) {
                d.contracts[k].cancelChannel = .email
                d.contracts[k].mail = "kuendigung@example.ch"
                d.contracts[k].customerNo = ""
                d.contracts[k].contractNo = ""
            }
            if seeds.contains("endsself"), let id = contract(label: "Fitnessabo"), let k = d.contractIndex(id) {
                d.contracts[k].renewMonths = 0
            }
        }
    }
}
#endif
