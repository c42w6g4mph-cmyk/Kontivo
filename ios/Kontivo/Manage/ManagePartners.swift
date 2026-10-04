import SwiftUI
import KontivoCore

// MARK: - Liste

/// Rückfrage «Zu «Ziel» zusammenführen?» für einen Dubletten-Hinweis
private struct MDDupMergeAsk: Identifiable {
    let id = UUID()
    let targetID: UUID
    let targetName: String
    let sources: [UUID]
    let sourceNames: [String]
    let count: Int
}

/// Vertragspartner: Suche, Dubletten-Hinweise, Liste (MD_PAGES.partner)
struct MDPartnersPage: View {
    @Environment(AppModel.self) private var model
    @Environment(ManageNav.self) private var nav
    @State private var mergeAsk: MDDupMergeAsk?

    var body: some View {
        @Bindable var nav = nav
        let q = nav.partnerQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = Partners.groups(model.data, today: model.today)
        let list = q.isEmpty ? all : all.filter { $0.partner.name.lowercased().contains(q) }
        List {
            if q.isEmpty {
                ForEach(Array(Partners.duplicateSets(model.data, today: model.today).enumerated()), id: \.offset) { _, set in
                    dupCard(set)
                }
            }
            if list.isEmpty {
                Section {
                    MDHint(q.isEmpty ? "Noch keine Verträge mit Vertragspartner." : "Kein Vertragspartner gefunden.")
                        .mdPlainRow()
                }
            } else {
                Section {
                    ForEach(list, id: \.partner.id) { g in
                        row(g)
                    }
                }
            }
        }
        .mdListStyle()
        .searchable(text: $nav.partnerQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Vertragspartner suchen")
        .navigationTitle("Vertragspartner")
        .modifier(MDDupMergeAlert(ask: $mergeAsk, onMerge: merge))
    }

    private func row(_ g: Partners.Group) -> some View {
        let home = model.data.settings.homeCurrency.rawValue
        let cost: String = g.monthlyCost != 0 ? [" · ", Format.money(g.monthlyCost), " ", home, "/Mt."].joined() : ""
        let sub: String = Format.count(g.contractIDs.count, "Vertrag", "Verträge") + cost
        return NavigationLink(value: ManagePage.partner(g.partner.id)) {
            HStack(spacing: 12) {
                MDPartnerMark(partnerID: g.partner.id, size: 36)
                MDTitleSub(title: g.partner.name, subtitle: sub)
            }
        }
        .mdRow()
    }

    private func dupCard(_ set: [Partners.Group]) -> some View {
        let target = Partners.mergeTarget(set)
        let names = set.map { "«" + $0.partner.name + "»" }.joined(separator: " und ")
        return Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Gleicher Vertragspartner?").font(.subheadline.weight(.semibold)).foregroundStyle(KColor.ink)
                Text(names + " sehen gleich aus.").font(.subheadline).foregroundStyle(KColor.ink2)
                if let t = target {
                    Button("Zu «\(t.partner.name)» zusammenführen") { askMerge(set, target: t) }
                        .buttonStyle(.borderless)
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)
            .listRowBackground(KColor.warn.opacity(0.10))
        }
    }

    private func askMerge(_ set: [Partners.Group], target t: Partners.Group) {
        let src = set.filter { $0.partner.id != t.partner.id }
        let n = src.reduce(0) { $0 + $1.contractIDs.count }
        mergeAsk = MDDupMergeAsk(targetID: t.partner.id, targetName: t.partner.name, sources: src.map { $0.partner.id },
                                 sourceNames: src.map { $0.partner.name }, count: n)
    }

    private func merge(_ a: MDDupMergeAsk) {
        let ok = model.update { _ = $0.mergePartners(a.sources, into: a.targetID) }
        guard ok else { return }
        for n in a.sourceNames { model.mdRenameFilters(partnerFrom: n, partnerTo: a.targetName) }
        model.toast("Zusammengeführt")
    }
}

/// Rückfrage zum Zusammenführen von Dubletten
private struct MDDupMergeAlert: ViewModifier {
    @Binding var ask: MDDupMergeAsk?
    let onMerge: (MDDupMergeAsk) -> Void

    private var title: String {
        guard let a = ask else { return "" }
        return "Zu «" + a.targetName + "» zusammenführen?"
    }

    private func message(_ a: MDDupMergeAsk) -> String {
        let names: String = a.sourceNames.map { "«" + $0 + "»" }.joined(separator: ", ")
        let verb: String = a.sources.count == 1 ? "läuft" : "laufen"
        let parts: [String] = [names, " (", Format.count(a.count, "Vertrag", "Verträge"), ") ", verb, " danach unter «", a.targetName, "»."]
        return parts.joined()
    }

    func body(content: Content) -> some View {
        let show = Binding<Bool>(get: { ask != nil }, set: { if !$0 { ask = nil } })
        return content.alert(title, isPresented: show, presenting: ask) { a in
            Button("Zusammenführen") { onMerge(a) }
            Button("Abbrechen", role: .cancel) {}
        } message: { a in
            Text(message(a))
        }
    }
}

// MARK: - Vertragspartner-Seite

private enum MDPartnerField: Hashable {
    case name, web, company, extra, street, zip, city, country

    var isAddress: Bool {
        switch self {
        case .company, .extra, .street, .zip, .city, .country: return true
        default: return false
        }
    }
}

/// Seite eines Vertragspartners (MD_PAGES.pe): Name, Logo, Website, Adresse, Verträge, Zusammenführen
struct MDPartnerPage: View {
    let partnerID: UUID
    @Environment(AppModel.self) private var model
    @Environment(ManageNav.self) private var nav
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var name = ""
    @State private var web = ""
    @State private var addr = PostalAddress()
    @FocusState private var focus: MDPartnerField?
    @State private var logoTarget: MDLogoTarget?
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var crop: MDCropItem?
    @State private var addrPick: MDAddrPick?
    @State private var googleWait = false

    var body: some View {
        Group {
            if let p = model.data.partner(partnerID) {
                page(p)
            } else {
                List {
                    Section { MDHint("Dieser Vertragspartner existiert nicht mehr.").mdPlainRow() }
                }
                .mdListStyle()
            }
        }
        .navigationTitle(model.data.partner(partnerID)?.name ?? "Vertragspartner")
    }

    private func page(_ p: Partner) -> some View {
        sheets(handlers(content(p), p))
    }

    private func content(_ p: Partner) -> some View {
        List {
            headerSection
            logoSection(p)
            webSection
            addressSection
            contractsSection
            mergeSection
        }
        .mdListStyle()
    }

    private func handlers<V: View>(_ v: V, _ p: Partner) -> some View {
        v.onAppear {
            sync(p, force: true)
            nav.flush[.partner(partnerID)] = { commitAll() }
        }
            .onDisappear {
                commitAll()
                nav.flush[.partner(partnerID)] = nil
            }
            // Rückfrage abgebrochen: Feld auf den gespeicherten Namen zurücksetzen
            .onChange(of: nav.renameAsk?.id) { old, new in
                if old != nil && new == nil, let n = model.data.partner(partnerID)?.name, focus != .name { name = n }
            }
            .onChange(of: model.data.partner(partnerID)) { _, np in
                if let np { sync(np, force: false) }
            }
            .onChange(of: focus) { old, new in focusChanged(old, new) }
            .onChange(of: scenePhase) { _, ph in
                if ph == .active { googleReturned() }
            }
    }

    private func sheets<V: View>(_ v: V) -> some View {
        v.modifier(MDImageFlow(showPhotos: $showPhotos, showFiles: $showFiles, crop: $crop, title: "Logo zuschneiden") { png, bg in
            if model.mdSetPartnerLogo(partnerID, png: png, bg: bg) { model.toast("Logo gespeichert") }
        })
        .modifier(MDLogoSheet(target: $logoTarget))
        .modifier(MDAddrPickSheet(pick: $addrPick) { a in addr = a })
    }

    // MARK: Abschnitte

    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                MDPartnerMark(partnerID: partnerID, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Name").font(.caption).foregroundStyle(KColor.ink2)
                    TextField("Name", text: $name)
                        .font(.title3.weight(.semibold))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($focus, equals: .name)
                        .onSubmit { commitName() }
                        .accessibilityLabel("Name")
                }
            }
            .padding(.vertical, 6)
            .mdRow()
        }
    }

    private func logoSection(_ p: Partner) -> some View {
        let hasLogo = (p.logoID.map { !$0.isEmpty } ?? false) && model.files.has(p.logoID)
        return Section {
            VStack(alignment: .leading, spacing: 10) {
                Button { openLogoSearch() } label: {
                    Text("Logo automatisch finden").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                HStack(spacing: 8) {
                    Button { paste() } label: { Text("Einfügen").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                        .tint(googleWait ? KColor.warn : nil)
                    MDImageSourceMenu(showPhotos: $showPhotos, showFiles: $showFiles) {
                        Text("Hochladen").frame(maxWidth: .infinity)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.bordered)
                    Button { google() } label: { Text("Google").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                }
                if googleWait {
                    (Text("So geht’s: ").bold() + Text("In Google das passende Bild lange drücken → «Kopieren». Dann zurück in die App und «Einfügen» tippen."))
                        .font(.footnote)
                        .foregroundStyle(KColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if hasLogo {
                    Button(role: .destructive) { removeLogo() } label: {
                        Text("Bild entfernen").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(KColor.alert)
                }
            }
            .padding(.vertical, 4)
            .mdRow()
        } header: {
            Text("Logo")
        } footer: {
            Text("Gilt für alle Verträge dieses Vertragspartners.")
        }
    }

    private var webSection: some View {
        Section {
            TextField("z.B. sunrise.ch", text: $web)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focus, equals: .web)
                .onSubmit { commitWeb() }
                .accessibilityLabel("Website")
                .mdRow()
        } header: {
            Text("Website")
        }
    }

    private var addressSection: some View {
        Section {
            addrField("Firma, z.B. Sunrise GmbH", $addr.company, .company, next: .extra, content: .organizationName)
            addrField("Zusatz, z.B. Kundendienst oder Postfach", $addr.extra, .extra, next: .street)
            addrField("Strasse und Nr.", $addr.street, .street, next: .zip)
            HStack(spacing: 10) {
                TextField("PLZ", text: $addr.zip)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .zip)
                    .onSubmit { focus = .city }
                    .frame(maxWidth: 100)
                    .accessibilityLabel("PLZ")
                Divider()
                TextField("Ort", text: $addr.city)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .city)
                    .onSubmit { focus = .country }
                    .accessibilityLabel("Ort")
            }
            .mdRow()
            TextField("Land (optional)", text: $addr.country)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focus, equals: .country)
                .onSubmit {
                    focus = nil
                    commitAddress()
                }
                .accessibilityLabel("Land (optional)")
                .mdRow()
        } header: {
            MDSectionHeader(title: "Adresse") {
                Button("Suchen") { searchAddress() }
            }
        } footer: {
            Text("Für die Kündigung per Brief. Gilt für alle Verträge dieses Vertragspartners.")
        }
    }

    private func addrField(_ ph: String, _ text: Binding<String>, _ f: MDPartnerField, next: MDPartnerField, content: UITextContentType? = nil) -> some View {
        TextField(ph, text: text)
            .textContentType(content)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .focused($focus, equals: f)
            .onSubmit { focus = next }
            .accessibilityLabel(ph)
            .mdRow()
    }

    private var contractsSection: some View {
        let cs = model.data.contracts.filter { $0.partnerID == partnerID }
        let cost = model.data.mdPerMonth(cs, today: model.today)
        let home = model.data.settings.homeCurrency.rawValue
        return Section {
            ForEach(cs) { c in
                MDContractRow(contract: c)
            }
        } header: {
            MDSectionHeader(title: Format.count(cs.count, "Vertrag", "Verträge")) {
                Text(Format.money(cost) + " " + home + "/Mt.")
                    .font(.subheadline)
                    .foregroundStyle(KColor.ink2)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder private var mergeSection: some View {
        let others = Partners.groups(model.data, today: model.today).filter { $0.partner.id != partnerID }
        if !others.isEmpty {
            Section {
                MDActionRow(title: "Mit anderem Vertragspartner zusammenführen …") {
                    commitAll()
                    nav.push(.partnerMerge(partnerID))
                }
            }
        }
    }

    // MARK: Speichern

    private func sync(_ p: Partner, force: Bool) {
        if force || focus != .name { name = p.name }
        if force || focus != .web { web = p.web }
        if force || !(focus?.isAddress ?? false) { addr = p.address }
    }

    private func focusChanged(_ old: MDPartnerField?, _ new: MDPartnerField?) {
        guard let old else { return }
        if old == .name && new != .name { commitName() }
        if old == .web && new != .web { commitWeb() }
        if old.isAddress && !(new?.isAddress ?? false) { commitAddress() }
    }

    private func commitAll() {
        commitName()
        commitWeb()
        commitAddress()
    }

    /// Umbenennen (peRename): leer → zurücksetzen; gleicher Name eines anderen → Rückfrage Zusammenführen
    /// (auf Fenster-Ebene, damit sie auch beim Wegnavigieren erscheint – Web mdFlush)
    private func commitName() {
        guard let p = model.data.partner(partnerID) else { return }
        let n = Format.collapseSpaces(name)
        if n.isEmpty {
            name = p.name
            model.toast("Name darf nicht leer sein")
            return
        }
        if n == p.name { return }
        if let ex = model.data.partners.first(where: { $0.id != partnerID && $0.name.lowercased() == n.lowercased() }) {
            let cnt = model.data.contracts.filter { $0.partnerID == partnerID }.count
            nav.ask(MDRenameAsk(kind: .partner, sourceID: partnerID, otherID: ex.id, otherName: ex.name, oldName: p.name, count: cnt))
            return
        }
        let old = p.name
        if model.update({ try $0.renamePartner(partnerID, to: n) }) {
            model.mdRenameFilters(partnerFrom: old, partnerTo: n)
            name = n
            model.toast("Umbenannt")
        } else {
            name = p.name
        }
    }

    private func commitWeb() {
        guard let p = model.data.partner(partnerID) else { return }
        let w = web.trimmingCharacters(in: .whitespacesAndNewlines)
        if w == p.web { return }
        if model.update({ $0.setPartnerWeb(partnerID, w) }) { model.toast("Website gespeichert") }
    }

    /// Adresse speichern (paSave): nur bei Änderung; leer → «Adresse entfernt»
    private func commitAddress() {
        guard let p = model.data.partner(partnerID) else { return }
        let t = { (s: String) in Format.collapseSpaces(s) }
        let a = PostalAddress(company: t(addr.company), extra: t(addr.extra), street: t(addr.street),
                              zip: t(addr.zip), city: t(addr.city), country: t(addr.country))
        if a == p.address { return }
        if model.update({ $0.setPartnerAddress(partnerID, a) }) {
            model.toast(a.isEmpty ? "Adresse entfernt" : "Adresse gespeichert")
        }
    }

    // MARK: Logo

    private func openLogoSearch() {
        commitName()
        logoTarget = model.mdLogoTarget(partner: partnerID, name: name)
    }

    private func removeLogo() {
        if model.update({ $0.setPartnerLogo(partnerID, logoID: nil, background: nil) }) {
            model.toast("Logo entfernt")
        }
    }

    private func paste() {
        googleWait = false
        Task { @MainActor in
            if let img = await model.mdPasteboardImage() { crop = MDCropItem(image: img) }
        }
    }

    private func google() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty {
            model.toast("Zuerst den Namen eintragen")
            return
        }
        googleWait = true
        if let u = WebLinks.googleImages(n) { openURL(u) }
    }

    /// Zurück aus Google: Bild aus der Zwischenablage übernehmen, sonst Hinweis
    private func googleReturned() {
        guard googleWait else { return }
        let pb = UIPasteboard.general
        if pb.hasImages, let img = pb.image {
            googleWait = false
            crop = MDCropItem(image: img)
        } else {
            model.toast("Bild kopiert? Jetzt «Einfügen» tippen")
        }
    }

    // MARK: Adresse suchen

    private func searchAddress() {
        commitAddress()
        Task { @MainActor in
            if let pick = await model.mdFindAddress(.partner(partnerID), notFound: "Keine Adresse gefunden. Bitte von Website oder Rechnung übernehmen.") {
                addrPick = pick
            }
        }
    }
}

// MARK: - Zusammenführen

/// Zusammenführen mit einem anderen Vertragspartner (MD_PAGES.pmerge)
struct MDPartnerMergePage: View {
    let sourceID: UUID
    @Environment(AppModel.self) private var model
    @Environment(ManageNav.self) private var nav
    @State private var to: UUID?
    @State private var initialized = false

    var body: some View {
        Group {
            if let src = model.data.partner(sourceID) {
                content(src)
            } else {
                List { Section { MDHint("Nicht gefunden.").mdPlainRow() } }.mdListStyle()
            }
        }
        .navigationTitle("Zusammenführen")
    }

    private func candidates(_ src: Partner) -> [Partners.Group] {
        let groups = Partners.groups(model.data, today: model.today).filter { $0.partner.id != sourceID }
        let mine = Partners.pkey(src.name)
        if mine.isEmpty { return groups }
        return groups.filter { $0.key == mine } + groups.filter { $0.key != mine }
    }

    private func content(_ src: Partner) -> some View {
        let list = candidates(src)
        let mine = Partners.pkey(src.name)
        let srcCount = model.data.contracts.filter { $0.partnerID == sourceID }.count
        let target = list.first { $0.partner.id == to }
        return List {
            Section {
                MDHint(["«", src.name, "» (", Format.count(srcCount, "Vertrag", "Verträge"), ") zusammenführen mit:"].joined())
                    .mdPlainRow()
            }
            Section {
                ForEach(list, id: \.partner.id) { g in
                    Button { to = g.partner.id } label: {
                        HStack(spacing: 12) {
                            MDPartnerMark(partnerID: g.partner.id, size: 36)
                            MDTitleSub(title: g.partner.name, subtitle: Format.count(g.contractIDs.count, "Vertrag", "Verträge"))
                            Spacer(minLength: 4)
                            MDRadio(on: to == g.partner.id)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(to == g.partner.id ? .isSelected : [])
                    .mdRow()
                }
            }
            if let t = target {
                Section {
                    MDHint([Format.count(srcCount + t.contractIDs.count, "Vertrag läuft", "Verträge laufen"), " danach unter «", t.partner.name, "». Fehlendes Logo und fehlende Website werden ergänzt, die Adresse gilt für alle."].joined())
                        .mdPlainRow()
                }
            }
            Section {
                MDMainButton(title: "Zusammenführen", disabled: target == nil) { merge() }
            }
        }
        .mdListStyle()
        .onAppear {
            guard !initialized else { return }
            initialized = true
            if !mine.isEmpty { to = list.first { $0.key == mine }?.partner.id }
        }
    }

    private func merge() {
        guard let t = to, let tp = model.data.partner(t) else { return }
        let srcName = model.data.partner(sourceID)?.name ?? ""
        guard model.update({ _ = $0.mergePartners([sourceID], into: t) }) else { return }
        model.mdRenameFilters(partnerFrom: srcName, partnerTo: tp.name)
        nav.swap(.partner(t), n: 2)
        model.toast("Zusammengeführt mit «\(tp.name)»")
    }
}
