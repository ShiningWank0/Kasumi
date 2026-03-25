//
//  EditorUI.swift
//  Kasumi
//
//  Created by Takuma Kaneko on 2026/03/25.
//

import Cocoa

// MARK: - Edit Tool

/// 編集ツールの種類
enum EditTool {
    case none
    case trim
    case mosaicRect
    case mosaicStroke
    case backgroundRemoval
}

// MARK: - Editor View Controller

/// メイン編集画面のビューコントローラー
class EditorViewController: NSViewController {
    
    private let document: KasumiDocument
    private var canvasView: CanvasView!
    private var toolbarView: ToolbarView!
    private var currentTool: EditTool = .none
    
    init(document: KasumiDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadDocument()
    }
    
    private func setupUI() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        canvasView = CanvasView(frame: view.bounds)
        canvasView.autoresizingMask = [.width, .height]
        canvasView.delegate = self
        view.addSubview(canvasView)
        
        toolbarView = ToolbarView()
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.delegate = self
        view.addSubview(toolbarView)
        
        NSLayoutConstraint.activate([
            toolbarView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            toolbarView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toolbarView.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    private func loadDocument() {
        if let cgImage = document.cgImage {
            canvasView.setImage(cgImage)
        }
    }
    
    private func selectTool(_ tool: EditTool) {
        currentTool = tool
        canvasView.setTool(tool)
    }
    
    func save() {
        do {
            try document.save()
            showNotification("Saved successfully")
        } catch {
            showError("Failed to save: \(error.localizedDescription)")
        }
    }
    
    func saveAs() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.jpeg, .png, .tiff]
        savePanel.nameFieldStringValue = "Untitled"
        
        savePanel.begin { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            
            do {
                try self?.document.save(to: url)
                self?.view.window?.title = url.lastPathComponent
                self?.showNotification("Saved successfully")
            } catch {
                self?.showError("Failed to save: \(error.localizedDescription)")
            }
        }
    }
    
    @objc func undo() {
        if let previousImage = document.undo() {
            canvasView.setImage(previousImage)
        }
    }
    
    @objc func redo() {
        if let nextImage = document.redo() {
            canvasView.setImage(nextImage)
        }
    }
    
    private func showNotification(_ message: String) {
        print("✅ \(message)")
    }
    
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

extension EditorViewController: CanvasViewDelegate {
    func canvasViewDidCompleteEdit(_ canvasView: CanvasView, resultImage: CGImage) {
        document.updateImage(resultImage)
    }
}

extension EditorViewController: ToolbarViewDelegate {
    func toolbarView(_ toolbar: ToolbarView, didSelectTool tool: EditTool) {
        selectTool(tool)
    }
    
    func toolbarViewDidRequestUndo(_ toolbar: ToolbarView) {
        undo()
    }
    
    func toolbarViewDidRequestRedo(_ toolbar: ToolbarView) {
        redo()
    }
    
    func toolbarViewDidRequestSave(_ toolbar: ToolbarView) {
        save()
    }
}

// MARK: - Canvas View

protocol CanvasViewDelegate: AnyObject {
    func canvasViewDidCompleteEdit(_ canvasView: CanvasView, resultImage: CGImage)
}

class CanvasView: NSView {
    
    weak var delegate: CanvasViewDelegate?
    
    private var displayImage: CGImage?
    private var currentTool: EditTool = .none
    private var selectionPath: NSBezierPath?
    private var strokePoints: [CGPoint] = []
    private var isDrawing = false
    private var brushSize: CGFloat = 40.0
    private var mosaicEffect: MosaicEffect = .classic
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.1).cgColor
    }
    
    func setImage(_ image: CGImage) {
        displayImage = image
        needsDisplay = true
    }
    
    func setTool(_ tool: EditTool) {
        currentTool = tool
        resetDrawingState()
    }
    
    func setBrushSize(_ size: CGFloat) {
        brushSize = size
    }
    
    func setMosaicEffect(_ effect: MosaicEffect) {
        mosaicEffect = effect
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        guard let image = displayImage else { return }
        
        let imageSize = CGSize(width: image.width, height: image.height)
        let imageRect = centerRect(for: imageSize, in: bounds)
        
        context.draw(image, in: imageRect)
        
        if let path = selectionPath {
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(2.0)
            context.addPath(path.cgPath)
            context.strokePath()
        }
        
        if !strokePoints.isEmpty {
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(brushSize)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            
            if let firstPoint = strokePoints.first {
                context.move(to: firstPoint)
                for point in strokePoints.dropFirst() {
                    context.addLine(to: point)
                }
                context.strokePath()
            }
        }
    }
    
    private func centerRect(for size: CGSize, in bounds: CGRect) -> CGRect {
        let x = (bounds.width - size.width) / 2
        let y = (bounds.height - size.height) / 2
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
    
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        
        switch currentTool {
        case .none:
            break
        case .trim, .mosaicRect:
            selectionPath = NSBezierPath()
            selectionPath?.move(to: location)
            isDrawing = true
        case .mosaicStroke:
            strokePoints = [location]
            isDrawing = true
        case .backgroundRemoval:
            handleBackgroundRemovalClick(at: location)
        }
        
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isDrawing else { return }
        
        let location = convert(event.locationInWindow, from: nil)
        
        switch currentTool {
        case .trim, .mosaicRect:
            guard let path = selectionPath else { return }
            let cgPath = path.cgPath
            let startPoint = cgPath.currentPoint
            
            let rect = CGRect(
                x: min(startPoint.x, location.x),
                y: min(startPoint.y, location.y),
                width: abs(location.x - startPoint.x),
                height: abs(location.y - startPoint.y)
            )
            
            selectionPath = NSBezierPath(rect: rect)
            
        case .mosaicStroke:
            strokePoints.append(location)
            
        default:
            break
        }
        
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        guard isDrawing else { return }
        isDrawing = false
        
        switch currentTool {
        case .trim:
            applyTrim()
        case .mosaicRect, .mosaicStroke:
            applyMosaic()
        default:
            break
        }
        
        resetDrawingState()
        needsDisplay = true
    }
    
    private func applyTrim() {
        guard let image = displayImage,
              let path = selectionPath,
              let rect = path.bounds as CGRect? else { return }
        
        let imageSize = CGSize(width: image.width, height: image.height)
        let imageRect = centerRect(for: imageSize, in: bounds)
        
        let cropRect = CGRect(
            x: rect.origin.x - imageRect.origin.x,
            y: rect.origin.y - imageRect.origin.y,
            width: rect.width,
            height: rect.height
        )
        
        if let processor = TrimProcessor(image: image) {
            let croppedImage = processor.trim(to: cropRect)
            delegate?.canvasViewDidCompleteEdit(self, resultImage: croppedImage)
            setImage(croppedImage)
        }
    }
    
    private func applyMosaic() {
        guard let image = displayImage else { return }
        
        let processor = MosaicProcessor(image: image)
        
        if currentTool == .mosaicRect, let path = selectionPath {
            let result = processor!.applyMosaic(in: path.bounds, effect: mosaicEffect, blockSize: 20)
            delegate?.canvasViewDidCompleteEdit(self, resultImage: result)
            setImage(result)
            
        } else if currentTool == .mosaicStroke {
            let result = processor!.applyMosaicStroke(points: strokePoints, brushSize: brushSize, effect: mosaicEffect)
            delegate?.canvasViewDidCompleteEdit(self, resultImage: result)
            setImage(result)
        }
    }
    
    private func handleBackgroundRemovalClick(at point: CGPoint) {
        guard let image = displayImage else { return }
        
        let imageSize = CGSize(width: image.width, height: image.height)
        let imageRect = centerRect(for: imageSize, in: bounds)
        
        let imagePoint = CGPoint(
            x: point.x - imageRect.origin.x,
            y: point.y - imageRect.origin.y
        )
        
        Task {
            let remover = BackgroundRemover(image: image)
            if let result = await remover.removeBackground(startingAt: imagePoint, tolerance: 30) {
                await MainActor.run {
                    self.delegate?.canvasViewDidCompleteEdit(self, resultImage: result)
                    self.setImage(result)
                }
            }
        }
    }
    
    private func resetDrawingState() {
        selectionPath = nil
        strokePoints = []
        isDrawing = false
    }
}

extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        
        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }
        
        return path
    }
}

// MARK: - Toolbar View

protocol ToolbarViewDelegate: AnyObject {
    func toolbarView(_ toolbar: ToolbarView, didSelectTool tool: EditTool)
    func toolbarViewDidRequestUndo(_ toolbar: ToolbarView)
    func toolbarViewDidRequestRedo(_ toolbar: ToolbarView)
    func toolbarViewDidRequestSave(_ toolbar: ToolbarView)
}

class ToolbarView: NSView {
    
    weak var delegate: ToolbarViewDelegate?
    
    private var selectedTool: EditTool = .none
    private var toolButtons: [EditTool: NSButton] = [:]
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.95).cgColor
        layer?.cornerRadius = 8
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.2
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.shadowRadius = 8
        
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        
        let trimButton = createToolButton(tool: .trim, icon: "crop", tooltip: "Trim (C)")
        let mosaicRectButton = createToolButton(tool: .mosaicRect, icon: "square.on.square", tooltip: "Mosaic Area (M)")
        let mosaicStrokeButton = createToolButton(tool: .mosaicStroke, icon: "paintbrush", tooltip: "Mosaic Brush (B)")
        let bgRemovalButton = createToolButton(tool: .backgroundRemoval, icon: "wand.and.stars", tooltip: "Background Removal (T)")
        
        stackView.addArrangedSubview(trimButton)
        stackView.addArrangedSubview(mosaicRectButton)
        stackView.addArrangedSubview(mosaicStrokeButton)
        stackView.addArrangedSubview(bgRemovalButton)
        
        let separator1 = createSeparator()
        stackView.addArrangedSubview(separator1)
        
        let undoButton = createButton(icon: "arrow.uturn.backward", action: #selector(undoTapped), tooltip: "Undo (⌘Z)")
        let redoButton = createButton(icon: "arrow.uturn.forward", action: #selector(redoTapped), tooltip: "Redo (⌘⇧Z)")
        
        stackView.addArrangedSubview(undoButton)
        stackView.addArrangedSubview(redoButton)
        
        let separator2 = createSeparator()
        stackView.addArrangedSubview(separator2)
        
        let saveButton = createButton(icon: "square.and.arrow.down", action: #selector(saveTapped), tooltip: "Save (⌘S)")
        stackView.addArrangedSubview(saveButton)
        
        addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    private func createToolButton(tool: EditTool, icon: String, tooltip: String) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .texturedRounded
        button.isBordered = true
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.setButtonType(.pushOnPushOff)
        button.toolTip = tooltip
        button.target = self
        button.action = #selector(toolButtonTapped(_:))
        
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        
        toolButtons[tool] = button
        return button
    }
    
    private func createButton(icon: String, action: Selector, tooltip: String) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .texturedRounded
        button.isBordered = true
        button.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
        button.target = self
        button.action = action
        
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        button.heightAnchor.constraint(equalToConstant: 32).isActive = true
        
        return button
    }
    
    private func createSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 1).isActive = true
        return box
    }
    
    @objc private func toolButtonTapped(_ sender: NSButton) {
        for (tool, button) in toolButtons {
            if button == sender {
                selectTool(tool)
                return
            }
        }
    }
    
    private func selectTool(_ tool: EditTool) {
        for (otherTool, button) in toolButtons {
            button.state = (otherTool == tool) ? .on : .off
        }
        
        selectedTool = tool
        delegate?.toolbarView(self, didSelectTool: tool)
    }
    
    @objc private func undoTapped() {
        delegate?.toolbarViewDidRequestUndo(self)
    }
    
    @objc private func redoTapped() {
        delegate?.toolbarViewDidRequestRedo(self)
    }
    
    @objc private func saveTapped() {
        delegate?.toolbarViewDidRequestSave(self)
    }
}
