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
    /// PDFの各ページをラスタライズした画像（モザイク加工後の画像を保持）
    var pdfPageImages: [Int: CGImage] = [:]

    // 編集履歴
    private(set) var editHistory: EditHistory
    /// PDF用：ページごとの編集履歴
    var pdfEditHistories: [Int: EditHistory] = [:]
    
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
    
    func updatePDFPage(at index: Int, with newImage: CGImage) {
        guard type == .pdf, let pdf = pdfDocument else { return }
        guard index < pdf.pageCount else { return }

        // ページ別の編集履歴を初期化（なければ）
        if pdfEditHistories[index] == nil {
            pdfEditHistories[index] = EditHistory()
        }

        // 現在の画像を履歴にpush
        if let current = pdfPageImages[index] {
            pdfEditHistories[index]?.push(current)
        }

        // 画像を保存
        pdfPageImages[index] = newImage

        // PDFドキュメント内のページを画像ページに差し替え
        let pageSize = pdf.page(at: index)?.bounds(for: .mediaBox).size ?? CGSize(width: newImage.width, height: newImage.height)
        let nsImage = NSImage(cgImage: newImage, size: pageSize)
        if let imageData = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: imageData),
           let pdfData = bitmap.representation(using: .png, properties: [:]) {
            // PDFページとして画像を挿入
            let pdfImagePage = createPDFPage(from: newImage, size: pageSize)
            if let newPage = pdfImagePage {
                pdf.removePage(at: index)
                pdf.insert(newPage, at: index)
            }
        }

        isModified = true
    }

    func undoPDFPage(at index: Int, currentImage: CGImage) -> CGImage? {
        guard let history = pdfEditHistories[index] else { return nil }
        guard let previous = history.undo(currentImage: currentImage) else { return nil }
        pdfPageImages[index] = previous

        // PDFページも差し替え
        if let pdf = pdfDocument, index < pdf.pageCount {
            let pageSize = pdf.page(at: index)?.bounds(for: .mediaBox).size ?? CGSize(width: previous.width, height: previous.height)
            if let newPage = createPDFPage(from: previous, size: pageSize) {
                pdf.removePage(at: index)
                pdf.insert(newPage, at: index)
            }
        }
        return previous
    }

    func redoPDFPage(at index: Int, currentImage: CGImage) -> CGImage? {
        guard let history = pdfEditHistories[index] else { return nil }
        guard let next = history.redo(currentImage: currentImage) else { return nil }
        pdfPageImages[index] = next

        if let pdf = pdfDocument, index < pdf.pageCount {
            let pageSize = pdf.page(at: index)?.bounds(for: .mediaBox).size ?? CGSize(width: next.width, height: next.height)
            if let newPage = createPDFPage(from: next, size: pageSize) {
                pdf.removePage(at: index)
                pdf.insert(newPage, at: index)
            }
        }
        return next
    }

    func canUndoPDFPage(at index: Int) -> Bool {
        pdfEditHistories[index]?.canUndo ?? false
    }

    func canRedoPDFPage(at index: Int) -> Bool {
        pdfEditHistories[index]?.canRedo ?? false
    }

    private func createPDFPage(from cgImage: CGImage, size: CGSize) -> PDFPage? {
        // CGImageからPDFページを作成
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return nil }
        var mediaBox = CGRect(origin: .zero, size: size)
        guard let pdfCtx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }
        pdfCtx.beginPDFPage(nil)
        pdfCtx.draw(cgImage, in: mediaBox)
        pdfCtx.endPDFPage()
        pdfCtx.closePDF()

        guard let pdfDoc = PDFDocument(data: data as Data), let page = pdfDoc.page(at: 0) else { return nil }
        return page
    }
    
    // MARK: - Undo / Redo
    
    func undo() -> CGImage? {
        guard type == .image, let current = cgImage else { return nil }

        if let previousImage = editHistory.undo(currentImage: current) {
            cgImage = previousImage
            image = NSImage(cgImage: previousImage, size: NSSize(width: previousImage.width, height: previousImage.height))
            return previousImage
        }
        return nil
    }

    func redo() -> CGImage? {
        guard type == .image, let current = cgImage else { return nil }

        if let nextImage = editHistory.redo(currentImage: current) {
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
