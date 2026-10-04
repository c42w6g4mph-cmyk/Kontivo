import SwiftUI
import KontivoCore

// MARK: - Seiten

/// Seiten im Fenster «Verwalten» (Web: md.stack mit partner, pe, pmerge, holder, he, hs, henew, hdel, hassign, hbulk,
/// cat, ce, cenew, cdel, qual, qlist und der Ergebnisseite der Sammelsuche).
enum ManagePage: Hashable {
    case overview
    case partners
    case partner(UUID)
    case partnerMerge(UUID)
    case persons
    case person(UUID)
    case personNew
    case personDelete(UUID)
    case sender(UUID)
    case assign(MDAssignFilter)
    case transfer
    case categories
    case category(UUID)
    case categoryNew
    case categoryDelete(UUID, fromDetail: Bool)
    case quality
    case qualityList(QualityGroup, String, String)
    case logoBatch

    init(route: ManageRoute) {
        switch route {
        case .overview: self = .overview
        case .partners: self = .partners
        case .partner(let u): self = .partner(u)
        case .persons: self = .persons
        case .person(let u): self = .person(u)
        case .sender(let u): self = .sender(u)
        case .assign(let u): self = .assign(u.map { MDAssignFilter.person($0) } ?? .all)
        case .categories: self = .categories
        case .quality: self = .quality
        }
    }
}

/// Filter der Seite «Verträge zuordnen»
enum MDAssignFilter: Hashable {
    case all
    case person(UUID)
    case unassigned
}

// MARK: - Navigation

/// Navigationsstapel des Fensters (Wurzel + Pfad). `swap` ersetzt oberste Seiten, auch die Wurzel.
@MainActor
@Observable
final class ManageNav {
    var root: ManagePage
    var path: [ManagePage] = []
    /// Suchtext der Vertragspartner-Liste (bleibt erhalten, solange das Fenster offen ist)
    var partnerQuery = ""
    /// Schliesst das ganze Fenster
    @ObservationIgnored var close: () -> Void = {}
    /// Rückfrage «X gibt es schon» auf Fenster-Ebene: überlebt «Zurück»/«Fertig» (Web mdFlush, Fix N8)
    var renameAsk: MDRenameAsk?
    /// Nach der Rückfrage das Fenster schliessen («Fertig» mit offenem Namenskonflikt)
    @ObservationIgnored var closeAfterAsk = false
    /// Offene Eingaben der sichtbaren Seite sichern (vor «Fertig» und beim Wechsel in den Hintergrund)
    @ObservationIgnored var flush: [ManagePage: () -> Void] = [:]

    init(root: ManagePage) { self.root = root }

    /// «Fertig»: zuerst offene Eingaben sichern; steht eine Rückfrage an, erst danach schliessen
    func requestClose() {
        for f in flush.values { f() }
        if renameAsk != nil { closeAfterAsk = true } else { close() }
    }

    /// Rückfrage stellen (nur eine gleichzeitig)
    func ask(_ a: MDRenameAsk) {
        if renameAsk == nil { renameAsk = a }
    }

    /// Seiten einer Quelle im Stapel durch die Zielseite ersetzen (nach dem Zusammenführen)
    func replace(_ from: ManagePage, with to: ManagePage) {
        if root == from { root = to }
        path = path.map { $0 == from ? to : $0 }
    }

    func push(_ p: ManagePage) { path.append(p) }

    /// n Seiten zurück; reicht der Stapel nicht, schliesst das Fenster (wie mdPop)
    func pop(_ n: Int = 1) {
        if path.count >= n { path.removeLast(n) } else { close() }
    }

    /// Oberste n Seiten durch p ersetzen (wie mdSwap)
    func swap(_ p: ManagePage, n: Int = 1) {
        var full = [root] + path
        full.removeLast(Swift.min(n, full.count))
        full.append(p)
        root = full[0]
        path = Array(full.dropFirst())
    }
}

// MARK: - Fenster

/// Fenster «Verwalten» mit eigener Navigation (NavigationStack), Einstieg je nach Route.
struct ManageView: View {
    let start: ManageRoute
    @Environment(\.dismiss) private var dismiss
    @State private var nav: ManageNav

    init(start: ManageRoute) {
        self.start = start
        _nav = State(initialValue: ManageNav(root: ManagePage(route: start)))
    }

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var nav = nav
        let showAsk = Binding<Bool>(get: { nav.renameAsk != nil }, set: { if !$0 { nav.renameAsk = nil } })
        NavigationStack(path: $nav.path) {
            ManagePageView(page: nav.root)
                .id(nav.root)
                .navigationDestination(for: ManagePage.self) { p in
                    ManagePageView(page: p).id(p)
                }
        }
        .environment(nav)
        .onAppear { nav.close = { dismiss() } }
        // Eingaben sichern, bevor iOS die App im Hintergrund beenden kann
        .onChange(of: scenePhase) { _, ph in
            if ph == .background {
                for f in nav.flush.values { f() }
                model.saveNow()
            }
        }
        .alert(nav.renameAsk?.title ?? "", isPresented: showAsk, presenting: nav.renameAsk) { a in
            Button("Zusammenführen") { merge(a) }
            Button("Abbrechen", role: .cancel) { finishAsk() }
        } message: { a in
            Text(a.message)
        }
    }

    private func finishAsk() {
        nav.renameAsk = nil
        if nav.closeAfterAsk {
            nav.closeAfterAsk = false
            nav.close()
        }
    }

    private func merge(_ a: MDRenameAsk) {
        switch a.kind {
        case .partner:
            if model.data.partner(a.sourceID) != nil, model.data.partner(a.otherID) != nil {
                model.update { _ = $0.mergePartners([a.sourceID], into: a.otherID) }
                model.mdRenameFilters(partnerFrom: a.oldName, partnerTo: a.otherName)
                nav.replace(.partner(a.sourceID), with: .partner(a.otherID))
                model.toast("Zusammengeführt mit «\(a.otherName)»")
            }
        case .person:
            if model.data.person(a.sourceID) != nil, model.data.person(a.otherID) != nil {
                model.update { $0.mergePerson(a.sourceID, into: a.otherID) }
                model.mdMovePersonFilters(from: a.sourceID, to: a.otherID)
                nav.replace(.person(a.sourceID), with: .person(a.otherID))
                nav.replace(.sender(a.sourceID), with: .sender(a.otherID))
                model.toast("Zusammengeführt mit «\(a.otherName)»")
            }
        }
        finishAsk()
    }
}

/// Rückfrage beim Umbenennen auf einen bestehenden Namen (Vertragspartner: peRename, Inhaber: heRename)
struct MDRenameAsk: Identifiable {
    enum Kind { case partner, person }
    let id = UUID()
    let kind: Kind
    let sourceID: UUID
    let otherID: UUID
    let otherName: String
    let oldName: String
    /// Anzahl Verträge des Vertragspartners (nur Vertragspartner)
    var count = 0

    var title: String { "«" + otherName + "» gibt es schon" }

    var message: String {
        switch kind {
        case .partner:
            return [Format.count(count, "Vertrag wird", "Verträge werden"), " mit «", otherName, "» zusammengeführt."].joined()
        case .person:
            return ["Alle Einträge von «", oldName, "» gehen an «", otherName, "», «", oldName, "» wird entfernt."].joined()
        }
    }
}

/// Inhalt einer Seite mit Kopfzeile («Fertig» rechts; links der Zurück-Knopf der Navigation)
struct ManagePageView: View {
    let page: ManagePage
    @Environment(ManageNav.self) private var nav

    var body: some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { nav.requestClose() }
                        .fontWeight(.semibold)
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .overview: MDOverviewPage()
        case .partners: MDPartnersPage()
        case .partner(let id): MDPartnerPage(partnerID: id)
        case .partnerMerge(let id): MDPartnerMergePage(sourceID: id)
        case .persons: MDPersonsPage()
        case .person(let id): MDPersonPage(personID: id)
        case .personNew: MDPersonNewPage()
        case .personDelete(let id): MDPersonDeletePage(personID: id)
        case .sender(let id): MDSenderPage(personID: id)
        case .assign(let f): MDAssignPage(initialFilter: f)
        case .transfer: MDTransferPage()
        case .categories: MDCategoriesPage()
        case .category(let id): MDCategoryPage(categoryID: id)
        case .categoryNew: MDCategoryNewPage()
        case .categoryDelete(let id, let fromDetail): MDCategoryDeletePage(categoryID: id, fromDetail: fromDetail)
        case .quality: MDQualityPage()
        case .qualityList(let g, let f, let t): MDQualityListPage(group: g, field: f, title: t)
        case .logoBatch: MDLogoBatchPage()
        }
    }
}

// MARK: - Übersicht

/// Übersicht «Verwalten» (wie der Abschnitt «Verwalten» in «Mehr», paintMdSummary)
struct MDOverviewPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                partnersRow
                personsRow
                categoriesRow
                qualityRow
            }
        }
        .mdListStyle()
        .navigationTitle("Verwalten")
    }

    private var partnersRow: some View {
        let groups = Partners.groups(model.data, today: model.today)
        let d = groups.filter { $0.isDuplicate }.count
        let right = d > 0 ? Format.count(d, "Dublette", "Dubletten") : (groups.isEmpty ? "–" : "\(groups.count)")
        return NavigationLink(value: ManagePage.partners) {
            MDOverviewRow(title: "Vertragspartner", subtitle: "Namen, Logos und Adressen deiner Anbieter",
                          trailing: right, color: d > 0 ? KColor.warn : KColor.ink2, bold: d > 0)
        }
        .mdRow()
    }

    private var personsRow: some View {
        let names = model.data.persons.map { $0.name }
        let right = names.count <= 2 ? names.joined(separator: ", ") : "\(names.count) Personen"
        return NavigationLink(value: ManagePage.persons) {
            MDOverviewRow(title: "Inhaber", subtitle: "Personen, Absender und Unterschrift", trailing: right, color: KColor.ink2, bold: false)
        }
        .mdRow()
    }

    private var categoriesRow: some View {
        NavigationLink(value: ManagePage.categories) {
            MDOverviewRow(title: "Kategorien", subtitle: "Gruppen für deine Verträge: Name, Farbe, Reihenfolge",
                          trailing: "\(model.data.categories.count)", color: KColor.ink2, bold: false)
        }
        .mdRow()
    }

    private var qualityRow: some View {
        let r = model.mdQualityReport
        let has = r.contractCount > 0
        let open = r.affectedCount
        let color: Color = !has ? KColor.ink2 : (open > 0 ? KColor.warn : KColor.ok)
        let sub = has && open == 0 ? "Alles da, nichts fehlt. Gut gemacht." : "Was bei deinen Verträgen noch fehlt"
        return NavigationLink(value: ManagePage.quality) {
            MDOverviewRow(title: "Datenqualität", subtitle: sub, trailing: Quality.summary(r), color: color, bold: has)
        }
        .mdRow()
    }
}

/// Zeile der Übersicht: Titel, Untertitel, rechts eine Angabe
private struct MDOverviewRow: View {
    let title: String
    let subtitle: String
    let trailing: String
    let color: Color
    let bold: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(KColor.ink)
                Text(subtitle).font(.footnote).foregroundStyle(KColor.ink2)
            }
            Spacer(minLength: 8)
            Text(trailing)
                .font(.subheadline.weight(bold ? .semibold : .regular))
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
