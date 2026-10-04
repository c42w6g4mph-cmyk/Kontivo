import SwiftUI
import UIKit
import KontivoCore

/// Einführung als Vollbild (wie `#onb` der Web-App).
/// Erststart: 8 Seiten (Willkommen, 4 Tabs, Gut zu wissen, Einrichten, Womit fangen wir an?); Tour aus «Mehr»: 6 Seiten.
/// Wischen links/rechts, Fortschrittsstriche oben, «Überspringen» auf den Tab-Seiten. Schliessen setzt `onboarded = 1`.
struct OnboardingView: View {
    let mode: OnboardingMode

    @Environment(AppModel.self) private var model
    @State private var index = 0
    @State private var home: Currency = .EUR
    @State private var moreOpen = false
    @State private var name = ""
    @State private var quick: Int?
    @State private var prepared = false

    private var pages: [OnbPage] { mode == .firstRun ? OnbPage.firstRun : OnbPage.tour }
    /// Index der Seite «Gut zu wissen» – davor gibt es «Überspringen»
    private var tipsIndex: Int { pages.firstIndex(of: .tips) ?? pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            OnbProgress(count: pages.count, index: index)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            TabView(selection: $index) {
                ForEach(pages.indices, id: \.self) { i in
                    pageView(i)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity)
        .background(OnbBackground().ignoresSafeArea())
        .onAppear(perform: prepare)
        .onChange(of: index) { old, new in
            // Einrichten übernehmen, sobald die Seite vorwärts verlassen wird (Knopf oder Wischen)
            if pages.indices.contains(old), pages[old] == .setup, new > old { applySetup() }
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Einführung")
    }

    @ViewBuilder private func pageView(_ i: Int) -> some View {
        switch pages[i] {
        case .welcome:
            OnbWelcomePage(first: mode == .firstRun, onNext: { next(from: i) }, onSecondary: { mode == .firstRun ? backup() : close() })
        case .tab(let t):
            OnbTabPage(tab: t, showSkip: i < tipsIndex, onSkip: skip, onNext: { next(from: i) })
        case .tips:
            OnbTipsPage(isLast: i == pages.count - 1, showSkip: i < tipsIndex, onSkip: skip, onNext: { next(from: i) })
        case .setup:
            OnbSetupPage(home: $home, moreOpen: $moreOpen, name: $name, onNext: { next(from: i) }, onBackup: backup)
        case .start:
            OnbStartPage(items: OnbQuick.items(model.data), quick: $quick, onCreate: create, onDone: close)
        }
    }

    // MARK: Vorbelegung

    /// Hauptwährung: beim echten Erststart EUR; gibt es schon gespeicherte Daten (z.B. nach «Alle Daten löschen»), die bisherige.
    /// Name: erste Person ausser «Ich».
    private func prepare() {
        guard !prepared else { return }
        prepared = true
        let s = model.data.settings
        if mode == .firstRun {
            let saved = FileManager.default.fileExists(atPath: model.files.base.appendingPathComponent("data.json").path)
            home = saved ? s.homeCurrency : .EUR
        } else {
            home = s.homeCurrency
        }
        moreOpen = MoreCurrencyPicker.more.contains(home)
        name = model.data.persons.first(where: { $0.name != "Ich" })?.name ?? ""
    }

    // MARK: Navigation

    private func next(from i: Int) {
        if i < pages.count - 1 {
            withAnimation(.easeInOut(duration: 0.3)) { index = i + 1 }
        } else {
            close()
        }
    }

    /// «Überspringen»: zur Seite Einrichten, in der Tour schliessen
    private func skip() {
        if let s = pages.firstIndex(of: .setup) {
            withAnimation(.easeInOut(duration: 0.3)) { index = s }
        } else {
            close()
        }
    }

    // MARK: Aktionen

    /// Einrichten übernehmen: Hauptwährung (Kurse laden) und Name (ersetzt «Ich», sonst vorne anfügen).
    private func applySetup() {
        let nm = Format.collapseSpaces(name)
        let newHome = home
        var homeChanged = false
        model.update { d in
            if d.settings.homeCurrency != newHome {
                d.settings.homeCurrency = newHome
                homeChanged = true
            }
            guard !nm.isEmpty else { return }
            let last = d.settings.lastHolderIDs
            let lastWasIch = last.count == 1 && d.person(last[0])?.name == "Ich"
            let pid: UUID
            if let existing = d.persons.first(where: { $0.name.lowercased() == nm.lowercased() }) {
                pid = existing.id
            } else if let i = d.persons.firstIndex(where: { $0.name == "Ich" }) {
                d.persons[i].name = nm
                pid = d.persons[i].id
            } else {
                let p = Person(name: nm)
                d.persons.insert(p, at: 0)
                pid = p.id
            }
            if last.isEmpty || lastWasIch { d.settings.lastHolderIDs = [pid] }
        }
        if homeChanged {
            let m = model
            Task { await RateService.refreshIfNeeded(m, force: false) }
        }
    }

    /// Schliessen: gesehen merken, Tab «Verträge»
    private func close(then: (() -> Void)? = nil) {
        model.update { $0.settings.onboarded = 1 }
        model.goTab(.contracts)
        model.closeOnboarding(then: then)
    }

    /// «Ich habe schon ein Backup» / «Backup einspielen»: schliessen, Tab «Mehr», Dateiauswahl für das Backup
    private func backup() {
        close()
        MoreRequests.openBackupImport(model, delay: 0.9)
    }

    /// «{Vorlage} erfassen»: schliessen und das Formular «Neuer Vertrag» mit Bezeichnung und Kategorie öffnen
    private func create() {
        let items = OnbQuick.items(model.data)
        guard let q = quick, let item = items.first(where: { $0.id == q }) else { return }
        let d = model.data
        let draft = Contract(label: item.label, categoryID: item.category?.id,
                             currency: d.settings.homeCurrency, holderIDs: d.defaultHolderIDs)
        let m = model
        // erst öffnen, wenn die Einführung geschlossen ist (Modell meldet das Ende)
        close { m.present(.contractForm(.new(prefill: draft))) }
    }
}
