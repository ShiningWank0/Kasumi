//
//  EditorView.swift
//  Kasumi
//
//  Created by Takuma Kaneko on 2026/03/25.
//

import SwiftUI
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

// MARK: - Editor View

struct EditorView: View {
    @StateObject private var viewModel: EditorViewModel
    
    init(document: KasumiDocument) {
        _viewModel = StateObject(wrappedValue: EditorViewModel(document: document))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            ToolbarView(
                selectedTool: $viewModel.selectedTool,
                canUndo: viewModel.canUndo,
                canRedo: viewModel.canRedo,
                onUndo: { viewModel.undo() },
                onRedo: { viewModel.redo() },
                onSave: { viewModel.save() }
            )
            .padding()
            
            // Canvas
            CanvasView(
                image: viewModel.displayImage,
                tool: viewModel.selectedTool,
                onEditComplete: { result in
                    viewModel.applyEdit(result)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Editor View Model

@MainActor
class EditorViewModel: ObservableObject {
    @Published var displayImage: NSImage?
    @Published var selectedTool: EditTool = .none
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false
    
    private let document: KasumiDocument
    
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
}

// MARK: - Toolbar View

struct ToolbarView: View {
    @Binding var selectedTool: EditTool
    let canUndo: Bool
    let canRedo: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onSave: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Tool buttons
            ForEach([EditTool.trim, .mosaicRect, .mosaicStroke, .backgroundRemoval], id: \.self) { tool in
                Button(action: {
                    selectedTool = tool
                }) {
                    Image(systemName: tool.icon)
                        .font(.title3)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
                .background(selectedTool == tool ? Color.accentColor.opacity(0.2) : Color.clear)
                .cornerRadius(6)
                .keyboardShortcut(tool.shortcut, modifiers: [])
                .help(tool.rawValue)
            }
            
            Divider()
                .frame(height: 32)
            
            // Undo/Redo
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .disabled(!canUndo)
            .keyboardShortcut("z", modifiers: .command)
            .help("Undo")
            
            Button(action: onRedo) {
                Image(systemName: "arrow.uturn.forward")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .disabled(!canRedo)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .help("Redo")
            
            Divider()
                .frame(height: 32)
            
            // Save
            Button(action: onSave) {
                Image(systemName: "square.and.arrow.down")
                    .frame(width: 32, height: 32)
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
    let onEditComplete: (NSImage) -> Void
    
    @State private var currentPath: [CGPoint] = []
    @State private var selectionRect: CGRect = .zero
    @State private var isDrawing = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Selection overlay
                    if tool == .trim || tool == .mosaicRect {
                        Rectangle()
                            .stroke(Color.blue, lineWidth: 2)
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
                        .stroke(Color.blue, lineWidth: 40)
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
    
    private func handleDragChanged(_ value: DragGesture.Value, in size: CGSize) {
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
        guard let image = image else { return }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        
        switch tool {
        case .trim:
            if let processor = TrimProcessor(image: cgImage) {
                let result = processor.trim(to: selectionRect)
                onEditComplete(NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height)))
            }
            
        case .mosaicRect:
            if let processor = MosaicProcessor(image: cgImage) {
                let result = processor.applyMosaic(in: selectionRect, effect: .classic, blockSize: 20)
                onEditComplete(NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height)))
            }
            
        case .mosaicStroke:
            if let processor = MosaicProcessor(image: cgImage) {
                let result = processor.applyMosaicStroke(points: currentPath, brushSize: 40, effect: .classic)
                onEditComplete(NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height)))
            }
            
        case .backgroundRemoval:
            Task {
                let remover = BackgroundRemover(image: cgImage)
                if let result = await remover.removeBackground(startingAt: value.location, tolerance: 30) {
                    await MainActor.run {
                        onEditComplete(NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height)))
                    }
                }
            }
            
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
