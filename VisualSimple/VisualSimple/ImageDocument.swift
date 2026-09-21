//
//  ImageDocument.swift
//  VisualSimple
//

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

enum BlurShape: String {
    case square, rectangle, circle, freeform
}

/// What a drag on the canvas produces.
enum ImageTool: String, CaseIterable, Identifiable {
    case square, rectangle, circle, freeform, arrow, box, text, crop

    var id: String { rawValue }

    var label: String {
        switch self {
        case .square: String(localized: "Blur square")
        case .rectangle: String(localized: "Blur rectangle")
        case .circle: String(localized: "Blur circle")
        case .freeform: String(localized: "Blur freeform")
        case .arrow: String(localized: "Arrow")
        case .box: String(localized: "Outline box")
        case .text: String(localized: "Text")
        case .crop: String(localized: "Crop")
        }
    }

    var icon: String {
        switch self {
        case .square: "square"
        case .rectangle: "rectangle"
        case .circle: "circle"
        case .freeform: "lasso"
        case .arrow: "arrow.up.right"
        case .box: "rectangle.dashed"
        case .text: "textformat"
        case .crop: "crop"
        }
    }

    var blurShape: BlurShape? {
        switch self {
        case .square: .square
        case .rectangle: .rectangle
        case .circle: .circle
        case .freeform: .freeform
        default: nil
        }
    }

    /// Square and circle keep both sides equal while dragging.
    var keepsAspect: Bool { self == .square || self == .circle }
}

enum BlurEffect: String, CaseIterable, Identifiable {
    case gaussian, pixelate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gaussian: String(localized: "Blur")
        case .pixelate: String(localized: "Pixelate")
        }
    }
}

enum ImageSaveFormat: String, CaseIterable, Identifiable {
    case png, jpeg, heic

    var id: String { rawValue }
    var label: String { ".\(rawValue)" }

    var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        }
    }

    static func from(url: URL) -> ImageSaveFormat {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": .jpeg
        case "heic", "heif": .heic
        default: .png
        }
    }
}

/// One area to blur, in original image pixel coordinates (origin bottom-left, like Core Image).
struct BlurRegion {
    let shape: BlurShape
    let rect: CGRect
    let points: [CGPoint]
    let effect: BlurEffect
    /// 0...1, mapped to a radius or a pixel size at render time.
    let strength: Double

    var path: CGPath {
        switch shape {
        case .square, .rectangle:
            return CGPath(rect: rect, transform: nil)
        case .circle:
            return CGPath(ellipseIn: rect, transform: nil)
        case .freeform:
            let path = CGMutablePath()
            guard let first = points.first else { return path }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
            return path
        }
    }
}

struct Annotation {
    enum Kind { case arrow, box, text }
    let kind: Kind
    let start: CGPoint
    let end: CGPoint
    let text: String
}

/// Where a watermark sits on the image.
enum WatermarkPlacement: String, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight, center, tiled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .topLeft: String(localized: "Top left")
        case .topRight: String(localized: "Top right")
        case .bottomLeft: String(localized: "Bottom left")
        case .bottomRight: String(localized: "Bottom right")
        case .center: String(localized: "Centre")
        case .tiled: String(localized: "Tiled")
        }
    }
}

/// A line of text laid over the finished image, once in a corner or repeated across it.
struct Watermark {
    let text: String
    let placement: WatermarkPlacement
    /// Type size as a fraction of the image's short side, so the result looks the same at any
    /// resolution — the same reasoning as a blur region's strength.
    let scale: Double
    /// 0...1.
    let opacity: Double
}

enum ImageEdit {
    case blur(BlurRegion)
    case annotation(Annotation)
    case crop(CGRect)
    case watermark(Watermark)
}

/// One image tab: the original pixels plus an ordered list of edits.
/// Rendering is non-destructive until the file is written.
@Observable
final class ImageDocument: TabDocument {
    let id = UUID()
    private(set) var fileURL: URL?
    let original: CGImage
    private(set) var edits: [ImageEdit] = []
    private(set) var rendered: CGImage
    private(set) var isModified = false

    var tool: ImageTool = .rectangle
    var effect: BlurEffect = .gaussian
    var strength: Double = 0.35
    var saveFormat: ImageSaveFormat = .png

    /// Settings for the NEXT watermark; an applied one keeps the values it was created with.
    var watermarkText: String = ""
    var watermarkPlacement: WatermarkPlacement = .bottomRight
    var watermarkScale: Double = 0.05
    var watermarkOpacity: Double = 0.35

    @ObservationIgnored let undoManager = UndoManager()
    @ObservationIgnored private let baseName: String
    @ObservationIgnored private let ciOriginal: CIImage
    /// Lets a container (a PDF) notice that a page changed.
    @ObservationIgnored var onEditsChanged: (() -> Void)?

    var isBlank: Bool { false }
    var hasEdits: Bool { !edits.isEmpty }

    var regions: [BlurRegion] {
        edits.compactMap { if case .blur(let region) = $0 { region } else { nil } }
    }

    var annotations: [Annotation] {
        edits.compactMap { if case .annotation(let annotation) = $0 { annotation } else { nil } }
    }

    var watermarks: [Watermark] {
        edits.compactMap { if case .watermark(let watermark) = $0 { watermark } else { nil } }
    }

    /// The last crop wins; earlier crops are only kept for undo.
    var cropRect: CGRect? {
        edits.reversed().compactMap { if case .crop(let rect) = $0 { rect } else { nil } }.first
    }

    /// Size of what is shown and saved (the crop, if any).
    var pixelSize: CGSize {
        CGSize(width: rendered.width, height: rendered.height)
    }

    var fileName: String {
        fileURL?.lastPathComponent ?? "\(baseName).\(saveFormat.rawValue)"
    }

    var fileTypeLabel: String {
        if let fileURL, !fileURL.pathExtension.isEmpty {
            return ".\(fileURL.pathExtension.lowercased())"
        }
        return saveFormat.label
    }

    static func canOpen(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }

    /// Loads `url` (already symlink-resolved), applying the EXIF orientation.
    /// SVG and other vector formats go through NSImage and are rasterized.
    init(url: URL) throws {
        BlurRenderer.warmUp()
        _ = url.startAccessingSecurityScopedResource()
        var cgImage: CGImage?
        if let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) {
            cgImage = BlurRenderer.cgImage(from: image)
        }
        if cgImage == nil, let vector = NSImage(contentsOf: url) {
            cgImage = Self.rasterize(vector)
        }
        guard let cgImage else {
            url.stopAccessingSecurityScopedResource()
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        fileURL = url
        original = cgImage
        rendered = cgImage
        ciOriginal = CIImage(cgImage: cgImage)
        baseName = url.deletingPathExtension().lastPathComponent
        saveFormat = ImageSaveFormat.from(url: url)
    }

    /// An image that has no file yet (pasted, dropped as data, or a PDF page).
    init(image: CGImage, name: String) {
        BlurRenderer.warmUp()
        original = image
        rendered = image
        ciOriginal = CIImage(cgImage: image)
        baseName = name
    }

    /// Vector images are drawn so their longest side is at least 2048 pixels.
    private static func rasterize(_ image: NSImage) -> CGImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = max(1, 2048 / max(size.width, size.height))
        let width = Int(size.width * scale)
        let height = Int(size.height * scale)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    // MARK: Edits (coordinates given in displayed-image pixels)

    /// Displayed pixels become original pixels by adding the crop origin.
    private func toOriginal(_ point: CGPoint) -> CGPoint {
        guard let crop = cropRect else { return point }
        return CGPoint(x: point.x + crop.minX, y: point.y + crop.minY)
    }

    private func toOriginal(_ rect: CGRect) -> CGRect {
        CGRect(origin: toOriginal(rect.origin), size: rect.size)
    }

    func addBlur(shape: BlurShape, rect: CGRect, points: [CGPoint]) {
        let region = BlurRegion(
            shape: shape, rect: toOriginal(rect), points: points.map(toOriginal),
            effect: effect, strength: strength
        )
        apply(.blur(region))
    }

    func addAnnotation(_ kind: Annotation.Kind, from start: CGPoint, to end: CGPoint, text: String = "") {
        apply(.annotation(Annotation(kind: kind, start: toOriginal(start), end: toOriginal(end), text: text)))
    }

    func setCrop(_ rect: CGRect) {
        apply(.crop(toOriginal(rect).integral))
    }

    /// Adds a watermark with the current settings. Unlike a blur or an arrow, it is not drawn on
    /// the canvas: it covers the whole finished image, so there is nothing to point at.
    func addWatermark() {
        let text = watermarkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        apply(.watermark(Watermark(
            text: text, placement: watermarkPlacement,
            scale: watermarkScale, opacity: watermarkOpacity
        )))
    }

    func apply(_ edit: ImageEdit) {
        edits.append(edit)
        undoManager.registerUndo(withTarget: self) { document in
            document.removeLastEdit()
        }
        markChanged()
    }

    func removeLastEdit() {
        guard let edit = edits.popLast() else { return }
        undoManager.registerUndo(withTarget: self) { document in
            document.apply(edit)
        }
        markChanged()
    }

    private func markChanged() {
        isModified = true
        rendered = ImageComposer.render(
            original: original, ciOriginal: ciOriginal,
            regions: regions, annotations: annotations, crop: cropRect, watermarks: watermarks
        )
        onEditsChanged?()
    }

    // MARK: Saving

    /// Images always go through the panel so the original is never overwritten by accident.
    @discardableResult
    func save() throws -> Bool {
        try saveAs()
    }

    @discardableResult
    func saveAs() throws -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedSaveName()
        panel.allowedContentTypes = [saveFormat.utType]
        panel.canCreateDirectories = true
        if let directory = fileURL?.deletingLastPathComponent() {
            panel.directoryURL = directory
        }

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        let format = ImageSaveFormat.from(url: url)
        try BlurRenderer.write(rendered, to: url, format: format)

        releaseFileAccess()
        _ = url.startAccessingSecurityScopedResource()
        fileURL = url
        saveFormat = format
        isModified = false
        return true
    }

    func releaseFileAccess() {
        fileURL?.stopAccessingSecurityScopedResource()
    }

    func discardUndoHistory() {
        undoManager.removeAllActions()
    }

    private func suggestedSaveName() -> String {
        if fileURL != nil {
            return String(localized: "\(baseName) (edited)") + ".\(saveFormat.rawValue)"
        }
        return "\(baseName).\(saveFormat.rawValue)"
    }
}

/// Blur first, then annotations on top, then the crop, and the watermark last of all — it belongs
/// to the picture that is actually published, so it must survive a crop rather than be cut by it.
enum ImageComposer {
    static func render(
        original: CGImage, ciOriginal: CIImage, regions: [BlurRegion],
        annotations: [Annotation], crop: CGRect?, watermarks: [Watermark]
    ) -> CGImage {
        var image = regions.isEmpty ? original : (BlurRenderer.render(ciOriginal, regions: regions) ?? original)
        if !annotations.isEmpty, let annotated = AnnotationRenderer.draw(annotations, on: image) {
            image = annotated
        }
        if let crop {
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let clipped = crop.intersection(bounds)
            // CGImage.cropping counts rows from the top; our rectangles have a bottom-left origin.
            let flipped = CGRect(x: clipped.minX, y: bounds.height - clipped.maxY, width: clipped.width, height: clipped.height)
            if clipped.width >= 1, clipped.height >= 1, let cropped = image.cropping(to: flipped) {
                image = cropped
            }
        }
        if !watermarks.isEmpty, let marked = WatermarkRenderer.draw(watermarks, on: image) {
            image = marked
        }
        return image
    }
}

/// Text laid over the finished image: white with a dark halo, so it stays readable on a light
/// screenshot and on a dark one alike, at an opacity the user chooses.
enum WatermarkRenderer {
    static func draw(_ watermarks: [Watermark], on image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for watermark in watermarks {
            draw(watermark, width: CGFloat(width), height: CGFloat(height), in: context)
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    private static func draw(_ watermark: Watermark, width: CGFloat, height: CGFloat, in context: CGContext) {
        let shortest = min(width, height)
        let fontSize = max(10, shortest * watermark.scale)
        let attributes = self.attributes(fontSize: fontSize, opacity: watermark.opacity)
        let string = NSAttributedString(string: watermark.text, attributes: attributes)
        let size = string.size()

        if watermark.placement == .tiled {
            drawTiled(string, size: size, width: width, height: height, in: context)
            return
        }

        let margin = shortest * 0.03
        let origin: CGPoint
        switch watermark.placement {
        case .topLeft: origin = CGPoint(x: margin, y: height - margin - size.height)
        case .topRight: origin = CGPoint(x: width - margin - size.width, y: height - margin - size.height)
        case .bottomLeft: origin = CGPoint(x: margin, y: margin)
        case .bottomRight: origin = CGPoint(x: width - margin - size.width, y: margin)
        case .center, .tiled: origin = CGPoint(x: (width - size.width) / 2, y: (height - size.height) / 2)
        }
        string.draw(at: origin)
    }

    /// Repeats the text on a -30° diagonal. The grid is rotated with the context, and made wide
    /// enough to still cover the image once turned.
    private static func drawTiled(_ string: NSAttributedString, size: CGSize, width: CGFloat, height: CGFloat, in context: CGContext) {
        let stepX = size.width * 1.8
        let stepY = size.height * 3.2
        guard stepX > 0, stepY > 0 else { return }
        let reach = (width + height)

        context.saveGState()
        context.translateBy(x: width / 2, y: height / 2)
        context.rotate(by: -.pi / 6)
        var y = -reach
        var row = 0
        while y < reach {
            // Offset every other row so the tiles do not line up in columns.
            var x = -reach + (row % 2 == 0 ? 0 : stepX / 2)
            while x < reach {
                string.draw(at: CGPoint(x: x, y: y))
                x += stepX
            }
            y += stepY
            row += 1
        }
        context.restoreGState()
    }

    private static func attributes(fontSize: CGFloat, opacity: Double) -> [NSAttributedString.Key: Any] {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(opacity * 0.8)
        shadow.shadowBlurRadius = fontSize * 0.12
        shadow.shadowOffset = NSSize(width: 0, height: -fontSize * 0.03)
        return [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(opacity),
            .shadow: shadow,
        ]
    }
}

/// Arrows, boxes and labels drawn with Core Graphics, sized relative to the image.
enum AnnotationRenderer {
    static let color = NSColor(red: 0.90, green: 0.20, blue: 0.15, alpha: 1)

    static func draw(_ annotations: [Annotation], on image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let longest = CGFloat(max(width, height))
        let lineWidth = max(2, longest / 300)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for annotation in annotations {
            switch annotation.kind {
            case .arrow:
                drawArrow(from: annotation.start, to: annotation.end, lineWidth: lineWidth, in: context)
            case .box:
                let rect = CGRect(x: annotation.start.x, y: annotation.start.y,
                                  width: annotation.end.x - annotation.start.x, height: annotation.end.y - annotation.start.y).standardized
                context.stroke(rect)
            case .text:
                drawLabel(annotation.text, at: annotation.start, longest: longest)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint, lineWidth: CGFloat, in context: CGContext) {
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(12, lineWidth * 4)
        for side in [CGFloat.pi / 7, -CGFloat.pi / 7] {
            let point = CGPoint(
                x: end.x - headLength * cos(angle + side),
                y: end.y - headLength * sin(angle + side)
            )
            context.move(to: end)
            context.addLine(to: point)
        }
        context.strokePath()
    }

    private static func drawLabel(_ text: String, at point: CGPoint, longest: CGFloat) {
        let fontSize = max(14, longest / 40)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: color,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding = fontSize * 0.3
        let origin = CGPoint(x: point.x, y: point.y - size.height)
        let background = NSRect(x: origin.x - padding, y: origin.y - padding * 0.6,
                                width: size.width + padding * 2, height: size.height + padding * 1.2)
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: background, xRadius: padding, yRadius: padding).fill()
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }
}

enum BlurRenderer {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private static var warmedUp = false

    /// Compiles the filter pipelines once, off the main thread, so the first
    /// real region does not stall the UI for a second.
    static func warmUp() {
        guard !warmedUp else { return }
        warmedUp = true
        DispatchQueue.global(qos: .userInitiated).async {
            let sample = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
            for effect in BlurEffect.allCases {
                let region = BlurRegion(shape: .rectangle, rect: CGRect(x: 8, y: 8, width: 32, height: 32), points: [], effect: effect, strength: 0.4)
                _ = render(sample, regions: [region])
            }
        }
    }

    static func cgImage(from image: CIImage) -> CGImage? {
        context.createCGImage(image, from: image.extent)
    }

    /// Applies every region in order; each one blurs the image as already modified.
    static func render(_ original: CIImage, regions: [BlurRegion]) -> CGImage? {
        var current = original
        for region in regions {
            guard let mask = maskImage(for: region, extent: original.extent) else { continue }
            let effected = apply(region.effect, strength: region.strength, to: current)
            let blend = CIFilter.blendWithMask()
            blend.inputImage = effected
            blend.backgroundImage = current
            blend.maskImage = mask
            guard let output = blend.outputImage else { continue }
            current = output.cropped(to: original.extent)
        }
        return cgImage(from: current)
    }

    private static func apply(_ effect: BlurEffect, strength: Double, to image: CIImage) -> CIImage {
        let clamped = max(0, min(1, strength))
        let longestSide = max(image.extent.width, image.extent.height)
        switch effect {
        case .gaussian:
            // 0.2 % to 6 % of the longest side, so the result looks alike whatever the resolution.
            let radius = longestSide * (0.002 + 0.058 * clamped)
            let filter = CIFilter.gaussianBlur()
            filter.inputImage = image.clampedToExtent()
            filter.radius = Float(radius)
            return filter.outputImage?.cropped(to: image.extent) ?? image
        case .pixelate:
            let scale = max(4, longestSide * (0.004 + 0.056 * clamped))
            let filter = CIFilter.pixellate()
            filter.inputImage = image.clampedToExtent()
            filter.scale = Float(scale)
            filter.center = CGPoint(x: image.extent.minX, y: image.extent.minY)
            return filter.outputImage?.cropped(to: image.extent) ?? image
        }
    }

    /// White inside the region on black, with a slightly softened edge.
    private static func maskImage(for region: BlurRegion, extent: CGRect) -> CIImage? {
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else { return nil }

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 1, alpha: 1)
        context.addPath(region.path)
        context.fillPath()

        guard let cgMask = context.makeImage() else { return nil }
        let mask = CIImage(cgImage: cgMask)
        let feather = CIFilter.gaussianBlur()
        feather.inputImage = mask.clampedToExtent()
        feather.radius = 1.5
        return feather.outputImage?.cropped(to: mask.extent) ?? mask
    }

    static func write(_ image: CGImage, to url: URL, format: ImageSaveFormat) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        var properties: [CFString: Any] = [:]
        if format == .jpeg || format == .heic {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.92
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
    }

    /// Decodes PNG, TIFF or JPEG data from a pasteboard or a drop.
    static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
    }
}
