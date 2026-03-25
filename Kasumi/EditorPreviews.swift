//
//  EditorPreviews.swift
//  Kasumi
//
//  Created by Takuma Kaneko on 2026/03/25.
//

import SwiftUI

// MARK: - Toolbar Preview

#Preview("Toolbar") {
    ToolbarView(
        selectedTool: .constant(.mosaicRect),
        canUndo: true,
        canRedo: false,
        onUndo: {},
        onRedo: {},
        onSave: {}
    )
    .padding()
    .frame(width: 600, height: 100)
}

// MARK: - Full Editor Preview

#Preview("Full Editor") {
    let sampleImage = createEditorSampleImage()
    let document = KasumiDocument(image: sampleImage)
    return EditorView(document: document)
        .frame(width: 1024, height: 768)
}

// MARK: - Tool States Preview

#Preview("Tool States") {
    VStack(spacing: 20) {
        Text("Tool Selection States")
            .font(.title2)
            .fontWeight(.bold)
        
        ForEach([EditTool.trim, .mosaicRect, .mosaicStroke, .backgroundRemoval], id: \.self) { tool in
            HStack {
                Text(tool.rawValue)
                    .frame(width: 150, alignment: .trailing)
                
                Image(systemName: tool.icon)
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
    .frame(width: 400, height: 500)
}

// MARK: - Effect Types Preview

#Preview("Effect Types") {
    VStack(spacing: 16) {
        Text("Mosaic Effect Types")
            .font(.title2)
            .fontWeight(.bold)
        
        ForEach([MosaicEffect.classic, .blur, .frostGlass, .colorFill], id: \.self) { effect in
            EffectPreviewRow(effect: effect)
        }
    }
    .padding()
    .frame(width: 600, height: 450)
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

private func createEditorSampleImage() -> NSImage {
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
