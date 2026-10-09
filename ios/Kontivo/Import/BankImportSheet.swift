import SwiftUI
import KontivoCore

/// Fenster «Kontoauszug» → «Vorschläge» (Web `#sheetBank`): Ladeanzeige (Variante 2), Fehlerhinweis oder Vorschlagsliste.
struct BankImportSheet: View {
    let sessionID: UUID
    @Environment(AppModel.self) private var model

    private var session: BankImportSession? { BankImportCenter.shared.session(sessionID) }

    var body: some View {
        NavigationStack {
            Group {
                if let s = session {
                    switch s.phase {
                    case .loading(let step, let n):
                        BankLoadingView(step: step, nTx: n)
                    case .failed(let title, let text):
                        BankFailedView(title: title, text: text) { model.dismissTop() }
                    case .review:
                        if let r = s.review { BankReviewView(review: r, onDone: { finish(r) }) }
                    }
                } else {
                    Color.clear
                }
            }
            .background(KColor.surface.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { model.dismissTop() }
                        .accessibilityIdentifier("bankCancel")
                }
            }
        }
        .onDisappear { BankImportCenter.shared.end(sessionID) }
    }

    private var title: String {
        if case .review = session?.phase { return "Vorschläge" }
        return "Kontoauszug"
    }

    /// «n Verträge anlegen»: anlegen, Fenster schliessen, Toast, danach «Fast fertig!» (Web `bkGo`)
    private func finish(_ r: BankReview) {
        let out = r.apply(model: model)
        let n = out.created.count, p = out.priced
        model.goTab(.contracts)
        let parts = [n > 0 ? (n == 1 ? "1 Vertrag angelegt" : "\(n) Verträge angelegt") : "",
                     p > 0 ? (p == 1 ? "1 Preis angepasst" : "\(p) Preise angepasst") : ""].filter { !$0.isEmpty }
        model.toast(parts.joined(separator: ", ") + " — bitte kurz prüfen", seconds: 3.2)
        let open = BankReview.incompleteCount(out.created, data: model.data, today: model.today)
        guard open > 0 else { return }
        let m = model
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            m.ask(title: "Fast fertig!",
                  message: "Bei " + (open == 1 ? "1 neuem Vertrag" : "\(open) neuen Verträgen")
                    + " fehlen noch Angaben wie Logo oder Kündigungsfrist. In einer Minute erledigt – dann erinnert Kontivo dich rechtzeitig.",
                  ok: "Jetzt vervollständigen", cancel: "Später") {
                m.present(.completeness(only: nil))
            }
        }
    }
}

// MARK: - Ladeanzeige (Variante 2)

struct BankLoadingView: View {
    let step: Int
    let nTx: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var steps: [String] {
        var l = ["Kontoauszug lesen", "Wiederkehrende Zahlungen suchen", "Mit deinen Verträgen abgleichen"]
        if let n = nTx { l[0] = n == 1 ? "1 Buchung gelesen" : "\(n) Buchungen gelesen" }
        return l
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                pulsingLogo
                    .padding(.bottom, 22)
                Text("Kontivo sucht deine Fixkosten")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(KColor.ink)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 6)
                    .accessibilityAddTraits(.isHeader)
                Text("Das dauert nur einen Moment.\nDie Datei bleibt auf diesem Gerät.")
                    .font(.subheadline)
                    .foregroundStyle(KColor.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 22)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(steps.indices, id: \.self) { i in
                        stepRow(i, steps[i])
                    }
                }
                .frame(maxWidth: 300, alignment: .leading)
            }
            .padding(.top, 34)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bankLoading")
    }

    private var pulsingLogo: some View {
        TimelineView(.animation(paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                if !reduceMotion {
                    pulse((t / 1.8).truncatingRemainder(dividingBy: 1))
                    pulse(((t + 0.9) / 1.8).truncatingRemainder(dividingBy: 1))
                }
                Image("Logo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .frame(width: 84, height: 84)
        }
        .accessibilityHidden(true)
    }

    /// bkpulse: Grösse 1 → 1.6, Deckkraft .45 → 0 (ease-out)
    private func pulse(_ p: Double) -> some View {
        let q = 1 - pow(1 - p, 3)
        return RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(KColor.teal)
            .frame(width: 84, height: 84)
            .scaleEffect(1 + 0.6 * q)
            .opacity(0.45 * (1 - q))
    }

    private func stepRow(_ i: Int, _ text: String) -> some View {
        let done = i < step, now = i == step
        return HStack(spacing: 12) {
            ZStack {
                if done {
                    Circle().fill(KColor.ok)
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else if now {
                    ProgressView().controlSize(.small).tint(KColor.teal)
                } else {
                    Circle().strokeBorder(KColor.line, lineWidth: 2)
                }
            }
            .frame(width: 22, height: 22)
            Text(text)
                .font(now ? .body.weight(.semibold) : .body)
                .foregroundStyle(done || now ? KColor.ink : KColor.ink3)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "erledigt" : (now ? "läuft" : ""))
    }
}

// MARK: - Nicht erkannt

struct BankFailedView: View {
    let title: String
    let text: String
    let onOK: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "doc.questionmark")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(KColor.ink3)
                    .padding(.top, 34)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(KColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(KColor.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onOK) {
                    Text("OK").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(KColor.teal)
                .padding(.top, 10)
            }
            .padding(.horizontal, 24)
            .kContentWidth()
        }
    }
}
