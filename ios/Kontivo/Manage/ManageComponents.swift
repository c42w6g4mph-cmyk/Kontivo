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

    /// Zeilenhintergrund (Karte)
    func mdRow() -> some View {
        listRowBackground(KColor.surface)
    }

    /// Zeile ohne Karte (Hinweise, Kopfzeilen)
    func mdPlainRow() -> some View {
        self.listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            .listRowSeparator(.hidden)
    }
}

/// Titel fett, darunter klein (Zeilen der Web-App: <b> + <small>)
struct MDTitleSub: View {
    let title: String
    var subtitle: String = ""
    var subtitleColor: Color = KColor.ink2

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(KColor.ink)
                .lineLimit(2)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(subtitleColor)
                    .monospacedDigit()
                    .lineLimit(3)
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
            .font(.footnote)
            .foregroundStyle(KColor.ink2)
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
            Spacer(minLength: 8)
            trailing
                .font(.subheadline.weight(.semibold))
                .textCase(nil)
        }
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
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(KColor.ink3.opacity(0.7))
            .accessibilityHidden(true)
    }
}

/// Auswahlpunkt (Radio) rechts
struct MDRadio: View {
    let on: Bool
    var body: some View {
        Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(on ? KColor.teal : KColor.ink3.opacity(0.6))
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
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                segButton(o.title, o.value)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.field))
    }

    private func segButton(_ title: String, _ value: T) -> some View {
        let on = selected.contains(value)
        return Button { action(value) } label: {
            Text(title)
                .font(.subheadline.weight(on ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .padding(.horizontal, 4)
                .foregroundStyle(on ? Color.white : KColor.ink)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? KColor.teal : Color.clear))
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
        let sub: String = [Format.money(calc.curPrice(contract)), " ", contract.currency.rawValue, " · ",
                           Format.cycleTextOrMonthly(contract.cycle), ended].joined()
        return Button {
            model.present(.contractDetail(contract.id))
        } label: {
            HStack(spacing: 12) {
                MarkView(contract: contract, data: d, size: 36)
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
                    if let d = data, let img = UIImage(data: d) {
                        crop = MDCropItem(image: img)
                    } else {
                        model.toast("Bild konnte nicht gelesen werden")
                    }
                }
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image]) { result in
                guard case .success(let url) = result else { return }
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                if let d = try? Data(contentsOf: url), let img = UIImage(data: d) {
                    crop = MDCropItem(image: img)
                } else {
                    model.toast("Bild konnte nicht gelesen werden")
                }
            }
            .sheet(item: $crop) { c in
                ImageCropSheet(image: c.image, title: title, onDone: onDone)
                    .environment(model)
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

    /// Bild aus der Zwischenablage (pasteLogo): Bild direkt, sonst ein Bild-Link (http/https)
    func mdPasteboardImage() async -> UIImage? {
        let pb = UIPasteboard.general
        if pb.hasImages, let img = pb.image { return img }
        var txt = ""
        if pb.hasURLs, let u = pb.url { txt = u.absoluteString }
        if txt.isEmpty, pb.hasStrings { txt = (pb.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        if txt.range(of: "^https?://\\S+$", options: .regularExpression) != nil {
            toast("Lade Bild…")
            if let img = await LogoFinder.loadImage(txt, timeout: 15) { return img }
            toast("Bild-Link konnte nicht geladen werden")
            return nil
        }
        toast("Kein Bild in der Zwischenablage. In Google Bild lange drücken → «Kopieren».")
        return nil
    }

    /// Filter, die Namen von Vertragspartnern/Kategorien bzw. Personen enthalten, nachziehen
    func mdRenameFilters(partnerFrom: String? = nil, partnerTo: String? = nil, categoryFrom: String? = nil, categoryTo: String? = nil) {
        if let f = partnerFrom, costFilter.partner == f { costFilter.partner = partnerTo }
        if let f = categoryFrom, costFilter.category == f { costFilter.category = categoryTo }
    }

    func mdMovePersonFilters(from: UUID, to: UUID?) {
        if costFilter.person == from { costFilter.person = to }
        if budgetPerson == from { budgetPerson = to }
    }
}


// Fachaktionen der Inline-Editoren (mdSet…, MDTermChoice, mdNoticeValue …) liegen im Kern: KontivoCore/ExtManage.swift.
// Zahlen immer mit Format.parseNum (1:1 wie Web parseNum).

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
        .tint(destructive ? KColor.alert : KColor.teal)
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
