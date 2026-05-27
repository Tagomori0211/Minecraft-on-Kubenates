---
description: シェルコマンド安全実行ワークフロー（2026-05-27 追加）
trigger_doc: .clinerules "シェルコマンド安全実行ルール"
---

# CLI Safety — シェルコマンド安全実行ガイド

## 目的

誤ったファイル検索や長時間コマンドにより CLI が応答不能になるインシデント（2026-05-27 発生）を再発防止するため、シェルコマンド実行時の安全ルールを定める。

## インシデントサマリー

- **発生日時**: 2026-05-27 13:30 頃
- **原因**: プロジェクトルートで `grep -rl` を `--exclude-dir=.git` なしで実行
  - `.git/objects/` 以下の大量の圧縮オブジェクトがスキャン対象に含まれ長時間化
  - パイプ `| grep -v ".git/"` の前段が完了せず、後段に出力が渡らず応答不能に
- **対策**: `.clinerules` に本ルールを追加、本ワークフローを整備

## ファイル検索の優先順位

| 優先度 | 手段 | 特徴 |
|--------|------|------|
| **1** | `search_files` ツール | Rust regex、高速、`.git` 自動除外、context-rich |
| **2** | `list_files` ツール | ディレクトリ構造確認、再帰リスト |
| **3** | シェル `find` / `grep` | 上記で不十分な場合のみ使用 |

## シェル grep / find 使用時の必須ルール

### `grep -rl` の安全な使用法

```bash
# ✅ 正しい: --exclude-dir=.git を必ず付与
grep -rl "playersync" . --include="*.yaml" --exclude-dir=.git
grep -rn "TODO" Documents/ --include="*.md" --exclude-dir=.git

# ❌ 禁止: --exclude-dir=.git なし
grep -rl "playersync" . --include="*.yaml"
grep -rl "pattern" .
```

### パイプチェーンの制限

```bash
# ✅ 正しい: 単一コマンドで完結
grep -rl "playersync" . --include="*.yaml" --exclude-dir=.git --exclude-dir=Task_mds

# ❌ 禁止: 長時間 grep の後続パイプ
grep -rl "pattern" . --include="*.yaml" | grep -v ".git/"
grep -rl "pattern" . | xargs grep "another"
```

### `find` の安全な使用法

```bash
# ✅ 正しい: -path で .git を除外
find . -path ./.git -prune -o -name "*.yaml" -print

# ❌ 禁止: .git 除外なしの再帰 find
find . -name "*.yaml"
```

## システム変更コマンドの必須フラグ

`require_approval: true` を必ず指定:

- `apt install`, `apt remove`, `apt upgrade`
- `pip install`, `pip uninstall`
- `npm install -g`
- `systemctl stop/start/restart`（サービス停止を伴う場合）
- `rm -rf /...`（システムディレクトリ操作）
- `mkfs`, `mount`, `umount`

## 長時間が予想されるコマンドの事前チェックリスト

`execute_command` 前に以下を評価:

1. スキャン範囲は広大か？（`find /`, `grep -r /` など）
2. ファイル数は膨大か？（node_modules、.git、キャッシュディレクトリを含むか）
3. `search_files` ツールで代替できないか？

いずれかに該当する場合、`search_files` ツールを使用する。

## トラブルシューティング

### コマンドが応答しない場合

1. Ctrl+C で中断（ツール経由の場合は自動タイムアウトを待つ）
2. `search_files` ツールで同様の検索を試行
3. どうしてもシェル grep が必要な場合は、対象ディレクトリを明示的に絞る

### すでに長時間実行中の grep がある場合

```bash
# grep プロセスの確認
ps aux | grep "grep -r"

# 強制終了
kill -9 <PID>
```

## 関連リソース

- `.clinerules` — 「シェルコマンド安全実行ルール」セクション
- `.agents/workflows/k3s-ssh-operations.md` — SSH 経由コマンド実行の安全ルール
- `Documents/OperationPostmortem/` — インシデントポストモーテム