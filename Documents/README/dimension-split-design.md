# ディメンション分割設計 — 工業エリア分離

> **作成日**: 2026-05-27
> **対象**: NeoForge 1.21.1、Mekanism + AE2 工業サーバー
> **前提**: Survival 統合サーバー（単一 Helm リリース）、Waystones 導入済み

---

## ⚠️ 設計変更通知（2026-05-27）

**Ad Astra（月面活用）案は破棄する。**

| 項目 | 旧案（破棄） | 新案（採用） |
|------|-------------|-------------|
| 工業ディメンション | Ad Astra MOD の月面を流用 | **vanilla datapack で定義するカスタムディメンション `sushi:industry`** |
| ポータル MOD | Waystones でクロスディメンションワープ | **World Portal（CurseForge projectID `1205026`）** |
| 地形生成 | Ad Astra が自動生成（月面） | **採掘特化のガチ実用地形**（vanilla overworld noise をベースに `sea_level: 20` に変更） |
| MOD 追加数 | 3（resourceful-config, botarium, ad-astra） | 1（World Portal のみ） |
| 破棄理由 | botarium が NeoForge 1.21.1 非対応（Modrinth に NeoForge loader のファイルなし） | — |

> 以下の候補 MOD 一覧は旧設計時の検討資料として残す（変更履歴）。

---

## 目的

オーバーワールドを純粋なサバイバルエリアとして維持し、工業設備（Mekanism、AE2 など）を別ディメンションに隔離することで以下を実現する:

- オーバーワールドの景観保護（工業設備による景観破壊の防止）
- ラグの局所化（大量の Tick 処理を別ディメンションに隔離）
- プレイヤー体験の分離（探検と工業の棲み分け）

---

## 候補 MOD 一覧

### 1. Ad Astra（★推奨）

| 項目 | 内容 |
|------|------|
| **Modrinth ID** | `3ufwT9JF` |
| **CurseForge ID** | `635042` |
| **必須依存** | Resourceful Lib、Resourceful Config、Botarium |
| **追加ディメンション** | 月、火星、金星、水星、氷衛星（Glacio） |
| **利点** | 宇宙探索 + 工業（ロケット製造）の相性が抜群。Mekanism の酸素・水素生成と連携可能 |
| **懸念** | ロケットで移動するため、初期アクセスのハードルがやや高い。Waystones のクロスディメンション設定で緩和可能 |
| **1.21.1 対応** | ✅ `ad-astra`（NeoForge 対応済） |

### 2. The Aether

| 項目 | 内容 |
|------|------|
| **Modrinth ID** | `YhmgMVyu` |
| **CurseForge ID** | `255308` |
| **追加ディメンション** | 天空の楽園（The Aether） |
| **利点** | 安定したカスタムディメンション、ボス・ダンジョンあり |
| **懸念** | 工業テーマとの乖離。自然保護エリアとしては優秀だが、工業地帯としては違和感 |
| **1.21.1 対応** | ✅ `aether`（NeoForge 対応） |

### 3. Deeper and Darker

| 項目 | 内容 |
|------|------|
| **Modrinth ID** | `fnAffV0n` |
| **CurseForge ID** | `667903` |
| **追加ディメンション** | 深淵（The Otherside）— 古代都市の地下に広がる暗黒ディメンション |
| **利点** | 既存の YUNG's Better シリーズとの親和性。地下に自然に統合 |
| **懸念** | スカルク系 Mob がスポーンし、工業地帯としての安全確保が難しい |
| **1.21.1 対応** | ✅ `deeperdarker`（NeoForge 対応） |

### 4. Twilight Forest

| 項目 | 内容 |
|------|------|
| **CurseForge ID** | `227639` |
| **追加ディメンション** | 黄昏の森 |
| **利点** | 最も有名なカスタムディメンション、進行度システムあり |
| **懸念** | **1.21.1 未対応**（1.20.1 が最新安定版） |
| **1.21.1 対応** | ❌ |

### 5. The Bumblezone

| 項目 | 内容 |
|------|------|
| **Modrinth ID** | `EeYl6MfQ` |
| **追加ディメンション** | 蜂の世界 |
| **利点** | ユニークな生態系、資源豊富 |
| **懸念** | 工業テーマとの乖離が大きい |
| **1.21.1 対応** | ✅ |

---

## 推奨方針: Ad Astra を工業ディメンションとして活用

### 選定理由

1. **Mekanism との連携が自然**: 酸素供給・水素ロケット燃料・発電設備など、工業 MOD の延長線上に宇宙開発が位置する
2. **隔離の正当性**: 「月面に工業基地を建設する」という設定は没入感が高く、プレイヤーにとって自然な動機付けになる
3. **Waystones クロスディメンション対応**: Waystone を月面に設置することで、ロケット不要のファストトラベルが可能
4. **段階的解放**: ロケット製造（Mekanism の冶金インフラが必要）→ 月到達 → 工業拡張 の自然なプログレッション

### 構成案

```
オーバーワールド (サバイバルエリア)
  ├── スポーン地点: Waystone（オーバーワールド間移動用）
  ├── 資源採掘エリア
  └── 初期工業エリア（ロケット発射台）
  
月 (工業メインベース)
  ├── 酸素供給設備（Mekanism 電解装置）
  ├── AE2 ストレージシステム
  ├── Mekanism 大規模発電（核融合炉など）
  ├── 自動化工場（Mekanism 5x 鉱石処理）
  └── Waystone（オーバーワールドと直結）
```

---

## Datapack + World Portal 構成（採用方式）

### ディレクトリ構造

```
k8s/onprem/datapacks/industry_dim/
├── pack.mcmeta                          # datapack メタデータ
└── data/
    └── sushi/
        ├── dimension/
        │   └── industry.json            # ディメンションタイプ・generator 定義
        └── worldgen/
            └── noise_settings/
                └── industry.json         # vanilla overworld noise ベース（sea_level=20）
```

### パラメーター定義

| パラメーター | 採用値 | 根拠 |
|-------------|--------|------|
| `sea_level` | **20** | vanilla の 63 → 20 に下げ、海面積を極小化。採掘特化のガチ実用地形 |
| `biome_source` | `minecraft:multi_noise` + `minecraft:overworld` preset | 全バイオームを overworld 同様に生成 |
| `default_block` | `minecraft:stone` | vanilla 同一 |
| `default_fluid` | `minecraft:water` | vanilla 同一 |

### Step 1: Datapack 作成（本リポジトリに含む）

- `k8s/onprem/datapacks/industry_dim/` ディレクトリに全ファイルを配置
- `pack_format: 61`（1.21.1 準拠）
- vanilla overworld noise_settings を misode/mcmeta の `data` branch から取得し、`sed` で `"sea_level": 63` → `"sea_level": 20` に変更

### Step 2: MOD 導入（CurseForge 統一）

- `CF_PROJECTS` に `1205026`（World Portal）を追記
- `MODRINTH_*` は使用不可（Modrinth に World Portal なし）
- Modrinth env は削除不要（他の MOD 解決用に維持）
- **全 MOD は CurseForge から取得**
- 必須依存: World Portal が NEKit に依存する可能性あり。欠損エラーが出た場合は追加調査

### Step 3: Datapack 配置

サーバーボリュームに datapack を配置（helper Pod → PVC コピー）:

```bash
# datapack tar を ConfigMap 経由で PVC に展開
# 詳細は deploy 時に調査・実施
```

### Step 4: デプロイ（安全停止手順）

```bash
# ----- 安全停止 -----
ssh k3s-worker 'sudo kubectl scale deployment deploy-survival -n minecraft --replicas=0'
# 全 Pod 基準完了確認（kubectl get pods で Terminating → 消失確認）

# ----- manifest rsync -----
rsync -avz k8s/ --exclude='.git' k3s-worker:/opt/manifests/Minecraft_java_k3s/k8s/

# ----- Helm upgrade -----
ssh k3s-worker 'sudo helm upgrade --install survival /opt/manifests/Minecraft_java_k3s/k8s/onprem/helm/minecraft-server -f /opt/manifests/Minecraft_java_k3s/k8s/onprem/helm/values-survival.yaml -n minecraft'

# ----- Datapack 配置（PVC に helper Pod でコピー）-----
# Server が Running になった後に datapack tar を ConfigMap からマウントし、
# kubectl exec cp で PVC 内の world/datapacks/ にコピー。実施タイミングは次の指示まで保留

# ----- 起動 -----
ssh k3s-worker 'sudo kubectl scale deployment deploy-survival -n minecraft --replicas=1'
```

### Step 5: 動作確認

1. `docker logs`（または `kubectl logs`）で datapack ロード確認
2. World Portal を使い `/execute in sushi:industry run tp @s 0 100 0` でディメンション生成テスト

---

## リスクと対策（Datapack 方式）

| リスク | 対策 |
|--------|------|
| World Portal の必須依存漏れ | MOD 追加エラー時にクラッシュログから依存名を特定し、CF_PROJECTS に追記 |
| datapack がロードされない | `kubectl logs` で確認。`pack_format: 61` が正しいか再確認 |
| ディメンション `sushi:industry` が未生成 | プレイヤーが World Portal または datapack をロードした状態で `/execute in sushi:industry ...` を実行して生成を誘発 |
| 低水位で砂漠が巨大化しすぎる | `biome_source` を `checkerboard` に変更するなど調整余地あり |

---

## 参考

- misode/mcmeta data branch: `https://github.com/misode/mcmeta/tree/data`
- World Portal CurseForge: `https://www.curseforge.com/minecraft/mc-mods/world-portals`
- NeoForge 1.21.1 Pack Format: `61`
