import SwiftUI
import KontivoCore

/// Vertragsdetail (openDetail) als reine Ansicht (Web v125–v141): Kopf mit Dokumente-Knopf, Pillen, Kennzahlen,
/// Hinweis «Angaben fehlen», Fristen-Kasten (nur bei Frist ≤ 60 Tage), Abschnitte mit Preisverlauf, Sonderzahlungen, Notiz.
/// Aktionen im Menü ••• oben (Web 4be2078). Bearbeiten (inkl. Preise, Dokumente löschen) nur im Formular.
struct ContractDetailView: View {
    let contractID: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var scrolled = false
    @State private var showPause = false
    @State private var askDelete = false
    @State private var showDocs = false
    @State private var calendarFor: UUID?

    init(contractID: UUID) {
        self.contractID = contractID
    }

    var body: some View {
        NavigationStack {
            Group {
                if let c = model.data.contract(contractID) {
                    content(c)
                } else {
                    // z.B. gerade gelöscht: Hinweis statt leerer Seite
                    Text("Dieser Vertrag existiert nicht mehr.")
                        .font(.subheadline)
                        .foregroundStyle(KColor.ink2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(KColor.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schliessen") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Text(model.data.contract(contractID).map { model.data.title(of: $0) } ?? "")
                        .font(.headline)
                        .lineLimit(1)
                        .opacity(scrolled ? 1 : 0)
                        .animation(.easeInOut(duration: 0.15), value: scrolled)
                        .accessibilityHidden(!scrolled)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let c = model.data.contract(contractID) {
                        actionsMenu(c)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bearbeiten") {
                        model.present(.contractForm(.edit(contractID)))
                    }
                    .disabled(model.data.contract(contractID) == nil)
                }
            }
        }
        .deadlineCalendar(contractID: $calendarFor)
        .sheet(isPresented: $showPause) {
            CTPauseSheet(contractID: contractID, onPaused: { model.dismissAll() })
                .environment(model)
        }
        .sheet(isPresented: $showDocs) {
            CTDetailDocsSheet(contractID: contractID)
                .environment(model)
                .environment(\.locale, Locale(identifier: "de_CH"))
                .presentationDetents([.medium, .large])
        }
        .alert("Vertrag löschen?", isPresented: $askDelete) {
            Button("Löschen", role: .destructive) { deleteContract() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("«" + (model.data.contract(contractID).map { model.data.title(of: $0) } ?? "") + "» wird endgültig gelöscht. Angehängte Dateien bleiben erhalten.")
        }
    }

    // MARK: Inhalt

    private func content(_ c: Contract) -> some View {
        let calc = model.calc
        let due60 = CTDetailState.due60(c, calc: calc)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CTDetailHeader(contract: c) { showDocs = true }
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: CTDetailScrollKey.self, value: g.frame(in: .named("ctDetail")).minY)
                        }
                    )
                CTDetailPills(contract: c, due60: due60)
                CTDetailKeyFigures(contract: c)
                CTDetailCompletenessHint(contract: c)
                if due60 {
                    CTDetailDeadlineBox(contract: c, onCancel: { model.startCancel(contractID, trial: false) }, onKeep: {
                        let t = model.today
                        run({ $0.keep(contractID, trial: false, today: t) }, toast: AppData.keepToast)
                    })
                }
                if calc.specialCancelHint(c) {
                    Text(verbatim: Calc.specialCancelText)
                        .font(.footnote).foregroundStyle(KColor.ink2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 9).padding(.horizontal, 12)
                        .background(KColor.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.bottom, 10)
                        .accessibilityIdentifier("detail.skr")
                }
                CTDetailSections(contract: c, due60: due60)
            }
            .padding(.horizontal, KMetric.gutter)
            .padding(.bottom, 32)
            .kContentWidth()
        }
        .coordinateSpace(name: "ctDetail")
        .onPreferenceChange(CTDetailScrollKey.self) { y in
            let s = y < -60
            if s != scrolled { scrolled = s }
        }
    }

    // MARK: Menü ••• (Web 4be2078): Kündigen mit Weg, Pausieren, Duplizieren, Archiv, Löschen

    private func actionsMenu(_ c: Contract) -> some View {
        let calc = model.calc
        let fixd = calc.isFixed(c)
        let archived = c.status == .cancelled
        let kok = !(c.cancelPer != nil || archived || fixd)
        let kword = c.mandatory ? "Wechseln" : "Kündigen"
        let via: String = {
            switch calc.cancVia(c) {
            case .online: return "online"
            case .mail: return "per E-Mail"
            case .post: return "per Brief"
            case .none: return "Weg wählen"
            }
        }()
        return Menu {
            if kok {
                Button {
                    model.startCancel(contractID, trial: false)
                } label: {
                    Text(kword)
                    Text(via)
                }
            }
            if c.cancelPer != nil {
                Button("Kündigung zurücknehmen") {
                    run({ $0.undoCancel(contractID) }, toast: "Kündigung zurückgenommen")
                }
            }
            if calc.isKept(c) {
                Button("«Behalten» zurücksetzen") {
                    run({ $0.unkeep(contractID) }, toast: "Wieder offen")
                }
            }
            if !archived && !fixd && !c.mandatory && !calc.isRent(c) {
                if calc.isPaused(c) {
                    Button("Fortsetzen") {
                        let t = model.today
                        run({ $0.resume(contractID, today: t) }, toast: "Fortgesetzt")
                    }
                } else {
                    Button("Pausieren") { showPause = true }
                }
            }
            if DeadlineCalendar.canAdd(c, calc: model.calc) {
                Button { calendarFor = c.id } label: { Label(DeadlineCalendar.menuTitle, systemImage: DeadlineCalendar.symbol) }
            }
            Button("Duplizieren") {
                model.present(.contractForm(.duplicate(contractID)))
            }
            if archived {
                Button("Wieder aktiv setzen") {
                    run({ $0.reactivate(contractID) }, toast: "Wieder aktiv")
                }
            } else {
                Button("Ins Archiv") {
                    let t = model.today
                    run({ $0.archive(contractID, today: t) }, toast: "Ins Archiv verschoben")
                }
            }
            Button("Löschen", role: .destructive) {
                askDelete = true
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .accessibilityLabel("Aktionen")
        }
        .accessibilityIdentifier("detail.menu")
    }

    /// Aktion ausführen; danach schliessen wie Web (`closeSheets(); render(); toast(…)`)
    private func run(_ change: (inout AppData) throws -> Void, toast: String) {
        guard model.update(change) else { return }
        model.dismissAll()
        model.toast(toast)
    }

    private func deleteContract() {
        let id = contractID
        model.update { $0.deleteContract(id) }
        model.toast("Gelöscht")
        dismiss()
    }
}

/// Zustände, die mehrere Teile des Details brauchen
enum CTDetailState {
    /// Gekündigt (Archiv oder «gekündigt per») oder abgelaufen: keine Frist und kein nächster Termin mehr
    static func gone(_ c: Contract, calc: Calc) -> Bool {
        c.status == .cancelled || c.cancelPer != nil || calc.endedByTerm(c)
    }

    /// Frist in ≤ 60 Tagen: Kasten «Kündigen bis …» mit Kündigen/Behalten oben (Web due60)
    static func due60(_ c: Contract, calc: Calc) -> Bool {
        if gone(c, calc: calc) || calc.isFixed(c) { return false }
        let u = calc.urgency(c)
        guard u.date != nil, let d = u.days, d >= 0, d <= 60 else { return false }
        return !calc.isAnytime(c) && !c.noWatch && c.cancelPer == nil && !calc.isKept(c) && calc.termEnd(c) != nil
    }
}

private struct CTDetailScrollKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Rahmen-Knopf volle Breite (wie .ghost der Web-App)
struct CTActionButton: View {
    let title: String
    var prominent = false
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .foregroundStyle(role == .destructive ? KColor.alert : KColor.teal)
                .background(
                    RoundedRectangle(cornerRadius: KMetric.radius, style: .continuous)
                        .fill(prominent ? KColor.teal.opacity(0.08) : KColor.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: KMetric.radius, style: .continuous)
                        .strokeBorder(role == .destructive ? KColor.alert.opacity(0.45) : KColor.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Kopf

private struct CTDetailHeader: View {
    @Environment(AppModel.self) private var model
    let contract: Contract
    let onDocs: () -> Void

    var body: some View {
        let data = model.data
        HStack(alignment: .center, spacing: 14) {
            MarkView(contract: contract, data: data, size: 76)
            VStack(alignment: .leading, spacing: 3) {
                Text(data.title(of: contract))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(KColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                let meta = data.meta(of: contract)
                if !meta.isEmpty {
                    Text(meta)
                        .font(.footnote)
                        .foregroundStyle(KColor.ink2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            CTDetailDocsButton(count: contract.documents.count, action: onDocs)
        }
        .padding(.top, 12)
    }
}

// MARK: - Pillen

private struct CTDetailPills: View {
    @Environment(AppModel.self) private var model
    let contract: Contract
    let due60: Bool

    var body: some View {
        let pills = CTDetailPills.pills(contract, calc: model.calc, due60: due60)
        if pills.isEmpty {
            Color.clear.frame(height: 10)
        } else {
            CTFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(pills.indices, id: \.self) { i in
                    Pill(text: pills[i].text, tone: pills[i].tone)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
    }

    struct Item {
        var text: String
        var tone: Pill.Tone
    }

    /// Rangfolge wie die Web-App (openDetail): Archiv → gekündigt per → befristet abgelaufen → behalten → Frist rot/orange;
    /// Frist-Pille entfällt, wenn der Kasten «Kündigen bis …» erscheint; «Pausiert …» nur bei nicht gekündigten/abgelaufenen Verträgen.
    static func pills(_ c: Contract, calc: Calc, due60: Bool) -> [Item] {
        var main: Item?
        let archived = c.status == .cancelled
        let gone = CTDetailState.gone(c, calc: calc)
        let fixd = calc.isFixed(c)
        let u = calc.urgency(c)
        if archived {
            main = Item(text: "Gekündigt" + (c.cancelledAt.map { " am " + Format.fmtD($0) } ?? ""), tone: .neutral)
        } else if let cp = c.cancelPer {
            main = Item(text: "Gekündigt · " + (calc.endedByNotice(c) ? "beendet am " : "läuft bis ") + Format.fmtD(cp), tone: .neutral)
        } else if calc.endedByTerm(c), let e = c.end {
            main = Item(text: "Beendet am " + Format.fmtD(e), tone: .neutral)
        } else if calc.reviewKill(c) {
            main = Item(text: "Zum Kündigen vorgemerkt", tone: .warn)
        } else if calc.isKept(c) {
            main = Item(text: "Behalten bis nächster Termin", tone: .neutral)
        } else if !fixd && !due60 && u.level == .alert, let d = u.days {
            main = Item(text: "Frist " + Format.inDays(d), tone: .alert)
        } else if !fixd && !due60 && u.level == .warn, let d = u.days {
            main = Item(text: "Frist " + Format.inDays(d), tone: .warn)
        }
        if !gone && main == nil && fixd {
            main = Item(text: "Nicht kündbar", tone: .neutral)
        }
        if !gone && calc.isPaused(c), let p = calc.currentPause(c) {
            main = Item(text: p.until.map { "Pausiert bis " + Format.fmtD($0) } ?? "Pausiert seit " + Format.fmtD(p.from), tone: .neutral)
        }
        var out: [Item] = []
        if let m = main { out.append(m) }
        if let nc = calc.nextChange(c) {
            out.append(Item(text: "Neuer Preis ab " + Format.fmtD(nc.from) + ": " + Format.money(nc.amount, c.currency) + " " + c.currency.rawValue, tone: .warn))
        }
        return out
    }
}

// MARK: - Abschnitte

private struct CTDetailSections: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let contract: Contract
    let due60: Bool

    var body: some View {
        let c = contract
        let data = model.data
        let calc = model.calc
        VStack(alignment: .leading, spacing: 0) {
            // Kosten: Zeilen und Preisverlauf (nur Ansicht; Preise erfassen nur unter «Bearbeiten»)
            SectionHead(title: "Kosten")
            let cr = costRows(c, calc: calc)
            if !cr.isEmpty {
                KCard { CTDetailRowsView(rows: cr) }
            }
            if !calc.pricesOf(c).isEmpty {
                CTPriceChart(contract: c, today: calc.today)
                    .padding(.top, cr.isEmpty ? 0 : 8)
            }
            CTDetailGroup(title: "Laufzeit & Kündigung", rows: termRows(c, calc: calc))
            assignment(c, data: data)
            contact(c, data: data)
            let xs = calc.extrasOf(c)
            if !xs.isEmpty {
                SectionHead(title: "Sonderzahlungen")
                CTExtrasList(extras: xs, currency: c.currency.rawValue, today: calc.today, onDelete: nil)
            }
            if !c.note.isEmpty {
                SectionHead(title: "Notiz")
                Text(c.note)
                    .font(.body)
                    .foregroundStyle(KColor.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: KMetric.radius, style: .continuous).fill(KColor.surface))
            }
        }
    }

    /// Web: «Betrag» nur bei nicht monatlicher Zahlung; «Zahlung» = Zahlungsregel (+ «nächste am …»)
    private func costRows(_ c: Contract, calc: Calc) -> [CTDetailRow] {
        var r: [CTDetailRow] = []
        if c.cycleForCalc != 1 {
            r.append(CTDetailRow("Betrag", Format.money(calc.curPrice(c), c.currency) + " " + c.currency.rawValue))
        }
        let rule = Calc.payRule(cycle: c.cycle, due: c.due)
        if !rule.isEmpty {
            var row = CTDetailRow("Zahlung", rule)
            if c.cycleForCalc != 1, let nd = calc.nextDue(c), CTDetailKeyFigures.paidSoFar(c, calc: calc) != nil {
                row.sub = "nächste am " + Format.fmtShort(nd)
            }
            r.append(row)
        }
        return r
    }

    private func termRows(_ c: Contract, calc: Calc) -> [CTDetailRow] {
        var r: [CTDetailRow] = []
        let te = calc.termEnd(c)
        let gone = CTDetailState.gone(c, calc: calc)
        let fixed = calc.isFixed(c)
        if let s = c.start { r.append(CTDetailRow("Beginn", Format.fmtD(s))) }
        if c.end != nil, let e = calc.effEnd(c) {
            let missed = !gone && (te.map { $0 > e } ?? false)
            r.append(CTDetailRow("Vertragsende", Format.fmtD(e) + (missed ? " · Frist verpasst" : "")))
        }
        let nt = Format.noticeText(c)
        if fixed {
            r.append(CTDetailRow("Kündigung", calc.isTax(c) ? "nicht kündbar · Steuern & Gebühren" : "nicht kündbar"))
        } else {
            r.append(CTDetailRow("Kündigung", (nt.isEmpty ? "ohne Frist" : nt)
                + (c.end == nil ? " · " + (c.cancelTerm != .anytime ? "auf " + Format.termText(c.cancelTerm) : "jederzeit") : "")))
        }
        let u = calc.urgency(c)
        if !gone && !fixed && !due60, let d = u.date {
            let days = u.days ?? 0
            if days >= 0, let T = te {
                // Mini-Zeitstrahl heute → kündigen bis → Ende (Web termLine)
                r.append(CTDetailRow(timeline: CTTimeline(today: calc.today, deadline: d, end: T, anytime: calc.isAnytime(c), days: days)))
            } else if let T = te {
                r.append(CTDetailRow("Nächster Termin", "per " + Format.fmtShort(T) + ", kündigen bis " + Format.fmtShort(d) + " (abgelaufen)"))
            }
        }
        if c.mandatory && !fixed { r.append(CTDetailRow("Pflichtvertrag", "nur Wechsel möglich")) }
        if c.noWatch && !fixed { r.append(CTDetailRow("Frist", "wird nicht beobachtet")) }
        if fixed {
            // keine Verlängerungs-Zeilen
        } else if !gone, let rt = calc.renewTo(c) {
            r.append(CTDetailRow("Sonst verlängert bis", Format.fmtD(rt)))
        } else if c.renewMonths > 0 {
            r.append(CTDetailRow("Verlängerung", "automatisch um \(c.renewMonths)" + (c.renewMonths == 1 ? " Monat" : " Monate")))
        }
        if let ch = c.cancelChannel { r.append(CTDetailRow("Kündigung per", ch.webText)) }
        if c.cancelPer != nil, let on = c.cancelledOn { r.append(CTDetailRow("Gekündigt am", Format.fmtD(on))) }
        if let tr = c.trial { r.append(CTDetailRow("Probeabo endet", Format.fmtD(tr))) }
        return r
    }

    private func assignmentRows(_ c: Contract, data: AppData) -> [CTDetailRow] {
        var rows: [CTDetailRow] = []
        if let cat = data.category(c.categoryID) { rows.append(CTDetailRow("Kategorie", cat.name)) }
        let hn = data.holdersText(of: c)
        if !hn.isEmpty { rows.append(CTDetailRow(c.holderIDs.count > 1 ? "Personen" : "Person", hn)) }
        if !c.customerNo.isEmpty { rows.append(CTDetailRow("Kundennummer", c.customerNo)) }
        if !c.contractNo.isEmpty { rows.append(CTDetailRow("Vertragsnummer", c.contractNo)) }
        if !c.payMethod.isEmpty { rows.append(CTDetailRow("Zahlungsart", c.payMethod)) }
        if !c.payAccount.isEmpty { rows.append(CTDetailRow("Belastet über", c.payAccount)) }
        return rows
    }

    @ViewBuilder
    private func assignment(_ c: Contract, data: AppData) -> some View {
        let partner = data.partner(c.partnerID)
        let rows = assignmentRows(c, data: data)
        if partner != nil || !rows.isEmpty {
            SectionHead(title: "Zuordnung")
            KCard {
                if let p = partner, !p.name.isEmpty {
                    Button {
                        model.present(.manage(.partner(p.id)))
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("Vertragspartner")
                                .font(.subheadline)
                                .foregroundStyle(KColor.ink2)
                            Spacer(minLength: 8)
                            Text(p.name + " ›")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(KColor.teal)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Öffnet den Vertragspartner")
                    if !rows.isEmpty { Divider().padding(.leading, 14) }
                }
                CTDetailRowsView(rows: rows)
            }
        }
    }

    @ViewBuilder
    private func contact(_ c: Contract, data: AppData) -> some View {
        let web = data.partner(c.partnerID)?.web.trimmingCharacters(in: .whitespaces) ?? ""
        let tel = c.tel.trimmingCharacters(in: .whitespaces)
        let mail = c.mail.trimmingCharacters(in: .whitespaces)
        if !web.isEmpty || !tel.isEmpty || !mail.isEmpty {
            SectionHead(title: "Kontakt")
            KCard {
                if !web.isEmpty {
                    linkRow("Website", CTDetailSections.stripScheme(web), url: URL(string: Format.normUrl(web)))
                }
                if !tel.isEmpty {
                    if !web.isEmpty { Divider().padding(.leading, 14) }
                    linkRow("Telefon", tel, url: URL(string: "tel:" + tel.filter { !$0.isWhitespace }))
                }
                if !mail.isEmpty {
                    if !web.isEmpty || !tel.isEmpty { Divider().padding(.leading, 14) }
                    linkRow("E-Mail", mail, url: URL(string: "mailto:" + mail))
                }
            }
        }
    }

    private func linkRow(_ label: String, _ value: String, url: URL?) -> some View {
        Button {
            if let u = url { openURL(u) }
        } label: {
            HStack(spacing: 12) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(KColor.ink2)
                Spacer(minLength: 8)
                Text(value)
                    .font(.body)
                    .foregroundStyle(KColor.teal)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                UIPasteboard.general.string = value
            } label: {
                Label("Kopieren", systemImage: "doc.on.doc")
            }
        }
    }

    static func stripScheme(_ s: String) -> String {
        var t = s
        for p in ["https://", "http://", "HTTPS://", "HTTP://"] where t.hasPrefix(p) {
            t = String(t.dropFirst(p.count))
        }
        return t
    }
}

// MARK: - Zeilen

struct CTDetailRow: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    /// Zusatz unter dem Wert (z.B. «nächste am 15.10.26»)
    var sub = ""
    var timeline: CTTimeline?
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
    init(timeline: CTTimeline) {
        label = ""
        value = ""
        self.timeline = timeline
    }
}

/// Nächste Kündigung als Zeitstrahl: Punkt heute, Frist (teal, anteilig 28–62 %), Vertragsende (Ring)
struct CTTimeline {
    let today: Day
    let deadline: Day
    let end: Day
    let anytime: Bool
    let days: Int

    var position: CGFloat {
        let tot = max(1, today.days(to: end))
        let p = Int(Format.jsRound(Double(today.days(to: deadline)) / Double(tot) * 100))
        return CGFloat(max(28, min(62, p))) / 100
    }

    /// «noch 55 Tage», ab 61 Tagen in Monaten, «heute»; leer bei jederzeit kündbaren Verträgen
    var remaining: String {
        if anytime { return "" }
        if days == 0 { return "heute" }
        if days <= 60 { return "noch \(days)" + (days == 1 ? " Tag" : " Tage") }
        let m = Int(Format.jsRound(Double(days) / 30.44))
        return "noch \(m)" + (m == 1 ? " Monat" : " Monate")
    }

    var urgent: Bool { !anytime && days <= 7 }
}

private struct CTTimelineView: View {
    let t: CTTimeline

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Nächste Kündigung").font(.footnote).foregroundStyle(KColor.ink2)
                Spacer()
                Text(verbatim: t.remaining).font(.footnote.weight(t.urgent ? .semibold : .regular))
                    .foregroundStyle(t.urgent ? KColor.alert : KColor.ink2)
            }
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Rectangle().fill(KColor.line).frame(height: 2).padding(.horizontal, 6)
                    Circle().fill(KColor.ink3).frame(width: 8, height: 8).offset(x: 2)
                    Circle().fill(KColor.teal).frame(width: 12, height: 12).offset(x: w * t.position - 6)
                    Circle().strokeBorder(KColor.ink, lineWidth: 2).frame(width: 12, height: 12).offset(x: w - 12)
                }
                .frame(height: 14)
            }
            .frame(height: 14)
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .topLeading) {
                    Text("heute").font(.footnote).foregroundStyle(KColor.ink3)
                    label(Format.fmtShort(t.deadline), "kündigen bis", align: .center)
                        .fixedSize()
                        .position(x: w * t.position, y: 17)
                    HStack { Spacer(); label(Format.fmtShort(t.end), "Ende", align: .trailing) }
                }
            }
            .frame(height: 36)
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Nächste Kündigung: bis " + Format.fmtD(t.deadline) + " kündigen, Vertragsende " + Format.fmtD(t.end)
                                 + (t.remaining.isEmpty ? "" : ", " + t.remaining)))
    }

    private func label(_ date: String, _ sub: String, align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 1) {
            Text(verbatim: date).font(.footnote.weight(.semibold)).foregroundStyle(KColor.ink).monospacedDigit()
            Text(verbatim: sub).font(.caption2).foregroundStyle(KColor.ink2)
        }
    }
}

/// Abschnitt mit Kopf und Zeilen «Bezeichnung | Wert»; entfällt ohne Zeilen
private struct CTDetailGroup: View {
    let title: String
    let rows: [CTDetailRow]
    var body: some View {
        if !rows.isEmpty {
            SectionHead(title: title)
            KCard {
                CTDetailRowsView(rows: rows)
            }
        }
    }
}

private struct CTDetailRowsView: View {
    let rows: [CTDetailRow]
    var body: some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
            if i > 0 { Divider().padding(.leading, 14) }
            if let tl = r.timeline {
                CTTimelineView(t: tl)
            } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(r.label)
                    .font(.subheadline)
                    .foregroundStyle(KColor.ink2)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(r.value)
                        .font(.body)
                        .foregroundStyle(KColor.ink)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .textSelection(.enabled)
                    if !r.sub.isEmpty {
                        Text(r.sub)
                            .font(.footnote)
                            .foregroundStyle(KColor.ink2)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Zeile im Preisverlauf bzw. in den Preisänderungen
struct CTPriceRow: View {
    enum Tag { case current, planned }
    let label: String
    let amount: String
    var tag: Tag?
    var isCurrent = false
    var onDelete: (() -> Void)? = nil
    var hPad: CGFloat = 14

    var body: some View {
        HStack(spacing: 10) {
            if isCurrent {
                RoundedRectangle(cornerRadius: 1.5).fill(KColor.teal).frame(width: 3, height: 22)
            }
            Text(label).foregroundStyle(KColor.ink)
            if let t = tag {
                switch t {
                case .current: CTMiniTag(text: "aktuell")
                case .planned: CTMiniTag(text: "geplant", tone: KColor.warn)
                }
            }
            Spacer(minLength: 8)
            Text(amount)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(KColor.ink)
            if let del = onDelete {
                Button(action: del) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(KColor.ink3).imageScale(.large)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Entfernen")
            }
        }
        .padding(.horizontal, hPad).padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }
}

/// Liste der Sonderzahlungen (Detail ohne, Formular mit Löschknopf)
struct CTExtrasList: View {
    let extras: [ExtraPayment]
    let currency: String
    let today: Day
    var onDelete: ((ExtraPayment) -> Void)?
    var framed = true

    var body: some View {
        if framed {
            KCard { rows }
        } else {
            rows
        }
    }

    @ViewBuilder private var rows: some View {
        ForEach(Array(extras.enumerated()), id: \.element.id) { i, x in
            if i > 0 && framed { Divider().padding(.leading, 14) }
            CTExtraRow(extra: x, currency: currency, today: today, onDelete: deleteAction(x))
                .padding(.horizontal, framed ? 14 : 0)
        }
    }

    private func deleteAction(_ x: ExtraPayment) -> (() -> Void)? {
        guard let f = onDelete else { return nil }
        return { f(x) }
    }
}

struct CTExtraRow: View {
    let extra: ExtraPayment
    let currency: String
    let today: Day
    var onDelete: (() -> Void)?

    var body: some View {
        let cr = extra.amount < 0
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Format.fmtD(extra.date) + (extra.note.isEmpty ? "" : " · " + extra.note))
                    .foregroundStyle(KColor.ink)
                if cr || extra.date > today {
                    HStack(spacing: 4) {
                        if cr { CTMiniTag(text: "Gutschrift", tone: KColor.ok) }
                        if extra.date > today { CTMiniTag(text: "geplant", tone: KColor.warn) }
                    }
                }
            }
            Spacer(minLength: 8)
            Text((cr ? Format.minus : "") + Format.money(abs(extra.amount), Currency(rawValue: currency)) + " " + currency)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(cr ? KColor.ok : KColor.ink)
            if let del = onDelete {
                Button(action: del) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(KColor.ink3).imageScale(.large)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Entfernen")
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: onDelete == nil ? AccessibilityChildBehavior.combine : .contain)
    }
}
