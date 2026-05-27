# ディメンション分割設計 — 工業エリア分離

> **作成日**: 2026-05-27
> **対象**: NeoForge 1.21.1、Mekanism + AE2 工業サーバー
> **前提**: Survival 統合サーバー（単一 Helm リリース）、Waystones 導入済み

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

## 実装手順

### Step 1: MOD 追加

`values-survival.yaml` の `server.mods` に以下を追加:

```yaml
mods:
  # --- Ad Astra + 依存 ---
  - "resourceful-lib"         # 既存を確認（既にリストにあるはず）
  - "resourceful-config"
  - "botarium"
  - "ad-astra"
```

### Step 2: Cross-Dimension Waystones 設定

Ad Astra のディメンション間で Waystone が機能するよう、`waystones-common.toml` コンフィグを調整。

Waystones はデフォルトでクロスディメンションのワープに対応しているため、特別な設定変更は不要な可能性が高い。

### Step 3: ワールド保護設定

工業ディメンション専用の Chunky Pregenerator は不要（月は Ad Astra が生成するため）。

必要に応じて、Mekanism の放射線・廃棄物のクロスディメンション漏洩を防ぐコンフィグ調整を検討。

### Step 4: デプロイ

```bash
# replicas=0 → helm upgrade → replicas=1（安全手順）
ssh k3s-worker 'sudo kubectl scale deployment deploy-survival -n minecraft --replicas=0'
ssh k3s-worker 'sudo kubectl get pods -n minecraft -w'  # 停止確認
ssh k3s-worker 'cd /opt/manifests/Minecraft_java_k3s/k8s/onprem/helm && sudo helm upgrade --install survival ./minecraft-server -f values-survival.yaml -n minecraft'
ssh k3s-worker 'sudo kubectl scale deployment deploy-survival -n minecraft --replicas=1'
```

---

## リスクと対策

| リスク | 対策 |
|--------|------|
| Ad Astra のディメンションが重い（月面生成の負荷） | 基本はプレイヤーが訪れてから生成。プリジェネレートする場合は範囲を限定 |
| クロスディメンション Waystones が機能しない | `waystones-common.toml` でディメンションブラックリストを確認 |
| 既存ワールドに Ad Astra 追加時のクラッシュ | **新規ワールド生成済み**のため、リスクは低い。ただし初回ロード時に構造物生成でラグが発生する可能性あり |
| Modrinth 依存の解決失敗 | `MODRINTH_DOWNLOAD_DEPENDENCIES: REQUIRED` 設定済みのため、自動解決されるはず |

---

## 参考

- Ad Astra Modrinth: `https://modrinth.com/mod/ad-astra`
- Waystones クロスディメンション: デフォルト有効。制限する場合は `waystones-common.toml` の `dimensional_warp_allowed` を確認