# Architecture Decision Records (ADRs)

本ドキュメントは、Minecraft ハイブリッドクラウドインフラ（`Minecraft_java_k3s`）における主要な技術的・設計的決定を記録したアーキテクチャ決定記録（ADR）です。

---

## ADR 01: GKEからGCE & Docker Composeへの移行（コスト最適化）

### ステータス
承認済み (Accepted) - 2026-05-03

### コンテキスト（背景）
- 当初はプロキシ層として GKE Standard を採用し運用していた。
- しかし、GKE Standard のシステムコンポーネント（OSやKubernetes自体のオーバーヘッド）によるメモリ消費が大きく、`e2-small`（2GB RAM）1ノードでは Minecraft プロキシ関連の Pod（`nginx-gw`, `velocity`）がリソース不足で `Pending` となり起動できない問題が発生。
- 一時的に `e2-medium`（4GB RAM）へ増強、あるいは DaemonSet + hostPath 等による最適化を行ったものの、GKE 構成全体の維持費用が月額約 ¥19,700 と高コストであった。

### 決定（Decision）
- プロキシ層の Kubernetes (GKE) 自体を完全に廃止し、GCE 単一 VM (`mc-proxy-1`, e2-medium / 4GB RAM, pd-balanced 20GB, asia-northeast1-b) 上の Docker Compose 構成へ移行した。
- オンプレミスクラスター (k3s) との接続経路として、Tailscale メッシュ VPN を採用し、GCE VM 上で `tailscaled` をホスト側の systemd (kernel mode) で常時稼働させた。

### 結果（Consequences）
- **コストの大幅削減**: クラウド（GCP）側のコストが月額約 ¥19,700 から約 ¥3,680 へと **81% の削減**を達成。
- **リソース効率の向上**: VM 内の Kubernetes 制御プレーンやシステムコンポーネントのメモリオーバーヘッドが消滅し、VM リソース（4GBメモリ）をプロキシおよび中継プロセス（socat 等）に最大限活用可能となった。
- **耐障害性の向上**: シンプルな Docker Compose 起動のため、障害発生時の再起動やトラブルシュートが容易になった。

---

## ADR 02: BedrockプロキシのL4透過転送(socat)への統一とL7プロキシの廃止

### ステータス
承認済み (Accepted) - 2026-03-27

### コンテキスト（背景）
- Bedrock Edition（BDS）のプロキシとして、当初 WaterdogPE（L7）や Node.js ベースの `bedrock-relay`（L7）を採用した。
- しかし、以下の致命的な問題が頻発した：
  1. **パケット消失**: マイナーバージョン（プロトコルバージョン）の違いにより、未知の操作パケットがプロキシ層でドロップされ、チェストやドアが開かない等の現象が発生。
  2. **認証情報の消失 (XUID 消失)**: プロキシが Xbox Live 認証の暗号化ペイロードを正しく処理できず、すべての接続プレイヤーの XUID が `Unknown (0)` として転送され、2人目以降のログインが `Already connected`（ゴーストセッション/ID衝突）として弾かれた。
- また、L4プロキシとして Nginx Stream (UDP) を使用した際、Nginx の UDP プロキシ仕様により新しいパケットごとに異なるソースポートが割り当てられ、RakNet（ステートフルなUDPプロトコル）のセッションが数秒で切断された。

### 決定（Decision）
- L7 プロキシ（WaterdogPE, bedrock-relay）および Nginx Stream (UDP) プロキシを完全に廃止。
- GCE VM 上の Docker Compose にて、`socat` の UDP 透過転送（`UDP4-LISTEN:19132,fork,reuseaddr`）を採用し、オンプレミス側の BDS ポートへ直接中継した。

### 結果（Consequences）
- **完全な互換性**: パケットを一切解析・改変せずにそのまま透過させる（L4 透過）ため、BDS のバージョンアップ時もプロトコル不一致が発生しなくなり、XUID も正常に伝達されて多人数同時接続が可能になった。
- **セッションの維持**: `socat` の `fork` オプションにより、クライアントの接続（ソースIPおよびポート）ごとにソケットをフォークして透過転送するため、RakNet のステートフル接続が破綻しなくなった。

---

## ADR 03: オンプレk3sメモリ制限に伴うPod再起動ポリシーの厳格化

### ステータス
承認済み (Accepted) - 2026-04-18

### コンテキスト（背景）
- オンプレミスのリソース（Ryzen 5700G, 64GB RAM）は、Lobby（8Gi）, Survival（16Gi）, Industry（30Gi）, Bedrock（8Gi）の各サーバーの要求メモリ予約合計が約 62Gi に達しており、物理的な空きメモリが限界に近い。
- この状態で `kubectl rollout restart` を行うと、Kubernetes は旧 Pod の稼働を維持したまま新 Pod を立ち上げるため、一時的に要求メモリがオーバーコミットされ、OOMKilled によるプロセスクラッシュやノードフリーズが発生する重大なリスクがあった。

### 決定（Decision）
- `minecraft` namespace のゲーム用 Deployment において、**`kubectl rollout restart` の実行を完全に禁止**した。
- 再起動やマニフェスト更新時は、まず `replicas=0` にスケールダウンして旧 Pod のメモリを完全に解放し、`Terminating` プロセスが消滅したことを確認した後に `replicas=1` にスケールアップする手順をルール化した。

### 結果（Consequences）
- 限界まで切り詰めたメモリ容量であっても、Pod の更新や設定変更時にノードのクラッシュを招くことなく、安全にリリースサイクルを回せるようになった。

---

## ADR 04: Bedrock Server 接続性監視の MOTD 健全性チェック採用

### ステータス
承認済み (Accepted) - 2026-06-21

### コンテキスト（背景）
- BDS 1.26.x への自動更新時、特定のワールドデータ（`level.dat`）が破損し、`LANBroadcast` フィールドが `0` に書き換わってしまった。
- これにより、BDS は RakNet `UNCONNECTED_PONG` 応答にサーバー名やバージョン等の「MOTD（Server ID 文字列）」を載せなくなった。
- クライアントは MOTD がないためにサーバーを検出できず接続タイムアウトとなったが、従来の監視ツール（itzg/mc-monitor）は単に「UDPポートから Pong 応答があるか」で生存確認を行っていたため、この深刻な接続障害を検知できず17時間放置された。

### 決定（Decision）
- 監視ツールを Python による自作カスタムエクスポーターに差し替え、単に RakNet の Pong 応答があるかどうかだけでなく、**「返された Pong 応答に正常な MOTD (Server ID) 文字列が内包されているか」** をチェックして `minecraft_status_healthy=1` とする判定ロジックを実装した。
- また、プレイヤーのログイン数 (`minecraft_status_players_online_count`) が長期間ゼロのまま推移している状態をアラート検知の条件に追加した。

### 結果（Consequences）
- クライアント視点での「実際の接続可能性（Discovery 可能性）」に追従した監視ができるようになり、サイレントな接続障害を速やかに検知・対応できるようになった。

---

## ADR 05: Nasu Golem リソースパックのクライアント側グローバル配布への移行

### ステータス
承認済み (Accepted) - 2026-03-27

### コンテキスト（背景）
- 特定のリソースパック（Nasu Golem）をサーバーの `world_resource_packs.json` に登録して強制適用させようとした。
- しかし、BDS のリソースパック評価仕様とバグにより、クライアント側でグラフィック設定「Vibrant Visuals (VV)」が強制的にグレーアウトしてしまい、PBR（物理ベースレンダリング）などのグラフィック改善機能が選択できなくなる問題が発生した。

### 決定（Decision）
- サーバー側の `world_resource_packs.json` を空 (`[]`) に設定し、サーバーから強制配布するのを中止した。
- 代わりに、当該リソースパックは各プレイヤーが手動でクライアントのグローバルリソースパックとして適用する運用（BOOTH等の配布先の案内）へと切り替えた。

### 結果（Consequences）
- サーバー側のVV無効化バグを完全に回避しつつ、プレイヤー各自でVVおよび特定リソースパックの適用を両立することが可能となった。

---

## ADR 06: 工業エリアのカスタムディメンション(`sushi:industry`)への分離

### ステータス
承認済み (Accepted) - 2026-05-27

### コンテキスト（背景）
- オーバーワールド（生活ワールド）に Mekanism や AE2 などの大規模工業設備を構築すると、大量の Tick 処理によるサーバーのラグ（TPS低下）が一般のサバイバルエリアにまで波及し、同時に配線や機械による景観破壊も課題となっていた。
- 当初は Ad Astra MOD を導入して月面ディメンションを工業地帯にする案があったが、前提 MOD (botarium) が NeoForge 1.21.1 に対応していないためクラッシュし、断念した。

### 決定（Decision）
- vanilla datapack を使用して、カスタムディメンション `sushi:industry` （海面高さを `sea_level: 20` に下げて海面積を極小化した採掘・実用特化のフラットなオーバーワールド型地形）を自前定義した。
- ディメンション間の移動には、追加 MOD 数を最小限に抑えるため `World Portal` MOD のみを採用した。

### 結果（Consequences）
- 多数の MOD の競合リスクを回避しつつ、工業 Tick ラグをディメンション単位で隔離することに成功。
- サバイバル生活エリアの景観と快適なレスポンスを保護し、工業側の自由な設備拡張も実現した。
