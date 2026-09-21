//
//  CodeEditorView.swift
//  VisualSimple
//

import AppKit
import SwiftUI

struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    let language: SyntaxLanguage
    let isDark: Bool
    let backgroundColor: Color
    /// The editor of the selected tab. Hidden editors stay alive so each tab
    /// keeps its undo history and scroll position.
    let isActive: Bool
    let undoManager: UndoManager
    let onPasteImage: () -> Void
    let onDrop: (NSPasteboard) -> Bool
    let caretRequest: EditorDocument.CaretRequest?
    /// Underlined in the editor once validation reports it.
    let issue: SyntaxIssue?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, language: language, isDark: isDark, undoManager: undoManager)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = EditorTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? EditorTextView else { return scrollView }
        textView.onPasteImage = onPasteImage
        textView.onDrop = onDrop

        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor(backgroundColor)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        context.coordinator.textView = textView
        context.coordinator.applyHighlighting(text: text)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        context.coordinator.text = $text
        context.coordinator.language = language
        context.coordinator.isDark = isDark
        context.coordinator.undoManager = undoManager
        textView.backgroundColor = NSColor(backgroundColor)
        if let editorTextView = textView as? EditorTextView {
            editorTextView.onPasteImage = onPasteImage
            editorTextView.onDrop = onDrop
        }

        if context.coordinator.needsRehighlight || textView.string != text {
            context.coordinator.applyHighlighting(text: text)
        }
        if context.coordinator.issue != issue {
            context.coordinator.issue = issue
            context.coordinator.applyIssueUnderline()
        }

        if let caretRequest, caretRequest.token != context.coordinator.lastCaretToken {
            context.coordinator.lastCaretToken = caretRequest.token
            let length = (textView.string as NSString).length
            let range = NSRange(location: min(max(caretRequest.utf16Offset, 0), length), length: 0)
            DispatchQueue.main.async {
                textView.setSelectedRange(range)
                textView.scrollRangeToVisible(range)
                textView.window?.makeFirstResponder(textView)
            }
        }

        // Claim the keyboard when the tab becomes active, and again whenever focus fell back
        // to the window itself (SwiftUI removing another tab's view drops it there).
        if isActive {
            EditorFocus.active = textView
        }
        if isActive && (!context.coordinator.wasActive || textView.window.map { $0.firstResponder === $0 } == true) {
            DispatchQueue.main.async {
                guard let window = textView.window, window.firstResponder !== textView else { return }
                window.makeFirstResponder(textView)
            }
        }
        context.coordinator.wasActive = isActive
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var language: SyntaxLanguage
        var isDark: Bool
        var undoManager: UndoManager
        weak var textView: NSTextView?
        var isUpdating = false
        var wasActive = false
        var lastCaretToken = 0
        var issue: SyntaxIssue?

        var needsRehighlight: Bool {
            language != lastLanguage || isDark != lastIsDark
        }
        private var lastLanguage: SyntaxLanguage
        private var lastIsDark: Bool

        init(text: Binding<String>, language: SyntaxLanguage, isDark: Bool, undoManager: UndoManager) {
            self.text = text
            self.language = language
            self.isDark = isDark
            self.undoManager = undoManager
            self.lastLanguage = language
            self.lastIsDark = isDark
        }

        func applyHighlighting(text content: String) {
            guard let textView else { return }
            let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            let theme = SyntaxTheme.obsidian(isDark: isDark)
            let highlighted = SyntaxHighlighter.highlight(
                content,
                language: language,
                theme: theme,
                font: font
            )
            let selection = textView.selectedRange()
            isUpdating = true
            textView.textStorage?.setAttributedString(highlighted)
            textView.setSelectedRange(selection)
            isUpdating = false
            lastLanguage = language
            lastIsDark = isDark
            applyIssueUnderline()
        }

        /// Red dotted underline from the issue to the end of its token (at least one character).
        func applyIssueUnderline() {
            guard let textView, let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.removeAttribute(.underlineStyle, range: full)
            storage.removeAttribute(.underlineColor, range: full)
            if let issue, issue.utf16Offset < storage.length {
                let text = storage.string as NSString
                var end = issue.utf16Offset
                while end < text.length, !Self.tokenBoundary.contains(text.character(at: end)) { end += 1 }
                let length = max(1, end - issue.utf16Offset)
                let range = NSRange(location: issue.utf16Offset, length: min(length, text.length - issue.utf16Offset))
                storage.addAttributes([
                    .underlineStyle: NSUnderlineStyle.thick.rawValue | NSUnderlineStyle.patternDot.rawValue,
                    .underlineColor: NSColor(red: 0.85, green: 0.25, blue: 0.2, alpha: 1),
                ], range: range)
            }
            storage.endEditing()
        }

        private static let tokenBoundary: Set<unichar> = [0x20, 0x09, 0x0A, 0x0D, 0x2C, 0x3B, 0x3A, 0x29, 0x5D, 0x7D, 0x3E]

        func undoManager(for view: NSTextView) -> UndoManager? {
            undoManager
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            let newText = textView.string
            if text.wrappedValue != newText {
                text.wrappedValue = newText
            }
            applyHighlighting(text: newText)
        }
    }
}

/// Hands image pastes and file drops to the document store instead of inserting them as text.
final class EditorTextView: NSTextView {
    var onPasteImage: (() -> Void)?
    var onDrop: ((NSPasteboard) -> Bool)?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            EditorFocus.reclaim()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if PasteboardImport.hasFileURLs(pasteboard) || PasteboardImport.hasImageOnly(pasteboard), let onPasteImage {
            onPasteImage()
        } else {
            super.paste(sender)
        }
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)), PasteboardImport.hasFilesOrImage(NSPasteboard.general) {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if PasteboardImport.hasFilesOrImage(sender.draggingPasteboard) { return .copy }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if PasteboardImport.hasFilesOrImage(sender.draggingPasteboard) { return .copy }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if PasteboardImport.hasFilesOrImage(sender.draggingPasteboard), let onDrop {
            return onDrop(sender.draggingPasteboard)
        }
        return super.performDragOperation(sender)
    }
}
