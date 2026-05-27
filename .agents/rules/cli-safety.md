---
trigger: always_on
description: シェルコマンド安全実行ルール（2026-05-27 追加）
trigger_doc: .clinerules "シェルコマンド安全実行ルール"
---

# 🔒 シェルコマンド安全実行ルール

## grep / find の制限（最重要）

- **`search_files` ツール（Rust regex、`.git` 自動除外）を最優先で使用する**
- シェル `grep -rl` を使う場合は **必ず `--exclude-dir=.git` を付与**:
  ```bash
  # ✅ 正しい
  grep -rl "pattern" . --include="*.yaml" --exclude-dir=.git

  # ❌ 禁止（.git/objects をスキャンし長時間応答不能になる）
  grep -rl "pattern" . --include="*.yaml"
  ```
- パイプチェーン（`grep ... | grep -v ...`）は前段が完了するまで出力されないため、グロブ検索では**使用禁止**
- `find` も必ず `-path ./.git -prune -o` で `.git` を除外

## ファイル検索の優先順位

1. **`search_files` ツール** — Rust regex、高速、`.git` 自動除外
2. **`list_files` ツール** — ディレクトリ構造確認
3. **シェル `find` / `grep`** — 上記で不十分な場合のみ。`--exclude-dir=.git` 必須

## システム変更コマンド

- `apt install` / `apt remove` / `pip install` などは **`requires_approval: true`** 必須
- 詳細は `.agents/workflows/cli-safety.md` を参照