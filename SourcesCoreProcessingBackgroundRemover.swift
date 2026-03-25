import CoreGraphics
import Foundation

/// 背景透明化処理（フラッドフィル方式）
class BackgroundRemover {
    
    private let sourceImage: CGImage
    private let width: Int
    private let height: Int
    
    init(image: CGImage) {
        self.sourceImage = image
        self.width = image.width
        self.height = image.height
    }
    
    /// 指定した座標から開始して、背景を透明化
    /// - Parameters:
    ///   - startPoint: 透明化を開始する座標
    ///   - tolerance: 色の許容範囲（0〜100）
    /// - Returns: 透明化された画像
    func removeBackground(startingAt startPoint: CGPoint, tolerance: Int) async -> CGImage? {
        // バックグラウンドスレッドで実行
        return await Task.detached {
            return self.performFloodFill(startPoint: startPoint, tolerance: tolerance)
        }.value
    }
    
    // MARK: - Flood Fill Algorithm
    
    private func performFloodFill(startPoint: CGPoint, tolerance: Int) -> CGImage? {
        // ピクセルデータを取得
        guard let pixelData = getPixelData() else { return nil }
        
        let x = Int(startPoint.x)
        let y = Int(startPoint.y)
        
        // 範囲チェック
        guard x >= 0 && x < width && y >= 0 && y < height else { return nil }
        
        // 基準色を取得
        let baseColor = getPixelColor(at: (x, y), from: pixelData)
        
        // 訪問済みフラグ
        var visited = Array(repeating: Array(repeating: false, count: width), count: height)
        
        // BFS
        var queue: [(Int, Int)] = [(x, y)]
        visited[y][x] = true
        
        while !queue.isEmpty {
            let (cx, cy) = queue.removeFirst()
            
            // 透明化
            setPixelAlpha(at: (cx, cy), alpha: 0, in: pixelData)
            
            // 4方向探索
            let neighbors = [
                (cx - 1, cy),
                (cx + 1, cy),
                (cx, cy - 1),
                (cx, cy + 1)
            ]
            
            for (nx, ny) in neighbors {
                // 範囲チェック
                guard nx >= 0 && nx < width && ny >= 0 && ny < height else { continue }
                guard !visited[ny][nx] else { continue }
                
                // 色差チェック
                let neighborColor = getPixelColor(at: (nx, ny), from: pixelData)
                let colorDistance = calculateColorDistance(baseColor, neighborColor)
                
                if colorDistance <= Double(tolerance) {
                    visited[ny][nx] = true
                    queue.append((nx, ny))
                }
            }
        }
        
        // CGImageを作成
        return createImage(from: pixelData)
    }
    
    // MARK: - Pixel Data Operations
    
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
        
        let r = pixelData[offset]
        let g = pixelData[offset + 1]
        let b = pixelData[offset + 2]
        let a = pixelData[offset + 3]
        
        return (r, g, b, a)
    }
    
    private func setPixelAlpha(at point: (Int, Int), alpha: UInt8, in pixelData: UnsafeMutablePointer<UInt8>) {
        let (x, y) = point
        let bytesPerPixel = 4
        let offset = (y * width + x) * bytesPerPixel
        
        pixelData[offset + 3] = alpha
    }
    
    private func calculateColorDistance(_ color1: (r: UInt8, g: UInt8, b: UInt8, a: UInt8), _ color2: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Double {
        // RGB空間での距離
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
