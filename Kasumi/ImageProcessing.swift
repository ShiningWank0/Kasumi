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

        // CGImage座標系はY軸反転 — CIImageのextentに合わせてrectを変換
        let flippedRect = CGRect(
            x: rect.origin.x,
            y: sourceCIImage.extent.height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )

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
            filteredImage = sourceCIImage.applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: Double(blockSize)
            ])
        case .colorFill:
            filteredImage = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
                .cropped(to: sourceCIImage.extent)
        }

        // 指定範囲のみをエフェクト適用、それ以外は元画像
        let maskImage = createRectMask(rect: flippedRect, imageSize: sourceCIImage.extent.size)
        let maskedImage = filteredImage.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: sourceCIImage,
            kCIInputMaskImageKey: CIImage(cgImage: maskImage)
        ])

        if let outputImage = ciContext.createCGImage(maskedImage, from: sourceCIImage.extent) {
            return outputImage
        }

        return sourceImage
    }

    /// ストローク範囲にモザイクを適用
    func applyMosaicStroke(points: [CGPoint], brushSize: CGFloat, effect: MosaicEffect) -> CGImage {
        guard !points.isEmpty else { return sourceImage }
        let sourceCIImage = CIImage(cgImage: sourceImage)
        let imageHeight = CGFloat(sourceImage.height)

        // Y軸反転したポイント
        let flippedPoints = points.map { CGPoint(x: $0.x, y: imageHeight - $0.y) }

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

        // ストロークパスからマスクを作成（反転済み座標を使用）
        let maskImage = createStrokeMask(points: flippedPoints, brushSize: brushSize, imageSize: sourceImage.size)

        // マスクを使って元画像と合成
        let maskedImage = filteredImage.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: sourceCIImage,
            kCIInputMaskImageKey: CIImage(cgImage: maskImage)
        ])

        if let outputImage = ciContext.createCGImage(maskedImage, from: sourceCIImage.extent) {
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
        let imageSize = CGSize(width: sourceImage.width, height: sourceImage.height)

        // SwiftUIのビュー座標系ではY軸が上→下だが、CGImageではY軸が下→上
        let flippedRect = CGRect(
            x: rect.origin.x,
            y: imageSize.height - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )

        // 範囲を画像サイズ内にクランプ
        let clampedRect = flippedRect.intersection(CGRect(origin: .zero, size: imageSize))

        guard !clampedRect.isEmpty, clampedRect.width > 1, clampedRect.height > 1 else {
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
/// 修正: ピクセルデータのライフサイクル管理、BFSの効率化
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
        return await Task.detached { [width, height, sourceImage] in
            return Self.performFloodFill(
                image: sourceImage,
                width: width,
                height: height,
                startPoint: startPoint,
                tolerance: tolerance
            )
        }.value
    }

    private static func performFloodFill(
        image: CGImage,
        width: Int,
        height: Int,
        startPoint: CGPoint,
        tolerance: Int
    ) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        // CGContextを作成しスコープ内に保持（ピクセルデータのライフサイクルを保証）
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

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let pixelData = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return nil
        }

        let x = Int(startPoint.x)
        // Y軸変換: ビュー座標（上→下）をCGImage座標（下→上）に
        let y = Int(startPoint.y)

        guard x >= 0 && x < width && y >= 0 && y < height else { return nil }

        let baseOffset = (y * width + x) * bytesPerPixel
        let baseR = pixelData[baseOffset]
        let baseG = pixelData[baseOffset + 1]
        let baseB = pixelData[baseOffset + 2]
        let toleranceSq = Double(tolerance * tolerance)

        // 1ビットのvisited配列（メモリ効率化）
        let totalPixels = width * height
        var visited = [UInt64](repeating: 0, count: (totalPixels + 63) / 64)

        // リングバッファBFS（O(1) dequeue）
        // 最大キューサイズを画像サイズに制限
        var ringBuffer = [Int32](repeating: 0, count: min(totalPixels, 4_000_000) * 2)
        let ringCapacity = ringBuffer.count / 2
        var head = 0
        var tail = 0
        var count = 0

        func enqueue(_ px: Int, _ py: Int) {
            let idx = py * width + px
            let wordIdx = idx >> 6
            let bitIdx = idx & 63
            let mask: UInt64 = 1 << bitIdx
            guard visited[wordIdx] & mask == 0 else { return }
            visited[wordIdx] |= mask

            let offset = idx * bytesPerPixel
            let dr = Double(pixelData[offset]) - Double(baseR)
            let dg = Double(pixelData[offset + 1]) - Double(baseG)
            let db = Double(pixelData[offset + 2]) - Double(baseB)
            let distSq = dr * dr + dg * dg + db * db

            guard distSq <= toleranceSq else { return }

            // 透明化
            pixelData[offset + 3] = 0

            let ringIdx = tail % ringCapacity
            ringBuffer[ringIdx * 2] = Int32(px)
            ringBuffer[ringIdx * 2 + 1] = Int32(py)
            tail += 1
            count += 1
        }

        enqueue(x, y)

        while count > 0 {
            let ringIdx = head % ringCapacity
            let cx = Int(ringBuffer[ringIdx * 2])
            let cy = Int(ringBuffer[ringIdx * 2 + 1])
            head += 1
            count -= 1

            if cx > 0 { enqueue(cx - 1, cy) }
            if cx < width - 1 { enqueue(cx + 1, cy) }
            if cy > 0 { enqueue(cx, cy - 1) }
            if cy < height - 1 { enqueue(cx, cy + 1) }
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
