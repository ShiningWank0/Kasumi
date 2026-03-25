//
//  AppDelegate.swift
//  Kasumi
//
//  Created by Takuma Kaneko on 2026/03/25.
//

import Cocoa
import SwiftUI

/// アプリケーションのメインデリゲート
/// グローバルショートカット、Dock挙動、アプリケーションライフサイクルを管理
class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var globalShortcutMonitor: GlobalShortcutMonitor?
    
    // MARK: - Application Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupGlobalShortcut()
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
            let editorVC = EditorViewController(document: document)
            
            let window = NSWindow(contentViewController: editorVC)
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
        let editorVC = EditorViewController(document: document)
        
        let window = NSWindow(contentViewController: editorVC)
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
        let script = """
        tell application "Finder"
            set selectedItems to selection
            set filePaths to {}
            repeat with anItem in selectedItems
                set end of filePaths to POSIX path of (anItem as alias)
            end repeat
            return filePaths
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: script) {
            let output = scriptObject.executeAndReturnError(&error)
            if error == nil {
                let paths = output.stringValue?.components(separatedBy: ", ") ?? []
                let urls = paths.compactMap { URL(fileURLWithPath: $0) }
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
