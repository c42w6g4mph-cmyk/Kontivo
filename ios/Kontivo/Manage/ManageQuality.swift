import SwiftUI
import KontivoCore

// MARK: - Übersicht

/// Datenqualität (paintMdQual): Status-Karte, Checkliste «Was geprüft wird», Ignorierte
struct MDQualityPage: View {
    @Environment(AppModel.self) private var model

    /// Web `paintMdQual`: Kopfkarte `.qtop`, Checkliste `.qcrit` mit Gruppen `.qgrp` (Karten statt Systemliste, 1:1 Web)
    var body: some View {
        let r = model.mdQualityReport
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let h = Quality.headline(r) {
                    statusCard(h)
                        .padding(.bottom, 14)
                    checklist(r)
                } else {
                    // Web `.qok`
                    Text(Quality.emptyText)
                        .font(KFont.text(14))
                        .foregroundStyle(KColor.ink2)
                        .kLineHeight(14, 20.3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 6)
                }
                if let ig = Quality.ignoredText(r) {
                    // Web `.note` margin 14px 4px 0
                    HStack(spacing: 4) {
                        Text(ig + " ·").foregroundStyle(KColor.ink2)
                        Button("Zurücksetzen") {
                            model.update { $0.resetQualityIgnored() }
                        }
                        .buttonStyle(.plain)
                        .fontWeight(.medium)
                        .foregroundStyle(KColor.teal)
                    }
                    .font(KFont.text(12.5))
                    .padding(.top, 14).padding(.horizontal, 4)
                }
            }
            .mdScrollPage()
        }
        .mdScrollStyle()
        .navigationTitle("Datenqualität")
    }

    /// Web `.qtop`: Radius 14, Innenabstand 14, Fläche Warnfarbe 10 % über `--field` (sauber: `.qtop.ok` mit grünem Haken)
    private func statusCard(_ h: (title: String, text: String, clean: Bool)) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if h.clean {
                KIcon.view("ic.check.hook", 22)
                    .foregroundStyle(Color.white)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(KColor.ok))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(h.title).font(KFont.text(16, .bold)).foregroundStyle(KColor.ink)
                    .kLineHeight(16, 23.2)
                Text(h.text).font(KFont.text(13.5)).foregroundStyle(KColor.ink2)
                    .kLineHeight(13.5, 19.575)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(h.clean ? KColor.qualOkFill : KColor.qualWarnFill))
        .accessibilityElement(children: .combine)
    }

    /// Web `.qcrit`: Fläche `--field`, Radius 14, Innenabstand 14/14/12; Kopf «Was geprüft wird» 15 pt Bold
    private func checklist(_ r: QualityReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Quality.checklistTitle).font(KFont.text(15, .bold)).foregroundStyle(KColor.ink)
                Spacer(minLength: 0)
                Text(Quality.checklistSubtitle(r)).font(KFont.text(12, .medium)).foregroundStyle(KColor.ink3)
            }
            .kLineHeight(15, 21.75)
            .padding(.bottom, 4)
            ForEach(Quality.checklist, id: \.group) { g in
                group(g, r).padding(.top, 10)
            }
            MDHint(Quality.footnote)
                .padding(.top, 10)
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KColor.field))
    }

    /// Web `.qgrp`: weiss, Radius 11, Innenabstand 4/12/2; Kopf `.qgh` 14 pt Bold mit Pille «vollständig»
    private func group(_ g: QualityChecklistGroup, _ r: QualityReport) -> some View {
        let rows = g.rows.filter { $0.field != "inc" || r.incomeCount > 0 }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(g.title).font(KFont.text(14, .bold)).foregroundStyle(KColor.ink)
                    .kLineHeight(14, 20.3)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if r.issues(g.group).isEmpty {
                    Text(Quality.completeBadge)
                        .font(KFont.text(12, .semibold))
                        .foregroundStyle(KColor.ok)
                        .kLineHeight(12, 17.4)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(KColor.ok.opacity(0.12)))
                }
            }
            .padding(.top, 8).padding(.bottom, 6)
            ForEach(rows, id: \.field) { row in
                KDivider()
                checkRow(g.group, row, r.select(g.group, field: row.field).count)
            }
        }
        .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 2)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(KColor.surface)
                .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
        )
    }

    /// Web `.qcrit li` (6 pt oben/unten, 13.5 pt `--ink2`, ✓ grün) bzw. `li.w button` (8 pt, `--ink`, «n offen» Messing, ›)
    @ViewBuilder private func checkRow(_ g: QualityGroup, _ row: QualityChecklistRow, _ m: Int) -> some View {
        if m > 0 {
            NavigationLink(value: ManagePage.qualityList(g, row.field, row.title)) {
                HStack(spacing: 6) {
                    Text(row.title).foregroundStyle(KColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(m) offen").fontWeight(.semibold).foregroundStyle(KColor.warn)
                    // Web `i` mit line-height 1 → 17 hoch
                    Text("›").font(KFont.text(17)).foregroundStyle(KColor.ink3).frame(height: 17)
                }
                .font(KFont.text(13.5))
                .kLineHeight(13.5, 19.575)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            HStack {
                Text(row.title).foregroundStyle(KColor.ink2)
                Spacer(minLength: 8)
                Text("✓").fontWeight(.semibold).foregroundStyle(KColor.ok)
            }
            .font(KFont.text(13.5))
            .kLineHeight(13.5, 19.575)
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
    }
}

extension KColor {
    /// Web `.qtop`: `color-mix(--warn 10%, --field)`
    static let qualWarnFill = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(rgb: KColor.mix(0xC6AB78, 0x414246, 0.10)) : UIColor(rgb: KColor.mix(0x86671F, 0xF1F1EF, 0.10))
    })
    /// Web `.qtop.ok`: `color-mix(--ok 11%, --field)`
    static let qualOkFill = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(rgb: KColor.mix(0x7DBF98, 0x414246, 0.11)) : UIColor(rgb: KColor.mix(0x2E6A4E, 0xF1F1EF, 0.11))
    })
}

// MARK: - Liste je Kriterium

/// Offene Einträge eines Kriteriums mit Inline-Editoren (MD_PAGES.qlist)
struct MDQualityListPage: View {
    let group: QualityGroup
    let field: String
    let title: String
    @Environment(AppModel.self) private var model
    @Environment(ManageNav.self) private var nav
    @State private var logoTarget: MDLogoTarget?
    @State private var addrPick: MDAddrPick?

    var body: some View {
        let items = model.mdQualityReport.select(group, field: field)
        return List {
            if items.isEmpty {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(KColor.ok).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Erledigt.").font(.headline).foregroundStyle(KColor.ok)
                            Text("Hier ist nichts mehr offen.").font(.subheadline).foregroundStyle(KColor.ink2)
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(KColor.ok.opacity(0.12))
                }
            } else {
                Section {
                    ForEach(items) { it in
                        MDQualityRow(issue: it, field: field,
                                     onLogo: { pid in logoTarget = model.mdLogoTarget(partner: pid) },
                                     onAddrSearch: { t in searchAddress(t) })
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Format.count(items.count, "Eintrag", "Einträge"))
                            .foregroundStyle(KColor.warn)
                        Spacer(minLength: 8)
                        HStack(spacing: 14) {
                            if field == "logo" {
                                Button("Alle suchen") {
                                    Task { @MainActor in
                                        if await NetCheck.isOnline() { nav.push(.logoBatch) } else { model.toast("Keine Internetverbindung") }
                                    }
                                }
                                    .font(.subheadline.weight(.semibold))
                            }
                            Button("Alle ignorieren") {
                                let keys = items.map { $0.key }
                                model.update { $0.ignoreQuality(keys) }
                            }
                            .font(.subheadline)
                            .tint(KColor.ink2)
                        }
                        .textCase(nil)
                    }
                } footer: {
                    Text(hint)
                }
            }
        }
        .mdListStyle()
        .navigationTitle(title)
        // Zifferntastaturen (Betrag, Frist) haben keine Eingabetaste: «Fertig» über der Tastatur
        .kKeyboardDone()
        .modifier(MDLogoSheet(target: $logoTarget))
        .modifier(MDAddrPickSheet(pick: $addrPick))
    }

    private var hint: String {
        if field == "logo" { return "«Suchen» schlägt ein Logo vor. Tippe auf den Namen, um es selbst zu wählen." }
        let inline: Set<String> = ["holder", "amount", "cat", "cycle", "due", "via", "ref", "link", "mail", "notice", "inc", "addr", "sender"]
        return inline.contains(field) ? "Direkt hier eintragen. Tippe auf den Namen für alle Angaben." : "Tippe auf einen Eintrag, um die Angabe nachzutragen."
    }

    private func searchAddress(_ t: MDAddrTarget) {
        Task { @MainActor in
            if let p = await model.mdFindAddress(t, notFound: "Keine Adresse gefunden") { addrPick = p }
        }
    }
}

/// Zeile eines offenen Punkts: Marke, Name (antippbar), «Suchen»/«Ignorieren», darunter der Editor
private struct MDQualityRow: View {
    let issue: QualityIssue
    let field: String
    let onLogo: (UUID) -> Void
    let onAddrSearch: (MDAddrTarget) -> Void
    @Environment(AppModel.self) private var model
    @Environment(ManageNav.self) private var nav

    var body: some View {
        let logoPartner: UUID? = {
            if issue.criterion == .logo, case .partner(let pid) = issue.subject { return pid }
            return nil
        }()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Button(action: open) {
                    HStack(spacing: 12) {
                        mark
                        MDTitleSub(title: issue.name, subtitle: smallText)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 4)
                if let pid = logoPartner {
                    Button("Suchen") { onLogo(pid) }
                        .buttonStyle(.borderless)
                        .font(.subheadline.weight(.semibold))
                }
                Button("Ignorieren") {
                    let k = issue.key
                    model.update { $0.ignoreQuality([k]) }
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
                .tint(KColor.ink2)
            }
            MDQualityEditor(issue: issue, onAddrSearch: onAddrSearch)
        }
        .padding(.vertical, 4)
        .mdRow()
    }

    private var smallText: String {
        if field != "logo" && field != "notice" && field != "inc" { return issue.subtitle }
        return [issue.reason, issue.subtitle].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder private var mark: some View {
        let d = model.data
        switch issue.subject {
        case .contract(let id):
            if let c = d.contract(id) { MarkView(contract: c, data: d, size: 40) }
        case .income(let id):
            if let i = d.income(id) { MarkView(income: i, size: 40) }
        case .partner(let id):
            MDPartnerMark(partnerID: id, size: 36)
        case .person(let id):
            PersonAvatar(person: d.person(id), size: 36)
        }
    }

    /// Tipp auf den Namen: Vertrag → Formular, Einnahme → Einnahmen-Formular, Vertragspartner → Seite, Inhaber → Absender
    private func open() {
        switch issue.subject {
        case .contract(let id): model.present(.contractForm(.edit(id)))
        case .income(let id): model.present(.incomeForm(id))
        case .partner(let id): nav.push(.partner(id))
        case .person(let id): nav.push(.sender(id))
        }
    }
}

// MARK: - Editoren

/// Inline-Editor je Kriterium (qEditor / qMulti)
private struct MDQualityEditor: View {
    let issue: QualityIssue
    let onAddrSearch: (MDAddrTarget) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        switch issue.subject {
        case .contract(let id):
            if let c = model.data.contract(id) {
                MDContractEditor(contract: c, criterion: issue.criterion, onAddrSearch: onAddrSearch)
            }
        case .income(let id):
            if let i = model.data.income(id) {
                MDIncomeEditor(income: i, criterion: issue.criterion)
            }
        case .partner(let id):
            if issue.criterion == .addr, let p = model.data.partner(id) {
                MDAddrEditor(target: .partner(id), title: p.name, address: p.address,
                             company: p.address.company.isEmpty ? p.name : p.address.company, onSearch: onAddrSearch)
            }
        case .person(let id):
            if issue.criterion == .sender, model.data.person(id) != nil {
                MDSenderEditor(personID: id, level: issue.senderLevel, initial: model.data.resolvedSender(id))
            }
        }
    }
}

/// Einfeld-Editoren für Verträge (Speichern sofort, Toast «Titel: gespeichert»)
private struct MDContractEditor: View {
    let contract: Contract
    let criterion: QualityCriterion
    let onAddrSearch: (MDAddrTarget) -> Void
    @Environment(AppModel.self) private var model

    private var title: String { model.data.title(of: contract) }

    var body: some View {
        switch criterion {
        case .via:
            MDSegment(options: [(title: "Online", value: CancelChannel.online),
                                (title: "E-Mail", value: CancelChannel.email),
                                (title: "Brief", value: CancelChannel.letter)],
                      selected: Set<CancelChannel>()) { ch in
                saved(model.update { $0.setCancelChannel(contract.id, ch) })
            }
        case .holder:
            MDHolderPicker(selected: []) { ids in
                saved(model.update { $0.mdSetHolders(contract: contract.id, ids) })
            }
        case .cat:
            categoryMenu
        case .cycle:
            cycleMenu
        case .due:
            MDDueEditor { d in
                saved(model.update { $0.mdSetContractDue(contract.id, d) })
            }
        case .amount:
            MDInlineText(placeholder: "Betrag in " + contract.currency.rawValue, keyboard: .decimalPad) { v in
                guard let n = Format.parseAmount(v), n > 0 else {
                    model.toast("Bitte einen Betrag eingeben")
                    return false
                }
                return saved(model.update { $0.mdSetContractAmount(contract.id, n) })
            }
        case .ref:
            MDInlineText(placeholder: "Kunden- oder Vertragsnummer", autocap: .never) { v in
                saved(model.update { $0.mdSetCustomerNo(contract.id, v) })
            }
        case .link:
            MDInlineText(placeholder: "z.B. sunrise.ch/kuendigen", keyboard: .URL, autocap: .never, content: .URL) { v in
                saved(model.update { $0.mdSetCancelURL(contract.id, v) })
            }
        case .mail:
            MDInlineText(placeholder: "z.B. kuendigung@anbieter.ch", keyboard: .emailAddress, autocap: .never, content: .emailAddress) { v in
                saved(model.update { $0.mdSetContractMail(contract.id, v) })
            }
        case .notice:
            MDNoticeEditor(contract: contract)
        case .addr:
            MDAddrEditor(target: .contract(contract.id), title: title, address: PostalAddress(), company: title, onSearch: onAddrSearch)
        default:
            EmptyView()
        }
    }

    @discardableResult
    private func saved(_ ok: Bool) -> Bool {
        if ok { model.toast(title + ": gespeichert") }
        return ok
    }

    private var categoryMenu: some View {
        let cats = model.data.categories.filter { $0.kind != .other && $0.id != model.data.otherCategory?.id }
        return Menu {
            ForEach(cats) { k in
                Button(k.name) { saved(model.update { $0.mdSetContractCategory(contract.id, k.id) }) }
            }
        } label: {
            MDMenuLabel(text: "Kategorie wählen …")
        }
    }

    private var cycleMenu: some View {
        Menu {
            ForEach(Format.cycleOptions, id: \.self) { m in
                Button(Format.cycleTextOrMonthly(m)) { saved(model.update { $0.mdSetContractCycle(contract.id, m) }) }
            }
        } label: {
            MDMenuLabel(text: "Zahlungsrhythmus wählen …")
        }
    }
}

/// Beschriftung eines Auswahlmenüs (wie ein select-Feld)
private struct MDMenuLabel: View {
    let text: String
    var body: some View {
        HStack {
            Text(text).foregroundStyle(KColor.ink)
            Spacer(minLength: 6)
            Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(KColor.ink2)
        }
        .mdFieldBox()
        .contentShape(Rectangle())
    }
}

/// Inhaber wählen: alle Personen und bei ≥ 2 «Beide» (2) bzw. «Alle» (≥ 3)
private struct MDHolderPicker: View {
    let selected: Set<HolderChoice>
    var allowAll = true
    let pick: ([UUID]) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let ps = model.data.persons
        let opts = options(ps)
        if ps.count <= 3 {
            MDSegment(options: opts, selected: selected) { ch in pick(ids(ch, ps)) }
        } else {
            MDChipRow {
                ForEach(Array(opts.enumerated()), id: \.offset) { _, o in
                    Chip(title: o.title, isOn: selected.contains(o.value)) { pick(ids(o.value, ps)) }
                }
            }
        }
    }

    private func options(_ ps: [Person]) -> [(title: String, value: HolderChoice)] {
        var o: [(title: String, value: HolderChoice)] = ps.map { (title: $0.name, value: HolderChoice.person($0.id)) }
        if allowAll && ps.count > 1 { o.append((title: ps.count == 2 ? "Beide" : "Alle", value: HolderChoice.all)) }
        return o
    }

    private func ids(_ ch: HolderChoice, _ ps: [Person]) -> [UUID] {
        switch ch {
        case .all: return ps.map { $0.id }
        case .person(let p): return [p]
        }
    }
}

/// Datum wählen mit «Übernehmen» (Fälligkeit)
private struct MDDueEditor: View {
    let save: (Day) -> Void
    @State private var date = Date()

    var body: some View {
        HStack(spacing: 10) {
            DatePicker("Nächste Zahlung", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .accessibilityLabel("Nächste Zahlung")
            Spacer(minLength: 6)
            Button("Übernehmen") { save(Day(date: date)) }
                .buttonStyle(.bordered)
                .font(.subheadline.weight(.semibold))
        }
    }
}

/// Textfeld, das beim Verlassen, mit Enter oder «Übernehmen» speichert. onSave gibt true zurück, wenn gespeichert.
private struct MDInlineText: View {
    let placeholder: String
    var keyboard: UIKeyboardType = .default
    var autocap: TextInputAutocapitalization = .sentences
    var content: UITextContentType? = nil
    let onSave: (String) -> Bool
    @State private var text = ""
    @State private var lastFailed: String?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocap)
                .textContentType(content)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused)
                .onSubmit { commit() }
                .mdFieldBox()
                .accessibilityLabel(placeholder)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Übernehmen") { commit() }
                    .buttonStyle(.borderless)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .onChange(of: focused) { _, f in if !f { commit() } }
        .onChange(of: text) { _, _ in lastFailed = nil }
    }

    private func commit() {
        let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty, v != lastFailed else { return }
        if onSave(v) {
            text = ""
            focused = false
        } else {
            lastFailed = v
        }
    }
}

/// Frist und Laufzeit mit «Übernehmen» (qMulti «notice»), inkl. «jederzeit» und «Feste Laufzeit bis …».
/// Prüfung und Toasts wie Web (noticeVal, qMultiSave) – Regeln im Kern (ExtManage.swift).
private struct MDNoticeEditor: View {
    let contract: Contract
    @Environment(AppModel.self) private var model
    @State private var notice: String
    @State private var unit: NoticeUnit
    @State private var choice: MDTermChoice
    /// Vertragsende; leer, bis der Nutzer ein Datum wählt (Web: leeres Datumsfeld)
    @State private var end: Date?
    @State private var renew: Int

    private static let renewOptions: [(title: String, value: Int)] = [
        ("ohne Verlängerung", 0), ("verlängert um 1 Monat", 1), ("verlängert um 3 Monate", 3),
        ("verlängert um 6 Monate", 6), ("verlängert um 12 Monate", 12), ("verlängert um 24 Monate", 24),
    ]

    init(contract: Contract) {
        self.contract = contract
        _notice = State(initialValue: contract.notice > 0 ? "\(contract.notice)" : "")
        _unit = State(initialValue: contract.noticeUnit)
        _choice = State(initialValue: MDTermChoice.initial(for: contract))
        _end = State(initialValue: contract.end?.date())
        _renew = State(initialValue: contract.renewMonths)
    }

    private var renewOptions: [(title: String, value: Int)] {
        var o = MDNoticeEditor.renewOptions
        // unbekannter gespeicherter Wert bleibt als Option erhalten (optHtml)
        if renew > 0 && !o.contains(where: { $0.value == renew }) { o.append(("verlängert um \(renew) Monate", renew)) }
        return o
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Frist", text: $notice)
                    .keyboardType(.numberPad)
                    .frame(width: 64)
                    .mdFieldBox()
                    .accessibilityLabel("Frist")
                Picker("Einheit", selection: $unit) {
                    Text("Monate").tag(NoticeUnit.months)
                    Text("Wochen").tag(NoticeUnit.weeks)
                    Text("Tage").tag(NoticeUnit.days)
                    Text(". im Monat").tag(NoticeUnit.dayOfMonth)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                Spacer(minLength: 0)
            }
            Picker("Kündbar auf", selection: $choice) {
                ForEach(MDTermChoice.options, id: \.value) { o in
                    Text(o.title).tag(o.value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            if choice == .fixed {
                HStack(spacing: 8) {
                    if let e = end {
                        DatePicker("Vertragsende", selection: Binding(get: { e }, set: { end = $0 }), displayedComponents: .date)
                            .labelsHidden()
                            .accessibilityLabel("Vertragsende")
                    } else {
                        Button("Vertragsende wählen") { end = Date() }
                            .buttonStyle(.bordered)
                            .font(.subheadline)
                    }
                    Picker("Verlängerung", selection: $renew) {
                        ForEach(renewOptions, id: \.value) { o in
                            Text(o.title).tag(o.value)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
            Button("Übernehmen") { save() }
                .buttonStyle(.bordered)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func save() {
        let endDay: Day? = choice == .fixed ? end.map { Day(date: $0) } : nil
        let n: Int
        switch AppData.mdCheckNotice(notice, unit: unit, choice: choice, end: endDay) {
        case .invalid(let t):
            model.toast(t)
            return
        case .ok(let v):
            n = v
        }
        let id = contract.id
        let ch = choice
        let u = unit
        let r = renew
        guard model.update({ $0.mdSetNotice(id, notice: n, unit: u, choice: ch, end: endDay, renew: r) }) else { return }
        model.toast(model.data.mdNoticeSavedToast(id, today: model.today))
    }
}

/// Adresse des Vertragspartners mit «Übernehmen» und «Suchen» (qMulti «addr»)
private struct MDAddrEditor: View {
    let target: MDAddrTarget
    let title: String
    let onSearch: (MDAddrTarget) -> Void
    @Environment(AppModel.self) private var model
    @State private var firm: String
    @State private var street: String
    @State private var zip: String
    @State private var city: String

    init(target: MDAddrTarget, title: String, address: PostalAddress, company: String, onSearch: @escaping (MDAddrTarget) -> Void) {
        self.target = target
        self.title = title
        self.onSearch = onSearch
        _firm = State(initialValue: company)
        _street = State(initialValue: address.street)
        _zip = State(initialValue: address.zip)
        _city = State(initialValue: address.city)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Firma", text: $firm)
                .textContentType(.organizationName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .mdFieldBox()
                .accessibilityLabel("Firma")
            TextField("Strasse und Nr.", text: $street)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .mdFieldBox()
                .accessibilityLabel("Strasse und Nr.")
            HStack(spacing: 8) {
                TextField("PLZ", text: $zip)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .frame(width: 80)
                    .mdFieldBox()
                    .accessibilityLabel("PLZ")
                TextField("Ort", text: $city)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .mdFieldBox()
                    .accessibilityLabel("Ort")
            }
            HStack(spacing: 8) {
                Button("Übernehmen") { save() }
                    .buttonStyle(.bordered)
                    .font(.subheadline.weight(.semibold))
                Button("Suchen") { onSearch(target) }
                    .buttonStyle(.bordered)
                    .font(.subheadline)
            }
        }
    }

    private func save() {
        let t = { (s: String) in Format.collapseSpaces(s) }
        let f = t(firm), s = t(street), z = t(zip), c = t(city)
        if s.isEmpty || c.isEmpty {
            model.toast("Bitte Strasse und Ort eingeben")
            return
        }
        switch target {
        case .partner(let pid):
            guard let p = model.data.partner(pid) else { return }
            var a = p.address
            a.company = f
            a.street = s
            a.zip = z
            a.city = c
            if model.update({ $0.setPartnerAddress(pid, a) }) { model.toast(p.name + ": Adresse gespeichert") }
        case .contract(let cid):
            let a = PostalAddress(company: f, street: s, zip: z, city: c)
            var ok = false
            model.update { d in ok = d.mdSetContractAddress(cid, company: f, address: a) != nil }
            if ok { model.toast(title + ": Adresse gespeichert") }
        }
    }
}

/// Absender eines Inhabers (qMulti «sender»): bei Brief Name, Strasse und Ort; bei E-Mail nur der Name (Fund M3)
private struct MDSenderEditor: View {
    let personID: UUID
    let level: Int
    @Environment(AppModel.self) private var model
    @State private var first: String
    @State private var last: String
    @State private var street: String
    @State private var zip: String
    @State private var city: String

    init(personID: UUID, level: Int, initial: SenderAddress) {
        self.personID = personID
        self.level = level
        _first = State(initialValue: initial.first)
        _last = State(initialValue: initial.last)
        _street = State(initialValue: initial.street)
        _zip = State(initialValue: initial.zip)
        _city = State(initialValue: initial.city)
    }

    var body: some View {
        let others = level >= 2 ? model.data.persons.filter { o in
            o.id != personID && o.sameAddressAs == nil && model.data.resolvedSender(o.id).isComplete
        } : []
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Vorname", text: $first)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .mdFieldBox()
                    .accessibilityLabel("Vorname")
                TextField("Nachname", text: $last)
                    .textContentType(.familyName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .mdFieldBox()
                    .accessibilityLabel("Nachname")
            }
            if level >= 2 {
                TextField("Strasse und Nr.", text: $street)
                    .textContentType(.streetAddressLine1)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .mdFieldBox()
                    .accessibilityLabel("Strasse und Nr.")
                HStack(spacing: 8) {
                    TextField("PLZ", text: $zip)
                        .textContentType(.postalCode)
                        .keyboardType(.numbersAndPunctuation)
                        .autocorrectionDisabled()
                        .frame(width: 80)
                        .mdFieldBox()
                        .accessibilityLabel("PLZ")
                    TextField("Ort", text: $city)
                        .textContentType(.addressCity)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .mdFieldBox()
                        .accessibilityLabel("Ort")
                }
            }
            MDChipRow {
                Button("Übernehmen") { save() }
                    .buttonStyle(.bordered)
                    .font(.subheadline.weight(.semibold))
                ForEach(others) { o in
                    Button("Adresse wie \(o.name)") { sameAs(o.id) }
                        .buttonStyle(.bordered)
                        .font(.subheadline)
                }
            }
        }
    }

    private func save() {
        guard let p = model.data.person(personID) else { return }
        let t = { (s: String) in Format.collapseSpaces(s) }
        let f = t(first), l = t(last)
        if level >= 2 {
            let s = t(street), z = t(zip), c = t(city)
            if (f.isEmpty && l.isEmpty) || s.isEmpty || c.isEmpty {
                model.toast("Bitte Name, Strasse und Ort eingeben")
                return
            }
            let snd = SenderAddress(first: f, last: l, street: s, zip: z, city: c, country: p.sender.country)
            if model.update({ $0.setSender(personID, snd, sameAs: nil) }) { model.toast("Absender von \(p.name) gespeichert") }
        } else {
            if f.isEmpty && l.isEmpty {
                model.toast("Bitte einen Namen eingeben")
                return
            }
            var snd = p.sender
            snd.first = f
            snd.last = l
            if model.update({ $0.setSender(personID, snd, sameAs: p.sameAddressAs) }) { model.toast("Absender von \(p.name) gespeichert") }
        }
    }

    private func sameAs(_ other: UUID) {
        guard let p = model.data.person(personID) else { return }
        let t = { (s: String) in Format.collapseSpaces(s) }
        var snd = p.sender
        snd.first = t(first)
        snd.last = t(last)
        if model.update({ $0.setSender(personID, snd, sameAs: other) }) {
            model.toast("Adresse übernommen" + (snd.first.isEmpty && snd.last.isEmpty ? ", Name noch eintragen" : ""))
        }
    }
}

/// Editoren für Einnahmen: Betrag, Empfänger (genau eine Person, Fix N6)
private struct MDIncomeEditor: View {
    let income: Income
    let criterion: QualityCriterion
    @Environment(AppModel.self) private var model

    var body: some View {
        switch criterion {
        case .amount:
            MDInlineText(placeholder: "Betrag in " + income.currency.rawValue, keyboard: .decimalPad) { v in
                guard let n = Format.parseAmount(v), n > 0 else {
                    model.toast("Bitte einen Betrag eingeben")
                    return false
                }
                let ok = model.update { $0.mdSetIncomeAmount(income.id, n) }
                if ok { model.toast(income.title + ": gespeichert") }
                return ok
            }
        case .holder:
            MDHolderPicker(selected: [], allowAll: false) { ids in
                guard let p = ids.first else { return }
                var changed = false
                model.update { changed = $0.setIncomeRecipient(income.id, person: p) }
                if changed { model.toast(income.title + ": gespeichert") }
            }
        default:
            EmptyView()
        }
    }
}
