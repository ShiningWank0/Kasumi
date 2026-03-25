//
//  ImageProcessing.swift
//  Kasumi
//
//  Created by Takuma Kaneko on 2026/03/25.
//

import CoreGraphics
import CoreImage
import Metal
import Foundation

// MARK: - Mosaic Effect Type

/// モザイク・ぼかしエフェクトの種類
enum MosaicEffect {
    case classic        // クラシックモザイク
    case blur           // Gaussianぼかし
    case frostGlass     // フロストガラス
    case colorFill      // カラー塗りつぶし
}

// MARK: - Mosaic Processor

/// モザイク・ぼかし処理を行うプロセッサー
class MosaicProcessor {
    
    private let sourceImage: CGImage
    private let ciContext: CIContext
    
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
    
    /// 矩形範囲にモザイクを適用
    func applyMosaic(in rect: CGRect, effect: MosaicEffect, blockSize: Int = 20) -> CGImage {
        let sourceCIImage = CIImage(cgImage: sourceImage)
        
        // エフェクトを適用した画像全体を作成
        let filteredImage: CIImage
        switch effect {
        case .classic:
            filteredImage = sourceCIImage.applyingFilter("CIPixellate", parameters: [
                kCIInputScaleKey: blockSize
            ])
        case .blur:
            filteredImage = sourceCIImage.applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: Double(blockSize)
            ])
        case .frostGlass:
            let blurred = sourceCIImage.applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: Double(blockSize)
            ])
            filteredImage = blurred
        case .colorFill:
            filteredImage = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
                .cropped(to: sourceCIImage.extent)
        }
        
        // 指定範囲のみをエフェクト適用、それ以外は元画像
        let maskImage = createRectMask(rect: rect, imageSize: sourceCIImage.extent.size)
        let maskedImage = filteredImage.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: sourceCIImage,
            kCIInputMaskImageKey: CIImage(cgImage: maskImage)
        ])
        
        if let outputImage = ciContext.createCGImage(maskedImage, from: maskedImage.extent) {
            return outputImage
        }
        
        return sourceImage
    }
    
    /// ストローク範囲にモザイクを適用
    func applyMosaicStroke(points: [CGPoint], brushSize: CGFloat, effect: MosaicEffect) -> CGImage {
        guard !points.isEmpty else { return sourceImage }
        let sourceCIImage = CIImage(cgImage: sourceImage)
        
        // エフェクトを画像全体に適用
        let filteredImage: CIImage
        switch effect {
        case .classic:
            filteredImage = sourceCIImage.applyingFilter("CIPixellate", parameters: [
                kCIInputScaleKey: 20
            ])
        case .blur:
            filteredImage = sourceCIImage.applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: 20.0
            ])
        case .frostGlass:
            filteredImage = sourceCIImage.applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: 20.0
            ])
        case .colorFill:
            filteredImage = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
                .cropped(to: sourceCIImage.extent)
        }
        
        // ストロークパスからマスクを作成
        let maskImage = createStrokeMask(points: points, brushSize: brushSize, imageSize: sourceImage.size)
        
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
    
    // MARK: - Mask Creation
    
    private func createRectMask(rect: CGRect, imageSize: CGSize) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        
        guard let context = CGContext(
            data: nil,
            width: Int(imageSize.width),
            height: Int(imageSize.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(imageSize.width),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return createEmptyMask(size: imageSize)
        }
        
        // 黒で塗りつぶし（マスクなし）
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: imageSize))
        
        // 指定範囲を白で描画（マスク適用範囲）
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        
        return context.makeImage() ?? createEmptyMask(size: imageSize)
    }
    
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

// MARK: - Trim Processor

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

// MARK: - Background Remover

/// 背景透明化処理（フラッドフィル方式）
nonisolated class BackgroundRemover {
    
    private let sourceImage: CGImage
    private let width: Int
    private let height: Int
    
    init(image: CGImage) {
        self.sourceImage = image
        self.width = image.width
        self.height = image.height
    }
    
    /// 指定した座標から開始して、背景を透明化
    func removeBackground(startingAt startPoint: CGPoint, tolerance: Int) async -> CGImage? {
        return await Task.detached {
            return self.performFloodFill(startPoint: startPoint, tolerance: tolerance)
        }.value
    }
    
    private func performFloodFill(startPoint: CGPoint, tolerance: Int) -> CGImage? {
        guard let pixelData = getPixelData() else { return nil }
        
        let x = Int(startPoint.x)
        let y = Int(startPoint.y)
        
        guard x >= 0 && x < width && y >= 0 && y < height else { return nil }
        
        let baseColor = getPixelColor(at: (x, y), from: pixelData)
        var visited = Array(repeating: Array(repeating: false, count: width), count: height)
        var queue: [(Int, Int)] = [(x, y)]
        visited[y][x] = true
        
        while !queue.isEmpty {
            let (cx, cy) = queue.removeFirst()
            setPixelAlpha(at: (cx, cy), alpha: 0, in: pixelData)
            
            let neighbors = [
                (cx - 1, cy),
                (cx + 1, cy),
                (cx, cy - 1),
                (cx, cy + 1)
            ]
            
            for (nx, ny) in neighbors {
                guard nx >= 0 && nx < width && ny >= 0 && ny < height else { continue }
                guard !visited[ny][nx] else { continue }
                
                let neighborColor = getPixelColor(at: (nx, ny), from: pixelData)
                let colorDistance = calculateColorDistance(baseColor, neighborColor)
                
                if colorDistance <= Double(tolerance) {
                    visited[ny][nx] = true
                    queue.append((nx, ny))
                }
            }
        }
        
        return createImage(from: pixelData)
    }
    
    private func getPixelData() -> UnsafeMutablePointer<UInt8>? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.data?.assumingMemoryBound(to: UInt8.self)
    }
    
    private func getPixelColor(at point: (Int, Int), from pixelData: UnsafeMutablePointer<UInt8>) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let (x, y) = point
        let bytesPerPixel = 4
        let offset = (y * width + x) * bytesPerPixel
        
        return (pixelData[offset], pixelData[offset + 1], pixelData[offset + 2], pixelData[offset + 3])
    }
    
    private func setPixelAlpha(at point: (Int, Int), alpha: UInt8, in pixelData: UnsafeMutablePointer<UInt8>) {
        let (x, y) = point
        let bytesPerPixel = 4
        let offset = (y * width + x) * bytesPerPixel
        pixelData[offset + 3] = alpha
    }
    
    private func calculateColorDistance(_ color1: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ color2: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Double {
        let dr = Double(color1.r) - Double(color2.r)
        let dg = Double(color1.g) - Double(color2.g)
        let db = Double(color1.b) - Double(color2.b)
        return sqrt(dr * dr + dg * dg + db * db)
    }
    
    private func createImage(from pixelData: UnsafeMutablePointer<UInt8>) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        guard let context = CGContext(
            data: pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        return context.makeImage()
    }
}

// MARK: - CGImage Extension

extension CGImage {
    var size: CGSize {
        return CGSize(width: width, height: height)
    }
}
