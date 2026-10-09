import SwiftUI
import KontivoCore

// MARK: - Vollständigkeit (Web openVk/paintVk/vkNext, v120–v134)
//
// Ein zentraler Ablauf: Start (Ring, «Los geht’s · ca. n Minuten»), 1 Logos (Raster mit Austausch/Suche/«Ohne Logo»),
// 2 Fristen (eine Frage pro Vertrag mit Katalog-Vorschlag), 3 Absender (pro Person), Abschluss.
// Öffnen: `model.present(.manage(.completeness(only: nil)))` (alle) bzw. `only: vertragsID` (Hinweis im Vertragsdetail).
// Regeln und Texte: KontivoCore/Completeness.swift.

/// Kachel eines Vertragspartners im Logo-Schritt (Web `vk.logos[i]`)
struct CFLogoTile: Identifiable {
    enum LoadState { case load, ok, none, skip }
    let id: UUID
    let name: String
    let currency: Currency
    let web: String
    var state: LoadState = .load
    var cands: [LogoCandidate] = []
    var sel = 0
    var on = false
    /// Eigener Suchbegriff (Selbst suchen)
    var query: String

    var current: LogoCandidate? { state == .ok && sel < cands.count ? cands[sel] : nil }
}

@MainActor
@Observable
final class CompletenessFlowState {
    enum Step: Equatable { case start, logo, term, sender, end }

    let only: UUID?
    var step: Step = .start
    /// Katalog-Ergänzungen (beim Start bestätigt)
    var auto: [CatalogFillItem] = []
    var logos: [CFLogoTile] = []
    /// Logo-Kachel in Bearbeitung (Auswahl, Suche, «Ohne Logo»)
    var pick: Int?
    var terms: [UUID] = []
    var ti = 0
    var senders: [UUID] = []
    var si = 0
    var draft = CompletenessTermDraft()
    /// Logos beim Öffnen (zählt als eine Frage, auch wenn später alle erledigt sind)
    var initialLogoCount = 0
    var offline = false
    /// Übernahme läuft (Schliessen gesperrt)
    var busy = false
    var applyText: String?
    var searching = false
    var closed = false
    @ObservationIgnored var didSetup = false
    @ObservationIgnored var searchTask: Task<Void, Never>?

    init(only: UUID?) { self.only = only }

    /// Anzahl Fragen (`vkQCount`)
    var questionCount: Int { (logos.isEmpty && initialLogoCount == 0 ? 0 : 1) + terms.count + senders.count }

    func report(_ model: AppModel) -> CompletenessReport {
        let f = model.files
        return Completeness.report(model.data, today: model.today, only: only, hasFile: { f.has($0) })
    }

    /// Öffnen (Web `openVk`): einzelner Vertrag startet direkt mit der ersten Frage
    func setup(_ model: AppModel) {
        if didSetup { return }
        didSetup = true
        let n = report(model)
        initialLogoCount = n.logoPartners.count
        terms = n.termContracts
        senders = n.senderPersons
        if only != nil {
            auto = []
            next(from: .start, model)
        } else {
            auto = Completeness.autoPlan(model.data, today: model.today)
            if n.total > 0 && n.questionCount == 0 && auto.isEmpty { step = .end }
        }
    }

    /// Weiter (Web `vkNext`)
    func next(from: Step, _ model: AppModel) {
        var from = from
        if from == .start {
            if only == nil && !auto.isEmpty {
                let plan = auto
                model.update { $0.applyCompletenessAuto(plan) }
                auto = []
            }
            let n = report(model)
            terms = n.termContracts
            senders = n.senderPersons
            if !n.logoPartners.isEmpty {
                step = .logo
                pick = nil
                logos = n.logoPartners.compactMap { pid in
                    guard let p = model.data.partner(pid) else { return nil }
                    return CFLogoTile(id: pid, name: p.name, currency: model.mdCurrency(partner: pid), web: p.web, query: p.name)
                }
                startSearch(model)
                return
            }
            from = .logo
        }
        if from == .logo {
            if !terms.isEmpty {
                step = .term
                ti = 0
                initTerm(model)
                return
            }
            from = .term
        }
        if from == .term {
            if step == .term && ti < terms.count - 1 {
                ti += 1
                initTerm(model)
                return
            }
            if !senders.isEmpty {
                step = .sender
                si = 0
                return
            }
            from = .sender
        }
        if from == .sender && step == .sender && si < senders.count - 1 {
            si += 1
            return
        }
        step = .end
    }

    /// Zurück (Web `vkBack`)
    func back(_ model: AppModel) {
        if step == .logo && pick != nil { pick = nil; return }
        if step == .term && ti > 0 { ti -= 1; initTerm(model); return }
        if step == .sender && si > 0 { si -= 1; return }
        if step == .sender && !terms.isEmpty { step = .term; ti = terms.count - 1; initTerm(model); return }
        if (step == .sender || step == .term) && !logos.isEmpty { step = .logo; pick = nil; return }
        if only == nil { step = .start }
    }

    var backVisible: Bool {
        switch step {
        case .start, .end: return false
        case .logo: return only == nil || pick != nil
        case .term, .sender: return true
        }
    }

    // MARK: Fristen

    func initTerm(_ model: AppModel) {
        guard ti < terms.count, let c = model.data.contract(terms[ti]) else { return }
        draft = Completeness.termDraft(c, data: model.data)
    }

    // MARK: Logos

    func startSearch(_ model: AppModel) {
        searchTask?.cancel()
        let items = logos.map { (name: $0.name, cur: $0.currency, web: $0.web) }
        if model.uiTestMode {
            // UI-Tests: ohne Netz, sofort «nichts gefunden»
            for i in logos.indices { logos[i].state = .none }
            return
        }
        searchTask = Task { @MainActor [weak self] in
            if !(await NetCheck.isOnline()) {
                guard let self else { return }
                self.offline = true
                for i in self.logos.indices { self.logos[i].state = .none }
                return
            }
            // bis zu 4 Suchen gleichzeitig (Web vkFindLogos)
            await withTaskGroup(of: (Int, [LogoCandidate]).self) { group in
                var nextIndex = 0
                let limit = Swift.min(4, items.count)
                while nextIndex < limit {
                    let i = nextIndex, it = items[i]
                    group.addTask { (i, await LogoFinder.allCandidates(name: it.name, currency: it.cur, alt: nil, web: it.web, manual: false).cands) }
                    nextIndex += 1
                }
                while let r = await group.next() {
                    if Task.isCancelled { break }
                    let (i, cands) = r
                    await self?.found(i, cands)
                    if nextIndex < items.count {
                        let j = nextIndex, it = items[j]
                        group.addTask { (j, await LogoFinder.allCandidates(name: it.name, currency: it.cur, alt: nil, web: it.web, manual: false).cands) }
                        nextIndex += 1
                    }
                }
            }
        }
    }

    private func found(_ i: Int, _ cands: [LogoCandidate]) {
        guard i < logos.count, logos[i].state == .load else { return }
        logos[i].cands = cands
        logos[i].sel = 0
        logos[i].state = cands.isEmpty ? .none : .ok
        logos[i].on = !cands.isEmpty && cands[0].score >= 3
    }

    var loading: Bool { logos.contains { $0.state == .load } }
    var selectedCount: Int { logos.filter { $0.state == .ok && $0.on }.count }

    /// «Selbst suchen» in der Kachel (manuelle Suche wie im Vertrag)
    func manualSearch(_ model: AppModel) async {
        guard let k = pick, k < logos.count else { return }
        let q = logos[k].query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return }
        if !(await NetCheck.isOnline()) {
            model.toast("Keine Internetverbindung")
            return
        }
        searching = true
        let cs = await LogoFinder.allCandidates(name: q, currency: logos[k].currency, alt: nil, web: "", manual: true).cands
        searching = false
        guard pick == k, k < logos.count else { return }
        if cs.isEmpty {
            model.toast("Nichts gefunden")
        } else {
            logos[k].cands = cs
            logos[k].sel = 0
        }
    }

    func choose(_ c: Int) {
        guard let k = pick, k < logos.count else { return }
        logos[k].sel = c
        logos[k].state = .ok
        logos[k].on = true
        pick = nil
    }

    func skipLogo(_ model: AppModel) {
        guard let k = pick, k < logos.count else { return }
        let pid = logos[k].id
        model.update { $0.skipLogo(partner: pid) }
        logos[k].state = .skip
        logos[k].on = false
        pick = nil
    }

    /// Gewählte Logos übernehmen (Web `vkLogoApply`): gilt für den Vertragspartner, nur ohne vorhandenes Logo
    func applyLogos(_ model: AppModel) async {
        let sel = logos.indices.filter { logos[$0].state == .ok && logos[$0].on }
        if sel.isEmpty {
            next(from: .logo, model)
            return
        }
        busy = true
        for (n, i) in sel.enumerated() {
            applyText = "Übernehme \(n + 1)/\(sel.count) …"
            let t = logos[i]
            guard let cand = t.current, let p = model.data.partner(t.id) else { continue }
            if let lid = p.logoID, !lid.isEmpty, model.files.has(lid) { continue }
            if case .success(let img) = await LogoFinder.take(cand) {
                model.mdSetPartnerLogo(t.id, png: img.png, bg: img.background)
            }
        }
        busy = false
        applyText = nil
        if closed { return }
        next(from: .logo, model)
    }
}

// MARK: - Fenster

struct CompletenessFlowView: View {
    let only: UUID?
    @Environment(AppModel.self) private var model
    @State private var flow: CompletenessFlowState

    init(only: UUID?) {
        self.only = only
        _flow = State(initialValue: CompletenessFlowState(only: only))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.horizontal, KMetric.gutter)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .kContentWidth()
            }
            .scrollDismissesKeyboard(.interactively)
            .kPageBackground()
            .kKeyboardDone()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if flow.backVisible {
                        Button {
                            flow.back(model)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "chevron.left").fontWeight(.semibold)
                                Text("Zurück")
                            }
                        }
                        .disabled(flow.busy)
                        .accessibilityIdentifier("vk.back")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(flow.step == .end ? "Fertig" : Completeness.laterTitle) { close() }
                        .fontWeight(.semibold)
                        .disabled(flow.busy)
                        .accessibilityIdentifier("vk.later")
                }
            }
        }
        .interactiveDismissDisabled(flow.busy)
        .onAppear { flow.setup(model) }
        .onDisappear {
            flow.closed = true
            flow.searchTask?.cancel()
        }
    }

    private var title: String {
        switch flow.step {
        case .start: return Completeness.title
        case .logo: return flow.pick.flatMap { $0 < flow.logos.count ? flow.logos[$0].name : nil } ?? "Logos"
        case .term: return "Fristen"
        case .sender: return "Adresse"
        case .end: return Completeness.endTitle(single: flow.only != nil)
        }
    }

    private func close() {
        if flow.busy { return }
        flow.closed = true
        model.dismissTop()
    }

    @ViewBuilder private var content: some View {
        let n = flow.report(model)
        switch flow.step {
        case .start: CFStartPage(flow: flow, report: n, close: close)
        case .logo:
            if flow.pick != nil {
                CFLogoPickPage(flow: flow)
            } else {
                CFLogoPage(flow: flow, report: n)
            }
        case .term: CFTermPage(flow: flow, report: n)
        case .sender: CFSenderPage(flow: flow, report: n)
        case .end: CFEndPage(flow: flow, report: n, close: close)
        }
    }
}

// MARK: - Bausteine

/// Ring mit Prozent (Web `.vkring`)
struct CFRing: View {
    let percent: Int
    var size: CGFloat = 150

    var body: some View {
        ZStack {
            Circle().stroke(KColor.line, lineWidth: size * 0.093)
            Circle()
                .trim(from: 0, to: CGFloat(Swift.max(0, Swift.min(100, percent))) / 100)
                .stroke(KColor.teal, style: StrokeStyle(lineWidth: size * 0.093, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Text(verbatim: "\(percent)%")
                .font(.system(size: size * 0.23, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(KColor.ink)
        }
        .padding(size * 0.0465)
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(percent) Prozent startklar"))
    }
}

/// Hauptknopf (Web `.vkbtn`), grau bei `secondary`
struct CFButton: View {
    let title: String
    var secondary = false
    var disabled = false
    var identifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(secondary ? KColor.ink : Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(secondary ? KColor.sunken : KColor.teal))
                .opacity(disabled ? 0.55 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .padding(.top, 12)
        .accessibilityIdentifier(identifier ?? title)
    }
}

/// Dezenter Textknopf (Web `.vklink`)
struct CFLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(KColor.ink3)
                .padding(8)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
    }
}

/// Fortschritt oben (Web `vkProg`): Balken, links «Frage 2 von 4», rechts «60 % startklar»
struct CFProgress: View {
    let index: Int
    let total: Int
    let label: String
    let gain: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(KColor.line)
                    Capsule().fill(KColor.teal)
                        .frame(width: g.size.width * CGFloat(Swift.min(1, Double(index) / Double(Swift.max(1, total)))))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            HStack {
                Text(label).font(.footnote).foregroundStyle(KColor.ink2)
                Spacer()
                if let g = gain {
                    Text(g)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(KColor.ok)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(KColor.ok.opacity(0.15)))
                }
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 16)
    }
}

/// Frage (Web `.vkq`) und Erklärung (`.vkp.l`)
struct CFQuestion: View {
    let title: String
    var text: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(KColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let t = text {
                Text(t)
                    .font(.subheadline)
                    .foregroundStyle(KColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 12)
    }
}

/// Eingabefeld mit Beschriftung (Web `.vkf`)
struct CFField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.footnote).foregroundStyle(KColor.ink2)
            content
        }
        .padding(.top, 8)
    }
}

extension View {
    /// Feldhintergrund (Web `.vkf input`)
    func cfFieldBox() -> some View {
        padding(12)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(KColor.field))
    }
}

// MARK: - Start

struct CFStartPage: View {
    let flow: CompletenessFlowState
    let report: CompletenessReport
    let close: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if report.total == 0 {
                Text(Completeness.emptyTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(KColor.ink)
                    .padding(.top, 24)
                    .padding(.bottom, 6)
                Text(Completeness.emptyText)
                    .font(.subheadline)
                    .foregroundStyle(KColor.ink2)
                    .multilineTextAlignment(.center)
            } else {
                CFRing(percent: report.percent)
                    .padding(.top, 14)
                    .padding(.bottom, 16)
                Text(Completeness.startHeadline(percent: report.percent))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(KColor.ink)
                    .padding(.bottom, 6)
                Text(attributed(Completeness.startText(questions: report.questionCount)))
                    .font(.subheadline)
                    .foregroundStyle(KColor.ink2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)
                if !flow.auto.isEmpty {
                    Text(Completeness.autoText(flow.auto.count))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KColor.ok)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 4)
                }
                CFButton(title: Completeness.goTitle(report), identifier: "vk.go") {
                    flow.next(from: .start, model)
                }
                CFButton(title: Completeness.laterTitle, secondary: true, identifier: "vk.startLater") { close() }
                CFLink(title: Completeness.detailLink) {
                    model.dismissTop()
                    model.presentAfterDismiss(.manage(.quality))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func attributed(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s)) ?? AttributedString(s.replacingOccurrences(of: "**", with: ""))
    }
}

// MARK: - Logos

struct CFLogoPage: View {
    @Bindable var flow: CompletenessFlowState
    let report: CompletenessReport
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)]

    var body: some View {
        let anyOk = flow.logos.contains { $0.state == .ok }
        let load = flow.loading
        VStack(alignment: .leading, spacing: 0) {
            CFProgress(index: 0, total: flow.questionCount, label: Completeness.logoStepLabel,
                       gain: Completeness.gainText(report, single: flow.only != nil))
            CFQuestion(title: anyOk || load ? Completeness.logoQuestionFound : Completeness.logoQuestionNone,
                       text: flow.offline ? Completeness.logoTextOffline : (anyOk || load ? Completeness.logoTextFound : Completeness.logoTextNone))
            LazyVGrid(columns: columns, spacing: 9) {
                ForEach(Array(flow.logos.enumerated()), id: \.element.id) { i, t in
                    tile(i, t)
                }
            }
            .padding(.vertical, 4)
            let n = flow.selectedCount
            CFButton(title: flow.applyText ?? (load ? Completeness.logoSearching : Completeness.logoApplyTitle(n)),
                     disabled: load || flow.busy, identifier: "vk.logoNext") {
                Task { await flow.applyLogos(model) }
            }
        }
    }

    private func tile(_ i: Int, _ t: CFLogoTile) -> some View {
        let selected = t.state == .ok && t.on
        return Button {
            if t.state == .load || flow.busy { return }
            flow.pick = i
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    switch t.state {
                    case .ok:
                        AsyncImage(url: URL(string: t.current.map { $0.thumb.isEmpty ? $0.url : $0.thumb } ?? "")) { ph in
                            if let img = ph.image { img.resizable().interpolation(.high).scaledToFit() } else { Color.clear }
                        }
                        .frame(width: 52, height: 52)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    case .load:
                        ProgressView().frame(width: 52, height: 52)
                    case .none, .skip:
                        Text(t.state == .skip ? "–" : "?")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(KColor.ink3)
                            .frame(width: 52, height: 52)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KColor.sunken))
                    }
                }
                Text(t.name)
                    .font(.caption)
                    .foregroundStyle(KColor.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if t.state == .none {
                    Text("Suchen").font(.caption2.weight(.semibold)).foregroundStyle(KColor.teal)
                } else if t.state == .skip {
                    Text("ohne Logo").font(.caption2.weight(.semibold)).foregroundStyle(KColor.teal)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 12)
            .padding(.bottom, 9)
            .frame(maxWidth: .infinity, minHeight: 104)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KColor.field))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? KColor.teal : Color.clear, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(KColor.teal))
                        .padding(6)
                }
            }
            .opacity(t.state == .ok && !t.on ? 0.5 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.name + (t.state == .none ? ", Suchen" : (t.state == .skip ? ", ohne Logo" : "")))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("vk.tile." + t.name)
    }
}

/// Logo für eine Kachel: andere Treffer, selbst suchen, «Ohne Logo» (Web `paintVkPick`)
struct CFLogoPickPage: View {
    @Bindable var flow: CompletenessFlowState
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)]

    var body: some View {
        if let k = flow.pick, k < flow.logos.count {
            let t = flow.logos[k]
            VStack(alignment: .leading, spacing: 0) {
                CFQuestion(title: "Logo für «" + t.name + "»")
                if t.cands.isEmpty {
                    Text("Kontivo hat noch nichts gefunden. Versuch es mit einem anderen Namen.")
                        .font(.subheadline)
                        .foregroundStyle(KColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    LazyVGrid(columns: columns, spacing: 9) {
                        ForEach(Array(t.cands.prefix(9).enumerated()), id: \.element.id) { i, c in
                            Button {
                                flow.choose(i)
                            } label: {
                                VStack(spacing: 6) {
                                    AsyncImage(url: URL(string: c.thumb.isEmpty ? c.url : c.thumb)) { ph in
                                        if let img = ph.image { img.resizable().interpolation(.high).scaledToFit() } else { Color.clear }
                                    }
                                    .frame(width: 52, height: 52)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    Text(c.src.label).font(.caption2.weight(.semibold)).foregroundStyle(KColor.teal).lineLimit(1)
                                }
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, minHeight: 96)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KColor.field))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(t.state == .ok && i == t.sel ? KColor.teal : Color.clear, lineWidth: 2))
                                .opacity(t.state == .ok && i == t.sel ? 1 : 0.5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Logo " + String(i + 1) + ", " + c.src.label)
                        }
                    }
                }
                CFField(label: "Selbst suchen") {
                    HStack(spacing: 8) {
                        TextField("Name", text: $flow.logos[k].query)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit { Task { await flow.manualSearch(model) } }
                            .cfFieldBox()
                        Button(flow.searching ? "Sucht …" : "Suchen") {
                            Task { await flow.manualSearch(model) }
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(KColor.teal)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(KColor.sunken))
                        .buttonStyle(.plain)
                        .disabled(flow.searching)
                    }
                }
                CFButton(title: "Ohne Logo", secondary: true, identifier: "vk.noLogo") { flow.skipLogo(model) }
                CFLink(title: "Zurück zur Übersicht") { flow.pick = nil }
            }
        }
    }
}

// MARK: - Fristen

struct CFTermPage: View {
    @Bindable var flow: CompletenessFlowState
    let report: CompletenessReport
    @Environment(AppModel.self) private var model
    @FocusState private var noticeFocus: Bool

    var body: some View {
        if flow.ti < flow.terms.count, let c = model.data.contract(flow.terms[flow.ti]) {
            let calc = model.calc
            let name = Completeness.termName(c, data: model.data)
            let t = Catalog.match(names: [model.data.partnerName(of: c), c.label], currency: c.currency)
            let idx = (flow.logos.isEmpty ? 0 : 1) + flow.ti
            VStack(alignment: .leading, spacing: 0) {
                CFProgress(index: idx, total: flow.questionCount, label: Completeness.questionLabel(idx + 1, of: flow.questionCount),
                           gain: Completeness.gainText(report, single: flow.only != nil))
                HStack(spacing: 12) {
                    MarkView(contract: c, data: model.data, size: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).font(.body.weight(.semibold)).foregroundStyle(KColor.ink)
                        Text(Completeness.termWho(c, calc: calc)).font(.footnote).foregroundStyle(KColor.ink3)
                    }
                }
                .padding(.bottom, 4)
                .accessibilityElement(children: .combine)
                CFQuestion(title: Completeness.termQuestion(name), text: Completeness.termText(catalog: t))
                ForEach(0..<Completeness.termModes.count, id: \.self) { i in
                    let m = Completeness.termModes[i]
                    modeTile(m.mode, icon: m.icon, title: m.title, subtitle: m.subtitle, contractID: c.id)
                }
                fields
                if let m = flow.draft.mode, m != .tax {
                    CFButton(title: "Weiter", identifier: "vk.termSave") { save(c.id) }
                }
                CFLink(title: Completeness.termSkip) { flow.next(from: .term, model) }
                    .accessibilityIdentifier("vk.termSkip")
            }
        }
    }

    private func modeTile(_ m: CompletenessTermDraft.Mode, icon: String, title: String, subtitle: String, contractID: UUID) -> some View {
        let on = flow.draft.mode == m
        return Button {
            flow.draft.mode = m
            if m == .tax {
                save(contractID)
            } else if m == .fixed && flow.draft.end == nil {
                // Datum zuerst
            } else if flow.draft.notice.isEmpty {
                noticeFocus = true
            }
        } label: {
            HStack(spacing: 12) {
                Text(icon)
                    .font(.body.weight(.bold))
                    .foregroundStyle(KColor.teal)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(KColor.surface))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(KColor.ink)
                    Text(subtitle).font(.caption).foregroundStyle(KColor.ink3)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(on ? KColor.teal.opacity(0.09) : KColor.field))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(on ? KColor.teal : Color.clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
        .accessibilityLabel(title + ", " + subtitle)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("vk.mode." + m.rawValue)
    }

    @ViewBuilder private var fields: some View {
        switch flow.draft.mode {
        case .open?:
            noticeField(placeholder: "1")
            CFField(label: "Kündbar") {
                Picker("Kündbar", selection: $flow.draft.cancelTerm) {
                    ForEach(0..<termOptions.count, id: \.self) { i in Text(termOptions[i].title).tag(termOptions[i].value) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .cfFieldBox()
            }
        case .fixed?:
            CFField(label: "Läuft bis") {
                if let e = flow.draft.end {
                    DatePicker("Läuft bis", selection: Binding(get: { e.date() }, set: { flow.draft.end = Day(date: $0) }), displayedComponents: .date)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cfFieldBox()
                } else {
                    Button {
                        flow.draft.end = model.today.addingMonths(12)
                    } label: {
                        Text("Datum wählen")
                            .foregroundStyle(KColor.teal)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cfFieldBox()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("vk.endPick")
                }
            }
            CFField(label: "Verlängert sich danach") {
                Picker("Verlängert sich danach", selection: $flow.draft.renew) {
                    ForEach(0..<Completeness.renewOptions.count, id: \.self) { i in
                        Text(Completeness.renewOptions[i].title).tag(Completeness.renewOptions[i].value)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .cfFieldBox()
            }
            noticeField(placeholder: "3")
        default:
            EmptyView()
        }
    }

    /// Auswahl «Kündbar»; ein bestehender Halbjahres-Termin bleibt wählbar
    private var termOptions: [(value: CancelTerm, title: String)] {
        var o = Completeness.termOptions
        if flow.draft.cancelTerm == .halfYearEnd { o.append((.halfYearEnd, "auf Halbjahresende")) }
        return o
    }

    private var unitOptions: [(value: NoticeUnit, title: String)] {
        var o = Completeness.unitOptions
        if flow.draft.noticeUnit == .dayOfMonth { o.append((.dayOfMonth, ". im Monat")) }
        return o
    }

    private func noticeField(placeholder: String) -> some View {
        CFField(label: "Kündigungsfrist") {
            HStack(spacing: 8) {
                TextField(placeholder, text: $flow.draft.notice)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($noticeFocus)
                    .frame(width: 66)
                    .cfFieldBox()
                    .accessibilityLabel("Kündigungsfrist")
                    .accessibilityIdentifier("vk.notice")
                Picker("Einheit", selection: $flow.draft.noticeUnit) {
                    ForEach(0..<unitOptions.count, id: \.self) { i in Text(unitOptions[i].title).tag(unitOptions[i].value) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .cfFieldBox()
            }
        }
    }

    private func save(_ id: UUID) {
        noticeFocus = false
        var out: CompletenessTermOutcome = .saved
        let d = flow.draft
        let today = model.today
        let ok = model.update { out = $0.saveCompletenessTerm(id, d, today: today) }
        guard ok else { return }
        switch out {
        case .saved:
            flow.next(from: .term, model)
        case .invalid(let m):
            model.toast(m)
            if m == Completeness.noticeMissing { noticeFocus = true }
        case .stillMissing(let m):
            model.toast(m)
        }
    }
}

// MARK: - Absender

struct CFSenderPage: View {
    @Bindable var flow: CompletenessFlowState
    let report: CompletenessReport
    @Environment(AppModel.self) private var model
    @State private var shownID: UUID?
    @State private var first = ""
    @State private var last = ""
    @State private var street = ""
    @State private var zip = ""
    @State private var city = ""

    var body: some View {
        if flow.si < flow.senders.count, let p = model.data.person(flow.senders[flow.si]) {
            let idx = (flow.logos.isEmpty ? 0 : 1) + flow.terms.count + flow.si
            let others = model.data.completenessSameCandidates(for: p.id)
            VStack(alignment: .leading, spacing: 0) {
                CFProgress(index: idx, total: flow.questionCount, label: Completeness.questionLabel(idx + 1, of: flow.questionCount),
                           gain: Completeness.gainText(report, single: flow.only != nil))
                CFQuestion(title: Completeness.senderQuestion(name: p.name, personCount: model.data.persons.count), text: Completeness.senderText)
                if !others.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(others) { o in
                                Chip(title: "Gleich wie " + o.name, isOn: false) {
                                    model.update { $0.setCompletenessSenderSame(p.id, as: o.id) }
                                    flow.next(from: .sender, model)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 6)
                }
                VStack(spacing: 6) {
                    field("Vorname", $first, .givenName)
                    field("Nachname", $last, .familyName)
                    field("Strasse und Nr.", $street, .streetAddressLine1)
                    HStack(spacing: 8) {
                        field("PLZ", $zip, .postalCode, keyboard: .numbersAndPunctuation)
                        field("Ort", $city, .addressCity)
                    }
                }
                .padding(.top, 8)
                CFButton(title: "Weiter", identifier: "vk.senderSave") { save(p.id) }
                CFLink(title: Completeness.senderSkip) { flow.next(from: .sender, model) }
                    .accessibilityIdentifier("vk.senderSkip")
            }
            .onAppear { load(p.id) }
            .onChange(of: flow.si) { _, _ in
                if flow.si < flow.senders.count { load(flow.senders[flow.si]) }
            }
        }
    }

    private func load(_ id: UUID) {
        if shownID == id { return }
        shownID = id
        let s = model.data.resolvedSender(id)
        first = s.first
        last = s.last
        street = s.street
        zip = s.zip
        city = s.city
    }

    private func field(_ ph: String, _ text: Binding<String>, _ content: UITextContentType, keyboard: UIKeyboardType = .default) -> some View {
        TextField(ph, text: text)
            .textContentType(content)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .cfFieldBox()
            .accessibilityLabel(ph)
    }

    private func save(_ id: UUID) {
        var msg: String? = nil
        let (f, l, s, z, c) = (first, last, street, zip, city)
        model.update { msg = $0.saveCompletenessSender(id, first: f, last: l, street: s, zip: z, city: c) }
        if let m = msg {
            model.toast(m)
            return
        }
        flow.next(from: .sender, model)
    }
}

// MARK: - Abschluss

struct CFEndPage: View {
    let flow: CompletenessFlowState
    let report: CompletenessReport
    let close: () -> Void

    var body: some View {
        let single = flow.only != nil
        VStack(spacing: 0) {
            if report.isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 110, height: 110)
                    .background(Circle().fill(KColor.ok))
                    .background(Circle().fill(KColor.ok.opacity(0.15)).padding(-14))
                    .padding(.top, 24)
                    .padding(.bottom, 16)
                    .accessibilityHidden(true)
            } else {
                CFRing(percent: report.percent)
                    .padding(.top, 14)
                    .padding(.bottom, 16)
            }
            Text(Completeness.endHeadline(report, single: single))
                .font(.title2.weight(.bold))
                .foregroundStyle(KColor.ink)
                .multilineTextAlignment(.center)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            Text(Completeness.endText(report))
                .font(.subheadline)
                .foregroundStyle(KColor.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 14)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Completeness.endList, id: \.self) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("✓").font(.body.weight(.bold)).foregroundStyle(KColor.ok).accessibilityHidden(true)
                        Text(s).font(.body).foregroundStyle(KColor.ink)
                    }
                }
            }
            .frame(maxWidth: 300, alignment: .leading)
            .padding(.top, 6)
            CFButton(title: "Fertig", identifier: "vk.done") { close() }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Hinweis im Vertragsdetail (für den Bereich Verträge)

/// «✨ 2 Angaben fehlen noch · Logo · Kündigungsfrist – dann erinnert Kontivo rechtzeitig · Ergänzen ›» (Web `vkHintHtml`).
/// Zeigt nichts, wenn nichts fehlt. Antippen öffnet die Vollständigkeit nur für diesen Vertrag.
struct CompletenessHintButton: View {
    let contractID: UUID
    @Environment(AppModel.self) private var model

    var body: some View {
        let f = model.files
        if let h = Completeness.hint(contract: contractID, data: model.data, today: model.today, hasFile: { f.has($0) }) {
            Button {
                model.present(.manage(.completeness(only: contractID)))
            } label: {
                HStack(spacing: 10) {
                    Text("✨").accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(h.title).font(.subheadline.weight(.semibold)).foregroundStyle(KColor.teal)
                        Text(h.detail).font(.footnote).foregroundStyle(KColor.ink2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    Text(h.action).font(.subheadline.weight(.semibold)).foregroundStyle(KColor.teal).fixedSize()
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KColor.teal.opacity(0.09)))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("vk.hint")
        }
    }
}
