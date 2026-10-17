import SwiftUI
import KontivoCore

/// Tab «Fristen» (Web v224): Kopf wie die Summe (Serif 34 px, linksbündig, v164/v184), eine Liste nach Datum mit
/// «Behalten» / «Kündigen» nur bei anstehenden Fristen, Karte «Flexibel», Klappgruppen und Quartals-Check.
struct DeadlinesTab: View {
    @Environment(AppModel.self) private var model
    @State private var openFolds: Set<String> = []
    @State private var killTarget: DeadlineKillTarget?
    /// «In Kalender» (Knopf in der Knopfzeile bzw. langes Drücken auf eine Zeile)
    @State private var calendarTarget: DeadlineCalendarTarget?
    @State private var showReview = false

    var body: some View {
        let calc = model.calc
        let ov = calc.deadlineOverview()
        let review = calc.reviewDue()
        GeometryReader { geo in
            ScrollViewReader { proxy in
            ScrollView {
                if ov.isEmpty && !review {
                    DeadlinesEmptyView(showPreview: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom > 700) {
                        model.present(.contractForm(.new(prefill: nil)))
                    }
                    .padding(.horizontal, KMetric.gutter)
                    .padding(.bottom, 28)
                    .kContentWidth()
                } else {
                    content(ov, review: review)
                        .padding(.horizontal, KMetric.gutter)
                        .padding(.bottom, 28)
                        .kContentWidth()
                }
                Color.clear.frame(height: 1).id("deadlines.end")
            }
            #if DEBUG
            .onAppear {
                CTUITestSeed.applyIfNeeded(model)
                if let s = DLUITestSeed.apply(model) {
                    if s.contains("folds") { openFolds = ["any", "none", "unw"] }
                    if s.contains("end") {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 600_000_000)
                            proxy.scrollTo("deadlines.end", anchor: .bottom)
                        }
                    }
                }
            }
            #endif
            }
        }
        .kPageBackground()
        .navigationTitle("Fristen")
        .deadlineKillSheet($killTarget)
        .deadlineCalendar($calendarTarget)
        .sheet(isPresented: $showReview) {
            DeadlineReviewSheet().environment(model)
        }
    }

    // MARK: Inhalt (Web renderView, Tab «term»)

    @ViewBuilder private func content(_ ov: Calc.DeadlineOverview, review: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let st = ov.status {
                DeadlineStatusView(status: st)
            }
            if !ov.marked.isEmpty {
                markedGroup(ov)
            }
            if !ov.items.isEmpty {
                DeadlineGroup(title: Calc.DeadlineOverview.listTitle, trailing: Calc.DeadlineOverview.listRight) {
                    VStack(spacing: 0) {
                        ForEach(Array(ov.items.enumerated()), id: \.element) { item in
                            if let c = model.data.contract(item.element.contractID) {
                                DeadlineItemRow(item: item.element, contract: c, data: model.data,
                                                canCalendar: DeadlineCalendar.deadline(for: item.element, contract: c) != nil,
                                                onOpen: { model.present(.contractDetail(c.id)) },
                                                onKeep: { keep(item.element) },
                                                onKill: { killTarget = DeadlineKillTarget(contractID: c.id, trial: item.element.trial) },
                                                onCalendar: { addToCalendar(item.element) })
                                    .overlay(alignment: .top) {
                                        if item.offset > 0 { DeadlineRule() }
                                    }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(KColor.surface))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("deadlines.list")
                }
            }
            if !ov.flexible.isEmpty {
                flexGroup(ov)
            }
            // «Ohne Frist erfasst»: Zeile öffnet den Inline-Editor «Kündigungsfrist und Laufzeit» (Web data-qnotice)
            foldGroup(key: "none", title: Calc.DeadlineOverview.withoutNoticeTitle, extra: Calc.DeadlineOverview.withoutNoticeExtra, rows: ov.withoutNotice,
                      chevron: true) { _ in
                model.present(.manage(.qualityList(.B, field: "notice", title: "Kündigungsfrist und Laufzeit")))
            }
            foldGroup(key: "unw", title: Calc.DeadlineOverview.unwatchedTitle, extra: "", rows: ov.unwatched)
            if review {
                DeadlineReviewCard(onGo: { showReview = true }, onDone: markReviewed, onLater: snoozeReview)
                    .padding(.top, 18)
            }
        }
    }

    /// «Zum Kündigen vorgemerkt» (Quartals-Check, `.tcard`): Karte mit «Doch behalten» und «Kündigen»/«Wechseln»
    @ViewBuilder private func markedGroup(_ ov: Calc.DeadlineOverview) -> some View {
        DeadlineGroup(title: Calc.DeadlineOverview.markedTitle, trailing: Format.money(ov.markedMonthly) + " " + model.calc.home.rawValue + "/Mt.") {
            VStack(spacing: 8) {
                ForEach(ov.marked, id: \.self) { m in
                    if let c = model.data.contract(m.contractID) {
                        DeadlineMarkedCard(row: m, contract: c, data: model.data,
                                           onOpen: { model.present(.contractDetail(c.id)) },
                                           onKeep: {
                                               // Web data-rvkeep: Antwort «Brauche ich» mit heutigem Datum, Toast «Behalten»
                                               let id = c.id, day = model.today
                                               if model.update({ $0.setReview(id, .keep, today: day) }) { model.toast("Behalten") }
                                           },
                                           onKill: { killTarget = DeadlineKillTarget(contractID: c.id, trial: false) })
                    }
                }
            }
            .padding(.bottom, 8) // `.tcard` margin-bottom 8 (auch nach der letzten Karte)
        }
    }

    /// «Flexibel» (`.tflex`): kurzfristig kündbare Verträge als eine Karte mit Logostapel, aufklappbar
    @ViewBuilder private func flexGroup(_ ov: Calc.DeadlineOverview) -> some View {
        let open = openFolds.contains("any")
        DeadlineGroup(title: Calc.DeadlineOverview.flexTitle) {
            VStack(spacing: 0) {
                Button {
                    toggleFold("any")
                } label: {
                    HStack(spacing: 12) {
                        HStack(spacing: -9) {
                            ForEach(ov.flexStack, id: \.self) { id in
                                if let c = model.data.contract(id) {
                                    MarkView(contract: c, data: model.data, size: 34)
                                        // box-shadow 0 0 0 2px var(--surface): Ring ausserhalb der Kachel
                                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(KColor.surface).padding(-2))
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            DeadlineName(title: ov.flexCountText, partner: "")
                            DeadlineSub(text: Calc.DeadlineOverview.flexSubtitle)
                        }
                        Spacer(minLength: 0)
                        OnbChevron(degrees: open ? 45 : -45)
                            .padding(.trailing, 4)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(open ? "aufgeklappt" : "zugeklappt")
                .accessibilityIdentifier("deadlines.flex")
                if open {
                    Text(verbatim: Calc.DeadlineOverview.flexNote)
                        .font(.system(size: 13))
                        .foregroundStyle(KColor.ink2)
                        .onbLine(13, 18.2)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .top) { Rectangle().fill(KColor.line).frame(height: 1) }
                    VStack(spacing: 0) {
                        ForEach(Array(ov.flexible.enumerated()), id: \.element) { i, r in
                            if let c = model.data.contract(r.contractID) {
                                Button { model.present(.contractDetail(c.id)) } label: {
                                    HStack(spacing: 12) {
                                        MarkView(contract: c, data: model.data, size: 34)
                                        VStack(alignment: .leading, spacing: 0) {
                                            DeadlineName(title: model.data.title(of: c), partner: r.partner)
                                            DeadlineSub(text: r.sub)
                                        }
                                        Spacer(minLength: 8)
                                        DeadlineChip(text: r.chip, level: .none)
                                    }
                                    .padding(.vertical, 13)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .overlay(alignment: .top) { if i > 0 { DeadlineRule() } }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .overlay(alignment: .top) { Rectangle().fill(KColor.line).frame(height: 1) }
                }
            }
            .background(KColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: KMetric.radius, style: .continuous))
        }
    }

    /// Klappgruppe (`.grp.tfg` + `.tfold`): Zeile mit Linie oben auf dem Papier, aufgeklappt eine Karte mit den Verträgen
    @ViewBuilder private func foldGroup(key: String, title: String, extra: String, rows: [Calc.FoldRow],
                                        chevron: Bool = false, onRow: ((Contract) -> Void)? = nil) -> some View {
        if !rows.isEmpty {
            let open = openFolds.contains(key)
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    toggleFold(key)
                } label: {
                    HStack(spacing: 8) {
                        Text("\(title) (\(rows.count))\(extra)")
                            .font(.system(size: 14))
                            .foregroundStyle(KColor.ink2)
                            .multilineTextAlignment(.leading)
                            .onbLine(14, 20.3)
                        Spacer(minLength: 8)
                        OnbChevron(degrees: open ? -135 : 45)
                            .padding(.trailing, 6)
                            .offset(y: open ? 2 : -2)
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) { Rectangle().fill(KColor.line).frame(height: 1) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(open ? "aufgeklappt" : "zugeklappt")
                if open {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element) { i, r in
                            if let c = model.data.contract(r.contractID) {
                                DeadlineListRow(contract: c, data: model.data, partner: r.partner, text: r.text + (chevron ? " ›" : "")) {
                                    if let f = onRow { f(c) } else { model.present(.contractDetail(c.id)) }
                                }
                                .overlay(alignment: .top) { if i > 0 { DeadlineRule() } }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(KColor.surface))
                    .padding(.bottom, 12)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 2)
        }
    }

    // MARK: Aktionen

    private func toggleFold(_ key: String) {
        if openFolds.contains(key) {
            _ = openFolds.remove(key)
        } else {
            _ = openFolds.insert(key)
        }
    }

    /// «Behalten» (auch Probeabo): Toast wie Web «Fristen» (`AppData.keepToast`)
    private func keep(_ d: Calc.DeadlineItem) {
        let day = model.today
        let id = d.contractID
        let trial = d.trial
        if model.update({ $0.keep(id, trial: trial, today: day) }) {
            model.toast(AppData.keepToast)
        }
    }

    private func markReviewed() {
        let day = model.today
        if model.update({ $0.markReviewed(today: day) }) {
            model.toast(AppData.reviewedToast)
        }
    }

    private func snoozeReview() {
        let day = model.today
        model.update { $0.snoozeReview(today: day) }
    }

    private func addToCalendar(_ d: Calc.DeadlineItem) {
        // Doppeltippen: nur ein Kalenderdialog
        guard calendarTarget == nil, let c = model.data.contract(d.contractID),
              let dl = DeadlineCalendar.deadline(for: d, contract: c) else { return }
        calendarTarget = DeadlineCalendarTarget(contractID: c.id, deadline: dl)
    }
}

#if DEBUG
/// Bildschirmfotos/UI-Tests: Startargument «-uiDeadlines a,b» (nur mit -uiDemo, nichts wird gespeichert)
/// - `review`: Quartals-Check fällig (letzte Prüfung vor 120 Tagen)
/// - `marked`: «Halbtax» beim Quartals-Check zum Kündigen vorgemerkt
/// - `folds`: «Flexibel» und Klappgruppen aufgeklappt
/// - `end`: ans Ende gescrollt
@MainActor
enum DLUITestSeed {
    private static var done = false

    static func apply(_ model: AppModel) -> Set<String>? {
        guard !done, model.uiTestMode else { return nil }
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiDeadlines"), i + 1 < args.count else { return nil }
        done = true
        let seeds = Set(args[i + 1].split(separator: ",").map { String($0) })
        let day = model.today
        model.update { d in
            if seeds.contains("review") { d.settings.lastReview = day.addingDays(-120) }
            if seeds.contains("marked"), let c = d.contracts.first(where: { $0.label == "Halbtax" }) {
                d.setReview(c.id, .kill, today: day)
            }
        }
        return seeds
    }
}
#endif

// MARK: - Bausteine (Werte aus den berechneten Styles der Web-App v224, Viewport 402×874)

/// `.grp` mit `.grphead`: Abstand 20 oben / 2 unten; Kopf 12 px (links 600 ink, rechts 400 ink2, Tabellenziffern), 6 px darunter
private struct DeadlineGroup<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(KColor.ink)
                Spacer(minLength: 8)
                if let t = trailing {
                    Text(verbatim: t)
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(KColor.ink2)
                }
            }
            .onbLine(12, 17.4, .semibold)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(.top, 20)
        .padding(.bottom, 2)
    }
}

/// Trennlinie zwischen Zeilen (`border-top: 1px solid var(--line)`) innerhalb des Kartenabstands
private struct DeadlineRule: View {
    var body: some View { Rectangle().fill(KColor.line).frame(height: 1) }
}

/// Kopf (`.tstat`, Design-Schicht v164/v184): linksbündig ohne Kreis, Titel Serif 34 px 500 (Zeilenhöhe 1.1),
/// Untertitel 14 px ink2 6 px darunter; Abstand 22 oben / 8 unten.
private struct DeadlineStatusView: View {
    let status: Calc.DeadlineStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: status.title)
                .font(KFont.serif(34, .medium))
                .tracking(-0.34)
                .foregroundStyle(KColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .onbLine(34, 37.4, .medium, .serif)
            Text(verbatim: status.subtitle)
                .font(.system(size: 14))
                .foregroundStyle(KColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .onbLine(14, 20.3)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 22)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("deadlines.status")
    }
}

/// Chip rechts (`.tchip`, v164): ohne Hintergrund, 12 px 600; Messing = Knöpfe sichtbar, rot nur bei gekündigt (v163),
/// grün = behalten, sonst neutral (auch ≤ 7 Tage: `.tchip{color:var(--ink2)!important}` überschreibt `.tchip.alert`).
private struct DeadlineChip: View {
    let text: String
    let level: Calc.ChipLevel

    var body: some View {
        let col: Color = {
            switch level {
            case .warn: return KColor.teal
            case .end: return KColor.alert
            case .ok: return KColor.ok
            case .alert, .none: return KColor.ink2
            }
        }()
        Text(verbatim: text)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(col)
            .onbLine(12, 17.4, .semibold)
            .fixedSize()
    }
}

/// Titel (`.mn`, Rounded 16 px 600) mit Vertragspartner (`· Spotify`, Rounded 0.88em 500 ink2), eine Zeile mit «…»
private struct DeadlineName: View {
    let title: String
    let partner: String

    var body: some View {
        (Text(verbatim: title).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundColor(KColor.ink)
            + Text(verbatim: partner.isEmpty ? "" : " · " + partner).font(.system(size: 14.08, weight: .medium, design: .rounded))
                .foregroundColor(KColor.ink2))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(height: 20)
    }
}

/// Unterzeile (`.mm`): 12.5 px ink2, eine Zeile
private struct DeadlineSub: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 12.5))
            .foregroundStyle(KColor.ink2)
            .lineLimit(1)
            .frame(height: 18.125)
    }
}

/// Zeile der Liste «Fristen · nach Datum» (`.tit`): Kachel 34, Titel, Unterzeile, Chip; Knöpfe nur bei `showActions`.
private struct DeadlineItemRow: View {
    let item: Calc.DeadlineItem
    let contract: Contract
    let data: AppData
    /// Frist für «In Kalender» vorhanden (nicht bei «Gekündigt» und «Behalten · läuft bis»)
    let canCalendar: Bool
    let onOpen: () -> Void
    let onKeep: () -> Void
    let onKill: () -> Void
    let onCalendar: () -> Void

    /// Web v163: «endet von selbst» neutral, rot nur bei gekündigt.
    /// TODO core-API: entfällt, sobald `Calc.deadlineOverview()` (Bereich core) `chipLevel` so liefert.
    private var level: Calc.ChipLevel {
        if item.kind == .ended && contract.cancelPer == nil { return .none }
        return item.chipLevel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    MarkView(contract: contract, data: data, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        DeadlineName(title: data.title(of: contract), partner: item.partner)
                        DeadlineSub(text: item.sub)
                    }
                    Spacer(minLength: 12)
                    DeadlineChip(text: item.chip, level: level)
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Öffnet die Vertragsdetails")
            // «In Kalender» für jede Frist per langem Drücken (Zeile bleibt wie im Web ohne Zusatzknopf)
            .contextMenu {
                Button(action: onOpen) { Label("Details", systemImage: "doc.text") }
                if canCalendar {
                    Button(action: onCalendar) { Label(DeadlineCalendar.menuTitle, systemImage: DeadlineCalendar.symbol) }
                }
            }
            .accessibilityActions {
                if canCalendar { Button(DeadlineCalendar.menuTitle, action: onCalendar) }
            }
            if item.showActions {
                // `.tlist .tacts`: links 52, unten 13, −3 oben, Lücke 8
                HStack(spacing: 8) {
                    DeadlineActionButton(title: item.keepTitle, action: onKeep)
                    DeadlineActionButton(title: item.cancelTitle, accent: true, action: onKill)
                }
                .padding(.leading, 52)
                .padding(.bottom, 13)
                .padding(.top, -3)
            }
        }
    }
}

/// Knopf `.tacts button`: 14 px 600, Abstand 8/10, Radius 10, sunken; «Kündigen» (`.tk`) in Teal
private struct DeadlineActionButton: View {
    let title: String
    var accent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent ? KColor.teal : KColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .onbLine(14, 20.3, .semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.sunken))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Vorgemerkter Vertrag (`.tcard`): Kachel 50, Name Rounded 14.5 px, Zeile 12.5 px ink3; Knöpfe links 76
private struct DeadlineMarkedCard: View {
    let row: Calc.MarkedRow
    let contract: Contract
    let data: AppData
    let onOpen: () -> Void
    let onKeep: () -> Void
    let onKill: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    MarkView(contract: contract, data: data, size: 50)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(data.title(of: contract))
                            .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(KColor.ink)
                            .lineLimit(1)
                            .frame(height: 18.125)
                            .padding(.bottom, 1)
                        Text(verbatim: row.line)
                            .font(.system(size: 12.5))
                            .foregroundStyle(KColor.ink3)
                            .lineLimit(1)
                            .frame(height: 16.875)
                            .padding(.top, 1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 9).padding(.bottom, 9).padding(.leading, 6).padding(.trailing, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            HStack(spacing: 8) {
                DeadlineActionButton(title: row.keepTitle, action: onKeep)
                DeadlineActionButton(title: row.cancelTitle, action: onKill)
            }
            .padding(.leading, 76).padding(.trailing, 13).padding(.bottom, 12)
        }
        .background(KColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: KMetric.radius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deadlines.marked")
    }
}

/// Zeile in den Klappgruppen (`.trow`): Kachel 34, Titel, rechts Text 12.5 px ink2 (max. 60 %).
private struct DeadlineListRow: View {
    let contract: Contract
    let data: AppData
    /// Vertragspartner grau hinter dem Titel (Web `titleP`)
    let partner: String
    let text: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                MarkView(contract: contract, data: data, size: 34)
                DeadlineName(title: data.title(of: contract), partner: partner)
                Spacer(minLength: 12)
                if !text.isEmpty {
                    Text(text)
                        .font(.system(size: 12.5))
                        .foregroundStyle(KColor.ink2)
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// «Quartals-Check» (`.review.rvsmall`): Radius 13, Abstand 14/15, linker Rand 3 px in Linienfarbe;
/// «Durchgehen» (tealFill), «Alles passt» und «Später» (Rahmen) je 40 px hoch.
private struct DeadlineReviewCard: View {
    let onGo: () -> Void
    let onDone: () -> Void
    let onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Quartals-Check")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(KColor.ink)
                .onbLine(14, 20.3, .bold)
            Text("Brauchst du noch alles? Geh deine Verträge kurz durch.")
                .font(.system(size: 14))
                .foregroundStyle(KColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .onbLine(14, 20.3)
                .padding(.top, 4)
                .padding(.bottom, 10)
            HStack(spacing: 8) {
                Button(action: onGo) {
                    Text("Durchgehen")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.tealFill))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("review.go")
                ghost("Alles passt", action: onDone)
                ghost("Später", action: onLater)
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .padding(.leading, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KColor.surface)
        // border-left: 3px solid var(--line) auf der gerundeten Karte
        .overlay(alignment: .leading) { KColor.line.frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: KMetric.radius, style: .continuous))
    }

    private func ghost(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(KColor.ink2)
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(KColor.line, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Quartals-Check pro Vertrag (Web openReview): Liste der laufenden Verträge, je Zeile «Brauche ich» / «Weg damit» (Pflichtvertrag: «Wechseln»);
/// «Fertig» merkt die Prüfung als erledigt. «Weg damit» landet in «Fristen» unter «Zum Kündigen vorgemerkt».
struct DeadlineReviewSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let calc = model.calc
        let list = calc.reviewList()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tippe bei jedem Vertrag, ob du ihn noch brauchst. «Weg damit» merkt ihn in «Fristen» zum Kündigen vor.")
                        .font(.footnote).foregroundStyle(KColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    if list.isEmpty {
                        Text("Keine laufenden Verträge.").font(.footnote).foregroundStyle(KColor.ink2)
                    }
                    ForEach(list) { c in
                        let v = calc.freshReview(c)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                MarkView(contract: c, data: model.data, size: 36)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(model.data.title(of: c)).font(.subheadline.weight(.semibold)).foregroundStyle(KColor.ink).lineLimit(1)
                                    Text(verbatim: DeadlineReviewSheet.line(c, calc: calc))
                                        .font(.caption).foregroundStyle(KColor.ink3).lineLimit(1)
                                }
                            }
                            HStack(spacing: 6) {
                                seg("Brauche ich", on: v == .keep) { set(c.id, .keep) }
                                seg(c.mandatory ? "Wechseln" : "Weg damit", on: v == .kill) { set(c.id, .kill) }
                            }
                        }
                        .padding(12)
                        .background(KColor.surface, in: RoundedRectangle(cornerRadius: KMetric.radius, style: .continuous))
                        .accessibilityIdentifier("review.row")
                    }
                    Button {
                        let t = model.today
                        if model.update({ $0.markReviewed(today: t) }) {
                            // Web: vorgemerkte Verträge (Weg damit, noch nicht gekündigt) nennen, sonst «Geprüft …»
                            let nk = model.data.contracts.filter { model.calc.reviewKill($0) && $0.cancelPer == nil }.count
                            let what: String = nk == 1 ? "1 Vertrag" : "\(nk) Verträge"
                            model.toast(nk > 0 ? what + " zum Kündigen vorgemerkt, siehe «Fristen»" : AppData.reviewedToast)
                        }
                        dismiss()
                    } label: {
                        Text("Fertig").font(.body.weight(.semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(KColor.tealFill, in: RoundedRectangle(cornerRadius: KMetric.radius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                    .accessibilityIdentifier("review.done")
                }
                .padding(.horizontal, KMetric.gutter).padding(.vertical, 12)
            }
            .kPageBackground()
            .navigationTitle("Quartals-Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").symbolRenderingMode(.hierarchical) }
                        .accessibilityLabel("Schliessen")
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    /// «Spotify · 12.95 CHF/Mt. · Pflichtvertrag» (Vertragspartner nur, wenn die Bezeichnung ihn nicht nennt; Web `partnerOf`)
    static func line(_ c: Contract, calc: Calc) -> String {
        let p = calc.data.partnerSuffix(of: c)
        return (p.isEmpty ? "" : p + " · ") + Format.money(calc.monthlyCost(c)) + " " + calc.home.rawValue + "/Mt."
            + (c.mandatory ? " · Pflichtvertrag" : "")
    }

    private func set(_ id: UUID, _ v: ReviewVerdict) {
        let t = model.today
        model.update { $0.setReview(id, v, today: t) }
    }

    private func seg(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? Color.white : KColor.ink)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity).frame(minHeight: 36)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? KColor.tealFill : KColor.sunken))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Kündigen aus «Fristen» (killOptions)

struct DeadlineKillTarget: Identifiable {
    let contractID: UUID
    let trial: Bool
    var id: String { "\(contractID)-\(trial)" }
}

enum DeadlineKillChoice {
    /// Kündigungsweg starten (Link, Mail, Brief, Auswahl)
    case start
    /// Als gekündigt markieren (Pflichtvertrag: neuen Vertragspartner erfassen)
    case done
}

struct DeadlineKillAction {
    let target: DeadlineKillTarget
    let choice: DeadlineKillChoice
}

/// Auswahl «Kündigen: …» (Web `killOptions`) als Fenster; die Wahl läuft erst nach dem Schliessen
/// (Kündigungsweg starten bzw. «Als gekündigt markieren», Pflichtvertrag: Formular «Neuer Vertragspartner»).
private struct DeadlineKillModifier: ViewModifier {
    @Binding var target: DeadlineKillTarget?
    @Environment(AppModel.self) private var model
    @State private var action: DeadlineKillAction?

    func body(content: Content) -> some View {
        content.sheet(item: $target, onDismiss: run) { t in
            DeadlineKillSheet(target: t) { choice in
                action = DeadlineKillAction(target: t, choice: choice)
            }
            .environment(model)
        }
    }

    private func run() {
        guard let a = action else { return }
        action = nil
        switch a.choice {
        case .start:
            model.startCancel(a.target.contractID, trial: a.target.trial)
        case .done:
            model.cancelFlowMarkCancelled(a.target.contractID, trial: a.target.trial)
        }
    }
}

extension View {
    /// «Kündigen: …» für `target` (Fristen, Probeabo-Kasten im Detail).
    func deadlineKillSheet(_ target: Binding<DeadlineKillTarget?>) -> some View {
        modifier(DeadlineKillModifier(target: target))
    }
}

private struct DeadlineKillSheet: View {
    let target: DeadlineKillTarget
    let onChoose: (DeadlineKillChoice) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let c = model.data.contract(target.contractID) {
                    options(c)
                } else {
                    Text("Dieser Vertrag existiert nicht mehr.")
                        .foregroundStyle(KColor.ink2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func options(_ c: Contract) -> some View {
        // Texte aus dem Kern (Web `killOptions`, v143/v145)
        let k = model.calc.killOptions(c, trial: target.trial)
        let title = k.title
        let firstTitle = k.startTitle
        let firstDetail = k.startDetail
        let doneTitle = k.doneTitle
        let doneDetail = k.doneDetail
        let hint = k.note
        return List {
            Section {
                Button { choose(.start) } label: { DeadlineKillRow(title: firstTitle, detail: firstDetail) }
                Button { choose(.done) } label: { DeadlineKillRow(title: doneTitle, detail: doneDetail) }
            } header: {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(KColor.ink)
                    .textCase(nil)
                    .padding(.bottom, 4)
            } footer: {
                Text(hint)
            }
            .listRowBackground(KColor.surface)
        }
        .scrollContentBackground(.hidden)
        .background(KColor.paper.ignoresSafeArea())
        .navigationTitle(k.navTitle)
    }

    private func choose(_ c: DeadlineKillChoice) {
        onChoose(c)
        dismiss()
    }
}

private struct DeadlineKillRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(KColor.ink)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            if !detail.isEmpty {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(KColor.ink2)
                    .multilineTextAlignment(.trailing)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Leerseite (emptyTerm / emptyHero, Web v224)

/// Leerseite wie `emptyHero` der Web-App: Kachel 68 (Radius 20, 12 % Teal) mit Fristen-Symbol, Titel Rounded 22 px,
/// Text 15 px, drei Punkte mit Haken, Vorschau «Als Nächstes» (nicht antippbar), Knopf «Ersten Vertrag erfassen».
private struct DeadlinesEmptyView: View {
    /// `@media (max-height: 700px)`: Vorschau ausblenden
    let showPreview: Bool
    let onCreate: () -> Void

    @Environment(AppModel.self) private var model

    static let hooks = ["Behalten oder kündigen? Du entscheidest", "Kündigung als PDF: mailen oder drucken", "Auch Probeabos und Jahresverträge"]

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(OnbColor.heroTile)
                .frame(width: 68, height: 68)
                .overlay(OnbIcon(glyph: .term, size: 34, stroke: 1.6).foregroundStyle(KColor.teal))
                .padding(.bottom, 14)
            Text(verbatim: "Nie mehr eine\nFrist verpassen")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(KColor.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .onbLine(22, 26.4, .bold, .rounded)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: "Kontivo rechnet den Kündigungstermin aus und zeigt ihn dir rechtzeitig hier unter «Fristen».")
                .font(.system(size: 15))
                .foregroundStyle(KColor.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .onbLine(15, 21.75)
                .frame(maxWidth: 303)
                .padding(.top, 8)
                .padding(.bottom, 18)
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Self.hooks, id: \.self) { h in
                    HStack(spacing: 10) {
                        OnbIcon(glyph: .heroCheck, size: 18, stroke: 2.2).foregroundStyle(KColor.teal)
                        Text(verbatim: h)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(KColor.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                            .onbLine(15, 21.75, .medium)
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.bottom, 6)
            if showPreview {
                preview
                    .padding(.top, 14)
            }
            Button(action: onCreate) {
                Text(verbatim: "Ersten Vertrag erfassen")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .onbLine(17, 24.65, .semibold)
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KColor.tealFill))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 320)
            .padding(.top, 18)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 36)
    }

    /// Illustration «Als Nächstes» (`.eprev.illu`, Deckkraft 0.9, nicht antippbar)
    private var preview: some View {
        let d = model.today.addingDays(29)
        return VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "Als Nächstes")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(KColor.ink3)
                .onbLine(11, 15.95, .bold)
                .padding(.bottom, 8)
            HStack(spacing: 11) {
                previewMark
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "Fitnessstudio")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(KColor.ink)
                        .frame(height: 21.75)
                    Text(verbatim: "Frist " + String(format: "%02d.%02d.", d.day, d.month) + " · noch 29 Tage")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(KColor.warn)
                        .frame(height: 18.125)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .overlay(alignment: .top) { Rectangle().fill(KColor.line).frame(height: 1) }
            HStack(spacing: 8) {
                previewButton("Behalten")
                previewButton("Kündigen")
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: 380)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(KColor.surface)
            .shadow(color: Color.black.opacity(0.04), radius: 1, y: 1))
        .opacity(0.9)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var previewMark: some View {
        if let cat = model.data.categories.first(where: { $0.kind == .leisure }) {
            MarkView(category: cat, size: 30)
        } else {
            MarkView(logoID: nil, logoBg: nil, colorHex: "#2E6A4E", symbol: KIcon.symbol(forKey: "Freizeit & Sport"), size: 30)
        }
    }

    private func previewButton(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(KColor.ink3)
            .onbLine(13.5, 19.575, .medium)
            .frame(maxWidth: .infinity)
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(OnbColor.previewButton))
    }
}
