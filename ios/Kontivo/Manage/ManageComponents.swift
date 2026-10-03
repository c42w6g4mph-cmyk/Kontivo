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

/// Google-Bildersuche «<Name> logo» (logoSearch)
func mdGoogleImageURL(_ name: String) -> URL? {
    URL(string: "https://www.google.com/search?tbm=isch&q=" + LogoFinder.enc(name + " logo"))
}

// MARK: - Fachaktionen der Inline-Editoren (Datenqualität)

/// Auswahl «Kündbar auf …» im Editor Frist/Laufzeit
enum MDTermChoice: Hashable {
    case unset
    case anytime
    case term(CancelTerm)
    case fixed

    static let options: [(title: String, value: MDTermChoice)] = [
        ("Kündbar auf … wählen", .unset),
        ("jederzeit", .anytime),
        ("auf Monatsende", .term(.monthEnd)),
        ("auf Quartalsende", .term(.quarterEnd)),
        ("auf Halbjahresende", .term(.halfYearEnd)),
        ("auf Jahresende", .term(.yearEnd)),
        ("auf Ende Vertragsjahr", .term(.contractYear)),
        ("auf Ende Zahlungsperiode", .term(.period)),
        ("Feste Laufzeit bis …", .fixed),
    ]
}

extension AppData {
    mutating func mdSetHolders(contract id: UUID, _ ids: [UUID]) {
        guard let i = contractIndex(id) else { return }
        contracts[i].holderIDs = persons.map { $0.id }.filter { ids.contains($0) }
    }

    mutating func mdSetContractAmount(_ id: UUID, _ v: Double) {
        guard let i = contractIndex(id) else { return }
        contracts[i].amount = Format.round2(v)
    }

    mutating func mdSetContractCategory(_ id: UUID, _ cat: UUID) {
        guard let i = contractIndex(id), category(cat) != nil else { return }
        contracts[i].categoryID = cat
    }

    mutating func mdSetContractCycle(_ id: UUID, _ months: Int) {
        guard let i = contractIndex(id) else { return }
        contracts[i].cycle = months
    }

    mutating func mdSetContractDue(_ id: UUID, _ d: Day) {
        guard let i = contractIndex(id) else { return }
        contracts[i].due = d
    }

    mutating func mdSetCustomerNo(_ id: UUID, _ s: String) {
        guard let i = contractIndex(id) else { return }
        contracts[i].customerNo = s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func mdSetCancelURL(_ id: UUID, _ s: String) {
        guard let i = contractIndex(id) else { return }
        contracts[i].cancelURL = s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func mdSetContractMail(_ id: UUID, _ s: String) {
        guard let i = contractIndex(id) else { return }
        contracts[i].mail = s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Frist und Laufzeit (qMultiSave «notice»). Bei einem Termin werden Vertragsende und Verlängerung geleert (Fund N1).
    mutating func mdSetNotice(_ id: UUID, notice: Int, unit: NoticeUnit, choice: MDTermChoice, end: Day?, renew: Int) {
        guard let i = contractIndex(id) else { return }
        contracts[i].notice = Swift.max(0, notice)
        contracts[i].noticeUnit = unit
        switch choice {
        case .fixed:
            contracts[i].end = end
            contracts[i].renewMonths = end == nil ? 0 : renew
            contracts[i].cancelTerm = .anytime
        case .anytime:
            contracts[i].cancelTerm = .anytime
            contracts[i].end = nil
            contracts[i].renewMonths = 0
        case .term(let t):
            contracts[i].cancelTerm = t
            contracts[i].end = nil
            contracts[i].renewMonths = 0
        case .unset:
            break
        }
    }

    mutating func mdSetIncomeAmount(_ id: UUID, _ v: Double) {
        guard let i = incomeIndex(id) else { return }
        incomes[i].amount = Format.round2(v)
    }

    /// Adresse für einen Vertrag: mit Vertragspartner dort, ohne Vertragspartner wird einer mit dem Firmennamen
    /// angelegt bzw. gefunden und zugeordnet (der Brief nimmt die Adresse immer vom Vertragspartner).
    @discardableResult
    mutating func mdSetContractAddress(_ id: UUID, company: String, address: PostalAddress) -> UUID? {
        guard let i = contractIndex(id) else { return nil }
        if let pid = contracts[i].partnerID, partner(pid) != nil {
            setPartnerAddress(pid, address)
            return pid
        }
        let c = Format.collapseSpaces(company)
        let name = c.isEmpty ? title(of: contracts[i]) : c
        guard let pid = partnerID(forName: name) else { return nil }
        contracts[i].partnerID = pid
        var a = address
        if a.company.trimmingCharacters(in: .whitespaces).isEmpty { a.company = name }
        setPartnerAddress(pid, a)
        return pid
    }

    /// Verträge einer Kategorie (alle Status); ohne bzw. mit unbekannter Kategorie zählt als «Sonstiges» (catCount)
    func mdContracts(inCategory id: UUID) -> [Contract] {
        let isOther = otherCategory?.id == id
        return contracts.filter { c in
            if c.categoryID == id { return true }
            if isOther { return c.categoryID == nil || category(c.categoryID) == nil }
            return false
        }
    }

    /// Monatskosten (Hauptwährung) laufender, nicht pausierter Verträge (perMonth)
    func mdPerMonth(_ list: [Contract], today: Day) -> Double {
        let calc = Calc(data: self, today: today)
        return list.reduce(0.0) { s, c in s + ((calc.isActive(c) && !calc.isPaused(c)) ? calc.monthlyCost(c) : 0) }
    }
}

/// Zahl lesen wie parseNum der Web-App: «'» und «’» entfernen, erstes Komma → Punkt, führende Zahl
func mdParseNum(_ s: String) -> Double? {
    var t = s.replacingOccurrences(of: "'", with: "")
        .replacingOccurrences(of: "\u{2019}", with: "")
        .replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "\u{2212}", with: "-")
    if let r = t.range(of: ",") { t.replaceSubrange(r, with: ".") }
    var out = ""
    var seenDot = false
    for (i, ch) in t.enumerated() {
        if ch.isASCII && ch.isNumber {
            out.append(ch)
        } else if ch == "." && !seenDot {
            seenDot = true
            out.append(ch)
        } else if (ch == "-" || ch == "+") && i == 0 {
            out.append(ch)
        } else {
            break
        }
    }
    guard let v = Double(out), v.isFinite else { return nil }
    return v
}

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
