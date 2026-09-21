//
//  EditorDocument.swift
//  VisualSimple
//

import AppKit
import Foundation

/// One open document, i.e. one tab.
@Observable
final class EditorDocument: TabDocument {
    let id = UUID()
    var content = ""
    private(set) var fileURL: URL?
    var selectedSaveFormat: SaveFormat = .txt {
        didSet { scheduleValidation(after: .zero) }
    }
    private(set) var isModified = false
    /// Markdown only: rendered preview shown next to the editor.
    var isPreviewVisible = false
    /// Result of the last structure check (JSON, XML, CSV, brackets...), refreshed after edits.
    private(set) var validation: ValidationResult = .notApplicable
    /// Set by the status bar to move the caret; consumed by the editor view.
    private(set) var caretRequest: CaretRequest?
    @ObservationIgnored private var validationTask: Task<Void, Never>?

    struct CaretRequest: Equatable {
        let utf16Offset: Int
        let token: Int
    }
    /// One undo stack per tab, handed to the text view through its delegate.
    /// Kept out of observation: it is never read by a view body.
    @ObservationIgnored let undoManager = UndoManager()

    /// Untitled, empty and never edited: safe to reuse for an incoming file.
    var isBlank: Bool {
        fileURL == nil && !isModified && content.isEmpty
    }

    var fileName: String {
        fileURL?.lastPathComponent ?? suggestedDefaultName()
    }

    var fileTypeLabel: String {
        if activeFormat != .none { return activeFormat.label }
        if let fileURL, !fileURL.pathExtension.isEmpty {
            return ".\(fileURL.pathExtension.lowercased())"
        }
        return selectedSaveFormat.label
    }

    var activeFormat: SaveFormat {
        if let fileURL {
            return SaveFormat.from(url: fileURL)
        }
        return selectedSaveFormat
    }

    var activeSyntaxLanguage: SyntaxLanguage {
        SyntaxLanguage.resolve(url: fileURL, format: activeFormat)
    }

    init() {}

    /// Loads `url` (already symlink-resolved). Keeps security-scoped access
    /// until `releaseFileAccess()` is called.
    init(url: URL) throws {
        _ = url.startAccessingSecurityScopedResource()
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            url.stopAccessingSecurityScopedResource()
            throw error
        }
        fileURL = url
        selectedSaveFormat = SaveFormat.from(url: url)
        scheduleValidation(after: .zero)
    }

    func contentChanged(_ newValue: String) {
        content = newValue
        isModified = true
        scheduleValidation()
    }

    /// Asks the editor to put the caret at the issue and scroll to it.
    func requestCaret(at utf16Offset: Int) {
        caretRequest = CaretRequest(utf16Offset: utf16Offset, token: (caretRequest?.token ?? 0) + 1)
    }

    // MARK: Validation

    /// Debounced so typing does not re-parse at every keystroke; the parse itself runs off the main thread.
    private func scheduleValidation(after delay: Duration = .milliseconds(300)) {
        validationTask?.cancel()
        let text = content
        let language = activeSyntaxLanguage
        let format = activeFormat
        let fileExtension = fileURL?.pathExtension ?? ""
        validationTask = Task { @MainActor [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .utility) {
                SyntaxValidator.validate(text, language: language, format: format, fileExtension: fileExtension)
            }.value
            guard !Task.isCancelled, let self else { return }
            if self.validation != result {
                self.validation = result
            }
        }
    }

    /// Returns false when the user cancelled the save panel.
    @discardableResult
    func save() throws -> Bool {
        guard let fileURL else { return try saveAs() }
        try write(to: fileURL)
        return true
    }

    /// Returns false when the user cancelled the save panel.
    @discardableResult
    func saveAs() throws -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedSaveName()
        panel.allowedContentTypes = [selectedSaveFormat.utType]
        panel.allowsOtherFileTypes = true
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        releaseFileAccess()
        _ = url.startAccessingSecurityScopedResource()
        selectedSaveFormat = SaveFormat.from(url: url)
        try write(to: url)
        fileURL = url
        return true
    }

    func releaseFileAccess() {
        fileURL?.stopAccessingSecurityScopedResource()
    }

    /// Drops undo entries that still point at the tab's text view.
    func discardUndoHistory() {
        undoManager.removeAllActions()
    }

    private func suggestedDefaultName() -> String {
        if selectedSaveFormat.hasExtension {
            return String(localized: "Untitled") + ".\(selectedSaveFormat.rawValue)"
        }
        return String(localized: "Untitled")
    }

    private func suggestedSaveName() -> String {
        if let fileURL {
            if SaveFormat.from(url: fileURL) == selectedSaveFormat {
                return fileURL.lastPathComponent
            }
            let base = fileURL.deletingPathExtension().lastPathComponent
            if selectedSaveFormat.hasExtension {
                return base + ".\(selectedSaveFormat.rawValue)"
            }
            return base
        }
        return suggestedDefaultName()
    }

    private func write(to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
        isModified = false
    }
}
