import SwiftUI
import PhotosUI
import UIKit
import KontivoCore

// Einnahmen-Formular: Kopf (Logo, Bezeichnung, Quelle mit Trefferliste), Logo-Bereich, Kacheln (Web `#sheetInc`)

extension KBIncomeForm {
    // MARK: Kopf (Logo, Bezeichnung, Quelle)

    var headSection: some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showLogo.toggle() }
            } label: {
                // Web: Vorschau ohne Logo neutral grau (Inline-Farbe ohne `--c` → Pastell in #5F666E)
                MarkView(logoID: draft.logoID, logoBg: draft.logoBg, colorHex: "#5F666E",
                         symbol: KIcon.symbol(forKey: draft.kind.icon), size: 76)
                    .overlay(alignment: .bottomTrailing) {
                        // Web `.ledit`: 26 pt Kreis Messing mit weissem Rand, Stift
                        KBPencilGlyph()
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                            .frame(width: 12, height: 12)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(KColor.tealFill))
                            .overlay(Circle().strokeBorder(KColor.surface, lineWidth: 2))
                            .offset(x: 5, y: 5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Logo ändern")
            .accessibilityIdentifier("income.logo")
            VStack(spacing: 6) {
                TextField("", text: $draft.label, prompt: Text("Bezeichnung, z.B. Lohn").foregroundColor(KColor.ink3))
                    .font(KFont.title(21))
                    .tracking(-0.252)
                    .foregroundStyle(KColor.ink)
                    .focused($focus, equals: .label)
                    .padding(.horizontal, 10)
                    .frame(height: 42)
                    .background(KColor.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(KBMissRing(on: miss == "label"))
                    .id("label")
                    .accessibilityLabel("Bezeichnung")
                    .accessibilityIdentifier("income.label")
                TextField("", text: $draft.name, prompt: Text("Quelle, z.B. Arbeitgeber AG").foregroundColor(KColor.ink3))
                    .font(.system(size: 16))
                    .foregroundStyle(KColor.ink2)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .name)
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background(KColor.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("Quelle")
                    .accessibilityIdentifier("income.name")
            }
        }
        // Web `.fhead` margin 8 0 4 (die 8 oben fallen mit dem Abstand unter der Kopfzeile zusammen)
        .padding(.bottom, 4)
    }

    // MARK: Trefferliste «Quelle» (Web v222)

    /// Eigene Quellen (bis 3, Name enthält die Eingabe), ohne die gleiche Quelle doppelt
    var ownSources: [Income] {
        let q = draft.name.trimmingCharacters(in: .whitespaces).lowercased()
        var seen = Set<String>()
        var out: [Income] = []
        for i in model.data.incomes where i.id != draft.id {
            let n = i.name.trimmingCharacters(in: .whitespaces)
            let k = n.lowercased()
            if n.isEmpty || seen.contains(k) || !k.contains(q) { continue }
            seen.insert(k)
            out.append(i)
            if out.count == 3 { break }
        }
        return out
    }

    func hideSuggestions() {
        sugTask?.cancel()
        sugHidden = true
        sugWeb = []
        sugLoading = false
    }

    func scheduleSuggestions() {
        sugTask?.cancel()
        let q = draft.name.trimmingCharacters(in: .whitespaces)
        guard focus == .name, q.count >= 2, q != sugSelected else { hideSuggestions(); return }
        sugWeb = []
        sugLoading = q.count >= 3
        sugHidden = ownSources.isEmpty && !sugLoading
        sugTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            let hits = model.uiTestMode ? [] : await CTWebPartners.search(q)
            if Task.isCancelled { return }
            let own = Set(ownSources.map { $0.name.lowercased() })
            sugWeb = hits.filter { !own.contains($0.name.lowercased()) }
            sugLoading = false
            sugHidden = ownSources.isEmpty && sugWeb.isEmpty
        }
    }

    var suggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            let own = ownSources
            if !own.isEmpty {
                sugHead("Deine Quellen")
                ForEach(own) { i in
                    Button { pickOwn(i) } label: {
                        sugRow(mark: AnyView(MarkView(income: i, size: 34)), title: i.name,
                               sub: i.label.isEmpty ? i.kind.displayName : i.label)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !sugWeb.isEmpty {
                sugHead("Aus dem Internet")
                ForEach(sugWeb, id: \.self) { w in
                    Button { pickWeb(w) } label: {
                        sugRow(mark: AnyView(KBWebThumb(url: CTWebPartners.thumbURL(w))), title: w.name,
                               sub: w.dom + (w.desc.isEmpty ? "" : " · " + w.desc))
                    }
                    .buttonStyle(.plain)
                }
            } else if sugLoading {
                Text("Suche …")
                    .font(.system(size: 13))
                    .foregroundStyle(KColor.ink3)
                    .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(KColor.line, lineWidth: 1))
    }

    func sugHead(_ t: String) -> some View {
        Text(verbatim: t)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(KColor.ink3)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    func sugRow(mark: AnyView, title: String, sub: String) -> some View {
        HStack(spacing: 12) {
            mark
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(KColor.ink)
                    .lineLimit(1)
                Text(verbatim: sub)
                    .font(.system(size: 12))
                    .foregroundStyle(KColor.ink2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    /// Eigene Quelle übernehmen: Name und (falls noch keins) Logo
    func pickOwn(_ i: Income) {
        sugSelected = i.name
        draft.name = i.name
        if let l = i.logoID, draft.logoID == nil || model.image(draft.logoID) == nil {
            draft.logoID = l
            draft.logoBg = i.logoBg ?? "#FFFFFF"
        }
        hideSuggestions()
    }

    /// Internet-Treffer übernehmen; Logo laden (Commons, sonst Website-Symbol), nur wenn noch keins gesetzt ist
    func pickWeb(_ w: WebPartnerHit) {
        sugSelected = w.name
        draft.name = w.name
        hideSuggestions()
        if draft.logoID != nil && model.image(draft.logoID) != nil {
            model.toast("Übernommen")
            return
        }
        model.toast("Lade Logo …")
        let before = draft.id
        Task { @MainActor in
            let r = await CTLogoFetch.logo(file: w.file, domain: w.dom)
            guard !closed, draft.id == before, draft.name.trimmingCharacters(in: .whitespaces) == w.name.trimmingCharacters(in: .whitespaces) else { return }
            if let r, draft.logoID == nil || model.image(draft.logoID) == nil, let id = model.storeFile(r.png, type: "image/png") {
                draft.logoID = id
                draft.logoBg = r.bg
                model.toast("Übernommen: Logo")
            } else {
                model.toast("Kein Logo gefunden – unter «Logo» selbst wählen")
            }
        }
    }

    // MARK: Logo

    var logoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { autoFind() } label: {
                Text("Logo automatisch finden")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.tealFill))
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                logoButton("Einfügen") { pasteLogo() }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    KBLogoButtonLabel(title: "Hochladen")
                }
                .buttonStyle(.plain)
                logoButton("Google") { googleSearch() }
            }
            if webHint {
                (Text("So geht’s: ").bold()
                 + Text("In Google das passende Bild lange drücken → «Kopieren». Dann zurück in die App und «Einfügen» tippen."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(KColor.ink2)
            }
            if draft.logoID != nil {
                Button {
                    draft.logoID = nil
                    draft.logoBg = nil
                } label: {
                    KBLogoButtonLabel(title: "Logo entfernen", destructive: true)
                }
                .buttonStyle(.plain)
            }
            Text("Ohne Bild: Symbol der Art")
                .font(.system(size: 12))
                .foregroundStyle(KColor.ink3)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: KBM.cardRadius, style: .continuous).fill(KColor.surface))
    }

    func logoButton(_ t: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { KBLogoButtonLabel(title: t) }
            .buttonStyle(.plain)
    }

    // MARK: Kacheln «pro Monat | pro Jahr» (Web iPaintKz)

    /// Entwurf mit eingetipptem Betrag (Web `iDraftPC`)
    var draftForCalc: Income {
        var t = draft
        t.amount = Format.parseAmount(amountText) ?? 0
        return t
    }

    @ViewBuilder
    var tilesSection: some View {
        let d = draftForCalc
        if d.amount > 0 || !d.prices.isEmpty {
            let cp = model.calc.curPrice(d)
            let cu = d.currency
            HStack(spacing: 8) {
                if d.cycle != 0 {
                    tile("pro Monat", Format.money(cp / Double(d.cycle), cu), cu)
                    tile("pro Jahr", Format.money0(cp / Double(d.cycle) * 12, cu), cu)
                } else {
                    tile("einmalig", Format.money(cp, cu), cu)
                }
            }
            .padding(.top, 12)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("income.tiles")
        }
    }

    /// Web `#iKz > *`: Fläche Feldfarbe, Rundung 12, Wert Serif 22 mit Währung Serif 13
    func tile(_ label: String, _ value: String, _ cu: Currency) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: label)
                .font(.system(size: 12.5))
                .foregroundStyle(KColor.ink2)
                .frame(height: 18)
            (Text(verbatim: value).font(KFont.serif(22, .medium))
                + Text(verbatim: " " + cu.rawValue).font(KFont.serif(13, .medium)).foregroundStyle(KColor.ink2))
                .tracking(-0.22)
                .foregroundStyle(KColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: 31.9)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KColor.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

}
