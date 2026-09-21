//
//  PasteboardImport.swift
//  VisualSimple
//

import AppKit
import UniformTypeIdentifiers

/// What a pasteboard (paste or drop) offers that can become a tab.
enum PasteboardImport {
    static let imageDataTypes: [NSPasteboard.PasteboardType] = [
        .png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier),
    ]

    static func fileURLs(in pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
    }

    static func hasFileURLs(_ pasteboard: NSPasteboard) -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return pasteboard.canReadObject(forClasses: [NSURL.self], options: options)
    }

    static func hasImageData(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.availableType(from: imageDataTypes) != nil
    }

    /// Image bytes without any text alongside: what a text view should hand over.
    static func hasImageOnly(_ pasteboard: NSPasteboard) -> Bool {
        hasImageData(pasteboard) && pasteboard.string(forType: .string) == nil
    }

    static func hasFilesOrImage(_ pasteboard: NSPasteboard) -> Bool {
        hasFileURLs(pasteboard) || hasImageData(pasteboard)
    }

    static func imageData(in pasteboard: NSPasteboard) -> Data? {
        guard let type = pasteboard.availableType(from: imageDataTypes) else { return nil }
        return pasteboard.data(forType: type)
    }
}
