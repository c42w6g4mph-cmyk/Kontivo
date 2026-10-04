import SwiftUI
import KontivoCore

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            NavigationStack { ContractsTab() }
                .tabItem { Label("Verträge", systemImage: "doc.text") }
                .tag(AppTab.contracts)
            NavigationStack { CostsTab() }
                .tabItem { Label("Kosten", systemImage: "chart.bar") }
                .tag(AppTab.costs)
            NavigationStack { BudgetTab() }
                .tabItem { Label("Budget", systemImage: "wallet.pass") }
                .tag(AppTab.budget)
            NavigationStack { DeadlinesTab() }
                .tabItem { Label("Fristen", systemImage: "stopwatch") }
                .badge(model.calc.deadlineBadgeCount)
                .tag(AppTab.deadlines)
            NavigationStack { MoreTab() }
                .tabItem { Label("Mehr", systemImage: "ellipsis") }
                .tag(AppTab.more)
        }
        .modifier(SheetLevel(level: 0))
        .overlay(alignment: .bottom) {
            if model.sheets.isEmpty { ToastView() }
        }
        .modifier(CancelQuestionModifier(isTop: model.sheets.isEmpty))
        .modifier(PromptModifier(isTop: model.sheets.isEmpty))
        .fullScreenCover(item: $model.onboarding, onDismiss: { model.onboardingDidDismiss() }) { mode in
            OnboardingView(mode: mode)
                .environment(model)
        }
    }
}

/// Präsentiert model.sheets[level] und darüber rekursiv die nächste Ebene.
struct SheetLevel: ViewModifier {
    @Environment(AppModel.self) private var model
    let level: Int

    func body(content: Content) -> some View {
        // Wert im body lesen (Beobachtung), Schliessen meldet onDismiss an das Modell (Fensterwechsel ohne feste Wartezeiten)
        let item = model.sheets.indices.contains(level) ? model.sheets[level] : nil
        content.sheet(item: Binding<AppSheet?>(
            get: { item },
            set: { newValue in if newValue == nil { model.dismiss(level: level) } }
        ), onDismiss: { model.sheetDidDismiss(level: level) }) { sheet in
            AppSheetView(sheet: sheet, level: level)
                .modifier(SheetLevel(level: level + 1))
                .environment(model)
        }
    }
}

/// Inhalt eines Fensters je nach Art
struct AppSheetView: View {
    @Environment(AppModel.self) private var model
    let sheet: AppSheet
    let level: Int

    var body: some View {
        content
            .overlay(alignment: .bottom) {
                if model.sheets.count - 1 == level { ToastView() }
            }
            .modifier(CancelQuestionModifier(isTop: model.sheets.count - 1 == level))
            .modifier(PromptModifier(isTop: model.sheets.count - 1 == level))
            .tint(KColor.teal)
            // Fenster übernehmen die Umgebung der App nicht zuverlässig: Datumsauswahl sonst im US-Format («10/3/26»)
            .environment(\.locale, Locale(identifier: "de_CH"))
    }

    @ViewBuilder private var content: some View {
        switch sheet {
        case .contractDetail(let id):
            ContractDetailView(contractID: id)
        case .contractForm(let ctx):
            ContractFormView(context: ctx)
                .interactiveDismissDisabled(true)
        case .incomeForm(let id):
            IncomeFormView(incomeID: id)
                .interactiveDismissDisabled(true)
        case .incomesAll:
            IncomesAllView()
        case .letter(let id, let trial):
            LetterView(contractID: id, trial: trial)
        case .cancelChannelPick(let id, let trial):
            CancelChannelPickView(contractID: id, trial: trial)
                .presentationDetents([.medium])
        case .mail(let draft):
            MailComposeView(draft: draft)
                .ignoresSafeArea()
        case .document(let ref):
            DocumentViewer(ref: ref)
        case .manage(let route):
            ManageView(start: route)
        }
    }
}

/// Rückfrage «Gekündigt?» nach Rückkehr von Website/Mail – immer auf der obersten Ebene
struct CancelQuestionModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    let isTop: Bool

    func body(content: Content) -> some View {
        content.alert(
            "Gekündigt?",
            isPresented: Binding(get: { isTop && model.cancelQuestion != nil },
                                 set: { if !$0 { model.cancelQuestion = nil } }),
            presenting: model.cancelQuestion
        ) { q in
            Button("Ja, gekündigt") { model.answerCancelQuestion(q, cancelled: true) }
            Button("Noch nicht", role: .cancel) { model.answerCancelQuestion(q, cancelled: false) }
        } message: { q in
            Text(model.cancelQuestionText(q))
        }
    }
}

/// Allgemeine Rückfrage (`model.ask`) – immer auf der obersten Ebene.
/// Hängt an einem Hintergrund, damit sie sich nicht mit dem Alert «Gekündigt?» an derselben Ansicht stört.
struct PromptModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    let isTop: Bool

    func body(content: Content) -> some View {
        let p = model.prompt
        content.background {
            Color.clear
                .alert(
                    p?.title ?? "",
                    isPresented: Binding(get: { isTop && p != nil },
                                         set: { if !$0, model.prompt?.id == p?.id { model.prompt = nil } }),
                    presenting: p
                ) { q in
                    Button(q.ok, role: q.destructive ? .destructive : nil) {
                        model.prompt = nil
                        // nach dem Schliessen des Alerts ausführen (Folgefenster/-rückfragen)
                        Task { @MainActor in q.action() }
                    }
                    Button(q.cancel, role: .cancel) {
                        model.prompt = nil
                        if let c = q.onCancel { Task { @MainActor in c() } }
                    }
                } message: { q in
                    if !q.message.isEmpty { Text(q.message) }
                }
        }
    }
}

/// Kurze Meldung unten (wie der Toast der Web-App)
struct ToastView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let t = model.toastText {
            Text(t)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(Color.black.opacity(0.82)))
                .padding(.horizontal, 24)
                .padding(.bottom, 64)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
                .accessibilityAddTraits(.isStaticText)
        }
    }
}
