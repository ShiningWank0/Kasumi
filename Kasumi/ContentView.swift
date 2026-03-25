//
//  ContentView.swift
//  Kasumi
//
//  Created by Takuma Kaneko on 2026/03/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var document: KasumiDocument?
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .imageScale(.large)
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            
            Text("Kasumi")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Privacy-focused image and PDF editor")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                Button(action: openFile) {
                    Label("Open File", systemImage: "folder")
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("o", modifiers: .command)
                
                Button(action: openFromClipboard) {
                    Label("From Clipboard", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
            .padding(.top, 20)
            
            Divider()
                .padding(.vertical)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                
                ShortcutHintView(key: "⌘⇧K", description: "Open from clipboard/Finder (Global)")
                ShortcutHintView(key: "⌘O", description: "Open file")
                ShortcutHintView(key: "⌘S", description: "Save")
                ShortcutHintView(key: "⌘Z", description: "Undo")
            }
            .font(.caption)
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 500)
        .sheet(item: Binding(
            get: { document },
            set: { document = $0 }
        )) { doc in
            EditorView(document: doc)
        }
    }
    
    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff, .pdf]
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            do {
                let doc = try KasumiDocument(contentsOf: url)
                openEditorWindow(with: doc, title: url.lastPathComponent)
            } catch {
                print("Failed to open file: \(error)")
            }
        }
    }
    
    private func openFromClipboard() {
        if let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            let doc = KasumiDocument(image: image)
            openEditorWindow(with: doc, title: "Untitled")
        }
    }
    
    private func openEditorWindow(with document: KasumiDocument, title: String) {
        // SwiftUIのEditorViewを新しいウィンドウで開く
        let editorView = EditorView(document: document)
        let hostingController = NSHostingController(rootView: editorView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1024, height: 768))
        window.center()
        
        let windowController = NSWindowController(window: window)
        windowController.showWindow(nil)
        
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct ShortcutHintView: View {
    let key: String
    let description: String
    
    var body: some View {
        HStack {
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2))
                .cornerRadius(4)
            
            Text(description)
                .foregroundColor(.secondary)
            
            Spacer()
        }
    }
}

#Preview("Main Window") {
    ContentView()
        .frame(width: 450, height: 600)
}

#Preview("Editor View - With Sample Image") {
    let sampleImage = createSampleImage()
    let document = KasumiDocument(image: sampleImage)
    
    return EditorView(document: document)
        .frame(width: 1024, height: 768)
}

// プレビュー用のサンプル画像生成
private func createSampleImage() -> NSImage {
    let size = NSSize(width: 400, height: 300)
    let image = NSImage(size: size)
    
    image.lockFocus()
    
    // グラデーション背景
    let gradient = NSGradient(colors: [
        NSColor.systemBlue,
        NSColor.systemPurple
    ])
    gradient?.draw(in: NSRect(origin: .zero, size: size), angle: 45)
    
    // テキスト
    let text = "Sample Image\nfor Preview"
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 32, weight: .bold),
        .foregroundColor: NSColor.white
    ]
    
    let attrString = NSAttributedString(string: text, attributes: attrs)
    let textRect = NSRect(x: 50, y: 100, width: 300, height: 100)
    attrString.draw(in: textRect)
    
    image.unlockFocus()
    
    return image
}

extension KasumiDocument: Identifiable {
    var id: UUID {
        // 一時的なID（実際にはプロパティとして持つべき）
        UUID()
    }
}


