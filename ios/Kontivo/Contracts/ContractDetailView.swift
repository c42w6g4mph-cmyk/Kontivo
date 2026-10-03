import SwiftUI
import KontivoCore

/// Vertragsdetail (openDetail): Kopf, Pillen, Abschnitte, Preisverlauf, Sonderzahlungen, Notiz, Dokumente und Aktionen.
struct ContractDetailView: View {
    let contractID: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var scrolled = false
    @State private var showPause = false
    @State private var askDelete = false
    @State private var moreOpen = false

    init(contractID: UUID) {
        self.contractID = contractID
    }

    var body: some View {
        NavigationStack {
            Group {
                if let c = model.data.contract(contractID) {
                    content(c)
                } else {
                    Color.clear
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bearbeiten") {
                        model.present(.contractForm(.edit(contractID)))
                    }
                    .disabled(model.data.contract(contractID) == nil)
                }
            }
        }
        .sheet(isPresented: $showPause) {
            CTPauseSheet(contractID: contractID)
                .environment(model)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CTDetailHeader(contract: c)
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: CTDetailScrollKey.self, value: g.frame(in: .named("ctDetail")).minY)
                        }
                    )
                CTDetailPills(contract: c)
                CTDetailSections(contract: c)
                actions(c)
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

    // MARK: Aktionen (Knöpfe unten)

    @ViewBuilder
    private func actions(_ c: Contract) -> some View {
        let calc = model.calc
        let archived = c.status == .cancelled
        VStack(spacing: 10) {
            if c.cancelPer != nil {
                CTActionButton(title: "Kündigung zurücknehmen") {
                    run({ $0.undoCancel(contractID) }, toast: "Kündigung zurückgenommen")
                }
            }
            if calc.isKept(c) {
                CTActionButton(title: "Entscheid «Behalten» zurücksetzen") {
                    run({ $0.unkeep(contractID) }, toast: "Wieder offen")
                }
            }
            if c.cancelPer == nil && !archived {
                CTActionButton(title: CTText.cancelButton(calc.cancVia(c)), prominent: true) {
                    model.startCancel(contractID, trial: false)
                }
            }
            if !archived {
                if calc.isPaused(c) {
                    CTActionButton(title: "Fortsetzen") {
                        let t = model.today
                        run({ $0.resume(contractID, today: t) }, toast: "Fortgesetzt")
                    }
                } else {
                    CTActionButton(title: "Pausieren") { showPause = true }
                }
            }
            DisclosureGroup(isExpanded: $moreOpen) {
                VStack(spacing: 10) {
                    CTActionButton(title: "Duplizieren") {
                        model.present(.contractForm(.duplicate(contractID)))
                    }
                    if archived {
                        CTActionButton(title: "Wieder aktiv setzen") {
                            run({ $0.reactivate(contractID) }, toast: "Wieder aktiv")
                        }
                    } else {
                        CTActionButton(title: "Als gekündigt ins Archiv") {
                            let t = model.today
                            run({ $0.archive(contractID, today: t) }, toast: "Ins Archiv verschoben")
                        }
                    }
                    CTActionButton(title: "Vertrag löschen", role: .destructive) {
                        askDelete = true
                    }
                }
                .padding(.top, 10)
            } label: {
                Text("Weitere Aktionen")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KColor.ink2)
            }
            .tint(KColor.ink2)
            .padding(.top, 6)
        }
        .padding(.top, 22)
    }

    private func run(_ change: (inout AppData) throws -> Void, toast: String) {
        if model.update(change) { model.toast(toast) }
    }

    private func deleteContract() {
        let id = contractID
        model.update { $0.deleteContract(id) }
        model.toast("Gelöscht")
        dismiss()
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
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Pillen

private struct CTDetailPills: View {
    @Environment(AppModel.self) private var model
    let contract: Contract

    var body: some View {
        let pills = CTDetailPills.pills(contract, calc: model.calc)
        if pills.isEmpty {
            Color.clear.frame(height: 10)
        } else {
            CTFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(pills.indices, id: \.self) { i in
                    Pill(text: pills[i].text, tone: pills[i].tone)
                }
            }
            .padding(.top, 12)
        }
    }

    struct Item {
        var text: String
        var tone: Pill.Tone
    }

    /// Reihenfolge wie die Web-App (spätere überschreiben), zusätzlich «Beendet am» für abgelaufene befristete Verträge.
    static func pills(_ c: Contract, calc: Calc) -> [Item] {
        var main: Item?
        let u = calc.urgency(c)
        let archived = c.status == .cancelled
        if !archived && u.level == .alert, let d = u.days {
            main = Item(text: "Frist " + Format.inDays(d), tone: .alert)
        } else if !archived && u.level == .warn, let d = u.days {
            main = Item(text: "Frist " + Format.inDays(d), tone: .warn)
        } else if archived {
            main = Item(text: "Gekündigt" + (c.cancelledAt.map { " am " + Format.fmtD($0) } ?? ""), tone: .neutral)
        }
        if let cp = c.cancelPer, !archived {
            main = Item(text: "Gekündigt · läuft bis " + Format.fmtD(cp), tone: .neutral)
        } else if calc.isKept(c) {
            main = Item(text: "Behalten bis nächster Termin", tone: .neutral)
        } else if !archived && calc.endedByTerm(c), let e = c.end {
            main = Item(text: "Beendet am " + Format.fmtD(e), tone: .neutral)
        }
        if calc.isPaused(c) {
            if let p = calc.currentPause(c) {
                main = Item(text: p.until.map { "Pausiert bis " + Format.fmtD($0) } ?? "Pausiert seit " + Format.fmtD(p.from), tone: .neutral)
            }
        }
        var out: [Item] = []
        if let m = main { out.append(m) }
        if let nc = calc.nextChange(c) {
            out.append(Item(text: "Neuer Preis ab " + Format.fmtD(nc.from) + ": " + Format.money(nc.amount) + " " + c.currency.rawValue, tone: .warn))
        }
        return out
    }
}

// MARK: - Abschnitte

private struct CTDetailSections: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let contract: Contract

    var body: some View {
        let c = contract
        let data = model.data
        let calc = model.calc
        VStack(alignment: .leading, spacing: 0) {
            CTDetailGroup(title: "Kosten", rows: costRows(c, calc: calc, data: data))
            CTDetailGroup(title: "Laufzeit & Kündigung", rows: termRows(c, calc: calc))
            assignment(c, data: data)
            contact(c, data: data)
            if !c.prices.isEmpty {
                SectionHead(title: "Preisverlauf")
                KCard(padding: 14) {
                    CTPriceChart(contract: c, today: calc.today)
                }
                priceList(c, calc: calc)
                    .padding(.top, 8)
            }
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
            if !c.documents.isEmpty {
                SectionHead(title: "Dokumente")
                KCard {
                    ForEach(Array(c.documents.enumerated()), id: \.element.id) { i, d in
                        if i > 0 { Divider().padding(.leading, 14) }
                        Button {
                            model.present(.document(DocumentRef(fileID: d.id, type: d.type, title: d.name, fileName: d.name)))
                        } label: {
                            Label {
                                Text(d.name).foregroundStyle(KColor.ink).lineLimit(1)
                            } icon: {
                                Image(systemName: CTText.isPDF(d) ? "doc.richtext" : "photo")
                                    .foregroundStyle(KColor.teal)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func costRows(_ c: Contract, calc: Calc, data: AppData) -> [CTDetailRow] {
        let home = data.settings.homeCurrency
        var r: [CTDetailRow] = [
            CTDetailRow("Betrag", Format.money(calc.curPrice(c)) + " " + c.currency.rawValue + " · " + Format.cycleTextOrMonthly(c.cycle))
        ]
        if !(c.cycleForCalc == 1 && c.currency == home) {
            r.append(CTDetailRow("Ø pro Monat", Format.money(calc.monthlyCost(c)) + " " + home.rawValue))
        }
        r.append(CTDetailRow("Pro Jahr", Format.money(calc.monthlyCost(c) * 12) + " " + home.rawValue))
        r.append(CTDetailRow("Nächste Zahlung", Format.fmtD(calc.nextDue(c))))
        return r
    }

    private func termRows(_ c: Contract, calc: Calc) -> [CTDetailRow] {
        var r: [CTDetailRow] = []
        let te = calc.termEnd(c)
        if let s = c.start { r.append(CTDetailRow("Beginn", Format.fmtD(s))) }
        if c.end != nil, let e = calc.effEnd(c) {
            let missed = te.map { $0 > e } ?? false
            r.append(CTDetailRow("Vertragsende", Format.fmtD(e) + (missed ? " · Frist verpasst" : "")))
        }
        let nt = Format.noticeText(c)
        r.append(CTDetailRow("Kündigung", (nt.isEmpty ? "ohne Frist" : nt)
            + (c.end == nil ? " · " + (c.cancelTerm != .anytime ? "auf " + Format.termText(c.cancelTerm) : "jederzeit") : "")))
        let u = calc.urgency(c)
        if let d = u.date, let T = te, c.cancelPer == nil, calc.isActive(c) {
            let txt = "per " + Format.fmtShort(T) + ", kündigen bis " + Format.fmtShort(d)
            if calc.isAnytime(c) {
                r.append(CTDetailRow("Nächste Gelegenheit", txt))
            } else {
                let days = u.days ?? 0
                r.append(CTDetailRow("Nächster Termin", txt + (days >= 0 ? " (" + Format.inDays(days) + ")" : " (abgelaufen)")))
            }
        }
        if c.mandatory { r.append(CTDetailRow("Pflichtvertrag", "nur Wechsel möglich")) }
        if c.noWatch { r.append(CTDetailRow("Frist", "wird nicht beobachtet")) }
        if let rt = calc.renewTo(c) {
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
        let hn = data.holderNames(of: c)
        if !hn.isEmpty { rows.append(CTDetailRow("Inhaber", hn.joined(separator: " & "))) }
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

    private func priceList(_ c: Contract, calc: Calc) -> some View {
        let ps = calc.pricesOf(c)
        var ni = -1
        for (i, p) in ps.enumerated() where p.from <= calc.today { ni = i }
        return KCard {
            CTPriceRow(label: c.start.map { "ab " + Format.fmtD($0) } ?? "Anfangspreis",
                       amount: Format.money(c.amount) + " " + c.currency.rawValue,
                       tag: ni < 0 ? .current : nil, isCurrent: ni < 0)
            ForEach(Array(ps.enumerated()), id: \.offset) { i, p in
                Divider().padding(.leading, 14)
                CTPriceRow(label: "ab " + Format.fmtD(p.from),
                           amount: Format.money(p.amount) + " " + c.currency.rawValue,
                           tag: i == ni ? .current : (p.from > calc.today ? .planned : nil),
                           isCurrent: i == ni)
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
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
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
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(r.label)
                    .font(.subheadline)
                    .foregroundStyle(KColor.ink2)
                Spacer(minLength: 8)
                Text(r.value)
                    .font(.body)
                    .foregroundStyle(KColor.ink)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .accessibilityElement(children: .combine)
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
            Text((cr ? Format.minus : "") + Format.money(abs(extra.amount)) + " " + currency)
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
