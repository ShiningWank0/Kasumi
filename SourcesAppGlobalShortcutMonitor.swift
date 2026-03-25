import Cocoa
import Carbon

/// グローバルキーボードショートカットを監視するクラス
class GlobalShortcutMonitor {
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var callback: (() -> Void)?
    
    // デフォルト: ⌘ + Shift + K
    private var targetKeyCode: UInt16 = 0x28 // K key
    private var targetModifiers: CGEventFlags = [.maskCommand, .maskShift]
    
    // MARK: - Initialization
    
    init() {
        loadShortcutFromSettings()
    }
    
    deinit {
        stop()
    }
    
    // MARK: - Control
    
    func start(callback: @escaping () -> Void) {
        self.callback = callback
        
        // アクセシビリティ権限をチェック
        guard checkAccessibilityPermission() else {
            promptForAccessibilityPermission()
            return
        }
        
        // イベントタップを作成
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            NSLog("Failed to create event tap")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        NSLog("Global shortcut monitor started")
    }
    
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            eventTap = nil
            runLoopSource = nil
        }
        NSLog("Global shortcut monitor stopped")
    }
    
    // MARK: - Event Handling
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // キーダウンイベントのみ処理
        guard type == .keyDown else {
            return Unmanaged.passRetained(event)
        }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        
        // ターゲットのキーとモディファイアがマッチするかチェック
        if keyCode == Int64(targetKeyCode) && flags.contains(targetModifiers) {
            DispatchQueue.main.async { [weak self] in
                self?.callback?()
            }
            // イベントを消費（他のアプリに渡さない）
            return nil
        }
        
        // それ以外のイベントはパススルー
        return Unmanaged.passRetained(event)
    }
    
    // MARK: - Settings
    
    private func loadShortcutFromSettings() {
        if let keyCode = UserDefaults.standard.object(forKey: "globalShortcutKeyCode") as? UInt16 {
            targetKeyCode = keyCode
        }
        
        if let modifiersRaw = UserDefaults.standard.object(forKey: "globalShortcutModifiers") as? UInt64 {
            targetModifiers = CGEventFlags(rawValue: modifiersRaw)
        }
    }
    
    func updateShortcut(keyCode: UInt16, modifiers: CGEventFlags) {
        targetKeyCode = keyCode
        targetModifiers = modifiers
        
        UserDefaults.standard.set(keyCode, forKey: "globalShortcutKeyCode")
        UserDefaults.standard.set(modifiers.rawValue, forKey: "globalShortcutModifiers")
        
        // 再起動が必要
        if eventTap != nil {
            let oldCallback = callback
            stop()
            if let oldCallback = oldCallback {
                start(callback: oldCallback)
            }
        }
    }
    
    // MARK: - Accessibility Permission
    
    private func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    private func promptForAccessibilityPermission() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Kasumi needs Accessibility permission to monitor global keyboard shortcuts.\n\nPlease grant permission in System Settings > Privacy & Security > Accessibility."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
