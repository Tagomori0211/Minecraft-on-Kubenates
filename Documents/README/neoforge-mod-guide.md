# NeoForgeサーバーへのMOD追加ガイド (詳細版)

このドキュメントでは、本プロジェクトのHelm Chart (`minecraft-server`) を使用して、NeoForgeサーバーにMODを追加・管理する方法を解説します。

---

## 1. 設定ファイルの場所と役割

本プロジェクトでは、設定を以下の場所で管理しています。混同しないよう注意してください。

- **`ROOT/.env`**: プロジェクト全体の共通設定（GCPプロジェクトID、Tailscaleキー、Velocity共通シークレットなど）を保持する秘密ファイルです。通常、ここを編集してMODを追加することはありません。
- **`k8s/onprem/helm/minecraft-server/values.yaml`**: 全Javaサーバーの **共通デフォルト設定** です。ここにMODを追加すると、SurvivalとIndustryの両方に反映されます。
- **`k8s/onprem/helm/values-survival.yaml`**: **生活鯖 (Survival)** 専用の設定。
- **`k8s/onprem/helm/values-industry.yaml`**: **工業鯖 (Industry)** 専用の設定。

---

## 2. MODの探し方 (Modrinth)

本環境では [Modrinth](https://modrinth.com/) に対応しています。

### Webで探す
1. Modrinthのサイトへ行き、`Categories: NeoForge` および `Versions: 1.21.1` でフィルターします。
2. 追加したいMODのページURL末尾にある **slug** (例: `xaeros-minimap`) をメモします。

### CLIで探す (サーバー上で実行可能)
```bash
# 例: radarに関連するMODを探す
curl -sG 'https://api.modrinth.com/v2/search' \
  --data-urlencode 'query=radar' \
  --data-urlencode 'facets=[["categories:neoforge"],["versions:1.21.1"]]' \
  | python3 -c "import sys, json; [print(f\"{h['title']}: {h['slug']}\") for h in json.load(sys.stdin)['hits']]"
```

---

## 3. MOD導入の具体例: レーダーMOD (Xaero's Minimap)

### ケースA: 工業鯖 (Industry) だけに導入する場合
`k8s/onprem/helm/values-industry.yaml` を編集します。

```yaml
server:
  mods:
    - "xaeros-minimap"
    # 他にもあれば追加
    # - "another-mod-slug"
```

### ケースB: 生活鯖と工業鯖、両方に導入する場合
`k8s/onprem/helm/minecraft-server/values.yaml` (共通設定) を編集するか、両方の `values-*.yaml` に記述します。

```yaml
server:
  mods:
    - "xaeros-minimap"
```

---

## 4. 設定の反映手順

ファイルを編集・保存したら、以下のコマンドでクラスターに適用します。

```bash
# 生活鯖への反映
helm --kubeconfig k8s/onprem/onprem_kubeconfig.yaml upgrade mc-survival k8s/onprem/helm/minecraft-server -f k8s/onprem/helm/values-survival.yaml -n minecraft

# 工業鯖への反映
helm --kubeconfig k8s/onprem/onprem_kubeconfig.yaml upgrade mc-industry k8s/onprem/helm/minecraft-server -f k8s/onprem/helm/values-industry.yaml -n minecraft
```

適用後、サーバーが再起動し、起動ログに `Downloaded /data/mods/xaeros-minimap-xxx.jar` と表示されれば成功です。

---

## 5. 補足: 既に導入済みの必須MOD
以下のMODは、システムの動作上、テンプレート側で自動的に追加されるようになっています。これらを `mods` リストに手動で書く必要はありません。

- **neoforged-velocity-support**: Velocityプロキシ経由の接続を許可するために自動注入されます。
