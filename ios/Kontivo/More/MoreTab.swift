import SwiftUI
import UniformTypeIdentifiers
import KontivoCore

/// Tab «Mehr»: Darstellung, Währung, Verwalten, Daten, Hilfe, Rechtliches (Reihenfolge wie die Web-App).
struct MoreTab: View {
    @Environment(AppModel.self) private var model
    @State private var flow = MoreDataFlow()
    @State private var moreCurrencies = false

    private var requests: MoreRequests { MoreRequests.shared }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                MoreThemeGroup()
                MoreCurrencyGroup(expanded: $moreCurrencies)
                MoreManageGroup()
                MoreDataGroup(flow: flow)
                MoreHelpGroup()
                MoreLegalGroup()
                MoreBrandFooter()
            }
            .padding(.horizontal, KMetric.gutter)
            .padding(.top, 6)
            .padding(.bottom, 28)
            .kContentWidth()
        }
        .kPageBackground()
        .navigationTitle("Mehr")
        .fileImporter(isPresented: $flow.showImporter, allowedContentTypes: flow.importTypes) { result in
            flow.handleImport(result, model: model)
        }
        .alert(flow.ask?.title ?? "", isPresented: askBinding, presenting: flow.ask) { a in
            if let c = a.confirm {
                Button(c, role: a.destructive ? ButtonRole.destructive : nil) { flow.perform(a) }
                Button("Abbrechen", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { a in
            Text(a.message)
        }
        .onAppear {
            if MoreCurrencyPicker.more.contains(model.data.settings.homeCurrency) { moreCurrencies = true }
            checkPending()
        }
        .onChange(of: requests.token) { _, _ in checkPending() }
        .onChange(of: model.data.settings.homeCurrency) { _, c in
            if MoreCurrencyPicker.more.contains(c) { moreCurrencies = true }
        }
    }

    private var askBinding: Binding<Bool> {
        Binding(get: { flow.ask != nil }, set: { if !$0 { flow.ask = nil } })
    }

    /// «Backup laden» von aussen (Einführung, Leerseite) – Dateiauswahl öffnen, sobald vorherige Fenster zu sind.
    private func checkPending() {
        guard let delay = requests.consume() else { return }
        let f = flow
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            f.startImport(.backup)
        }
    }
}

// MARK: - Bausteine

/// Gruppe wie `.sgroup` der Web-App: weisse Karte, Titel klein oben in der Karte.
struct MoreGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(KColor.ink3)
                .padding(.bottom, 10)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(.horizontal, 15)
        .padding(.top, 13)
        .padding(.bottom, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: KMetric.radius, style: .continuous).fill(KColor.surface))
    }
}

/// Trennlinie zwischen Zeilen einer Gruppe
struct MoreLine: View {
    var body: some View {
        Rectangle().fill(KColor.line).frame(height: 1).accessibilityHidden(true)
    }
}

/// Zeile mit Titel, Untertitel, rechts Zusammenfassung und Pfeil (wie `.srowbtn`)
struct MoreRow: View {
    enum Tone { case plain, warn, ok }

    let title: String
    let subtitle: String
    var trailing: String? = nil
    var tone: Tone = .plain
    var bold: Bool = false
    var first: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KColor.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(KColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let t = trailing, !t.isEmpty {
                    Text(t)
                        .font(.caption.weight(bold ? .semibold : .regular))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KColor.ink3)
                    .accessibilityHidden(true)
            }
            .padding(.top, first ? 2 : 12)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var color: Color {
        switch tone {
        case .plain: return KColor.ink3
        case .warn: return KColor.warn
        case .ok: return KColor.ok
        }
    }
}

/// Kachel der Gruppe «Daten» (wie `.tile`)
struct MoreTile: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(KColor.teal)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(KColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KColor.field))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Darstellung

struct MoreThemeGroup: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        MoreGroup(title: "Darstellung") {
            Picker("Darstellung", selection: themeBinding) {
                Text("Automatisch").tag(KontivoCore.Theme.auto)
                Text("Hell").tag(KontivoCore.Theme.light)
                Text("Dunkel").tag(KontivoCore.Theme.dark)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Darstellung")
        }
    }

    private var themeBinding: Binding<KontivoCore.Theme> {
        Binding(get: { model.data.settings.theme },
                set: { t in
                    guard t != model.data.settings.theme else { return }
                    model.update { $0.settings.theme = t }
                })
    }
}

// MARK: - Währung

struct MoreCurrencyGroup: View {
    @Environment(AppModel.self) private var model
    @Binding var expanded: Bool

    var body: some View {
        MoreGroup(title: "Währung") {
            Text("Hauptwährung für alle Summen")
                .font(.caption)
                .foregroundStyle(KColor.ink2)
                .padding(.bottom, 8)
            MoreCurrencyPicker(selection: model.data.settings.homeCurrency, expanded: $expanded) { c in pick(c) }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(RateService.stampText(model.data.settings))
                    .font(.caption)
                    .foregroundStyle(KColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Aktualisieren") {
                    Task { await RateService.refreshIfNeeded(model, force: true) }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(KColor.teal)
                .buttonStyle(.plain)
                .fixedSize()
            }
            .padding(.top, 10)
        }
    }

    /// Tippen auf eine andere Währung: speichern, Kurse laden (ohne Zwang), Toast «Hauptwährung: XXX».
    private func pick(_ c: Currency) {
        guard c != model.data.settings.homeCurrency else { return }
        model.update { $0.settings.homeCurrency = c }
        model.toast("Hauptwährung: " + c.rawValue)
        Task { await RateService.refreshIfNeeded(model, force: false) }
    }
}

// MARK: - Verwalten

/// Zusammenfassungen rechts in «Verwalten» (wie `paintMdSummary`)
struct MoreManageSummary {
    var partners: String
    var partnerWarn: Bool
    var persons: String
    var categories: String
    var quality: String
    var qualityTone: MoreRow.Tone
    var qualityBold: Bool
    var qualitySubtitle: String

    @MainActor init(model: AppModel) {
        let data = model.data
        let today = model.today
        let groups = Partners.groups(data, today: today)
        let dups = groups.filter { $0.isDuplicate }.count
        partners = dups > 0 ? Format.count(dups, "Dublette", "Dubletten") : (groups.isEmpty ? "–" : "\(groups.count)")
        partnerWarn = dups > 0

        let names = data.persons.map { $0.name }
        persons = names.count <= 2 ? names.joined(separator: ", ") : "\(names.count) Personen"
        categories = "\(data.categories.count)"

        let running = model.calc.active.count
        let files = model.files
        let report = Quality.report(data, today: today, hasFile: { files.has($0) })
        let open = report.affectedCount
        if running == 0 {
            quality = "–"
            qualityTone = .plain
        } else if open > 0 {
            quality = Format.count(open, "Eintrag offen", "Einträge offen")
            qualityTone = .warn
        } else {
            quality = "Sauber gepflegt ✓"
            qualityTone = .ok
        }
        qualityBold = running > 0
        qualitySubtitle = running > 0 && open == 0 ? "Alles da, nichts fehlt. Gut gemacht." : "Was bei deinen Verträgen noch fehlt"
    }
}

struct MoreManageGroup: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let sum = MoreManageSummary(model: model)
        MoreGroup(title: "Verwalten") {
            MoreRow(title: "Vertragspartner", subtitle: "Namen, Logos und Adressen deiner Anbieter",
                    trailing: sum.partners, tone: sum.partnerWarn ? .warn : .plain, bold: sum.partnerWarn, first: true) {
                model.present(.manage(.partners))
            }
            MoreLine()
            MoreRow(title: "Inhaber", subtitle: "Personen, Absender und Unterschrift", trailing: sum.persons) {
                model.present(.manage(.persons))
            }
            MoreLine()
            MoreRow(title: "Kategorien", subtitle: "Gruppen für deine Verträge: Name, Farbe, Reihenfolge", trailing: sum.categories) {
                model.present(.manage(.categories))
            }
            MoreLine()
            MoreRow(title: "Datenqualität", subtitle: sum.qualitySubtitle, trailing: sum.quality,
                    tone: sum.qualityTone, bold: sum.qualityBold) {
                model.present(.manage(.quality))
            }
        }
    }
}

// MARK: - Daten

struct MoreDataGroup: View {
    @Environment(AppModel.self) private var model
    let flow: MoreDataFlow

    var body: some View {
        MoreGroup(title: "Daten") {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    MoreTile(symbol: "square.and.arrow.up", title: "Backup erstellen") { flow.exportBackup(model: model) }
                    MoreTile(symbol: "square.and.arrow.down", title: "Backup laden") { flow.startImport(.backup) }
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    MoreTile(symbol: "tablecells", title: "CSV importieren") { flow.startImport(.csv) }
                    MoreTile(symbol: "tablecells", title: "CSV exportieren") { flow.exportCSV(model: model) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(flow.working)
            Text("**Backup:** alles inkl. Logos und Dokumente, auch für den Gerätewechsel.\n**CSV:** nur Tabellendaten, z.B. für Excel. Der Import erkennt gängige Spaltennamen.")
                .font(.caption)
                .foregroundStyle(KColor.ink2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            Button {
                flow.askWipe(model: model)
            } label: {
                Text("Alle Daten löschen")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KColor.alert)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.alert.opacity(0.08)))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
    }
}

// MARK: - Hilfe

struct MoreHelpGroup: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        MoreGroup(title: "Hilfe") {
            MoreRow(title: "Einführung ansehen", subtitle: "Die wichtigsten Funktionen in einer Minute", first: true) {
                model.onboarding = .tour
            }
        }
    }
}

// MARK: - Rechtliches

enum MoreTexts {
    static let disclaimer = [
        "Kontivo ist ein Hilfsmittel zur persönlichen Übersicht. Alle Berechnungen (Kosten, Fristen, Kündigungstermine, Wechselkurse) erfolgen ohne Gewähr auf Basis deiner Eingaben. Massgebend sind allein dein Vertrag und die Angaben des Anbieters.",
        "Kündigungstexte, Katalogangaben und Hinweise sind unverbindliche Vorlagen und ersetzen keine Rechts- oder Finanzberatung. Prüfe Fristen und Formvorschriften selbst. Für verpasste Fristen, falsche Beträge oder Datenverlust wird keine Haftung übernommen, soweit gesetzlich zulässig.",
    ]

    static let privacy = [
        "Kontivo hat kein Benutzerkonto, keine Werbung, kein Tracking und keine Analyse. Deine Verträge, Logos und Dokumente werden nur lokal auf diesem Gerät gespeichert und nicht an Kontivo übermittelt.",
        "Für einzelne Funktionen ruft die App externe Dienste auf. Dabei wird technisch bedingt deine IP-Adresse übertragen:",
        "• Wechselkurse: Frankfurter (Referenzkurse der EZB), ersatzweise open.er-api.com. Es werden keine Vertragsdaten gesendet.\n• Logo-Suche und Vertragspartner-Vorschläge: Nur der eingegebene Firmenname bzw. die Website geht an Apple (iTunes-Suche), Wikidata/Wikimedia, Google (Symbol-Dienst) und unavatar.io; das App-Symbol wird direkt von der Website des Anbieters geladen. Ein eingefügter Bild-Link wird direkt von dieser Adresse geladen.\n• Adresssuche für das Kündigungsschreiben: Nur der Firmenname geht an Wikidata und OpenStreetMap (Nominatim).\n• «Logo im Web suchen» öffnet die Google-Bildersuche in deinem Browser.\n• Handschrift-Schriften für Namenszug-Vorschläge sind in der App enthalten (SIL Open Font License), dafür wird nichts geladen.",
        "Backups und CSV-Dateien erstellst und speicherst du selbst. Ohne Backup gehen deine Daten beim Löschen der App verloren. Mit «Alle Daten löschen» entfernst du alles vom Gerät.",
    ]

    static let brands = [
        "Logos, Marken und Firmennamen gehören ihren jeweiligen Inhabern. Sie werden nur zur Wiedererkennung deiner eigenen Verträge angezeigt. Kontivo steht in keiner Verbindung zu den genannten Anbietern und wird von ihnen weder unterstützt noch gesponsert.",
    ]
}

struct MoreLegalGroup: View {
    var body: some View {
        MoreGroup(title: "Rechtliches") {
            MoreLegalItem(title: "Haftungsausschluss", paragraphs: MoreTexts.disclaimer, first: true)
            MoreLine()
            MoreLegalItem(title: "Datenschutz", paragraphs: MoreTexts.privacy)
            MoreLine()
            MoreLegalItem(title: "Marken und Logos", paragraphs: MoreTexts.brands)
        }
    }
}

/// Aufklappbarer Rechtstext (wie `<details class="legal">`)
struct MoreLegalItem: View {
    let title: String
    let paragraphs: [String]
    var first: Bool = false
    @State private var open = false

    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(paragraphs, id: \.self) { p in
                    Text(verbatim: p)
                        .font(.caption)
                        .foregroundStyle(KColor.ink2)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 8)
        } label: {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(KColor.ink)
        }
        .tint(KColor.ink3)
        .padding(.top, first ? 2 : 10)
        .padding(.bottom, 10)
    }
}

// MARK: - Fuss

struct MoreBrandFooter: View {
    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image("Logo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Kontivo")
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(KColor.ink)
                    Text("Deine Verträge, ganz entspannt")
                        .font(.subheadline)
                        .foregroundStyle(KColor.ink2)
                }
            }
            .accessibilityElement(children: .combine)
            .padding(.top, 16)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { features }
                VStack(spacing: 6) { features }
            }
            .padding(.top, 14)

            Text("Version " + version)
                .font(.caption2)
                .foregroundStyle(KColor.ink3)
                .padding(.top, 10)

            HStack(spacing: 4) {
                Text("Made with ❤️ in")
                MoreSwissMark()
                    .frame(width: 13, height: 13)
            }
            .font(.caption)
            .foregroundStyle(KColor.ink3)
            .padding(.top, 30)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Made with ❤️ in der Schweiz")
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var features: some View {
        MoreFeature(text: "Ohne Bankanbindung")
        MoreFeature(text: "Keine Werbung")
        MoreFeature(text: "Daten bleiben privat")
    }
}

struct MoreFeature: View {
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(KColor.teal)
                .accessibilityHidden(true)
            Text(text)
                .font(.caption)
                .foregroundStyle(KColor.ink2)
                .lineLimit(1)
        }
    }
}
