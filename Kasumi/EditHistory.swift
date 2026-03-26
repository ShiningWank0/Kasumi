//
//  EditHistory.swift
//  Kasumi
//
//  Created by Takuma Kaneko on 2026/03/25.
//

import CoreGraphics
import Foundation

/// Undo/Redo機能のための編集履歴管理
/// 無制限にスタックを保持し、メモリ管理はNSCacheで行う
class EditHistory {
    
    private var undoStack: [CGImage] = []
    private var redoStack: [CGImage] = []
    
    // メモリキャッシュでLRU管理
    private let cache = NSCache<NSNumber, CGImageWrapper>()
    
    private let maxHistoryCount: Int = 100 // 実用的な上限
    
    init() {
        // キャッシュの設定
        cache.countLimit = 50 // 最大50個のCGImageをメモリに保持
    }
    
    // MARK: - Stack Operations
    
    /// 新しい編集を追加（現在の状態を履歴に保存）
    func push(_ image: CGImage) {
        undoStack.append(image)
        
        // 新しい編集が行われたらredoスタックをクリア
        redoStack.removeAll()
        
        // 上限を超えたら古いものを削除
        if undoStack.count > maxHistoryCount {
            undoStack.removeFirst()
        }
    }
    
    /// Undo: currentImage を redoStack に保存し、前の状態を返す
    func undo(currentImage: CGImage) -> CGImage? {
        guard !undoStack.isEmpty else { return nil }
        redoStack.append(currentImage)
        return undoStack.removeLast()
    }

    /// Redo: currentImage を undoStack に保存し、次の状態を返す
    func redo(currentImage: CGImage) -> CGImage? {
        guard !redoStack.isEmpty else { return nil }
        undoStack.append(currentImage)
        return redoStack.removeLast()
    }
    
    var canUndo: Bool {
        undoStack.count > 0
    }
    
    var canRedo: Bool {
        !redoStack.isEmpty
    }
    
    /// 履歴をクリア
    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        cache.removeAllObjects()
    }
}

/// CGImageをNSCacheに保存するためのラッパー
private class CGImageWrapper {
    let image: CGImage
    
    init(_ image: CGImage) {
        self.image = image
    }
}
