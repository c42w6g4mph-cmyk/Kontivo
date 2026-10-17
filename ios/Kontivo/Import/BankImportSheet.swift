import SwiftUI
import KontivoCore

/// Fenster «Kontoauszug» (Web `#sheetBank`, v177–v223): Ladeanzeige mit drehendem Ring aus dem Intro-Logo und grüner Box
/// «Bleibt auf deinem Gerät», danach die geführten Schritte Fixkosten → Einnahmen → Fristen. Knopf unten: «Bitte kurz warten …»,
/// «Weiter» bzw. «n Einträge übernehmen». Links oben «Abbrechen», ab Schritt 2 «‹ Zurück».
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
                        BankLoadingView(step: step, nTx: n, logoDone: s.review?.logoDone ?? 0, logoTotal: s.review?.logoTotal ?? 0,
                                        safe: s.input.safeNote)
                    case .failed(let title, let text):
                        BankFailedView(title: title, text: text) { model.dismissTop() }
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
        }
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
                        .accessibilityIdentifier("bankApply")
                }
            }
        }
    }

    private func go(_ s: BankImportSession, _ r: BankReview) {
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
        let n = out.created.count, p = out.priced, ni = out.incomes
        model.goTab(n > 0 || p > 0 || ni == 0 ? .contracts : .budget)
        let parts = [n > 0 ? (n == 1 ? "1 Vertrag angelegt" : "\(n) Verträge angelegt") : "",
                     ni > 0 ? (ni == 1 ? "1 Einnahme" : "\(ni) Einnahmen") + (n > 0 ? "" : " angelegt") : "",
                     p > 0 ? (p == 1 ? "1 Preis angepasst" : "\(p) Preise angepasst") : ""].filter { !$0.isEmpty }
        model.toast(parts.joined(separator: ", ") + " — bitte kurz prüfen", seconds: 3.2)
        guard n > 0 else { return }
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
        .padding(.horizontal, 17)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(KColor.paper.ignoresSafeArea(edges: .bottom))
    }
}

// MARK: - Ladeanzeige (Web `bkLoad`)

struct BankLoadingView: View {
    let step: Int
    let nTx: Int?
    let logoDone: Int
    let logoTotal: Int
    let safe: String

    private var steps: [String] {
        var l = ["Kontoauszug lesen", "Wiederkehrende Zahlungen suchen", "Mit deinen Verträgen abgleichen", "Logos suchen"]
        if logoTotal > 0 { l[3] = "Logos suchen (\(logoDone) von \(logoTotal))" }
        if let n = nTx { l[0] = n == 1 ? "1 Buchung gelesen" : "\(n) Buchungen gelesen" }
        return l
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                BankSpinLogo()
                    .padding(.bottom, 22)
                Text("Kontivo sucht deine Fixkosten")
                    .font(.system(size: 21, weight: .bold))
                    .tracking(-0.21)
                    .foregroundStyle(KColor.ink)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 6)
                    .accessibilityAddTraits(.isHeader)
                Text("Das dauert nur einen Moment.")
                    .font(.system(size: 15))
                    .lineSpacing(15 * 0.4 - 3)
                    .foregroundStyle(KColor.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 22)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(steps.indices, id: \.self) { i in
                        stepRow(i, steps[i])
                    }
                }
                .frame(maxWidth: 300, alignment: .leading)
                BankSafeNote(text: safe)
                    .padding(.top, 26)
            }
            .padding(.top, 34)
            .padding(.horizontal, 8)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 17)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bankLoading")
    }

    /// `.bksteps li`: Kreis 22 pt (Rand 2 pt), erledigt = Messing mit Haken, laufend = drehender Ring, Text 16 pt
    private func stepRow(_ i: Int, _ text: String) -> some View {
        let done = i < step, now = i == step
        return HStack(spacing: 12) {
            ZStack {
                if done {
                    Circle().fill(KColor.brass)
                    Text("✓").font(.system(size: 13)).foregroundStyle(KColor.onBrass)
                } else if now {
                    BankSpinner(size: 22, line: 2)
                } else {
                    Circle().strokeBorder(KColor.line, lineWidth: 2)
                }
            }
            .frame(width: 22, height: 22)
            Text(text)
                .font(.system(size: 16, weight: now ? .semibold : .regular))
                .foregroundStyle(done || now ? KColor.ink : KColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "erledigt" : (now ? "läuft" : ""))
    }
}

/// Drehender Ring (Web `.bksteps .now i`, `.bkload2 i`): Rand in Akzent 25 %, oben voller Akzent, 0.8 s je Umdrehung
struct BankSpinner: View {
    var size: CGFloat
    var line: CGFloat
    var period: Double = 0.8
    var top: Color = KColor.teal
    var track: Color = KColor.teal.opacity(0.25)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { ctx in
            let p = reduceMotion ? 2.4 : period
            let a = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: p) / p * 360
            ZStack {
                Circle().strokeBorder(track, lineWidth: line)
                // border-top eines Kreises = Viertelbogen oben
                Circle()
                    .inset(by: line / 2)
                    .trim(from: 0.625, to: 0.875)
                    .stroke(top, lineWidth: line)
            }
            .rotationEffect(.degrees(a))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Intro-Logo (Web `#splash .splLogo`, `BK_LOGO`): schwarze Kachel, heller Ring, Messing-Segment dreht sich um das K (1.4 s),
/// 84 pt, Radius 20, Schatten 0 10 26 rgba(0,0,0,.22)
struct BankSpinLogo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { ctx in
            let p = reduceMotion ? 4.0 : 1.4
            let a = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: p) / p * 360
            Canvas { g, size in
                Self.draw(g, size: size, angle: a)
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 13, y: 10)
        .accessibilityHidden(true)
    }

    static let light = Color(red: 0xEC / 255, green: 0xEA / 255, blue: 0xE6 / 255)
    static let dark = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x13 / 255)
    static let brass = Color(red: 0xC6 / 255, green: 0xAB / 255, blue: 0x78 / 255)

    /// SVG viewBox 0 0 1024 1024
    static func draw(_ g: GraphicsContext, size: CGSize, angle: Double) {
        let k = size.width / 1024
        var c = g
        c.scaleBy(x: k, y: k)
        c.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024), cornerRadius: 228), with: .color(dark))
        let ctr = CGPoint(x: 512, y: 512)
        c.stroke(Path(ellipseIn: CGRect(x: 512 - 382, y: 512 - 382, width: 764, height: 764)), with: .color(light), lineWidth: 64)
        // Segment: von oben (−90°) im Uhrzeigersinn bis 30°, dreht sich um die Mitte
        var seg = Path()
        seg.addArc(center: ctr, radius: 382, startAngle: .degrees(-90 + angle), endAngle: .degrees(30 + angle), clockwise: false)
        c.stroke(seg, with: .color(brass), style: StrokeStyle(lineWidth: 64, lineCap: .butt))
        // K: translate(512 512) scale(0.88) translate(-516.4 -512)
        var kc = c
        kc.translateBy(x: 512, y: 512)
        kc.scaleBy(x: 0.88, y: 0.88)
        kc.translateBy(x: -516.4, y: -512)
        var stem = Path()
        stem.addLines([CGPoint(x: 339.78, y: 292), CGPoint(x: 393.78, y: 292), CGPoint(x: 439.78, y: 349.5), CGPoint(x: 439.78, y: 732), CGPoint(x: 339.78, y: 732)])
        stem.closeSubpath()
        kc.fill(stem, with: .color(light))
        var arm = Path()
        arm.move(to: CGPoint(x: 693, y: 792))
        arm.addLine(to: CGPoint(x: 469, y: 512))
        arm.addLine(to: CGPoint(x: 693, y: 232))
        kc.clip(to: Path(CGRect(x: 0, y: 292, width: 1024, height: 440)))
        kc.stroke(arm, with: .color(dark), style: StrokeStyle(lineWidth: 144, lineCap: .butt, lineJoin: .miter))
        kc.stroke(arm, with: .color(light), style: StrokeStyle(lineWidth: 80, lineCap: .butt, lineJoin: .miter))
    }
}

/// Grüne Box «Bleibt auf deinem Gerät.» (Web v201 `.safenote`, gleich wie in der Einführung): Schloss 22 pt in Grün,
/// Text 13 pt (Zeilenhöhe 1.4), Fläche Grün 9 % über surface, Radius 16, höchstens 360 pt breit
struct BankSafeNote: View {
    let text: String
    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Canvas { g, size in
                let k = size.width / 24
                var c = g
                c.scaleBy(x: k, y: k)
                let style = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                c.stroke(Path(roundedRect: CGRect(x: 5, y: 10.5, width: 14, height: 10), cornerRadius: 2), with: .color(KColor.ok), style: style)
                var arc = Path()
                arc.move(to: CGPoint(x: 8, y: 10.5))
                arc.addLine(to: CGPoint(x: 8, y: 8))
                arc.addArc(center: CGPoint(x: 12, y: 8), radius: 4, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                arc.addLine(to: CGPoint(x: 16, y: 10.5))
                c.stroke(arc, with: .color(KColor.ok), style: style)
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
            (Text("Bleibt auf deinem Gerät.").fontWeight(.semibold).foregroundColor(KColor.ok) + Text(" " + text).foregroundColor(KColor.ink2))
                .font(.system(size: 13))
                .lineSpacing(13 * 0.4 - 2.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: 360)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(KColor.surface)
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(KColor.ok.opacity(0.09))
            }
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Nicht erkannt (nativ: Fenster bleibt mit Erklärung statt Web-Rückfrage)

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
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(KColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(KColor.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                BankFooterButton(title: "OK", enabled: true, action: onOK)
                    .padding(.horizontal, -17)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 24)
            .kContentWidth()
        }
    }
}
