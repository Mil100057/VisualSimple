//
//  VisualSimpleApp.swift
//  VisualSimple
//

import SwiftUI

@main
struct VisualSimpleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = DocumentStore()
    @State private var appearance = AppearanceController()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, appearance: appearance)
                .onAppear {
                    appDelegate.openFilesHandler = { urls in
                        store.open(urls: urls)
                    }
                    appDelegate.shouldTerminateHandler = {
                        store.resolveUnsavedChangesBeforeQuit()
                    }
                }
        }
        .defaultSize(width: 800, height: 600)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { store.newDocument() }
                    .keyboardShortcut("t")
                Button("Open…") { store.showOpenPanel = true }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Close Tab") { store.closeCurrent() }
                    .keyboardShortcut("w")
                Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("W", modifiers: [.command, .shift])
                Divider()
                Button("Save") { store.save() }
                    .keyboardShortcut("s")
                Button("Save As…") { store.saveAs() }
                    .keyboardShortcut("S", modifiers: [.command, .shift])
            }
            CommandMenu("Tabs") {
                Button("Next Tab") { store.selectNext() }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Tab") { store.selectPrevious() }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                Divider()
                ForEach(Array(store.documents.prefix(9).enumerated()), id: \.element.id) { index, document in
                    Button(document.fileName) { store.select(document.id) }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))))
                }
            }
            CommandGroup(replacing: .sidebar) {
                Button("Toggle Markdown Preview") {
                    if let document = store.current as? EditorDocument {
                        document.isPreviewVisible.toggle()
                    }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button("Next Page") { (store.current as? PDFTabDocument)?.nextPage() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                Button("Previous Page") { (store.current as? PDFTabDocument)?.previousPage() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Divider()
                Toggle("Show Window Controls", isOn: Binding(
                    get: { appearance.showsWindowControls },
                    set: { appearance.showsWindowControls = $0 }
                ))
                Button("Hide to Menu Bar") { MenuBarController.shared.hide() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Enter Full Screen") { NSApp.keyWindow?.toggleFullScreen(nil) }
                    .keyboardShortcut("f", modifiers: [.command, .control])
            }
            CommandMenu("Appearance") {
                Button("Light") { appearance.mode = .light }
                Button("Dark") { appearance.mode = .dark }
                Button("Toggle Light / Dark") { appearance.mode = appearance.isDark ? .light : .dark }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
    }
}
