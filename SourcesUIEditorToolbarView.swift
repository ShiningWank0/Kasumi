import Cocoa

/// ツールバーのデリゲート
protocol ToolbarViewDelegate: AnyObject {
    func toolbarView(_ toolbar: ToolbarView, didSelectTool tool: EditTool)
    func toolbarViewDidRequestUndo(_ toolbar: ToolbarView)
    func toolbarViewDidRequestRedo(_ toolbar: ToolbarView)
    func toolbarViewDidRequestSave(_ toolbar: ToolbarView)
}

/// フローティングツールバー
class ToolbarView: NSView {
    
    weak var delegate: ToolbarViewDelegate?
    
    private var selectedTool: EditTool = .none
    private var toolButtons: [EditTool: NSButton] = [:]
    
    // MARK: - Initialization
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    // MARK: - UI Setup
    
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
        
        // ツールボタン
        let trimButton = createToolButton(tool: .trim, icon: "crop", tooltip: "Trim (C)")
        let mosaicRectButton = createToolButton(tool: .mosaicRect, icon: "square.on.square", tooltip: "Mosaic Area (M)")
        let mosaicStrokeButton = createToolButton(tool: .mosaicStroke, icon: "paintbrush", tooltip: "Mosaic Brush (B)")
        let bgRemovalButton = createToolButton(tool: .backgroundRemoval, icon: "wand.and.stars", tooltip: "Background Removal (T)")
        
        stackView.addArrangedSubview(trimButton)
        stackView.addArrangedSubview(mosaicRectButton)
        stackView.addArrangedSubview(mosaicStrokeButton)
        stackView.addArrangedSubview(bgRemovalButton)
        
        // セパレーター
        let separator1 = createSeparator()
        stackView.addArrangedSubview(separator1)
        
        // Undo/Redo
        let undoButton = createButton(icon: "arrow.uturn.backward", action: #selector(undoTapped), tooltip: "Undo (⌘Z)")
        let redoButton = createButton(icon: "arrow.uturn.forward", action: #selector(redoTapped), tooltip: "Redo (⌘⇧Z)")
        
        stackView.addArrangedSubview(undoButton)
        stackView.addArrangedSubview(redoButton)
        
        // セパレーター
        let separator2 = createSeparator()
        stackView.addArrangedSubview(separator2)
        
        // 保存
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
    
    // MARK: - Actions
    
    @objc private func toolButtonTapped(_ sender: NSButton) {
        // どのツールがタップされたか判定
        for (tool, button) in toolButtons {
            if button == sender {
                selectTool(tool)
                return
            }
        }
    }
    
    private func selectTool(_ tool: EditTool) {
        // 他のツールボタンを解除
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
