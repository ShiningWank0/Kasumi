import CoreGraphics

/// 画像のトリミング処理
class TrimProcessor {
    
    private let sourceImage: CGImage
    
    init?(image: CGImage) {
        self.sourceImage = image
    }
    
    /// 指定した矩形範囲で画像をトリミング
    func trim(to rect: CGRect) -> CGImage {
        // 範囲を画像サイズ内にクランプ
        let imageSize = CGSize(width: sourceImage.width, height: sourceImage.height)
        let clampedRect = rect.intersection(CGRect(origin: .zero, size: imageSize))
        
        guard !clampedRect.isEmpty else {
            return sourceImage
        }
        
        // CGImageをクロップ
        if let croppedImage = sourceImage.cropping(to: clampedRect) {
            return croppedImage
        }
        
        return sourceImage
    }
}
