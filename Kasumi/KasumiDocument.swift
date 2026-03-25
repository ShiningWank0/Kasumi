//
//  KasumiDocument.swift
//  Kasumi
//
//  Created by Takuma Kaneko on 2026/03/25.
//

import Cocoa
import PDFKit
import UniformTypeIdentifiers

/// Kasumiの基本ドキュメントモデル
/// 画像またはPDFファイルを扱う
class KasumiDocument {
    
    enum DocumentType {
        case image
        case pdf
    }
    
    enum DocumentError: Error {
        case unsupportedFileType
        case failedToLoadFile
        case failedToSaveFile
        case noImageData
    }
    
    // MARK: - Properties
    
    let type: DocumentType
    private(set) var sourceURL: URL?
    private(set) var isModified: Bool = false
    
    // 画像データ
    private(set) var image: NSImage?
    private(set) var cgImage: CGImage?
    
    // PDF データ
    private(set) var pdfDocument: PDFDocument?
    
    // 編集履歴
    private(set) var editHistory: EditHistory
    
    // MARK: - Initialization
    
    /// ファイルURLから初期化
    init(contentsOf url: URL) throws {
        self.sourceURL = url
        self.editHistory = EditHistory()
        
        // ファイルタイプを判定
        if url.pathExtension.lowercased() == "pdf" {
            self.type = .pdf
            guard let pdf = PDFDocument(url: url) else {
                throw DocumentError.failedToLoadFile
            }
            self.pdfDocument = pdf
        } else {
            self.type = .image
            guard let image = NSImage(contentsOf: url) else {
                throw DocumentError.failedToLoadFile
            }
            self.image = image
            
            // CGImageを取得
            var imageRect = CGRect(origin: .zero, size: image.size)
            self.cgImage = image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
        }
    }
    
    /// NSImageから初期化（クリップボードから）
    init(image: NSImage) {
        self.type = .image
        self.image = image
        self.editHistory = EditHistory()
        
        // CGImageを取得
        var imageRect = CGRect(origin: .zero, size: image.size)
        self.cgImage = image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
    }
    
    // MARK: - Image Update
    
    func updateImage(_ newImage: CGImage) {
        guard type == .image else { return }
        
        // 現在の画像を履歴に保存
        if let current = cgImage {
            editHistory.push(current)
        }
        
        cgImage = newImage
        image = NSImage(cgImage: newImage, size: NSSize(width: newImage.width, height: newImage.height))
        isModified = true
    }
    
    func updatePDFPage(at index: Int, with image: CGImage) {
        guard type == .pdf, let pdf = pdfDocument else { return }
        guard index < pdf.pageCount else { return }
        
        // PDFページの更新処理は後で実装
        isModified = true
    }
    
    // MARK: - Undo / Redo
    
    func undo() -> CGImage? {
        guard type == .image else { return nil }
        
        if let previousImage = editHistory.undo() {
            cgImage = previousImage
            image = NSImage(cgImage: previousImage, size: NSSize(width: previousImage.width, height: previousImage.height))
            return previousImage
        }
        return nil
    }
    
    func redo() -> CGImage? {
        guard type == .image else { return nil }
        
        if let nextImage = editHistory.redo() {
            cgImage = nextImage
            image = NSImage(cgImage: nextImage, size: NSSize(width: nextImage.width, height: nextImage.height))
            return nextImage
        }
        return nil
    }
    
    var canUndo: Bool {
        editHistory.canUndo
    }
    
    var canRedo: Bool {
        editHistory.canRedo
    }
    
    // MARK: - Save
    
    func save() throws {
        guard let url = sourceURL else {
            throw DocumentError.failedToSaveFile
        }
        try save(to: url)
    }
    
    func save(to url: URL) throws {
        switch type {
        case .image:
            guard let cgImage = cgImage else {
                throw DocumentError.noImageData
            }
            try ImageExporter.export(cgImage, to: url)
            
        case .pdf:
            guard let pdf = pdfDocument else {
                throw DocumentError.noImageData
            }
            try PDFExporter.export(pdf, to: url)
        }
        
        sourceURL = url
        isModified = false
    }
}
