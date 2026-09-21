//
//  TabDocument.swift
//  VisualSimple
//

import Foundation

/// What every tab holds, whatever its content (text or image).
protocol TabDocument: AnyObject {
    var id: UUID { get }
    var fileURL: URL? { get }
    var fileName: String { get }
    var fileTypeLabel: String { get }
    var isModified: Bool { get }
    /// Untitled, empty and never edited: safe to reuse for an incoming file.
    var isBlank: Bool { get }
    var undoManager: UndoManager { get }

    /// Returns false when the user cancelled the save panel.
    @discardableResult func save() throws -> Bool
    /// Returns false when the user cancelled the save panel.
    @discardableResult func saveAs() throws -> Bool
    func releaseFileAccess()
    /// Drops undo entries that still point at the tab's view.
    func discardUndoHistory()
}
