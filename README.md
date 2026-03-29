# TAK Pipeline - Hybrid Cloud Minecraft Infrastructure

**ハイブリッドクラウド構成によるMinecraftサーバー基盤**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Kubernetes](https://img.shields.io/badge/Kubernetes-k3s%20%2B%20GKE-326CE5?logo=kubernetes)
![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC?logo=terraform)
![Ansible](https://img.shields.io/badge/Config-Ansible-EE0000?logo=ansible)

---

## 📋 プロジェクト概要

本プロジェクトは、**オンプレミス（自宅サーバー）とGoogle Cloud（GKE）を Tailscale VPN で接続**し、コスト効率と可用性を両立させたMinecraftサーバー基盤です。

Java版・Bedrock版の両対応、専用ステータスプラットフォーム（sushiski Status Platform）を含む総合的なゲームインフラを構成しています。

Infrastructure as Code（IaC）を全面採用し、**Terraform / Ansible / Kubernetes マニフェスト**による完全な構成管理を実現しています。


### 🎯 設計思想

| 観点 | アプローチ |
|------|-----------|
| **コスト最適化** | GKE Autopilot の Spot Pod（最大91%削減）+ オンプレ活用 |
| **可用性** | プロキシ層をクラウドに配置し、グローバルアクセスを確保 |
| **運用効率** | IaCによる宣言的管理、GitOps対応の設計 |
| **セキュリティ** | Tailscale によるゼロトラストネットワーク |
| **拡張性** | StatusPlatform（Kotlin API + Flutter Web + Envoy）による独自ステータス基盤 |

---

## 🏗️ アーキテクチャ

```mermaid
flowchart TB
    subgraph Internet["インターネット"]
        direction LR
        Player_Java["Java版"]
        Player_Bedrock["Bedrock版"]
        Admin["管理者"]
        User["一般ユーザー"]
    end

    subgraph GCP["GCP (asia-northeast1)"]
        direction TB
        
        subgraph GKE["GKE Autopilot"]
            subgraph MonPods["監視層"]
                Prometheus["Prometheus"]
                Grafana["Grafana"]
            end
            subgraph GamePods["ゲームプロキシ層"]
                GW["Nginx GW<br/>25565/TCP<br/>19132/UDP"]
                Velocity["Velocity<br/>ClusterIP"]
                Lobby["Lobby<br/>Spot Pod"]
            end
            
        end
        subgraph transform01["a"]
        direction TB
            SubnetRouter["Subnet Router<br/>e2-micro / VPC 100.64.0.0/10"]
        end
    end

    subgraph TS["Tailscale VPN (100.x.x.x)"]
        TS_Net["Tailscale仮想LAN"]
    end

    subgraph Onprem["オンプレ: Ryzen 5700G / 64GB"]
        subgraph Worker["k3s-worker VM (58Gi)"]
            TS_K3s["Tailscale Client"]
            subgraph GameServers["ゲームサーバー"]
                subgraph Experimental["実験的 (Java)"]
                    Java_Survival["Survival<br/>16Gi"]
                    Java_Industry["Industry MOD<br/>30Gi"]
                end
                subgraph Conservative["安定 (Bedrock)"]
                    Bedrock["Bedrock (BDS)<br/>8Gi / 16-Thread<br/>hostPort 19132"]
                end
            end
            subgraph SP["Status Platform"]
                direction TB
                CF_Tunnel["CF Tunnel"]
                Flutter["Flutter Web"]
                Envoy["Envoy"]
                Kotlin["Kotlin API<br/>Ktor + gRPC"]
            end
        end
        
    end

    %% === ゲームトラフィック ===
    Player_Java -->|"25565/TCP"| GW
    Player_Bedrock -->|"19132/UDP"| GW
    GW --> Velocity
    Velocity --> Lobby

    %% === GKE → Tailscale → オンプレ ===
    Velocity --->|"VPC Route"| SubnetRouter
    GW ---->|"UDP Stream (L4 Proxy)"| SubnetRouter
    TS_Net <--> TS_K3s
    TS_K3s --> Java_Survival
    TS_K3s --> Java_Industry
    TS_K3s --> Bedrock
    
    SubnetRouter <-->|"Tunnel"| TS_Net
    %% === Status Platform ===
    User ------->|"HTTPS"| CF_Tunnel
    direction TB
    CF_Tunnel --> Flutter
    Flutter --> Envoy
    Envoy --> Kotlin

    

    %% === 管理者・監視 ===
    Admin -->|"Tailscale"| Grafana
    Grafana -.-> Prometheus
    Prometheus -.->|"VPC Route"| SubnetRouter

    

    %% === スタイル ===
    style GW fill:#00C853,color:#fff
    style Velocity fill:#34a853,color:#fff
    style Lobby fill:#fbbc04,color:#000
    style Prometheus fill:#e6522c,color:#fff
    style Grafana fill:#f46800,color:#fff
    style SubnetRouter fill:#8B5CF6,color:#fff
    style TS_Net fill:#333,color:#fff
    style TS_K3s fill:#555,color:#fff
    style Java_Survival fill:#2E7D32,color:#fff
    style Java_Industry fill:#1B5E20,color:#fff
    style Bedrock fill:#ea4335,color:#fff
    style CF_Tunnel fill:#F6821F,color:#fff
    style Flutter fill:#02569B,color:#fff
    style Envoy fill:#AC6199,color:#fff
    style Kotlin fill:#7F52FF,color:#fff
    style GamePods fill:#0d1117,color:#c9d1d9,stroke:#30363d
    style MonPods fill:#0d1117,color:#c9d1d9,stroke:#30363d
    style GameServers fill:#0d1117,color:#c9d1d9,stroke:#30363d
    style Experimental fill:#1a1a2e,color:#4ade80,stroke:#4ade80
    style Conservative fill:#1a1a2e,color:#f87171,stroke:#f87171
    style SP fill:#0d1117,color:#c9d1d9,stroke:#30363d
```

### コンポーネント構成

| レイヤー | コンポーネント | 配置 | 役割 |
|----------|---------------|------|------|
| **Entry** | Nginx Stream Gateway | GKE 通常Pod | Java/Bedrock版のトラフィック受付・透過的L4レベル転送 |
| **Proxy (Java)** | Velocity Proxy | GKE 通常Pod | Java版プレイヤー接続受付・サーバー振り分け |
| **Lobby** | Paper Server | GKE Spot Pod | 軽量ロビー（ステートレス） |
| **Game** | Java-Survival | On-Prem k3s | バニラライクサバイバル (16GB Guaranteed) |
| **Game** | Java-Industry MOD | On-Prem k3s | NeoForge工業MOD (30GB Guaranteed) |
| **Game** | Bedrock Server | On-Prem k3s | Bedrock版ゲームサーバー (8GB Guaranteed / 16-Thread) |
| **Monitoring** | Prometheus | GKE 通常Pod | 全コンポーネント監視 |
| **Monitoring** | Grafana | GKE 通常Pod | 管理者専用ダッシュボード（Tailscale接続） |
| **Status** | Kotlin API | On-Prem k3s | メトリクス集計・gRPCサービング |
| **Status** | Flutter Web | On-Prem k3s | マイクラライクステータスUI |
| **Status** | Envoy Proxy | On-Prem k3s | gRPC-Web → gRPC 変換 |
| **Status** | Cloudflare Tunnel | On-Prem k3s | 外部HTTPS公開 |
| **Network** | Tailscale | 全ノード | ゼロトラストメッシュVPN |

---

## 🛠️ 技術スタック

### Infrastructure as Code

| ツール | バージョン | 用途 |
|--------|-----------|------|
| **Terraform** | >= 1.5.0 | GKE / VPC / NAT / Proxmox VM のプロビジョニング |
| **Ansible** | - | k3s + Tailscale インストール、マニフェストデプロイ |
| **Kubernetes** | k3s + GKE Autopilot | コンテナオーケストレーション |

### クラウド・インフラ

| サービス | 用途 |
|---------|------|
| **GKE Autopilot** | マネージドKubernetes（Spot Pod対応） |
| **Cloud NAT** | プライベートノードの外部通信 |
| **Proxmox VE** | オンプレミス仮想化基盤 |
| **Tailscale** | メッシュVPN（ゼロトラスト） |
| **Cloudflare Tunnel** | StatusPlatform 外部公開 |

### アプリケーション

| コンポーネント | イメージ |
|---------------|---------|
| Velocity Proxy | `itzg/bungeecord` |
| Lobby / Survival | `itzg/minecraft-server` (Paper) |
| Java-Indicatory MOD | `itzg/minecraft-server` (NeoForge) |
| Bedrock Server | `itzg/minecraft-bedrock-server` |
| Metrics Exporter | `itzg/mc-monitor` |
| Prometheus | `prom/prometheus` |
| Grafana | `grafana/grafana` |
| Envoy Proxy | `envoyproxy/envoy` |
| Kotlin API | Ktor + gRPC（独自ビルド） |
| Flutter Web | Flutter Web Build（独自ビルド） |
| Cloudflare Tunnel | `cloudflare/cloudflared` |

---

## 📁 ディレクトリ構成

```
.
├── Ansible/
│   ├── inventory.ini        # ホスト定義 (k3s-worker: 192.168.0.151)
│   ├── install_k3s.yml      # k3s + Tailscale インストールPlaybook
│   └── deploy_minecraft.yml # マニフェストデプロイPlaybook
│
├── Terraform/
│   ├── main.tf              # Terraformブロック・プロバイダ設定
│   ├── gke.tf               # GKE Autopilot、VPC、NAT、Firewall
│   ├── proxmox.tf           # Proxmox VM定義（k3s-worker: 58Gi, 16Cores）
│   ├── variables.tf         # 変数定義
│   ├── output.tf            # 出力定義
│   ├── terraform.tfvars     # 変数値
│   └── secret.tfvars.template # シークレット用テンプレート
│
└── k8s/
    ├── gke/                  # GKE用マニフェスト
    │   ├── 00-namespace.yaml
    │   ├── 02-velocity-config.yaml      # Velocity設定 (survival/mod/lobby)
    │   ├── 10-velocity-deployment.yaml  # Velocity 通常Pod + Tailscale Sidecar
    │   ├── 11-lobby-deployment.yaml     # Lobby Spot Pod
    │   ├── 20-nginx-gw.yaml             # Nginx Stream Gateway (TCP/UDP)
    │   ├── 20-services.yaml             # LoadBalancer / ClusterIP
    │   └── 30-monitoring.yaml           # Prometheus + Grafana (Tailscale経由)
    │
    └── onprem/               # オンプレミス(k3s)用マニフェスト
        ├── backend-servers.yaml  # Survival / Mod / Bedrock + Tailscale Router
        └── appserver.yaml        # StatusPlatform (Kotlin API, Flutter, Envoy, CF Tunnel)
```

---

## ⚙️ 主要な設計ポイント

### 1. コスト最適化戦略

```hcl
# Terraform: Spot Pod強制設定
variable "enable_spot_only" {
  default = true  # 全ワークロードをSpot Podで実行
}
```

```yaml
# Kubernetes: Spot Pod toleration (Lobby)
nodeSelector:
  cloud.google.com/gke-spot: "true"
tolerations:
  - key: "cloud.google.com/gke-spot"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
```

| 項目 | 通常 Pod (Standard) | Spot Pod (採用中) | 削減額 |
|------|---------------------|-------------------|--------|
| vCPU (0.25) | ~$8.12 | ~$0.73 | -$7.39 |
| メモリ (0.5GB) | ~$1.79 | ~$0.16 | -$1.63 |
| 合計 | ~$9.91 (約1,500円) | ~$0.89 (約135円) | 約91% OFF |

**効果**: GKE Autopilotの通常Podと比較して**最大91%のコスト削減**

### 2. ゼロトラストネットワーク (Tailscale)

```yaml
# Tailscale Sidecar パターン (Velocity / Prometheus / Grafana)
containers:
  - name: tailscale
    image: tailscale/tailscale:latest
    env:
      - name: TS_USERSPACE
        value: "true"  # GKE Autopilot対応（カーネルモード不可）
      - name: TS_EXTRA_ARGS
        value: "--accept-routes"
```

オンプレミス側の**Tailscale Subnet Router**がk3s Service CIDR（`10.43.0.0/16`）をアドバタイズし、GKEからシームレスにアクセス可能。

### 3. Nginx Stream Gatewayによる透過的ルーティング

```text
Player (Bedrock) --UDP 19132--> GKE L4 LB
                                  |
                  Nginx Stream L4 Gateway (GKE)
                      (No packet morphing)
                                  |
                 Tailscale VPN 経由 直接 UDP 転送
                                  |
                Bedrock Server Pod (k3s hostPort)
```

GKEにNginx UDP/TCP Stream Gatewayを配置しアクセスIPを統合。Bedrock版アクセスは、L7プロキシ特有の通信欠損やIP・Xbox認証情報(XUID)の消失を防ぐため、敢えてNginxからオンプレ側のMinecraftサーバー(`hostPort`)へパケットを一切改変せずL4レベルで透過転送しています。

### 4. StatusPlatform (gRPC-Web アーキテクチャ)

```
User --> HTTPS --> Cloudflare Tunnel --> Flutter Web
                                             |
                                      gRPC-Web (HTTP/1.1)
                                             |
                                        Envoy Proxy
                                             |
                                       gRPC (HTTP/2)
                                             |
                                        Kotlin API (Ktor)
                                             |
                                    PromQL --> Prometheus (GKE)
```

shared `.proto` ファイルからKotlin API・Flutter Webのコードを自動生成し、型安全なAPIを実現。

### 5. Secret管理

```yaml
# initContainerによるSecret注入
initContainers:
  - name: inject-velocity-secret
    command: ["sh", "-c"]
    args:
      - |
        echo -n "${VELOCITY_SECRET}" > /velocity-data/forwarding.secret
    env:
      - name: VELOCITY_SECRET
        valueFrom:
          secretKeyRef:
            name: velocity-secret
            key: velocity-forwarding-secret
```

### 6. 可観測性（全コンポーネント監視）

Prometheusが監視する対象：
- GKE: Nginx Stream Gateway, Velocity, Lobby
- オンプレ (Tailscale経由): Java-Survival, Java-Industry MOD, Bedrock Server, Kotlin API

Grafanaは管理者専用。Tailscale経由（`tak-grafana-gke`ホスト名）でのみアクセス可能。

### 7. オンプレミス リソース構成

```mermaid
pie title "k3s-worker VM 内訳（58Gi）"
    "Java-Industry MOD (30Gi)" : 30
    "Java-Survival (16Gi)" : 16
    "Bedrock Server (8Gi)" : 8
    "Kotlin API (1Gi)" : 1
    "Tailscale sidecar (256Mi)" : 0.25
    "Flutter Web (256Mi)" : 0.25
    "Envoy (256Mi)" : 0.25
    "CF Tunnel (128Mi)" : 0.125
    "kube-system (~1.5Gi)" : 1.5
    "残バッファ (~0.6Gi)" : 0.625
```

---

## 🚀 デプロイ手順

### 前提条件

- Terraform >= 1.5.0
- Ansible
- kubectl
- gcloud CLI（認証済み）
- Tailscale アカウント
- Cloudflare アカウント（StatusPlatform公開用）

### 1. GKEクラスター構築

```bash
cd Terraform

# 変数設定
cp secret.tfvars.template secret.tfvars
# secret.tfvars を編集（tailscale_auth_key, proxmox認証情報等）

# プロビジョニング
terraform init
terraform plan -var-file="secret.tfvars"
terraform apply -var-file="secret.tfvars"
```

### 2. オンプレミスk3s + Tailscaleセットアップ

```bash
cd Ansible

# .env に TAILSCALE_AUTH_KEY を記載しておくこと
# k3s インストールと Tailscale 自動認証
ansible-playbook -i inventory.ini install_k3s.yml
```

### 3. GKEマニフェスト適用

```bash
# クレデンシャル取得
gcloud container clusters get-credentials tagomori-minecraft --region asia-northeast1

# Secret作成
kubectl create secret generic velocity-secret \
  --from-literal=velocity-forwarding-secret='YOUR_SECRET' \
  -n minecraft

kubectl create secret generic tailscale-auth \
  --from-literal=TS_AUTHKEY='tskey-auth-xxxxx' \
  -n minecraft

kubectl create secret generic tailscale-auth \
  --from-literal=TS_AUTHKEY='tskey-auth-xxxxx' \
  -n monitoring

# マニフェスト適用
kubectl apply -f k8s/gke/
```

### 4. オンプレミスマニフェストデプロイ

```bash
cd Ansible

# k3s-worker node へのデプロイ
ansible-playbook -i inventory.ini deploy_minecraft.yml
```

### 5. Cloudflare Tunnel設定

```bash
# Cloudflare Zero TrustダッシュボードでTunnelを作成
# TUNNEL_TOKEN を取得後:
kubectl create secret generic cloudflare-tunnel-secret \
  --from-literal=tunnel-token='<TUNNEL_TOKEN>' \
  -n status

# Cloudflareダッシュボードでルーティング設定:
# <your-domain> --> http://flutter-web.status.svc.cluster.local:80
```

---

## 📊 実証された成果

| 指標 | 結果 |
|------|------|
| **月間インフラコスト** | 約$15-20（Spot Pod + オンプレ） |
| **グローバル遅延** | 東京リージョン経由で国内100ms以下 |
| **デプロイ時間** | Terraform + Ansible で約15分 |
| **可用性** | Spot中断時も30秒以内に自動復旧 |
| **対応バージョン** | Java版 + Bedrock版（クロスプレイ対応） |

---

## 🔧 運用Tips

### Tailscale接続確認

```bash
# GKE Velocity Pod内
kubectl exec -it deploy/velocity -c tailscale -n minecraft -- tailscale status

# GKE Prometheus Pod内
kubectl exec -it deploy/prometheus -c tailscale -n monitoring -- tailscale status

# オンプレ MinecraftServer
ssh 192.168.0.151 -- tailscale status
```

### Prometheus ターゲット確認

```bash
# GKE Prometheus ダッシュボード（port-forward）
kubectl port-forward svc/prometheus-service 9090:9090 -n monitoring
# http://localhost:9090/targets
```

### ログ確認

```bash
# Velocity
kubectl logs -f deploy/velocity -c velocity -n minecraft

# Bedrock Server
kubectl logs -f deploy/deploy-bedrock -c bedrock -n minecraft

# Kotlin API
kubectl logs -f deploy/kotlin-api -n status
```

---

## 📝 今後の拡張計画

- [ ] **Argo CD** によるGitOps化
- [ ] **External Secrets Operator** によるSecret管理の外部化
- [ ] **Grafana Dashboard** のテンプレート化（Minecraft専用メトリクス）
- [ ] **Kotlin API / Flutter Web** の実装
- [ ] **Disaster Recovery** 手順の文書化
- [ ] **GeyserMC / Floodgate** によるJava-Bedrocクロスプレイ

---

## 📜 ライセンス

MIT License - 詳細は [LICENSE](LICENSE) を参照

---

## 👤 Author

**HN:田籠 勇吉 (Tagomori Yukichi)**

- GitHub: [@tagomori0211](https://github.com/tagomori0211)
- Portfolio: インフラエンジニア / SRE志望

---

> **Note**: 本プロジェクトは、クラウドとオンプレミスのハイブリッド構成における
> Infrastructure as Code の実践的なポートフォリオとして構築されました。
