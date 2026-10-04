import SwiftUI
import KontivoCore

/// Zustand der Sammelsuche «Alle suchen» (qsr der Web-App)
@MainActor
@Observable
final class MDLogoBatchState {
    struct Item: Identifiable {
        let id: UUID
        let name: String
        let cand: LogoCandidate
        let sure: Bool
        var on: Bool
    }

    var items: [Item] = []
    var miss: [String] = []
    var busy = false
    var started = false
    var finished = false
    var progress = 0
    var total = 0

    /// Suche je Vertragspartner ohne Logo (qSearch/qFindOne): bester Vorschlag, «sicher» ab 3 Punkten (vorausgewählt)
    func run(_ model: AppModel) async {
        guard !started else { return }
        started = true
        busy = true
        let issues = model.mdQualityReport.C.filter { $0.criterion == .logo }
        total = issues.count
        for (i, iss) in issues.enumerated() {
            if Task.isCancelled { break }
            progress = i + 1
            guard case .partner(let pid) = iss.subject, let p = model.data.partner(pid) else { continue }
            let r = await LogoFinder.allCandidates(name: p.name, currency: model.mdCurrency(partner: pid), alt: nil, web: p.web, manual: false)
            if let best = r.cands.first {
                items.append(Item(id: pid, name: p.name, cand: best, sure: best.score >= 3, on: best.score >= 3))
            } else {
                miss.append(p.name)
            }
        }
        busy = false
        finished = true
    }

    /// Gewählte Vorschläge übernehmen (qApply); zählt Vertragspartner (Fix N11)
    func apply(_ model: AppModel) async -> Int {
        let sel = items.filter { $0.on }
        guard !sel.isEmpty, !busy else { return 0 }
        busy = true
        var n = 0
        for (i, x) in sel.enumerated() {
            model.toast("Übernehme \(i + 1)/\(sel.count) …", seconds: 30)
            guard let p = model.data.partner(x.id) else { continue }
            let has = (p.logoID.map { !$0.isEmpty } ?? false) && model.files.has(p.logoID)
            if has { continue }
            if case .success(let img) = await LogoFinder.take(x.cand), model.mdSetPartnerLogo(x.id, png: img.png, bg: img.background) {
                n += 1
            }
        }
        busy = false
        return n
    }
}

/// Seite der Sammelsuche: «Suche läuft …», danach «Vorschläge» bzw. «Keine Treffer»
struct MDLogoBatchPage: View {
    @Environment(AppModel.self) private var model
    @Environment(ManageNav.self) private var nav
    @State private var state = MDLogoBatchState()
    @State private var logoTarget: MDLogoTarget?

    var body: some View {
        List {
            if !state.finished {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(state.progress == 0 ? "Suche 0/\(state.total)" : "Suche \(state.progress)/\(state.total) …")
                            .font(.subheadline)
                            .foregroundStyle(KColor.ink2)
                            .monospacedDigit()
                    }
                    .mdPlainRow()
                }
            } else {
                results
            }
        }
        .mdListStyle()
        .navigationTitle(!state.finished ? "Suche läuft …" : (state.items.isEmpty ? "Keine Treffer" : "Vorschläge"))
        .task { await state.run(model) }
        .modifier(MDLogoSheet(target: $logoTarget) { pid in
            state.items.removeAll { $0.id == pid }
        })
    }

    @ViewBuilder private var results: some View {
        if !state.items.isEmpty {
            Section {
                MDHint("Tippe auf einen Eintrag, um ihn an- oder abzuwählen. Unsichere Treffer sind nicht vorausgewählt. «Andere …» zeigt alle Vorschläge wie im Vertrag.")
                    .mdPlainRow()
            }
            Section {
                ForEach(state.items) { x in
                    row(x)
                }
            }
            Section {
                let n = state.items.filter { $0.on }.count
                MDMainButton(title: n > 0 ? (n == 1 ? "1 Vorschlag übernehmen" : "\(n) Vorschläge übernehmen") : "Nichts ausgewählt",
                             disabled: n == 0 || state.busy) {
                    Task { @MainActor in
                        let done = await state.apply(model)
                        // Nur schliessen, wenn die Ergebnisseite noch oben liegt (Zurück während der Übernahme, Web closeMe)
                        if nav.path.last == .logoBatch { nav.pop() }
                        model.toast(done == 1 ? "1 Logo übernommen" : "\(done) Logos übernommen")
                    }
                }
            }
        }
        if !state.miss.isEmpty {
            Section {
                MDHint("Nichts gefunden: " + state.miss.joined(separator: ", ") + ". Diese über die Vertragspartner-Pflege oder «Logo automatisch finden» im Vertrag ergänzen.")
                    .mdPlainRow()
            }
        }
        if state.items.isEmpty && state.miss.isEmpty {
            Section { MDHint("Kein Ergebnis.").mdPlainRow() }
        }
    }

    private func row(_ x: MDLogoBatchState.Item) -> some View {
        HStack(spacing: 10) {
            Button {
                if let i = state.items.firstIndex(where: { $0.id == x.id }) { state.items[i].on.toggle() }
            } label: {
                HStack(spacing: 12) {
                    MDRadio(on: x.on)
                    MDTitleSub(title: x.name, subtitle: (x.sure ? "Guter Treffer" : "Unsicher") + " · " + x.cand.src.label)
                    Spacer(minLength: 4)
                    AsyncImage(url: URL(string: x.cand.thumb)) { ph in
                        if let img = ph.image {
                            img.resizable().interpolation(.high).scaledToFit()
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(x.on ? .isSelected : [])
            Button("Andere …") {
                logoTarget = model.mdLogoTarget(partner: x.id)
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        }
        .mdRow()
    }
}
