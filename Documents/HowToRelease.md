# リリース手順

Kasumi の新バージョンをリリースする手順です。

## 前提条件

- `main` ブランチへの直接 push は禁止されています
- すべての変更は PR（Pull Request）を経由して `main` ブランチにマージする必要があります
- GitHub Actions によりタグ push 時に自動ビルド・リリースが実行されます

## 手順

### 1. 開発ブランチで作業

```bash
git checkout -b feature/your-feature-name
# 変更を加える
git add .
git commit -m "変更内容の説明"
git push -u origin feature/your-feature-name
```

### 2. Pull Request を作成・マージ

1. GitHub 上で `main` ブランチへの PR を作成
2. コードレビュー後、PR をマージ

### 3. バージョンタグを付与

PR がマージされたら、GitHub 上でタグを作成します。

**方法A: GitHub Web UI（推奨）**

1. GitHub リポジトリの [Releases ページ](../../releases) を開く
2. 「Draft a new release」をクリック
3. 「Choose a tag」で新しいタグ名を入力（例: `v1.0.0`）→ 「Create new tag: v1.0.0 on publish」を選択
4. Target は `main` ブランチを指定
5. 「Publish release」をクリック

**方法B: ローカルから**

```bash
git checkout main
git pull origin main
git tag v1.0.0
git push origin v1.0.0
```

> **注意:** ブランチ保護ルールは `main` ブランチへの直接コミットの push を禁止しますが、タグの push は別の操作であり制限されません。ただしリポジトリにタグ保護ルールが設定されている場合は、方法A を使用してください。

タグ名は `v` で始める必要があります（例: `v1.0.0`, `v1.1.0`, `v2.0.0-beta`）。

### 4. 自動リリース

タグを push すると、GitHub Actions（`.github/workflows/release.yml`）が自動で以下を実行します：

1. macOS 15 + Xcode 16 環境でビルド
2. `Kasumi.app` を DMG ファイルにパッケージ（Applications フォルダへのシンボリックリンク付き）
3. GitHub Releases にリリースを作成し、`Kasumi.dmg` をアップロード
4. コミット履歴からリリースノートを自動生成

### 5. リリースの確認

- [Releases ページ](../../releases) でリリースが正しく作成されたか確認
- `Kasumi.dmg` がダウンロード可能か確認
- DMG を開いて `Kasumi.app` が正しく含まれているか確認
- Actions タブでビルドログにエラーがないか確認

## バージョニング規則

[セマンティックバージョニング](https://semver.org/lang/ja/) に従います：

| 変更内容 | バージョン例 |
|----------|-------------|
| バグ修正 | v1.0.0 → v1.0.1 |
| 新機能追加（後方互換あり） | v1.0.0 → v1.1.0 |
| 破壊的変更 | v1.0.0 → v2.0.0 |

## トラブルシューティング

### ビルドが失敗する場合

- Actions タブでエラーログを確認
- Xcode のバージョン要件（Xcode 16）を満たしているか確認
- ローカルで `xcodebuild -scheme Kasumi -configuration Release` が成功するか確認

### リリースが作成されない場合

- タグ名が `v` で始まっているか確認（`v*` パターンにマッチする必要あり）
- リポジトリの Settings > Actions > General で GitHub Actions が有効になっているか確認
- ワークフローに `contents: write` 権限があるか確認（`.github/workflows/release.yml` で設定済み）
