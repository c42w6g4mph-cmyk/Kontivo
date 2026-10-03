import SwiftUI
import KontivoCore

// MARK: - Hilfen

/// «n Verträge · m Einnahmen» (holderStats)
private func mdCountText(_ s: PersonStat) -> String {
    Format.count(s.contracts, "Vertrag", "Verträge") + (s.incomes > 0 ? " · " + Format.count(s.incomes, "Einnahme", "Einnahmen") : "")
}

/// Runde Initiale ohne Bild (hdel)
private struct MDInitial: View {
    let text: String
    var dimmed = false
    var body: some View {
        ZStack {
            Circle().fill(dimmed ? KColor.field : KColor.teal.opacity(0.14))
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(dimmed ? KColor.ink2 : KColor.teal)
        }
        .frame(width: 36, height: 36)
        .accessibilityHidden(true)
    }
}

/// Eintrag eines Inhabers: Vertrag oder Einnahme
private enum MDPersonEntry: Identifiable {
    case contract(Contract)
    case income(Income)

    var id: UUID {
        switch self {
        case .contract(let c): return c.id
        case .income(let i): return i.id
        }
    }
}

extension Array where Element == Contract {
    /// Stabil nach Titel (de-CH) sortieren
    func mdSortedByTitle(_ d: AppData) -> [Contract] {
        enumerated().sorted { a, b in
            let ta = d.title(of: a.element), tb = d.title(of: b.element)
            if Format.lessDE(ta, tb) { return true }
            if Format.lessDE(tb, ta) { return false }
            return a.offset < b.offset
        }.map { $0.element }
    }
}

extension Array where Element == Income {
    func mdSortedByTitle() -> [Income] {
        enumerated().sorted { a, b in
            if Format.lessDE(a.element.title, b.element.title) { return true }
            if Format.lessDE(b.element.title, a.element.title) { return false }
            return a.offset < b.offset
        }.map { $0.element }
    }
}

/// Zusatz eines Vertrags wie in der Web-App: Vertragspartner, wenn Bezeichnung und Vertragspartner gesetzt sind
func mdContractSub(_ c: Contract, _ d: AppData) -> String {
    let pn = d.partnerName(of: c)
    return (!c.label.isEmpty && !pn.isEmpty) ? pn : ""
}

// MARK: - Liste

/// Inhaber (MD_PAGES.holder)
struct MDPersonsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let d = model.data
        let stats = d.personStats()
        let nAll = d.contracts.count + d.incomes.count
        return List {
            if stats.count > 1 && nAll > 0 {
                Section {
                    NavigationLink(value: ManagePage.assign(.all)) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(KColor.teal.opacity(0.14))
                                Image(systemName: "person.2.fill").font(.system(size: 15)).foregroundStyle(KColor.teal)
                            }
                            .frame(width: 36, height: 36)
                            .accessibilityHidden(true)
                            MDTitleSub(title: "Verträge zuordnen", subtitle: "Wer zahlt was: pro Vertrag mit einem Tipp wechseln")
                        }
                    }
                    .mdRow()
                }
            }
            Section {
                ForEach(stats, id: \.person.id) { s in
                    NavigationLink(value: ManagePage.person(s.person.id)) {
                        HStack(spacing: 12) {
                            PersonAvatar(person: s.person, size: 36)
                            MDTitleSub(title: s.person.name, subtitle: mdCountText(s))
                        }
                    }
                    .mdRow()
                }
                NavigationLink(value: ManagePage.personNew) {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(KColor.teal)
                            .frame(width: 36, height: 36)
                            .accessibilityHidden(true)
                        Text("Inhaber hinzufügen").font(.body.weight(.semibold)).foregroundStyle(KColor.teal)
                    }
                }
                .mdRow()
            } header: {
                Text("Personen")
            } footer: {
                Text("Inhaber sind die Personen in deinem Haushalt. Tippe auf eine Person für Absender, Unterschrift und Verträge."
                     + (stats.count < 2 ? " Mit zwei oder mehr Personen kannst du Verträge gemeinsam oder getrennt zuordnen." : ""))
            }
        }
        .mdListStyle()
        .navigationTitle("Inhaber")
    }
}

// MARK: - Neuer Inhaber

/// Neuer Inhaber (MD_PAGES.henew)
struct MDPersonNewPage: View {
    @Environment(AppModel.self) private var model
    @Environment(ManageNav.self) private var nav
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        List {
            Section {
                TextField("z.B. Lara", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focused)
                    .onSubmit { add() }
                    .onChange(of: name) { _, v in if v.count > 30 { name = mdLimit30(v) } }
                    .accessibilityLabel("Name")
                    .mdRow()
            } header: {
                Text("Name")
            }
            Section {
                MDMainButton(title: "Hinzufügen") { add() }
            }
        }
        .mdListStyle()
        .navigationTitle("Neuer Inhaber")
        .task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            focused = true
        }
    }

    private func add() {
        let v = Format.collapseSpaces(name)
        if v.isEmpty {
            model.toast("Bitte einen Namen eingeben")
            return
        }
        if model.data.persons.contains(where: { $0.name.lowercased() == v.lowercased() }) {
            model.toast("Diesen Inhaber gibt es schon")
            return
        }
        if model.update({ _ = try $0.addPerson(v) }) {
            focused = false
            nav.pop()
            model.toast("Inhaber «\(v)» angelegt")
        }
    }
}

// MARK: - Personenkarte

private struct MDPersonRenameAsk: Identifiable {
    let id = UUID()
    let otherID: UUID
    let otherName: String
    let oldName: String
}

/// Personenkarte wie die iOS-Kontakte (MD_PAGES.he)
struct MDPersonPage: View {
    let personID: UUID
    @Environment(AppModel.self) private var model
    @Environment(ManageNav.self) private var nav
    @State private var editing = false
    @State private var showAll = false
    @State private var name = ""
    @FocusState private var nameFocused: Bool
    @State private var renameAsk: MDPersonRenameAsk?
    @State private var deleteAsk = false
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var crop: MDCropItem?

    var body: some View {
        Group {
            if let p = model.data.person(personID) {
                page(p)
            } else {
                List { Section { MDHint("Diese Person gibt es nicht mehr.").mdPlainRow() } }.mdListStyle()
            }
        }
        .navigationTitle(model.data.person(personID)?.name ?? "Inhaber")
    }

    private func page(_ p: Person) -> some View {
        List {
            headerSection(p)
            cancelSection(p)
            entriesSection
            if editing {
                Section {
                    MDActionRow(title: "Inhaber löschen", destructive: true) { deleteTapped(p) }
                }
            }
        }
        .mdListStyle()
        .onAppear { if !nameFocused { name = p.name } }
        .onDisappear { commitName(ask: false) }
        .onChange(of: nameFocused) { _, f in if !f { commitName(ask: true) } }
        .onChange(of: model.data.person(personID)?.name) { _, n in
            if let n, !nameFocused { name = n }
        }
        .modifier(MDImageFlow(showPhotos: $showPhotos, showFiles: $showFiles, crop: $crop, title: "Bild zuschneiden") { png, _ in
            setAvatar(png)
        })
        .alert(renameAsk.map { "«\($0.otherName)» gibt es schon" } ?? "",
               isPresented: Binding(get: { renameAsk != nil }, set: { if !$0 { renameAsk = nil } }),
               presenting: renameAsk) { a in
            Button("Zusammenführen") { mergeInto(a) }
            Button("Abbrechen", role: .cancel) { name = model.data.person(personID)?.name ?? name }
        } message: { a in
            Text("Alle Einträge von «" + a.oldName + "» gehen an «" + a.otherName + "», «" + a.oldName + "» wird entfernt.")
        }
        .alert("«\(p.name)» löschen?", isPresented: $deleteAsk) {
            Button("Löschen", role: .destructive) { deleteNow() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Der Inhaber ist nirgends zugeordnet.")
        }
    }

    private var stat: PersonStat? {
        model.data.personStats().first { $0.person.id == personID }
    }

    // MARK: Kopf

    private func headerSection(_ p: Person) -> some View {
        let hasAvatar = (p.avatarID.map { !$0.isEmpty } ?? false) && model.files.has(p.avatarID)
        return Section {
            VStack(spacing: 10) {
                HStack {
                    Spacer()
                    Button(editing ? "Fertig" : "Bearbeiten") { toggleEdit() }
                        .buttonStyle(.borderless)
                        .font(.subheadline.weight(.semibold))
                }
                PersonAvatar(person: p, size: 96)
                if editing {
                    HStack(spacing: 10) {
                        MDImageSourceMenu(showPhotos: $showPhotos, showFiles: $showFiles) {
                            Text(hasAvatar ? "Bild ändern" : "Foto oder Logo wählen")
                        }
                        .menuStyle(.button)
                        .buttonStyle(.bordered)
                        if hasAvatar {
                            Button("Entfernen") { removeAvatar() }
                                .buttonStyle(.bordered)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name").font(.caption).foregroundStyle(KColor.ink2)
                        TextField("Name", text: $name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($nameFocused)
                            .onSubmit { commitName(ask: true) }
                            .onChange(of: name) { _, v in if v.count > 30 { name = mdLimit30(v) } }
                            .mdFieldBox()
                            .accessibilityLabel("Name")
                    }
                } else {
                    Text(p.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(KColor.ink)
                        .multilineTextAlignment(.center)
                    if let s = stat {
                        Text(mdCountText(s)).font(.subheadline).foregroundStyle(KColor.ink2)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .mdRow()
        }
    }

    // MARK: Kündigungen

    private func cancelSection(_ p: Person) -> some View {
        let s = model.data.resolvedSender(personID)
        let ok = s.isComplete
        let zipCity = [s.zip, s.city].filter { !$0.isEmpty }.joined(separator: " ")
        let sub = ok ? [s.fullName, s.street, zipCity].filter { !$0.isEmpty }.joined(separator: ", ") : "Name und Adresse für Briefe"
        let sig = p.signatureJPEG != nil
        return Section {
            NavigationLink(value: ManagePage.sender(personID)) {
                HStack(spacing: 10) {
                    MDTitleSub(title: "Absender", subtitle: sub)
                    Spacer(minLength: 6)
                    Text(ok ? "✓" : "ergänzen")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ok ? KColor.ok : KColor.warn)
                }
            }
            .mdRow()
            NavigationLink(value: ManagePage.sender(personID)) {
                HStack(spacing: 10) {
                    MDTitleSub(title: "Unterschrift", subtitle: sig ? "hinterlegt" : "ohne: Linie zum Unterschreiben von Hand")
                    Spacer(minLength: 6)
                    Text(sig ? "✓" : "optional")
                        .font(.subheadline.weight(sig ? .semibold : .regular))
                        .foregroundStyle(sig ? KColor.ok : KColor.ink2)
                }
            }
            .mdRow()
        } header: {
            Text("Kündigungen")
        }
    }

    // MARK: Einträge

    private var entriesSection: some View {
        let d = model.data
        let calc = model.calc
        let cs = d.contracts.filter { $0.holderIDs.contains(personID) }
            .enumerated().sorted { a, b in
                let ma = calc.monthlyCost(a.element), mb = calc.monthlyCost(b.element)
                if ma != mb { return ma > mb }
                return a.offset < b.offset
            }.map { $0.element }
        let iss = d.incomes.filter { $0.holderID == personID }.mdSortedByTitle()
        let items: [MDPersonEntry] = cs.map { MDPersonEntry.contract($0) } + iss.map { MDPersonEntry.income($0) }
        let multi = d.persons.count > 1
        var parts: [String] = []
        if !cs.isEmpty { parts.append(Format.count(cs.count, "Vertrag", "Verträge")) }
        if !iss.isEmpty { parts.append(Format.count(iss.count, "Einnahme", "Einnahmen")) }
        let title = items.isEmpty ? "Verträge" : parts.joined(separator: ", ")
        let shown = showAll ? items : Array(items.prefix(4))
        return Section {
            if items.isEmpty {
                MDHint("Noch nichts zugeordnet." + (multi ? " Über «Zuordnen» Verträge zuweisen." : ""))
                    .mdRow()
            } else {
                ForEach(shown) { e in
                    entryRow(e)
                }
                if items.count > 4 && !showAll {
                    MDActionRow(title: "Alle \(items.count) zeigen") { showAll = true }
                }
            }
        } header: {
            MDSectionHeader(title: title) {
                if multi {
                    Button("Zuordnen") {
                        commitName(ask: false)
                        nav.push(.assign(.person(personID)))
                    }
                }
            }
        }
    }

    @ViewBuilder private func entryRow(_ e: MDPersonEntry) -> some View {
        let d = model.data
        switch e {
        case .contract(let c):
            let others = c.holderIDs.filter { $0 != personID }.compactMap { d.person($0)?.name }
            let sub = [mdContractSub(c, d), others.isEmpty ? "" : "mit " + others.joined(separator: ", ")]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            Button { model.present(.contractDetail(c.id)) } label: {
                HStack(spacing: 12) {
                    MarkView(contract: c, data: d, size: 36)
                    MDTitleSub(title: d.title(of: c), subtitle: sub)
                    Spacer(minLength: 4)
                    MoneyText(amount: model.calc.curPrice(c), currency: c.currency.rawValue, font: .subheadline.weight(.semibold))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .mdRow()
        case .income(let i):
            Button { model.present(.incomeForm(i.id)) } label: {
                HStack(spacing: 12) {
                    MarkView(income: i, size: 36)
                    MDTitleSub(title: i.title, subtitle: "Einnahme")
                    Spacer(minLength: 4)
                    MoneyText(amount: i.amount, currency: i.currency.rawValue, font: .subheadline.weight(.semibold))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .mdRow()
        }
    }

    // MARK: Aktionen

    private func toggleEdit() {
        if editing { commitName(ask: true) }
        nameFocused = false
        editing.toggle()
    }

    /// Umbenennen (heRename)
    private func commitName(ask: Bool) {
        guard let p = model.data.person(personID) else { return }
        let n = Format.collapseSpaces(name)
        if n.isEmpty {
            name = p.name
            model.toast("Name darf nicht leer sein")
            return
        }
        if n == p.name { return }
        if let ex = model.data.persons.first(where: { $0.id != personID && $0.name.lowercased() == n.lowercased() }) {
            if ask {
                if renameAsk == nil { renameAsk = MDPersonRenameAsk(otherID: ex.id, otherName: ex.name, oldName: p.name) }
            } else {
                name = p.name
            }
            return
        }
        if model.update({ try $0.renamePerson(personID, to: n) }) {
            name = n
            model.toast("Umbenannt")
        } else {
            name = p.name
        }
    }

    private func mergeInto(_ a: MDPersonRenameAsk) {
        guard model.data.person(a.otherID) != nil else { return }
        model.update { $0.mergePerson(personID, into: a.otherID) }
        model.mdMovePersonFilters(from: personID, to: a.otherID)
        nav.swap(.person(a.otherID))
        model.toast("Zusammengeführt mit «\(a.otherName)»")
    }

    private func setAvatar(_ png: Data) {
        guard let fid = model.storeFile(png, type: "image/png") else { return }
        if model.update({ $0.setAvatar(personID, fid) }) { model.toast("Bild gesetzt") }
    }

    private func removeAvatar() {
        if model.update({ $0.setAvatar(personID, nil) }) { model.toast("Bild entfernt") }
    }

    private func deleteTapped(_ p: Person) {
        if model.data.persons.count <= 1 {
            model.toast("Mindestens ein Inhaber ist nötig")
            return
        }
        commitName(ask: false)
        let s = stat
        if (s?.contracts ?? 0) == 0 && (s?.incomes ?? 0) == 0 {
            deleteAsk = true
        } else {
            nav.push(.personDelete(personID))
        }
    }

    private func deleteNow() {
        if model.update({ try $0.deletePerson(personID, transferTo: nil) }) {
            model.mdMovePersonFilters(from: personID, to: nil)
            nav.pop()
            model.toast("Inhaber gelöscht")
        }
    }
}

// MARK: - Inhaber löschen

/// Inhaber löschen mit Übertrag oder ohne Inhaber (MD_PAGES.hdel)
struct MDPersonDeletePage: View {
    let personID: UUID
    @Environment(AppModel.self) private var model
    @Environment(ManageNav.self) private var nav
    @State private var to: UUID?
    @State private var initialized = false

    var body: some View {
        Group {
            if let p = model.data.person(personID) {
                content(p)
            } else {
                List { Section { MDHint("Diese Person gibt es nicht mehr.").mdPlainRow() } }.mdListStyle()
            }
        }
        .navigationTitle("Inhaber löschen")
    }

    private func content(_ p: Person) -> some View {
        let st = model.data.personStats().first { $0.person.id == personID }
        let c = st?.contracts ?? 0
        let i = st?.incomes ?? 0
        let others = model.data.persons.filter { $0.id != personID }
        let inc: String = i > 0 ? " und " + Format.count(i, "Einnahme", "Einnahmen") : ""
        let text: String = ["«", p.name, "» ist ", Format.count(c, "Vertrag", "Verträgen"), inc, " zugeordnet. Was soll damit passieren?"].joined()
        return List {
            Section { MDHint(text).mdPlainRow() }
            Section {
                ForEach(others) { o in
                    option(on: to == o.id, action: { to = o.id }) {
                        MDInitial(text: String(o.name.prefix(1)).uppercased())
                        MDTitleSub(title: "An «" + o.name + "» übertragen")
                    }
                }
                option(on: to == nil, action: { to = nil }) {
                    MDInitial(text: "–", dimmed: true)
                    MDTitleSub(title: "Ohne Inhaber lassen", subtitle: "Gemeinsame Einträge behalten die übrigen Inhaber")
                }
            }
            Section {
                MDMainButton(title: "Inhaber löschen", destructive: true) { delete() }
            }
        }
        .mdListStyle()
        .onAppear {
            guard !initialized else { return }
            initialized = true
            to = others.first?.id
        }
    }

    private func option<L: View>(on: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                label()
                Spacer(minLength: 4)
                MDRadio(on: on)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .mdRow()
    }

    private func delete() {
        let toName = to.flatMap { model.data.person($0)?.name }
        if model.update({ try $0.deletePerson(personID, transferTo: to) }) {
            model.mdMovePersonFilters(from: personID, to: to)
            nav.pop(2)
            model.toast(toName.map { "Gelöscht, Einträge an «\($0)» übertragen" } ?? "Inhaber gelöscht")
        }
    }
}

// MARK: - Absender und Unterschrift

private enum MDSenderField: Hashable {
    case first, last, street, zip, city, country
}

/// Namenszug-Vorschläge für
private struct MDSigSuggest: Identifiable {
    let id = UUID()
    let first: String
    let last: String
}

/// Absender und Unterschrift einer Person (MD_PAGES.hs)
struct MDSenderPage: View {
    let personID: UUID
    @Environment(AppModel.self) private var model
    @State private var draft = SenderAddress()
    @FocusState private var focus: MDSenderField?
    @State private var showPad = false
    @State private var suggest: MDSigSuggest?

    var body: some View {
        Group {
            if let p = model.data.person(personID) {
                page(p)
            } else {
                List { Section { MDHint("Diese Person gibt es nicht mehr.").mdPlainRow() } }.mdListStyle()
            }
        }
        .navigationTitle("Absender")
    }

    private func page(_ p: Person) -> some View {
        let candidates = model.data.sameAddressCandidates(for: personID)
        let sameID: UUID? = p.sameAddressAs.flatMap { sid in candidates.contains { $0.id == sid } ? sid : nil }
        return List {
            Section {
                MDHint("Steht oben im Kündigungsschreiben, wenn \(p.name) kündigt.").mdPlainRow()
            }
            Section {
                HStack(spacing: 10) {
                    field("Vorname", $draft.first, .first, next: .last, content: .givenName)
                    Divider()
                    field("Nachname", $draft.last, .last, next: sameID == nil ? .street : nil, content: .familyName)
                }
                .mdRow()
                if sameID == nil {
                    field("Strasse und Nr.", $draft.street, .street, next: .zip, content: .streetAddressLine1)
                        .mdRow()
                    HStack(spacing: 10) {
                        field("PLZ", $draft.zip, .zip, next: .city, content: .postalCode, keyboard: .numbersAndPunctuation)
                            .frame(maxWidth: 100)
                        Divider()
                        field("Ort", $draft.city, .city, next: .country, content: .addressCity)
                    }
                    .mdRow()
                    field("Land (optional)", $draft.country, .country, next: nil, content: .countryName)
                        .mdRow()
                }
            }
            if !candidates.isEmpty {
                Section {
                    MDChipRow {
                        Chip(title: "Eigene Adresse", isOn: sameID == nil) { setSame(nil) }
                        ForEach(candidates) { o in
                            Chip(title: "Gleich wie \(o.name)", isOn: sameID == o.id) { setSame(o.id) }
                        }
                    }
                    .mdPlainRow()
                    if sameID != nil {
                        MDHint(model.data.resolvedSender(personID).addressLines.joined(separator: ", "))
                            .mdPlainRow()
                    }
                }
            }
            signatureSection(p)
        }
        .mdListStyle()
        .onAppear { draft = p.sender }
        .onDisappear { save() }
        .onChange(of: focus) { old, new in
            if old != nil && new == nil { save() }
        }
        .sheet(isPresented: $showPad) {
            SignaturePadSheet(title: "Unterschrift") { jpeg in
                showPad = false
                setSignature(jpeg, toast: "Unterschrift gespeichert")
            }
            .environment(model)
        }
        .sheet(item: $suggest) { s in
            SignatureSuggestionsSheet(first: s.first, last: s.last) { jpeg in
                suggest = nil
                setSignature(jpeg, toast: "Namenszug übernommen")
            }
            .environment(model)
        }
    }

    private func field(_ ph: String, _ text: Binding<String>, _ f: MDSenderField, next: MDSenderField?,
                       content: UITextContentType, keyboard: UIKeyboardType = .default) -> some View {
        TextField(ph, text: text)
            .textContentType(content)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(next == nil ? .done : .next)
            .focused($focus, equals: f)
            .onSubmit {
                if let next {
                    focus = next
                } else {
                    focus = nil
                    save()
                }
            }
            .accessibilityLabel(ph)
    }

    private func signatureSection(_ p: Person) -> some View {
        Section {
            Group {
                if let d = p.signatureJPEG, let img = UIImage(data: d) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 90)
                        .accessibilityLabel("Unterschrift")
                } else {
                    Text("Noch keine Unterschrift")
                        .font(.subheadline)
                        .foregroundStyle(Color.gray)
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(KColor.line, lineWidth: 0.5))
            .mdPlainRow()
            HStack(spacing: 8) {
                Button { save(); showPad = true } label: { Text("Zeichnen").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                Button { openSuggestions(p) } label: { Text("Vorschläge").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                if p.signatureJPEG != nil {
                    Button { setSignature(nil, toast: "Unterschrift entfernt") } label: { Text("Entfernen").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                }
            }
            .mdPlainRow()
        } header: {
            Text("Unterschrift")
        } footer: {
            Text("Nur \(p.name) selbst sollte die Unterschrift zeichnen oder wählen. Sie bleibt auf diesem Gerät. Ohne Unterschrift bleibt im Brief eine Linie zum Unterschreiben von Hand.")
        }
    }

    private func normalized() -> SenderAddress {
        let t = { (s: String) in Format.collapseSpaces(s) }
        return SenderAddress(first: t(draft.first), last: t(draft.last), street: t(draft.street),
                             zip: t(draft.zip), city: t(draft.city), country: t(draft.country))
    }

    /// Absender speichern (hsSave): nur bei Änderung; ungültiges «gleich wie» fällt weg (Fix M1)
    private func save() {
        guard let p = model.data.person(personID) else { return }
        let s = normalized()
        if s == p.sender { return }
        if model.update({ $0.setSender(personID, s, sameAs: p.sameAddressAs) }) {
            model.toast("Absender gespeichert")
        }
    }

    /// «Eigene Adresse» / «Gleich wie X»: zuerst die Felder sichern, dann umstellen
    private func setSame(_ other: UUID?) {
        focus = nil
        save()
        let s = normalized()
        model.update { $0.setSender(personID, s, sameAs: other) }
    }

    private func openSuggestions(_ p: Person) {
        save()
        let s = model.data.resolvedSender(personID)
        var first = s.first
        var last = s.last
        if first.isEmpty && last.isEmpty {
            let w = p.name.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            first = w.first ?? ""
            last = w.dropFirst().joined(separator: " ")
        }
        if first.isEmpty && last.isEmpty {
            model.toast("Zuerst den Namen beim Absender erfassen")
            return
        }
        suggest = MDSigSuggest(first: first, last: last)
    }

    private func setSignature(_ jpeg: Data?, toast: String) {
        if model.update({ $0.setSignature(personID, jpeg) }) { model.toast(toast) }
    }
}

// MARK: - Verträge zuordnen

private enum MDAssignItem: Identifiable {
    case contract(Contract)
    case income(Income)

    var id: UUID {
        switch self {
        case .contract(let c): return c.id
        case .income(let i): return i.id
        }
    }

    var holderless: Bool {
        switch self {
        case .contract(let c): return c.holderIDs.isEmpty
        case .income(let i): return i.holderID == nil
        }
    }

    func has(_ p: UUID) -> Bool {
        switch self {
        case .contract(let c): return c.holderIDs.contains(p)
        case .income(let i): return i.holderID == p
        }
    }
}

/// Verträge zuordnen (MD_PAGES.hassign): pro Eintrag mit einem Tipp wechseln
struct MDAssignPage: View {
    let initialFilter: MDAssignFilter
    @Environment(AppModel.self) private var model
    @State private var filter: MDAssignFilter

    init(initialFilter: MDAssignFilter) {
        self.initialFilter = initialFilter
        _filter = State(initialValue: initialFilter)
    }

    var body: some View {
        let d = model.data
        let calc = model.calc
        let contracts = d.contracts.filter { calc.isActive($0) }.mdSortedByTitle(d)
        let incomes = d.incomes.mdSortedByTitle()
        let items: [MDAssignItem] = contracts.map { MDAssignItem.contract($0) } + incomes.map { MDAssignItem.income($0) }
        let noneCount = items.filter { $0.holderless }.count
        let shown: [MDAssignItem]
        switch filter {
        case .all: shown = items
        case .unassigned: shown = items.filter { $0.holderless }
        case .person(let p): shown = items.filter { $0.has(p) }
        }
        return List {
            Section {
                MDChipRow {
                    Chip(title: "Alle", isOn: filter == .all) { filter = .all }
                    ForEach(d.persons) { p in
                        Chip(title: p.name, isOn: filter == .person(p.id)) { filter = .person(p.id) }
                    }
                    Chip(title: "Ohne Inhaber" + (noneCount > 0 ? " · \(noneCount)" : ""), isOn: filter == .unassigned) { filter = .unassigned }
                }
                .mdPlainRow()
            }
            if shown.isEmpty {
                Section { MDHint(emptyText(d)).mdPlainRow() }
            } else {
                Section {
                    ForEach(shown) { it in
                        MDAssignRow(item: it)
                    }
                }
                Section {
                    NavigationLink(value: ManagePage.transfer) {
                        Text("Alle Einträge einer Person übertragen …")
                            .font(.body.weight(.medium))
                            .foregroundStyle(KColor.teal)
                    }
                    .mdRow()
                }
            }
        }
        .mdListStyle()
        .navigationTitle("Verträge zuordnen")
    }

    private func emptyText(_ d: AppData) -> String {
        switch filter {
        case .unassigned: return "Alle Einträge haben einen Inhaber."
        case .person(let p): return "«" + (d.person(p)?.name ?? "") + "» ist nichts zugeordnet."
        case .all: return "Noch keine Verträge oder Einnahmen."
        }
    }
}

/// Zeile «Verträge zuordnen»: Segment bei 2 Personen, sonst Chips; Einnahmen nur eine Person (Fix N6)
private struct MDAssignRow: View {
    let item: MDAssignItem
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            control
        }
        .padding(.vertical, 4)
        .mdRow()
    }

    @ViewBuilder private var header: some View {
        let d = model.data
        switch item {
        case .contract(let c):
            HStack(spacing: 12) {
                MarkView(contract: c, data: d, size: 36)
                MDTitleSub(title: d.title(of: c), subtitle: mdContractSub(c, d))
            }
        case .income(let i):
            HStack(spacing: 12) {
                MarkView(income: i, size: 36)
                MDTitleSub(title: i.title, subtitle: "Einnahme")
            }
        }
    }

    @ViewBuilder private var control: some View {
        let persons = model.data.persons
        switch item {
        case .contract(let c):
            let all = !persons.isEmpty && persons.allSatisfy { c.holderIDs.contains($0.id) }
            if persons.count == 2 {
                let sel: Set<HolderChoice> = all ? [.all] : (c.holderIDs.count == 1 ? [.person(c.holderIDs[0])] : [])
                MDSegment(options: persons.map { (title: $0.name, value: HolderChoice.person($0.id)) } + [(title: "Beide", value: HolderChoice.all)],
                          selected: sel) { ch in apply(c, ch) }
            } else {
                MDChipRow {
                    ForEach(persons) { p in
                        Chip(title: p.name, isOn: c.holderIDs.contains(p.id)) { apply(c, .person(p.id)) }
                    }
                    Chip(title: "Alle", isOn: all) { apply(c, .all) }
                }
            }
        case .income(let i):
            if persons.count == 2 {
                MDSegment(options: persons.map { (title: $0.name, value: $0.id) },
                          selected: i.holderID.map { Set([$0]) } ?? Set<UUID>()) { p in recipient(i, p) }
            } else {
                MDChipRow {
                    ForEach(persons) { p in
                        Chip(title: p.name, isOn: i.holderID == p.id) { recipient(i, p.id) }
                    }
                }
            }
        }
    }

    private func apply(_ c: Contract, _ ch: HolderChoice) {
        var changed = false
        model.update { changed = $0.applyHolderChoice(contract: c.id, choice: ch) }
        guard changed, let nc = model.data.contract(c.id) else { return }
        model.toast(model.data.holderChoiceToast(title: model.data.title(of: nc), holderIDs: nc.holderIDs))
    }

    private func recipient(_ i: Income, _ p: UUID) {
        var changed = false
        model.update { changed = $0.setIncomeRecipient(i.id, person: p) }
        guard changed else { return }
        model.toast(i.title + " → " + (model.data.person(p)?.name ?? ""))
    }
}

// MARK: - Alle übertragen

/// Alle Einträge einer Person übertragen (MD_PAGES.hbulk)
struct MDTransferPage: View {
    @Environment(AppModel.self) private var model
    @Environment(ManageNav.self) private var nav
    @State private var from: UUID?
    @State private var to: UUID?

    var body: some View {
        let stats = model.data.personStats()
        let fromID = from ?? stats.first?.person.id
        let fs = stats.first { $0.person.id == fromID }
        let n = (fs?.contracts ?? 0) + (fs?.incomes ?? 0)
        let fromName = fs?.person.name ?? ""
        let toName = to.flatMap { model.data.person($0)?.name }
        return List {
            Section {
                ForEach(stats, id: \.person.id) { s in
                    pick(s, on: fromID == s.person.id) {
                        from = s.person.id
                        if to == s.person.id { to = nil }
                    }
                }
            } header: {
                Text("Von")
            }
            Section {
                ForEach(stats.filter { $0.person.id != fromID }, id: \.person.id) { s in
                    pick(s, on: to == s.person.id) { to = s.person.id }
                }
            } header: {
                Text("An")
            }
            Section {
                MDHint(transferHint(n: n, fromName: fromName, toName: toName))
                    .mdPlainRow()
            }
            Section {
                MDMainButton(title: "Übertragen", disabled: to == nil || n == 0) { transfer(fromID) }
            }
        }
        .mdListStyle()
        .navigationTitle("Alle übertragen")
    }

    private func transferHint(n: Int, fromName: String, toName: String?) -> String {
        guard let tn = toName else { return "Zum Beispiel nach einem Umzug oder wenn jemand die Verträge übernimmt." }
        let parts: [String] = [Format.count(n, "Eintrag geht", "Einträge gehen"), " von «", fromName, "» an «", tn,
                               "». Gemeinsame Einträge bleiben gemeinsam. «", fromName, "» bleibt als Person bestehen."]
        return parts.joined()
    }

    private func pick(_ s: PersonStat, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                PersonAvatar(person: s.person, size: 36)
                MDTitleSub(title: s.person.name, subtitle: mdCountText(s))
                Spacer(minLength: 4)
                MDRadio(on: on)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .mdRow()
    }

    private func transfer(_ fromID: UUID?) {
        guard let f = fromID, let t = to, f != t, let tn = model.data.person(t)?.name else { return }
        var n = 0
        guard model.update({ n = $0.transferAll(from: f, to: t) }) else { return }
        nav.pop()
        model.toast(Format.count(n, "Eintrag", "Einträge") + " an «" + tn + "» übertragen")
    }
}
