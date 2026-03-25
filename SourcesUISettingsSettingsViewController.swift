import Cocoa

/// 設定画面のビューコントローラー
class SettingsViewController: NSViewController {
    
    private let shortcutRecorder = ShortcutRecorderView()
    private let infoLabel = NSTextField(labelWithString: "Global Shortcut:")
    
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        // タイトル
        let titleLabel = NSTextField(labelWithString: "Settings")
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        
        // ショートカット設定セクション
        let shortcutSection = NSStackView()
        shortcutSection.orientation = .vertical
        shortcutSection.alignment = .leading
        shortcutSection.spacing = 8
        shortcutSection.translatesAutoresizingMaskIntoConstraints = false
        
        let sectionTitle = NSTextField(labelWithString: "Keyboard Shortcuts")
        sectionTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        shortcutSection.addArrangedSubview(sectionTitle)
        
        // ショートカットレコーダー
        let shortcutContainer = NSStackView()
        shortcutContainer.orientation = .horizontal
        shortcutContainer.spacing = 12
        
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        shortcutRecorder.translatesAutoresizingMaskIntoConstraints = false
        
        shortcutContainer.addArrangedSubview(infoLabel)
        shortcutContainer.addArrangedSubview(shortcutRecorder)
        
        shortcutSection.addArrangedSubview(shortcutContainer)
        
        // 説明文
        let descLabel = NSTextField(wrappingLabelWithString: "This shortcut will open Kasumi with clipboard image or Finder-selected files.")
        descLabel.font = .systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        descLabel.preferredMaxLayoutWidth = 450
        shortcutSection.addArrangedSubview(descLabel)
        
        view.addSubview(shortcutSection)
        
        // About セクション
        let aboutSection = NSStackView()
        aboutSection.orientation = .vertical
        aboutSection.alignment = .leading
        aboutSection.spacing = 8
        aboutSection.translatesAutoresizingMaskIntoConstraints = false
        
        let aboutTitle = NSTextField(labelWithString: "About")
        aboutTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        aboutSection.addArrangedSubview(aboutTitle)
        
        let versionLabel = NSTextField(labelWithString: "Version 1.0.0")
        versionLabel.font = .systemFont(ofSize: 12)
        versionLabel.textColor = .secondaryLabelColor
        aboutSection.addArrangedSubview(versionLabel)
        
        let licenseLabel = NSTextField(labelWithString: "Licensed under MIT License")
        licenseLabel.font = .systemFont(ofSize: 12)
        licenseLabel.textColor = .secondaryLabelColor
        aboutSection.addArrangedSubview(licenseLabel)
        
        view.addSubview(aboutSection)
        
        // レイアウト制約
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            
            shortcutSection.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 30),
            shortcutSection.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            shortcutSection.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            
            shortcutRecorder.widthAnchor.constraint(equalToConstant: 200),
            shortcutRecorder.heightAnchor.constraint(equalToConstant: 28),
            
            aboutSection.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            aboutSection.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20)
        ])
    }
}

/// ショートカットキーを記録するカスタムビュー
class ShortcutRecorderView: NSView {
    
    private let textField = NSTextField()
    private var isRecording = false
    
    private var recordedKeyCode: UInt16 = 0x28 // デフォルト: K
    private var recordedModifiers: NSEvent.ModifierFlags = [.command, .shift]
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        loadSavedShortcut()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        loadSavedShortcut()
    }
    
    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        
        textField.isEditable = false
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.alignment = .center
        textField.font = .systemFont(ofSize: 13)
        textField.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(textField)
        
        NSLayoutConstraint.activate([
            textField.centerXAnchor.constraint(equalTo: centerXAnchor),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
            textField.widthAnchor.constraint(equalTo: widthAnchor, constant: -16)
        ])
        
        updateDisplay()
    }
    
    override func mouseDown(with event: NSEvent) {
        isRecording = true
        textField.stringValue = "Press keys..."
        layer?.backgroundColor = NSColor.selectedControlColor.withAlphaComponent(0.3).cgColor
    }
    
    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }
        
        recordedKeyCode = event.keyCode
        recordedModifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        
        // 保存
        saveShortcut()
        
        isRecording = false
        updateDisplay()
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    }
    
    private func updateDisplay() {
        var parts: [String] = []
        
        if recordedModifiers.contains(.control) {
            parts.append("⌃")
        }
        if recordedModifiers.contains(.option) {
            parts.append("⌥")
        }
        if recordedModifiers.contains(.shift) {
            parts.append("⇧")
        }
        if recordedModifiers.contains(.command) {
            parts.append("⌘")
        }
        
        // キーコードを文字に変換（簡易版）
        let keyChar = keyCodeToString(recordedKeyCode)
        parts.append(keyChar)
        
        textField.stringValue = parts.joined()
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        // 簡易的なキーコード変換
        let keyMap: [UInt16: String] = [
            0x28: "K",
            0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E",
            0x03: "F", 0x05: "G", 0x04: "H", 0x22: "I", 0x26: "J",
            0x25: "L", 0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P",
            0x0C: "Q", 0x0F: "R", 0x01: "S", 0x11: "T", 0x20: "U",
            0x09: "V", 0x0D: "W", 0x07: "X", 0x10: "Y", 0x06: "Z"
        ]
        return keyMap[keyCode] ?? "?"
    }
    
    private func loadSavedShortcut() {
        if let keyCode = UserDefaults.standard.object(forKey: "globalShortcutKeyCode") as? UInt16 {
            recordedKeyCode = keyCode
        }
        
        if let modifiersRaw = UserDefaults.standard.object(forKey: "globalShortcutModifiersNS") as? UInt {
            recordedModifiers = NSEvent.ModifierFlags(rawValue: modifiersRaw)
        }
    }
    
    private func saveShortcut() {
        UserDefaults.standard.set(recordedKeyCode, forKey: "globalShortcutKeyCode")
        UserDefaults.standard.set(recordedModifiers.rawValue, forKey: "globalShortcutModifiersNS")
        
        // CGEventFlagsに変換して保存
        var cgFlags: CGEventFlags = []
        if recordedModifiers.contains(.command) { cgFlags.insert(.maskCommand) }
        if recordedModifiers.contains(.shift) { cgFlags.insert(.maskShift) }
        if recordedModifiers.contains(.control) { cgFlags.insert(.maskControl) }
        if recordedModifiers.contains(.option) { cgFlags.insert(.maskAlternate) }
        
        UserDefaults.standard.set(cgFlags.rawValue, forKey: "globalShortcutModifiers")
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
}
