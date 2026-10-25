import SwiftUI
import KontivoCore

// Gemeinsame Bausteine der Listen im Verträge-Tab (Verträge, Einnahmen, Variabel): Reiter, Suche mit Filter/Sortierung,
// Filter-Etiketten, Gruppenkopf, Archiv-Knopf, Leertext.

// MARK: - Reiter «Verträge · Einnahmen · Variabel» (Web v231/v232 `.lmseg`)

/// Reiter mit Messing-Unterstrich und Trennlinie: 16 px, gewählt Tinte 650 mit 2.5 Unterstrich, Abstand 22 (Web `.lmseg`,
/// margin 22 0 4). Wechsel leert die Suche (Web `state.q = ""`).
struct CTModeTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 22) {
            ForEach(ListMode.allCases, id: \.self) { m in
                let on = model.listMode == m
                Button {
                    guard model.listMode != m else { return }
                    model.searchText = ""
                    model.listMode = m
                } label: {
                    Text(verbatim: m.title)
                        .font(.system(size: 16, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? KColor.ink : KColor.ink2)
                        .padding(.top, 10).padding(.bottom, 11)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(on ? KColor.brass : .clear).frame(height: 2.5)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
                .accessibilityIdentifier("listMode." + m.rawValue)
            }
            Spacer(minLength: 0)
        }
        .background(alignment: .bottom) { Rectangle().fill(KColor.line).frame(height: 1) }
        .padding(.top, 22)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ansicht")
    }
}

/// Zustand der Ansichten Einnahmen/Variabel je Ansicht (Web `state.fltA`, `state.heroFA`, `state.showArchI/V`)
struct CTAltState {
    var filters: [ListMode: AltFilter] = [:]
    var status: [ListMode: AltStatus] = [:]
    var archiveOpen: Set<ListMode> = []

    func filter(_ m: ListMode) -> AltFilter { filters[m] ?? AltFilter() }
}

// MARK: - Suche, Filter- und Sortierknopf (Web `.searchrow`: 38 hoch, Abstand 6, Knöpfe nur Symbol 42 × 38)

struct CTListControls: View {
    @Environment(AppModel.self) private var model
    @Binding var showFilter: Bool
    @FocusState private var focused: Bool
    @State private var showSort = false

    var body: some View {
        @Bindable var model = model
        let mode = model.listMode
        let n = mode == .contracts ? model.costFilter.count : model.alt.filter(mode).count(mode)
        let sortLabel = mode == .contracts ? model.data.settings.sort.shortLabel : model.calc.altSort(mode).shortLabel(mode)
        let searchLabel = mode == .incomes ? "Einnahmen durchsuchen" : (mode == .variable ? "Variable Kosten durchsuchen" : "Verträge durchsuchen")
        HStack(alignment: .top, spacing: 6) {
            // Suchfeld: 42 hoch mit Rahmen (ragt 4 pt unter die Knöpfe, wie im Web), Radius 12
            HStack(spacing: 0) {
                CTIcon.search(17)
                    .foregroundStyle(KColor.ink3)
                    .padding(.leading, 12)
                    .padding(.trailing, 7)
                TextField("", text: $model.searchText, prompt: Text("Suchen").foregroundColor(KColor.ink3))
                    .font(.system(size: 16))
                    .foregroundStyle(KColor.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($focused)
                    .accessibilityLabel(Text(verbatim: searchLabel))
                    .accessibilityIdentifier("contracts.search")
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(KColor.ink3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Suche löschen")
                    .padding(.leading, 6)
                }
                Spacer(minLength: 12)
            }
            .frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(focused ? KColor.ink2 : KColor.line, lineWidth: 1))
            .frame(height: 38, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            Button {
                showFilter = true
            } label: {
                // Web: aktiver Filter färbt den Knopf (Symbol weiss auf Fläche); hier Symbol in Messing, damit es sichtbar bleibt
                CTIcon.filter(16)
                    .foregroundStyle(n > 0 ? KColor.teal : KColor.ink2)
                    .frame(width: 42, height: 38)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.surface))
                    .overlay(alignment: .topTrailing) {
                        if n > 0 {
                            Circle().fill(KColor.brassFab).frame(width: 7, height: 7).offset(x: -8, y: 8)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filter" + (n > 0 ? ", \(n) aktiv" : ""))
            .accessibilityIdentifier("contracts.filter")

            // Web: Auswahlblatt «Sortieren nach» (openPick("sort") bzw. openAltPick(m, "sort"))
            Button {
                showSort = true
            } label: {
                CTIcon.sort(16)
                    .foregroundStyle(KColor.ink2)
                    .frame(width: 42, height: 38)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.surface))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sortierung ändern, sortiert nach " + sortLabel)
            .accessibilityIdentifier("contracts.sort")
        }
        .frame(height: 38, alignment: .top)
        .padding(.top, 14)
        .sheet(isPresented: $showSort) {
            Group {
                if mode == .contracts {
                    CTSortSheet()
                } else {
                    AltSortSheet(mode: mode)
                }
            }
            .environment(model)
        }
    }
}

// MARK: - Aktive Filter (Web `.ftag`: 12.5/600, Innenabstand 6 8 6 12, Messing 12 %)

struct CTFilterTagBar: View {
    let tags: [CTFilterTag]
    let remove: (CTFilterTag) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags) { t in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { remove(t) }
                    } label: {
                        HStack(spacing: 6) {
                            // Web max-width 170 (inkl. Innenabstand und ×)
                            Text(t.text).lineLimit(1).truncationMode(.tail)
                                .font(.system(size: 12.5, weight: .semibold))
                                .frame(maxWidth: 170 - 20 - 16, alignment: .leading)
                            Text("×").font(.system(size: 16, weight: .semibold))
                        }
                        .ctLine(18.1)
                        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 6)
                        .foregroundStyle(KColor.teal)
                        .background(Capsule().fill(KColor.teal.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t.kind == .hero ? "Filter entfernen" : "Filter \(t.text) entfernen")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }
}

// MARK: - Gruppenkopf (Web `.grphead`: 12 px, Titel 600 Tinte, Summe Tinte 2; ohne Titel nur Abstand)

struct CTGroupHeader: View {
    let title: String?
    let sum: String?

    var body: some View {
        if let title {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(KColor.ink)
                Spacer(minLength: 8)
                if let s = sum, !s.isEmpty {
                    Text(s)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(KColor.ink2)
                }
            }
            .ctLine(17.4)
            .padding(.bottom, 6)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        } else {
            Color.clear.frame(height: 0)
        }
    }
}

// MARK: - Archiv-Knopf (Web `.archtoggle`)

struct CTArchiveToggle: View {
    /// «3 beendete Verträge», «1 beendete Einnahme», «2 beendet»
    let text: String
    let open: Bool

    var body: some View {
        HStack(alignment: .center) {
            Text("Archiv")
                .font(.system(size: 14))
                .foregroundStyle(KColor.ink)
                .ctLine(20.3)
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                Text(verbatim: text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(KColor.ink2)
                CTChevron(up: open)
                    .stroke(KColor.ink3, style: StrokeStyle(lineWidth: 1.6, lineCap: .square))
                    .frame(width: 9.9, height: 4.95)
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(KColor.line, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Leertext (Web `.empty`: 46 6, 14 px, Titel 16/600)

struct CTEmptyText: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: title).font(.system(size: 16, weight: .semibold)).foregroundStyle(KColor.ink)
            Text(verbatim: text).font(.system(size: 14)).foregroundStyle(KColor.ink2).lineSpacing(5.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 46).padding(.horizontal, 6)
    }
}
