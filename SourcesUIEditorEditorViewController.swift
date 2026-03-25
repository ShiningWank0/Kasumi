import Cocoa

/// メイン編集画面のビューコントローラー
class EditorViewController: NSViewController {
    
    // MARK: - Properties
    
    private let document: KasumiDocument
    private var canvasView: CanvasView!
    private var toolbarView: ToolbarView!
    
    private var currentTool: EditTool = .none
    
    // MARK: - Initialization
    
    init(document: KasumiDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - View Lifecycle
    
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1024, height: 768))
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadDocument()
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        // キャンバスビュー
        canvasView = CanvasView(frame: view.bounds)
        canvasView.autoresizingMask = [.width, .height]
        canvasView.delegate = self
        view.addSubview(canvasView)
        
        // ツールバー
        toolbarView = ToolbarView()
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.delegate = self
        view.addSubview(toolbarView)
        
        NSLayoutConstraint.activate([
            toolbarView.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            toolbarView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toolbarView.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    private func loadDocument() {
        if let cgImage = document.cgImage {
            canvasView.setImage(cgImage)
        }
    }
    
    // MARK: - Tool Selection
    
    private func selectTool(_ tool: EditTool) {
        currentTool = tool
        canvasView.setTool(tool)
    }
    
    // MARK: - Save Actions
    
    func save() {
        do {
            try document.save()
            showNotification("Saved successfully")
        } catch {
            showError("Failed to save: \(error.localizedDescription)")
        }
    }
    
    func saveAs() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.jpeg, .png, .tiff]
        savePanel.nameFieldStringValue = "Untitled"
        
        savePanel.begin { [weak self] response in
            guard response == .OK, let url = savePanel.url else { return }
            
            do {
                try self?.document.save(to: url)
                self?.view.window?.title = url.lastPathComponent
                self?.showNotification("Saved successfully")
            } catch {
                self?.showError("Failed to save: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Undo / Redo
    
    @objc func undo() {
        if let previousImage = document.undo() {
            canvasView.setImage(previousImage)
        }
    }
    
    @objc func redo() {
        if let nextImage = document.redo() {
            canvasView.setImage(nextImage)
        }
    }
    
    // MARK: - Notifications
    
    private func showNotification(_ message: String) {
        // 簡易通知（後でより良いUIに改善）
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - CanvasViewDelegate

extension EditorViewController: CanvasViewDelegate {
    
    func canvasViewDidCompleteEdit(_ canvasView: CanvasView, resultImage: CGImage) {
        document.updateImage(resultImage)
    }
}

// MARK: - ToolbarViewDelegate

extension EditorViewController: ToolbarViewDelegate {
    
    func toolbarView(_ toolbar: ToolbarView, didSelectTool tool: EditTool) {
        selectTool(tool)
    }
    
    func toolbarViewDidRequestUndo(_ toolbar: ToolbarView) {
        undo()
    }
    
    func toolbarViewDidRequestRedo(_ toolbar: ToolbarView) {
        redo()
    }
    
    func toolbarViewDidRequestSave(_ toolbar: ToolbarView) {
        save()
    }
}
