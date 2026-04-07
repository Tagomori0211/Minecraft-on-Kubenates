# Project Context: Minecraft Java/Bedrock Multi-Cloud Infrastructure

## 概要
本プロジェクトは、GKE (GCP) とオンプレミス (k3s) を Tailscale VPN で接続したハイブリッド・マルチクラウド環境で Minecraft サーバー（Java版/Bedrock版）を運用するものです。

## インフラ構成
### 1. 監視ノード (オンプレミス)
- **Node Name**: `k3s-monitoring` (Proxmox VM ID: 100)
- **IP**: `192.168.0.101` / **Tailscale IP**: `100.94.84.51`
- **役割**: 監視専用ワークロード (Prometheus, Grafana) のホスト
- **ストレージ**: `local-path` プロビジョナによる 50GB ディスク（拡張済み）

### 2. クラスター構成
- **制御ノード**: `ubuntu-151` (IP: `192.168.0.151`)
- **ワーカーノード**: 
    - `k3s-worker` (メインゲームサーバー)
    - `k3s-monitoring` (監視専用)

## 監視スタック (monitoring-prometheus)
GKE からオンプレミスへ移行完了。

- **Prometheus**:
    - URL: [http://100.94.84.51:30090](http://100.94.84.51:30090)
    - ストレージ: 20GB PVC (`prometheus-storage-pvc`)
    - 収集対象: GKE (Velocity, Lobby), オンプレミス (Survival, Mod, Bedrock, Kotlin API)
- **Grafana**:
    - URL: [http://100.94.84.51:30300](http://100.94.84.51:30300)
    - 初期パスワード: `admin`

## ネーミング規約 (Naming Convention)
- **Namespace**: `prod-`, `dev-`, `monitoring-` プレフィックス必須
- **リソース**: kebab-case (`<service>-<role>`)
- **ラベル**: 必須セット (`app.kubernetes.io/name`, `component`, `managed-by`, `env`)

## ネットワーク
- **Tailscale**: GKE とオンプレミス間のセキュア通信。
- **NodePort**: 外部アクセス（30000-32767）。9000, 9001 は予約済みのた​​め回避。
