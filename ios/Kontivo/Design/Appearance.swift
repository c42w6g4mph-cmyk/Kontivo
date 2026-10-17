import SwiftUI
import UIKit

/// UIKit-Erscheinungsbild für Tabbar und Fenster-Kopfzeilen wie in der Web-App (v164–v186).
/// Einmal beim Start setzen (`RootView.init`), bevor Leisten erzeugt werden.
enum KAppearance {
    private static var done = false

    @MainActor static func apply() {
        guard !done else { return }
        done = true

        // Tabbar (Web `.tabbar`): Beschriftung 11 pt, gewählt Semibold Messing, sonst Medium `--ink2`; Plakette `--brassFab`
        let ink2 = KColor.ui(0x5E6064, 0xA8A7A3)
        let teal = KColor.ui(0x86671F, 0xC6AB78)
        let item = UITabBarItem.appearance()
        item.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 11, weight: .medium), .kern: 0.11, .foregroundColor: ink2], for: .normal)
        item.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 11, weight: .semibold), .kern: 0.11, .foregroundColor: teal], for: .selected)
        item.badgeColor = KColor.ui(0x8F6E22, 0xC6AB78)
        item.setBadgeTextAttributes([.font: UIFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: KColor.ui(0xFFFFFF, 0x1E1D1A)], for: .normal)
        UITabBar.appearance().unselectedItemTintColor = ink2
        UITabBar.appearance().tintColor = teal
        // iOS 26 übernimmt Plakettenfarbe und Beschriftung nur über UITabBarAppearance (Hintergrund bleibt Glas)
        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        for l in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            l.normal.badgeBackgroundColor = KColor.ui(0x8F6E22, 0xC6AB78)
            l.normal.badgeTextAttributes = [.font: UIFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: KColor.ui(0xFFFFFF, 0x1E1D1A)]
            l.normal.iconColor = ink2
            l.normal.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 11, weight: .medium), .kern: 0.11, .foregroundColor: ink2]
            l.selected.iconColor = teal
            l.selected.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 11, weight: .semibold), .kern: 0.11, .foregroundColor: teal]
            l.selected.badgeBackgroundColor = KColor.ui(0x8F6E22, 0xC6AB78)
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        // Fenster-Kopfzeile (Web `.shbar`): Fläche `--surface`, Linie unten `--line`, Titel 18 pt Semibold −0.012em `--ink`
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = KColor.ui(0xFFFFFF, 0x36373B)
        nav.shadowColor = KColor.ui(0xE6E6E3, 0x45464A)
        nav.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 18, weight: .semibold), .kern: -0.216,
                                   .foregroundColor: KColor.ui(0x121314, 0xE8E6E2)]
        nav.largeTitleTextAttributes = [.font: UIFont.systemFont(ofSize: 30, weight: .semibold), .kern: -0.45,
                                        .foregroundColor: KColor.ui(0x121314, 0xE8E6E2)]
        let button = UIBarButtonItemAppearance(style: .plain)
        button.normal.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 16, weight: .regular), .foregroundColor: ink2]
        nav.buttonAppearance = button
        let doneButton = UIBarButtonItemAppearance(style: .done)
        doneButton.normal.titleTextAttributes = [.font: UIFont.systemFont(ofSize: 16, weight: .bold), .foregroundColor: teal]
        nav.doneButtonAppearance = doneButton
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = nav
        bar.scrollEdgeAppearance = nav
        bar.compactAppearance = nav
        bar.tintColor = teal
    }
}
