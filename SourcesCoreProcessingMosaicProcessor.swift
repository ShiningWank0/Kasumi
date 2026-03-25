import CoreImage
import CoreGraphics
import Metal

/// モザイク・ぼかしエフェクトの種類
enum MosaicEffect {
    case classic        // クラシックモザイク
    case blur           // Gaussianぼかし
    case frostGlass     // フロストガラス
    case colorFill      // カラー塗りつぶし
}

/// モザイク・ぼかし処理を行うプロセッサー
class MosaicProcessor {
    
    private let sourceImage: CGImage
    private let ciContext: CIContext
    
    // MARK: - Initialization
    
    init?(image: CGImage) {
        self.sourceImage = image
        
        // MetalデバイスでCore Imageコンテキストを作成
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(mtlDevice: metalDevice)
        } else {
            // Metalが利用できない場合はCPUフォールバック
            self.ciContext = CIContext()
        }
    }
    
    // MARK: - Mosaic Application
    
    /// 矩形範囲にモザイクを適用
    func applyMosaic(in rect: CGRect, effect: MosaicEffect, blockSize: Int = 20) -> CGImage {
        guard let sourceCIImage = CIImage(cgImage: sourceImage) else {
            return sourceImage
        }
        
        // エフェクトを適用
        let filteredImage: CIImage
        switch effect {
        case .classic:
            filteredImage = applyClassicMosaic(to: sourceCIImage, in: rect, blockSize: blockSize)
        case .blur:
            filteredImage = applyBlur(to: sourceCIImage, in: rect, radius: Double(blockSize))
        case .frostGlass:
            filteredImage = applyFrostGlass(to: sourceCIImage, in: rect, intensity: Double(blockSize))
        case .colorFill:
            filteredImage = applyColorFill(to: sourceCIImage, in: rect)
        }
        
        // CGImageに変換
        if let outputImage = ciContext.createCGImage(filteredImage, from: filteredImage.extent) {
            return outputImage
        }
        
        return sourceImage
    }
    
    /// ストローク範囲にモザイクを適用
    func applyMosaicStroke(points: [CGPoint], brushSize: CGFloat, effect: MosaicEffect) -> CGImage {
        guard !points.isEmpty else { return sourceImage }
        guard let sourceCIImage = CIImage(cgImage: sourceImage) else {
            return sourceImage
        }
        
        // ストロークパスからマスクを作成
        let maskImage = createStrokeMask(points: points, brushSize: brushSize, imageSize: sourceImage.size)
        
        // エフェクトを画像全体に適用
        let filteredImage: CIImage
        switch effect {
        case .classic:
            filteredImage = applyClassicMosaicFilter(to: sourceCIImage, blockSize: 20)
        case .blur:
            filteredImage = applyBlurFilter(to: sourceCIImage, radius: 20)
        case .frostGlass:
            filteredImage = applyFrostGlassFilter(to: sourceCIImage, intensity: 20)
        case .colorFill:
            filteredImage = applyColorFillFilter(to: sourceCIImage)
        }
        
        // マスクを使って元画像と合成
        let maskedImage = filteredImage.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: sourceCIImage,
            kCIInputMaskImageKey: CIImage(cgImage: maskImage)
        ])
        
        if let outputImage = ciContext.createCGImage(maskedImage, from: maskedImage.extent) {
            return outputImage
        }
        
        return sourceImage
    }
    
    // MARK: - Effect Filters
    
    private func applyClassicMosaic(to image: CIImage, in rect: CGRect, blockSize: Int) -> CIImage {
        let croppedImage = image.cropped(to: rect)
        let mosaicImage = applyClassicMosaicFilter(to: croppedImage, blockSize: blockSize)
        return image.applyingFilter("CISourceOverCompositing", parameters: [
            kCIInputBackgroundImageKey: image,
            kCIInputImageKey: mosaicImage.transformed(by: CGAffineTransform(translationX: rect.origin.x, y: rect.origin.y))
        ])
    }
    
    private func applyClassicMosaicFilter(to image: CIImage, blockSize: Int) -> CIImage {
        return image.applyingFilter("CIPixellate", parameters: [
            kCIInputScaleKey: blockSize
        ])
    }
    
    private func applyBlur(to image: CIImage, in rect: CGRect, radius: Double) -> CIImage {
        let croppedImage = image.cropped(to: rect)
        let blurredImage = applyBlurFilter(to: croppedImage, radius: radius)
        return image.applyingFilter("CISourceOverCompositing", parameters: [
            kCIInputBackgroundImageKey: image,
            kCIInputImageKey: blurredImage.transformed(by: CGAffineTransform(translationX: rect.origin.x, y: rect.origin.y))
        ])
    }
    
    private func applyBlurFilter(to image: CIImage, radius: Double) -> CIImage {
        return image.applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: radius
        ])
    }
    
    private func applyFrostGlass(to image: CIImage, in rect: CGRect, intensity: Double) -> CIImage {
        let croppedImage = image.cropped(to: rect)
        let frostImage = applyFrostGlassFilter(to: croppedImage, intensity: intensity)
        return image.applyingFilter("CISourceOverCompositing", parameters: [
            kCIInputBackgroundImageKey: image,
            kCIInputImageKey: frostImage.transformed(by: CGAffineTransform(translationX: rect.origin.x, y: rect.origin.y))
        ])
    }
    
    private func applyFrostGlassFilter(to image: CIImage, intensity: Double) -> CIImage {
        // Gaussianブラー + ノイズ + コントラスト調整
        let blurred = image.applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: intensity
        ])
        
        // ノイズを追加
        let noiseImage = CIFilter(name: "CIRandomGenerator")?.outputImage?
            .cropped(to: image.extent)
            .applyingFilter("CIColorMonochrome", parameters: [
                kCIInputColorKey: CIColor.white,
                kCIInputIntensityKey: 0.1
            ])
        
        if let noise = noiseImage {
            return blurred.applyingFilter("CISourceOverCompositing", parameters: [
                kCIInputBackgroundImageKey: blurred,
                kCIInputImageKey: noise
            ])
        }
        
        return blurred
    }
    
    private func applyColorFill(to image: CIImage, in rect: CGRect) -> CIImage {
        // 単色で塗りつぶし（グレー）
        let colorImage = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: rect)
        
        return image.applyingFilter("CISourceOverCompositing", parameters: [
            kCIInputBackgroundImageKey: image,
            kCIInputImageKey: colorImage
        ])
    }
    
    private func applyColorFillFilter(to image: CIImage) -> CIImage {
        return CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
            .cropped(to: image.extent)
    }
    
    // MARK: - Mask Creation
    
    private func createStrokeMask(points: [CGPoint], brushSize: CGFloat, imageSize: CGSize) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGImageAlphaInfo.none.rawValue
        
        guard let context = CGContext(
            data: nil,
            width: Int(imageSize.width),
            height: Int(imageSize.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(imageSize.width),
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            // フォールバック: 空のマスク
            return createEmptyMask(size: imageSize)
        }
        
        // 黒で塗りつぶし（マスクなし）
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: imageSize))
        
        // ストロークを白で描画（マスク適用範囲）
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.setLineWidth(brushSize)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        if let firstPoint = points.first {
            context.move(to: firstPoint)
            for point in points.dropFirst() {
                context.addLine(to: point)
            }
            context.strokePath()
        }
        
        return context.makeImage() ?? createEmptyMask(size: imageSize)
    }
    
    private func createEmptyMask(size: CGSize) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        
        return context.makeImage()!
    }
}

// CGImage size extension
extension CGImage {
    var size: CGSize {
        return CGSize(width: width, height: height)
    }
}
