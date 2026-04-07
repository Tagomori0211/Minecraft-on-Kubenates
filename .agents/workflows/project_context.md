---
description: プロジェクト進捗管理
---

# Minecraft Hybrid Cloud Infrastructure (Minecraft_java_k3s)

## 概要
本プロジェクトは、GCP (GKE Autopilot) とオンプレミス (k3s) をTailscale VPNで接続して構築された、Minecraft (Java版 / Bedrock版) のハイブリッドクラウド構成のリポジトリです。
フロントエンドのトラフィックルーティングや死活監視をGCPで受け持ち、負荷の大きいバックエンドゲームサーバー群を自宅のオンプレミス環境に配置する構成をとっています。

## アーキテクチャ構成
### 1. GCP / GKE Autopilot (フロントエンド・プロキシ・監視・ロビー)
- **ゲームプロキシ層:** 
  - `nginx-gw`: ロードバランサーとして動作。Java版(TCP 25565)を後段のVelocityにプロキシし、Bedrock版(UDP 19132)は`socat`を用いて透過的にオンプレミス側のTailscale IP(`100.100.135.81`)へ転送します。
  - `Velocity`: Java版サーバー間のプロキシ・ルーティングを担当。
  - `Lobby`: Spot PodとしてGKE上で軽量に稼働し、ログイン時の待機場所となります。
- **監視層:** `Prometheus` と `Grafana`。
- **ネットワーク層:** VPC内に配置された`Subnet Router`が、GKEからTailscale VPN(100.x.x.x)へのトラフィックをルーティングします。

### 2. オンプレミス / k3s (バックエンド・データベース)
- **スペック:** Ryzen 5700G / 64GBメモリ (k3s-worker VM 58Gi)。Tailscale Clientを実行してGCPとVPN経由で接続されています。
- **ゲームバックエンド:**
  - `Java_Survival`, `Java_Industry`: Helm等を用いてデプロイされた比較的リソースを消費するメインサーバー群。
  - `Bedrock (BDS)`: Bedrock版用の専用サーバー(hostPort 19132で稼働)。GKE側のsocatから透過的にトラフィックを受けます。
- **Status Platform (状態確認基盤):**
  - Cloudflare Tunnelを経由し、外部にHTTPSでステータスを提供します。
  - `Flutter Web` (フロント), `Envoy`, `Kotlin API (Ktor + gRPC)` の構成です。

## ディレクトリ構成
- `k8s/gke/`: GKE Autopilot向けのKubernetesマニフェスト群。(Nginx, Velocity, Lobby, 監視系など)
- `k8s/onprem/`: オンプレミス（k3s）向けのマニフェストとHelmチャート群。(ゲームバックエンド, BDSなど)
- `Documents/`: `infrastructure.mermaid` などの設計図、および障害対応記録(`OperationPostmortem/`)などのドキュメント類。
- `Ansible/` / `Terraform/`: インフラストラクチャおよびノード構成のプロビジョニング自動化に関連する設定。
- `bedrock-relay/`: Bedrock版固有の連携や中継に関連するシステムコンポーネント。

## k8s 開発・運用におけるルール (Naming Convention)
- **Namespace:** 必ず環境別プレフィックス（`prod-`, `dev-`, `monitoring-`）を付与する。`default`への直デプロイは禁止。
- **リソース命名規則:** すべてkebab-case。`<service>-<role>` の形式（例: `minecraft-java`, `velocity-proxy`）。
- **必須Labels:** 全リソースに以下のラベルを付与すること。（Prometheusのサービスディスカバリ等で必須）
  - `app.kubernetes.io/name`
  - `app.kubernetes.io/component`
  - `app.kubernetes.io/managed-by`
  - `env`
- **PVC/ConfigMap/Secret:** `<service>-<用途>-pvc` / `<service>-<内容>-cm` / `<service>-<内容>-secret` の形式。

## 特記事項
- ルーティングやプロキシ関連の変更を行う際は、Java版/Bedrock版のトラフィック経路の違い(L7 TCPリバースプロキシ vs L4 UDP透過転送)に十分留意してください。
- 変更を行った後はリモートにすぐに同期するため、こまめにcommit/pushしてください。
- リモートへ同期したのちproject_context.md自体を改稿して常に最新状況にして。
