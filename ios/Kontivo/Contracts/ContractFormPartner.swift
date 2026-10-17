import SwiftUI
import KontivoCore

/// Feld «Vertragspartner» im Kopf (Web #fPartner) mit Katalog-Knopf. Tippen sucht eigene Vertragspartner und im Internet
/// (Liste darunter, `CTFormPartnerSuggestions`); fertig eingegeben → Währung eines bekannten Vertragspartners (v156).
struct CTFormPartnerField: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState
    var focus: FocusState<ContractFormField?>.Binding

    var body: some View {
        HStack(spacing: 6) {
            TextField("Vertragspartner", text: Binding(
                get: { form.partnerName },
                set: { v in
                    // SwiftUI setzt den Wert beim Schliessen der Tastatur erneut: nur echte Änderungen suchen
                    let changed = v != form.partnerName
                    form.userTypedPartner(v)
                    if changed { CTPartnerSearch.schedule(form) }
                }))
                .focused(focus, equals: .partner)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .foregroundStyle(KColor.ink)
                .submitLabel(.done)
                .onSubmit { form.partnerCommitted(data: model.data) }
                .accessibilityLabel("Vertragspartner")
                .accessibilityIdentifier("form.partner")
            Button {
                focus.wrappedValue = nil
                form.showCatalog = true
            } label: {
                Image(systemName: "book")
                    .foregroundStyle(KColor.teal)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Aus Katalog wählen")
            .accessibilityIdentifier("form.catalog")
        }
        .padding(.leading, 10).padding(.trailing, 4).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.field))
        .id(ContractFormField.partner)
        .onChange(of: focus.wrappedValue == .partner) { was, now in
            if now {
                CTPartnerSearch.schedule(form)
            } else if was {
                // Web «change» beim Verlassen des Felds
                form.partnerCommitted(data: model.data)
                // Web v214: Liste bleibt beim Schliessen der Tastatur offen; Wechsel in ein anderes Feld = Tipp ausserhalb
                if focus.wrappedValue != nil { CTPartnerSearch.hide(form) }
            }
        }
        .background(GeometryReader { g in
            Color.clear
                .onAppear { form.partnerFieldFrame = g.frame(in: .global) }
                .onChange(of: g.frame(in: .global)) { _, r in form.partnerFieldFrame = r }
        })
    }
}

/// Suche nach Vertragspartnern (eigene sofort, Internet nach kurzer Pause), Zustand im Formular
@MainActor
enum CTPartnerSearch {
    static func schedule(_ form: CTFormState) {
        form.searchTask?.cancel()
        let q = form.partnerName.ctTrimmed
        if q.count < 2 || q == form.pSugSel {
            form.sugVisible = false
            form.webHits = []
            form.webLoading = false
            return
        }
        form.sugVisible = true
        form.webHits = []
        form.webLoading = q.count >= 3
        form.searchToken += 1
        let tok = form.searchToken
        form.searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            let r = await CTWebPartners.search(q)
            if Task.isCancelled || tok != form.searchToken { return }
            form.webHits = r
            form.webLoading = false
        }
    }

    static func hide(_ form: CTFormState) {
        form.searchTask?.cancel()
        form.sugVisible = false
        form.webLoading = false
    }
}

/// Katalogtreffer für die gemeinsame Trefferliste (Web v213 `tplHits`, `tplAll`, `tplTerm`).
// TODO core-API: `Catalog.hits(_:currency:more:)` / `Catalog.all(named:currency:)` / `CatalogEntry.termShort` (Bereich core); hier lokal 1:1.
enum CTCatalogHits {
    /// Web `tplAll(n, cur)`: alle Einträge mit diesem Namen; mehrere → die des Landes (EUR → DE, sonst CH) plus internationale
    static func all(_ name: String, currency: Currency) -> [CatalogEntry] {
        let n = name.ctTrimmed.lowercased()
        var L = Catalog.entries.filter { $0.name.lowercased() == n }
        if L.count > 1 {
            let cc = currency == .EUR ? "DE" : "CH"
            let m = L.filter { $0.country == cc }
            if !m.isEmpty { L = m + L.filter { $0.country.isEmpty } }
        }
        return L
    }

    /// Web `tplHits(q)`: exakte Namen, sonst «Name Bezeichnung» enthält den Text (nur Länder-Variante passend zur Währung);
    /// höchstens 3 (mit «Weitere» 8). `more` = es gibt mehr als 3.
    static func hits(_ q: String, currency: Currency, more: Bool) -> (list: [CatalogEntry], hasMore: Bool) {
        let n = q.ctTrimmed.lowercased()
        if n.count < 2 { return ([], false) }
        let ex = Catalog.entries.filter { $0.name.lowercased() == n }
        let L = !ex.isEmpty ? ex : Catalog.entries.filter { t in
            (t.name + " " + t.label).lowercased().contains(n) && all(t.name, currency: currency).contains(t)
        }
        return (Array(L.prefix(more ? 8 : 3)), L.count > 3 && !more)
    }

    /// Web `tplTerm(t)`: «nicht kündbar», «Pflichtvertrag», «jederzeit kündbar» oder «3 Monate Frist»
    static func term(_ t: CatalogEntry) -> String {
        if t.category == "Steuern & Gebühren" { return "nicht kündbar" }
        if t.mandatory { return "Pflichtvertrag" }
        let n = t.notice
        if n == 0 { return "jederzeit kündbar" }
        let u: (String, String)
        switch t.noticeUnit {
        case .days: u = ("Tag", "Tage")
        case .weeks: u = ("Woche", "Wochen")
        default: u = ("Monat", "Monate")
        }
        return "\(n) " + (n == 1 ? u.0 : u.1) + " Frist"
    }

    /// Unterzeile: Bezeichnung (sonst Kategorie) · Land bei mehreren Einträgen gleichen Namens · Kündigung
    static func subtitle(_ t: CatalogEntry, currency: Currency) -> String {
        let multi = all(t.name, currency: currency).count > 1
        let land = multi && !t.country.isEmpty ? (t.country == "CH" ? "Schweiz" : t.country == "DE" ? "Deutschland" : t.country) : ""
        return [t.label.isEmpty ? t.category : t.label, land, term(t)].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Gemeinsame Trefferliste unter dem Vertragspartner (Web v213 `#pSug`): «Deine Vertragspartner» · «Katalog» · «Aus dem Internet»,
/// gleiche Website nur einmal (Katalog gewinnt). Bleibt beim Schliessen der Tastatur offen; schliesst bei Tipp ausserhalb oder
/// nach einer Auswahl (v214). Fläche wie Web `.psug`: Rand, Radius 12, Innenabstand 2 10 4.
struct CTFormPartnerSuggestions: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState
    var focus: FocusState<ContractFormField?>.Binding

    var body: some View {
        let data = model.data
        let q = form.partnerName.ctTrimmed
        let showList = form.sugVisible && q.count >= 2 && q != form.pSugSel
        let own = showList ? Partners.matches(q, in: data, today: model.today, limit: 3) : []
        let ownNames = Set(own.map { $0.partner.name.lowercased() })
        let th = showList ? CTCatalogHits.hits(q, currency: form.currency, more: form.tplMore) : ([], false)
        let tDom = Set(th.list.compactMap { $0.web.isEmpty ? nil : Partners.regDom($0.web) })
        let web = showList ? form.webHits.filter { !ownNames.contains($0.name.lowercased()) && !tDom.contains(Partners.regDom($0.dom)) } : []
        let searching = showList && web.isEmpty && form.webLoading && q.count >= 3
        if showList && (!own.isEmpty || !th.list.isEmpty || !web.isEmpty || searching) {
            Section {
                VStack(alignment: .leading, spacing: 0) {
                    if !own.isEmpty {
                        CTSuggestHeader(title: "Deine Vertragspartner")
                        ForEach(Array(own.enumerated()), id: \.element.partner.id) { i, g in
                            ownRow(g, data: data, first: i == 0)
                        }
                    }
                    if !th.list.isEmpty {
                        CTSuggestHeader(title: "Katalog")
                        ForEach(Array(th.list.enumerated()), id: \.offset) { i, t in
                            tplRow(t, first: own.isEmpty && i == 0)
                        }
                        if th.hasMore {
                            Button {
                                form.tplMore = true
                            } label: {
                                Text("Weitere Katalogtreffer")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(KColor.teal)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("form.tplMore")
                        }
                    }
                    if !web.isEmpty {
                        CTSuggestHeader(title: "Aus dem Internet")
                        ForEach(Array(web.enumerated()), id: \.element) { i, w in
                            webRow(w, first: own.isEmpty && th.list.isEmpty && i == 0)
                        }
                    } else if searching {
                        Text("Suche …")
                            .font(.system(size: 12.5))
                            .foregroundStyle(KColor.ink3)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.top, 2).padding(.bottom, 4).padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KColor.surface))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(KColor.line, lineWidth: 1))
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { form.sugFrame = g.frame(in: .global) }
                        .onChange(of: g.frame(in: .global)) { _, r in form.sugFrame = r }
                        .onDisappear { form.sugFrame = .zero }
                })
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 2, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("form.partnerHits")
            }
        }
    }

    /// Zeile der Liste (Web `.psug .mdrow`: 7 oben/unten, Kachel 34/9, Titel 14.5/600, Zeile 12 px; Trennlinie ausser oben)
    private func hitRow<M: View>(first: Bool, title: String, sub: String, @ViewBuilder mark: () -> M) -> some View {
        HStack(spacing: 12) {
            mark()
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(KColor.ink).lineLimit(1)
                    .ctLine(21)
                Text(sub).font(.system(size: 12)).foregroundStyle(KColor.ink2).lineLimit(1)
                    .ctLine(17.4)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(KColor.line).frame(height: 1) }
        }
        .contentShape(Rectangle())
    }

    private func ownRow(_ g: Partners.Group, data: AppData, first: Bool) -> some View {
        let c0 = data.contract(g.contractIDs.first)
        let dom = Format.domain(of: g.partner.web)
        return Button {
            form.pickOwn(g, data: model.data)
            hide()
        } label: {
            hitRow(first: first, title: g.partner.name, sub: CTText.contracts(g.contractIDs.count) + (dom.isEmpty ? "" : " · " + dom)) {
                if let c = c0 {
                    MarkView(contract: c, data: data, size: 34)
                } else {
                    MarkView(logoID: g.partner.logoID, logoBg: g.partner.logoBg, colorHex: AppData.hashColor(g.partner.name),
                             symbol: KIcon.symbol(for: nil), size: 34)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Katalogtreffer: Kategorie-Symbol, Name, Kurzinfo; Antippen übernimmt die Vorlage (Web `data-pt` → applyTpl, tplLogo)
    private func tplRow(_ t: CatalogEntry, first: Bool) -> some View {
        let data = model.data
        let cat = CTFormState.categoryID(for: t.category.isEmpty ? "Sonstiges" : t.category, data: data).flatMap { data.category($0) }
        return Button {
            hide()
            CTTplLogo.apply(t, form: form, model: model)
            form.pSugSel = t.name
        } label: {
            hitRow(first: first, title: t.name, sub: CTCatalogHits.subtitle(t, currency: form.currency)) {
                if let c = cat {
                    MarkView(category: c, size: 34)
                } else {
                    MarkView(logoID: nil, logoBg: nil, colorHex: KCategory.fallbackColor, symbol: KIcon.symbol(forKey: t.category), size: 34)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("form.tplHit")
    }

    private func webRow(_ w: WebPartnerHit, first: Bool) -> some View {
        Button {
            pickWeb(w)
        } label: {
            hitRow(first: first, title: w.name, sub: w.dom + (w.desc.isEmpty ? "" : " · " + w.desc)) {
                AsyncImage(url: CTWebPartners.thumbURL(w)) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFit()
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
    }

    private func hide() {
        CTPartnerSearch.hide(form)
        focus.wrappedValue = nil
    }

    /// Internet-Treffer übernehmen, danach Logo laden (nur wenn noch keins da ist)
    private func pickWeb(_ w: WebPartnerHit) {
        let got = form.pickWeb(w, data: model.data)
        hide()
        let msg: ([String]) -> String = { extra in
            let a = got + extra
            return a.isEmpty ? "Nichts Weiteres gefunden" : "Übernommen: " + a.joined(separator: ", ")
        }
        if form.effectiveLogo(model.data) != nil {
            model.toast(msg([]))
            return
        }
        model.toast("Lade Logo …")
        let f = form
        let m = model
        // Name beim Übernehmen: kommt das Logo spät und wurde der Vertragspartner inzwischen geändert, nicht mehr setzen
        let n0 = f.partnerName.ctTrimmed
        Task {
            let r = await CTLogoFetch.logo(file: w.file, domain: w.dom)
            if f.closed || f.partnerName.ctTrimmed != n0 { return }
            if let r, f.effectiveLogo(m.data) == nil, let id = m.storeFile(r.png, type: "image/png") {
                f.logoID = id
                f.logoBg = r.bg
                f.logoTouched = true
                m.toast(msg(["Logo"]))
            } else {
                m.toast(msg([]))
            }
        }
    }
}

/// Zwischentitel der Trefferliste (Web `.psug .ph`: 11.5/600 Tinte 3, 8 oben, 2 unten)
private struct CTSuggestHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(KColor.ink3)
            .ctLine(16.7)
            .padding(.top, 8).padding(.bottom, 2)
    }
}

/// Vorlage-Chips, Hinweistext bzw. Karte «Aus dem Katalog übernommen» unter dem Vertragspartner (paintSugg)
struct CTTemplateRow: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState

    var body: some View {
        switch form.suggest {
        case .none:
            EmptyView()
        case .hint(let text, let chip):
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(KColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if chip {
                    Button("Übliche Frist übernehmen") {
                        form.applyStandard(data: model.data)
                        model.toast("Vorlage übernommen — bitte prüfen")
                    }
                    .buttonStyle(.bordered)
                    .tint(KColor.teal)
                    .font(.subheadline.weight(.semibold))
                }
            }
            .padding(.vertical, 2)
        case .summary(let t, let items):
            CTTemplateSummaryCard(form: form, hint: t.hintFull.ctTrimmed, items: items)
        case .exact(let t):
            VStack(alignment: .leading, spacing: 6) {
                Text("Vorlage")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(KColor.ink2)
                Chip(title: t.name + " übernehmen", isOn: false) {
                    CTTplLogo.apply(t, form: form, model: model)
                }
            }
            .padding(.vertical, 2)
        case .chips(let hits):
            VStack(alignment: .leading, spacing: 6) {
                Text("Vorlage")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(KColor.ink2)
                CTFlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(hits) { t in
                        Chip(title: t.name, isOn: false) {
                            CTTplLogo.apply(t, form: form, model: model)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// Zusammenfassung statt stiller Feldänderungen (Web .tplsum): Liste der übernommenen Angaben, Hinweis, «Rückgängig»
private struct CTTemplateSummaryCard: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState
    let hint: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("Aus dem Katalog übernommen")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KColor.ink)
                Spacer(minLength: 8)
                Button("Rückgängig") {
                    form.tplUndoApply(data: model.data)
                    model.toast("Katalogdaten entfernt")
                }
                .buttonStyle(.borderless)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KColor.teal)
                .accessibilityIdentifier("form.tplUndo")
            }
            if !items.isEmpty {
                CTFlowLayout(spacing: 5, lineSpacing: 5) {
                    ForEach(items, id: \.self) { x in
                        Text(x)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(KColor.teal)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(KColor.teal.opacity(0.12)))
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("form.tplTags")
            }
            if !hint.isEmpty {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(KColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Bitte kurz prüfen – Angaben können sich ändern.")
                .font(.caption)
                .foregroundStyle(KColor.ink3)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KColor.sunken, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.vertical, 2)
        .accessibilityIdentifier("form.tplSummary")
    }
}

/// Katalog-Vorlage übernehmen und – wie bei Internet-Treffern – ein Logo vorschlagen (Web tplLogo, 1ce25ad):
/// zuerst das Website-Symbol der Katalog-Domain, sonst die normale Logo-Suche. Nur in den offenen Entwurf
/// (gilt erst mit «Sichern»); kommt das Logo zu spät oder wurde der Vertragspartner geändert, wird es verworfen.
@MainActor
enum CTTplLogo {
    static func apply(_ t: CatalogEntry, form: CTFormState, model: AppModel) {
        form.applyTemplate(t, keepName: false, onlyEmpty: false, data: model.data)
        suggest(t, form: form, model: model)
    }

    static func suggest(_ t: CatalogEntry, form: CTFormState, model: AppModel) {
        if form.effectiveLogo(model.data) != nil { return }
        let n0 = form.partnerName.ctTrimmed
        let cur = form.currency
        Task { @MainActor in
            guard await NetCheck.isOnline() else { return }
            let r = await find(t, currency: cur)
            guard let r, !form.closed, form.partnerName.ctTrimmed == n0, form.effectiveLogo(model.data) == nil,
                  let id = model.storeFile(r.png, type: "image/png") else { return }
            form.applyCatalogLogo(id: id, bg: r.background)
        }
    }

    /// siteCand(regDom(web)) → takeLogo, sonst autoLogo (bis 3 gute Vorschläge ab 3 Punkten)
    static func find(_ t: CatalogEntry, currency: Currency) async -> LogoImage? {
        let dom = Format.domain(of: t.web)
        if !dom.isEmpty, let sc = await LogoFinder.siteCand(Partners.regDom(dom), score: 3),
           case .success(let img) = await LogoFinder.take(sc) {
            return img
        }
        guard Partners.lusable(t.name) else { return nil }
        let r = await LogoFinder.allCandidates(name: t.name, currency: currency, alt: nil, web: t.web, manual: false)
        for c in r.cands.filter({ $0.score >= 3 }).prefix(3) {
            if case .success(let img) = await LogoFinder.take(c) { return img }
        }
        return nil
    }
}
