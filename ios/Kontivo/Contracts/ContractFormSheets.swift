import SwiftUI
import KontivoCore

/// Auswahl «Kategorie» mit eigener Kategorie (openCatPick("c"), addCustomCat). Eine neue Kategorie wird sofort gespeichert.
struct CTCategoryPickSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: UUID?
    @State private var newName = ""

    init(selected: Binding<UUID?>) {
        _selected = selected
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.data.categories) { cat in
                        Button {
                            selected = cat.id
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                MarkView(category: cat, size: 30)
                                Text(cat.name).foregroundStyle(KColor.ink)
                                Spacer()
                                if selected == cat.id {
                                    Image(systemName: "checkmark").foregroundStyle(KColor.teal)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityAddTraits(selected == cat.id ? .isSelected : [])
                    }
                }
                .listRowBackground(KColor.surface)
                Section {
                    HStack(spacing: 10) {
                        TextField("Eigene Kategorie, z.B. Haustier", text: $newName)
                            .submitLabel(.done)
                            .onSubmit(add)
                            .onChange(of: newName) { _, v in
                                if v.count > 30 { newName = String(v.prefix(30)) }
                            }
                        Button("Hinzufügen", action: add)
                            .buttonStyle(.borderless)
                            .fontWeight(.semibold)
                            .disabled(Format.collapseSpaces(newName).isEmpty)
                    }
                }
                .listRowBackground(KColor.surface)
            }
            .scrollContentBackground(.hidden)
            .background(KColor.paper)
            .navigationTitle("Kategorie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    private func add() {
        let n = String(Format.collapseSpaces(newName).prefix(30))
        if n.isEmpty { return }
        if let ex = model.data.categories.first(where: { $0.name.lowercased() == n.lowercased() }) {
            selected = ex.id
            model.toast("Kategorie gewählt")
            dismiss()
            return
        }
        var newID: UUID?
        let ok = model.update { d in
            newID = try d.addCategory(n)
        }
        if ok, let id = newID {
            selected = id
            model.toast("Kategorie «" + n + "» angelegt")
            dismiss()
        }
    }
}

/// Bleibt bis zum Beenden der App erhalten (tplCC der Web-App)
@MainActor
enum CTCatalogMemory {
    static var country = ""
}

/// «Anbieter-Katalog»: Suche, Land Alle/CH/DE, Übernahme der Vorlage per Tipp (openTplPick).
struct CTCatalogSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onPick: (CatalogEntry) -> Void
    @State private var query = ""
    @State private var country = CTCatalogMemory.country

    init(onPick: @escaping (CatalogEntry) -> Void) {
        self.onPick = onPick
    }

    var body: some View {
        let list = Catalog.search(query, country: country)
        NavigationStack {
            List {
                Section {
                    Picker("Land", selection: $country) {
                        Text("Alle").tag("")
                        Text("CH").tag("CH")
                        Text("DE").tag("DE")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    if list.isEmpty {
                        Text("Kein Anbieter gefunden. Du kannst ihn einfach selbst eintippen.")
                            .font(.subheadline)
                            .foregroundStyle(KColor.ink2)
                    }
                    ForEach(list) { t in
                        Button {
                            onPick(t)
                            dismiss()
                        } label: {
                            row(t)
                        }
                    }
                } footer: {
                    Text("Fristen sind typische Werte. Massgebend ist immer dein Vertrag.")
                }
                .listRowBackground(KColor.surface)
            }
            .scrollContentBackground(.hidden)
            .background(KColor.paper)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Anbieter suchen")
            .navigationTitle("Anbieter-Katalog")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .onChange(of: country) { _, v in CTCatalogMemory.country = v }
        }
    }

    private func row(_ t: CatalogEntry) -> some View {
        let color = model.data.category(named: t.category)?.colorHex ?? KCategory.standardColors[t.category] ?? KCategory.fallbackColor
        return HStack(spacing: 12) {
            MarkView(logoID: nil, logoBg: nil, colorHex: color, symbol: KIcon.symbol(forKey: t.category.isEmpty ? "Sonstiges" : t.category), size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.name).foregroundStyle(KColor.ink)
                if !t.label.isEmpty {
                    Text(t.label).font(.footnote).foregroundStyle(KColor.ink2)
                }
            }
            Spacer(minLength: 8)
            Text(t.flag)
                .font(.caption.weight(.semibold))
                .foregroundStyle(KColor.ink2)
        }
        .contentShape(Rectangle())
    }
}
