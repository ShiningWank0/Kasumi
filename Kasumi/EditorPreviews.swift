//
//  EditorPreviews.swift
//  Kasumi
//
//  Created by Takuma Kaneko on 2026/03/25.
//

import SwiftUI

// MARK: - Toolbar Preview

struct ToolbarPreview: View {
    var body: some View {
        ToolbarViewRepresentable()
            .frame(height: 60)
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ToolbarViewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> ToolbarView {
        return ToolbarView()
    }
    
    func updateNSView(_ nsView: ToolbarView, context: Context) {
        // 更新処理
    }
}

#Preview("Toolbar") {
    ToolbarPreview()
        .frame(width: 600, height: 100)
}

// MARK: - Canvas Preview

struct CanvasPreview: View {
    @State private var sampleDocument: KasumiDocument
    
    init() {
        let sampleImage = Self.createSampleImage()
        _sampleDocument = State(initialValue: KasumiDocument(image: sampleImage))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Canvas View Preview")
                .font(.headline)
                .padding()
            
            CanvasViewRepresentable(document: sampleDocument)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    static func createSampleImage() -> NSImage {
        let size = NSSize(width: 600, height: 400)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        // グラデーション背景
        let gradient = NSGradient(colors: [
            NSColor.systemTeal,
            NSColor.systemIndigo
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 135)
        
        // 装飾的な図形
        NSColor.white.withAlphaComponent(0.3).setFill()
        let circle1 = NSBezierPath(ovalIn: NSRect(x: 100, y: 100, width: 150, height: 150))
        circle1.fill()
        
        let circle2 = NSBezierPath(ovalIn: NSRect(x: 350, y: 150, width: 200, height: 200))
        circle2.fill()
        
        // テキスト
        let text = "Sample Image\n📸"
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 48, weight: .bold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let textRect = NSRect(x: 0, y: 150, width: 600, height: 100)
        attrString.draw(in: textRect)
        
        image.unlockFocus()
        
        return image
    }
}

struct CanvasViewRepresentable: NSViewRepresentable {
    let document: KasumiDocument
    
    func makeNSView(context: Context) -> CanvasView {
        let canvas = CanvasView()
        if let cgImage = document.cgImage {
            canvas.setImage(cgImage)
        }
        return canvas
    }
    
    func updateNSView(_ nsView: CanvasView, context: Context) {
        if let cgImage = document.cgImage {
            nsView.setImage(cgImage)
        }
    }
}

#Preview("Canvas with Sample Image") {
    CanvasPreview()
        .frame(width: 800, height: 600)
}

// MARK: - Full Editor Preview

struct FullEditorPreview: View {
    @State private var sampleDocument: KasumiDocument
    
    init() {
        let sampleImage = CanvasPreview.createSampleImage()
        _sampleDocument = State(initialValue: KasumiDocument(image: sampleImage))
    }
    
    var body: some View {
        EditorViewControllerRepresentable(document: sampleDocument)
    }
}

#Preview("Full Editor") {
    FullEditorPreview()
        .frame(width: 1024, height: 768)
}

// MARK: - Settings Preview with AppKit Integration

struct SettingsViewControllerPreview: View {
    var body: some View {
        SettingsViewControllerRepresentable()
            .frame(width: 500, height: 400)
    }
}

struct SettingsViewControllerRepresentable: NSViewControllerRepresentable {
    func makeNSViewController(context: Context) -> SettingsViewController {
        return SettingsViewController()
    }
    
    func updateNSViewController(_ nsViewController: SettingsViewController, context: Context) {
        // 更新処理
    }
}

#Preview("Settings (AppKit)") {
    SettingsViewControllerPreview()
}

// MARK: - Tool Selection States Preview

struct ToolStatesPreview: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Tool Selection States")
                .font(.title2)
                .fontWeight(.bold)
            
            ForEach([EditTool.trim, .mosaicRect, .mosaicStroke, .backgroundRemoval], id: \.self) { tool in
                HStack {
                    Text(toolName(for: tool))
                        .frame(width: 150, alignment: .trailing)
                    
                    Image(systemName: toolIcon(for: tool))
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    
                    Spacer()
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
    }
    
    private func toolName(for tool: EditTool) -> String {
        switch tool {
        case .none: return "None"
        case .trim: return "Trim"
        case .mosaicRect: return "Mosaic Area"
        case .mosaicStroke: return "Mosaic Brush"
        case .backgroundRemoval: return "Background Removal"
        }
    }
    
    private func toolIcon(for tool: EditTool) -> String {
        switch tool {
        case .none: return "circle"
        case .trim: return "crop"
        case .mosaicRect: return "square.on.square"
        case .mosaicStroke: return "paintbrush"
        case .backgroundRemoval: return "wand.and.stars"
        }
    }
}

#Preview("Tool States") {
    ToolStatesPreview()
        .frame(width: 400, height: 500)
}

// MARK: - Effect Types Preview

struct EffectTypesPreview: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Mosaic Effect Types")
                .font(.title2)
                .fontWeight(.bold)
            
            ForEach([MosaicEffect.classic, .blur, .frostGlass, .colorFill], id: \.self) { effect in
                EffectPreviewRow(effect: effect)
            }
        }
        .padding()
    }
}

struct EffectPreviewRow: View {
    let effect: MosaicEffect
    
    var body: some View {
        HStack {
            Text(effectName)
                .frame(width: 150, alignment: .trailing)
                .fontWeight(.medium)
            
            RoundedRectangle(cornerRadius: 8)
                .fill(effectColor)
                .frame(width: 100, height: 60)
                .overlay(
                    Text(effectIcon)
                        .font(.title)
                )
            
            Text(effectDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
    
    private var effectName: String {
        switch effect {
        case .classic: return "Classic Mosaic"
        case .blur: return "Gaussian Blur"
        case .frostGlass: return "Frost Glass"
        case .colorFill: return "Color Fill"
        }
    }
    
    private var effectIcon: String {
        switch effect {
        case .classic: return "▦"
        case .blur: return "~"
        case .frostGlass: return "❄️"
        case .colorFill: return "■"
        }
    }
    
    private var effectColor: Color {
        switch effect {
        case .classic: return .purple
        case .blur: return .blue
        case .frostGlass: return .cyan
        case .colorFill: return .gray
        }
    }
    
    private var effectDescription: String {
        switch effect {
        case .classic: return "Pixelated blocks"
        case .blur: return "Smooth blur effect"
        case .frostGlass: return "Frosted glass look"
        case .colorFill: return "Solid color overlay"
        }
    }
}

extension MosaicEffect: Hashable {}
extension EditTool: Hashable {}

#Preview("Effect Types") {
    EffectTypesPreview()
        .frame(width: 600, height: 450)
}
