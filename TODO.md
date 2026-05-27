# TODO - TAK Pipeline

> **最終更新**: 2026-05-27
> **優先順位**: Phase 0（割り込み） > Phase 1 > Phase 2 > Phase 3

---

## 🔴 Phase 0: Java ワールド一本化（割り込み・最優先）

### 背景
- 現在、Survival と Industry (Mod) は別サーバーとして稼働し、Velocity で振り分け + playersync でデータ連携している
- ディメンション分割（例: オーバーワールド=Survival / 別ディメンション=工業）により単一サーバーに統合し、サーバー間通信・playersync を不要にする
- **ワールドデータは破棄し、新規生成する（シード値はランダム = LEVEL_SEED 未設定）**
- **Velocity プロキシ層は廃止し、socat TCP 透過転送に置き換え（nginx も廃止）**
- **online-mode は全サーバー `false` で統一（BE と同様、認証不要運用）**

### タスク

- [x] **socat TCP転送の調査**:
  - ✅ socat は `TCP4-LISTEN:25565,fork,reuseaddr TCP4:<target>:25565` で TCP 透過転送可能
  - ✅ 既に `gce/compose.yaml` で Bedrock UDP 転送に `alpine/socat:latest` が稼働中
  - ✅ **結論: socat に一本化**。nginx も廃止し、TCP+UDP ともに socat で転送

- [ ] **Helm values 統合**: `values-survival.yaml` と `values-industry.yaml` を統合し、単一の values ファイルを作成
  - MOD セットの重複排除・マージ
  - メモリ: 30GB 程度に統合（Survival 16GB + Industry 30GB の合算を考慮しつつ最適化）
  - NodePort を単一に統一
  - `LEVEL_SEED` を削除（ランダムシードで新規ワールド生成）
  - `onlineMode: "FALSE"` を維持（Velocity の `online-mode = true` がなくなるため）

- [ ] **ディメンション分割の設計**: 工業ワールド用のカスタムディメンション設定を追加
  - 工業エリアへのポータル移動手段の選定（waystones / 専用ポータル MOD / カスタムディメンション MOD など）

- [ ] **Velocity 廃止**:
  - `gce/velocity/velocity.toml` を含む Velocity 関連の全設定を削除
  - `gce/systemd/mc-proxy.service` の停止・削除
  - `gce/compose.yaml` の velocity サービス + nginx-stream サービスを削除
  - socat TCP サービス（`TCP4-LISTEN:25565,fork,reuseaddr`）を compose.yaml に追加

- [ ] **playersync 設定削除**: 単一サーバーになるため playersync 関連の ConfigMap 参照を削除

- [ ] **k8s マニフェスト更新**: `k8s/onprem/backend-servers.yaml` のコメント・構造を更新

- [ ] **Lobby の扱い検討**: 単一サーバー化に伴い Lobby を残すか廃止するか判断

- [ ] **テスト・動作確認**: 統合サーバー起動、ディメンション間移動、MOD 動作、プラグイン互換性の確認

### 完了条件
- Survival + Industry が 1 つの Helm リリースで稼働
- Velocity が完全に廃止され、socat で TCP 透過転送
- playersync が不要になる
- ワールドが新規生成（ランダムシード）
- プレイヤーが工業エリアにポータルで移動可能
- online-mode = false で統一

---

## 🟡 Phase 1: オブザーバビリティ強化

- [ ] **Looker Studio ダッシュボード**: `cost_analysis_view` を基にした公開向けレポート作成
  - BigQuery `cost_analysis_view`（課金 Export × server_metrics JOIN）をデータソースに使用
  - コスト按分・プレイヤー数推移・サーバー稼働率の可視化

- [ ] **External Secrets Operator (ESO)**: k3s Secret 管理の外部化
  - GCP Secret Manager をバックエンドに、k3s 上の Secret を自動同期
  - `SecretStore` / `ExternalSecret` CRD の導入
  - 対象: `forwarding.secret`（Velocity 廃止後は不要だが、他 Secret があれば移行）

---

## 🟢 Phase 2: 運用堅牢化

- [ ] **Argo CD 導入**: k3s マニフェストの GitOps 化
  - Argo CD を k3s クラスタにデプロイ
  - GitHub リポジトリとの同期設定
  - Auto-Sync / Prune ポリシーの設定

- [ ] **Disaster Recovery 手順の確立**:
  - GCS Coldline バックアップからのリストア演習
  - runbook 文書化（手順・想定所要時間・ロールバック方法）
  - 定期的な復元テストのスケジュール化

- [ ] **作業手順書の整備** (`Documents/Task_mds/`):
  - `fix-nasu-golem-vv.md`: Nasu Golem VV 対応化手順の確認・更新
  - `restore-bedrock-world.md`: BDS ワールドリストア手順の確認・更新
  - Phase 0 作業で生じた新しい手順の文書化

---

## 🔵 Phase 3: Status Platform（Kotlin API + Flutter Web）

> 参照: `k8s/onprem/appserver.yaml`（マニフェスト定義済み、未適用）
> README ロードマップ Phase 3

### アーキテクチャ概要
```
User → HTTPS → Cloudflare Tunnel → Flutter Web (nginx)
Flutter Web → gRPC-Web → Envoy Proxy → Kotlin API (Ktor + gRPC)
Kotlin API → PromQL/HTTP → VictoriaMetrics
```

### コンポーネントと現状

| コンポーネント | 現状 | TODO |
|---------------|------|------|
| **Kotlin API** (Ktor + gRPC) | `appserver.yaml` に Deployment/Service 定義済み。イメージは `eclipse-temurin:21-jre` で `sleep infinity` のプレースホルダー | 実装・イメージビルド・デプロイ |
| **Envoy Proxy** (gRPC-Web → gRPC) | `appserver.yaml` に Deployment/ConfigMap/Service 定義済み。`envoyproxy/envoy:v1.31-latest` 使用 | 設定確認・適用 |
| **Flutter Web** (gRPC-Web Client) | `appserver.yaml` に Deployment/Service 定義済み。イメージは `nginx:alpine` のプレースホルダー | 実装・`flutter build web`・イメージビルド・デプロイ |
| **Cloudflare Tunnel** | `appserver.yaml` に Deployment 定義済み。要 `cloudflare-tunnel-secret` | トンネル作成・Secret 登録・ルーティング設定 |
| **Proto 定義** | 未作成。gRPC スキーマ（Kotlin API / Flutter Web のコード生成元） | `.proto` ファイルの設計・作成 |

### タスク

- [ ] **Proto 定義の設計**:
  - サービス定義: サーバーステータス、プレイヤー数、リソース使用率、アラート一覧 など
  - コード生成パイプラインの構築（Kotlin / Dart）

- [ ] **Kotlin API の実装**:
  - Ktor フレームワーク + gRPC Server
  - VictoriaMetrics への PromQL クエリ発行・集計ロジック
  - Prometheus メトリクスエンドポイント (`/metrics`) の実装
  - イメージビルド → `ghcr.io/tagomori1102/sushiski-kotlin-api` にプッシュ
  - `appserver.yaml` のイメージ参照をプレースホルダー → 実イメージに更新
  - `PROMETHEUS_URL` を VictoriaMetrics の Tailscale アドレスに設定（現在 `100.64.0.1:9090` は TODO）

- [ ] **Flutter Web の実装**:
  - gRPC-Web Client（マイクラライク UI）
  - サーバーステータス一覧・詳細・アラート表示
  - `flutter build web` で静的ファイル生成
  - イメージビルド → `ghcr.io/tagomori1102/sushiski-flutter-web` にプッシュ
  - `appserver.yaml` のイメージ参照をプレースホルダー → 実イメージに更新

- [ ] **Envoy Proxy の適用**:
  - ConfigMap `envoy-config` の gRPC-Web 設定を確認・調整
  - CORS 設定（本番ドメインに制限）

- [ ] **Cloudflare Tunnel のセットアップ**:
  - Cloudflare Zero Trust Dashboard でトンネル作成
  - トンネルトークンを取得し `cloudflare-tunnel-secret` として登録
  - CF ダッシュボードでパブリックホスト名 → `flutter-web.status.svc.cluster.local:80` にルーティング

- [ ] **デプロイ・動作確認**:
  - `kubectl apply -f k8s/onprem/appserver.yaml`
  - Flutter Web の外部 HTTPS アクセス確認
  - Kotlin API → VictoriaMetrics の接続確認

### 完了条件
- Kotlin API が VictoriaMetrics からメトリクスを取得し gRPC で提供
- Flutter Web が Cloudflare Tunnel 経由で HTTPS 公開
- サーバーステータスが Web UI で確認可能

---

## ⚪ Phase 4: 将来構想（優先度低）

- [ ] **GitHub Actions CI/CD**: イメージビルド・k3s デプロイの自動化
- [ ] **Loki + Tempo 導入**: ログ集約・分散トレーシング（現在は `mc-log-shipper` のみ）
- [ ] **負荷試験**: プレイヤー増加時のリソース使用率検証
- [ ] **Auto-scaling**: 需要に応じた k3s ノード追加（現在は単一 Proxmox VM）