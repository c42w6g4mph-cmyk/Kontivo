import SwiftUI
import UIKit
import PhotosUI
import VisionKit
import UniformTypeIdentifiers

/// Herkunft eines Kontoauszugs (Plus-Menü «Aus Kontoauszug», Einführung «Automatisch finden»)
enum BankPickSource: Hashable, CaseIterable {
    /// Dateien: CSV, camt.053 (XML), MT940, PDF (mehrere auf einmal)
    case file
    /// Kamera: Dokument-Scanner (mehrere Seiten, entzerrt)
    case camera
    /// Fotomediathek (mehrere Bilder)
    case photos

    /// Titel im Menü
    var title: String {
        switch self {
        case .file: return "Datei wählen"
        case .camera: return "Foto aufnehmen"
        case .photos: return "Aus Fotos wählen"
        }
    }

    /// Zweite Zeile im Menü
    var subtitle: String {
        switch self {
        case .file: return "CSV, camt.053, MT940 oder PDF"
        case .camera: return "Auszug mit der Kamera scannen"
        case .photos: return "Fotos oder Bildschirmfotos vom Auszug"
        }
    }

    /// Titel in der Auswahl (Einführung, ohne zweite Zeile)
    var dialogTitle: String {
        switch self {
        case .file: return "Datei wählen (CSV, PDF)"
        case .camera: return "Foto aufnehmen"
        case .photos: return "Aus Fotos wählen"
        }
    }

    var symbol: String {
        switch self {
        case .file: return "doc"
        case .camera: return "camera"
        case .photos: return "photo.on.rectangle"
        }
    }

    /// Verfügbare Quellen (Kamera nur, wenn das Gerät scannen kann – nicht im Simulator)
    @MainActor static var available: [BankPickSource] {
        allCases.filter { $0 != .camera || VNDocumentCameraViewController.isSupported }
    }
}

/// Systemauswahl für Dateien, Kamera und Fotos – direkt über UIKit vom obersten Fenster präsentiert
/// (kein `.fileImporter` in geteilten Ansichten nötig; mehrere `.fileImporter` in einer Hierarchie stören sich).
@MainActor
final class BankPickers: NSObject {
    static let shared = BankPickers()

    private var onFiles: (([URL]) -> Void)?
    private var onImages: (([UIImage]) -> Void)?

    /// Dateitypen wie Web `#bankFile` (.csv,.txt,.xml,.sta,.mt940,.940) plus PDF und Bilder (nativ)
    static var fileTypes: [UTType] {
        var t: [UTType] = [.commaSeparatedText, .plainText, .text, .xml, .pdf, .image]
        for ext in ["csv", "txt", "xml", "sta", "mt940", "940"] {
            if let u = UTType(filenameExtension: ext), !t.contains(u) { t.append(u) }
        }
        return t
    }

    func pickFiles(_ done: @escaping ([URL]) -> Void) {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: Self.fileTypes, asCopy: true)
        vc.allowsMultipleSelection = true
        vc.delegate = self
        onFiles = done
        present(vc)
    }

    /// Dokument-Scanner (VisionKit). false = auf diesem Gerät nicht verfügbar.
    @discardableResult
    func scan(_ done: @escaping ([UIImage]) -> Void) -> Bool {
        guard VNDocumentCameraViewController.isSupported else { return false }
        let vc = VNDocumentCameraViewController()
        vc.delegate = self
        onImages = done
        present(vc)
        return true
    }

    func pickPhotos(_ done: @escaping ([UIImage]) -> Void) {
        var cfg = PHPickerConfiguration()
        cfg.filter = .images
        cfg.selectionLimit = 0
        cfg.selection = .ordered
        let vc = PHPickerViewController(configuration: cfg)
        vc.delegate = self
        onImages = done
        present(vc)
    }

    private func present(_ vc: UIViewController) {
        guard let top = Self.topViewController() else { return }
        top.present(vc, animated: true)
    }

    /// Oberstes sichtbares Fenster (über allen Sheets)
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var vc = window?.rootViewController
        while let p = vc?.presentedViewController, !p.isBeingDismissed { vc = p }
        return vc
    }

    /// Ergebnis erst weitergeben, wenn die Systemauswahl ganz geschlossen ist (sonst scheitert das nächste Fenster)
    fileprivate func finishFiles(_ urls: [URL]) {
        let f = onFiles
        onFiles = nil
        Self.whenSettled { f?(urls) }
    }

    fileprivate func finishImages(_ images: [UIImage]) {
        let f = onImages
        onImages = nil
        Self.whenSettled { f?(images) }
    }

    /// Wartet (höchstens 1.5 s), bis keine Systemauswahl mehr sichtbar ist oder schliesst
    static func whenSettled(_ action: @escaping () -> Void) {
        Task { @MainActor in
            for _ in 0..<30 {
                guard let top = topViewController() else { break }
                let picker = top is UIDocumentPickerViewController || top is PHPickerViewController || top is VNDocumentCameraViewController
                if !picker && !top.isBeingDismissed && !top.isBeingPresented { break }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
            action()
        }
    }
}

extension BankPickers: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finishFiles(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finishFiles([])
    }
}

extension BankPickers: VNDocumentCameraViewControllerDelegate {
    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        var images: [UIImage] = []
        for i in 0..<scan.pageCount { images.append(scan.imageOfPage(at: i)) }
        controller.dismiss(animated: true)
        finishImages(images)
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
        finishImages([])
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        controller.dismiss(animated: true)
        finishImages([])
    }
}

extension BankPickers: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else {
            finishImages([])
            return
        }
        // Bilder in der gewählten Reihenfolge laden (Seiten eines Auszugs)
        let slots = BankImageSlots(count: results.count)
        let group = DispatchGroup()
        for (i, r) in results.enumerated() where r.itemProvider.canLoadObject(ofClass: UIImage.self) {
            group.enter()
            r.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                slots.set(i, obj as? UIImage)
                group.leave()
            }
        }
        group.notify(queue: .main) {
            Task { @MainActor in BankPickers.shared.finishImages(slots.all) }
        }
    }
}

/// Sammelbehälter für asynchron geladene Bilder (Reihenfolge der Auswahl)
private final class BankImageSlots: @unchecked Sendable {
    private var items: [UIImage?]
    private let lock = NSLock()

    init(count: Int) { items = Array(repeating: nil, count: count) }

    func set(_ i: Int, _ image: UIImage?) {
        lock.lock()
        defer { lock.unlock() }
        if items.indices.contains(i) { items[i] = image }
    }

    var all: [UIImage] {
        lock.lock()
        defer { lock.unlock() }
        return items.compactMap { $0 }
    }
}
