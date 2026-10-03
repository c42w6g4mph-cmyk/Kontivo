import SwiftUI
import KontivoCore

#if DEBUG
/// Startargumente für automatische Bildschirmfotos (nur Debug):
///   -uiDemo            Beispieldaten statt gespeicherter Daten (nichts wird gespeichert)
///   -uiEmpty           leere Daten ohne Einführung
///   -uiOnboarding      Einführung (Erststart)
///   -uiTab <name>      contracts | costs | budget | deadlines | more
///   -uiSheet <name>    detail | form | income | incomes | letter | manage | partners | persons | sender | categories | quality | cancelpick
extension AppModel {
    /// true = Argumente angewendet (Initialisierung danach beenden)
    func applyUITestArguments() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        func value(_ key: String) -> String? {
            guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let demo = args.contains("-uiDemo"), empty = args.contains("-uiEmpty"), onb = args.contains("-uiOnboarding")
        guard demo || empty || onb else { return false }
        uiTestMode = true
        if demo, let d = DemoData.make(today: today) {
            data = d
            data.settings.onboarded = 1
        } else {
            data = AppData.initial(homeCurrency: .CHF)
            data.settings.onboarded = onb ? 0 : 1
        }
        onboarding = onb ? .firstRun : nil
        if let t = value("-uiTab"), let tab = AppTab(rawValue: t) { self.tab = tab }
        if let s = value("-uiSheet") {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 800_000_000)
                self?.openUITestSheet(s)
            }
        }
        return true
    }

    private func openUITestSheet(_ s: String) {
        let c = data.contracts.first { $0.status == .active && $0.partnerID != nil }
        let post = data.contracts.first { calc.cancVia($0) == .post && calc.isActive($0) }
        let open = data.contracts.first { calc.cancVia($0) == .none && calc.isActive($0) }
        switch s {
        case "detail": if let c { present(.contractDetail(c.id)) }
        case "form": present(.contractForm(.new(prefill: nil)))
        case "edit": if let c { present(.contractForm(.edit(c.id))) }
        case "income": present(.incomeForm(nil))
        case "incomes": present(.incomesAll)
        case "letter": if let p = post { present(.letter(p.id, trial: false)) }
        case "cancelpick": if let o = open { present(.cancelChannelPick(o.id, trial: false)) }
        case "manage": present(.manage(.overview))
        case "partners": present(.manage(.partners))
        case "persons": present(.manage(.persons))
        case "sender": if let p = data.persons.first { present(.manage(.sender(p.id))) }
        case "categories": present(.manage(.categories))
        case "quality": present(.manage(.quality))
        default: break
        }
    }
}
#endif
