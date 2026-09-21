//
//  DocumentStore.swift
//  VisualSimple
//

import AppKit
import Foundation
import UniformTypeIdentifiers

enum SaveFormat: String, CaseIterable, Identifiable {
    case none, txt, md, json, yaml, html, xml, csv, tsv, swift, css, js, ts, sh, log, ini, toml, env
    case sql, rs, go, c, cpp, m, java, kt, plist, strings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: String(localized: "none")
        default: ".\(rawValue)"
        }
    }

    var hasExtension: Bool { self != .none }

    var utType: UTType {
        switch self {
        case .none, .txt, .log, .env, .ini, .toml, .strings, .tsv, .sql, .rs, .go, .java, .kt: UTType(filenameExtension: rawValue) ?? .plainText
        case .c: .cSource
        case .cpp: .cPlusPlusSource
        case .m: .objectiveCSource
        case .ts: UTType(filenameExtension: "ts") ?? .javaScript
        case .plist: .propertyList
        case .md: UTType(filenameExtension: "md") ?? .plainText
        case .json: .json
        case .yaml: UTType(filenameExtension: "yaml") ?? .plainText
        case .html: .html
        case .xml: .xml
        case .csv: .commaSeparatedText
        case .swift: .swiftSource
        case .css: .css
        case .js: .javaScript
        case .sh: UTType(filenameExtension: "sh") ?? .shellScript
        }
    }

    static var openUTTypes: [UTType] {
        var types = allCases.filter(\.hasExtension).map(\.utType)
        types.append(UTType(filenameExtension: "yml") ?? .plainText)
        types.append(UTType(filenameExtension: "htm") ?? .html)
        types.append(UTType(filenameExtension: "markdown") ?? .plainText)
        types.append(UTType(filenameExtension: "bash") ?? .shellScript)
        types.append(UTType(filenameExtension: "zsh") ?? .shellScript)
        types.append(UTType(filenameExtension: "py") ?? .pythonScript)
        types.append(UTType(filenameExtension: "rb") ?? .rubyScript)
        types.append(UTType(filenameExtension: "pl") ?? .perlScript)
        types.append(UTType(filenameExtension: "php") ?? .phpScript)
        types.append(UTType(filenameExtension: "ps1") ?? .plainText)
        types.append(UTType(filenameExtension: "ts") ?? .javaScript)
        types.append(UTType(filenameExtension: "tsx") ?? .javaScript)
        types.append(.shellScript)
        types.append(.plainText)
        types.append(.image)
        types.append(.pdf)
        types.append(.item)
        return Array(Set(types))
    }

    static func from(url: URL) -> SaveFormat {
        let ext = url.pathExtension.lowercased()
        if url.lastPathComponent.lowercased().hasPrefix(".env") { return .env }
        if ext.isEmpty { return .none }
        switch ext {
        case "yml": return .yaml
        case "htm": return .html
        case "markdown": return .md
        case "bash", "zsh", "fish", "command", "awk", "sed": return .sh
        case "jsx", "mjs", "cjs": return .js
        case "tsx": return .ts
        case "canvas", "excalidraw", "xcstrings": return .json
        case "entitlements": return .plist
        case "gpx": return .xml
        case "h", "cc", "cxx", "hpp", "hh": return .cpp
        case "mm": return .m
        case "kts": return .kt
        default: return SaveFormat(rawValue: ext) ?? .none
        }
    }
}

@Observable
final class DocumentStore {
    private(set) var documents: [any TabDocument]
    var selectedID: UUID
    var showOpenPanel = false
    var errorMessage: String?

    init() {
        let first = EditorDocument()
        documents = [first]
        selectedID = first.id
    }

    var current: any TabDocument {
        documents.first { $0.id == selectedID } ?? documents[0]
    }

    private var currentIndex: Int {
        documents.firstIndex { $0.id == selectedID } ?? 0
    }

    // MARK: Tabs

    func newDocument() {
        let document = EditorDocument()
        documents.append(document)
        selectedID = document.id
    }

    /// Adds a freshly created document, reusing the current tab if it is still blank.
    private func insert(_ document: any TabDocument) {
        if current.isBlank {
            current.discardUndoHistory()
            documents[currentIndex] = document
        } else {
            documents.append(document)
        }
        selectedID = document.id
    }

    func select(_ id: UUID) {
        guard documents.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    func select(index: Int) {
        guard documents.indices.contains(index) else { return }
        selectedID = documents[index].id
    }

    func selectNext() {
        select(index: (currentIndex + 1) % documents.count)
    }

    func selectPrevious() {
        select(index: (currentIndex - 1 + documents.count) % documents.count)
    }

    /// Closes a tab, asking about unsaved changes first.
    /// Returns false when the user cancelled.
    @discardableResult
    func close(_ id: UUID) -> Bool {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return true }
        let document = documents[index]

        if document.isModified {
            selectedID = id
            switch askToSave(document) {
            case .save:
                guard run({ try document.save() }) else { return false }
            case .discard:
                break
            case .cancel:
                return false
            }
        }

        document.discardUndoHistory()
        document.releaseFileAccess()
        documents.remove(at: index)

        if documents.isEmpty {
            let replacement = EditorDocument()
            documents = [replacement]
            selectedID = replacement.id
        } else if selectedID == id {
            selectedID = documents[min(index, documents.count - 1)].id
        }
        return true
    }

    func closeCurrent() {
        close(selectedID)
    }

    /// Set once the close-window prompt has run, so quitting right after does not ask again.
    @ObservationIgnored private var unsavedChangesResolved = false

    /// Asks about every modified document, one alert per tab.
    /// Returns false as soon as the user cancels or a save fails.
    func resolveUnsavedChangesBeforeQuit() -> Bool {
        if unsavedChangesResolved { return true }
        for document in documents where document.isModified {
            selectedID = document.id
            switch askToSave(document) {
            case .save:
                guard run({ try document.save() }) else { return false }
            case .discard:
                continue
            case .cancel:
                return false
            }
        }
        unsavedChangesResolved = true
        return true
    }

    // MARK: Files

    func open(url: URL) {
        errorMessage = nil
        let incoming = url.isFileURL ? url : URL(fileURLWithPath: url.path)
        let resolved = incoming.resolvingSymlinksInPath()

        if let existing = documents.first(where: { $0.fileURL == resolved }) {
            selectedID = existing.id
            return
        }

        do {
            insert(try makeDocument(for: resolved))
        } catch {
            errorMessage = String(localized: "Could not open file: \(error.localizedDescription)")
        }
    }

    /// Images get an image tab; anything else is read as UTF-8 text.
    private func makeDocument(for url: URL) throws -> any TabDocument {
        if url.pathExtension.lowercased() == "pdf" {
            return try PDFTabDocument(url: url)
        }
        if ImageDocument.canOpen(url) {
            do {
                return try ImageDocument(url: url)
            } catch {
                // An image type nothing can decode falls through to text, then hex.
            }
        }
        if Self.isBinary(url) {
            return try HexDocument(url: url)
        }
        return try EditorDocument(url: url)
    }

    /// Anything that is not valid UTF-8 is shown as a hexadecimal dump.
    private static func isBinary(_ url: URL) -> Bool {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]), !data.isEmpty else { return false }
        return String(data: data, encoding: .utf8) == nil
    }

    /// Opens what the clipboard holds: files as tabs, raw image bytes as a new image tab.
    func pasteImage() {
        _ = importContents(of: NSPasteboard.general, name: String(localized: "Pasted Image"))
    }

    /// Shared by paste and drop. Returns false when nothing usable was found.
    @discardableResult
    func importContents(of pasteboard: NSPasteboard, name: String) -> Bool {
        let urls = PasteboardImport.fileURLs(in: pasteboard)
        if !urls.isEmpty {
            open(urls: urls)
            return true
        }
        guard let data = PasteboardImport.imageData(in: pasteboard),
              let image = BlurRenderer.image(from: data) else { return false }
        insert(ImageDocument(image: image, name: name))
        return true
    }

    /// Image bytes delivered by a SwiftUI drop (no pasteboard involved).
    func importImage(data: Data, name: String) {
        guard let image = BlurRenderer.image(from: data) else {
            errorMessage = String(localized: "Could not read the dropped image.")
            return
        }
        insert(ImageDocument(image: image, name: name))
    }

    func open(urls: [URL]) {
        for url in urls {
            open(url: url)
        }
    }

    func save() {
        run { try current.save() }
    }

    func saveAs() {
        run { try current.saveAs() }
    }

    // MARK: Helpers

    /// Runs a save action, reporting failures through `errorMessage`.
    /// Returns the action's result, or false if it threw.
    @discardableResult
    private func run(_ action: () throws -> Bool) -> Bool {
        errorMessage = nil
        do {
            return try action()
        } catch {
            errorMessage = String(localized: "Could not save file: \(error.localizedDescription)")
            return false
        }
    }

    private enum CloseChoice {
        case save, discard, cancel
    }

    private func askToSave(_ document: any TabDocument) -> CloseChoice {
        let alert = NSAlert()
        alert.messageText = String(localized: "Do you want to save the changes made to \u{201C}\(document.fileName)\u{201D}?")
        alert.informativeText = String(localized: "Your changes will be lost if you don\u{2019}t save them.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.addButton(withTitle: String(localized: "Don\u{2019}t Save"))

        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertThirdButtonReturn: return .discard
        default: return .cancel
        }
    }
}
