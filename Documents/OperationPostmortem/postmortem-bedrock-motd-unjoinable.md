# 📝 インシデント・ポストモーテム — Bedrock 接続タイムアウト（MOTDなし offline-ping）

> Blameless Postmortem。事象の客観記録と再発防止が目的。

---

## 📅 基本情報

| 項目 | 内容 |
|------|------|
| 発生日時 | 不明（`:latest` 自動更新で BDS 1.26.31.1 に上がった頃から潜在化。ユーザー指摘 2026-06-21） |
| 調査日時 | 2026-06-21 |
| 影響範囲 | **Bedrock(統合版) サーバへ全クライアントが接続不可**（一覧でサーバ情報を取得できず、接続試行はタイムアウト）。Java版・監視・他サービスは影響なし |
| 対応者 | @Tagomori0211 + Claude Code |
| 状態 | **解消（接続復旧）**。真因＝level.dat `LANBroadcast=0`。外科的修正でワールド(建築/db)を保持したまま復旧。※エンティティは別の既存破損で復元不可→手動補填方針 |

---

## 🔍 1. 何が起きたか

- **事象概要**: 特定クライアント（実際は全クライアント）が Bedrock サーバ `35.200.78.252:19132` へ接続するとタイムアウトする。当該クライアントは他の最新版BDS（同 1.26.31）には接続成功するため、クライアント本体は正常。
- **ユーザー証言の要点**:
  - クライアント版数 = **1.26.31**（サーバ 1.26.31.1 と一致 → バージョン不一致ではない）
  - サーバ一覧で**「サーバー情報が取得できない」**（名前・人数が出ない）。保存したIP直打ちで接続試行 → タイムアウト。

---

## 🔬 2. 調査プロセス（レイヤー順の切り分け）

### 2.1 バックエンド〜経路は全て正常と確認
- k3s `deploy-bedrock` は Running、`Server started.`、RakNet ポート 19132 リッスン、エラー無し。
- hostPort DNAT（→pod:19132）正常、GCE `socat-bedrock`（`fork,reuseaddr`）稼働、GCE firewall `udp:19132` 開放、Tailscale direct 20ms/0%loss、静的IP `35.200.78.252` 正常付与。
- RakNet `OpenConnectionRequest1 → Reply1(0x06)` は応答する（接続層は生存）。

### 2.2 ❌ 誤誘導①：MTU/フラグメンテーション
- Tailscale トンネル MTU=1280 < RakNet 既定 MTU 1492 のため、1252B超の UDP が tailscale0 上で IP フラグメント化（tcpdumpで実証）。Java(TCP) は MSS 1240 に自動クランプされ無影響。
- 一見もっともらしいが、`RAKNET_FORCE_MTU` env は **server.properties に何も生成しない no-op** であり、かつ後述の通り本症状は MTU と無関係だった。暫定 drop ルールを入れても症状不変 → **MTU は本件の主因ではない**。

### 2.3 ❌ 誤誘導②：「MOTDなし pong は BDS1.26.x の仕様」という既存コメント
- 本番の offline-ping(UNCONNECTED_PONG) を raw デコードすると **33バイト・MOTD(server-ID文字列)が完全欠落**。
  ```
  1c <time8> <serverGUID8> <magic16>  ← ここで終端。MCPE;… 文字列が無い
  ```
- マニフェスト [backend-servers.yaml] のコメントは「BDS1.26.x の MOTDなし最小Pong は仕様」としていたが、これは**監視ツール(itzg/mc-monitor)を Python 製エクスポーターに差し替えた経緯の説明**であり、**実クライアントの接続可否の観点では誤り**だった。

### 2.4 ✅ 決定的比較：素のBDS vs 本番（同一ビルド 1.26.31.1）
| 条件 | pong長 | MOTD |
|------|-------|------|
| 素のBDS（最小設定・フレッシュワールド） | 134B | ✅ `MCPE;VanillaTest;1001;1.26.31;0;10;…;Bedrock level;Survival;…` |
| 本番の全env + **フレッシュワールド** | 139B | ✅ 完全 |
| 本番（実ワールド `Bedrock level`） | **33B** | ❌ **NONE** |

→ **env・server.properties・ビルド・level-name は全て無実**（個別に再現テストで除外）。違いは**ワールドデータのみ**。

### 2.5 ✅ 真因の確定
- 本番デプロイのまま `LEVEL_NAME` を新規ワールドに一時切替（実ワールドdirは温存）すると **MOTD 完全復活**。
- CPU は 23m（アイドル、読込で張り付いてはいない）。RakNet OCR1 応答あり。level.dat に `experiments / experiments_ever_used / saved_with_toggled_experiments` の痕跡。
- **`Documents/Task_mds/restore-bedrock-world.md` の履歴と符合**：このワールドは過去に BDS 1.26.11.1 で `gsl::narrowing_error` クラッシュを起こし、`sushi.ski-server.mcworld` から復元した経緯（levelname の「インポート完了_01」はこの復元由来）。**元々データ破損を抱えたワールド**が、バージョン更新（…→1.26.30.5→1.26.31.1）を経て、今回は「MOTDなし offline-ping → サーバ情報取得不可 → 接続タイムアウト」という形で再発した。

### 主要エビデンス（抜粋コマンド）
```bash
# offline-ping raw デコード（本番=33B/MOTD無, 素BDS=134B/MOTD有）
python3 raknet_probe.py <podIP> 19132
# 素BDS比較
kubectl run bdstest --image=itzg/minecraft-bedrock-server:latest --env=EULA=TRUE ...
# 実ワールド温存のままフレッシュワールドへ切替 → MOTD復活で世界データ起因を確定
kubectl set env deploy/deploy-bedrock -c bedrock LEVEL_NAME=diagworld_tmp
```

### ⚠️ なぜ気付けなかったか（監視の盲点）
- mc-monitor を Python 自作エクスポーターに差し替えた際、「MOTDなしでも healthy=1」とする実装にしたため、**Bedrock が接続不能でも監視は終始 healthy=1** を表示し、異常を検知できなかった。`minecraft_status_players_online_count` が長期間 0 のまま（ログインが17h以上ゼロ）だったが、アラートが無かった。

---

## 🛠️ 3. 対応内容

### 暫定対応（調査中に実施した本番変更）
- [x] `view-distance` 48 → **12**（過大値。トンネル越し前提では妥当化。※pong とは無関係と判明）
- [x] `transport=raknet` を server.properties(pvc) に明示追加（BDS1.26.x で RakNet 利用を明示。※単独では MOTD は直らず＝主因ではないが正しい設定）
- [x] 調査用の一時ワールド切替を**実ワールド `Bedrock level` へ復帰**済み。使い捨てテストpod 掃除済み。
- [ ] ⚠️ ライブ変更により repo マニフェストと**ドリフト**：`VIEW_DISTANCE`(12) / `LEVEL_NAME`(明示) / `transport`(pvc) ＝要 IaC 反映。`RAKNET_FORCE_MTU`(no-op) は削除推奨。

### 真因の精密特定（NBT 解析）
壊れた level.dat（`level.dat.orig`）と正常な level.dat を自作の Bedrock NBT(LE) パーサで diff した結果、ネットワーク広告系フラグが原因と判明：

| level.dat フィールド | 壊れ(orig) | 正常 |
|---|---|---|
| **`LANBroadcast`** | **0** | 1 |
| **`MultiplayerGameIntent`** | **0** | 1 |
| BiomeOverride | `minecraft:`×6（破損） | `minecraft:` |
| InventoryVersion / NetworkVersion | 1.21.132 / 898（旧版） | 1.26.31 / 1001 |
| experiments | 0/0（無効） | — |

→ **`LANBroadcast=0`（+`MultiplayerGameIntent=0`）が真因**。Bedrock の offline-ping(UNCONNECTED_PONG の server-ID文字列) は LAN ブロードキャスト広告機構そのものであり、これが 0 だとサーバ情報を載せない＝MOTD欠落＝クライアント discovery 不能。experiments は無実だった。
旧バージョン由来（InventoryVersion 1.21.132）の世界が版更新を跨いだ際にこのフラグが 0 のまま固定されたと推測。

### 恒久対応（実施済み）
- [x] **level.dat を外科的に修正**：NBT を round-trip 一致を確認の上、`LANBroadcast` と `MultiplayerGameIntent` のみ 0→1 に変更（他フィールドは完全保持）。**コピー(worldfix2)で検証 → MOTD 完全復活 & 「LOADING VANILLA WORLD（新規初期化なし）」を確認**してから本採用。
- [x] **世界の昇格**：修正版を正式 `worlds/Bedrock level` に昇格。元の破損版は `worlds/Bedrock level.orig-broken-20260621` として保全（将来のエンティティ復旧用）。
- [x] **env 整理**：`LEVEL_NAME=Bedrock level` 明示、no-op の `RAKNET_FORCE_MTU` 削除、`VIEW_DISTANCE` は原状(48)に復帰。manifest [k8s/onprem/backend-servers.yaml] へ反映済み。
- [x] **古い `sushi.ski-server.mcworld`(401MB) を pvc から削除**（ユーザー指示）。
- [ ] ⚠️ **エンティティ（モブ/村人/額縁等）は復元不可**：本件修正前から db 側で欠落（旧版→1.26 の移行 or 過去の破損履歴由来。`LANBroadcast` 修正・LOADING 起動でも戻らず）。→ **手動補填で対応**（ユーザー方針）。`Bedrock level.orig-broken-20260621` を残しているため、旧版クライアント等での復旧余地は保持。

### NBT 修正の再現メモ
- ツール: [bedrock-leveldat-fix.py](bedrock-leveldat-fix.py)（同ディレクトリ）。
- 自作 LE-NBT パーサ/シリアライザで round-trip 一致を担保 → byte値のみ変更 → 8byteヘッダ(version+length)を再構成して書き出し。
- 検証は必ず**実ワールドの複製**に対して行い、MOTD(pong)復活と起動ログ `LOADING`（`CREATING`でない）を確認してから昇格すること。

---

## 💡 4. 学び・改善点

- [ ] **監視の是正（最重要）**: Bedrock 健全性を「pong が返る」ではなく **「MOTD(server-ID文字列)を含む正常 pong か」+「offline-ping が実クライアントで discovery 可能か」** で判定する。`players_online==0 が N 時間継続`でアラート。自作エクスポーターが異常をマスクしないようにする。
- [ ] **`:latest` 運用の見直し**: `itzg/minecraft-bedrock-server:latest` は再起動毎に最新へ自動更新され、(1) クライアントとの版ズレ (2) 既存ワールドとの互換崩れ を誘発。**バージョンをピン**し、更新は計画的に。
- [ ] **ワールド健全性の定期チェック**: 破損歴のあるワールドのため、バージョン更新時に「フレッシュワールドとの pong/接続差分」を確認する手順を追加。
- [ ] **再発時の最速切り分け**: 「素のBDS(最小設定) と pong を比較」→ 即座に config/world/version を切り分け可能（本ポストモーテム 2.4 を定石化）。

---

## 付録: 確定した因果連鎖

```
ワールド「Bedrock level」の level.dat: LANBroadcast=0 / MultiplayerGameIntent=0（旧版由来）
  └─ BDS 1.26.31.1 が offline-ping(UNCONNECTED_PONG) に server-ID文字列(MOTD)を載せない（広告無効）
       └─ クライアントがサーバ情報(名称/protocol/version)を取得できない
            └─ サーバ一覧で「情報取得不可」表示、接続ハンドシェイクに進めない（OCR1 がGCEに届かない＝tcpdumpで確認）
                 └─ ユーザー視点で「接続タイムアウト」
（Java版は別経路(TCP/NodePort)のため無影響。MTU/socat/Tailscale/firewall/バージョンは全て無関係）
```

*Created by: Claude Code (調査) / @Tagomori0211*
