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
        Task {
            let r = await CTLogoFetch.logo(file: w.file, domain: w.dom)
            if f.closed { return }
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

/// Vorlage-Chips bzw. Hinweistext unter dem Vertragspartner (paintSugg)
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
        case .chips(let hits):
            VStack(alignment: .leading, spacing: 6) {
                Text("Vorlage")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(KColor.ink2)
                CTFlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(hits) { t in
                        Chip(title: t.name, isOn: false) {
                            form.applyTemplate(t, keepName: false, onlyEmpty: false, data: model.data)
                            model.toast("Vorlage übernommen — bitte prüfen")
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}
