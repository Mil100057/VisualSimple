//
//  ContentView.swift
//  VisualSimple
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: DocumentStore
    @Bindable var appearance: AppearanceController
    @State private var showsWatermarkForm = false

    private var theme: EditorTheme { appearance.theme }
    private var document: any TabDocument { store.current }
    private var textDocument: EditorDocument? { store.current as? EditorDocument }
    private var pdfDocument: PDFTabDocument? { store.current as? PDFTabDocument }
    private var hexDocument: HexDocument? { store.current as? HexDocument }
    /// The image being edited: an image tab, or the current page of a PDF tab.
    private var imageDocument: ImageDocument? {
        (store.current as? ImageDocument) ?? pdfDocument?.current
    }

    var body: some View {
        editorContent
            .ignoresSafeArea(edges: .top)
            .overlay(WindowBorder(isDark: appearance.isDark, cornerRadius: appearance.windowCornerRadius))
            .frame(minWidth: 600, minHeight: 400)
            .background(theme.backgroundPrimary)
            .navigationTitle(document.fileName + (document.isModified ? " •" : ""))
            .preferredColorScheme(appearance.isDark ? .dark : .light)
            .windowAppearance(appearance.mode)
            .background(WindowCloseGuard { store.resolveUnsavedChangesBeforeQuit() })
            .background(WindowChrome(showsWindowControls: appearance.showsWindowControls) { radius in
                if appearance.windowCornerRadius != radius { appearance.windowCornerRadius = radius }
            })
            .onOpenURL { url in
                store.open(url: url)
            }
            .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
                handleDrop(providers)
            }
            .fileImporter(
                isPresented: $store.showOpenPanel,
                allowedContentTypes: SaveFormat.openUTTypes,
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    store.open(urls: urls)
                case .failure(let error):
                    store.errorMessage = error.localizedDescription
                }
            }
            .alert("Error", isPresented: .init(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK") { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "")
            }
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            topBar
            if let imageDocument {
                imageToolbar(imageDocument)
                themeDivider
            }
            editors
            themeDivider
            statusBar
        }
    }

    /// Every open document keeps its own editor; only the selected one is shown.
    private var editors: some View {
        ZStack {
            ForEach(store.documents, id: \.id) { document in
                let isActive = document.id == store.selectedID
                editor(for: document, isActive: isActive)
                    .opacity(isActive ? 1 : 0)
                    .allowsHitTesting(isActive)
                    .accessibilityHidden(!isActive)
            }
        }
    }

    @ViewBuilder
    private func editor(for document: any TabDocument, isActive: Bool) -> some View {
        if let document = document as? EditorDocument {
            if document.activeSyntaxLanguage == .markdown && document.isPreviewVisible {
                HSplitView {
                    textEditor(document, isActive: isActive)
                        .frame(minWidth: 200)
                    MarkdownPreviewView(markdown: document.content, theme: theme, isDark: appearance.isDark)
                        .frame(minWidth: 200)
                }
            } else {
                textEditor(document, isActive: isActive)
            }
        } else if let document = document as? ImageDocument {
            imageEditor(document, isActive: isActive)
        } else if let document = document as? PDFTabDocument {
            imageEditor(document.current, isActive: isActive)
        } else if let document = document as? HexDocument {
            HexView(text: document.dump, isDark: appearance.isDark, backgroundColor: theme.backgroundPrimary)
        }
    }

    private func textEditor(_ document: EditorDocument, isActive: Bool) -> some View {
            CodeEditorView(
                text: Binding(
                    get: { document.content },
                    set: { document.contentChanged($0) }
                ),
                language: document.activeSyntaxLanguage,
                isDark: appearance.isDark,
                backgroundColor: theme.backgroundPrimary,
                isActive: isActive,
                undoManager: document.undoManager,
                onPasteImage: { store.pasteImage() },
                onDrop: { store.importContents(of: $0, name: String(localized: "Dropped Image")) },
                caretRequest: document.caretRequest,
                issue: {
                    if case .issue(let issue) = document.validation { return issue }
                    return nil
                }()
            )
    }

    private func imageEditor(_ document: ImageDocument, isActive: Bool) -> some View {
        ImageEditorView(
            document: document,
            rendered: document.rendered,
            isActive: isActive,
            onPasteImage: { store.pasteImage() },
            onDrop: { store.importContents(of: $0, name: String(localized: "Dropped Image")) }
        )
    }

    /// Drops landing on the chrome (toolbar, tab bar, status bar) rather than on an editor.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                    guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async { store.open(url: url) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                handled = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    DispatchQueue.main.async { store.importImage(data: data, name: String(localized: "Dropped Image")) }
                }
            }
        }
        return handled
    }

    /// Tabs on the left, five icon buttons on the right. Dragging the empty part moves the window.
    private var topBar: some View {
        HStack(spacing: 0) {
            TabBarView(store: store, theme: theme)
            HStack(spacing: 2) {
                if let textDocument, textDocument.activeSyntaxLanguage == .markdown {
                    iconButton(textDocument.isPreviewVisible ? "eye.fill" : "eye", help: "Markdown preview (Cmd+Shift+P)", active: textDocument.isPreviewVisible) {
                        textDocument.isPreviewVisible.toggle()
                    }
                }
                iconButton("plus", help: "New Tab (Cmd+T)") { store.newDocument() }
                iconButton("folder", help: "Open (Cmd+O)") { store.showOpenPanel = true }
                iconButton("square.and.arrow.down", help: "Save (Cmd+S)") { store.save() }
                iconButton("menubar.arrow.up.rectangle", help: "Hide to Menu Bar (Cmd+Shift+M)") {
                    MenuBarController.shared.hide()
                }
                iconButton(appearance.isDark ? "sun.max" : "moon", help: "Light / Dark (Cmd+Shift+D)") {
                    appearance.mode = appearance.isDark ? .light : .dark
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(theme.backgroundSecondary)
        }
        .background(theme.backgroundSecondary)
    }

    private func iconButton(_ symbol: String, help: LocalizedStringKey, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? theme.accent : theme.textSecondary)
        .help(help)
    }

    /// The save format lives in the status bar, as a menu on the extension.
    @ViewBuilder
    private var formatMenu: some View {
        if let textDocument {
            Menu {
                ForEach(SaveFormat.allCases) { format in
                    Button(format.label) { textDocument.selectedSaveFormat = format }
                }
            } label: {
                Text(textDocument.fileTypeLabel)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Save format")
        } else if let imageDocument, pdfDocument == nil {
            Menu {
                ForEach(ImageSaveFormat.allCases) { format in
                    Button(format.label) { imageDocument.saveFormat = format }
                }
            } label: {
                Text(imageDocument.fileTypeLabel)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Save format")
        } else {
            Text(document.fileTypeLabel)
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
        }
    }

    /// Second row for image and PDF tabs: tools, effect, strength, format, and pages.
    private func imageToolbar(_ document: ImageDocument) -> some View {
        HStack(spacing: 12) {
            Picker("Tool", selection: Bindable(document).tool) {
                ForEach(ImageTool.allCases) { tool in
                    Image(systemName: tool.icon)
                        .help(tool.label)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 290)
            .help("Tool: blur shapes, arrow, box, text, crop")

            Picker("Effect", selection: Bindable(document).effect) {
                ForEach(BlurEffect.allCases) { effect in
                    Text(effect.label).tag(effect)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 130)

            HStack(spacing: 6) {
                Image(systemName: "dial.low")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                Slider(value: Bindable(document).strength, in: 0.05...1)
                    .frame(width: 100)
                    .help("Strength of the next area")
            }

            watermarkControl(document)

            if let pdfDocument {
                Spacer(minLength: 8)
                pageControls(pdfDocument)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(theme.backgroundSecondary)
    }

    /// The watermark is not drawn by dragging: it covers the whole image, so it gets a small form
    /// rather than a slot in the tool picker.
    private func watermarkControl(_ document: ImageDocument) -> some View {
        Button {
            showsWatermarkForm = true
        } label: {
            Image(systemName: "signature")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.textSecondary)
        .help("Watermark")
        .popover(isPresented: $showsWatermarkForm, arrowEdge: .bottom) {
            watermarkForm(document)
        }
    }

    private func watermarkForm(_ document: ImageDocument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Watermark")
                .font(.headline)
            TextField("Text", text: Bindable(document).watermarkText)
                .textFieldStyle(.roundedBorder)
            Picker("Placement", selection: Bindable(document).watermarkPlacement) {
                ForEach(WatermarkPlacement.allCases) { placement in
                    Text(placement.label).tag(placement)
                }
            }
            HStack(spacing: 8) {
                Text("Size").frame(width: 62, alignment: .leading)
                Slider(value: Bindable(document).watermarkScale, in: 0.02...0.15)
            }
            HStack(spacing: 8) {
                Text("Opacity").frame(width: 62, alignment: .leading)
                Slider(value: Bindable(document).watermarkOpacity, in: 0.05...1)
            }
            HStack {
                Spacer()
                Button("Apply") {
                    document.addWatermark()
                    showsWatermarkForm = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(document.watermarkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func pageControls(_ document: PDFTabDocument) -> some View {
        HStack(spacing: 6) {
            Button {
                document.previousPage()
            } label: {
                Image(systemName: "chevron.left").frame(width: 24, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(document.currentPageIndex == 0)
            Text("Page \(document.currentPageIndex + 1) of \(document.pageCount)")
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
                .monospacedDigit()
            Button {
                document.nextPage()
            } label: {
                Image(systemName: "chevron.right").frame(width: 24, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(document.currentPageIndex + 1 >= document.pageCount)
        }
        .foregroundStyle(theme.textPrimary)
        .help("Cmd+Option+Left / Right")
    }

    private var statusBar: some View {
        HStack {
            Text(document.fileURL?.path ?? String(localized: "No file open"))
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let textDocument {
                validationStatus(textDocument)
            }
            Spacer()
            if let imageDocument {
                let size = imageDocument.pixelSize
                let count = imageDocument.edits.count
                Text("\(Int(size.width)) × \(Int(size.height)) px, edits: \(count)")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            if let hexDocument {
                Group {
                    if hexDocument.shownByteCount < hexDocument.byteCount {
                        Text("\(hexDocument.byteCount) bytes, showing the first \(hexDocument.shownByteCount / 1024 / 1024) MB, read-only")
                    } else {
                        Text("\(hexDocument.byteCount) bytes, read-only")
                    }
                }
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
            }
            formatMenu
            if document.isModified {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 6, height: 6)
                    .help("Unsaved changes")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 22)
        .background(theme.backgroundSecondary)
    }

    @ViewBuilder
    private func validationStatus(_ document: EditorDocument) -> some View {
        switch document.validation {
        case .notApplicable:
            EmptyView()
        case .valid(let label):
            Label(label, systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
                .padding(.leading, 8)
        case .issue(let issue):
            Button {
                document.requestCaret(at: issue.utf16Offset)
            } label: {
                Label(issue.summary, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(red: 0.85, green: 0.25, blue: 0.2))
            .padding(.leading, 8)
            .help("Click to jump to the problem")
        }
    }

    private var themeDivider: some View {
        Rectangle()
            .fill(theme.divider)
            .frame(height: 1)
    }

}

#Preview {
    ContentView(store: DocumentStore(), appearance: AppearanceController())
}
