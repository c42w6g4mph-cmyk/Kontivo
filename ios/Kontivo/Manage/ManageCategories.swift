import SwiftUI
import KontivoCore

// MARK: - Bausteine

/// Name eines Symbol-Schlüssels für Bedienhilfen
private func mdIconName(_ key: String) -> String {
    key == "tag" ? "Etikett" : key
}

/// Farbauswahl (CE_COL, 12 Farben)
struct MDColorGrid: View {
    let selected: String
    let pick: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 12)], spacing: 12) {
            ForEach(KCategory.editColors, id: \.self) { hex in
                let on = selected.uppercased() == hex.uppercased()
                Button { pick(hex) } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 36, height: 36)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: on ? 3 : 0))
                        .padding(3)
                        .overlay(Circle().strokeBorder(KColor.ink, lineWidth: on ? 2 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Farbe")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}

/// Symbolauswahl (CE_ICONS, 13 Symbole) auf der aktuellen Farbe
struct MDIconGrid: View {
    let color: String
    let selected: String
    let pick: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 10)], spacing: 10) {
            ForEach(KIcon.choices, id: \.self) { key in
                let on = selected == key
                Button { pick(key) } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: color))
                        Image(systemName: KIcon.symbol(forKey: key))
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 40, height: 40)
                    .padding(3)
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(KColor.ink, lineWidth: on ? 2 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Symbol " + mdIconName(key))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Liste

/// Rückfrage ««Name» löschen?» für eine leere Kategorie
private struct MDCategoryDeleteAlert: ViewModifier {
    @Binding var ask: KCategory?
    let onDelete: (KCategory) -> Void

    func body(content: Content) -> some View {
        let show = Binding<Bool>(get: { ask != nil }, set: { if !$0 { ask = nil } })
        let title: String = ask.map { "«" + $0.name + "» löschen?" } ?? ""
        return content.alert(title, isPresented: show, presenting: ask) { c in
            Button("Löschen", role: .destructive) { onDelete(c) }
            Button("Abbrechen", role: .cancel) {}
        } message: { _ in
            Text("Die Kategorie ist leer.")
        }
    }
}

/// Kategorien (MD_PAGES.cat): Bearbeiten-Modus mit Löschen und Umsortieren
struct MDCategoriesPage: View {
    @Environment(AppModel.self) private var model
    @Environment(ManageNav.self) private var nav
    @State private var editMode: EditMode = .inactive
    @State private var deleteAsk: KCategory?

    var body: some View {
        let cats = model.data.categories
        let editing = editMode.isEditing
        return List {
            Section {
                ForEach(cats) { c in
                    NavigationLink(value: ManagePage.category(c.id)) {
                        row(c)
                    }
                    .deleteDisabled(c.kind == .other)
                    .mdRow()
                }
                .onMove { src, dst in
                    model.update { $0.moveCategories(fromOffsets: src, toOffset: dst) }
                }
                .onDelete { idx in requestDelete(idx) }
                if !editing {
                    NavigationLink(value: ManagePage.categoryNew) {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(KColor.teal)
                                .frame(width: 36, height: 36)
                                .accessibilityHidden(true)
                            Text("Kategorie hinzufügen").font(.body.weight(.semibold)).foregroundStyle(KColor.teal)
                        }
                    }
                    .mdRow()
                }
            } header: {
                MDSectionHeader(title: Format.count(cats.count, "Kategorie", "Kategorien")) {
                    Button(editing ? "Fertig" : "Bearbeiten") {
                        withAnimation { editMode = editing ? .inactive : .active }
                    }
                }
            } footer: {
                Text(editing ? "Mit ⊖ löschen, mit ≡ ziehen, um die Reihenfolge zu ändern. «Sonstiges» bleibt immer."
                     : "Kategorien gruppieren deine Verträge in der Liste und in den Kosten. Tippe auf eine Kategorie, um Name, Farbe und Symbol zu ändern.")
            }
        }
        .mdListStyle()
        .environment(\.editMode, $editMode)
        .navigationTitle("Kategorien")
        .modifier(MDCategoryDeleteAlert(ask: $deleteAsk, onDelete: deleteEmpty))
    }

    private func row(_ c: KCategory) -> some View {
        let d = model.data
        let cs = d.mdContracts(inCategory: c.id)
        let home = d.settings.homeCurrency.rawValue
        let cost: String = cs.isEmpty ? "" : [" · ", Format.money(d.mdPerMonth(cs, today: model.today)), " ", home, "/Mt."].joined()
        let sub: String = Format.count(cs.count, "Vertrag", "Verträge") + cost
        return HStack(spacing: 12) {
            MarkView(category: c, size: 36)
            MDTitleSub(title: c.name, subtitle: sub)
        }
    }

    private func requestDelete(_ idx: IndexSet) {
        guard let i = idx.first, i < model.data.categories.count else { return }
        let c = model.data.categories[i]
        if c.kind == .other { return }
        if model.data.mdContracts(inCategory: c.id).isEmpty {
            deleteAsk = c
        } else {
            nav.push(.categoryDelete(c.id, fromDetail: false))
        }
    }

    private func deleteEmpty(_ c: KCategory) {
        if model.update({ try $0.deleteCategory(c.id) }) {
            model.mdRenameFilters(categoryFrom: c.name, categoryTo: nil)
            model.toast("Kategorie gelöscht")
        }
    }
}

// MARK: - Detail

/// Kategorie bearbeiten (MD_PAGES.ce): Name, Farbe, Symbol, Verträge, Löschen
struct MDCategoryPage: View {
    let categoryID: UUID
    @Environment(AppModel.self) private var model
    @Environment(ManageNav.self) private var nav
    @State private var name = ""
    @FocusState private var focused: Bool
    @State private var deleteAsk = false

    var body: some View {
        Group {
            if let c = model.data.category(categoryID) {
                page(c)
            } else {
                List { Section { MDHint("Diese Kategorie existiert nicht mehr.").mdPlainRow() } }.mdListStyle()
            }
        }
        .navigationTitle(model.data.category(categoryID)?.name ?? "Kategorie")
    }

    private func content(_ c: KCategory) -> some View {
        let fixed = c.kind == .other
        let cs = model.data.mdContracts(inCategory: c.id)
        return List {
            Section {
                HStack(spacing: 14) {
                    MarkView(category: c, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name").font(.caption).foregroundStyle(KColor.ink2)
                        TextField("Name", text: $name)
                            .font(.title3.weight(.semibold))
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($focused)
                            .onSubmit { commitName() }
                            .onChange(of: name) { _, v in if v.count > 30 { name = mdLimit30(v) } }
                            .disabled(fixed)
                            .accessibilityLabel("Name")
                    }
                }
                .padding(.vertical, 6)
                .mdRow()
            } footer: {
                if fixed {
                    Text("«Sonstiges» fängt alles ohne Kategorie auf und lässt sich weder umbenennen noch löschen.")
                }
            }
            Section {
                MDColorGrid(selected: c.colorHex) { hex in
                    model.update { $0.updateCategory(categoryID, colorHex: hex) }
                }
                .mdRow()
            } header: {
                Text("Farbe")
            }
            Section {
                MDIconGrid(color: c.colorHex, selected: c.icon) { key in
                    model.update { $0.updateCategory(categoryID, icon: key) }
                }
                .mdRow()
            } header: {
                Text("Symbol")
            }
            Section {
                if cs.isEmpty {
                    MDHint("Noch keine Verträge in dieser Kategorie.").mdRow()
                } else {
                    ForEach(cs) { k in
                        MDContractRow(contract: k)
                    }
                }
            } header: {
                Text(Format.count(cs.count, "Vertrag", "Verträge"))
            }
            if !fixed {
                Section {
                    MDActionRow(title: "Kategorie löschen", destructive: true) { deleteTapped() }
                }
            }
        }
        .mdListStyle()
    }

    private func page(_ c: KCategory) -> some View {
        let title: String = "«" + c.name + "» löschen?"
        return content(c)
            .onAppear {
                if !focused { name = c.name }
                nav.flush[.category(categoryID)] = { commitName() }
            }
            .onDisappear {
                commitName()
                nav.flush[.category(categoryID)] = nil
            }
            .onChange(of: focused) { _, f in if !f { commitName() } }
            .onChange(of: model.data.category(categoryID)?.name) { _, n in
                if let n, !focused { name = n }
            }
            .alert(title, isPresented: $deleteAsk) {
                Button("Löschen", role: .destructive) { deleteEmpty() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Die Kategorie ist leer.")
            }
    }

    /// Umbenennen (ceRename): leer → zurück; doppelt → zurück mit Hinweis (kein Zusammenführen)
    private func commitName() {
        guard let c = model.data.category(categoryID), c.kind != .other else { return }
        let n = Format.collapseSpaces(name)
        if n.isEmpty {
            name = c.name
            model.toast("Name darf nicht leer sein")
            return
        }
        if n == c.name { return }
        if model.data.categories.contains(where: { $0.id != categoryID && $0.name.lowercased() == n.lowercased() }) {
            name = c.name
            model.toast("Diese Kategorie gibt es schon")
            return
        }
        let old = c.name
        if model.update({ try $0.renameCategory(categoryID, to: n) }) {
            model.mdRenameFilters(categoryFrom: old, categoryTo: n)
            name = n
            model.toast("Umbenannt")
        } else {
            name = c.name
        }
    }

    private func deleteTapped() {
        commitName()
        if model.data.mdContracts(inCategory: categoryID).isEmpty {
            deleteAsk = true
        } else {
            nav.push(.categoryDelete(categoryID, fromDetail: true))
        }
    }

    private func deleteEmpty() {
        let old = model.data.category(categoryID)?.name ?? ""
        if model.update({ try $0.deleteCategory(categoryID) }) {
            model.mdRenameFilters(categoryFrom: old, categoryTo: nil)
            nav.pop()
            model.toast("Kategorie gelöscht")
        }
    }
}

// MARK: - Neue Kategorie

/// Neue Kategorie (MD_PAGES.cenew)
struct MDCategoryNewPage: View {
    @Environment(AppModel.self) private var model
    @Environment(ManageNav.self) private var nav
    @State private var name = ""
    @State private var color = ""
    @State private var icon = "tag"
    @FocusState private var focused: Bool

    var body: some View {
        let col = color.isEmpty ? KCategory.newColor(existingCount: model.data.categories.count) : color
        return List {
            Section {
                HStack(spacing: 14) {
                    MarkView(logoID: nil, logoBg: nil, colorHex: col, symbol: KIcon.symbol(forKey: icon), size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Name").font(.caption).foregroundStyle(KColor.ink2)
                        TextField("z.B. Haustier", text: $name)
                            .font(.title3.weight(.semibold))
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .focused($focused)
                            .onSubmit { add() }
                            .onChange(of: name) { _, v in if v.count > 30 { name = mdLimit30(v) } }
                            .accessibilityLabel("Name")
                    }
                }
                .padding(.vertical, 6)
                .mdRow()
            }
            Section {
                MDColorGrid(selected: col) { color = $0 }.mdRow()
            } header: {
                Text("Farbe")
            }
            Section {
                MDIconGrid(color: col, selected: icon) { icon = $0 }.mdRow()
            } header: {
                Text("Symbol")
            }
            Section {
                MDMainButton(title: "Hinzufügen") { add() }
            }
        }
        .mdListStyle()
        .navigationTitle("Neue Kategorie")
        .onAppear {
            if color.isEmpty { color = KCategory.newColor(existingCount: model.data.categories.count) }
        }
    }

    private func add() {
        let n = Format.collapseSpaces(name)
        if n.isEmpty {
            model.toast("Bitte einen Namen eingeben")
            return
        }
        if model.data.categories.contains(where: { $0.name.lowercased() == n.lowercased() }) {
            model.toast("Diese Kategorie gibt es schon")
            return
        }
        let col = color.isEmpty ? KCategory.newColor(existingCount: model.data.categories.count) : color
        if model.update({ _ = try $0.addCategory(n, colorHex: col, icon: icon) }) {
            focused = false
            nav.pop()
            model.toast("Kategorie «\(n)» angelegt")
        }
    }
}

// MARK: - Kategorie löschen

/// Kategorie löschen mit Zielkategorie (MD_PAGES.cdel)
struct MDCategoryDeletePage: View {
    let categoryID: UUID
    let fromDetail: Bool
    @Environment(AppModel.self) private var model
    @Environment(ManageNav.self) private var nav
    @State private var to: UUID?
    @State private var initialized = false

    var body: some View {
        Group {
            if let c = model.data.category(categoryID) {
                content(c)
            } else {
                List { Section { MDHint("Diese Kategorie existiert nicht mehr.").mdPlainRow() } }.mdListStyle()
            }
        }
        .navigationTitle("Kategorie löschen")
    }

    private func content(_ c: KCategory) -> some View {
        let n = model.data.mdContracts(inCategory: c.id).count
        let others = model.data.categories.filter { $0.id != categoryID }
        let verb: String = n == 1 ? "ist 1 Vertrag" : "sind \(n) Verträge"
        let text: String = n > 0
            ? ["In «", c.name, "» ", verb, ". In welche Kategorie sollen sie?"].joined()
            : ["«", c.name, "» ist leer und kann gelöscht werden."].joined()
        return List {
            Section { MDHint(text).mdPlainRow() }
            if n > 0 {
                Section {
                    ForEach(others) { o in
                        Button { to = o.id } label: {
                            HStack(spacing: 12) {
                                MarkView(category: o, size: 32)
                                Text(o.name).font(.body.weight(.semibold)).foregroundStyle(KColor.ink)
                                Spacer(minLength: 4)
                                MDRadio(on: to == o.id)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(to == o.id ? .isSelected : [])
                        .mdRow()
                    }
                }
            }
            Section {
                MDMainButton(title: "Kategorie löschen", destructive: true) { delete(c) }
            }
        }
        .mdListStyle()
        .onAppear {
            guard !initialized else { return }
            initialized = true
            if let o = model.data.otherCategory, o.id != categoryID {
                to = o.id
            } else {
                to = others.first?.id
            }
        }
    }

    private func delete(_ c: KCategory) {
        let old = c.name
        if model.update({ try $0.deleteCategory(categoryID, moveTo: to) }) {
            model.mdRenameFilters(categoryFrom: old, categoryTo: nil)
            nav.pop(fromDetail ? 2 : 1)
            model.toast("Kategorie gelöscht")
        }
    }
}
