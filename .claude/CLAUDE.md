# 絶対堅守条件（最優先）

1. **全出力は日本語**：会話・Task・WalkThrough・Plan等すべて日本語。英語ソースは翻訳して提示。
2. **JST時刻の明記**：毎回 `TZ='Asia/Tokyo' date` を実行し、回答冒頭に `JST:yyyy/mm/dd hh:mm`（24h表記）で記載。
3. **コマンドは逐次実行**：`&&` による複数コマンド連結禁止。トラブルシュート容易性を確保。
4. **各作業終了後は commit + push**：リモートを常に最新に保つ。
5. **コミットメッセージは英語で詳細に**：
    ```text
    feat(scope): Description

        - Detail 1
        - Detail 2
    ```

---

# 開発環境

## システム
- OS: Ubuntu 22.04.5 LTS (Linux 5.15.0, x86_64)
- Shell: bash

## インストール済みランタイム
| ツール | バージョン |
|--------|-----------|
| Python | 3.10.12 (`/usr/bin/python3`) |
| Node.js | v20.20.0 (nvm管理) |
| npm | 10.8.2 |
| Docker | 29.2.1 |
| git | 2.34.1 |

---

# コーディング規約

## 共通
- **コード内コメントは日本語**で書く。ただし技術用語はそのまま。
- 関数・変数名は英語（スネークケースまたはキャメルケース、プロジェクトに合わせる）。
- 変数名・関数名は役割が明確に伝わる説明的な命名。
- 深いネスト回避 → 早期リターン（Guard Clauses）活用。
- 重要セクションは強調表示。
- 不要なデバッグ用 `print` / `console.log` は残さない。

## Kubernetes (Naming Convention)
- **Namespace**: 環境別プレフィックス（`prod-`, `dev-`, `monitoring-`）を付与。`default` は使用禁止。
- **リソース命名**: すべて kebab-case。`<service>-<role>` 形式。
- **必須Labels**: `app.kubernetes.io/name`, `app.kubernetes.io/component`, `app.kubernetes.io/managed-by`, `env`
- **PVC/CM/Secret**: `<service>-<用途>-pvc` / `<service>-<内容>-cm` / `<service>-<内容>-secret`

## Python
- フォーマッタ: `black`
- linter: `flake8` or `ruff`
- 型ヒントを積極的に使用。
- 仮想環境: `venv` (`.venv/` ディレクトリ)

## JavaScript / TypeScript
- パッケージマネージャ: `npm`
- フォーマッタ: `prettier`
- linter: `eslint`
- TypeScript を優先。

---

# よく使うコマンド

## Git (作業完了時)
```bash
git add .
git commit -m "feat(scope): description..."
git push
```

## Python
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python3 -m pytest
```

## Node.js
```bash
npm install
npm run dev
npm run build
npm test
```

---

# Claudeへの作業指針

## コード変更時
- 変更前に必ずファイルを Read で読む。
- 既存のスタイル・命名規則（k8s naming等）に合わせる。
- 求められた範囲を超えた変更は行わない。

## ファイル操作
- 新規ファイルは必要な場合のみ作成。
- ドキュメント（README.md 等）はユーザーが明示的に要求した場合のみ。

## セキュリティ
- SQLインジェクション・XSS・コマンドインジェクション等の脆弱性を混入しない。
- 認証情報・シークレットをコードにハードコードしない（`.env` を使用）。
- `.env` ファイルは git に含めない。
