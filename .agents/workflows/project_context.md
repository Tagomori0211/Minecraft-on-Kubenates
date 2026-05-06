---
description: プロジェクト進捗管理
---

# Minecraft Hybrid Cloud Infrastructure (Minecraft_java_k3s)

## 概要

本プロジェクトは、GCP (GCE) とオンプレミス (k3s) を Tailscale VPN で接続して構築された、Minecraft (Java版 / Bedrock版) のハイブリッドクラウド構成のリポジトリです。
2026-05-03 に GKE → GCE 移行を完了し、月額 ¥19,700 → ¥3,680（81% 削減）を達成済み。

## アーキテクチャ構成

### 1. GCP / GCE (フロントエンド・プロキシ)

**VM仕様:** `mc-proxy-1` (e2-medium / 4GB RAM, pd-balanced 20GB, asia-northeast1-b)
**静的IP:** `35.200.78.252`

**Docker Compose コンポーネント (host network):**
- `nginx-stream`: Java TCP 25565 を受け、localhost:25577 (Velocity) にプロキシ
- `velocity`: Java Edition プロキシ (Velocity 3.4.0-SNAPSHOT)
- `socat-bedrock`: Bedrock UDP 19132 を fork 透過転送（RakNet 互換）

**tailscaled:** systemd (kernel mode) で動作。`gce-mc-proxy: 100.124.222.31`

**管理アクセス:** IAP SSH `gcloud compute ssh mc-proxy-1 --zone=asia-northeast1-b --tunnel-through-iap`

### 2. オンプレミス / k3s (バックエンド)

**スペック:** Ryzen 5700G / 64GB メモリ。`k3s-worker` (100.107.122.45) と `k3s-monitoring` (Xeon E5) の2ノード構成。

**ゲームバックエンド (minecraft namespace, 正常稼働中):**
- `Lobby` (8Gi, NodePort :30067): プレイヤーの初回接続先 — Helm 管理
- `Survival` (16Gi, NodePort :30065): Paper バニラサバイバル — Helm 管理
- `Industry` (30Gi, NodePort :30066): NeoForge 工業 MOD — Helm 管理
- `Bedrock BDS` (8Gi, hostPort :19132): Bedrock Edition 専用 — Deployment 管理

**自動バックアップ:**
- `bedrock-backup-cronjob`: 毎日 04:00 JST に MinIO へ tar.gz を自動アップロード

**Tailscale Subnet Router:** k3s Service CIDR `10.43.0.0/16` を Tailscale に広告

**Status Platform (未デプロイ):**
- Flutter Web + Envoy + Kotlin API + CF Tunnel の構想のみ。k3s クラスター上に未適用

### 3. 監視 (k3s-monitoring, Xeon E5, 100.105.190.5)

- `monitoring-prometheus` namespace で Grafana / Prometheus が稼働中
- mc-monitor サイドカー（各 Minecraft Pod の :8080/metrics）からメトリクス収集

## 接続フロー

```
Java:    Player → 35.200.78.252:25565/TCP
         → nginx-stream → Velocity (:25577)
         → Tailscale → k3s NodePort (:30065-30067)

Bedrock: Player → 35.200.78.252:19132/UDP
         → socat fork透過 → Tailscale → BDS hostPort (:19132)
```

## Tailscale ネットワーク

```
100.124.222.31  gce-mc-proxy      ← GCE VM
100.107.122.45  k3s-worker-1      ← バックエンド
100.105.190.5   k3s-monitoring-1  ← 監視ノード
```

## 既知の問題・制約

### Bedrock プロキシ禁止事項（ポストモーテム実証済み）
- **L7プロキシ禁止**: XUID 消失・パケット喪失が発生する（bedrock-protocol ライブラリ等）
- **Nginx Stream UDP 禁止**: ソースポート書き換えで RakNet セッションが破綻する
- → **socat fork透過 + hostPort** が唯一の正解

### Nasu Golem VV 問題（暫定対応中）
- BDS 経由でサーバー側 world_resource_packs.json に登録すると Vibrant Visuals がグレーアウト
- 暫定: world_resource_packs.json = [] でサーバー側から除外、クライアント側グローバルリソース配布

### Proxmox tags（ignore_changes で抑制済み）
- 両 Proxmox VM の state に `tags = " "`（空白）が残存
- terraform plan は No changes。apply が必要な場合は Proxmox GUI でタグを手動削除してから実施

## 直近のタスク（ロードマップ）

1. **Phase 2 バックアップ**: MinIO CronJob 完了済み。rclone + GCS 外部バックアップは未着手
2. **Phase 3 Status Platform**: Kotlin API + Flutter Web + Envoy + CF Tunnel — 未着手

## k8s 運用ルール

- **Namespace:** 環境別プレフィックス（`prod-`, `dev-`, `monitoring-`）を付与が理想だが、現在稼働中クラスターは `minecraft` namespace を使用中
- **命名:** kebab-case。`<service>-<role>` 形式
- **必須Labels:** `app.kubernetes.io/name`, `component`, `managed-by`, `env`
- **PVC/CM/Secret:** `<service>-<用途>-pvc/cm/secret` 形式
- **BDS 再起動:** replicas=0 → replicas=1 の順。`rollout restart` 禁止（旧 Pod と新 Pod 並走のリスク）
