//
//  ImageEditorView.swift
//  VisualSimple
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ImageEditorView: NSViewRepresentable {
    let document: ImageDocument
    /// Passed separately so SwiftUI re-runs `updateNSView` when the render changes.
    let rendered: CGImage
    let isActive: Bool
    let onPasteImage: () -> Void
    let onDrop: (NSPasteboard) -> Bool

    func makeNSView(context: Context) -> BlurCanvasView {
        let view = BlurCanvasView()
        view.document = document
        view.onPasteImage = onPasteImage
        view.onDrop = onDrop
        return view
    }

    func updateNSView(_ view: BlurCanvasView, context: Context) {
        view.document = document
        view.image = rendered
        view.onPasteImage = onPasteImage
        view.onDrop = onDrop

        // Claim the keyboard when the tab becomes active, and again whenever focus fell back
        // to the window itself (SwiftUI removing another tab's view drops it there).
        if isActive {
            EditorFocus.active = view
        }
        if isActive && (!context.coordinator.wasActive || view.window.map { $0.firstResponder === $0 } == true) {
            DispatchQueue.main.async {
                guard let window = view.window, window.firstResponder !== view else { return }
                window.makeFirstResponder(view)
            }
        }
        context.coordinator.wasActive = isActive
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var wasActive = false
    }
}

/// Shows the rendered image fitted in the view and lets the user drag a shape over it.
/// Coordinates handed to the document are image pixels with a bottom-left origin.
final class BlurCanvasView: NSView, NSUserInterfaceValidations {
    var document: ImageDocument?
    var onPasteImage: (() -> Void)?
    var onDrop: ((NSPasteboard) -> Bool)?

    var image: CGImage? {
        didSet {
            guard image !== oldValue else { return }
            imageLayer.contents = image
            needsLayout = true
        }
    }

    private let imageLayer = CALayer()
    private let selectionLayer = CAShapeLayer()

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var freeformPoints: [CGPoint] = []

    private let inset: CGFloat = 12

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.minificationFilter = .trilinear
        imageLayer.magnificationFilter = .linear
        selectionLayer.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        selectionLayer.strokeColor = NSColor.controlAccentColor.cgColor
        selectionLayer.lineWidth = 1.5
        selectionLayer.lineDashPattern = [6, 4]
        layer?.addSublayer(imageLayer)
        layer?.addSublayer(selectionLayer)
        registerForDraggedTypes([.fileURL] + PasteboardImport.imageDataTypes)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }
    /// Every mouse-down here starts a selection, never a window drag.
    override var mouseDownCanMoveWindow: Bool { false }

    override var undoManager: UndoManager? {
        document?.undoManager
    }

    // MARK: Geometry

    private var imageSize: CGSize {
        guard let image else { return .zero }
        return CGSize(width: image.width, height: image.height)
    }

    /// Where the image sits inside the view (aspect fit, inset).
    private var fitRect: CGRect {
        let size = imageSize
        let available = bounds.insetBy(dx: inset, dy: inset)
        guard size.width > 0, size.height > 0, available.width > 0, available.height > 0 else { return .zero }
        let scale = min(available.width / size.width, available.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: available.midX - fitted.width / 2,
            y: available.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private var scale: CGFloat {
        let fit = fitRect
        guard imageSize.width > 0 else { return 1 }
        return fit.width / imageSize.width
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = fitRect
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2
        selectionLayer.frame = bounds
        CATransaction.commit()
        window?.invalidateCursorRects(for: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            EditorFocus.reclaim()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func resetCursorRects() {
        addCursorRect(fitRect, cursor: .crosshair)
    }

    private func clampToImage(_ point: CGPoint) -> CGPoint {
        let fit = fitRect
        return CGPoint(
            x: min(max(point.x, fit.minX), fit.maxX),
            y: min(max(point.y, fit.minY), fit.maxY)
        )
    }

    private func toImage(_ point: CGPoint) -> CGPoint {
        let fit = fitRect
        let s = scale
        guard s > 0 else { return .zero }
        return CGPoint(x: (point.x - fit.minX) / s, y: (point.y - fit.minY) / s)
    }

    /// Rectangle drawn so far, in view coordinates.
    private func currentRect() -> CGRect? {
        guard let start = dragStart, let current = dragCurrent, let document else { return nil }
        var dx = current.x - start.x
        var dy = current.y - start.y
        if document.tool.keepsAspect {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        let rect = CGRect(x: start.x, y: start.y, width: dx, height: dy).standardized
        return rect.intersection(fitRect)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard fitRect.contains(point), document != nil else { return }
        dragStart = point
        dragCurrent = point
        freeformPoints = [point]
        selectionLayer.lineDashPattern = document?.tool == .crop ? [2, 3] : [6, 4]
        updateSelectionPath()
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil else { return }
        let point = clampToImage(convert(event.locationInWindow, from: nil))
        dragCurrent = point
        if document?.tool == .freeform {
            freeformPoints.append(point)
        }
        updateSelectionPath()
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragStart = nil
            dragCurrent = nil
            freeformPoints = []
            updateSelectionPath()
        }
        guard let document, let start = dragStart else { return }
        let s = scale
        guard s > 0 else { return }

        switch document.tool {
        case .freeform:
            guard freeformPoints.count >= 3 else { return }
            let points = freeformPoints.map(toImage)
            let bounds = CGPath.boundingBox(of: points)
            guard bounds.width >= 2, bounds.height >= 2 else { return }
            document.addBlur(shape: .freeform, rect: bounds, points: points)
        case .square, .rectangle, .circle:
            guard let rect = currentRect(), rect.width >= 2, rect.height >= 2 else { return }
            document.addBlur(shape: document.tool.blurShape ?? .rectangle, rect: imageRect(rect), points: [])
        case .box:
            guard let rect = currentRect(), rect.width >= 2, rect.height >= 2 else { return }
            let imageRect = imageRect(rect)
            document.addAnnotation(.box, from: imageRect.origin, to: CGPoint(x: imageRect.maxX, y: imageRect.maxY))
        case .arrow:
            guard let end = dragCurrent, hypot(end.x - start.x, end.y - start.y) >= 4 else { return }
            document.addAnnotation(.arrow, from: toImage(start), to: toImage(end))
        case .crop:
            guard let rect = currentRect(), rect.width >= 4, rect.height >= 4 else { return }
            document.setCrop(imageRect(rect))
        case .text:
            let point = dragCurrent ?? start
            guard let text = askForText() else { return }
            document.addAnnotation(.text, from: toImage(point), to: toImage(point), text: text)
        }
    }

    private func imageRect(_ viewRect: CGRect) -> CGRect {
        let origin = toImage(viewRect.origin)
        let s = scale
        return CGRect(x: origin.x, y: origin.y, width: viewRect.width / s, height: viewRect.height / s)
    }

    private func askForText() -> String? {
        let alert = NSAlert()
        alert.messageText = String(localized: "Text to add")
        alert.informativeText = String(localized: "It is drawn in red, with a light background, starting at the point you clicked.")
        alert.addButton(withTitle: String(localized: "Add"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = String(localized: "Label")
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private func updateSelectionPath() {
        guard let document, dragStart != nil else {
            selectionLayer.path = nil
            return
        }
        switch document.tool {
        case .freeform:
            guard freeformPoints.count >= 2 else { selectionLayer.path = nil; return }
            let path = CGMutablePath()
            path.move(to: freeformPoints[0])
            for point in freeformPoints.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
            selectionLayer.path = path
        case .circle:
            selectionLayer.path = currentRect().map { CGPath(ellipseIn: $0, transform: nil) }
        case .square, .rectangle, .box, .crop:
            selectionLayer.path = currentRect().map { CGPath(rect: $0, transform: nil) }
        case .arrow:
            guard let start = dragStart, let current = dragCurrent else { selectionLayer.path = nil; return }
            let path = CGMutablePath()
            path.move(to: start)
            path.addLine(to: current)
            selectionLayer.path = path
        case .text:
            selectionLayer.path = nil
        }
    }

    // MARK: Actions from the Edit menu

    @objc func undo(_ sender: Any?) {
        document?.undoManager.undo()
    }

    @objc func redo(_ sender: Any?) {
        document?.undoManager.redo()
    }

    @objc func paste(_ sender: Any?) {
        onPasteImage?()
    }

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)):
            return document?.undoManager.canUndo ?? false
        case #selector(redo(_:)):
            return document?.undoManager.canRedo ?? false
        case #selector(paste(_:)):
            return PasteboardImport.hasFilesOrImage(NSPasteboard.general)
        default:
            return true
        }
    }

    // MARK: Drop

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        PasteboardImport.hasFilesOrImage(sender.draggingPasteboard) ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingEntered(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        onDrop?(sender.draggingPasteboard) ?? false
    }
}

private extension CGPath {
    static func boundingBox(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
