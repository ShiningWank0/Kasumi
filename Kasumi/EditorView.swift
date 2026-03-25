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
        case .none: return "なし"
        case .trim: return "切り抜き"
        case .mosaicRect: return "モザイク"
        case .mosaicStroke: return "ブラシ"
        case .backgroundRemoval: return "背景透過"
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
                HStack(spacing: 0) {
                    canvasSection
                    toolbarSection(axis: .vertical)
                }
            } else {
                VStack(spacing: 0) {
                    toolbarSection(axis: .horizontal)
                    canvasSection
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if viewModel.isProcessing {
                Color.black.opacity(0.3)
                ProgressView("処理中...")
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }
        }
    }

    private func toolbarSection(axis: Axis) -> some View {
        VStack(spacing: 8) {
            ToolbarView(
                selectedTool: $viewModel.selectedTool,
                canUndo: viewModel.canUndo,
                canRedo: viewModel.canRedo,
                onUndo: { viewModel.undo() },
                onRedo: { viewModel.redo() },
                onSave: { viewModel.save() },
                hasBgPreview: viewModel.bgPreviewImage != nil,
                onBgConfirm: { viewModel.confirmBackgroundRemoval() },
                onBgCancel: { viewModel.cancelBackgroundRemoval() },
                axis: axis
            )
            .padding()
        }
    }

    private var canvasSection: some View {
        CanvasView(viewModel: viewModel)
            .modifier(ScrollZoomModifier(viewModel: viewModel))
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
    @Published var zoomScale: CGFloat = 1.0
    @Published var panOffset: CGSize = .zero

    // 背景透過プレビュー用
    @Published var bgPreviewImage: CGImage?
    @Published var bgPreviewMask: CGImage?
    @Published var marchingAntsPhase: CGFloat = 0

    private let document: KasumiDocument
    private var backgroundTask: Task<Void, Never>?
    private var marchingAntsTimer: Timer?

    var imageOrientation: ImageOrientation {
        if let image = displayImage {
            return ImageOrientation(size: image.size)
        }
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

    // MARK: - Background Removal with Preview

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
            let result = await remover.removeBackground(startingAt: imagePoint, tolerance: 30)
            if !Task.isCancelled, let result = result {
                bgPreviewImage = result
                startMarchingAnts()
            }
            isProcessing = false
        }
    }

    func confirmBackgroundRemoval() {
        guard let preview = bgPreviewImage else { return }
        let nsImage = NSImage(cgImage: preview, size: NSSize(width: preview.width, height: preview.height))
        applyEdit(nsImage)
        clearBgPreview()
    }

    func cancelBackgroundRemoval() {
        clearBgPreview()
    }

    private func clearBgPreview() {
        bgPreviewImage = nil
        bgPreviewMask = nil
        stopMarchingAnts()
    }

    private func startMarchingAnts() {
        stopMarchingAnts()
        marchingAntsTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.marchingAntsPhase += 4
                if self.marchingAntsPhase > 100 {
                    self.marchingAntsPhase = 0
                }
            }
        }
    }

    private func stopMarchingAnts() {
        marchingAntsTimer?.invalidate()
        marchingAntsTimer = nil
        marchingAntsPhase = 0
    }

    // MARK: - Zoom

    func adjustZoom(by delta: CGFloat) {
        let newScale = max(0.1, min(10.0, zoomScale + delta))
        zoomScale = newScale
    }

    func resetZoom() {
        zoomScale = 1.0
        panOffset = .zero
    }

    // MARK: - Standard Operations

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

    func convertToImageCoordinates(viewPoint: CGPoint, viewSize: CGSize, imageSize: CGSize) -> CGPoint {
        let info = imageDisplayInfo(viewSize: viewSize, imageSize: imageSize)
        // ズーム・パンを考慮
        let adjustedX = (viewPoint.x - panOffset.width) / zoomScale
        let adjustedY = (viewPoint.y - panOffset.height) / zoomScale
        let imageX = (adjustedX - info.origin.x) / info.scale
        let imageY = (adjustedY - info.origin.y) / info.scale
        return CGPoint(x: max(0, min(imageSize.width - 1, imageX)),
                       y: max(0, min(imageSize.height - 1, imageY)))
    }

    func imageDisplayInfo(viewSize: CGSize, imageSize: CGSize) -> (origin: CGPoint, scale: CGFloat) {
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
    var hasBgPreview: Bool = false
    var onBgConfirm: () -> Void = {}
    var onBgCancel: () -> Void = {}
    var axis: Axis = .horizontal

    var body: some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 10))
            : AnyLayout(VStackLayout(spacing: 10))

        layout {
            // Tool buttons
            ForEach([EditTool.trim, .mosaicRect, .mosaicStroke, .backgroundRemoval], id: \.self) { tool in
                Button(action: {
                    selectedTool = selectedTool == tool ? .none : tool
                }) {
                    Label(tool.label, systemImage: tool.icon)
                        .font(.caption)
                        .frame(minWidth: 80, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .background(selectedTool == tool ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(6)
                .keyboardShortcut(tool.shortcut, modifiers: [])
                .help(tool.label)
            }

            // 背景透過プレビュー中の確定/キャンセルボタン
            if hasBgPreview {
                Divider()
                    .frame(width: axis == .vertical ? 60 : nil, height: axis == .horizontal ? 32 : nil)

                Button(action: onBgConfirm) {
                    Label("適用", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .frame(minWidth: 60, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .keyboardShortcut(.return, modifiers: [])
                .help("背景透過を適用 (Enter)")

                Button(action: onBgCancel) {
                    Label("取消", systemImage: "xmark.circle")
                        .font(.caption)
                        .frame(minWidth: 60, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape, modifiers: [])
                .help("背景透過をキャンセル (Esc)")
            }

            Divider()
                .frame(width: axis == .vertical ? 60 : nil, height: axis == .horizontal ? 32 : nil)

            Button(action: onUndo) {
                Label("元に戻す", systemImage: "arrow.uturn.backward")
                    .font(.caption)
                    .frame(minWidth: 70, minHeight: 32)
            }
            .buttonStyle(.bordered)
            .disabled(!canUndo)
            .keyboardShortcut("z", modifiers: .command)
            .help("元に戻す")

            Button(action: onRedo) {
                Label("やり直し", systemImage: "arrow.uturn.forward")
                    .font(.caption)
                    .frame(minWidth: 70, minHeight: 32)
            }
            .buttonStyle(.bordered)
            .disabled(!canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .help("やり直し")

            Divider()
                .frame(width: axis == .vertical ? 60 : nil, height: axis == .horizontal ? 32 : nil)

            Button(action: onSave) {
                Label("保存", systemImage: "square.and.arrow.down")
                    .font(.caption)
                    .frame(minWidth: 60, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
            .help("保存")
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.95))
        .cornerRadius(8)
        .shadow(radius: 4)
    }
}

// MARK: - Canvas View

struct CanvasView: View {
    @ObservedObject var viewModel: EditorViewModel

    @State private var currentPath: [CGPoint] = []
    @State private var selectionRect: CGRect = .zero
    @State private var lastPanOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // チェッカーボード背景（透明部分を可視化）
                CheckerboardView()

                if let image = viewModel.displayImage {
                    let imageSize = image.size
                    let displayInfo = canvasDisplayInfo(viewSize: geometry.size, imageSize: imageSize)

                    // メイン画像（またはプレビュー画像）
                    Group {
                        if let preview = viewModel.bgPreviewImage {
                            Image(nsImage: NSImage(cgImage: preview, size: NSSize(width: preview.width, height: preview.height)))
                                .resizable()
                                .scaledToFit()
                        } else {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // マーチングアンツ（背景透過プレビュー）
                    if viewModel.bgPreviewImage != nil {
                        MarchingAntsOverlay(
                            previewImage: viewModel.bgPreviewImage!,
                            displayInfo: displayInfo,
                            phase: viewModel.marchingAntsPhase
                        )
                    }

                    // Selection overlay
                    if (viewModel.selectedTool == .trim || viewModel.selectedTool == .mosaicRect) && selectionRect.width > 2 {
                        Rectangle()
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                            .background(
                                viewModel.selectedTool == .trim
                                    ? Color.blue.opacity(0.1)
                                    : Color.red.opacity(0.15)
                            )
                            .frame(width: selectionRect.width, height: selectionRect.height)
                            .position(x: selectionRect.midX, y: selectionRect.midY)
                    }

                    // Stroke overlay
                    if viewModel.selectedTool == .mosaicStroke && !currentPath.isEmpty {
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
                }
            }
            .scaleEffect(viewModel.zoomScale)
            .offset(viewModel.panOffset)
            .contentShape(Rectangle())
            .gesture(editGesture(in: geometry.size))
            .gesture(zoomGesture())
            .gesture(panGesture())
            .onHover { hovering in
                if viewModel.selectedTool == .backgroundRemoval && hovering {
                    NSCursor.crosshair.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .clipped()
    }

    // MARK: - Display Info

    private func canvasDisplayInfo(viewSize: CGSize, imageSize: CGSize) -> (origin: CGPoint, scale: CGFloat, displaySize: CGSize) {
        let scaleX = viewSize.width / imageSize.width
        let scaleY = viewSize.height / imageSize.height
        let scale = min(scaleX, scaleY)
        let displayW = imageSize.width * scale
        let displayH = imageSize.height * scale
        let originX = (viewSize.width - displayW) / 2
        let originY = (viewSize.height - displayH) / 2
        return (CGPoint(x: originX, y: originY), scale, CGSize(width: displayW, height: displayH))
    }

    // MARK: - Coordinate Conversion

    private func convertToImageCoordinates(_ viewPoint: CGPoint, viewSize: CGSize, imageSize: CGSize) -> CGPoint {
        return viewModel.convertToImageCoordinates(viewPoint: viewPoint, viewSize: viewSize, imageSize: imageSize)
    }

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

    private func convertPointsToImageCoordinates(_ points: [CGPoint], viewSize: CGSize, imageSize: CGSize) -> [CGPoint] {
        return points.map { convertToImageCoordinates($0, viewSize: viewSize, imageSize: imageSize) }
    }

    // MARK: - Gestures

    private func editGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                handleDragChanged(value, in: size)
            }
            .onEnded { value in
                handleDragEnded(value, in: size)
            }
    }

    private func zoomGesture() -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                viewModel.zoomScale = max(0.1, min(10.0, value.magnification))
            }
    }

    private func panGesture() -> some Gesture {
        DragGesture(minimumDistance: 5)
            .modifiers(.command)
            .onChanged { value in
                viewModel.panOffset = CGSize(
                    width: lastPanOffset.width + value.translation.width,
                    height: lastPanOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastPanOffset = viewModel.panOffset
            }
    }

    // MARK: - Drag Handling

    private func handleDragChanged(_ value: DragGesture.Value, in size: CGSize) {
        guard !viewModel.isProcessing, viewModel.bgPreviewImage == nil else { return }

        switch viewModel.selectedTool {
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
        guard !viewModel.isProcessing, viewModel.bgPreviewImage == nil else { return }
        guard let image = viewModel.displayImage else { return }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)

        switch viewModel.selectedTool {
        case .trim:
            let imageRect = convertRectToImageCoordinates(selectionRect, viewSize: size, imageSize: imageSize)
            if let processor = TrimProcessor(image: cgImage) {
                let result = processor.trim(to: imageRect)
                viewModel.applyEdit(NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height)))
            }

        case .mosaicRect:
            let imageRect = convertRectToImageCoordinates(selectionRect, viewSize: size, imageSize: imageSize)
            if let processor = MosaicProcessor(image: cgImage) {
                let result = processor.applyMosaic(in: imageRect, effect: .classic, blockSize: 20)
                viewModel.applyEdit(NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height)))
            }

        case .mosaicStroke:
            let imagePoints = convertPointsToImageCoordinates(currentPath, viewSize: size, imageSize: imageSize)
            if let processor = MosaicProcessor(image: cgImage) {
                let result = processor.applyMosaicStroke(points: imagePoints, brushSize: 40, effect: .classic)
                viewModel.applyEdit(NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height)))
            }

        case .backgroundRemoval:
            viewModel.performBackgroundRemoval(at: value.location, viewSize: size)

        default:
            break
        }

        currentPath = []
        selectionRect = .zero
    }
}

// MARK: - Marching Ants Overlay

struct MarchingAntsOverlay: View {
    let previewImage: CGImage
    let displayInfo: (origin: CGPoint, scale: CGFloat, displaySize: CGSize)
    let phase: CGFloat

    var body: some View {
        Canvas { context, size in
            // プレビュー画像から透明境界を検出してマーチングアンツを描画
            let displayRect = CGRect(
                x: displayInfo.origin.x,
                y: displayInfo.origin.y,
                width: displayInfo.displaySize.width,
                height: displayInfo.displaySize.height
            )

            // 透明化された領域の境界に破線を描く
            let borderPath = createTransparencyBorderPath(
                image: previewImage,
                displayRect: displayRect
            )

            context.stroke(
                borderPath,
                with: .color(.white),
                style: StrokeStyle(lineWidth: 2, dash: [8, 4], dashPhase: phase)
            )
            context.stroke(
                borderPath,
                with: .color(.black),
                style: StrokeStyle(lineWidth: 2, dash: [8, 4], dashPhase: phase + 6)
            )
        }
        .allowsHitTesting(false)
    }

    private func createTransparencyBorderPath(image: CGImage, displayRect: CGRect) -> Path {
        // 簡易的なアプローチ: 画像をサンプリングして透明領域の境界を検出
        let sampleWidth = min(image.width, 200)
        let sampleHeight = min(image.height, 200)
        let stepX = max(1, image.width / sampleWidth)
        let stepY = max(1, image.height / sampleHeight)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return Path()
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return Path()
        }

        var path = Path()
        let scaleX = displayRect.width / CGFloat(image.width)
        let scaleY = displayRect.height / CGFloat(image.height)

        // 透明/不透明の境界ピクセルを検出
        for sy in stride(from: 0, to: image.height, by: stepY) {
            for sx in stride(from: 0, to: image.width, by: stepX) {
                let offset = (sy * image.width + sx) * 4
                let alpha = data[offset + 3]

                if alpha == 0 {
                    // 隣接ピクセルに不透明があれば境界
                    let isBorder = checkNeighborOpaque(data: data, x: sx, y: sy, width: image.width, height: image.height, step: max(stepX, stepY))
                    if isBorder {
                        let displayX = displayRect.origin.x + CGFloat(sx) * scaleX
                        let displayY = displayRect.origin.y + CGFloat(sy) * scaleY
                        let dotSize = max(scaleX, scaleY) * CGFloat(max(stepX, stepY))
                        path.addRect(CGRect(x: displayX, y: displayY, width: dotSize, height: dotSize))
                    }
                }
            }
        }

        return path
    }

    private func checkNeighborOpaque(data: UnsafeMutablePointer<UInt8>, x: Int, y: Int, width: Int, height: Int, step: Int) -> Bool {
        let neighbors = [(x - step, y), (x + step, y), (x, y - step), (x, y + step)]
        for (nx, ny) in neighbors {
            guard nx >= 0 && nx < width && ny >= 0 && ny < height else { continue }
            let offset = (ny * width + nx) * 4
            if data[offset + 3] > 0 {
                return true
            }
        }
        return false
    }
}

// MARK: - Checkerboard View (transparency indicator)

struct CheckerboardView: View {
    let squareSize: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            let cols = Int(ceil(size.width / squareSize))
            let rows = Int(ceil(size.height / squareSize))
            for row in 0..<rows {
                for col in 0..<cols {
                    let isLight = (row + col) % 2 == 0
                    let rect = CGRect(x: CGFloat(col) * squareSize, y: CGFloat(row) * squareSize, width: squareSize, height: squareSize)
                    context.fill(Path(rect), with: .color(isLight ? Color(white: 0.85) : Color(white: 0.75)))
                }
            }
        }
    }
}

// MARK: - NSEvent scroll wheel for zoom

struct ScrollZoomModifier: ViewModifier {
    @ObservedObject var viewModel: EditorViewModel

    func body(content: Content) -> some View {
        content.background(
            ScrollZoomNSViewRepresentable(viewModel: viewModel)
        )
    }
}

struct ScrollZoomNSViewRepresentable: NSViewRepresentable {
    @ObservedObject var viewModel: EditorViewModel

    func makeNSView(context: Context) -> ScrollZoomNSView {
        let view = ScrollZoomNSView()
        view.viewModel = viewModel
        return view
    }

    func updateNSView(_ nsView: ScrollZoomNSView, context: Context) {
        nsView.viewModel = viewModel
    }
}

class ScrollZoomNSView: NSView {
    var viewModel: EditorViewModel?

    override func scrollWheel(with event: NSEvent) {
        guard let viewModel = viewModel else { return }

        // ピンチズーム（トラックパッド）
        if event.phase == .changed || event.momentumPhase == .changed {
            let delta = event.scrollingDeltaY * 0.01
            Task { @MainActor in
                viewModel.adjustZoom(by: delta)
            }
        }
        // マウスホイール
        else if event.phase == [] && event.momentumPhase == [] {
            let delta = event.scrollingDeltaY * 0.05
            Task { @MainActor in
                viewModel.adjustZoom(by: delta)
            }
        }
    }

    override var acceptsFirstResponder: Bool { true }
}

// MARK: - Preview

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

    let text = "Sample Image"
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
