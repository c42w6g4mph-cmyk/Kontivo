import SwiftUI
import KontivoCore

/// Vertragsdetail (Web `openDetail`, Stand v160) als reine Ansicht. Zustände, Zeilen, Texte und Menü kommen aus dem Kern
/// (`Calc.detailInfo(_:)`, `Calc.detailMenu(_:)`): Kopf mit Dokumente-Knopf, Pillen, Kennzahlen mit Anteil bzw. Status,
/// Hinweis «Angaben fehlen», Kasten «Kündigen/Wechseln bis …» bzw. «Probeabo bis …», Abschnitte mit Preisverlauf,
/// Sonderzahlungen, Notiz. Aktionen im Menü ••• oben (Untertitel unter dem Titel, Web v150). Bearbeiten nur im Formular.
/// Native Zusätze: «In Kalender» im Menü, Dokumentliste mit Anhängen, Kontakt-Zeilen mit «Kopieren».
struct ContractDetailView: View {
    let contractID: UUID
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var scrolled = false
    @State private var showPause = false
    @State private var askDelete = false
    @State private var showDocs = false
    @State private var calendarFor: UUID?
    /// «Schon gekündigt …» / «Beendet …»: Rückfrage «Läuft bis» (Web v154)
    @State private var cancelledFor: CTIDItem?
    /// Probeabo-Kasten «Kündigen»: Auswahl wie in «Fristen» (Web `killOptions(id, true)`)
    @State private var killTarget: DeadlineKillTarget?
    /// Erklärblatt Sonderkündigung (Web `openSkr`)
    @State private var skrSheet: CTSkrSheetItem?

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
            .ctSheetBar(model.data.contract(contractID).map { model.data.title(of: $0) } ?? "", titleVisible: scrolled) {
                CTBarCancelButton(title: "Schliessen") { dismiss() }
            } trailing: {
                HStack(spacing: 10) {
                    if let c = model.data.contract(contractID) {
                        actionsMenu(c)
                    }
                    CTBarConfirmButton(title: "Bearbeiten", disabled: model.data.contract(contractID) == nil) {
                        model.present(.contractForm(.edit(contractID)))
                    }
                }
            }
        }
        .deadlineCalendar(contractID: $calendarFor)
        .deadlineKillSheet($killTarget)
        .ctAlreadyCancelledSheet($cancelledFor)
        .sheet(isPresented: $showPause) {
            CTPauseSheet(contractID: contractID, onPaused: { model.dismissAll() })
                .environment(model)
        }
        .sheet(item: $skrSheet) { it in
            CTSkrSheet(data: it.data)
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
        let info = calc.detailInfo(c)
        let skr = CTSpecialCancel.info(calc, data: model.data, c)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                CTDetailHeader(contract: c) { showDocs = true }
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: CTDetailScrollKey.self, value: g.frame(in: .named("ctDetail")).minY)
                        }
                    )
                CTDetailPills(pills: info.pills)
                CTDetailKeyFigures(contract: c, month: info.month)
                CTDetailCompletenessHint(contract: c)
                if let box = info.box {
                    CTDetailDeadlineBox(box: box, onCancel: { boxCancel(info) }, onKeep: { boxKeep(info) })
                }
                // Preiserhöhung: kurze Zeile mit ⓘ, Erklärung im Blatt (Web v205 `skrInfo`/`openSkr`)
                if let x = skr {
                    CTSkrLine(info: x) {
                        skrSheet = CTSkrSheetItem(data: CTSpecialCancel.sheet(x, contract: c, calc: calc, data: model.data))
                    }
                }
                CTDetailSections(contract: c, info: info)
                Color.clear.frame(height: 18)
            }
            .padding(.horizontal, CTListMetric.side)
            .padding(.bottom, 18)
            .kContentWidth()
        }
        .coordinateSpace(name: "ctDetail")
        .onPreferenceChange(CTDetailScrollKey.self) { y in
            // Web: Titel in der Leiste ab 60 px Scrollweite
            let s = y < -60 + 18
            if s != scrolled { scrolled = s }
        }
    }

    // MARK: Kasten oben

    /// Frist-Kasten (≤ 60 Tage): Kündigungsweg starten (laufendes Probeabo: fürs Probeabo, Web `dTrial`).
    /// Probeabo-Kasten: Auswahl «Kündigen: …» mit «Als gekündigt markieren» (Web `trialkill` → `killOptions(id, true)`).
    private func boxCancel(_ info: ContractDetailInfo) {
        if info.due60 {
            model.startCancel(contractID, trial: info.trialRunning)
        } else {
            killTarget = DeadlineKillTarget(contractID: contractID, trial: true)
        }
    }

    /// Frist-Kasten: für diesen Termin behalten (Web `keep`); Probeabo-Kasten: Probeabo behalten (Web `trialkeep`).
    private func boxKeep(_ info: ContractDetailInfo) {
        let t = model.today
        let id = contractID
        if info.due60 {
            run({ $0.keep(id, trial: false, today: t) }, toast: AppData.keepToast)
        } else {
            run({ $0.keep(id, trial: true, today: t) }, toast: AppData.keepTrialToast)
        }
    }

    // MARK: Menü ••• (Web `dMenu`, v143/v150/v154)

    private func actionsMenu(_ c: Contract) -> some View {
        let calc = model.calc
        let m = calc.detailMenu(c)
        let trial = calc.trialOn(c)
        return Menu {
            if let k = m.cancel {
                Button {
                    model.startCancel(contractID, trial: trial)
                } label: {
                    Text(k.title)
                    Text(k.subtitle)
                }
            }
            if m.uncancel {
                Button("Kündigung zurücknehmen") {
                    run({ $0.undoCancel(contractID) }, toast: "Kündigung zurückgenommen")
                }
            }
            if m.unkeep {
                Button("«Behalten» zurücksetzen") {
                    run({ $0.unkeep(contractID) }, toast: "Wieder offen")
                }
            }
            if let p = m.pause {
                Button(p) {
                    if calc.isPaused(c) {
                        let t = model.today
                        run({ $0.resume(contractID, today: t) }, toast: "Fortgesetzt")
                    } else {
                        showPause = true
                    }
                }
            }
            if DeadlineCalendar.canAdd(c, calc: calc) {
                Button { calendarFor = c.id } label: { Label(DeadlineCalendar.menuTitle, systemImage: DeadlineCalendar.symbol) }
            }
            Button("Duplizieren") {
                model.present(.contractForm(.duplicate(contractID)))
            }
            if m.reactivate {
                Button("Wieder aktiv setzen") {
                    model.ctReactivate(contractID)
                }
            } else if let a = m.alreadyCancelled {
                Button {
                    cancelledFor = CTIDItem(id: contractID)
                } label: {
                    Text(a.title)
                    Text(a.subtitle)
                }
            }
            Button("Löschen", role: .destructive) {
                askDelete = true
            }
        } label: {
            CTBarMenuLabel()
                .accessibilityLabel("Aktionen")
        }
        .accessibilityLabel("Aktionen")
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

// MARK: - Kopf (Web `.detailhead`: Kachel 76/17, Abstand 15, Titel 22/600 angepasst, Zusatz 13 px)

private struct CTDetailHeader: View {
    @Environment(AppModel.self) private var model
    let contract: Contract
    let onDocs: () -> Void

    var body: some View {
        let data = model.data
        HStack(alignment: .center, spacing: 15) {
            MarkView(contract: contract, data: data, size: 76)
            VStack(alignment: .leading, spacing: 0) {
                CTFitTitle(text: data.title(of: contract))
                let meta = data.meta(of: contract)
                if !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 13))
                        .foregroundStyle(KColor.ink2)
                        .lineSpacing(3.3)
                        .ctLine(18.85)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            CTDetailDocsButton(count: contract.documents.count, action: onDocs)
        }
        .padding(.top, 18)
        .padding(.bottom, 6)
    }
}

/// Titel im Detailkopf (Web v203/v204 `fitHeads`): erst auf eine Zeile verkleinern (bis ~78 %, min. 17 px), sonst bis 17 px für
/// höchstens 2 Zeilen, bis 14 px damit das längste Wort ganz passt; erst dann Umbruch im Wort (Notlösung).
struct CTFitTitle: View {
    let text: String
    var base: CGFloat = 22
    @State private var width: CGFloat = 0

    var body: some View {
        let sz = width > 0 ? CTFitTitle.fit(text, width: width, base: base) : base
        Text(text)
            .font(KFont.title(sz))
            .tracking(KFont.tracking(-0.012, sz))
            .foregroundStyle(KColor.ink)
            .lineSpacing(max(0, sz * 1.15 - CTFitTitle.uiFont(sz).lineHeight))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { width = g.size.width }
                    .onChange(of: g.size.width) { _, w in width = w }
            })
    }

    static func uiFont(_ sz: CGFloat) -> UIFont { UIFont.systemFont(ofSize: sz, weight: .semibold) }

    private static func attrs(_ sz: CGFloat) -> [NSAttributedString.Key: Any] {
        [.font: uiFont(sz), .kern: -0.012 * sz]
    }

    /// Zeilen bei Breite `w` (Wortumbruch wie im Browser)
    static func lines(_ s: String, _ sz: CGFloat, _ w: CGFloat) -> Int {
        let r = (s as NSString).boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude),
                                             options: [.usesLineFragmentOrigin], attributes: attrs(sz), context: nil)
        return max(1, Int((r.height / uiFont(sz).lineHeight).rounded()))
    }

    static func longestWord(_ s: String, _ sz: CGFloat) -> CGFloat {
        s.split(whereSeparator: { $0 == " " || $0 == "\n" }).map { (String($0) as NSString).size(withAttributes: attrs(sz)).width }.max() ?? 0
    }

    static func fit(_ s: String, width w: CGFloat, base: CGFloat) -> CGFloat {
        var sz = base
        let one = max(17, (base * 0.78).rounded())
        while sz > one && lines(s, sz, w) > 1 { sz -= 1 }
        if lines(s, sz, w) > 1 { sz = base }
        while sz > 17 && lines(s, sz, w) > 2 { sz -= 1 }
        while sz > 14 && longestWord(s, sz) > w + 1 { sz -= 1 }
        return sz
    }
}

// MARK: - Pillen (Web `.pills`: 8 0 14, Abstand 6; `.pill` 11 px, 3/9, neutral `--sunken`, warn 18 %, alert 16 %)

/// Pillen aus dem Kern (Rangfolge und Texte wie Web `openDetail`); ohne Pille 10 pt Abstand.
private struct CTDetailPills: View {
    let pills: [DetailPill]

    var body: some View {
        if pills.isEmpty {
            Color.clear.frame(height: 10)
        } else {
            CTFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(pills.indices, id: \.self) { i in
                    CTPill(text: pills[i].text, tone: pills[i].tone)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 14)
            .accessibilityIdentifier("detail.pills")
        }
    }
}

struct CTPill: View {
    let text: String
    let tone: DetailTone

    var body: some View {
        let (fg, bg, w): (Color, Color, Font.Weight) = {
            switch tone {
            case .neutral: return (KColor.ink2, KColor.sunken, .regular)
            case .warn: return (KColor.warn, KColor.warn.opacity(0.18), .semibold)
            case .alert: return (KColor.alert, KColor.alert.opacity(0.16), .semibold)
            }
        }()
        Text(text)
            .font(.system(size: 11, weight: w))
            .ctLine(15.95)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .foregroundStyle(fg)
            .background(Capsule().fill(bg))
    }
}

// MARK: - Abschnitte (Web `h3.dsec` 12.5/600 Tinte 2, 20 0 2; `.dgrp` Fläche, Radius 16, Innenabstand 0 13)

/// Abschnittskopf im Detail
struct CTDSec: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(KColor.ink2)
            .ctLine(18.125)
            .padding(.top, 20)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Gruppe mit Zeilen und Trennlinien (innerhalb des Innenabstands)
struct CTDGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 13)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(KColor.surface))
    }
}

/// Trennlinie zwischen Zeilen einer Gruppe (Web `.dl` border-top 1 px `--line`)
struct CTDLine: View {
    var body: some View { Rectangle().fill(KColor.line).frame(height: 1) }
}

private struct CTDetailSections: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let contract: Contract
    let info: ContractDetailInfo

    var body: some View {
        let c = contract
        let calc = model.calc
        VStack(alignment: .leading, spacing: 0) {
            // Kosten: Zeilen (Betrag, Zahlung, Bezahlung) und Preisverlauf (nur Ansicht; Preise erfassen unter «Bearbeiten»)
            CTDSec(title: "Kosten")
            if !info.costRows.isEmpty {
                CTDGroup { CTDetailRowsView(rows: info.costRows, today: calc.today) }
            }
            if !calc.pricesOf(c).isEmpty {
                CTPriceChart(contract: c, today: calc.today)
                    .padding(.top, info.costRows.isEmpty ? 0 : 8)
            }
            CTDetailGroup(title: "Laufzeit & Kündigung", rows: info.termRows, today: calc.today)
            assignment(c)
            contact(c)
            let xs = calc.extrasOf(c)
            if !xs.isEmpty {
                CTDSec(title: "Sonderzahlungen")
                CTExtrasList(extras: xs, currency: c.currency.rawValue, today: calc.today, onDelete: nil)
            }
            if !c.note.isEmpty {
                CTDSec(title: "Notiz")
                // Web: 14.5 px, Zeilenumbrüche bleiben, ohne Fläche
                Text(c.note)
                    .font(.system(size: 14.5))
                    .foregroundStyle(KColor.ink)
                    .lineSpacing(14.5 * 0.45 - 2.8)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Zuordnung aus dem Kern (Vertragspartner, Kategorie, Person(en), Kundennummer, Vertrags-/Policen-/Versicherten-/Rufnummer);
    /// Vertragspartner als Verweis auf «Vertragspartner bearbeiten» (Web `data-peopen`).
    @ViewBuilder
    private func assignment(_ c: Contract) -> some View {
        let rows = info.assignmentRows
        if !rows.isEmpty {
            CTDSec(title: "Zuordnung")
            CTDGroup {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    if i > 0 { CTDLine() }
                    if i == 0 && r.label == "Vertragspartner", let p = model.data.partner(c.partnerID) {
                        partnerLink(label: r.label, name: r.value, id: p.id)
                    } else {
                        CTDetailRowView(row: r, today: model.today)
                    }
                }
            }
        }
    }

    private func partnerLink(label: String, name: String, id: UUID) -> some View {
        Button {
            model.present(.manage(.partner(id)))
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(KColor.ink2)
                Spacer(minLength: 0)
                Text(name + " ›")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KColor.teal)
                    .multilineTextAlignment(.trailing)
            }
            .ctLine(20.3)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Öffnet den Vertragspartner")
    }

    /// Kontakt (Web `.links`: Knöpfe untereinander, Abstand 7, Fläche `--field`, Radius 10, 11/12, 14 px, Wert Messing 600)
    @ViewBuilder
    private func contact(_ c: Contract) -> some View {
        let web = model.data.partner(c.partnerID)?.web.trimmingCharacters(in: .whitespaces) ?? ""
        let tel = c.tel.trimmingCharacters(in: .whitespaces)
        let mail = c.mail.trimmingCharacters(in: .whitespaces)
        if !web.isEmpty || !tel.isEmpty || !mail.isEmpty {
            CTDSec(title: "Kontakt")
            VStack(spacing: 7) {
                if !web.isEmpty {
                    linkRow("Website", CTDetailSections.stripScheme(web), url: URL(string: Format.normUrl(web)))
                }
                if !tel.isEmpty {
                    linkRow("Telefon", tel, url: URL(string: "tel:" + tel.filter { !$0.isWhitespace }))
                }
                if !mail.isEmpty {
                    linkRow("E-Mail", mail, url: URL(string: "mailto:" + mail))
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
    }

    private func linkRow(_ label: String, _ value: String, url: URL?) -> some View {
        Button {
            if let u = url { openURL(u) }
        } label: {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundStyle(KColor.ink)
                Spacer(minLength: 0)
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KColor.teal)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .ctLine(20.3)
            .padding(.vertical, 11).padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.field))
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

/// Nächste Kündigung als Zeitstrahl (Web `termLine`): Punkt heute, Frist (Messing, anteilig 28–62 %), Ende (Ring).
/// Daten aus `DetailTimeline` (bei «Behalten» der nächste Termin, beim Probeabo der letzte Gratistag).
struct CTTimeline {
    let today: Day
    let deadline: Day
    let end: Day
    let anytime: Bool
    let days: Int

    init(_ t: DetailTimeline, today: Day) {
        self.today = today
        deadline = t.deadline
        end = t.end
        anytime = t.anytime
        days = t.days
    }

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

/// Web `.tlw`: Kopf 12.5 px (8 darunter), Linie 14 hoch mit 6 Rand, Beschriftungen 38 hoch (5 darüber), 13/11.5 px
private struct CTTimelineView: View {
    let t: CTTimeline

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Nächste Kündigung").font(.system(size: 12.5)).foregroundStyle(KColor.ink2)
                Spacer()
                Text(verbatim: t.remaining).font(.system(size: 12.5, weight: t.urgent ? .semibold : .regular))
                    .foregroundStyle(t.urgent ? KColor.alert : KColor.ink2)
            }
            .ctLine(18.125)
            .padding(.bottom, 8)
            GeometryReader { g in
                let w = g.size.width
                let inner = w - 12
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(KColor.line).frame(width: inner, height: 2).offset(x: 6, y: 6)
                    Circle().fill(KColor.ink3).frame(width: 8, height: 8).offset(x: 4, y: 3)
                    Circle().fill(KColor.teal).frame(width: 12, height: 12).offset(x: 6 + inner * t.position - 6, y: 1)
                    Circle().fill(KColor.field).frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(KColor.ink, lineWidth: 2))
                        .offset(x: w - 12, y: 1)
                }
            }
            .frame(height: 14)
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .topLeading) {
                    Text("heute").font(.system(size: 13)).foregroundStyle(KColor.ink3)
                    label(Format.fmtShort(t.deadline), "kündigen bis", align: .center)
                        .fixedSize()
                        .alignmentGuide(.leading) { d in d.width / 2 - w * t.position }
                    HStack { Spacer(); label(Format.fmtShort(t.end), "Ende", align: .trailing) }
                }
            }
            .frame(height: 38)
            .padding(.top, 5)
        }
        .padding(.top, 12).padding(.bottom, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Nächste Kündigung: bis " + Format.fmtD(t.deadline) + " kündigen, Vertragsende " + Format.fmtD(t.end)
                                 + (t.remaining.isEmpty ? "" : ", " + t.remaining)))
        .accessibilityIdentifier("detail.timeline")
    }

    private func label(_ date: String, _ sub: String, align: HorizontalAlignment) -> some View {
        VStack(alignment: align, spacing: 0) {
            Text(verbatim: date).font(.system(size: 13, weight: .semibold)).foregroundStyle(KColor.ink).monospacedDigit()
                .ctLine(16.25)
            Text(verbatim: sub).font(.system(size: 11.5)).foregroundStyle(KColor.ink2)
                .ctLine(14.4)
        }
    }
}

/// Abschnitt mit Kopf und Zeilen «Bezeichnung | Wert»; entfällt ohne Zeilen
private struct CTDetailGroup: View {
    let title: String
    let rows: [DetailRow]
    let today: Day

    var body: some View {
        if !rows.isEmpty {
            CTDSec(title: title)
            CTDGroup {
                CTDetailRowsView(rows: rows, today: today)
            }
        }
    }
}

private struct CTDetailRowsView: View {
    let rows: [DetailRow]
    let today: Day

    var body: some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
            if i > 0 { CTDLine() }
            CTDetailRowView(row: r, today: today)
        }
    }
}

/// Eine Zeile aus dem Kern (Web `.dl`): Zeitstrahl oder «Bezeichnung | Wert» (12.5 Tinte 2 | 14 Tinte, Abstand 16, 11 oben/unten)
/// mit Zusatz darunter («nächste am …», 12 px)
private struct CTDetailRowView: View {
    let row: DetailRow
    let today: Day

    var body: some View {
        if let tl = row.timeline {
            CTTimelineView(t: CTTimeline(tl, today: today))
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(row.label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(KColor.ink2)
                    .fixedSize()
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(row.value)
                        .font(.system(size: 14))
                        .foregroundStyle(KColor.ink)
                        .multilineTextAlignment(.trailing)
                        .lineSpacing(3.6)
                        .textSelection(.enabled)
                    if !row.sub.isEmpty {
                        Text(row.sub)
                            .font(.system(size: 12))
                            .foregroundStyle(KColor.ink2)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .frame(minHeight: 20.3)
            .padding(.vertical, 11)
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
            CTDGroup { rows }
        } else {
            rows
        }
    }

    @ViewBuilder private var rows: some View {
        ForEach(Array(extras.enumerated()), id: \.element.id) { i, x in
            if i > 0 && framed { CTDLine() }
            CTExtraRow(extra: x, currency: currency, today: today, onDelete: deleteAction(x))
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
