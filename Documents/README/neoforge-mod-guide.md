# NeoForgeサーバーへのMOD追加ガイド

このドキュメントでは、本プロジェクトの Helm Chart (`minecraft-server`) を使用して、NeoForgeサーバーにMODを追加・管理する方法を解説します。

---

## 1. 設定ファイルの場所と役割

| ファイル | 役割 |
|---------|------|
| `ROOT/.env` | プロジェクト全体の共通設定（認証情報等）。MOD 追加では通常編集しない |
| `k8s/onprem/helm/minecraft-server/values.yaml` | 全 Java サーバーの共通デフォルト設定 |
| `k8s/onprem/helm/values-survival.yaml` | 生活鯖（Survival）専用設定 |
| `k8s/onprem/helm/values-industry.yaml` | 工業鯖（Industry）専用設定 |
| `k8s/onprem/helm/values-lobby.yaml` | ロビー（Lobby）専用設定 |

---

## 2. MODの探し方 (Modrinth)

本環境は [Modrinth](https://modrinth.com/) に対応しています。

### Webで探す
1. Modrinthのサイトへ行き、`Categories: NeoForge` および `Versions: 1.21.1` でフィルターする
2. 追加したいMODのページURL末尾にある **slug**（例: `xaeros-minimap`）をメモする

### CLIで探す
```bash
curl -sG 'https://api.modrinth.com/v2/search' \
  --data-urlencode 'query=radar' \
  --data-urlencode 'facets=[["categories:neoforge"],["versions:1.21.1"]]' \
  | python3 -c "import sys, json; [print(f\"{h['title']}: {h['slug']}\") for h in json.load(sys.stdin)['hits']]"
```

---

## 3. MOD導入の具体例

### ケースA: 工業鯖（Industry）だけに導入する場合

`k8s/onprem/helm/values-industry.yaml` を編集する。

```yaml
server:
  mods:
    - "xaeros-minimap"
```

### ケースB: 生活鯖と工業鯖、両方に導入する場合

`k8s/onprem/helm/minecraft-server/values.yaml`（共通設定）を編集するか、両方の `values-*.yaml` に記述する。

```yaml
server:
  mods:
    - "xaeros-minimap"
```

---

## 4. 設定の反映手順

ファイルを編集・保存したら、以下のコマンドでクラスターに適用する。

```bash
# 生活鯖への反映
helm --kubeconfig k8s/onprem/onprem_kubeconfig.yaml upgrade mc-survival \
  k8s/onprem/helm/minecraft-server \
  -f k8s/onprem/helm/values-survival.yaml \
  -n minecraft

# 工業鯖への反映
helm --kubeconfig k8s/onprem/onprem_kubeconfig.yaml upgrade mc-industry \
  k8s/onprem/helm/minecraft-server \
  -f k8s/onprem/helm/values-industry.yaml \
  -n minecraft

# ロビーへの反映
helm --kubeconfig k8s/onprem/onprem_kubeconfig.yaml upgrade mc-lobby \
  k8s/onprem/helm/minecraft-server \
  -f k8s/onprem/helm/values-lobby.yaml \
  -n minecraft
```

適用後、サーバーが再起動し、起動ログに `Downloaded /data/mods/xaeros-minimap-xxx.jar` と表示されれば成功です。

---

## 5. 補足: 既に導入済みの必須MOD

以下のMODは、システムの動作上、テンプレート側で自動的に追加されるようになっています。`mods` リストに手動で書く必要はありません。

- **neoforged-velocity-support**: Velocity プロキシ経由の接続を許可するために自動注入されます

---

## 6. トラブルシューティング

### MODが読み込まれない

```bash
# 工業鯖のログを確認
kubectl --kubeconfig k8s/onprem/onprem_kubeconfig.yaml \
  logs deploy/mc-industry -n minecraft --tail=50
```

### Pod が再起動ループに入った場合

MOD のバージョン非互換が原因である可能性が高い。Modrinth で `Versions: 1.21.1` + `Loaders: NeoForge` の組み合わせを確認すること。

```bash
# Pod 状態確認
kubectl --kubeconfig k8s/onprem/onprem_kubeconfig.yaml get pods -n minecraft
```
