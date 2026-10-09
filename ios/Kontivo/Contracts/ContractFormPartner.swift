import SwiftUI
import KontivoCore

/// Feld «Vertragspartner» mit Vorschlägen (eigene Vertragspartner, Internet), Duplikat-Hinweis und Katalog-Vorlagen.
struct CTFormPartnerBlock: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState
    @FocusState private var focused: Bool
    @State private var visible = false
    @State private var webHits: [WebPartnerHit] = []
    @State private var loading = false
    @State private var token = 0
    @State private var searchTask: Task<Void, Never>?

    init(form: CTFormState) {
        self.form = form
    }

    var body: some View {
        let data = model.data
        let q = form.partnerName.ctTrimmed
        let showList = visible && q.count >= 2 && q != form.pSugSel
        let own = showList ? Partners.matches(q, in: data, today: model.today, limit: 3) : []
        let ownNames = Set(own.map { $0.partner.name.lowercased() })
        let web = showList ? webHits.filter { !ownNames.contains($0.name.lowercased()) } : []
        field
        if showList && !own.isEmpty {
            CTSuggestHeader(title: "Deine Vertragspartner")
            ForEach(own, id: \.partner.id) { g in
                ownRow(g, data: data)
            }
        }
        if showList && !web.isEmpty {
            CTSuggestHeader(title: "Aus dem Internet")
            ForEach(web, id: \.self) { w in
                webRow(w)
            }
        } else if showList && loading && q.count >= 3 {
            HStack(spacing: 8) {
                ProgressView()
                Text("Suche …").font(.subheadline).foregroundStyle(KColor.ink2)
            }
        }
        if let hint = form.duplicateHint(data, today: model.today) {
            Label {
                Text(hint)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .font(.footnote)
            .foregroundStyle(KColor.warn)
        }
        CTTemplateRow(form: form)
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Vertragspartner")
                .font(.footnote)
                .foregroundStyle(KColor.ink2)
            HStack(spacing: 8) {
                TextField("z.B. Swisscom", text: Binding(
                    get: { form.partnerName },
                    set: { v in
                        form.userTypedPartner(v)
                        schedule()
                    }))
                    .focused($focused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .foregroundStyle(KColor.ink)
                    .submitLabel(.done)
                Button {
                    focused = false
                    form.showCatalog = true
                } label: {
                    Image(systemName: "book")
                        .foregroundStyle(KColor.teal)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Aus Katalog wählen")
            }
        }
        .padding(.vertical, 2)
        .onChange(of: focused) { _, f in
            if f {
                schedule()
            } else {
                Task {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    if !focused { visible = false }
                }
            }
        }
        .onDisappear { searchTask?.cancel() }
    }

    private func ownRow(_ g: Partners.Group, data: AppData) -> some View {
        let first = data.contract(g.contractIDs.first)
        let dom = Format.domain(of: g.partner.web)
        return Button {
            form.pickOwn(g, data: model.data)
            hide()
        } label: {
            HStack(spacing: 12) {
                if let c = first {
                    MarkView(contract: c, data: data, size: 34)
                } else {
                    MarkView(logoID: g.partner.logoID, logoBg: g.partner.logoBg, colorHex: AppData.hashColor(g.partner.name),
                             symbol: KIcon.symbol(for: nil), size: 34)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(g.partner.name).font(.body.weight(.semibold)).foregroundStyle(KColor.ink)
                    Text(CTText.contracts(g.contractIDs.count) + (dom.isEmpty ? "" : " · " + dom))
                        .font(.footnote)
                        .foregroundStyle(KColor.ink2)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
    }

    private func webRow(_ w: WebPartnerHit) -> some View {
        Button {
            pickWeb(w)
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: CTWebPartners.thumbURL(w)) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFit().padding(3)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(KColor.line, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(w.name).font(.body.weight(.semibold)).foregroundStyle(KColor.ink)
                    Text(w.dom + (w.desc.isEmpty ? "" : " · " + w.desc))
                        .font(.footnote)
                        .foregroundStyle(KColor.ink2)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
    }

    // MARK: Ablauf

    private func schedule() {
        searchTask?.cancel()
        let q = form.partnerName.ctTrimmed
        if q.count < 2 || q == form.pSugSel {
            visible = false
            webHits = []
            loading = false
            return
        }
        visible = true
        webHits = []
        loading = q.count >= 3
        token += 1
        let tok = token
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            let r = await CTWebPartners.search(q)
            if Task.isCancelled || tok != token { return }
            webHits = r
            loading = false
        }
    }

    private func hide() {
        searchTask?.cancel()
        visible = false
        loading = false
        focused = false
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

private struct CTSuggestHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(KColor.ink2)
            .textCase(.uppercase)
            .padding(.top, 2)
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
