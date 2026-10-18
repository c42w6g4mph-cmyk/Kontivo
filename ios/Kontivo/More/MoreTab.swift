import SwiftUI
import UniformTypeIdentifiers
import KontivoCore

/// Tab «Mehr»: Bericht, Darstellung, Währung, Verwalten, Daten, Hilfe, Rechtliches, Fusszeile (Reihenfolge wie Web v224).
struct MoreTab: View {
    @Environment(AppModel.self) private var model
    @State private var flow = MoreDataFlow()
    @State private var moreCurrencies = false

    private var requests: MoreRequests { MoreRequests.shared }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 0) {
                KTabHeader(title: "Mehr")
                VStack(spacing: 12) {
                MoreReportGroup()
                MoreThemeGroup()
                MoreCurrencyGroup(expanded: $moreCurrencies)
                MoreManageGroup()
                MoreDataGroup(flow: flow)
                NativeMoreGroup() // Bereich native: Erinnerungen und App-Sperre (Native/NativeMoreGroup.swift)
                MoreHelpGroup()
                MoreLegalGroup()
                }
                .padding(.top, 14)
                .padding(.bottom, 12)
                MoreBrandFooter()
                    .id("more.footer")
            }
            .padding(.horizontal, KMetric.gutter)
            .padding(.bottom, 24)
            .kContentWidth()
        }
        #if DEBUG
        .task {
            // Bildschirmfoto der Fusszeile: «-uiMoreBottom»
            guard ProcessInfo.processInfo.arguments.contains("-uiMoreBottom") else { return }
            try? await Task.sleep(nanoseconds: 600_000_000)
            proxy.scrollTo("more.footer", anchor: .bottom)
        }
        #endif
        }
        .kPageBackground()
        .kTabPage(title: "Mehr")
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
            #if DEBUG
            MoreUITestSeed.applyIfNeeded(model)
            #endif
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

/// Gruppe wie `.sgroup` der Web-App: weisse Fläche Radius 13, Innenabstand 13/15/15, Titel 12.5 pt Semibold `--ink3`.
struct MoreGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(KFont.text(12.5, .semibold))
                .foregroundStyle(KColor.ink3)
                .kLineHeight(12.5, 18.125)
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

/// Trennlinie zwischen Zeilen einer Gruppe (`.srowbtn` border-top 1 px `--line`)
struct MoreLine: View {
    var body: some View {
        Rectangle().fill(KColor.line).frame(height: 1).accessibilityHidden(true)
    }
}

/// Zeile mit Titel, Untertitel und Pfeil (wie `.srowbtn .mdt`): Titel 15.5 pt Semibold, Untertitel 12 pt `--ink3`,
/// `plain` = Titel 16 pt Regular mit Untertitel 12.5 pt (Zeile «Fixkosten-Bericht»).
struct MoreRow: View {
    enum Tone { case plain, warn, ok }

    let title: String
    let subtitle: String
    var trailing: String? = nil
    var tone: Tone = .plain
    var bold: Bool = false
    var first: Bool = false
    var plainTitle: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(plainTitle ? KFont.text(16) : KFont.text(15.5, .semibold))
                        .foregroundStyle(KColor.ink)
                        .kLineHeight(plainTitle ? 16 : 15.5, plainTitle ? 23.2 : 22.5)
                    Text(subtitle)
                        .font(KFont.text(plainTitle ? 12.5 : 12))
                        .foregroundStyle(KColor.ink3)
                        .kLineHeight(plainTitle ? 12.5 : 12, plainTitle ? 18.1 : 17.4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let t = trailing, !t.isEmpty {
                    Text(t)
                        .font(KFont.text(12.5, bold ? .semibold : .regular))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                Text("›").font(KFont.text(12.5)).foregroundStyle(KColor.ink3).accessibilityHidden(true)
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

/// Kachel der Gruppe «Daten» (wie `.tile`): Fläche `--field`, Radius 12, Innenabstand 12, Symbol 22 pt Messing, Titel 13.5 pt Semibold
struct MoreTile: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                KIcon.view(symbol, 22)
                    .foregroundStyle(KColor.teal)
                    .accessibilityHidden(true)
                Text(title)
                    .font(KFont.text(13.5, .semibold))
                    .foregroundStyle(KColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .kLineHeight(13.5, 16.2)
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

// MARK: - Bericht

/// Einstieg «Fixkosten-Bericht» (Web v220). Standard: Auswahl des Berichts (Bereich costs, `MoreReport.openFixReport`).
@MainActor
enum MoreReport {
    static var open: (@MainActor (AppModel) -> Void)? = { MoreReport.openFixReport($0) }
}

struct MoreReportGroup: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        MoreGroup(title: "Bericht") {
            MoreRow(title: "Fixkosten-Bericht", subtitle: "PDF zum Teilen, Ablegen oder Drucken", first: true, plainTitle: true) {
                MoreReport.open?(model)
            }
            .accessibilityIdentifier("more.report")
        }
    }
}

// MARK: - Darstellung

struct MoreThemeGroup: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        MoreGroup(title: "Darstellung") {
            KSegmented(options: [(KontivoCore.Theme.auto, "Automatisch"), (.light, "Hell"), (.dark, "Dunkel")],
                       selection: themeBinding, label: "Darstellung")
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
                .font(KFont.text(12.5))
                .foregroundStyle(KColor.ink2)
                .kLineHeight(12.5, 19.375)
                .padding(.bottom, 8)
            MoreCurrencyPicker(selection: model.data.settings.homeCurrency, expanded: $expanded) { c in pick(c) }
            HStack(alignment: .center, spacing: 10) {
                Text(RateService.stampText(model.data.settings))
                    .font(KFont.text(12.5))
                    .foregroundStyle(KColor.ink2)
                    .kLineHeight(12.5, 19.375)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                Spacer(minLength: 8)
                Button("Aktualisieren") {
                    Task { await RateService.refreshIfNeeded(model, force: true) }
                }
                .font(KFont.text(12.5, .semibold))
                .foregroundStyle(KColor.teal)
                .padding(.vertical, 4)
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

/// Werte rechts in «Verwalten» (wie `paintMdSummary`/`paintVkRow`, iOS-Listenstil seit Web v121)
struct MoreManageSummary {
    /// «27 Vertragspartner», «2 Dubletten» (orange) bzw. «–» (Web `paintMdSummary`)
    var partners: String
    var partnerWarn: Bool
    /// Vornamen bis 2 Personen («Sinan, Lara»), sonst «3 Personen»
    var persons: String
    /// «12 Gruppen»
    var categories: String
    /// Vollständigkeit
    var completeness: CompletenessReport

    @MainActor init(model: AppModel) {
        let data = model.data
        let today = model.today
        let groups = Partners.groups(data, today: today)
        let dups = groups.filter { $0.isDuplicate }.count
        partners = dups > 0 ? Format.count(dups, "Dublette", "Dubletten") : (groups.isEmpty ? "–" : Format.count(groups.count, "Vertragspartner", "Vertragspartner"))
        partnerWarn = dups > 0
        let names = data.persons.map { $0.name }
        persons = names.count <= 2 ? names.map { Format.firstName($0) }.joined(separator: ", ") : "\(names.count) Personen"
        categories = Format.count(data.categories.count, "Gruppe", "Gruppen")
        let files = model.files
        completeness = Completeness.report(data, today: today, hasFile: { files.has($0) })
    }
}

/// Symbol links (wie `.mgi`, v164 neutral): 30 pt, Radius 8, Fläche `--sunken`, Symbol 18 pt `--ink`;
/// Vollständigkeit mit offenen Punkten: Fläche Messing 18 %, Symbol Messing (`.mgi.i4.w`).
struct MoreManageIcon: View {
    let symbol: String
    var accent: Bool = false

    var body: some View {
        KIcon.view(symbol, 18)
            .foregroundStyle(accent ? KColor.teal : KColor.ink)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(accent ? KColor.brassSoft : KColor.sunken))
            .accessibilityHidden(true)
    }
}

extension MoreManageIcon {
    /// Frühere Form mit Farbe (iCloud-Abschnitt): heute neutral wie alle Symbole (v164)
    init(symbol: String, color: Color) { self.init(symbol: symbol, accent: false) }
}

/// Zeile im iOS-Listenstil (`.srowbtn.mgr`): Symbol, Titel 16 pt Medium, Wert 15 pt `--ink3` bzw. Plakette, Pfeil «›» 18 pt
struct MoreManageRow: View {
    let symbol: String
    var accent: Bool = false
    let title: String
    var value: String = ""
    var valueColor: Color = KColor.ink3
    var valueBold = false
    /// Plakette statt Wert (Vollständigkeit): Messing (offen) bzw. grün
    var badge: String? = nil
    var badgeWarn = false
    var first = false
    var accessibility: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                MoreManageIcon(symbol: symbol, accent: accent)
                Text(title)
                    .font(KFont.text(16, .medium))
                    .foregroundStyle(KColor.ink)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let b = badge, !b.isEmpty {
                    Text(b)
                        .font(KFont.text(15, .semibold))
                        .foregroundStyle(badgeWarn ? KColor.teal : KColor.ok)
                        .kLineHeight(15, 21.75)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill((badgeWarn ? KColor.teal : KColor.ok).opacity(0.14)))
                        .lineLimit(1)
                        .fixedSize()
                } else if !value.isEmpty {
                    Text(value)
                        .font(KFont.text(15, valueBold ? .semibold : .regular))
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                }
                Text("›")
                    .font(KFont.text(18))
                    .foregroundStyle(KColor.ink3)
                    .padding(.leading, -4)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 31)
            .padding(.top, first ? 2 : 12)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility ?? ([title, badge ?? value].filter { !$0.isEmpty }.joined(separator: ", ")))
        .accessibilityAddTraits(.isButton)
    }
}

/// Die vier Zeilen «Vertragspartner», «Personen», «Kategorien», «Vollständigkeit» (Mehr und Übersicht «Verwalten»)
struct MoreManageRows: View {
    @Environment(AppModel.self) private var model
    /// Zeile antippen: Ziel öffnen
    let onOpen: (ManageRoute) -> Void

    var body: some View {
        let sum = MoreManageSummary(model: model)
        let vk = sum.completeness
        VStack(spacing: 0) {
            MoreManageRow(symbol: "ic.partner", title: "Vertragspartner", value: sum.partners,
                          valueColor: sum.partnerWarn ? KColor.warn : KColor.ink3, valueBold: sum.partnerWarn, first: true) {
                onOpen(.partners)
            }
            .accessibilityIdentifier("more.partners")
            MoreLine()
            MoreManageRow(symbol: "ic.persons", title: "Personen", value: sum.persons) {
                onOpen(.persons)
            }
            .accessibilityIdentifier("more.persons")
            MoreLine()
            MoreManageRow(symbol: "ic.categories", title: "Kategorien", value: sum.categories) {
                onOpen(.categories)
            }
            .accessibilityIdentifier("more.categories")
            MoreLine()
            MoreManageRow(symbol: "ic.check", accent: vk.open > 0, title: Completeness.title,
                          badge: Completeness.badge(vk), badgeWarn: vk.open > 0, accessibility: Completeness.accessibilityLabel(vk)) {
                onOpen(.completeness(only: nil))
            }
            .accessibilityIdentifier("more.completeness")
        }
    }
}

struct MoreManageGroup: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        MoreGroup(title: "Verwalten") {
            MoreManageRows { route in model.present(.manage(route)) }
        }
    }
}

#if DEBUG
/// UI-Test «Vollständigkeit»: Startargument «-uiVkTerm» entfernt bei «Stadtwerke Konstanz» die Kündigungsfrist,
/// damit der Ablauf eine Fristen-Frage stellt (Beispieldaten haben sonst keine).
@MainActor
enum MoreUITestSeed {
    private static var done = false

    static func applyIfNeeded(_ model: AppModel) {
        guard !done, model.uiTestMode, ProcessInfo.processInfo.arguments.contains("-uiVkTerm") else { return }
        done = true
        guard let p = model.data.partners.first(where: { $0.name == "Stadtwerke Konstanz" }),
              let c = model.data.contracts.first(where: { $0.partnerID == p.id }) else { return }
        model.update { d in
            if let i = d.contractIndex(c.id) {
                d.contracts[i].notice = 0
                d.contracts[i].cancelTerm = .anytime
                d.contracts[i].end = nil
            }
        }
    }
}
#endif

// MARK: - Daten

struct MoreDataGroup: View {
    @Environment(AppModel.self) private var model
    let flow: MoreDataFlow

    var body: some View {
        MoreGroup(title: "Daten") {
            MoreICloudSection() // iCloud-Sync (Bereich sync: More/MoreICloudSection.swift)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    MoreTile(symbol: "ic.upload", title: "Backup erstellen") { flow.exportBackup(model: model) }
                    MoreTile(symbol: "ic.download", title: "Backup laden") { flow.startImport(.backup) }
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    MoreTile(symbol: "ic.table", title: "CSV importieren") { flow.startImport(.csv) }
                    MoreTile(symbol: "ic.table", title: "CSV exportieren") { flow.exportCSV(model: model) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(flow.working)
            if let p = flow.progress {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(p).font(.footnote).foregroundStyle(KColor.ink2).monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            }
            Text("**Backup:** alles inkl. Logos und Dokumente, auch für den Gerätewechsel.\n**CSV:** nur Tabellendaten, z.B. für Excel. Der Import erkennt gängige Spaltennamen.")
                .font(KFont.text(12.5))
                .foregroundStyle(KColor.ink2)
                .kLineHeight(12.5, 19.375)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
            Button {
                flow.askWipe(model: model)
            } label: {
                Text("Alle Daten löschen")
                    .font(KFont.text(13, .semibold))
                    .foregroundStyle(KColor.alert)
                    .kLineHeight(13, 18.85)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .contentShape(Rectangle())
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

/// Rechtstexte der nativen App (Web v195/v196, Stand 15.10.2026): nur Anbieter und Datenschutz, Lizenz über die Apple-Standard-EULA.
/// Anbieter-Angaben sind Platzhalter [ ] und vor dem App-Store-Start zu ersetzen (keine echte Adresse im Repo).
/// Logo-Suche wie in der nativen App: Website des Vertragspartners statt Bildaufbereitung über images.weserv.nl (v196).
enum MoreTexts {
    static let provider = [
        "[Vorname Nachname]\n[Strasse Nr.]\n[PLZ Ort]\nSchweiz\nE-Mail: [kontakt@beispiel.ch]",
    ]

    static let privacy = [
        "**Verantwortlich** ist der oben genannte Anbieter. Kontakt: [kontakt@beispiel.ch]",
        "**Deine Daten bleiben bei dir.** Kontivo hat kein Konto, keine Werbung und kein Tracking. Deine Eingaben liegen auf deinem Gerät und, wenn du den iCloud-Sync einschaltest, in deinem iCloud-Konto bei Apple. Wir erhalten diese Daten nicht und haben keinen Zugriff darauf.",
        "**Externe Dienste.** Nur wenn du eine dieser Funktionen nutzt, ruft die App einen Dienst auf. Dieser erhält deine IP-Adresse und den Suchbegriff, aber keine Vertragsdaten:\n• Wechselkurse: Frankfurter, ersatzweise ExchangeRate-API\n• Logo-Suche: Apple, Google, Wikimedia, unavatar.io und die Website des Vertragspartners (Firmenname bzw. Website)\n• Adresssuche: Wikidata, OpenStreetMap (Firmenname)",
        "**Ausland.** Diese Dienste verarbeiten Daten auch ausserhalb der Schweiz und der EU, namentlich in den USA und im Vereinigten Königreich, teils in weiteren Ländern mit möglicherweise tieferem Datenschutz. Die Übermittlung erfolgt, weil du die Funktion nutzt. Ohne diese Funktionen funktioniert die App ebenfalls.",
        "**Absturzberichte.** Hast du in iOS «Mit App-Entwicklern teilen» eingeschaltet, erhalten wir von Apple anonyme Absturzberichte.",
        "**Rechtsgrundlage** (DSGVO) ist die Bereitstellung der von dir genutzten Funktion (Art. 6 Abs. 1 lit. b). E-Mails an uns löschen wir nach Erledigung.",
        "**Deine Rechte.** Du kannst Auskunft, Berichtigung, Löschung und Herausgabe deiner Daten verlangen sowie widersprechen. Da wir keine Daten speichern, löschst oder exportierst du sie direkt in der App, iCloud-Daten auch unter «Mehr» beim iCloud-Sync. Beschwerden kannst du beim EDÖB (Schweiz) oder bei der Datenschutzbehörde deines Wohnsitzes (EU) einreichen.",
        "Stand: 15. Oktober 2026",
    ]
}

struct MoreLegalGroup: View {
    var body: some View {
        MoreGroup(title: "Rechtliches") {
            MoreLegalItem(title: "Anbieter", paragraphs: MoreTexts.provider, first: true)
            MoreLine()
            MoreLegalItem(title: "Datenschutz", paragraphs: MoreTexts.privacy)
        }
    }
}

/// Aufklappbarer Rechtstext (wie `<details class="legal">`): «▶»/«▼» und Titel 15 pt, Absätze 12.5 pt `--ink2`, Abstand 8
struct MoreLegalItem: View {
    let title: String
    let paragraphs: [String]
    var first: Bool = false
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { open.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "triangle.fill")
                        .font(.system(size: 9))
                        .rotationEffect(.degrees(open ? 180 : 90))
                        .foregroundStyle(KColor.ink)
                        .frame(width: 11)
                    Text(title)
                        .font(KFont.text(15))
                        .foregroundStyle(KColor.ink)
                        .kLineHeight(15, 21.75)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(open ? "aufgeklappt" : "zugeklappt")
            if open {
                ForEach(paragraphs, id: \.self) { p in
                    Text(LocalizedStringKey(p))
                        .font(KFont.text(12.5))
                        .foregroundStyle(KColor.ink2)
                        .kLineHeight(12.5, 19.375)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
            }
        }
        .padding(.top, first ? 2 : 10)
        .padding(.bottom, 10)
    }
}

// MARK: - Fuss

/// Fusszeile (Web `.brandfoot`, `.bfeat`, `.bver`, `.foot`): App-Symbol 40 pt, Wortmarke 17 pt (v170/v171), Slogan 14 pt,
/// drei Merkmale mit Messing-Haken, Version, «Made with ❤️ in 🇨🇭».
struct MoreBrandFooter: View {
    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                KAppLogo(size: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    // Zeile 17 pt × 1.45: Wortmarke mit Grundlinie wie Text
                    KWordmark(size: 17)
                        .padding(.top, 5.6)
                        .frame(height: 24.65, alignment: .top)
                    Text("Deine Verträge, ganz entspannt")
                        .font(KFont.text(14))
                        .foregroundStyle(KColor.ink2)
                        .kLineHeight(14, 18.9)
                }
            }
            .accessibilityElement(children: .combine)
            .padding(.top, 28)

            MoreFeatureFlow(texts: ["Ohne Bankanbindung", "Keine Werbung", "Daten bleiben privat"])
                .padding(.top, 14)

            Text("Version " + version)
                .font(KFont.text(11))
                .foregroundStyle(KColor.ink3)
                .kLineHeight(11, 15.95)
                .padding(.top, 10)

            HStack(spacing: 0) {
                Text("Made with ❤️ in ")
                MoreSwissMark()
                    .frame(width: 13, height: 13)
                    .padding(.leading, 2)
            }
            .font(KFont.text(12.5))
            .foregroundStyle(KColor.ink3)
            .kLineHeight(12.5, 18.125)
            .padding(.top, 34)
            .padding(.bottom, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Made with ❤️ in der Schweiz")
        }
        .frame(maxWidth: .infinity)
    }
}

/// Merkmale zentriert mit Umbruch (Web `.bfeat`: Abstand 6 vertikal, 14 horizontal)
struct MoreFeatureFlow: View {
    let texts: [String]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { ForEach(texts, id: \.self) { MoreFeature(text: $0) } }
            VStack(spacing: 6) {
                HStack(spacing: 14) { ForEach(texts.prefix(2), id: \.self) { MoreFeature(text: $0) } }
                HStack(spacing: 14) { ForEach(texts.dropFirst(2), id: \.self) { MoreFeature(text: $0) } }
            }
            VStack(spacing: 6) { ForEach(texts, id: \.self) { MoreFeature(text: $0) } }
        }
    }
}

struct MoreFeature: View {
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            KIcon.view("ic.check.small", 14)
                .foregroundStyle(KColor.teal)
                .accessibilityHidden(true)
            Text(text)
                .font(KFont.text(12.5))
                .foregroundStyle(KColor.ink2)
                .lineLimit(1)
        }
        .kLineHeight(12.5, 18.125)
    }
}
