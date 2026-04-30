# TAK Pipeline - Hybrid Cloud Minecraft Infrastructure

**ハイブリッドクラウド構成によるMinecraftサーバー基盤**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge&logo=open-source-initiative&logoColor=white)](LICENSE)
![Terraform](https://img.shields.io/badge/IaC-Terraform-%237B42BC.svg?style=for-the-badge&logo=terraform&logoColor=white)
![Ansible](https://img.shields.io/badge/Config-Ansible-%23EE0000.svg?style=for-the-badge&logo=ansible&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-k3s%20%2B%20GKE-%23326CE5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)
![Google Cloud](https://img.shields.io/badge/GoogleCloud-GKE-%234285F4.svg?style=for-the-badge&logo=google-cloud&logoColor=white)
![Tailscale](https://img.shields.io/badge/Tailscale-VPN-%2354362B.svg?style=for-the-badge&logo=tailscale&logoColor=white)
![Cloudflare](https://img.shields.io/badge/Cloudflare-Tunnel-%23F38020.svg?style=for-the-badge&logo=cloudflare&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-%230F1628.svg?style=for-the-badge&logo=helm&logoColor=white)
![Hybrid Cloud](https://img.shields.io/badge/Hybrid%20Cloud-%23005571.svg?style=for-the-badge&logo=icloud&logoColor=white)
![Proxmox](https://img.shields.io/badge/Proxmox-%23E57024.svg?style=for-the-badge&logo=proxmox&logoColor=white)

---

## 📋 プロジェクト概要

本プロジェクトは、**オンプレミス（自宅サーバー）とGoogle Cloud（GKE）を Tailscale VPN で接続**し、コスト効率と可用性を両立させたMinecraftサーバー基盤です。

Java版・Bedrock版の両対応、専用ステータスプラットフォーム（Status Platform）を含む総合的なゲームインフラを構成しています。

Infrastructure as Code（IaC）を全面採用し、**Terraform / Ansible / Kubernetes マニフェスト**による完全な構成管理を実現しています。


### 🎯 設計思想

| 観点 | アプローチ |
|------|-----------|
| **コスト最適化** | GKE Standard（Zonal CP $0）+ オンプレ大容量メモリ活用 |
| **可用性** | プロキシ層をクラウドに配置し、グローバルアクセスを確保 |
| **運用効率** | IaCによる宣言的管理、GitOps対応の設計 |
| **セキュリティ** | Tailscale によるゼロトラストネットワーク |
| **拡張性** | StatusPlatform（Kotlin API + Flutter Web + Envoy）による独自ステータス基盤 |

---

## 🏗️ アーキテクチャ

![infrastructure](Documents/architecture/infrastructure.svg)
---

## 🛠️ 技術スタック

### Infrastructure as Code

| ツール | バージョン | 用途 |
|--------|-----------|------|
| **Terraform** | >= 1.5.0 | GKE / VPC / NAT / Proxmox VM のプロビジョニング |
| **Ansible** | - | k3s + Tailscale インストール、マニフェストデプロイ |
| **Kubernetes** | k3s + GKE Standard | コンテナオーケストレーション |

### クラウド・インフラ

| サービス | 用途 |
|---------|------|
| **GKE Standard** | ゾーナルクラスター（コントロールプレーン無料枠活用） |
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

## ⚙️ 主要な設計ポイント

### 1. コスト最適化戦略


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

**効果**: 当初見込みの**月額 35,000 円**から、ハイブリッド化とクラウド構成最適化により**月額約 7,650 円（約 78% 削減）**を達成。

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

![pie](Documents/architecture/MenResource.svg)

---

## 💰 コスト削減実績 (Cost Reduction Results)

### 7.1 アーキテクチャ進化によるコスト圧縮

当初のクラウド完結構成（見込み）と比較して、オンプレミスとクラウドの役割を分担させることで劇的な運用コスト削減を達成しました。

| 構成案 | 内容 | 月額コスト (概算) | 削減率 |
|--------|------|-------------------|--------|
| **Legacy Cloud Only (見込み)** | 全サーバーをクラウド上に配置 | **35,000 円** | 0% (基準) |
| **Hybrid Baseline** | GKE Autopilot Pod 課金 | 約 12,000 円 | 65.7% |
| **Optimized Hybrid (現在)** | **GKE Standard (Zonal $0 CP) + On-Prem** | **約 7,650 円** | **約 78.1%** |

#### 💡 削減のポイント
- **GKE Standard ゾーナル選定**: 1ゾーンに絞ることでコントロールプレーン費用（$74.4/月）を Google Cloud クレジットで実質無料化。
- **メモリ集約**: 高価なクラウドメモリを回避し、オンプレミス (Ryzen 5700G / 64GB) に JVM プロセスを集約。
- **Tailscale による透過的接続**: VPN 経由でもオーバーヘッドを最小限に抑え、クラウド側にプロキシ層 (Velocity) のみを残すことで、パケット転送費用と最小構成のノード代のみに圧縮。

---

### 7.2 ゲーム向けVPS（Xserver / さくらインターネット）との実弾コスト比較

「現実的な代替案」として、本構成と同等のゲーム機能（Java 2ワールド + Velocity + Lobby + Bedrock 1ワールド = 計5プロセス）を国内主要VPSで構築した場合のコストを試算しました。

#### 必要リソース見積もり

| コンポーネント | JVMヒープ目安 | 備考 |
|---|---|---|
| Velocity Proxy | 0.5〜1GB | 軽量プロキシ |
| Lobby (Paper) | 2GB | ハブサーバー |
| Java-Survival (Paper) | 6〜8GB | バニラ＋プラグイン |
| Java-Industry (NeoForge MOD) | 6〜10GB | MOD多数で重量 |
| Bedrock Server | 2〜4GB | 統合版 |
| **合計（OSオーバーヘッド込み）** | **約 18〜28GB** | |

#### 国内VPS料金リファレンス（2026年5月時点・税込）

**Xserver VPS（36ヶ月契約・通常料金）**

| プラン | メモリ / vCPU / SSD | 月額 |
|---|---|---|
| 12GBプラン | 12GB / 6コア / 400GB NVMe | 3,600円 |
| 24GBプラン | 24GB / 8コア / 800GB NVMe | 7,200円 |
| 48GBプラン | 48GB / 16コア / 1,500GB NVMe | 14,400円 |

**さくらのVPS（石狩リージョン・12ヶ月一括払い）**

| プラン | メモリ / vCPU / SSD | 月額 |
|---|---|---|
| 4Gプラン | 4GB / 4コア / 200GB SSD | 3,520円 |
| 8Gプラン | 8GB / 6コア / 400GB SSD | 7,040円 |
| 16Gプラン | 16GB / 8コア / 800GB SSD | 13,200円 |
| 32Gプラン | 32GB / 10コア / 1,600GB SSD | 26,400円 |

> **Note**: さくらVPSは長期割引が「12ヶ月一括で約1ヶ月分お得」程度。Xserverの36ヶ月契約は最大34%OFFと長期割引が強力。本比較ではそれぞれ最大割引適用後の正規料金を採用。

#### シナリオ別コスト比較

| シナリオ | 構成 | 月額 | 年額 | 現構成との差 |
|---|---|---:|---:|---:|
| **🏆 現構成 (Optimized Hybrid)** | GKE + オンプレk3s | **7,650円** | **91,800円** | **基準** |
| Xserver A: 単一VPS | 24GB × 1台 | 7,200円 | 86,400円 | -5,400円/年 |
| Xserver B: 思想維持 | 12GB + 24GB | 10,800円 | 129,600円 | +37,800円/年 |
| Xserver C: MOD余裕構成 | 12GB + 48GB | 18,000円 | 216,000円 | +124,200円/年 |
| **さくら A: 単一VPS** | **32G × 1台** | **26,400円** | **316,800円** | **+225,000円/年** |
| **さくら B: 思想維持** | **8G + 16G** | **20,240円** | **242,880円** | **+151,080円/年** |
| **さくら C: MOD余裕構成** | **8G + 32G** | **33,440円** | **401,280円** | **+309,480円/年** |
| Legacy Cloud Only (見込み) | フルクラウド | 35,000円 | 420,000円 | +328,200円/年 |

#### 💡 ベンダー間で価格差が3倍開く理由

同じ16GB帯でXserver（12GB+24GB=36GB相当で10,800円）と さくら（8G+16G=24GB相当で20,240円）に**約2倍の価格差**が生じる。これは：

1. **Xserverのメモリ無料増設**: 旧4GBプランが12GBプランに、旧16GBが24GBにそれぞれ自動増設されている（実質単価がGBあたり大幅に下がった）
2. **NVMe vs SSD**: XserverはNVMe標準、さくらはSATA SSD（ランダムIO性能で約17倍差）
3. **長期契約割引の強度**: Xserverは36ヶ月で34%OFF、さくらは12ヶ月で約8%OFFのみ

ただし**さくらにはローカルネットワーク機能（VPS間プライベート接続）がある**点で、本構成のような複数台冗長を「正しい設計で」組む場合の付加価値は大きい。Xserverには同等機能がない。

---

### 7.3 本構成の真価：シングルVPSと同等コストでエンタープライズ級基盤

数字を並べて見えてくる事実：

> **Xserver 24GB単体 (7,200円/月) ≒ 本構成 (7,650円/月)**

つまり「クラウドネイティブな冗長構成・IaC・k3s・Tailscale・Prometheus一式」を**シングルVPSとほぼ同コストで実現**している。さくらVPSで同等の冗長設計を組むと年間15万円以上の追加コストになるところを、本構成は単一VPSと同価格帯に収まっている。

#### 公平性のための補足：オンプレ運用の隠れコスト

本構成の真の総保有コスト (TCO) には以下を含める必要があります：

| 項目 | 月額換算 | 備考 |
|---|---:|---|
| 電気代（Ryzen 5700G常時稼働） | 約 1,290円 | 60W平均×30円/kWh×24h×30日（北九州・九電） |
| ハードウェア減価償却 | 約 4,170円 | 取得費15万円÷36ヶ月 |
| 自宅10GbE回線（按分） | 約 1,000円 | フレッツ光クロス一部按分 |
| **隠れコスト合計** | **約 6,460円** | |
| **真のTCO** | **約 14,110円/月** | |

この真のTCOで再評価しても：
- **さくら思想維持構成（20,240円）より6,000円/月安い**
- **Xserver思想維持構成（10,800円）より約3,300円/月高い**

つまり「VPS価格より安い」は誇張だが、**Xserverと拮抗・さくらに対して圧倒的優位**。さらにポートフォリオ価値・運用学習価値を含めれば、トータルで**就職活動の投資対効果が極めて高い**設計と言えます。

---

### 7.4 一番効いている削減技術：メモリ集約

本構成の核心は **「メモリ集約をオンプレに寄せる」** という設計判断に集約される：

| 環境 | メモリGB単価 (月額) | 備考 |
|---|---:|---|
| GKE Autopilot (Standard Pod) | 約 360円 | 0.5GBで月179円 |
| GKE Autopilot (Spot Pod) | 約 30円 | 91%OFF |
| Xserver VPS (24GB) | 300円 | プラン全体÷メモリ |
| さくらVPS (16GB) | 825円 | プラン全体÷メモリ |
| **オンプレ (5700G + 64GB)** | **65円** | 取得費15万円÷36ヶ月÷64GB |

オンプレのメモリGB単価は**さくらVPSの約13分の1、Xserver VPSの約5分の1**。GKE側に1GBもメモリを使わせず、Spot Podで月135円（電気代のおまけ）にまで圧縮していることが、全体コストを劇的に下げている本質的な要因です。

---

## 📊 実証された成果

| 指標 | 結果 |
|------|------|
| **月間インフラコスト** | 約$15-20（Spot Pod + オンプレ） |
| **グローバル遅延** | 東京リージョン経由で国内100ms以下 |
| **デプロイ時間** | Terraform + Ansible で約15分 |
| **可用性** | Spot中断時も30秒以内に自動復旧 |
| **対応バージョン** | Java版 + Bedrock版 |
| **コスト効率** | 同等機能のさくらVPS構成比 約62%削減 |

---

## 📝 今後の拡張計画

- [ ] **Kotlin API / Flutter Web** の実装
- [ ] **Argo CD** によるGitOps化
- [ ] **External Secrets Operator** によるSecret管理の外部化
- [ ] **Grafana Dashboard** のテンプレート化（Minecraft専用メトリクス）
- [ ] **Disaster Recovery** 手順の文書化


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


[def]: https://shields.io