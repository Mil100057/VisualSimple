//
//  PDFTabDocument.swift
//  VisualSimple
//

import AppKit
import PDFKit
import UniformTypeIdentifiers

/// A PDF shown one page at a time; every page becomes an image document on demand,
/// so the blur tools and undo stack work per page. Untouched pages are written back as they are.
@Observable
final class PDFTabDocument: TabDocument {
    let id = UUID()
    private(set) var fileURL: URL?
    private(set) var currentPageIndex = 0
    private(set) var isModified = false
    @ObservationIgnored private let pdf: PDFDocument
    @ObservationIgnored private var pages: [ImageDocument?]
    @ObservationIgnored private var observation: Any?

    var pageCount: Int { pdf.pageCount }
    var isBlank: Bool { false }
    var fileName: String { fileURL?.lastPathComponent ?? "Document.pdf" }
    var fileTypeLabel: String { ".pdf" }
    var undoManager: UndoManager { current.undoManager }

    /// The page on screen, rendered on first access.
    var current: ImageDocument {
        page(at: currentPageIndex)
    }

    init(url: URL) throws {
        _ = url.startAccessingSecurityScopedResource()
        guard let document = PDFDocument(url: url), document.pageCount > 0 else {
            url.stopAccessingSecurityScopedResource()
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        fileURL = url
        pdf = document
        pages = Array(repeating: nil, count: document.pageCount)
        BlurRenderer.warmUp()
    }

    func page(at index: Int) -> ImageDocument {
        if let existing = pages[index] { return existing }
        let image = Self.render(pdf.page(at: index)!)
        let document = ImageDocument(image: image, name: String(localized: "Page \(index + 1)"))
        if let previous = pages.compactMap({ $0 }).last {
            document.tool = previous.tool
            document.effect = previous.effect
            document.strength = previous.strength
        }
        document.onEditsChanged = { [weak self] in self?.refreshModified() }
        pages[index] = document
        return document
    }

    func goToPage(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        currentPageIndex = index
    }

    func nextPage() { goToPage(currentPageIndex + 1) }
    func previousPage() { goToPage(currentPageIndex - 1) }

    private func refreshModified() {
        isModified = pages.contains { $0?.hasEdits == true }
    }

    /// Bitmap of the page at 2x, capped so the longest side stays under 4000 pixels.
    private static func render(_ page: PDFPage) -> CGImage {
        let bounds = page.bounds(for: .mediaBox)
        var scale: CGFloat = 2
        let longest = max(bounds.width, bounds.height)
        if longest * scale > 4000 { scale = 4000 / longest }
        let width = max(1, Int(bounds.width * scale))
        let height = max(1, Int(bounds.height * scale))
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()!
    }

    // MARK: Saving

    func save() throws -> Bool {
        try saveAs()
    }

    func saveAs() throws -> Bool {
        let panel = NSSavePanel()
        let base = fileURL?.deletingPathExtension().lastPathComponent ?? "Document"
        panel.nameFieldStringValue = String(localized: "\(base) (blurred).pdf")
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        if let directory = fileURL?.deletingLastPathComponent() {
            panel.directoryURL = directory
        }
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        try write(to: url)
        return true
    }

    /// Untouched pages are drawn straight from the source (vectors kept);
    /// edited pages are replaced by their rendered bitmap at the same size.
    func write(to url: URL) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            var box = page.bounds(for: .mediaBox)
            let pageInfo: [CFString: Any] = [kCGPDFContextMediaBox: NSData(bytes: &box, length: MemoryLayout<CGRect>.size)]
            context.beginPDFPage(pageInfo as CFDictionary)
            if let edited = pages[index], edited.hasEdits {
                context.draw(edited.rendered, in: CGRect(origin: .zero, size: box.size))
            } else {
                context.translateBy(x: -box.minX, y: -box.minY)
                page.draw(with: .mediaBox, to: context)
            }
            context.endPDFPage()
        }
        context.closePDF()
    }

    func releaseFileAccess() {
        fileURL?.stopAccessingSecurityScopedResource()
    }

    func discardUndoHistory() {
        for page in pages { page?.discardUndoHistory() }
    }
}
