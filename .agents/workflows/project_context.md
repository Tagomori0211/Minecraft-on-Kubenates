---
description: プロジェクト進捗管理
---

# Minecraft Hybrid Cloud Infrastructure (Minecraft_java_k3s)

## 概要
本プロジェクトは、GCP (GKE Standard) とオンプレミス (k3s) をTailscale VPNで接続して構築された、Minecraft (Java版 / Bedrock版) のハイブリッドクラウド構成のリポジトリです。
フロントエンドのトラフィックルーティングや死活監視をGCPで受け持ち、負荷の大きいバックエンドゲームサーバー群を自宅のオンプレミス環境に配置する構成をとっています。

## アーキテクチャ構成
### 1. GCP / GKE Standard (フロントエンド・プロキシ)
- **ノード仕様:** `e2-small` (2 vCPU / 2GB RAM) シングルノード。
- **ゲームプロキシ層:** 
  - `nginx-gw`: ロードバランサー。Java版(TCP 25565)を後段のVelocityにプロキシし、Bedrock版(UDP 19132)は`socat`でTailscale経由でオンプレへ転送。
  - `Velocity`: Java版プロキシ。
- **現状の課題:** GKEノード(`e2-small`)のCPUリソースが枯渇しており（予約済み 99%）、`nginx-gw` および `velocity` が **Pending (Insufficient cpu)** 状態になっています。

### 2. オンプレミス / k3s (バックエンド・データベース)
- **スペック:** Ryzen 5700G / 64GBメモリ。`k3s-worker` (control-plane) と `k3s-monitoring` (monitoring) の2ノード構成。
- **ゲームバックエンド (正常稼働中):**
  - `Lobby` (8Gi): プレイヤーの初回接続先。
  - `Survival` (16Gi) / `Industry` (30Gi): メインサーバー群。
  - `Bedrock (BDS)` (8Gi): Bedrock版専用サーバー(hostPort 19132)。
- **Status Platform (未デプロイ):**
  - `Flutter Web`, `Envoy`, `Kotlin API` の構成ですが、現在k3sクラスタ上に `status` ネームスペースは存在せず、未デプロイ状態です。

## ネットワーク・監視
- **Tailscale:** GKEノードとオンプレノード間を接続。GKE側はDaemonSet/Sidecarで構成、オンプレ側はSubnet Routerが稼働。
- **監視:** `monitoring-prometheus` ネームスペースにて Grafana / Prometheus が稼働中。

## 直近のタスク
1. **GKEのリソース調整:** `e2-small` ノードでのリソース予約競合の解消、またはノードタイプのアップグレード。
2. **Status Platformのデプロイ:** `k8s/onprem/appserver.yaml` の適用とイメージのビルド。
3. **Bedrock版アドオンの整理:** `MC_addon-raw` 内の「Health and Damage Indicator」の適用確認。

## k8s 運用ルール
- **Namespace:** 環境別プレフィックス（`prod-`, `dev-`, `monitoring-`）を付与。
- **命名:** kebab-case。`<service>-<role>` 形式。
- **必須Labels:** `app.kubernetes.io/name`, `component`, `managed-by`, `env`。
- **PVC/CM/Secret:** `<service>-<用途>-pvc/cm/secret` 形式。
