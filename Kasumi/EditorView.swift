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
    case mosaic = "Mosaic"
    case mosaicRect = "Mosaic Area"
    case mosaicStroke = "Mosaic Brush"
    case backgroundRemoval = "Background Removal"

    var icon: String {
        switch self {
        case .none: return "circle"
        case .trim: return "crop"
        case .mosaic: return "mosaic.fill"
        case .mosaicRect: return "square.on.square"
        case .mosaicStroke: return "paintbrush"
        case .backgroundRemoval: return "wand.and.stars"
        }
    }

    var label: String {
        switch self {
        case .none: return "なし"
        case .trim: return "切り抜き"
        case .mosaic: return "モザイク"
        case .mosaicRect: return "範囲"
        case .mosaicStroke: return "ブラシ"
        case .backgroundRemoval: return "背景透過"
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
        ToolbarView(viewModel: viewModel, axis: axis)
            .padding()
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

    // モザイク設定
    @Published var mosaicBlockSize: Int = 20
    @Published var mosaicBrushSize: CGFloat = 40
    @Published var selectedMosaicEffect: MosaicEffect = .classic

    // 背景透過プレビュー用
    @Published var bgPreviewImage: CGImage?
    @Published var bgBorderVisible: Bool = true

    private let document: KasumiDocument
    private var backgroundTask: Task<Void, Never>?
    private var blinkTimer: Timer?
    /// ズーム前のスケール（ピンチ開始時）
    var baseZoomScale: CGFloat = 1.0

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
                startBorderBlink()
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
        stopBorderBlink()
        bgBorderVisible = true
    }

    private func startBorderBlink() {
        stopBorderBlink()
        bgBorderVisible = true
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.bgBorderVisible.toggle()
            }
        }
    }

    private func stopBorderBlink() {
        blinkTimer?.invalidate()
        blinkTimer = nil
    }

    // MARK: - Zoom

    func adjustZoom(by delta: CGFloat) {
        zoomScale = max(1.0, min(10.0, zoomScale + delta))
    }

    func resetZoom() {
        zoomScale = 1.0
        baseZoomScale = 1.0
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

    // MARK: - Coordinate Conversion

    /// ジェスチャー座標（GeometryReader空間）→ 画像ピクセル座標
    /// scaleEffect はビューの中心基準、offset はその後に適用
    func convertToImageCoordinates(viewPoint: CGPoint, viewSize: CGSize, imageSize: CGSize) -> CGPoint {
        let center = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)

        // 1) offset を除去
        let p1 = CGPoint(x: viewPoint.x - panOffset.width,
                         y: viewPoint.y - panOffset.height)
        // 2) scaleEffect (center基準) を除去
        let p2 = CGPoint(x: (p1.x - center.x) / zoomScale + center.x,
                         y: (p1.y - center.y) / zoomScale + center.y)

        // 3) ビュー座標 → 画像ピクセル座標
        let info = imageDisplayInfo(viewSize: viewSize, imageSize: imageSize)
        let imageX = (p2.x - info.origin.x) / info.scale
        let imageY = (p2.y - info.origin.y) / info.scale
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
    @ObservedObject var viewModel: EditorViewModel
    var axis: Axis = .horizontal

    @State private var showMosaicSub = false

    private var isMosaicActive: Bool {
        viewModel.selectedTool == .mosaicRect || viewModel.selectedTool == .mosaicStroke
    }

    var body: some View {
        let layout = axis == .horizontal
            ? AnyLayout(HStackLayout(spacing: 8))
            : AnyLayout(VStackLayout(spacing: 8))

        layout {
            Spacer(minLength: 0)

            // 切り抜き
            toolButton(for: .trim, icon: "crop", label: "切り抜き", shortcut: "c")

            // モザイク（親ボタン）
            mosaicParentButton

            // 範囲 / ブラシ ボタン（モザイクと背景透過の間）
            if showMosaicSub || isMosaicActive {
                mosaicSubButtons
            }

            // モザイク設定（ドロップダウン・スライダー — 範囲/ブラシと背景透過の間）
            if isMosaicActive {
                mosaicSettings
            }

            // 背景透過
            toolButton(for: .backgroundRemoval, icon: "wand.and.stars", label: "背景透過", shortcut: "t")

            // ズーム・パンリセット
            if viewModel.zoomScale > 1.0 || viewModel.panOffset != .zero {
                divider
                Button(action: { viewModel.resetZoom() }) {
                    Label("表示リセット", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                        .frame(minWidth: 80, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .help("ズーム・移動をリセット")
            }

            // 背景透過プレビュー中の確定/キャンセルボタン
            if viewModel.bgPreviewImage != nil {
                divider
                Button(action: { viewModel.confirmBackgroundRemoval() }) {
                    Label("適用", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .frame(minWidth: 60, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .keyboardShortcut(.return, modifiers: [])
                .help("背景透過を適用 (Enter)")

                Button(action: { viewModel.cancelBackgroundRemoval() }) {
                    Label("取消", systemImage: "xmark.circle")
                        .font(.caption)
                        .frame(minWidth: 60, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape, modifiers: [])
                .help("背景透過をキャンセル (Esc)")
            }

            divider

            Button(action: { viewModel.undo() }) {
                Label("元に戻す", systemImage: "arrow.uturn.backward")
                    .font(.caption)
                    .frame(minWidth: 70, minHeight: 32)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canUndo)
            .keyboardShortcut("z", modifiers: .command)
            .help("元に戻す")

            Button(action: { viewModel.redo() }) {
                Label("やり直し", systemImage: "arrow.uturn.forward")
                    .font(.caption)
                    .frame(minWidth: 70, minHeight: 32)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .help("やり直し")

            divider

            Button(action: { viewModel.save() }) {
                Label("保存", systemImage: "square.and.arrow.down")
                    .font(.caption)
                    .frame(minWidth: 60, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("s", modifiers: .command)
            .help("保存")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, axis == .horizontal ? 10 : 6)
        .padding(.vertical, axis == .horizontal ? 6 : 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.95))
    }

    // MARK: - Mosaic Parent Button

    private var mosaicParentButton: some View {
        Button(action: {
            showMosaicSub.toggle()
            if !showMosaicSub && isMosaicActive {
                viewModel.selectedTool = .none
            }
        }) {
            Label("モザイク", systemImage: "square.on.square")
                .font(.caption)
                .frame(minWidth: 80, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .tint(isMosaicActive ? .accentColor : nil)
        .keyboardShortcut("m", modifiers: [])
        .help("モザイク")
    }

    // MARK: - Mosaic Sub Buttons (範囲 / ブラシ)

    private var mosaicSubButtons: some View {
        HStack(spacing: 4) {
            Button(action: { viewModel.selectedTool = .mosaicRect }) {
                Label("範囲", systemImage: "rectangle.dashed")
                    .font(.caption2)
                    .frame(minWidth: 50, minHeight: 28)
            }
            .buttonStyle(.bordered)
            .tint(viewModel.selectedTool == .mosaicRect ? .accentColor : nil)

            Button(action: { viewModel.selectedTool = .mosaicStroke }) {
                Label("ブラシ", systemImage: "paintbrush")
                    .font(.caption2)
                    .frame(minWidth: 50, minHeight: 28)
            }
            .buttonStyle(.bordered)
            .tint(viewModel.selectedTool == .mosaicStroke ? .accentColor : nil)
        }
    }

    // MARK: - Mosaic Settings (エフェクト種類 + スライダー)

    @ViewBuilder
    private var mosaicSettings: some View {
        if axis == .horizontal {
            // 上側ツールバー: 横並び、スライダーは縦方向
            HStack(spacing: 8) {
                mosaicEffectPicker
                verticalSlider(label: "粗さ", value: Binding(
                    get: { Double(viewModel.mosaicBlockSize) },
                    set: { viewModel.mosaicBlockSize = Int($0) }
                ), range: 5...80, display: "\(viewModel.mosaicBlockSize)")
                if viewModel.selectedTool == .mosaicStroke {
                    verticalSlider(label: "太さ", value: Binding(
                        get: { Double(viewModel.mosaicBrushSize) },
                        set: { viewModel.mosaicBrushSize = CGFloat($0) }
                    ), range: 5...100, display: "\(Int(viewModel.mosaicBrushSize))")
                }
            }
        } else {
            // 右側ツールバー: 縦並び、スライダーは横方向
            VStack(spacing: 6) {
                mosaicEffectPicker
                compactSlider(label: "粗さ", value: Binding(
                    get: { Double(viewModel.mosaicBlockSize) },
                    set: { viewModel.mosaicBlockSize = Int($0) }
                ), range: 5...80, display: "\(viewModel.mosaicBlockSize)")
                if viewModel.selectedTool == .mosaicStroke {
                    compactSlider(label: "太さ", value: Binding(
                        get: { Double(viewModel.mosaicBrushSize) },
                        set: { viewModel.mosaicBrushSize = CGFloat($0) }
                    ), range: 5...100, display: "\(Int(viewModel.mosaicBrushSize))")
                }
            }
        }
    }

    // エフェクト種類ドロップダウン
    private var mosaicEffectPicker: some View {
        Picker("", selection: $viewModel.selectedMosaicEffect) {
            ForEach(MosaicEffect.allCases, id: \.self) { effect in
                Text(effect.label).tag(effect)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 120)
        .controlSize(.small)
    }

    // 縦方向スライダー（上側ツールバー用）
    private func verticalSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        VStack(spacing: 2) {
            Text(display)
                .font(.caption2)
                .monospacedDigit()
            Slider(value: value, in: range, step: 1)
                .controlSize(.small)
                .frame(height: 60)
                .rotationEffect(.degrees(-90))
                .frame(width: 20, height: 60)
            Text(label)
                .font(.caption2)
        }
        .frame(width: 30)
    }

    // MARK: - Helpers

    private var divider: some View {
        Divider()
            .frame(width: axis == .vertical ? 60 : nil, height: axis == .horizontal ? 32 : nil)
    }

    private func compactSlider(label: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .frame(width: 26)
            Slider(value: value, in: range, step: 1)
                .controlSize(.small)
                .frame(width: 90)
            Text(display)
                .font(.caption2)
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
        }
    }

    // MARK: - Tool Button Helper

    private func toolButton(for tool: EditTool, icon: String, label: String, shortcut: Character) -> some View {
        Button(action: {
            viewModel.selectedTool = viewModel.selectedTool == tool ? .none : tool
        }) {
            Label(label, systemImage: icon)
                .font(.caption)
                .frame(minWidth: 80, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .tint(viewModel.selectedTool == tool ? .accentColor : nil)
        .keyboardShortcut(KeyEquivalent(shortcut), modifiers: [])
        .help(label)
    }
}

// MARK: - Canvas View

struct CanvasView: View {
    @ObservedObject var viewModel: EditorViewModel

    @State private var currentPath: [CGPoint] = []
    @State private var selectionRect: CGRect = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // チェッカーボード（ズームの影響を受けない）
                CheckerboardView()
                    .frame(width: geometry.size.width, height: geometry.size.height)

                // 画像と背景透過プレビューはズーム・パンの影響を受ける
                ZStack {
                    if let image = viewModel.displayImage {
                        let displayInfo = canvasDisplayInfo(viewSize: geometry.size, imageSize: image.size)

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

                        // 背景透過プレビューの境界線（赤色で点滅）
                        if viewModel.bgPreviewImage != nil && viewModel.bgBorderVisible {
                            TransparencyBorderOverlay(
                                previewImage: viewModel.bgPreviewImage!,
                                displayInfo: displayInfo
                            )
                        }
                    }
                }
                .scaleEffect(viewModel.zoomScale)
                .offset(viewModel.panOffset)

                // 選択オーバーレイ（ズーム変換の外 — ジェスチャー座標と同じ空間）
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

                // ストロークオーバーレイ（同様にズーム変換の外）
                if viewModel.selectedTool == .mosaicStroke && !currentPath.isEmpty {
                    Path { path in
                        if let first = currentPath.first {
                            path.move(to: first)
                            for point in currentPath.dropFirst() {
                                path.addLine(to: point)
                            }
                        }
                    }
                    .stroke(Color.blue.opacity(0.5), lineWidth: viewModel.mosaicBrushSize / viewModel.zoomScale)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(editGesture(in: geometry.size))
            .simultaneousGesture(magnifyGesture())
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

    private func magnifyGesture() -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = viewModel.baseZoomScale * value.magnification
                viewModel.zoomScale = max(1.0, min(10.0, newScale))
            }
            .onEnded { _ in
                viewModel.baseZoomScale = viewModel.zoomScale
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
                let result = processor.applyMosaic(in: imageRect, effect: viewModel.selectedMosaicEffect, blockSize: viewModel.mosaicBlockSize)
                viewModel.applyEdit(NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height)))
            }

        case .mosaicStroke:
            let imagePoints = convertPointsToImageCoordinates(currentPath, viewSize: size, imageSize: imageSize)
            if let processor = MosaicProcessor(image: cgImage) {
                let result = processor.applyMosaicStroke(points: imagePoints, brushSize: viewModel.mosaicBrushSize, effect: viewModel.selectedMosaicEffect)
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

// MARK: - Transparency Border Overlay (red blinking)

struct TransparencyBorderOverlay: View {
    let previewImage: CGImage
    let displayInfo: (origin: CGPoint, scale: CGFloat, displaySize: CGSize)

    var body: some View {
        Canvas { context, size in
            let displayRect = CGRect(
                x: displayInfo.origin.x,
                y: displayInfo.origin.y,
                width: displayInfo.displaySize.width,
                height: displayInfo.displaySize.height
            )

            let borderPath = createTransparencyBorderPath(
                image: previewImage,
                displayRect: displayRect
            )

            context.stroke(
                borderPath,
                with: .color(.red),
                style: StrokeStyle(lineWidth: 2)
            )
        }
        .allowsHitTesting(false)
    }

    private func createTransparencyBorderPath(image: CGImage, displayRect: CGRect) -> Path {
        let sampleWidth = min(image.width, 300)
        let sampleHeight = min(image.height, 300)
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
        let dotW = max(scaleX * CGFloat(stepX), 1.5)
        let dotH = max(scaleY * CGFloat(stepY), 1.5)

        for sy in stride(from: 0, to: image.height, by: stepY) {
            for sx in stride(from: 0, to: image.width, by: stepX) {
                let offset = (sy * image.width + sx) * 4
                let alpha = data[offset + 3]

                if alpha == 0 {
                    if checkNeighborOpaque(data: data, x: sx, y: sy, width: image.width, height: image.height, step: max(stepX, stepY)) {
                        let displayX = displayRect.origin.x + CGFloat(sx) * scaleX
                        let displayY = displayRect.origin.y + CGFloat(sy) * scaleY
                        path.addRect(CGRect(x: displayX, y: displayY, width: dotW, height: dotH))
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
        content.overlay(
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
    private var scrollMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && scrollMonitor == nil {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self = self, let viewModel = self.viewModel else { return event }
                // このビューのウィンドウ内のイベントのみ処理
                guard event.window === self.window else { return event }
                // カーソルがこのビューの範囲内かチェック
                let locationInView = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(locationInView) else { return event }

                // トラックパッドの2本指スクロール → パン移動
                if event.phase == .changed || event.momentumPhase == .changed {
                    Task { @MainActor in
                        viewModel.panOffset = CGSize(
                            width: viewModel.panOffset.width + event.scrollingDeltaX,
                            height: viewModel.panOffset.height + event.scrollingDeltaY
                        )
                    }
                    return nil
                }
                // マウスホイール（非トラックパッド）→ ズーム
                else if event.phase == [] && event.momentumPhase == [] {
                    let delta = event.scrollingDeltaY * 0.05
                    Task { @MainActor in
                        viewModel.adjustZoom(by: delta)
                    }
                    return nil
                }
                return event
            }
        }
    }

    override func removeFromSuperview() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
        super.removeFromSuperview()
    }

    // hitTest で nil を返し、クリック・ドラッグを SwiftUI に透過させる
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
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
