import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 画像ファイルの書き出し処理
enum ImageExporter {
    
    enum ExportError: Error {
        case failedToCreateDestination
        case failedToWriteImage
        case unsupportedFormat
    }
    
    /// CGImageをファイルに書き出す
    /// - Parameters:
    ///   - image: 書き出す画像
    ///   - url: 保存先URL
    ///   - quality: JPEG品質（0.0〜1.0）、デフォルトは0.9
    static func export(_ image: CGImage, to url: URL, quality: CGFloat = 0.9) throws {
        let fileExtension = url.pathExtension.lowercased()
        
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            getUTType(for: fileExtension),
            1,
            nil
        ) else {
            throw ExportError.failedToCreateDestination
        }
        
        // ファイル形式に応じたオプションを設定
        var properties: [CFString: Any] = [:]
        
        switch fileExtension {
        case "jpg", "jpeg":
            properties[kCGImageDestinationLossyCompressionQuality] = quality
            
        case "png":
            // PNGは可逆圧縮なので品質設定は不要
            break
            
        case "tif", "tiff":
            properties[kCGImageDestinationLossyCompressionQuality] = 1.0
            
        case "heic":
            properties[kCGImageDestinationLossyCompressionQuality] = quality
            
        default:
            throw ExportError.unsupportedFormat
        }
        
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.failedToWriteImage
        }
    }
    
    /// ファイル拡張子からUTTypeを取得
    private static func getUTType(for fileExtension: String) -> CFString {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg":
            return UTType.jpeg.identifier as CFString
        case "png":
            return UTType.png.identifier as CFString
        case "tif", "tiff":
            return UTType.tiff.identifier as CFString
        case "heic":
            return UTType.heic.identifier as CFString
        default:
            return UTType.png.identifier as CFString // デフォルトはPNG
        }
    }
}
