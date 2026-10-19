import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import KontivoCore

// MARK: - Darstellung

extension View {
    /// Liste im Stil der Web-App: Papier-Hintergrund, weisse Gruppen, auf dem iPad max. 600 pt breit
    func mdListStyle() -> some View {
        self.listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: KMetric.maxContent)
            .frame(maxWidth: .infinity)
            .background(KColor.paper.ignoresSafeArea())
    }

    /// Inhalt einer Seite als freie Karten-Seite (Web `#mdBody`: Rand 17, 4 pt unter der Kopfzeile, unten 52), auf dem iPad mittig
    func mdScrollPage() -> some View {
        self.padding(.horizontal, KMetric.gutter)
            .padding(.top, 4)
            .padding(.bottom, 52)
            .frame(maxWidth: KMetric.maxContent)
            .frame(maxWidth: .infinity)
    }

    /// ScrollView einer Karten-Seite: Papier-Hintergrund, Tastatur beim Ziehen ausblenden
    func mdScrollStyle() -> some View {
        self.scrollDismissesKeyboard(.interactively)
            .background(KColor.paper.ignoresSafeArea())
    }

    /// Zeilenhintergrund (Web `.mdgrp`: Fläche `--field`, Zeilen 10 pt hoch gepolstert, Innenabstand 12, Trennlinie `--line`)
    func mdRow() -> some View {
        self.alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .listRowBackground(KColor.field)
            .listRowSeparatorTint(KColor.line)
            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
    }

    /// Zeile ohne Karte (Hinweise, Kopfzeilen)
    func mdPlainRow() -> some View {
        self.listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            .listRowSeparator(.hidden)
    }
}

/// Titel fett, darunter klein (Web `.mdrow .t`: <b> 15 pt Semibold, <small> 12 pt `--ink2`)
struct MDTitleSub: View {
    let title: String
    var subtitle: String = ""
    var subtitleColor: Color = KColor.ink2

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(KFont.text(15, .semibold))
                .foregroundStyle(KColor.ink)
                .lineLimit(2)
                .kLineHeight(15, 21.75)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(KFont.text(12))
                    .foregroundStyle(subtitleColor)
                    .monospacedDigit()
                    .lineLimit(3)
                    .kLineHeight(12, 23.2)
            }
        }
    }
}

/// Grauer Hinweis (mdhint/mdnote)
struct MDHint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(KFont.text(12.5))
            .foregroundStyle(KColor.ink3)
            .kLineHeight(12.5, 18.125)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Abschnittskopf mit Element rechts (mdSec)
struct MDSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(KFont.text(12.5, .semibold))
                .foregroundStyle(KColor.ink3)
            Spacer(minLength: 8)
            trailing
                .font(KFont.text(13.5, .semibold))
                .foregroundStyle(KColor.teal)
        }
        .textCase(nil)
    }
}

extension MDSectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.title = title
        self.trailing = EmptyView()
    }
}

/// Pfeil rechts in Zeilen, die etwas öffnen
struct MDChevron: View {
    var body: some View {
        Text("›")
            .font(KFont.text(18))
            .foregroundStyle(KColor.ink3)
            .accessibilityHidden(true)
    }
}

/// Auswahlpunkt (Radio) rechts
struct MDRadio: View {
    let on: Bool
    var body: some View {
        // Web `.mdpick .rad`: Kreis 20 pt, Rand 1.6 `--ink3`; gewählt Rand 6 pt Messing
        Circle()
            .strokeBorder(on ? KColor.teal : KColor.ink3, lineWidth: on ? 6 : 1.6)
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
    }
}

/// Eingabefeld-Hintergrund für Felder ausserhalb von Formularzeilen
struct MDFieldBox: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(KColor.field))
    }
}

extension View {
    func mdFieldBox() -> some View { modifier(MDFieldBox()) }
}

/// Segment wie .hseg der Web-App; erlaubt auch «nichts gewählt».
struct MDSegment<T: Hashable>: View {
    let options: [(title: String, value: T)]
    let selected: Set<T>
    let action: (T) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                segButton(o.title, o.value)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: KMetric.controlRadius, style: .continuous).fill(KColor.sunken))
    }

    private func segButton(_ title: String, _ value: T) -> some View {
        let on = selected.contains(value)
        return Button { action(value) } label: {
            // Web `.hseg button`: 13.5 pt, gewählt weiss mit leichtem Schatten
            Text(title)
                .font(KFont.text(13.5, on ? .semibold : .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .padding(.horizontal, 4)
                .foregroundStyle(on ? KColor.ink : KColor.ink2)
                .background {
                    if on {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(KColor.surface)
                            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Chips in einer waagrecht scrollbaren Zeile
struct MDChipRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content }
                .padding(.vertical, 2)
        }
    }
}

// MARK: - Zeilen

/// Vertragszeile (mdCRow): Logo, Titel, «Preis Währung · Turnus[ · beendet]». Antippen öffnet das Detail.
struct MDContractRow: View {
    let contract: Contract
    @Environment(AppModel.self) private var model

    var body: some View {
        let d = model.data
        let calc = model.calc
        let ended: String = calc.isActive(contract) ? "" : " · beendet"
        let sub: String = [Format.money(calc.curPrice(contract), contract.currency), " ", contract.currency.rawValue, " · ",
                           Format.cycleTextOrMonthly(contract.cycle), ended].joined()
        return Button {
            model.present(.contractDetail(contract.id))
        } label: {
            HStack(spacing: 12) {
                MarkView(contract: contract, data: d, size: 40)
                MDTitleSub(title: d.title(of: contract), subtitle: sub)
                Spacer(minLength: 4)
                MDChevron()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .mdRow()
    }
}

/// Kachel eines Vertragspartners: Logo bzw. Marke des ersten Vertrags
struct MDPartnerMark: View {
    let partnerID: UUID
    var size: CGFloat = 40
    @Environment(AppModel.self) private var model

    var body: some View {
        let d = model.data
        if let c = d.contracts.first(where: { $0.partnerID == partnerID }) {
            MarkView(contract: c, data: d, size: size)
        } else {
            let p = d.partner(partnerID)
            MarkView(logoID: p?.logoID, logoBg: p?.logoBg, colorHex: AppData.hashColor(p?.name ?? ""),
                     symbol: KIcon.symbol(forKey: "tag"), size: size)
        }
    }
}

// MARK: - Bild wählen und zuschneiden

/// Bild zum Zuschneiden
struct MDCropItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Fotos, Dateien und Zuschneiden (Web: Dateiauswahl → openCrop → cropOk)
struct MDImageFlow: ViewModifier {
    @Binding var showPhotos: Bool
    @Binding var showFiles: Bool
    @Binding var crop: MDCropItem?
    let title: String
    let onDone: (Data, String) -> Void
    @Environment(AppModel.self) private var model
    @State private var item: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $showPhotos, selection: $item, matching: .images)
            .onChange(of: item) { _, it in
                guard let it else { return }
                Task { @MainActor in
                    let data = try? await it.loadTransferable(type: Data.self)
                    item = nil
                    await open(data)
                }
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image]) { result in
                guard case .success(let url) = result else { return }
                Task { @MainActor in
                    let data = await ImageImport.read(url)
                    // Dateiauswahl erst ausblenden lassen, sonst erscheint das Zuschneiden je nach iOS nicht (wie MoreDataFlow)
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    await open(data)
                }
            }
            .sheet(item: $crop) { c in
                ImageCropSheet(image: c.image, title: title, onDone: onDone)
                    .environment(model)
            }
    }

    /// Bild verkleinert im Hintergrund lesen (ImageIO), dann zuschneiden
    @MainActor private func open(_ data: Data?) async {
        if let img = await ImageImport.downsampleDetached(data) {
            crop = MDCropItem(image: img)
        } else {
            model.toast("Bild konnte nicht gelesen werden")
        }
    }
}

/// Menü «Fotos» / «Dateien» für die Bildauswahl
struct MDImageSourceMenu<Label: View>: View {
    @Binding var showPhotos: Bool
    @Binding var showFiles: Bool
    @ViewBuilder var label: Label

    var body: some View {
        Menu {
            Button { showPhotos = true } label: { SwiftUI.Label("Fotos", systemImage: "photo.on.rectangle") }
            Button { showFiles = true } label: { SwiftUI.Label("Dateien", systemImage: "folder") }
        } label: {
            label
        }
    }
}

// MARK: - Logo-Suche für Vertragspartner

struct MDLogoTarget: Identifiable {
    let id: UUID
    let name: String
    let currency: Currency
    let web: String
}

/// Öffnet die Logo-Suche für einen Vertragspartner; Auswahl gilt für alle seine Verträge.
struct MDLogoSheet: ViewModifier {
    @Binding var target: MDLogoTarget?
    var onSaved: ((UUID) -> Void)? = nil
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.sheet(item: $target) { t in
            LogoSearchSheet(name: t.name, currency: t.currency, web: t.web) { png, bg in
                if model.mdSetPartnerLogo(t.id, png: png, bg: bg) {
                    model.toast("Logo gespeichert")
                    onSaved?(t.id)
                }
            }
            .environment(model)
        }
    }
}

// MARK: - Adresssuche

enum MDAddrTarget: Hashable {
    case partner(UUID)
    /// Vertrag ohne Vertragspartner (Kündigung per Brief): beim Übernehmen wird ein Vertragspartner angelegt
    case contract(UUID)
}

struct MDAddrPick: Identifiable {
    let id = UUID()
    let target: MDAddrTarget
    let candidates: [AddressCandidate]
}

/// Auswahl «Adresse wählen» (AddressPickSheet aus Shared/)
struct MDAddrPickSheet: ViewModifier {
    @Binding var pick: MDAddrPick?
    var onApplied: ((PostalAddress) -> Void)? = nil
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.sheet(item: $pick) { p in
            AddressPickSheet(candidates: p.candidates) { cand in
                pick = nil
                if let a = model.mdApplyAddress(p.target, lines: cand.lines) {
                    model.toast("Adresse übernommen, bitte prüfen")
                    onApplied?(a)
                }
            }
            .environment(model)
        }
    }
}

// MARK: - Aktionen am AppModel

extension AppModel {
    /// Datenqualität mit Prüfung der Logo-Dateien
    var mdQualityReport: QualityReport {
        let f = files
        return Quality.report(data, today: today, hasFile: { f.has($0) })
    }

    /// Währung des ersten Vertrags eines Vertragspartners (Logo- und Adresssuche), sonst CHF
    func mdCurrency(partner id: UUID) -> Currency {
        data.contracts.first { $0.partnerID == id }?.currency ?? .CHF
    }

    func mdLogoTarget(partner id: UUID, name: String? = nil) -> MDLogoTarget? {
        guard let p = data.partner(id) else { return nil }
        let n = (name ?? p.name).trimmingCharacters(in: .whitespacesAndNewlines)
        return MDLogoTarget(id: id, name: n, currency: mdCurrency(partner: id), web: p.web)
    }

    /// Logo speichern und beim Vertragspartner setzen (gilt für alle seine Verträge)
    @discardableResult
    func mdSetPartnerLogo(_ id: UUID, png: Data, bg: String) -> Bool {
        guard data.partner(id) != nil, let fid = storeFile(png, type: "image/png") else { return false }
        return update { $0.setPartnerLogo(id, logoID: fid, background: bg) }
    }

    /// Adresse suchen (Wikidata/OpenStreetMap über AddressSearch); ohne Treffer Toast `notFound`
    func mdFindAddress(_ target: MDAddrTarget, notFound: String) async -> MDAddrPick? {
        var name = ""
        var web = ""
        var cur: Currency = .CHF
        switch target {
        case .partner(let pid):
            guard let p = data.partner(pid) else { return nil }
            name = p.name
            web = p.web
            cur = mdCurrency(partner: pid)
        case .contract(let cid):
            guard let c = data.contract(cid) else { return nil }
            name = data.title(of: c)
            cur = c.currency
        }
        toast("Suche Adresse …")
        let cs = await AddressSearch.find(name: name, domain: Format.domain(of: web), currency: cur)
        if cs.isEmpty {
            toast(notFound)
            return nil
        }
        return MDAddrPick(target: target, candidates: cs)
    }

    /// Gefundene Adresse übernehmen (addrSplit → Felder)
    func mdApplyAddress(_ target: MDAddrTarget, lines: [String]) -> PostalAddress? {
        let text = lines.joined(separator: "\n")
        switch target {
        case .partner(let pid):
            guard let p = data.partner(pid) else { return nil }
            let a = WebImport.addrSplit(text, partnerName: p.name)
            return update { $0.setPartnerAddress(pid, a) } ? a : nil
        case .contract(let cid):
            guard let c = data.contract(cid) else { return nil }
            let a = WebImport.addrSplit(text)
            let firm = a.company.isEmpty ? data.title(of: c) : a.company
            var ok = false
            update { d in ok = d.mdSetContractAddress(cid, company: firm, address: a) != nil }
            return ok ? a : nil
        }
    }

    /// Eingefügtes Bild (PasteButton, pasteLogo): Bild direkt, sonst ein Bild-Link (http/https).
    /// Der Systemknopf «Einfügen» löst keine Rückfrage «Kontivo möchte einfügen» aus.
    func mdPastedImage(_ providers: [NSItemProvider]) async -> UIImage? {
        switch await ImageImport.pasted(providers) {
        case .image(let img):
            return img
        case .link(let txt):
            toast("Lade Bild…")
            if let img = await ImageImport.load(link: txt) { return img }
            toast("Bild-Link konnte nicht geladen werden")
            return nil
        case .none:
            toast("Kein Bild in der Zwischenablage. In Google Bild lange drücken → «Kopieren».")
            return nil
        }
    }

    /// Filter, die Namen von Vertragspartnern/Kategorien bzw. Personen enthalten, nachziehen
    func mdRenameFilters(partnerFrom: String? = nil, partnerTo: String? = nil, categoryFrom: String? = nil, categoryTo: String? = nil) {
        if let f = partnerFrom, costFilter.partner == f { costFilter.partner = partnerTo }
        if let f = categoryFrom, costFilter.category == f { costFilter.category = categoryTo }
    }

    func mdMovePersonFilters(from: UUID, to: UUID?) {
        if costFilter.person == from { costFilter.person = to }
    }
}


// Fachaktionen der Inline-Editoren (mdSet…, MDTermChoice, mdNoticeValue …) liegen im Kern: KontivoCore/ExtManage.swift.
// Zahlen mit Format.parseNum (1:1 wie Web parseNum), Beträge mit Format.parseAmount (Web parseAmt).

/// Name auf höchstens 30 Zeichen begrenzen (maxlength="30")
func mdLimit30(_ s: String) -> String {
    s.count > 30 ? String(s.prefix(30)) : s
}

// MARK: - Knöpfe

/// Hauptknopf über die ganze Breite (lbtn main, rot bei dangerbtn), als eigene Zeile ohne Karte
struct MDMainButton: View {
    let title: String
    var destructive = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(role: destructive ? .destructive : nil, action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(destructive ? KColor.alert : KColor.tealFill)
        .disabled(disabled)
        .mdPlainRow()
    }
}

/// Aktionszeile in einer Karte (mdact), optional rot
struct MDActionRow: View {
    let title: String
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(role: destructive ? .destructive : nil, action: action) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(destructive ? KColor.alert : KColor.teal)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .mdRow()
    }
}

// MARK: - Karten-Seiten (Web `.mdgrp`, `.mdsec`, `.mdrow`, `.mdhint`)

/// Gruppe (Web `.mdgrp`): Fläche `--field`, Radius 12, Innenabstand links/rechts 12. Abstände setzt die Seite.
struct MDGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KColor.field))
    }
}

/// Abschnittskopf (Web `.mdsec`): 12.5 pt Semibold `--ink3`, Rand links/rechts 4, unten 6 (oben 16 setzt die Seite)
struct MDSec<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(KFont.text(12.5, .semibold))
                .foregroundStyle(KColor.ink3)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing
        }
        .kLineHeight(12.5, 18.125)
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }
}

extension MDSec where Trailing == EmptyView {
    init(_ title: String) { self.init(title: title) { EmptyView() } }
}

/// Zeile einer Gruppe (Web `.mdrow`): 10 pt oben/unten, Abstand 12, Trennlinie oben ausser bei der ersten Zeile
struct MDRowBox<Content: View>: View {
    var first = false
    var chevron = true
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            if !first { KDivider() }
            HStack(spacing: 12) {
                content
                Spacer(minLength: 4)
                if chevron { MDChevron() }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
    }
}

/// Zeile «+ … hinzufügen» (Web `.mdadd`): Kreis 38 pt Messing 14 %, «+» 22 pt Medium, Titel 15 pt Semibold Messing
struct MDAddRowLabel: View {
    let title: String
    var body: some View {
        HStack(spacing: 12) {
            Text("+")
                .font(KFont.text(22, .medium))
                .foregroundStyle(KColor.teal)
                .frame(width: 38, height: 38)
                .background(Circle().fill(KColor.tealTint))
                .accessibilityHidden(true)
            Text(title)
                .font(KFont.text(15, .semibold))
                .foregroundStyle(KColor.teal)
                .kLineHeight(15, 21.75)
        }
    }
}

/// Hinweis unter einer Gruppe (Web `.mdhint` margin −6 4 12 nach einer Gruppe mit 14 Abstand)
struct MDGroupHint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        MDHint(text)
            .padding(.top, 8)
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension KColor {
    /// Web `.mdav.multi`: `color-mix(--teal 14%, --surface)`
    static let mdMultiFill = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(rgb: KColor.mix(0xC6AB78, 0x36373B, 0.14)) : UIColor(rgb: KColor.mix(0x86671F, 0xFFFFFF, 0.14))
    })
}

/// Heller Knopf (Web `.lbtns2 .lbtn`): weiss, Ring 1 pt `--line`, Radius 10, 13 pt Semibold `--ink`, Innenabstand 8/4
struct MDLightButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(KFont.text(13, .semibold))
                .foregroundStyle(KColor.ink)
                .lineLimit(1)
                .kLineHeight(13, 18.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8).padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.surface))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(KColor.line, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
