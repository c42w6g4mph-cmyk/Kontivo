import SwiftUI
import EventKitUI
import KontivoCore

/// Tab «Fristen» (Variante 1): Status, eine Liste nach Datum mit «Behalten» / «Kündigen» nur bei anstehenden Fristen,
/// Karte «Flexibel», Klappgruppen und Quartals-Check.
struct DeadlinesTab: View {
    @Environment(AppModel.self) private var model
    @State private var openFolds: Set<String> = []
    @State private var killTarget: DeadlineKillTarget?
    @State private var killAction: DeadlineKillAction?
    @State private var eventRequest: DeadlineEventRequest?
    @State private var showReview = false

    var body: some View {
        let calc = model.calc
        let ov = calc.deadlineOverview()
        let review = calc.reviewDue()
        GeometryReader { geo in
            ScrollView {
                if ov.isEmpty && !review {
                    DeadlinesEmptyView(showPreview: geo.size.height > 600) {
                        model.present(.contractForm(.new(prefill: nil)))
                    }
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                } else {
                    content(ov, review: review)
                        .padding(.horizontal, KMetric.gutter)
                        .padding(.bottom, 28)
                        .kContentWidth()
                }
            }
        }
        .kPageBackground()
        .navigationTitle("Fristen")
        .sheet(item: $killTarget, onDismiss: runKillAction) { t in
            DeadlineKillSheet(target: t) { choice in
                killAction = DeadlineKillAction(target: t, choice: choice)
            }
            .environment(model)
        }
        .sheet(item: $eventRequest) { r in
            DeadlineEventEditor(request: r) { action in eventDone(action) }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showReview) {
            DeadlineReviewSheet().environment(model)
        }
    }

    // MARK: Inhalt (Web Variante 1, 06./07.10.2026)

    @ViewBuilder private func content(_ ov: Calc.DeadlineOverview, review: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let st = ov.status {
                DeadlineStatusView(status: st)
            }
            if !ov.marked.isEmpty {
                markedGroup(ov)
            }
            if !ov.items.isEmpty {
                SectionHead(title: Calc.DeadlineOverview.listTitle, trailing: Calc.DeadlineOverview.listRight)
                KCard {
                    ForEach(Array(ov.items.enumerated()), id: \.element) { item in
                        if item.offset > 0 { Divider().padding(.leading, 65) }
                        if let c = model.data.contract(item.element.contractID) {
                            DeadlineItemRow(item: item.element, contract: c, data: model.data,
                                            onOpen: { model.present(.contractDetail(c.id)) },
                                            onKeep: { keep(item.element) },
                                            onKill: { killTarget = DeadlineKillTarget(contractID: c.id, trial: item.element.trial) },
                                            onCalendar: { addToCalendar(item.element) })
                        }
                    }
                }
                .accessibilityIdentifier("deadlines.list")
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
                    .padding(.top, 14)
            }
        }
        .padding(.top, 4)
    }

    /// «Zum Kündigen vorgemerkt» (Quartals-Check): Karte mit «Doch behalten» und «Kündigen»/«Wechseln»
    @ViewBuilder private func markedGroup(_ ov: Calc.DeadlineOverview) -> some View {
        SectionHead(title: Calc.DeadlineOverview.markedTitle, trailing: Format.money(ov.markedMonthly) + " " + model.calc.home.rawValue + "/Mt.")
        VStack(spacing: 8) {
            ForEach(ov.marked, id: \.self) { m in
                if let c = model.data.contract(m.contractID) {
                    VStack(spacing: 0) {
                        Button { model.present(.contractDetail(c.id)) } label: {
                            HStack(spacing: 12) {
                                MarkView(contract: c, data: model.data, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.data.title(of: c)).font(.body.weight(.semibold)).foregroundStyle(KColor.ink).lineLimit(1)
                                    Text(verbatim: m.line).font(.footnote).foregroundStyle(KColor.ink2).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 13).padding(.top, 12).padding(.bottom, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        HStack(spacing: 8) {
                            DeadlineActionButton(title: m.keepTitle) {
                                let id = c.id
                                if model.update({ $0.clearReview(id) }) { model.toast("Bleibt") }
                            }
                            DeadlineActionButton(title: m.cancelTitle, accent: true) {
                                killTarget = DeadlineKillTarget(contractID: c.id, trial: false)
                            }
                        }
                        .padding(.horizontal, 13).padding(.bottom, 12)
                    }
                    .background(KColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: KMetric.radius, style: .continuous))
                    .accessibilityIdentifier("deadlines.marked")
                }
            }
        }
    }

    /// «Flexibel»: kurzfristig kündbare Verträge als eine Karte mit Logostapel, aufklappbar
    @ViewBuilder private func flexGroup(_ ov: Calc.DeadlineOverview) -> some View {
        let open = openFolds.contains("any")
        SectionHead(title: Calc.DeadlineOverview.flexTitle)
        KCard {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { toggleFold("any") }
            } label: {
                HStack(spacing: 12) {
                    HStack(spacing: -9) {
                        ForEach(ov.flexStack, id: \.self) { id in
                            if let c = model.data.contract(id) {
                                MarkView(contract: c, data: model.data, size: 34)
                                    .overlay(RoundedRectangle(cornerRadius: 8.5, style: .continuous).strokeBorder(KColor.surface, lineWidth: 2))
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: ov.flexCountText).font(.body.weight(.semibold)).foregroundStyle(KColor.ink)
                        Text(verbatim: Calc.DeadlineOverview.flexSubtitle).font(.footnote).foregroundStyle(KColor.ink2).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(KColor.ink3)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(open ? "aufgeklappt" : "zugeklappt")
            .accessibilityIdentifier("deadlines.flex")
            if open {
                Divider()
                Text(verbatim: Calc.DeadlineOverview.flexNote)
                    .font(.footnote).foregroundStyle(KColor.ink2)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(ov.flexible, id: \.self) { r in
                    if let c = model.data.contract(r.contractID) {
                        Divider().padding(.leading, 61)
                        Button { model.present(.contractDetail(c.id)) } label: {
                            HStack(spacing: 12) {
                                MarkView(contract: c, data: model.data, size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.data.title(of: c)).font(.body.weight(.semibold)).foregroundStyle(KColor.ink).lineLimit(1).minimumScaleFactor(0.8)
                                    Text(verbatim: r.sub).font(.footnote).foregroundStyle(KColor.ink2).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                DeadlineChip(text: r.chip, level: .none)
                            }
                            .padding(.horizontal, 13).padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    @ViewBuilder private func foldGroup(key: String, title: String, extra: String, rows: [Calc.FoldRow],
                                        chevron: Bool = false, onRow: ((Contract) -> Void)? = nil) -> some View {
        if !rows.isEmpty {
            let open = openFolds.contains(key)
            KCard {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { toggleFold(key) }
                } label: {
                    HStack {
                        Text("\(title) (\(rows.count))\(extra)")
                            .font(.subheadline)
                            .foregroundStyle(KColor.ink2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(KColor.ink3)
                            .rotationEffect(.degrees(open ? 180 : 0))
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(open ? "aufgeklappt" : "zugeklappt")
                if open {
                    ForEach(rows, id: \.self) { r in
                        if let c = model.data.contract(r.contractID) {
                            Divider().padding(.leading, 61)
                            DeadlineListRow(contract: c, data: model.data, text: r.text + (chevron ? " ›" : ""), color: KColor.ink2) {
                                if let f = onRow { f(c) } else { model.present(.contractDetail(c.id)) }
                            }
                        }
                    }
                }
            }
            .padding(.top, 10)
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

    private func keep(_ d: Calc.DeadlineItem) {
        let day = model.today
        let id = d.contractID
        let trial = d.trial
        if model.update({ $0.keep(id, trial: trial, today: day) }) {
            model.toast(AppData.keepToast)
        }
    }

    private func runKillAction() {
        guard let a = killAction else { return }
        killAction = nil
        switch a.choice {
        case .start:
            model.startCancel(a.target.contractID, trial: a.target.trial)
        case .done:
            model.cancelFlowMarkCancelled(a.target.contractID, trial: a.target.trial)
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
        guard eventRequest == nil, let c = model.data.contract(d.contractID) else { return }
        let info = DeadlineCalendar.info(trial: d.trial, date: d.date, contract: c, calc: model.calc, data: model.data)
        eventRequest = DeadlineCalendar.prepare(info)
    }

    private func eventDone(_ action: EKEventEditViewAction) {
        eventRequest = nil
        if action == .saved { model.toast("Termin im Kalender eingetragen") }
    }
}

// MARK: - Status, Zeile, Chip

/// Status zentriert unter dem Titel: Kreis mit Haken (grün) bzw. Anzahl (gelb/rot), Titel, Untertitel.
private struct DeadlineStatusView: View {
    let status: Calc.DeadlineStatus

    var body: some View {
        let col: Color = status.kind == .ok ? KColor.ok : (status.kind == .alert ? KColor.alert : KColor.warn)
        VStack(spacing: 3) {
            ZStack {
                Circle().fill(col.opacity(0.16))
                if let n = status.count {
                    Text(verbatim: String(n)).font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(col)
                } else {
                    Image(systemName: "checkmark").font(.system(size: 22, weight: .bold)).foregroundStyle(col)
                }
            }
            .frame(width: 52, height: 52)
            .padding(.bottom, 8)
            .accessibilityHidden(true)
            Text(verbatim: status.title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(KColor.ink)
                .multilineTextAlignment(.center)
            Text(verbatim: status.subtitle)
                .font(.subheadline)
                .foregroundStyle(KColor.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("deadlines.status")
    }
}

/// Chip rechts: gelb (Knöpfe sichtbar), rot (≤ 7 Tage bzw. gekündigt), grün (behalten), sonst neutral.
private struct DeadlineChip: View {
    let text: String
    let level: Calc.ChipLevel

    var body: some View {
        let col: Color? = {
            switch level {
            case .warn: return KColor.warn
            case .alert, .end: return KColor.alert
            case .ok: return KColor.ok
            case .none: return nil
            }
        }()
        Text(verbatim: text)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(col ?? KColor.ink2)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(col.map { $0.opacity(0.15) } ?? KColor.sunken))
            .fixedSize()
    }
}

/// Zeile der Liste «Fristen · nach Datum»: Logo, Titel, Unterzeile, Chip; Knöpfe nur bei `showActions`.
private struct DeadlineItemRow: View {
    let item: Calc.DeadlineItem
    let contract: Contract
    let data: AppData
    let onOpen: () -> Void
    let onKeep: () -> Void
    let onKill: () -> Void
    let onCalendar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    MarkView(contract: contract, data: data, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(data.title(of: contract))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(KColor.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(verbatim: item.sub)
                            .font(.footnote)
                            .foregroundStyle(KColor.ink2)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    DeadlineChip(text: item.chip, level: item.chipLevel)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Öffnet die Vertragsdetails")
            if item.showActions {
                HStack(spacing: 8) {
                    DeadlineActionButton(title: item.keepTitle, action: onKeep)
                    DeadlineActionButton(title: item.cancelTitle, accent: true, action: onKill)
                    Button(action: onCalendar) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(KColor.teal)
                            .frame(width: 38, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("In den Kalender eintragen")
                }
                .padding(.leading, 13 + 40 + 12)
                .padding(.trailing, 13)
                .padding(.bottom, 12)
                .padding(.top, -3)
            }
        }
    }
}

private struct DeadlineActionButton: View {
    let title: String
    var accent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent ? KColor.teal : KColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.sunken))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Zeile in den Klappgruppen: Logo, Titel, rechts Text.
private struct DeadlineListRow: View {
    let contract: Contract
    let data: AppData
    let text: String
    let color: Color
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                MarkView(contract: contract, data: data, size: 36)
                Text(data.title(of: contract))
                    .font(.body)
                    .foregroundStyle(KColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if !text.isEmpty {
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// «Quartals-Check» mit «Durchgehen» (Verträge einzeln), «Alles passt» und «Später» (Web .review, data-rv)
private struct DeadlineReviewCard: View {
    let onGo: () -> Void
    let onDone: () -> Void
    let onLater: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(KColor.teal).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text("Quartals-Check")
                    .font(.body.weight(.bold))
                    .foregroundStyle(KColor.ink)
                Text("Brauchst du noch alles? Geh deine Verträge kurz durch.")
                    .font(.subheadline)
                    .foregroundStyle(KColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)
                HStack(spacing: 8) {
                    Button(action: onGo) {
                        Text("Durchgehen")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.teal))
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(KColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: KMetric.radius, style: .continuous))
    }

    private func ghost(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(KColor.ink2)
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 12)
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
        let home = calc.home.rawValue
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
                                    Text(verbatim: Format.money(calc.monthlyCost(c)) + " " + home + "/Mt." + (c.mandatory ? " · Pflichtvertrag" : ""))
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
                        if model.update({ $0.markReviewed(today: t) }) { model.toast(AppData.reviewedToast) }
                        dismiss()
                    } label: {
                        Text("Fertig").font(.body.weight(.semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(KColor.teal, in: RoundedRectangle(cornerRadius: KMetric.radius, style: .continuous))
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
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? KColor.teal : KColor.sunken))
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
    /// Als gekündigt markieren (Pflichtvertrag: neuen Anbieter erfassen)
    case done
}

struct DeadlineKillAction {
    let target: DeadlineKillTarget
    let choice: DeadlineKillChoice
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
        let calc = model.calc
        let title = (c.mandatory ? "Wechseln: " : "Kündigen: ") + model.data.title(of: c)
        let firstTitle: String
        switch calc.cancVia(c) {
        case .online: firstTitle = "Online kündigen"
        case .mail: firstTitle = "Per E-Mail kündigen"
        case .post: firstTitle = "Kündigungsschreiben erstellen"
        case .none: firstTitle = "Kündigen: Weg wählen …"
        }
        let firstDetail = c.cancelChannel?.webText ?? ""
        let doneTitle = c.mandatory ? "Gekündigt, neuen Anbieter erfassen" : "Als gekündigt markieren"
        let per = calc.cancelEnd(c, trial: target.trial)
        let doneDetail = per.map { "läuft bis " + Format.fmtShort($0) } ?? ""
        let T: Day? = target.trial ? c.trial : calc.termEnd(c)
        var hint = ""
        if let T {
            hint = target.trial
                ? "Kündigung muss vor dem " + Format.fmtD(T) + " sein. "
                : "Kündigung muss bis " + Format.fmtD(calc.noticeDeadline(for: c, end: T)) + " beim Anbieter sein. "
        }
        hint += "Nach dem Markieren zählt der Vertrag bis zum Ende weiter und wandert danach ins Archiv."
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
        .navigationTitle(c.mandatory ? "Wechseln" : "Kündigen")
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

// MARK: - Leerseite (emptyTerm)

private struct DeadlinesEmptyView: View {
    let showPreview: Bool
    let onCreate: () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            EmptyHero(symbol: "stopwatch",
                      title: "Nie mehr eine\nFrist verpassen",
                      text: "Kontivo rechnet den Kündigungstermin aus und meldet sich rechtzeitig.",
                      hooks: ["Behalten oder kündigen? Du entscheidest",
                              "Kündigung als PDF: mailen oder drucken",
                              "Auch Probe-Abos und Jahresverträge"])
            if showPreview {
                preview
                    .padding(.horizontal, 28)
            }
            Button(action: onCreate) {
                Text("Ersten Vertrag erfassen")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 28)
            .frame(maxWidth: 420)
        }
        .padding(.vertical, 24)
    }

    /// Illustration «Als Nächstes» (nicht antippbar)
    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Als Nächstes")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(KColor.ink2)
            HStack(spacing: 12) {
                previewMark
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fitnessstudio")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(KColor.ink)
                    Text("Frist 30.11. · noch 29 Tage")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(KColor.warn)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                previewButton("Behalten")
                previewButton("Kündigen")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: 380)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(KColor.surface))
        .opacity(0.9)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var previewMark: some View {
        if let cat = model.data.categories.first(where: { $0.kind == .leisure }) {
            MarkView(category: cat, size: 40)
        } else {
            MarkView(logoID: nil, logoBg: nil, colorHex: "#2E6A4E", symbol: KIcon.symbol(forKey: "Freizeit & Sport"), size: 40)
        }
    }

    private func previewButton(_ t: String) -> some View {
        Text(t)
            .font(.footnote.weight(.medium))
            .foregroundStyle(KColor.ink3)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.sunken.opacity(0.7)))
    }
}
