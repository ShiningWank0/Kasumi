import Cocoa

/// 編集ツールの種類
enum EditTool {
    case none
    case trim
    case mosaicRect
    case mosaicStroke
    case backgroundRemoval
}

/// キャンバスビューのデリゲート
protocol CanvasViewDelegate: AnyObject {
    func canvasViewDidCompleteEdit(_ canvasView: CanvasView, resultImage: CGImage)
}

/// 画像編集のためのキャンバスビュー
class CanvasView: NSView {
    
    weak var delegate: CanvasViewDelegate?
    
    // MARK: - Properties
    
    private var displayImage: CGImage?
    private var currentTool: EditTool = .none
    
    // 描画用
    private var selectionPath: NSBezierPath?
    private var strokePoints: [CGPoint] = []
    private var isDrawing = false
    
    // パラメータ
    private var brushSize: CGFloat = 40.0
    private var mosaicEffect: MosaicEffect = .classic
    
    // MARK: - Initialization
    
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
    
    // MARK: - Image Management
    
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
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        guard let image = displayImage else { return }
        
        // 画像を中央に配置して描画
        let imageSize = CGSize(width: image.width, height: image.height)
        let imageRect = centerRect(for: imageSize, in: bounds)
        
        context.draw(image, in: imageRect)
        
        // 選択範囲またはストロークを描画
        if let path = selectionPath {
            context.setStrokeColor(NSColor.systemBlue.cgColor)
            context.setLineWidth(2.0)
            context.addPath(path.cgPath)
            context.strokePath()
        }
        
        // ストロークを描画
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
    
    // MARK: - Mouse Events
    
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
            guard let path = selectionPath, let startPoint = path.cgPath.currentPoint else { return }
            
            // 矩形選択
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
    
    // MARK: - Tool Application
    
    private func applyTrim() {
        guard let image = displayImage,
              let path = selectionPath,
              let rect = path.bounds as CGRect? else { return }
        
        // 画像座標に変換
        let imageSize = CGSize(width: image.width, height: image.height)
        let imageRect = centerRect(for: imageSize, in: bounds)
        
        // 選択範囲を画像座標系に変換
        let cropRect = CGRect(
            x: rect.origin.x - imageRect.origin.x,
            y: rect.origin.y - imageRect.origin.y,
            width: rect.width,
            height: rect.height
        )
        
        // トリミングを適用
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
            // 矩形モザイク
            let result = processor.applyMosaic(in: path.bounds, effect: mosaicEffect, blockSize: 20)
            delegate?.canvasViewDidCompleteEdit(self, resultImage: result)
            setImage(result)
            
        } else if currentTool == .mosaicStroke {
            // ストロークモザイク
            let result = processor.applyMosaicStroke(points: strokePoints, brushSize: brushSize, effect: mosaicEffect)
            delegate?.canvasViewDidCompleteEdit(self, resultImage: result)
            setImage(result)
        }
    }
    
    private func handleBackgroundRemovalClick(at point: CGPoint) {
        guard let image = displayImage else { return }
        
        // 画像座標に変換
        let imageSize = CGSize(width: image.width, height: image.height)
        let imageRect = centerRect(for: imageSize, in: bounds)
        
        let imagePoint = CGPoint(
            x: point.x - imageRect.origin.x,
            y: point.y - imageRect.origin.y
        )
        
        // 背景透明化を適用
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

// NSBezierPath to CGPath extension
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
