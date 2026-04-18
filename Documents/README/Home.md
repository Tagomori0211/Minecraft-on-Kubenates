**Hybrid Cloud Minecraft Infrastructure**

Minecraftマルチサーバーを **GKE Standard + オンプレミス k3s** のハイブリッド構成で運用するインフラ基盤です。

---

## 🎯 プロジェクト概要

| 観点 | アプローチ |
|------|-----------|
| **コスト最適化** | GKE Spot Pod（最大91%削減）+ オンプレ大容量メモリ活用 |
| **可用性** | プロキシ層をクラウドに配置、グローバルアクセス確保 |
| **運用効率** | Terraform / Ansible / Kubernetes による IaC |
| **セキュリティ** | Tailscale によるゼロトラストネットワーク |

---

## 🏗️ システムアーキテクチャ

![infrastructure](.//architecture/infrastructure.svg)
### コンポーネント一覧

| レイヤー | コンポーネント | 配置 | 役割 |
|----------|---------------|------|------|
| Entry | Velocity Proxy | GKE | プレイヤー接続受付、サーバー振り分け |
| Lobby | Paper Server | GKE | 軽量ロビー（Spot Pod） |
| Game | Survival Server | On-Prem | バニラサバイバル（4GB） |
| Game | Industry Server | On-Prem | NeoForge工業MOD（8GB） |
| Network | Tailscale | Both | ゼロトラストVPN |

---

## 🔧 技術スタック

### Infrastructure as Code

```mermaid
flowchart LR
    subgraph Source
        Git["Git"]
    end

    subgraph Provisioning
        TF["Terraform"]
    end

    subgraph Configuration
        Ansible["Ansible"]
    end

    subgraph Orchestration
        K8S["Kubernetes"]
    end

    subgraph Runtime
        GKE_Pods["GKE Pods"]
        K3S_Pods["k3s Pods"]
    end

    Git --> TF
    TF --> Ansible
    TF --> K8S
    Ansible --> K8S
    K8S --> GKE_Pods
    K8S --> K3S_Pods
```

| ツール | 用途 |
|--------|------|
| **Terraform** | GKE / VPC / NAT / Proxmox VM プロビジョニング |
| **Ansible** | k3s インストール、マニフェストデプロイ |
| **Kubernetes** | コンテナオーケストレーション（k3s + GKE） |
| **Tailscale** | メッシュVPN（WireGuard） |

---

## 🌐 ネットワーク構成

```mermaid
flowchart LR
    subgraph Public
        Internet["Internet"]
        IP["Static IP"]
    end

    subgraph GKE_Net["GKE Network"]
        VPC["tak-vpc"]
        Subnet["10.100.0.0/20"]
        Pod["10.101.0.0/16"]
        Svc["10.102.0.0/20"]
    end

    subgraph TS_Net["Tailscale"]
        TS["100.x.x.x"]
    end

    subgraph K3S_Net["k3s Network"]
        K3S_Svc["10.43.0.0/16"]
    end

    Internet --> IP
    IP --> VPC
    VPC --> Subnet
    Subnet --> Pod
    Subnet --> Svc
    Pod <--> TS
    TS <--> K3S_Svc
```

| CIDR | 用途 |
|------|------|
| `10.100.0.0/20` | GKE Subnet |
| `10.101.0.0/16` | GKE Pod CIDR |
| `10.102.0.0/20` | GKE Service CIDR |
| `10.43.0.0/16` | k3s Service CIDR（Tailscale advertise） |

---

## 🎮 プレイヤー接続フロー

```mermaid
sequenceDiagram
    participant P as Player
    participant LB as LoadBalancer
    participant V as Velocity
    participant L as Lobby
    participant TS as Tailscale
    participant S as Survival

    P->>LB: Connect :25565
    LB->>V: Forward
    V->>V: Auth
    V->>L: Default Route
    L-->>P: Join Lobby
    
    Note over P,L: In Lobby

    P->>V: /server survival
    V->>TS: VPN Route
    TS->>S: Forward
    S-->>P: Join Survival
```

---

## 💰 コスト構成

```mermaid
flowchart TB
    subgraph Strategy["Cost Strategy"]
        S1["Zonal Standard CP\nCredit相殺 $0"]
        S2["e2-medium x1\nランニングコスト減"]
        S3["On-Prem\nメモリ(64GB)フル活用"]
    end

    subgraph GKE_Cost["GKE / Cloud"]
        C1["Node (e2-medium) ~$13"]
        C2["Static IP / LB ~$18"]
        C3["TS Router (e2-micro) ~$5"]
    end

    subgraph OnPrem_Cost["On-Prem"]
        C4["電気代約3,000円 (~$20)"]
    end

    subgraph Total
        Monthly["月額約7,650円 (~$51)"]
    end

    S1 --> C1
    S1 --> C2
    S2 --> GKE_Cost
    S3 --> C4
    
    GKE_Cost --> Monthly
    OnPrem_Cost --> Monthly
```

---

## 📁 リポジトリ構成

```
.
├── README.md                 # プロジェクト概要
├── docs/                     # ドキュメント
│   ├── OVERVIEW.md          # コラボレーター向け概要
│   ├── OPERATIONS.md        # 運用監視フロー
│   ├── ARCHITECTURE.md      # アーキテクチャ詳細図
│   └── postmortems/         # 障害振り返り
│
├── Ansible/                  # 構成管理
│   ├── inventory.ini
│   ├── install_k3s.yml
│   └── deploy_minecraft.yml
│
├── Terraform/                # インフラプロビジョニング
│   ├── main.tf
│   ├── gke.tf
│   ├── proxmox.tf
│   └── variables.tf
│
└── k8s/                      # Kubernetesマニフェスト
    ├── gke/                  # GKE用
    └── onprem/               # k3s用
```

---

## 🚀 クイックスタート

### 前提条件

- Terraform >= 1.5.0
- Ansible
- kubectl
- gcloud CLI（認証済み）
- Tailscale アカウント

### 1. GKEクラスター構築

```bash
cd Terraform
cp secret.tfvars.template secret.tfvars
# secret.tfvars を編集

terraform init
terraform apply -var-file="secret.tfvars"
```

### 2. オンプレミス k3s セットアップ

```bash
cd Ansible
ansible-playbook -i inventory.ini install_k3s.yml
ansible-playbook -i inventory.ini deploy_minecraft.yml
```

### 3. GKE マニフェスト適用

```bash
gcloud container clusters get-credentials tak-entrance --region asia-northeast1

kubectl create secret generic velocity-secret \
  --from-literal=velocity-forwarding-secret='YOUR_SECRET' \
  -n minecraft

kubectl apply -f k8s/gke/
```

---

## 📊 監視体制

```mermaid
flowchart LR
    subgraph Sources
        MC["mc-monitor"]
    end

    subgraph Collection
        GMP["Managed\nPrometheus"]
    end

    subgraph Alerting
        Alert["Cloud\nMonitoring"]
        Discord["Discord"]
    end

    MC --> GMP
    GMP --> Alert
    Alert --> Discord
```

### 日常監視コマンド

```bash
# Pod状態確認
kubectl get pods -n minecraft

# Tailscale接続確認
kubectl exec deploy/velocity -n minecraft -c tailscale -- tailscale status

# リソース使用状況
kubectl top pods -n minecraft
```

---

## 📚 ドキュメント

| ドキュメント | 説明 |
|-------------|------|
| [[OVERVIEW.md]] | コラボレーター向け概要・開発環境セットアップ |
| [[OPERATIONS]] | 運用監視フロー・障害対応手順 |
| [[Operations/Postmortem Template]] | 障害振り返りテンプレート |

---

## 🔗 外部リンク

- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
- [k3s Documentation](https://docs.k3s.io/)
- [Tailscale Documentation](https://tailscale.com/kb/)
- [Velocity Documentation](https://docs.papermc.io/velocity)

---

## 📝 ブランチ戦略

```mermaid
flowchart LR
    subgraph main
        M1(("init"))
        M2(("v1.1.0"))
    end

    subgraph develop
        D1(("feature-A"))
        D2(("merge"))
    end

    subgraph feature
        F1(("work"))
    end

    M1 -.-> D1
    D1 --> F1
    F1 --> D2
    D2 --> M2
```

| ブランチ | 用途 |
|----------|------|
| `main` | 本番適用済み安定版 |
| `develop` | 開発統合ブランチ |
| `feature/*` | 機能追加 |
| `fix/*` | バグ修正 |

---

## 👤 Author

**HN:田籠 勇吉(Tagomori0211)**

- インフラエンジニア / SRE志望
- ハイブリッドクラウド・IaC実践ポートフォリオ

---

> **License**: MIT License
