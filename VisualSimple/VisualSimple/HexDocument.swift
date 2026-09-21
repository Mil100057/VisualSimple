//
//  HexDocument.swift
//  VisualSimple
//

import AppKit
import SwiftUI

/// Read-only hexadecimal dump for files that are neither text nor images.
@Observable
final class HexDocument: TabDocument {
    let id = UUID()
    private(set) var fileURL: URL?
    let dump: String
    let byteCount: Int
    let shownByteCount: Int
    @ObservationIgnored let undoManager = UndoManager()

    static let displayLimit = 2 * 1024 * 1024

    var isModified: Bool { false }
    var isBlank: Bool { false }
    var fileName: String { fileURL?.lastPathComponent ?? String(localized: "Binary") }
    var fileTypeLabel: String {
        if let ext = fileURL?.pathExtension, !ext.isEmpty { return ".\(ext.lowercased())" }
        return "binary"
    }

    init(url: URL) throws {
        _ = url.startAccessingSecurityScopedResource()
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            url.stopAccessingSecurityScopedResource()
            throw error
        }
        fileURL = url
        byteCount = data.count
        shownByteCount = min(data.count, Self.displayLimit)
        dump = Self.format(data.prefix(shownByteCount))
    }

    /// Classic 16-bytes-per-line layout: offset, hex bytes in two groups, ASCII column.
    static func format(_ data: Data) -> String {
        let bytes = [UInt8](data)
        var lines: [String] = []
        lines.reserveCapacity(bytes.count / 16 + 1)
        let hexDigits = Array("0123456789ABCDEF".utf8)
        var index = 0
        while index < bytes.count {
            let end = min(index + 16, bytes.count)
            var line = [UInt8]()
            line.reserveCapacity(80)
            var offset = index
            var offsetDigits = [UInt8](repeating: 0x30, count: 8)
            for k in stride(from: 7, through: 0, by: -1) {
                offsetDigits[k] = hexDigits[offset & 0xF]
                offset >>= 4
            }
            line.append(contentsOf: offsetDigits)
            line.append(0x20); line.append(0x20)
            for k in index..<index + 16 {
                if k < end {
                    line.append(hexDigits[Int(bytes[k] >> 4)])
                    line.append(hexDigits[Int(bytes[k] & 0xF)])
                } else {
                    line.append(0x20); line.append(0x20)
                }
                line.append(0x20)
                if k == index + 7 { line.append(0x20) }
            }
            line.append(0x20); line.append(0x7C)
            for k in index..<end {
                let b = bytes[k]
                line.append((b >= 0x20 && b < 0x7F) ? b : 0x2E)
            }
            line.append(0x7C)
            lines.append(String(decoding: line, as: UTF8.self))
            index = end
        }
        return lines.joined(separator: "\n")
    }

    func save() throws -> Bool {
        throw CocoaError(.fileWriteNoPermission, userInfo: [NSLocalizedDescriptionKey: String(localized: "A binary file shown as a hexadecimal dump cannot be saved from VisualSimple.")])
    }

    func saveAs() throws -> Bool {
        try save()
    }

    func releaseFileAccess() {
        fileURL?.stopAccessingSecurityScopedResource()
    }

    func discardUndoHistory() {}
}

/// Monospaced, selectable, not editable.
struct HexView: NSViewRepresentable {
    let text: String
    let isDark: Bool
    let backgroundColor: Color

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isHorizontallyResizable = true
        scrollView.hasHorizontalScroller = true
        apply(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text || textView.backgroundColor != NSColor(backgroundColor) {
            apply(to: textView)
        }
    }

    private func apply(to textView: NSTextView) {
        textView.backgroundColor = NSColor(backgroundColor)
        textView.textColor = isDark ? NSColor(white: 0.85, alpha: 1) : NSColor(white: 0.15, alpha: 1)
        textView.string = text
    }
}
