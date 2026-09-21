//
//  TabBarView.swift
//  VisualSimple
//

import SwiftUI

struct TabBarView: View {
    @Bindable var store: DocumentStore
    let theme: EditorTheme

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(store.documents, id: \.id) { document in
                        TabItemView(
                            document: document,
                            isSelected: document.id == store.selectedID,
                            theme: theme,
                            select: { store.select(document.id) },
                            close: { store.close(document.id) }
                        )
                    }
                }
            }

            Color.clear
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
        }
        .frame(height: 32)
        .background(theme.backgroundSecondary)
    }
}

private struct TabItemView: View {
    let document: any TabDocument
    let isSelected: Bool
    let theme: EditorTheme
    let select: () -> Void
    let close: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            if let icon = tabIcon {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textSecondary)
            }
            Text(document.fileName)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            trailingControl
                .frame(width: 14, height: 14)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(minWidth: 90, maxWidth: 220)
        .frame(height: 32)
        .background(isSelected ? theme.backgroundPrimary : Color.clear)
        .overlay(alignment: .top) {
            if isSelected {
                Rectangle()
                    .fill(theme.accent)
                    .frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
        .help(document.fileURL?.path ?? document.fileName)
    }

    private var tabIcon: String? {
        switch document {
        case is ImageDocument: "photo"
        case is PDFTabDocument: "doc.richtext"
        case is HexDocument: "number"
        default: nil
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        if isHovering {
            closeButton
        } else if document.isModified {
            Circle()
                .fill(theme.accent)
                .frame(width: 7, height: 7)
        } else if isSelected {
            closeButton
        }
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.textSecondary)
        .help("Close Tab")
    }
}
