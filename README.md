# TAK Pipeline - Hybrid Cloud Minecraft Infrastructure

**ハイブリッドクラウド構成によるMinecraftサーバー基盤**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge&logo=open-source-initiative&logoColor=white)](LICENSE)
![Terraform](https://img.shields.io/badge/IaC-Terraform-%237B42BC.svg?style=for-the-badge&logo=terraform&logoColor=white)
![Ansible](https://img.shields.io/badge/Config-Ansible-%23EE0000.svg?style=for-the-badge&logo=ansible&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-k3s-%23326CE5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)
![Google Cloud](https://img.shields.io/badge/GoogleCloud-GCE%20%2B%20BigQuery-%234285F4.svg?style=for-the-badge&logo=google-cloud&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Compose-%232496ED.svg?style=for-the-badge&logo=docker&logoColor=white)
![Tailscale](https://img.shields.io/badge/Tailscale-VPN-%2354362B.svg?style=for-the-badge&logo=tailscale&logoColor=white)
![VictoriaMetrics](https://img.shields.io/badge/VictoriaMetrics-Monitoring-%23e6522c.svg?style=for-the-badge&logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-Dashboard-%23F46800.svg?style=for-the-badge&logo=grafana&logoColor=white)
![BigQuery](https://img.shields.io/badge/BigQuery-Analytics-%234285F4.svg?style=for-the-badge&logo=googlebigquery&logoColor=white)
![Hybrid Cloud](https://img.shields.io/badge/Hybrid%20Cloud-%23005571.svg?style=for-the-badge&logo=icloud&logoColor=white)
![Proxmox](https://img.shields.io/badge/Proxmox-%23E57024.svg?style=for-the-badge&logo=proxmox&logoColor=white)

---

## 📋 プロジェクト概要

本プロジェクトは、**オンプレミス（自宅サーバー）と Google Compute Engine を Tailscale VPN で接続**し、コスト効率と可用性を両立させた Minecraft サーバー基盤です。

Java版・Bedrock版の両対応に加え、**VictoriaMetrics + Grafana による可観測性**、**BigQuery によるコスト・運用メトリクス分析**、**Discord による通知統合** までを Infrastructure as Code（IaC）で完全管理しています。

> **History**: 2026/05/03 に GKE クラスターから GCE VM 構成へ移行（コスト削減）。2026/05/07-08 に監視スタックを k3s 内 Prometheus から GCE 専用 VM 上の VictoriaMetrics + Grafana に再構築。

### 🎯 設計思想

| 観点 | アプローチ |
|------|-----------|
| **コスト最適化** | エントリポイントのみ GCE / 重量級ワークロードはオンプレに集約 |
| **可用性** | クラウド側プロキシで世界中からの常時アクセスを保証 |
| **運用効率** | Terraform / Ansible / Kubernetes マニフェストで完全宣言的管理 |
| **セキュリティ** | Tailscale ゼロトラストネットワーク・公開ポートを最小化 |
| **可観測性** | vmagent → VictoriaMetrics → Grafana / BigQuery 二重配信 |
| **通知統合** | 課金アラート・バックアップ完了を Discord に集約 |

---

## 🏗️ アーキテクチャ

### ゲームトラフィック
![infrastructure](Documents/architecture/infrastructure.svg)

### 監視・通知系
![monitoring](Documents/architecture/monitoring.svg)

### k3s-worker メモリ配分
![pie](Documents/architecture/MenResource.svg)

---

## 🛠️ 技術スタック

### Infrastructure as Code

| ツール | バージョン | 用途 |
|--------|-----------|------|
| **Terraform** | >= 1.5.0 | GCE / VPC / IAM / BigQuery / Pub/Sub / Budget / Proxmox VM |
| **Ansible** | - | k3s + Tailscale インストール、Minecraft マニフェストデプロイ |
| **Kubernetes** | k3s v1.31 | オンプレ Minecraft サーバーのコンテナオーケストレーション |
| **Docker Compose** | - | GCE 上の Velocity / nginx-stream / VictoriaMetrics / Grafana |

### クラウド・インフラ

| サービス | 用途 |
|---------|------|
| **GCE: mc-proxy-1** (e2-medium) | Velocity + nginx-stream + socat-bedrock + systemd timer 群 |
| **GCE: mc-monitoring-1** (e2-small) | VictoriaMetrics + Grafana（Tailscale 経由のみアクセス可） |
| **BigQuery** | メトリクス時系列保存・課金 Export・コスト按分 VIEW |
| **Cloud Storage** (Coldline) | 月次ワールドバックアップ（lifecycle: 365日 ARCHIVE / 1095日削除） |
| **Pub/Sub** | 課金アラート用 pull subscription |
| **Cloud Billing Budget** | ¥8,000/月・90% / 100% しきい値 |
| **Secret Manager** | Tailscale auth-key / Discord Webhook URL / Player hash salt |
| **Proxmox VE** | オンプレミス仮想化基盤（Ryzen 5700G / 64GB） |
| **Tailscale** | メッシュVPN（ゼロトラスト） |

### アプリケーション

| コンポーネント | イメージ |
|---------------|---------|
| Velocity Proxy | `itzg/bungeecord` |
| nginx Stream | `nginx:alpine` |
| socat (Bedrock UDP) | `alpine/socat` |
| Lobby / Survival | `itzg/minecraft-server` (Paper) |
| Java-Industry MOD | `itzg/minecraft-server` (NeoForge) |
| Bedrock Server | `itzg/minecraft-bedrock-server` |
| Metrics Exporter | `itzg/mc-monitor` |
| VictoriaMetrics | `victoriametrics/victoria-metrics:v1.115.0` |
| vmagent | `victoriametrics/vmagent:v1.115.0` |
| Grafana | `grafana/grafana:11.6.1` |

---

## ⚙️ 主要な設計ポイント

### 1. クラウド・オンプレ責任分担

```text
[ Internet ]
    │
    │ 25565/TCP, 19132/UDP
    ▼
[ GCE: mc-proxy-1 ]  ← 静的IP 35.200.78.252、24/365 公開エンドポイント
    │  Docker Compose: nginx-stream + Velocity + socat-bedrock
    │
    │ Tailscale 暗号化トンネル ≈ 20ms direct
    ▼
[ オンプレ k3s-worker (Ryzen 5700G / 64GB) ]
    └─ Lobby / Survival / Industry MOD / Bedrock BDS（合計 62GB JVM ヒープ）
```

「公開・薄いプロキシ層」と「重量級ワークロード」を明確に分離。クラウド側は最小サイズの VM 1台に抑え、メモリ集約型のゲームサーバーをオンプレに寄せている。

### 2. Bedrock UDP の透過転送（socat）

```yaml
# gce/compose.yaml
socat-bedrock:
  image: alpine/socat:latest
  network_mode: host
  command:
    - "UDP4-LISTEN:19132,fork,reuseaddr"
    - "UDP4:100.107.122.45:19132"
```

Bedrock の RakNet は L7 プロキシで壊れるため、`fork` オプションでクライアント毎に独立 UDP ソケットを生成し Tailscale 経由で k3s `hostPort` まで一切改変せず透過転送。Java 側は `nginx-stream` の TCP プロキシ（25565 → 127.0.0.1:25577）で Velocity に渡している。

### 3. Tailscale ゼロトラストネットワーク

3 ノードのメッシュ構成:

| ホスト名 | Tailscale IP | 役割 |
|---|---|---|
| `gce-mc-proxy` | 100.124.222.31 | エッジプロキシ（公開エンドポイント） |
| `gce-mc-monitoring` | 100.121.113.37 | VictoriaMetrics / Grafana |
| `k3s-worker` | 100.107.122.45 | ゲームサーバー Pod |

GCE 側は `tailscaled` を host systemd（kernel mode）で起動。auth key は Secret Manager から `cloud-init` 起動時に取得。Grafana は `0.0.0.0:3000` でリッスンするが GCE ファイアウォールで未開放のため、Tailscale ピアからのみ到達可能。

### 4. 監視スタック (VictoriaMetrics + Grafana)

```text
[ k3s vmagent ]
    │ scrape 15s (Minecraft / k8s nodes / cAdvisor)
    │ remote_write via Tailscale
    ▼
[ GCE mc-monitoring-1 ]
    ├── VictoriaMetrics :8428 （保持 90日 / -memory.allowedPercent=40）
    └── Grafana :3000 （Tailscale 経由のみ・provisioning でデータソース・ダッシュボード自動投入）
```

- `gce/monitoring/compose.yaml`: VictoriaMetrics + Grafana を Docker Compose で起動
- `gce/monitoring/dashboards/minecraft-java-overview.json`: Java 各ワールドの稼働状態・プレイヤー数・応答時間・Pod リソース可視化
- `k8s/onprem/30-victoria-metrics.yaml`: vmagent + RBAC（ClusterRole で nodes/cAdvisor scrape 権限）

### 5. BigQuery メトリクス収集

mc-proxy-1 上の **systemd timer**（15 分間隔）が VictoriaMetrics へクエリを投げ、結果を BigQuery にストリーミング INSERT する。

```ini
# gce/systemd/bq-metrics.timer
OnCalendar=*:0/15
Persistent=true
```

- `Terraform/minecraft_monitoring.tf`: dataset `minecraft_monitoring` / table `server_metrics`（DAY パーティション + clustering=[server, metric_name]）
- `gce/scripts/insert_metrics.py`: stdlib のみ・ADC（GCE メタデータ）認証・`avg_over_time` / `max_over_time` で 15 分集計
- BigQuery `gcp_billing_export` × `server_metrics` を JOIN した **`cost_analysis_view`** によりプレイヤー比率で按分したコスト分析が可能（Looker Studio 接続向け）

### 6. Discord 通知統合（Pub/Sub Pull）

Cloud Functions push subscription は Cloudflare の ASN レベルブロック（GCP Functions の IP がブロックリスト掲載）で 403 になるため、**GCE VM 上の systemd timer (5 分間隔) が pull する** 構成に変更。

```text
[ Cloud Billing Budget ¥8,000/月 ]
    │ 90% / 100% threshold
    ▼
[ Pub/Sub: billing-alerts ] ←─── pull (5min) ─── [ billing-discord-notifier.service ]
                                                          │
                                                          ▼
                                                   Discord Webhook
                                              （JPY embed・User-Agent: DiscordBot）
```

- `Terraform/notifications.tf`: Pub/Sub topic + pull subscription + Budget + Secret Manager
- `gce/scripts/billing-discord-notifier.py`: stdlib のみ・`alertThresholdExceeded == 0` のメタメッセージはスキップ
- 月次バックアップ完了時にも `gcs-backup-cronjob` が **署名付き URL（7日有効）** 付き embed を Discord に送信

### 7. GCS Coldline バックアップ

```yaml
# Terraform/gcs_backup.tf
storage_class = "COLDLINE"
location      = "ASIA-NORTHEAST1"
lifecycle_rule {
  age = 365 → ARCHIVE
  age = 1095 → 削除
}
```

k3s の `gcs-backup-cronjob`（毎月1日 03:00 JST）が Lobby / Survival / MOD / Bedrock の 4 ワールドを `tar.gz` 化して GCS にアップロード。署名付き URL 生成には `mc-proxy-sa` への `roles/iam.serviceAccountTokenCreator` 委譲を Terraform で設定済み。

### 8. Secret 管理

Secret Manager で以下を管理:

| Secret 名 | 用途 |
|---|---|
| `tailscale-auth-key` | mc-proxy-1 / mc-monitoring-1 の cloud-init で `tailscale up` |
| `mc-discord-webhook-url` | 課金アラート・バックアップ通知の Webhook |
| `mc-player-hash-salt` | プレイヤー XUID の SHA256 ハッシュ用 256-bit salt（`Terraform/privacy.tf`） |

ハードコードを徹底排除し、SA に最小権限の `roles/secretmanager.secretAccessor` のみ付与。

---

## 💰 コスト削減実績

### アーキテクチャ進化

| フェーズ | 構成 | 月額コスト | 備考 |
|---|---|---:|---|
| Phase 0: 全クラウド見込み | 全コンポーネント GKE 上 | 約 35,000 円 | 当初試算（未実装） |
| Phase 1: GKE Hybrid | GKE Standard + オンプレ k3s | 約 19,700 円 | Phantom LB / Cloud NAT 等を含む |
| Phase 2: GCE 移行 (2026/05/03) | GCE mc-proxy-1 + オンプレ k3s | 約 3,680 円 | GKE 削除・LB 統合・NAT 廃止 |
| **Phase 3: 可観測性追加 (現在)** | **+ mc-monitoring-1 + BQ + Pub/Sub** | **約 7,000 円** | **監視 VM・課金予算 ¥8,000/月** |

主な削減要因:
- **GKE 削除**: コントロールプレーン費用・Phantom LB（¥2,700）・Cloud NAT（¥4,500）・nginx-gw-bedrock LB（¥2,700）が消滅
- **LB 統合**: Java/Bedrock 別 IP（¥2,700×2）→ 単一静的 IP 35.200.78.252
- **メモリ集約**: 高価なクラウドメモリを回避し JVM プロセスをオンプレ Ryzen 5700G / 64GB に集約

### VPS との比較（参考: 2026年5月時点・税込）

同等のゲーム機能（Velocity + Lobby + Survival + MOD + Bedrock = 18〜28GB JVM ヒープ）を国内 VPS で構築した場合:

| 構成 | 月額 | 年額 | 現構成との差 |
|---|---:|---:|---:|
| **🏆 現構成 (GCE Hybrid)** | **約 7,000 円** | **約 84,000 円** | 基準 |
| Xserver VPS 24GB（36ヶ月契約） | 7,200 円 | 86,400 円 | +2,400 円/年 |
| Xserver VPS 12GB + 24GB（思想維持） | 10,800 円 | 129,600 円 | +45,600 円/年 |
| さくらVPS 32G（12ヶ月一括） | 26,400 円 | 316,800 円 | +232,800 円/年 |

シングル VPS とほぼ同価格帯で「Terraform 管理・k3s・Tailscale ゼロトラスト・VictoriaMetrics 監視・BigQuery コスト分析・Discord 通知一式」を実現している。

#### 真の TCO（オンプレ運用の隠れコストを含む）

| 項目 | 月額換算 |
|---|---:|
| 電気代（Ryzen 5700G 60W 平均 / 30円/kWh） | 約 1,290 円 |
| ハードウェア減価償却（取得 15万円 / 36ヶ月） | 約 4,170 円 |
| 自宅 10GbE 回線（按分） | 約 1,000 円 |
| **クラウド支出** | **約 7,000 円** |
| **真の TCO 合計** | **約 13,460 円/月** |

---

## 📊 実証された成果

| 指標 | 結果 |
|------|------|
| **月間クラウド支出** | 約 ¥7,000（mc-proxy-1 + mc-monitoring-1 + BQ + Pub/Sub）|
| **グローバル遅延** | Tailscale Direct ≈ 20ms（東京リージョン経由）|
| **デプロイ時間** | Terraform `apply` 約 5 分（VM プロビジョニング + cloud-init） |
| **観測サイクル** | scrape 15秒 / BQ 集計 15分 / Discord pull 5分 |
| **バックアップ** | 月次 GCS Coldline + 日次 MinIO（オンプレ） |
| **コスト分析粒度** | プレイヤー比率按分（cost_analysis_view）|

---

## 📝 ロードマップ

### ✅ 完了（2026年5月）

- GKE → GCE 移行・LB 統合・NAT 廃止
- VictoriaMetrics + Grafana スタックを GCE 専用 VM へ移行
- BigQuery メトリクス収集（systemd timer + ADC 認証）
- BigQuery `cost_analysis_view`（課金 Export × server_metrics 日次 JOIN）
- GCS Coldline バックアップ（毎月1日・lifecycle 365日 ARCHIVE / 1095日削除）
- 課金アラート Discord 通知（Pub/Sub pull subscription）
- 月次バックアップ Discord 通知（署名付き URL 7日有効）
- プライバシー設計（player_hash_salt by Secret Manager）

### 🔲 今後

- [ ] **Looker Studio ダッシュボード**: cost_analysis_view を基にした公開向けレポート
- [ ] **External Secrets Operator**: k3s Secret 管理の外部化
- [ ] **Status Platform** (Phase 3): Kotlin API + Flutter Web + Envoy + Cloudflare Tunnel
- [ ] **Disaster Recovery 手順**: バックアップからのリストア演習・runbook 文書化
- [ ] **Argo CD 導入**: k3s マニフェストの GitOps 化

---

## 📜 ライセンス

MIT License - 詳細は [LICENSE](LICENSE) を参照

---

## 👤 Author

**HN: 田籠 勇吉 (Tagomori Yukichi)**

- GitHub: [@tagomori0211](https://github.com/tagomori0211)
- Portfolio: インフラエンジニア / SRE志望

---

> **Note**: 本プロジェクトは、クラウドとオンプレミスのハイブリッド構成における
> Infrastructure as Code の実践的なポートフォリオとして構築されました。
