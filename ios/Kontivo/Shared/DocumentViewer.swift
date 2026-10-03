import SwiftUI
import UIKit
import PDFKit
import MessageUI
import KontivoCore

/// Zeigt eine Datei (PDF/Bild) an; bei einem Brief-PDF mit Aktionen (Text ändern, Mail, Drucken, Teilen).
struct DocumentViewer: View {
    let ref: DocumentRef

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var content: DocViewerContent = .loading
    @State private var fileData: Data?
    @State private var shareURL: URL?

    private var isLetter: Bool { ref.letterContractID != nil }

    private var titleText: String {
        if !ref.title.isEmpty { return ref.title }
        if !ref.fileName.isEmpty { return ref.fileName }
        return "Dokument"
    }

    var body: some View {
        NavigationStack {
            DocViewerBody(content: content)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(KColor.sunken.ignoresSafeArea())
                .navigationTitle(titleText)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left").fontWeight(.semibold)
                                Text(isLetter ? "Zurück" : "Schliessen")
                            }
                        }
                        .accessibilityLabel(isLetter ? "Zurück" : "Schliessen")
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        }
        .onAppear { load() }
        .onDisappear { DocShareFile.remove(shareURL); shareURL = nil }
    }

    // MARK: Laden

    private var resolvedType: String {
        if !ref.type.isEmpty { return ref.type }
        if let id = ref.fileID {
            let t = model.files.type(id)
            if !t.isEmpty { return t }
        }
        return DocShareFile.guessType(ref.fileName)
    }

    /// Dateiname zum Teilen: Name, ohne Endung + «.pdf» bzw. «.jpg».
    private var shareName: String {
        var name = ref.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = ref.title.isEmpty ? "dokument" : ref.title }
        name = name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        if !DocShareFile.hasExtension(name) { name += resolvedType == "application/pdf" ? ".pdf" : ".jpg" }
        return name
    }

    private func load() {
        if case .loading = content {
            let data = ref.data ?? model.files.data(ref.fileID)
            guard let data else {
                content = .message("Diese Datei ist auf diesem Gerät nicht vorhanden. Spiele ein Backup mit Dateien ein oder hänge sie neu an.")
                return
            }
            fileData = data
            let type = resolvedType
            if type.hasPrefix("image/") {
                if let img = UIImage(data: data) { content = .image(img) } else { content = .message("Das Bild konnte nicht geladen werden.") }
            } else if type == "application/pdf" {
                if let doc = PDFDocument(data: data) {
                    content = .pdf(doc)
                } else {
                    content = .message(isLetter
                        ? "Die Vorschau lässt sich nicht anzeigen. Senden, Drucken und Sichern funktionieren trotzdem über die Knöpfe unten."
                        : "Das PDF lässt sich hier nicht anzeigen. Tippe auf «Teilen», dann öffnet es sich in der Dateien-App.")
                }
            } else {
                content = .message("Für diesen Dateityp gibt es keine Vorschau. Tippe auf «Teilen».")
            }
        }
        // Datei zum Teilen (mit richtigem Namen) bereitstellen
        if let d = fileData, shareURL == nil || !FileManager.default.fileExists(atPath: shareURL!.path) {
            shareURL = DocShareFile.write(d, name: shareName)
        }
    }

    // MARK: Aktionen

    private var letterInfo: LetterDocumentInfo {
        if let i = LetterDocumentStore.get(ref.id) { return i }
        guard let id = ref.letterContractID, let c = model.data.contract(id) else { return LetterDocumentInfo.empty }
        return LetterDocumentInfo.fallback(c, calc: model.calc)
    }

    @ViewBuilder private var actionBar: some View {
        let hasData = fileData != nil
        HStack(spacing: 8) {
            if isLetter {
                let info = letterInfo
                DocActionButton(title: "Text ändern", symbol: "pencil") { dismiss() }
                if !info.isRent {
                    DocActionButton(title: "Als E-Mail-Text", symbol: "text.alignleft") { mailAsText(info) }
                }
                DocActionButton(title: "Per Mail senden", symbol: "envelope") { sendMail(info) }
                    .disabled(!hasData)
                DocActionButton(title: "Drucken", symbol: "printer") { printDocument() }
                    .disabled(!hasData)
            }
            shareTile(enabled: hasData)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: KMetric.maxContent + 120)
        .frame(maxWidth: .infinity)
        .background(KColor.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(KColor.line).frame(height: 0.5) }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    @ViewBuilder private func shareTile(enabled: Bool) -> some View {
        if let url = shareURL, enabled {
            ShareLink(item: url) {
                DocActionLabel(title: "Teilen", symbol: "square.and.arrow.up", prominent: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isLetter ? "PDF teilen" : "Teilen")
        } else {
            DocActionButton(title: "Teilen", symbol: "square.and.arrow.up", prominent: true) {
                model.toast("Teilen fehlgeschlagen")
            }
            .disabled(!enabled)
        }
    }

    /// «Per Mail senden»: Mail mit PDF-Anhang; nach dem Senden Rückfrage «Gekündigt?» (nicht bei Miete).
    private func sendMail(_ info: LetterDocumentInfo) {
        guard let data = fileData else { return }
        guard MFMailComposeViewController.canSendMail() else {
            model.toast("Auf diesem Gerät ist kein Mail-Konto eingerichtet. Tippe auf «Teilen».")
            return
        }
        let draft = MailDraft(to: info.recipient.isEmpty ? [] : [info.recipient],
                              subject: info.subject,
                              body: info.attachmentMailBody,
                              attachment: data,
                              attachmentName: shareName,
                              attachmentType: "application/pdf",
                              cancelContractID: info.isRent ? nil : ref.letterContractID,
                              cancelTrial: ref.letterTrial)
        model.present(.mail(draft))
    }

    /// «Als E-Mail-Text»: Text in die Zwischenablage, dann Mail ohne Anhang.
    private func mailAsText(_ info: LetterDocumentInfo) {
        UIPasteboard.general.string = info.mailText
        model.toast(info.recipient.isEmpty ? "Text kopiert. Empfänger in Mail eintragen" : "Text kopiert, Mail wird geöffnet")
        let contractID = ref.letterContractID
        let trial = ref.letterTrial
        let m = model
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if MFMailComposeViewController.canSendMail() {
                m.present(.mail(MailDraft(to: info.recipient.isEmpty ? [] : [info.recipient], subject: info.subject, body: info.mailText,
                                          cancelContractID: contractID, cancelTrial: trial)))
            } else if let url = CancelLinks.mailto(to: info.recipient, subject: info.subject, body: info.mailText) {
                m.cancelFlowOpenExternal(url, pending: contractID.map { PendingCancel(contractID: $0, trial: trial) })
            }
        }
    }

    private func printDocument() {
        guard let data = fileData else { return }
        guard UIPrintInteractionController.canPrint(data) else {
            model.toast("Drucken ist für diese Datei nicht möglich")
            return
        }
        let pic = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = resolvedType.hasPrefix("image/") ? .photo : .general
        info.jobName = shareName
        pic.printInfo = info
        pic.printingItem = data
        if UIDevice.current.userInterfaceIdiom == .pad, let top = CancelFlowUI.topViewController(), let v = top.view {
            // iPad: Druckdialog als Popover über der Aktionsleiste
            let rect = CGRect(x: v.bounds.midX - 1, y: v.bounds.maxY - 90, width: 2, height: 2)
            _ = pic.present(from: rect, in: v, animated: true, completionHandler: nil)
        } else {
            _ = pic.present(animated: true, completionHandler: nil)
        }
    }
}

// MARK: - Inhalt

enum DocViewerContent {
    case loading
    case pdf(PDFDocument)
    case image(UIImage)
    case message(String)
}

private struct DocViewerBody: View {
    let content: DocViewerContent

    var body: some View {
        switch content {
        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                Text("Wird geladen…").font(.subheadline).foregroundStyle(KColor.ink2)
            }
        case .pdf(let doc):
            DocPDFView(document: doc)
                .ignoresSafeArea(edges: .bottom)
                .accessibilityLabel("PDF-Vorschau")
        case .image(let img):
            DocZoomImage(image: img)
                .padding(14)
                .accessibilityLabel("Bild")
        case .message(let text):
            Text(text)
                .font(.subheadline)
                .foregroundStyle(KColor.ink2)
                .multilineTextAlignment(.center)
                .padding(28)
                .frame(maxWidth: 460)
        }
    }
}

/// Grau wie `--sunken` (für UIKit-Ansichten)
private let docSunkenUIColor = UIColor { tc in
    UIColor(rgb: tc.userInterfaceStyle == .dark ? 0x272B30 : 0xE9E6DF)
}

private struct DocPDFView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.autoScales = true
        v.pageShadowsEnabled = true
        v.pageBreakMargins = UIEdgeInsets(top: 7, left: 14, bottom: 7, right: 14)
        v.backgroundColor = docSunkenUIColor
        v.document = document
        return v
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document !== document { uiView.document = document }
    }
}

/// Bild mit Zoom (zwei Finger, Doppeltipp nicht nötig)
private struct DocZoomImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let sv = UIScrollView()
        sv.minimumZoomScale = 1
        sv.maximumZoomScale = 5
        sv.backgroundColor = .clear
        sv.showsVerticalScrollIndicator = false
        sv.showsHorizontalScrollIndicator = false
        sv.delegate = context.coordinator
        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        sv.addSubview(iv)
        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: sv.contentLayoutGuide.leadingAnchor),
            iv.trailingAnchor.constraint(equalTo: sv.contentLayoutGuide.trailingAnchor),
            iv.topAnchor.constraint(equalTo: sv.contentLayoutGuide.topAnchor),
            iv.bottomAnchor.constraint(equalTo: sv.contentLayoutGuide.bottomAnchor),
            iv.widthAnchor.constraint(equalTo: sv.frameLayoutGuide.widthAnchor),
            iv.heightAnchor.constraint(equalTo: sv.frameLayoutGuide.heightAnchor),
        ])
        context.coordinator.imageView = iv
        return sv
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        if context.coordinator.imageView?.image !== image { context.coordinator.imageView?.image = image }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    }
}

// MARK: - Aktionsleiste

struct DocActionLabel: View {
    let title: String
    let symbol: String
    var prominent: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .regular))
                .frame(height: 22)
            Text(title)
                .font(.caption2.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .padding(.vertical, 6)
        .padding(.horizontal, 3)
        .foregroundStyle(prominent ? Color.white : KColor.ink)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(prominent ? KColor.teal : KColor.field))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct DocActionButton: View {
    let title: String
    let symbol: String
    var prominent: Bool = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            DocActionLabel(title: title, symbol: symbol, prominent: prominent)
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

// MARK: - Dateien zum Teilen

enum DocShareFile {
    /// Typ aus der Endung (`guessType`), unbekannt → "".
    static func guessType(_ name: String) -> String {
        let n = name.lowercased()
        if n.hasSuffix(".pdf") { return "application/pdf" }
        if n.hasSuffix(".png") { return "image/png" }
        if n.hasSuffix(".jpg") || n.hasSuffix(".jpeg") { return "image/jpeg" }
        if n.hasSuffix(".webp") { return "image/webp" }
        if n.hasSuffix(".heic") { return "image/heic" }
        if n.hasSuffix(".gif") { return "image/gif" }
        return ""
    }

    /// Endung mit 2–5 Buchstaben/Ziffern vorhanden?
    static func hasExtension(_ name: String) -> Bool {
        guard let dot = name.lastIndex(of: ".") else { return false }
        let ext = name[name.index(after: dot)...]
        return (2...5).contains(ext.count) && ext.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// Schreibt die Daten unter dem gewünschten Namen in einen eigenen temporären Ordner.
    static func write(_ data: Data, name: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Teilen", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(name.isEmpty ? "dokument" : name)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func remove(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
