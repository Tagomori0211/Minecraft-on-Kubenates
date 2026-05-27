<!-- ⚠️ このファイルは .clinerules の補完です。全絶対ルールは .clinerules を参照してください -->

# 開発環境

## システム
- OS: Ubuntu 22.04.5 LTS (Linux 5.15.0, x86_64)
- Shell: bash

## インストール済みランタイム

| ツール | バージョン |
|--------|-----------|
| Python | 3.10.12 (`/usr/bin/python3`) |
| Node.js | v20.20.0 (nvm 管理) |
| npm | 10.8.2 |
| Docker | 29.2.1 |
| git | 2.34.1 |
| kubectl | クライアントのみ（クラスタ操作は SSH 経由） |
| helm | クライアントのみ |
| gcloud | クライアントのみ |

---

# プロジェクト概要

Minecraft ハイブリッドクラウドインフラの構成管理リポジトリ。
詳細は `session-context.md`（.gitignore 対象）および `.agents/workflows/project_context.md` を参照。

## 主要ディレクトリ

| ディレクトリ | 用途 |
|-------------|------|
| `.clinerules` | **メインルールファイル**（絶対ルール・運用ルールすべて） |
| `.agents/` | エージェント細則（rules/）・ワークフロー手順（workflows/） |
| `k8s/onprem/` | k3s クラスタ用 Kubernetes マニフェスト・Helm charts |
| `gce/` | GCE `mc-proxy-1` の Docker Compose・cloud-init・systemd |
| `Terraform/` | GCP・Proxmox リソースの IaC 定義 |
| `mods/` | カスタム NeoForge MOD（Velocity Portals） |
| `Documents/` | アーキテクチャ図・ポストモーテム・README |
| `Grafana/` | ダッシュボード JSON |

---

# 言語別コーディング規約

（`.clinerules`「コード変更時のルール」に加えて）

## Python
- フォーマッタ: `black`
- linter: `flake8` or `ruff`
- 型ヒントを積極的に使用
- 仮想環境: `venv`（`.venv/` ディレクトリ）

## JavaScript / TypeScript
- パッケージマネージャ: `npm`
- フォーマッタ: `prettier`
- linter: `eslint`
- TypeScript を優先

## Kubernetes マニフェスト
- `.clinerules`「k8s Naming Convention」に従う
- YAML はスペース 2 インデント

---

# よく使うコマンド

詳細は `session-context.md` 参照。主なもの:

```bash
# k3s Pod 状態確認
ssh k3s-worker 'sudo kubectl get pods -n minecraft'

# GCE VM へ IAP SSH
ssh k3s-worker 'gcloud compute ssh mc-proxy-1 --zone=asia-northeast1-b --tunnel-through-iap'

# Terraform
cd Terraform && terraform plan -var-file=secret.tfvars

# Git 作業完了時（.clinerules 第3条参照: 必ず3段階で実行）
git add -A
git commit -m "feat(scope): description..."
git push