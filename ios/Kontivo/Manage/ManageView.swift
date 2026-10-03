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

    init(root: ManagePage) { self.root = root }

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

    var body: some View {
        @Bindable var nav = nav
        NavigationStack(path: $nav.path) {
            ManagePageView(page: nav.root)
                .id(nav.root)
                .navigationDestination(for: ManagePage.self) { p in
                    ManagePageView(page: p).id(p)
                }
        }
        .environment(nav)
        .onAppear { nav.close = { dismiss() } }
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
                    Button("Fertig") { nav.close() }
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
