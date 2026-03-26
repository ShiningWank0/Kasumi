//
//  AppDelegate.swift
//  Kasumi
//
//  Created by Takuma Kaneko on 2026/03/25.
//

import Cocoa
import SwiftUI
import UniformTypeIdentifiers

/// アプリケーションのメインデリゲート
/// グローバルショートカット、Dock挙動、アプリケーションライフサイクルを管理
class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var globalShortcutMonitor: GlobalShortcutMonitor?
    
    // MARK: - Application Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupGlobalShortcut()

        // Dock非表示設定を反映
        if UserDefaults.standard.bool(forKey: "hideDockIcon") {
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        globalShortcutMonitor?.stop()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // エディタウィンドウを閉じてもアプリは終了せず、バックグラウンドでショートカットを待機
        return false
    }
    
    // MARK: - Setup
    
    private func setupGlobalShortcut() {
        globalShortcutMonitor = GlobalShortcutMonitor()
        globalShortcutMonitor?.start { [weak self] in
            self?.handleGlobalShortcut()
        }
    }
    
    // MARK: - Actions (for menu items)
    
    @objc func openDocumentAction() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = true
        openPanel.allowedContentTypes = [.jpeg, .png, .heic, .tiff, .pdf]
        
        openPanel.begin { response in
            guard response == .OK else { return }
            for url in openPanel.urls {
                self.openEditorWindow(with: url)
            }
        }
    }
    
    // MARK: - Global Shortcut Handler
    
    private func handleGlobalShortcut() {
        // 1. クリップボードに画像があるかチェック
        if let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            openEditorWindow(with: image)
            return
        }
        
        // 2. Finderで選択中のファイルをチェック
        if let selectedFiles = getFinderSelectedFiles(), !selectedFiles.isEmpty {
            for file in selectedFiles {
                openEditorWindow(with: file)
            }
            return
        }
        
        // 3. どちらでもない場合は何もしない
        NSLog("Global shortcut triggered, but no image in clipboard or Finder selection")
    }
    
    // MARK: - Window Management
    
    private func openEditorWindow(with url: URL) {
        do {
            let document = try KasumiDocument(contentsOf: url)
            let editorView = EditorView(document: document)
            let hostingController = NSHostingController(rootView: editorView)
            
            let window = NSWindow(contentViewController: hostingController)
            window.title = url.lastPathComponent
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 1024, height: 768))
            window.center()
            
            let windowController = NSWindowController(window: window)
            windowController.showWindow(nil)
            
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            showError("Failed to open file: \(error.localizedDescription)")
        }
    }
    
    private func openEditorWindow(with image: NSImage) {
        let document = KasumiDocument(image: image)
        let editorView = EditorView(document: document)
        let hostingController = NSHostingController(rootView: editorView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Untitled"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1024, height: 768))
        window.center()
        
        let windowController = NSWindowController(window: window)
        windowController.showWindow(nil)
        
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Finder Integration
    
    private func getFinderSelectedFiles() -> [URL]? {
        // Finderが最前面アプリでなければスキップ
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier == "com.apple.finder" else {
            return nil
        }

        let script = """
        tell application "Finder"
            set selectedItems to selection
            if (count of selectedItems) is 0 then return ""
            set filePaths to {}
            repeat with anItem in selectedItems
                set end of filePaths to POSIX path of (anItem as alias)
            end repeat
            set AppleScript's text item delimiters to linefeed
            return filePaths as text
        end tell
        """

        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let output = scriptObject.executeAndReturnError(&error)
            if error == nil, let text = output.stringValue, !text.isEmpty {
                let paths = text.components(separatedBy: "\n").filter { !$0.isEmpty }
                let supportedExtensions = Set(["jpg", "jpeg", "png", "heic", "tiff", "tif", "pdf"])
                let urls = paths.compactMap { URL(fileURLWithPath: $0) }
                    .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
                return urls.isEmpty ? nil : urls
            }
        }
        return nil
    }
    
    // MARK: - Error Handling
    
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
