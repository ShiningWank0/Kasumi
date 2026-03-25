# Kasumi — Technical Design Plan

## Overview

| 項目 | 内容 |
|------|------|
| アプリ名 | Kasumi |
| プラットフォーム | macOS 13 Ventura 以上 |
| 言語 | Swift 5.9+ |
| UIフレームワーク | AppKit（一部SwiftUI併用可） |
| 配布 | GitHub OSS・無料 |
| ライセンス | MIT（予定） |
| ローカル処理 | 完全ローカル・ネット通信なし |

---

## 対応ファイル形式

| 形式 | 読み込み | 書き出し |
|------|---------|---------|
| JPEG | ✅ | ✅ |
| PNG | ✅ | ✅ |
| HEIC | ✅ | ✅ (PNG/JPEGに変換) |
| TIFF | ✅ | ✅ |
| PDF | ✅ (複数ページ) | ✅ (選択的Redaction) |

---

## アーキテクチャ方針

### 全体構成

```
Kasumi/
├── App/
│   ├── KasumiApp.swift          # エントリーポイント
│   └── AppDelegate.swift        # グローバルショートカット・Dock挙動
├── Core/
│   ├── Document/
│   │   ├── KasumiDocument.swift  # ドキュメントモデル（画像・PDF共通）
│   │   ├── ImageDocument.swift
│   │   └── PDFDocument.swift
│   ├── Processing/
│   │   ├── MosaicProcessor.swift
│   │   ├── TrimProcessor.swift
│   │   ├── BackgroundRemover.swift
│   │   └── PDFRedactor.swift
│   ├── History/
│   │   └── EditHistory.swift    # Undo/Redo管理
│   └── Export/
│       ├── ImageExporter.swift
│       └── PDFExporter.swift
├── UI/
│   ├── Editor/
│   │   ├── EditorViewController.swift   # メイン編集画面
│   │   ├── CanvasView.swift             # 描画キャンバス
│   │   ├── ToolbarView.swift            # フローティングツールバー
│   │   ├── OptionsPanel.swift           # ツールオプション
│   │   └── PDFPagePanel.swift           # PDFページサムネイル
│   ├── Settings/
│   │   └── ShortcutSettingsView.swift
│   └── Common/
│       └── OverlayView.swift            # 透明化プレビュー等
└── Resources/
    ├── Assets.xcassets
    └── Localizable.strings
```

### 設計パターン

- **MVVM** をベースにする
- ドキュメントモデルは `NSDocument` サブクラスで管理（macOS標準の保存・復元フローに乗る）
- 処理レイヤー（Core/Processing）はUIに依存しない純粋なSwiftクラスにする
- 将来的なテスト・CLI化を考慮し、処理ロジックをUIから完全分離する

---

## 機能詳細設計

### 1. グローバルショートカット

**動作フロー:**

```
ショートカットキー押下
  ├── クリップボードに画像データあり
  │     └── → そのままKasumiで編集画面を開く
  ├── Finderで画像・PDFファイルを選択中
  │     └── → そのファイルをKasumiで開く
  └── それ以外
        └── → 無視（何もしない）
```

**実装:**
- `CGEventTap` または `NSEvent.addGlobalMonitorForEvents` でグローバルキーイベントを監視
- クリップボード監視は `NSPasteboard`
- Finderの選択ファイル取得は `NSWorkspace` + AppleScript / Accessibility API
- ショートカットキーはSettings画面でカスタマイズ可能、`UserDefaults` に保存

**デフォルトショートカット:** `⌘ + Shift + K`（変更可）

---

### 2. エディタUI（CleanShot X風）

**基本レイアウト:**

```
┌─────────────────────────────────────────────────────────┐
│  [ツールバー: コンパクト・フローティング]                     │
│  ┌──┬──┬──┬──┬──┬──┐  [ブラシサイズ ●] [種類 ▾]          │
│  │✂️│🔲│🌫️│💧│🖼️│↩️│                                    │
│  └──┴──┴──┴──┴──┴──┘                                    │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │                                                  │   │
│  │                  キャンバス                        │   │
│  │           (編集対象の画像/PDF)                     │   │
│  │                                                  │   │
│  └──────────────────────────────────────────────────┘   │
│                                                         │
│  [PDF時のみ] 下部にページサムネイル横スクロール               │
└─────────────────────────────────────────────────────────┘
```

**ツールバーアイテム:**
| アイコン | ツール | ショートカット |
|---------|-------|------------|
| ✂️ | トリミング | `C` |
| 🔲 | 範囲モザイク | `M` |
| ✏️ | ストロークモザイク | `B` |
| 💧 | 背景透明化 | `T` |
| ↩️ | Undo | `⌘Z` |
| ↪️ | Redo | `⌘⇧Z` |
| 💾 | 保存 | `⌘S` / `⌘⇧S` |

**ツール選択時にインライン展開されるオプション:**
- モザイク選択時 → ブラシサイズスライダー・エフェクト種類ドロップダウン
- 背景透明化選択時 → 許容色範囲スライダー
- トリミング選択時 → アスペクト比プリセット

---

### 3. モザイク・ぼかし処理

#### v1に含めるエフェクト（プライバシー重視グループ）

| エフェクト名 | Core Imageフィルタ | 調整パラメータ |
|------------|-----------------|------------|
| クラシックモザイク | `CIPixellate` | ブロックサイズ |
| ぼかし（Gaussian） | `CIGaussianBlur` | 半径 |
| フロストガラス | `CIGaussianBlur` + `CIColorControls` + Noise | 強度 |
| カラー塗りつぶし | `CIConstantColorGenerator` | 塗りつぶし色 |

#### v2以降に追加するエフェクト（アート・表現グループ）

| エフェクト名 | 実装方針 |
|------------|---------|
| クリスタル（結晶化） | `CIPointillize` または Voronoi分割をMetalで実装 |
| ピクセルアート風 | ダウンサンプリング → ニアレストネイバーでアップサンプリング |
| ディストーション（渦） | `CITwirlDistortion` |
| ハーフトーン | `CIDotScreen` |
| 油絵風 | Metal Shaderで自前実装（Kuwahara Filter） |

#### ストロークモザイクの処理フロー

```
mouseDragged イベント
  → ストロークパスにポイント追加
  → ポイント間をCGPathで補間
  → パス領域をマスクとして切り出し
  → Core Imageフィルタ適用
  → 元画像と合成（CIBlendWithMask）
  → キャンバスに描画
```

**パフォーマンス最適化:**
- Core ImageはGPU実行（Metal バックエンド）
- ストローク中はダウンサンプリングしたプレビューを表示、リリース時にフル解像度で処理
- 大きなPDFは`CATiledLayer`でタイル単位でレンダリング

---

### 4. 背景透明化

#### アルゴリズム：フラッドフィル方式

```
クリックで基準ピクセルの色をサンプリング
  → 上下左右4方向（or 8方向）に探索（BFS）
  → 各ピクセルの色差（ΔE or RGB距離）を計算
  → 許容色範囲内かつ連続している領域をマーク
  → マーク済みピクセルをアルファ0に
  → 処理前にオーバーレイカラー（赤・緑など）でプレビュー表示
```

**色差計算:**
- RGB空間での距離: `sqrt((ΔR)² + (ΔG)² + (ΔB)²)`
- より精度を上げたい場合はLab色空間でのΔE（v2で検討）

**パラメータ:**
- 許容範囲: スライダーで 0〜100 に正規化（内部的には色差距離にマッピング）
- 探索方向: 4方向（デフォルト）/ 8方向（設定で切り替え）
- プレビューオーバーレイカラー: 赤（デフォルト）、変更可

**パフォーマンス:**
- BFSはバックグラウンドスレッド（`Task.detached`）で実行
- 許容範囲スライダー変更時はデバウンスを挟んでリアルタイムプレビュー更新

---

### 5. トリミング

- `NSBezierPath` で矩形選択
- 選択後に`CGImage.cropping(to:)` で切り出し
- アスペクト比ロック（Shiftキー押しながら）
- PDFの場合はページ単位でトリミング

---

### 6. PDF処理

#### 読み込み
- `PDFKit.PDFDocument` でページ読み込み
- 各ページを `PDFPage.thumbnail(of:for:)` でキャンバスにレンダリング
- ページサムネイルを下部パネルに一覧表示

#### モザイク済みPDFの保存（選択的Redaction）

```
編集済みページの処理:
  ├── モザイク・ぼかし範囲のみテキストオブジェクトを削除
  │     → PDFページのコンテンツストリームを直接操作
  │     → 該当矩形に重なるテキストグリフを消去
  ├── その矩形領域に処理済み画像を上書き合成
  └── 他の範囲のテキストデータはそのまま保持

未編集ページ:
  └── 元データをそのまま保持（テキスト検索可能）
```

**実装:** `PDFKit` + `CoreGraphics` でコンテンツストリームを操作。完全なRedactionにより、モザイク下のテキストは復元不可能になる。

---

### 7. Undo / Redo

- **無制限**（メモリの許す限り）
- 各操作の前後の `CGImage` スナップショットをスタックで管理
- 大きい画像はメモリ圧迫を防ぐため `NSCache` でLRU管理
- `⌘Z` / `⌘⇧Z` で操作

---

### 8. 保存・書き出し

- **上書き保存** `⌘S`: 元ファイルに上書き
- **別名保存** `⌘⇧S`: 形式・ファイル名を選んで保存
- **書き出しオプション**: JPEG品質スライダー・PNG圧縮レベル

---

## 技術スタック

| カテゴリ | 採用技術 | 理由 |
|---------|---------|------|
| UIフレームワーク | AppKit | カスタムキャンバスの制御精度 |
| 画像処理 | Core Image + Metal | GPU実行・高速 |
| PDF処理 | PDFKit + CoreGraphics | Apple標準・信頼性高い |
| 背景透明化 | 自前BFS（Swift） | 完全ローカル・軽量 |
| グローバルショートカット | CGEventTap | macOS標準の低レベルAPI |
| 設定保存 | UserDefaults | シンプルなKV保存 |
| ビルド | Swift Package Manager | Xcodeプロジェクト不要で管理しやすい |
| 最低動作OS | macOS 13 Ventura | API安定性・Vision対応 |

---

## ロードマップ

### v1.0（MVP）
- [ ] グローバルショートカットでクリップボード・Finderファイルを開く
- [ ] クラシックモザイク・Gaussianブラー（ストローク・範囲）
- [ ] フロストガラス・カラー塗りつぶし
- [ ] トリミング
- [ ] 背景透明化（フラッドフィル・プレビュー付き）
- [ ] PDF対応（選択的Redaction）
- [ ] 無制限Undo/Redo
- [ ] 別ウィンドウでの複数ファイル対応
- [ ] ショートカットカスタマイズ

### v1.x（安定化・UX改善）
- [ ] ダークモード最適化
- [ ] パフォーマンスチューニング（大きなPDF）
- [ ] キーボードショートカット一覧表示
- [ ] ドラッグ＆ドロップでファイルを開く

### v2.0（エフェクト拡張）
- [ ] クリスタル（結晶化）
- [ ] ピクセルアート風
- [ ] ディストーション（渦）
- [ ] ハーフトーン
- [ ] 8方向フラッドフィル

### v2.x（高度な機能）
- [ ] 油絵風エフェクト（Kuwahara Filter）
- [ ] Lab色空間によるより精度の高い背景透明化
- [ ] 複数範囲の一括処理
- [ ] CLIモード（`kasumi input.pdf --mosaic 100,200,300,400`）

---

## 開発環境セットアップ

### 必要な環境
- macOS 13 Ventura以上
- Xcode 15.0以上
- Swift 5.9以上

### ビルド手順

1. リポジトリをクローン
```bash
git clone https://github.com/yourusername/Kasumi.git
cd Kasumi
```

2. Xcodeでプロジェクトを開く
```bash
open Kasumi.xcodeproj
# または
xed .
```

3. ビルドして実行
- `⌘ + R` でビルド・実行
- または、ターミナルから: `swift build`

### 🎨 SwiftUIプレビューの使用

**開発効率を上げるため、SwiftUIプレビューを活用できます！**

#### 利用可能なプレビュー

| ファイル | プレビュー内容 |
|---------|-------------|
| `ContentView.swift` | メインウィンドウ、エディタビュー |
| `SettingsView.swift` | 設定画面（General, Shortcuts, About） |
| `EditorPreviews.swift` | ツールバー、キャンバス、フルエディタ、ツール状態、エフェクト種類 |

#### プレビューの開き方

1. Xcodeでファイルを開く（例: `ContentView.swift`）
2. 右側のプレビューパネルを開く:
   - メニュー: **Editor > Canvas** または
   - ショートカット: `⌥ + ⌘ + Enter`
3. ファイル内の `#Preview` マクロが自動的に検出される
4. 複数のプレビューがある場合は、下部のタブで切り替え

#### プレビュー例

```swift
// ContentView.swift
#Preview("Main Window") {
    ContentView()
}

#Preview("Editor View - With Sample Image") {
    EditorView(document: sampleDocument)
}

// EditorPreviews.swift
#Preview("Toolbar") {
    ToolbarPreview()
}

#Preview("Canvas with Sample Image") {
    CanvasPreview()
}

#Preview("Full Editor") {
    FullEditorPreview()
}
```

#### プレビューのメリット

- ✅ **高速な反復開発**: ビルドせずにUIの変更を即座に確認
- ✅ **複数の状態を同時表示**: 異なるツール状態を並べて比較
- ✅ **サンプルデータで開発**: 実際の画像なしでレイアウトを調整
- ✅ **ライブプレビュー**: コード変更がリアルタイムで反映

### プロジェクト構造

```
Kasumi/
├── KasumiApp.swift           # SwiftUIアプリのエントリーポイント
├── AppDelegateSwiftUI.swift  # グローバルショートカット管理
├── ContentView.swift          # メインウィンドウ（プレビュー可能✨）
├── SettingsView.swift         # 設定画面（プレビュー可能✨）
├── EditorPreviews.swift       # エディタ関連プレビュー（プレビュー可能✨）
│
├── Core Components/
│   ├── KasumiDocument.swift     # ドキュメントモデル
│   ├── EditHistory.swift        # Undo/Redo管理
│   ├── ImageProcessing.swift    # 画像処理（モザイク・トリミング等）
│   └── Exporters.swift          # ファイル書き出し
│
├── UI Components (AppKit)/
│   ├── EditorUI.swift           # エディタ、キャンバス、ツールバー
│   ├── SettingsViewController.swift  # AppKit版設定画面
│   └── GlobalShortcutMonitor.swift   # ショートカット監視
│
└── Resources/
    ├── Assets.xcassets
    └── Info.plist
```

### アーキテクチャ

**ハイブリッドアプローチ（SwiftUI + AppKit）**

- **SwiftUI**: メインウィンドウ、設定画面、プレビュー
- **AppKit**: 高度な画像編集UI（キャンバス、ツールバー）
- **ブリッジ**: `NSViewControllerRepresentable` でAppKitビューをSwiftUIに統合

このアプローチにより：
- 📱 SwiftUIの高速プレビューを活用
- 🎨 AppKitの精密なカスタムビュー制御
- 🔄 両方の利点を組み合わせた開発体験

### 開発ツール
- エディタ: **Xcode**（メイン）
- AIアシスト: **Claude Code**
- ビルド・署名・配布: Xcode
- **プレビュー**: SwiftUI Canvas （毎回ビルド不要！）

---

## セキュリティ・プライバシー方針

- ネットワーク通信: **一切なし**（App Sandboxで外向き通信を無効化）
- ファイルアクセス: ユーザーが明示的に開いたファイルのみ
- クリップボード: ショートカット起動時のみ読み取り
- テレメトリ・クラッシュレポート: **なし**
- 透明化処理したPDFのテキスト: **コンテンツストリームから完全削除**、復元不可

---

*Last updated: 2026-03-25*
