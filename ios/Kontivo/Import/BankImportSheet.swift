import SwiftUI
import KontivoCore

/// Fenster «Kontoauszug» (Web `#sheetBank`, Stand v330): Ladeanzeige mit drehendem Ring aus dem Intro-Logo und grüner Box
/// «Bleibt auf deinem Gerät», danach die geführten Schritte Fixkosten → Einnahmen → Fristen. Knopf unten: «Bitte kurz warten …»,
/// «Weiter zu Einnahmen» bzw. «n Einträge übernehmen» («Fertig», wenn nichts Neues gefunden wurde). Links oben «Abbrechen», ab
/// Schritt 2 «‹ Zurück». Wischen schliesst nicht (Web v280: Tippen daneben schliesst nicht); «Abbrechen» mit Ergebnis fragt nach (v285).
struct BankImportSheet: View {
    let sessionID: UUID
    @Environment(AppModel.self) private var model
    @State private var askClose = false

    private var session: BankImportSession? { BankImportCenter.shared.session(sessionID) }

    var body: some View {
        NavigationStack {
            Group {
                if let s = session {
                    switch s.phase {
                    case .loading(let step, let n):
                        BankLoadingView(step: step, nTx: n, logoDone: s.review?.logoDone ?? 0, logoTotal: s.review?.logoTotal ?? 0,
                                        safe: s.input.safeNote)
                    case .failed(let f):
                        BankFailedView(failure: f, onOther: {
                            let m = model, src = s.input.source
                            m.dismissTop { BankImportCenter.shared.pick(src, model: m) }
                        }, onCancel: { model.dismissTop() })
                    case .review:
                        if let r = s.review { BankReviewView(review: r, privacy: s.input.privacyNote) }
                    }
                } else {
                    Color.clear
                }
            }
            .background(KColor.paper.ignoresSafeArea())
            .navigationTitle("Kontoauszug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: leading) {
                        Text(leadingTitle)
                            .font(.system(size: 16))
                            .foregroundStyle(KColor.ink2)
                    }
                    .accessibilityIdentifier("bankCancel")
                }
            }
            .safeAreaInset(edge: .bottom) { footer }
            .alert("Import abbrechen?", isPresented: $askClose) {
                Button("Weiter prüfen", role: .cancel) {}
                Button("Import abbrechen", role: .destructive) { model.dismissTop() }
            } message: {
                Text("Die gefundenen Vorschläge gehen verloren. Du müsstest den Kontoauszug neu einlesen.")
            }
        }
        .interactiveDismissDisabled(true)
        .onDisappear { BankImportCenter.shared.end(sessionID, model: model) }
    }

    private var inReview: Bool {
        if case .review = session?.phase { return true }
        return false
    }

    private var leadingTitle: String {
        if inReview, let r = session?.review, r.stepIndex(model.data) > 0 { return "‹ Zurück" }
        return "Abbrechen"
    }

    /// Web `bkX`: zurück zum vorherigen Schritt, sonst abbrechen (Logos löschen, schliessen)
    private func leading() {
        if inReview, let r = session?.review, r.back(model.data) { return }
        // Schliessen mit Ergebnis: nachfragen, sonst ist die Auswertung weg (Web v285)
        if inReview, let r = session?.review, r.hasResults {
            askClose = true
            return
        }
        model.dismissTop()
    }

    // MARK: Knopf unten (Web `.bkfoot` / `bkFoot`)

    @ViewBuilder private var footer: some View {
        if let s = session {
            switch s.phase {
            case .loading:
                BankFooterButton(title: "Bitte kurz warten …", enabled: false) {}
            case .failed:
                EmptyView()
            case .review:
                if let r = s.review {
                    BankFooterButton(title: r.footerTitle(model.data), enabled: r.footerEnabled(model.data)) { go(s, r) }
                }
            }
        }
    }

    private func go(_ s: BankImportSession, _ r: BankReview) {
        if r.isDoneOnly(model.data) {
            model.dismissTop()
            return
        }
        if !r.isLastStep(model.data) {
            withAnimation(.easeInOut(duration: 0.2)) { r.next(model.data) }
            return
        }
        finish(s, r)
    }

    /// «n Einträge übernehmen»: anlegen, Fenster schliessen, Toast, danach «Fast fertig!» (Web `bkGo`)
    private func finish(_ s: BankImportSession, _ r: BankReview) {
        s.finished = true
        let out = r.apply(model: model)
        let n = out.created.count + out.reactivated, p = out.priced, ni = out.incomes
        model.goTab(n > 0 || p > 0 || ni == 0 ? .contracts : .budget)
        let parts = [n > 0 ? (n == 1 ? "1 Vertrag angelegt" : "\(n) Verträge angelegt") : "",
                     ni > 0 ? (ni == 1 ? "1 Einnahme" : "\(ni) Einnahmen") + (n > 0 ? "" : " angelegt") : "",
                     p > 0 ? (p == 1 ? "1 Preis angepasst" : "\(p) Preise angepasst") : ""].filter { !$0.isEmpty }
        model.toast(parts.joined(separator: ", ") + " — bitte kurz prüfen", seconds: 3.2)
        guard !out.created.isEmpty else { return }
        let open = BankReview.incompleteCount(out.created, data: model.data, today: model.today)
        guard open > 0 else { return }
        let m = model
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            m.ask(title: "Fast fertig!",
                  message: "Bei " + (open == 1 ? "1 neuem Vertrag" : "\(open) neuen Verträgen")
                    + " fehlen noch Angaben wie Kündigungsfrist, Logo oder Absender. In einer Minute erledigt – dann erinnert Kontivo dich rechtzeitig.",
                  ok: "Jetzt vervollständigen", cancel: "Später") {
                m.present(.completeness(only: nil))
            }
        }
    }
}

/// Knopf unten (Web `.bkfoot .primary`): Fläche ink, Schrift paper 16 pt halbfett, 15 pt Innenabstand, Radius 13; aus = 45 %
struct BankFooterButton: View {
    let title: String
    let enabled: Bool
    var id = "bankApply"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(KColor.paper)
                .frame(maxWidth: .infinity, minHeight: 23.2)
                .padding(15)
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(KColor.ink))
                .opacity(enabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(id)
        .padding(.horizontal, 17)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(KColor.paper.ignoresSafeArea(edges: .bottom))
    }
}

// MARK: - Nicht lesbar (Web v278: Meldung mit Dateikarte und «Andere Datei wählen»; nativ im Fenster statt Rückfrage)

/// Nicht lesbare Dateien: Titel, Dateikarten (Name, Grund in Rot), Erklärung
struct BankFailure: Equatable {
    struct File: Equatable {
        var name: String
        var reason: String
    }

    var title: String
    var text: String
    var files: [File]
}

struct BankFailedView: View {
    let failure: BankFailure
    let onOther: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(failure.title)
                    .font(KFont.title(24))
                    .tracking(-0.288)
                    .foregroundStyle(KColor.ink)
                    .padding(.bottom, 6)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("bankFailTitle")
                // `.axfl`: Karten mit Dokument-Symbol, Name 14.5 pt halbfett (eine Zeile), Grund 12.5 pt in Rot; höchstens 3, dann «und n weitere»
                VStack(spacing: 6) {
                    ForEach(Array(failure.files.prefix(3).enumerated()), id: \.offset) { _, f in
                        HStack(spacing: 10) {
                            Image(systemName: "doc")
                                .font(.system(size: 19))
                                .foregroundStyle(KColor.ink3)
                                .frame(width: 22, height: 22)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(f.name)
                                    .font(.system(size: 14.5, weight: .semibold))
                                    .foregroundStyle(KColor.ink)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(f.reason)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(KColor.alert)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KColor.field))
                        .accessibilityElement(children: .combine)
                    }
                    if failure.files.count > 3 {
                        Text("und \(failure.files.count - 3) weitere")
                            .font(.system(size: 12.5))
                            .foregroundStyle(KColor.ink2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 10)
                Text(failure.text)
                    .font(.system(size: 14))
                    .lineSpacing(BankType.extra(14, 19.6))
                    .foregroundStyle(KColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                BankFooterButton(title: "Andere Datei wählen", enabled: true, id: "bankOtherFile", action: onOther)
                    .padding(.horizontal, -17)
                    .padding(.top, 14)
                Button(action: onCancel) {
                    Text("Abbrechen")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(KColor.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 17)
            .padding(.top, 18)
            .kContentWidth()
        }
        .accessibilityIdentifier("bankFailed")
    }
}
