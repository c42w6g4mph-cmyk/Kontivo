import SwiftUI
import UIKit
import KontivoCore

// MARK: - Ansicht

/// Logo-Suche mit Vorschlägen (Wikidata/Commons, App Store, Website-Symbol, Profilbild). Antippen öffnet «Logo zuschneiden»,
/// übernommen wird erst mit dessen «Übernehmen» (Web v258).
/// onPick liefert PNG-Daten (512×512) und die Hintergrundfarbe (Hex); danach schliesst sich das Fenster. Die Auswahl bleibt
/// 20 Minuten gespeichert (erneutes Öffnen zeigt sie sofort, das gewählte Logo markiert, Web v184).
/// Den Toast nach der Übernahme («Logo übernommen» bzw. «Logo gespeichert») zeigt der Aufrufer.
struct LogoSearchSheet: View {
    let name: String
    let currency: Currency
    let web: String
    let onPick: (Data, String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LogoCandidatesView(name: name, currency: currency, web: web) { png, bg in
                    onPick(png, bg)
                    dismiss()
                }
                .padding(KMetric.gutter)
                .frame(maxWidth: KMetric.maxContent)
                .frame(maxWidth: .infinity)
            }
            .background(KColor.paper.ignoresSafeArea())
            .navigationTitle("Logo suchen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}

/// Vorschlagsliste wie im Web (`.lcands`, `paintCands`): Hinweis, Kacheln nebeneinander (64 pt breit, Bild 52 pt), Quelle darunter.
/// Für Formulare auch direkt einbettbar (Web zeigt die Liste unter dem Logo).
struct LogoCandidatesView: View {
    let name: String
    let currency: Currency
    let web: String
    var alt: String = ""
    let onPick: (Data, String) -> Void

    @State private var phase: Phase = .idle
    @State private var cands: [LogoCandidate] = []
    @State private var busyID: String?
    @State private var selected: String?
    @State private var notice: String?
    @State private var noticeTask: Task<Void, Never>?
    /// Geladenes Bild wartet auf «Logo zuschneiden» (Web v258: Übernahme erst nach Bestätigung)
    @State private var cropping: LogoCropItem?
    /// Ansicht noch sichtbar? Spät eintreffende Ergebnisse nur dann zeigen (Web B01 `candSame`)
    @State private var alive = false

    private enum Phase { case idle, searching, done, noName, offline }

    private var primary: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? alt.trimmingCharacters(in: .whitespacesAndNewlines) : n
    }

    private var cacheKey: String { LogoCache.key(primary, currency, web) }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { noticeView }
            .onAppear { alive = true }
            .onDisappear { alive = false }
            .task { await search() }
            .sheet(item: $cropping) { item in
                ImageCropSheet(image: item.image, title: "Logo zuschneiden") { png, bg in
                    choose(item.cand, png: png, bg: bg)
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .idle, .searching:
            message("Suche Logos…")
        case .noName:
            message("Zuerst den Namen eintragen")
        case .offline:
            message("Keine Internetverbindung")
        case .done:
            if cands.isEmpty {
                message("Nichts gefunden. Tipp: Vertragspartner oder Bezeichnung so schreiben, wie die Firma heisst, eine Website eintragen, oder «Logo im Web suchen».")
            } else {
                results
            }
        }
    }

    /// `.lcmsg`: 12.5 pt, ink3, volle Breite
    private func message(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 12.5))
            .foregroundStyle(KColor.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var results: some View {
        let list = Array(cands.prefix(10))
        return VStack(alignment: .leading, spacing: 10) {
            message((list.first?.score ?? 0) >= 3 ? "Tippe auf das passende Logo:" : "Keine eindeutige Übereinstimmung – passt eines davon?")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64, maximum: 64), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                ForEach(list) { c in
                    LogoCandidateTile(c: c, busy: busyID == c.id, selected: selected == c.url) {
                        Task { await pick(c) }
                    }
                    .disabled(busyID != nil)
                }
            }
        }
    }

    @ViewBuilder private var noticeView: some View {
        if let t = notice {
            Text(t)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(Color.black.opacity(0.82)))
                .padding(.horizontal, 24)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    private func show(_ t: String, seconds: Double = 2.4) {
        noticeTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { notice = t }
        noticeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { notice = nil }
        }
    }

    private func search() async {
        guard phase == .idle else { return }
        if primary.isEmpty && Format.domain(of: web).isEmpty {
            phase = .noName
            return
        }
        // letzte Suche (20 min) sofort zeigen
        if let hit = LogoCache.shared.list(cacheKey) {
            cands = hit
            selected = LogoCache.shared.selection(cacheKey)
            phase = .done
            return
        }
        phase = .searching
        if !(await NetCheck.isOnline()) {
            phase = .offline
            return
        }
        let key = cacheKey
        let cs = primary.isEmpty ? [] : await LogoFinder.manualCandidates(name: primary, currency: currency, web: web)
        var all = cs
        if cs.isEmpty, let fc = LogoFinder.faviconCand(Format.domain(of: web)) { all = [fc] }
        LogoCache.shared.setList(key, all)
        // Web B01: Ergebnis nur für dieselbe Suche (Name/Währung/Website unverändert)
        guard key == cacheKey else { return }
        cands = all
        phase = .done
    }

    /// Antippen lädt das Bild und öffnet zuerst «Logo zuschneiden» (Web v258); erst «Übernehmen» setzt das Logo.
    /// Die Liste bleibt stehen: ein anderes Logo lässt sich direkt antippen, ohne neu zu suchen.
    private func pick(_ c: LogoCandidate) async {
        guard busyID == nil else { return }
        if let img = LogoCache.shared.image(c.url) {
            openCrop(c, img)
            return
        }
        busyID = c.id
        show("Lade Logo…", seconds: 30)
        let r = await LogoFinder.take(c)
        busyID = nil
        // Fenster inzwischen geschlossen: nichts mehr anzeigen
        guard alive else { return }
        switch r {
        case .success(let img):
            noticeTask?.cancel()
            notice = nil
            LogoCache.shared.setImage(c.url, img)
            openCrop(c, img)
        case .failure(let e):
            show(e.message)
        }
    }

    private func openCrop(_ c: LogoCandidate, _ img: LogoImage) {
        guard let ui = UIImage(data: img.png) else {
            show("Bild konnte nicht geladen werden")
            return
        }
        cropping = LogoCropItem(cand: c, image: ui)
    }

    private func choose(_ c: LogoCandidate, png: Data, bg: String) {
        cropping = nil
        selected = c.url
        LogoCache.shared.select(cacheKey, c.url)
        onPick(png, bg)
    }
}

/// Bild aus der Vorschlagsliste, das zugeschnitten wird
struct LogoCropItem: Identifiable {
    let id = UUID()
    let cand: LogoCandidate
    let image: UIImage
}

/// Eine Kachel (`.lcand`): Bild 52 pt (weiss, Ring), Titel 10.5 pt, Quelle 9.5 pt; schwach = Bild halb durchsichtig,
/// Wikipedia-Schriftzug eingepasst mit Rand; App-Symbole in der Vorschau schon wie gespeichert (Saum übermalt, Web v186).
struct LogoCandidateTile: View {
    let c: LogoCandidate
    let busy: Bool
    let selected: Bool
    let action: () -> Void
    @State private var preview: UIImage?

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Color.white
                    if let p = preview {
                        Image(uiImage: p).resizable().interpolation(.high).scaledToFill()
                    } else {
                        AsyncImage(url: URL(string: c.thumb)) { ph in
                            if let img = ph.image {
                                if c.src == .wiki {
                                    img.resizable().interpolation(.high).scaledToFit().padding(6)
                                } else {
                                    img.resizable().interpolation(.high).scaledToFill()
                                }
                            } else if ph.error != nil {
                                Image(systemName: "photo").foregroundStyle(Color.gray.opacity(0.5))
                            } else {
                                ProgressView()
                            }
                        }
                    }
                    if busy {
                        Color.black.opacity(0.35)
                        ProgressView().tint(.white)
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(c.score >= 3 ? 1 : 0.55)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? KColor.brass : KColor.line, lineWidth: selected ? 2 : 1))
                Text(c.title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(KColor.ink2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 64)
                Text(c.src.label)
                    .font(.system(size: 9.5))
                    .foregroundStyle(KColor.ink3)
                    .padding(.top, -2)
            }
            .frame(width: 64)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(c.title + ", " + c.src.label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .task(id: c.url) { await makePreview() }
    }

    /// Vorschau wie beim Speichern (nicht für Profilbild/Website-Symbol)
    private func makePreview() async {
        if c.src == .social || c.src == .site { return }
        let big = c.url.replacingOccurrences(of: "/\\d+x\\d+bb\\.(jpg|jpeg|png|webp)$", with: "/512x512bb.png",
                                             options: [.regularExpression, .caseInsensitive])
        var im = await LogoFinder.loadImage(big)
        if im == nil { im = await LogoFinder.loadImage(c.thumb) }
        guard let img = im else { return }
        let tf = LogoTile.fix(img)
        guard tf.tile, let out = LogoTile.draw(img, tf) else { return }
        preview = out
    }
}
