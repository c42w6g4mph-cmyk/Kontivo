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
        .fullScreenCover(item: $model.onboarding) { mode in
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
        content.sheet(item: Binding<AppSheet?>(
            get: { model.sheets.indices.contains(level) ? model.sheets[level] : nil },
            set: { newValue in if newValue == nil { model.dismiss(level: level) } }
        )) { sheet in
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
            .tint(KColor.teal)
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
