import Cocoa

/// アプリケーションのメインデリゲート
/// グローバルショートカット、Dock挙動、アプリケーションライフサイクルを管理
class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var globalShortcutMonitor: GlobalShortcutMonitor?
    private var settingsWindowController: NSWindowController?
    
    // MARK: - Application Lifecycle
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupApplication()
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
    
    private func setupApplication() {
        // メニューバーのセットアップ
        let mainMenu = NSMenu()
        
        // アプリケーションメニュー
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        
        appMenu.addItem(withTitle: "About Kasumi", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Settings...", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Kasumi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        
        // ファイルメニュー
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        
        fileMenu.addItem(withTitle: "Open...", action: #selector(openDocument), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Save", action: #selector(saveDocument), keyEquivalent: "s")
        fileMenu.addItem(withTitle: "Save As...", action: #selector(saveDocumentAs), keyEquivalent: "S")
        
        // 編集メニュー
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        
        editMenu.addItem(withTitle: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        
        NSApplication.shared.mainMenu = mainMenu
    }
    
    private func setupGlobalShortcut() {
        globalShortcutMonitor = GlobalShortcutMonitor()
        globalShortcutMonitor?.start { [weak self] in
            self?.handleGlobalShortcut()
        }
    }
    
    // MARK: - Actions
    
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Kasumi"
        alert.informativeText = "Privacy-focused image and PDF editor for macOS\nVersion 1.0.0\n\n© 2026 Kasumi Contributors\nMIT License"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc private func showSettings() {
        if settingsWindowController == nil {
            let settingsVC = SettingsViewController()
            let window = NSWindow(contentViewController: settingsVC)
            window.title = "Settings"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 500, height: 400))
            settingsWindowController = NSWindowController(window: window)
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func openDocument() {
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
    
    @objc private func saveDocument() {
        // キーウィンドウのビューコントローラーから保存処理を呼び出す
        if let editorVC = NSApp.keyWindow?.contentViewController as? EditorViewController {
            editorVC.save()
        }
    }
    
    @objc private func saveDocumentAs() {
        // キーウィンドウのビューコントローラーから別名保存処理を呼び出す
        if let editorVC = NSApp.keyWindow?.contentViewController as? EditorViewController {
            editorVC.saveAs()
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
