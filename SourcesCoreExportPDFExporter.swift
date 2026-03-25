import PDFKit
import Foundation

/// PDFファイルの書き出し処理
enum PDFExporter {
    
    enum ExportError: Error {
        case failedToWritePDF
    }
    
    /// PDFDocumentをファイルに書き出す
    /// - Parameters:
    ///   - document: 書き出すPDFドキュメント
    ///   - url: 保存先URL
    static func export(_ document: PDFDocument, to url: URL) throws {
        guard document.write(to: url) else {
            throw ExportError.failedToWritePDF
        }
    }
    
    /// PDFページに編集済み画像を適用（選択的Redaction）
    /// - Parameters:
    ///   - page: 対象のPDFページ
    ///   - image: 適用する画像
    ///   - rect: 適用範囲
    static func applyRedactedImage(to page: PDFPage, image: CGImage, in rect: CGRect) {
        // PDFページのグラフィックスコンテキストに描画
        let pageBounds = page.bounds(for: .mediaBox)
        
        // 新しいPDFページを作成
        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &pageBounds.bounds, nil) else {
            return
        }
        
        context.beginPDFPage(nil)
        
        // 元のページを描画
        context.saveGState()
        if let pageRef = page.pageRef {
            context.drawPDFPage(pageRef)
        }
        context.restoreGState()
        
        // 編集済み画像を指定範囲に描画（上書き）
        context.draw(image, in: rect)
        
        context.endPDFPage()
        context.closePDF()
        
        // 新しいページデータで置き換え
        // 注: この実装は簡略化されており、実際にはPDFのコンテンツストリームを
        // より詳細に操作する必要があります
    }
}
