//
//  EditorView.swift
//  Kasumi
//
//  Created by Takuma Kaneko on 2026/03/25.
//

import SwiftUI
import Combine
import PDFKit
import UniformTypeIdentifiers

// MARK: - Edit Tool

enum EditTool: String, CaseIterable {
    case none = "None"
    case trim = "Trim"
    case mosaicRect = "Mosaic Area"
    case mosaicStroke = "Mosaic Brush"
    case backgroundRemoval = "Background Removal"

    var icon: String {
        switch self {
        case .none: return "circle"
        case .trim: return "crop"
        case .mosaicRect: return "square.on.square"
        case .mosaicStroke: return "paintbrush"
        case .backgroundRemoval: return "wand.and.stars"
        }
    }

    var label: String {
        switch self {
        case .none: return "None"
        case .trim: return "Trim"
        case .mosaicRect: return "Mosaic"
        case .mosaicStroke: return "Brush"
        case .backgroundRemoval: return "BG Remove"
        }
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .none: return " "
        case .trim: return "c"
        case .mosaicRect: return "m"
        case .mosaicStroke: return "b"
        case .backgroundRemoval: return "t"
        }
    }
}

// MARK: - Image Orientation

enum ImageOrientation {
    case landscape
    case portrait

    init(size: CGSize) {
        self = size.width >= size.height ? .landscape : .portrait
    }
}

// MARK: - Editor View

struct EditorView: View {
    @StateObject private var viewModel: EditorViewModel

    init(document: KasumiDocument) {
        _viewModel = StateObject(wrappedValue: EditorViewModel(document: document))
    }

    var body: some View {
        let orientation = viewModel.imageOrientation

        Group {
            if orientation == .portrait {
                // 縦長画像: ツールバーを右側に配置
                HStack(spacing: 0) {
                    canvasSection
                    ToolbarView(
                        selectedTool: $viewModel.selectedTool,
                        canUndo: viewModel.canUndo,
                        canRedo: viewModel.canRedo,
                        onUndo: { viewModel.undo() },
                        onRedo: { viewModel.redo() },
                        onSave: { viewModel.save() },
                        axis: .vertical
                    )
                    .padding()
                }
            } else {
                // 横長画像: ツールバーを上部に配置
                VStack(spacing: 0) {
                    ToolbarView(
                        selectedTool: $viewModel.selectedTool,
                        canUndo: viewModel.canUndo,
                        canRedo: viewModel.canRedo,
                        onUndo: { viewModel.undo() },
                        onRedo: { viewModel.redo() },
                        onSave: { viewModel.save() },
                        axis: .horizontal
                    )
                    .padding()

                    canvasSection
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if viewModel.isProcessing {
                Color.black.opacity(0.3)
                ProgressView("Processing...")
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }
        }
    }

    private var canvasSection: some View {
        CanvasView(
            image: viewModel.displayImage,
            tool: viewModel.selectedTool,
            isProcessing: viewModel.isProcessing,
            onEditComplete: { result in
                viewModel.applyEdit(result)
            },
            onBackgroundRemoval: { point, viewSize in
                viewModel.performBackgroundRemoval(at: point, viewSize: viewSize)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Editor View Model

@MainActor
class EditorViewModel: ObservableObject {
    @Published var displayImage: NSImage?
    @Published var selectedTool: EditTool = .none
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    @Published var isProcessing: Bool = false

    private let document: KasumiDocument
    private var backgroundTask: Task<Void, Never>?

    var imageOrientation: ImageOrientation {
        if let image = displayImage {
            return ImageOrientation(size: image.size)
        }
        // PDF: 最初のページのサイズで判定
        if let pdf = document.pdfDocument, let page = pdf.page(at: 0) {
            let bounds = page.bounds(for: .mediaBox)
            return ImageOrientation(size: bounds.size)
        }
        return .landscape
    }

    init(document: KasumiDocument) {
        self.document = document
        self.displayImage = document.image
        updateUndoRedoState()
    }

    func applyEdit(_ result: NSImage) {
        if let cgImage = result.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            document.updateImage(cgImage)
            displayImage = result
            updateUndoRedoState()
        }
    }

    func performBackgroundRemoval(at viewPoint: CGPoint, viewSize: CGSize) {
        guard let image = displayImage,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        let imagePoint = convertToImageCoordinates(
            viewPoint: viewPoint,
            viewSize: viewSize,
            imageSize: CGSize(width: cgImage.width, height: cgImage.height)
        )

        backgroundTask?.cancel()
        isProcessing = true

        backgroundTask = Task {
            let remover = BackgroundRemover(image: cgImage)
            if let result = await remover.removeBackground(startingAt: imagePoint, tolerance: 30) {
                if !Task.isCancelled {
                    let nsImage = NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height))
                    applyEdit(nsImage)
                }
            }
            isProcessing = false
        }
    }

    func undo() {
        if let previousImage = document.undo() {
            displayImage = NSImage(cgImage: previousImage, size: NSSize(width: previousImage.width, height: previousImage.height))
            updateUndoRedoState()
        }
    }

    func redo() {
        if let nextImage = document.redo() {
            displayImage = NSImage(cgImage: nextImage, size: NSSize(width: nextImage.width, height: nextImage.height))
            updateUndoRedoState()
        }
    }

    func save() {
        do {
            try document.save()
        } catch {
            print("Save failed: \(error)")
        }
    }

    private func updateUndoRedoState() {
        canUndo = document.canUndo
        canRedo = document.canRedo
    }

    private func convertToImageCoordinates(viewPoint: CGPoint, viewSize: CGSize, imageSize: CGSize) -> CGPoint {
        let info = imageDisplayInfo(viewSize: viewSize, imageSize: imageSize)
        let imageX = (viewPoint.x - info.origin.x) / info.scale
        let imageY = (viewPoint.y - info.origin.y) / info.scale
        return CGPoint(x: max(0, min(imageSize.width - 1, imageX)),
                       y: max(0, min(imageSize.height - 1, imageY)))
    }

    private func imageDisplayInfo(viewSize: CGSize, imageSize: CGSize) -> (origin: CGPoint, scale: CGFloat) {
        let scaleX = viewSize.width / imageSize.width
        let scaleY = viewSize.height / imageSize.height
        let scale = min(scaleX, scaleY)
        let displayW = imageSize.width * scale
        let displayH = imageSize.height * scale
        let originX = (viewSize.width - displayW) / 2
        let originY = (viewSize.height - displayH) / 2
        return (CGPoint(x: originX, y: originY), scale)
    }
}

// MARK: - Toolbar View

struct ToolbarView: View {
    @Binding var selectedTool: EditTool
    let canUndo: Bool
    let canRedo: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onSave: () -> Void
    var axis: Axis = .horizontal

    var body: some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 12))
            : AnyLayout(VStackLayout(spacing: 12))

        layout {
            // Tool buttons
            ForEach([EditTool.trim, .mosaicRect, .mosaicStroke, .backgroundRemoval], id: \.self) { tool in
                Button(action: {
                    selectedTool = selectedTool == tool ? .none : tool
                }) {
                    Label(tool.label, systemImage: tool.icon)
                        .font(.caption)
                        .frame(minWidth: 70, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .background(selectedTool == tool ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(6)
                .keyboardShortcut(tool.shortcut, modifiers: [])
                .help(tool.rawValue)
            }

            Divider()
                .frame(width: axis == .vertical ? 60 : nil, height: axis == .horizontal ? 32 : nil)

            // Undo/Redo
            Button(action: onUndo) {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .font(.caption)
                    .frame(minWidth: 60, minHeight: 32)
            }
            .buttonStyle(.bordered)
            .disabled(!canUndo)
            .keyboardShortcut("z", modifiers: .command)
            .help("Undo")

            Button(action: onRedo) {
                Label("Redo", systemImage: "arrow.uturn.forward")
                    .font(.caption)
                    .frame(minWidth: 60, minHeight: 32)
            }
            .buttonStyle(.bordered)
            .disabled(!canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .help("Redo")

            Divider()
                .frame(width: axis == .vertical ? 60 : nil, height: axis == .horizontal ? 32 : nil)

            // Save
            Button(action: onSave) {
                Label("Save", systemImage: "square.and.arrow.down")
                    .font(.caption)
                    .frame(minWidth: 60, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
            .help("Save")
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.95))
        .cornerRadius(8)
        .shadow(radius: 4)
    }
}

// MARK: - Canvas View

struct CanvasView: View {
    let image: NSImage?
    let tool: EditTool
    let isProcessing: Bool
    let onEditComplete: (NSImage) -> Void
    let onBackgroundRemoval: (CGPoint, CGSize) -> Void

    @State private var currentPath: [CGPoint] = []
    @State private var selectionRect: CGRect = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = image {
                    let imageSize = image.size
                    let displayInfo = imageDisplayInfo(viewSize: geometry.size, imageSize: imageSize)

                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Selection overlay
                    if tool == .trim || tool == .mosaicRect {
                        Rectangle()
                            .stroke(Color.blue, lineWidth: 2)
                            .background(
                                tool == .trim
                                    ? Color.blue.opacity(0.1)
                                    : Color.red.opacity(0.15)
                            )
                            .frame(width: selectionRect.width, height: selectionRect.height)
                            .position(x: selectionRect.midX, y: selectionRect.midY)
                    }

                    // Stroke overlay
                    if tool == .mosaicStroke && !currentPath.isEmpty {
                        Path { path in
                            if let first = currentPath.first {
                                path.move(to: first)
                                for point in currentPath.dropFirst() {
                                    path.addLine(to: point)
                                }
                            }
                        }
                        .stroke(Color.blue.opacity(0.5), lineWidth: 40)
                    }

                    // Background removal: show crosshair cursor hint
                    if tool == .backgroundRemoval {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(
                                width: displayInfo.displaySize.width,
                                height: displayInfo.displaySize.height
                            )
                            .position(
                                x: displayInfo.origin.x + displayInfo.displaySize.width / 2,
                                y: displayInfo.origin.y + displayInfo.displaySize.height / 2
                            )
                            .onHover { hovering in
                                if hovering {
                                    NSCursor.crosshair.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDragChanged(value, in: geometry.size)
                    }
                    .onEnded { value in
                        handleDragEnded(value, in: geometry.size)
                    }
            )
        }
    }

    // MARK: - Coordinate Conversion

    private func imageDisplayInfo(viewSize: CGSize, imageSize: CGSize) -> (origin: CGPoint, scale: CGFloat, displaySize: CGSize) {
        let scaleX = viewSize.width / imageSize.width
        let scaleY = viewSize.height / imageSize.height
        let scale = min(scaleX, scaleY)
        let displayW = imageSize.width * scale
        let displayH = imageSize.height * scale
        let originX = (viewSize.width - displayW) / 2
        let originY = (viewSize.height - displayH) / 2
        return (CGPoint(x: originX, y: originY), scale, CGSize(width: displayW, height: displayH))
    }

    /// ビュー座標を画像ピクセル座標に変換
    private func convertToImageCoordinates(_ viewPoint: CGPoint, viewSize: CGSize, imageSize: CGSize) -> CGPoint {
        let info = imageDisplayInfo(viewSize: viewSize, imageSize: imageSize)
        let imageX = (viewPoint.x - info.origin.x) / info.scale
        let imageY = (viewPoint.y - info.origin.y) / info.scale
        return CGPoint(
            x: max(0, min(imageSize.width - 1, imageX)),
            y: max(0, min(imageSize.height - 1, imageY))
        )
    }

    /// ビュー座標の矩形を画像ピクセル座標に変換
    private func convertRectToImageCoordinates(_ viewRect: CGRect, viewSize: CGSize, imageSize: CGSize) -> CGRect {
        let topLeft = convertToImageCoordinates(viewRect.origin, viewSize: viewSize, imageSize: imageSize)
        let bottomRight = convertToImageCoordinates(
            CGPoint(x: viewRect.maxX, y: viewRect.maxY),
            viewSize: viewSize,
            imageSize: imageSize
        )
        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        )
    }

    /// ビュー座標のポイント配列を画像ピクセル座標に変換
    private func convertPointsToImageCoordinates(_ points: [CGPoint], viewSize: CGSize, imageSize: CGSize) -> [CGPoint] {
        return points.map { convertToImageCoordinates($0, viewSize: viewSize, imageSize: imageSize) }
    }

    // MARK: - Drag Handling

    private func handleDragChanged(_ value: DragGesture.Value, in size: CGSize) {
        guard !isProcessing else { return }

        switch tool {
        case .trim, .mosaicRect:
            let start = value.startLocation
            let current = value.location
            selectionRect = CGRect(
                x: min(start.x, current.x),
                y: min(start.y, current.y),
                width: abs(current.x - start.x),
                height: abs(current.y - start.y)
            )

        case .mosaicStroke:
            currentPath.append(value.location)

        default:
            break
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value, in size: CGSize) {
        guard !isProcessing else { return }
        guard let image = image else { return }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        switch tool {
        case .trim:
            let imageRect = convertRectToImageCoordinates(selectionRect, viewSize: size, imageSize: imageSize)
            if let processor = TrimProcessor(image: cgImage) {
                let result = processor.trim(to: imageRect)
                onEditComplete(NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height)))
            }

        case .mosaicRect:
            let imageRect = convertRectToImageCoordinates(selectionRect, viewSize: size, imageSize: imageSize)
            if let processor = MosaicProcessor(image: cgImage) {
                let result = processor.applyMosaic(in: imageRect, effect: .classic, blockSize: 20)
                onEditComplete(NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height)))
            }

        case .mosaicStroke:
            let imagePoints = convertPointsToImageCoordinates(currentPath, viewSize: size, imageSize: imageSize)
            if let processor = MosaicProcessor(image: cgImage) {
                let result = processor.applyMosaicStroke(points: imagePoints, brushSize: 40, effect: .classic)
                onEditComplete(NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height)))
            }

        case .backgroundRemoval:
            onBackgroundRemoval(value.location, size)

        default:
            break
        }

        // Reset
        currentPath = []
        selectionRect = .zero
    }
}

#Preview("Editor - Sample Image") {
    let sampleImage = createSampleImageForEditor()
    let document = KasumiDocument(image: sampleImage)
    return EditorView(document: document)
        .frame(width: 1024, height: 768)
}

private func createSampleImageForEditor() -> NSImage {
    let size = NSSize(width: 600, height: 400)
    let image = NSImage(size: size)

    image.lockFocus()

    let gradient = NSGradient(colors: [NSColor.systemTeal, NSColor.systemIndigo])
    gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 135)

    let text = "Sample Image\n📸"
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center

    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 48, weight: .bold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraphStyle
    ]

    let attrString = NSAttributedString(string: text, attributes: attrs)
    attrString.draw(in: NSRect(x: 0, y: 150, width: 600, height: 100))

    image.unlockFocus()

    return image
}
