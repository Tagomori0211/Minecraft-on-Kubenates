# NeoForgeサーバーへのMOD追加ガイド

このドキュメントでは、本プロジェクトのHelm Chart (`minecraft-server`) を使用して、NeoForgeサーバーにMODを追加・管理する方法について説明します。

---

## 1. Modrinthからの自動ダウンロード (推奨)

最も簡単で管理しやすい方法です。`itzg/minecraft-server` イメージの機能を利用して、起動時にModrinthからMODを自動取得します。

### 設定画面 (`values-survival.yaml` など)
`MODRINTH_PROJECTS` 環境変数を追加するようにマニフェストを構成、または直接 `values` に追記します。
※現状のテンプレートでは、特定のMOD（Velocity Support等）が条件付きで追加されるようになっていますが、汎用的に追加する場合は以下のように記述します。

#### 手順
1. `k8s/onprem/helm/values-survival.yaml` を開く。
2. 他のMODを追加したい場合、`env` セクション（未定義の場合は追加）に `MODRINTH_PROJECTS` を記述します。

```yaml
# 例: values-survival.yaml への追記イメージ
server:
  # ... 既存設定
  extraEnv:
    - name: MODRINTH_PROJECTS
      value: "fabric-api,sodium,iris" # ModrinthのslugまたはIDをカンマ区切りで指定
```

> [!NOTE]
> 現在の `deployment.yaml` テンプレートでは `extraEnv` を処理するロジックが必要です。必要に応じて `templates/deployment.yaml` に `{{- with .Values.server.extraEnv }}{{ toYaml . | nindent 12 }}{{ end }}` を追記してください。

---

## 2. 独自のMODファイルを直接配置する場合

Modrinthにない自作MODや、特定のビルド済みJARファイルを使用する場合です。

### 手順
1. **一時的なPod (`edit-helper` 等) を利用してアップロード**
   PVC (`pvc-survival` 等) をマウントした管理用Podに `kubectl cp` でファイルを送ります。

   ```bash
   # ローカルのMODファイルをサーバーのmodsフォルダへコピー
   kubectl cp my-custom-mod.jar minecraft/edit-helper:/data/mods/
   ```

2. **サーバーの再起動**
   ファイルの配置後、Deploymentを再起動することでMODが読み込まれます。

   ```bash
   kubectl rollout restart deployment deploy-survival -n minecraft
   ```

---

## 3. 依存関係とバージョンの確認

NeoForgeでは、MODが要求する **NeoForge本体のバージョン** と **Minecraftのバージョン** が一致している必要があります。

- **Minecraft Version**: `1.21.1` (固定中)
- **NeoForge Version**: `latest` (または `values.yaml` で指定したバージョン)

新しいMODを追加した後にサーバーが起動しない（CrashLoopBackOff）場合は、ログを確認してください。

```bash
kubectl logs -f deploy-survival-<pod-id> -c minecraft -n minecraft
```

---

## 4. プロキシ (Velocity) 対応の注意点

新しくMODサーバーを追加する場合、以下の要素が必須です。

- **Velocity Support MOD**: Velocityからの接続を許可するために必須です（自動導入設定済み）。
- **forwarding.secret**: プロキシとの認証用シークレットです（`initContainer` で自動配置設定済み）。
- **オンラインモード**: `ONLINE_MODE: "FALSE"` に設定する必要があります（プロキシが認証を担当するため）。
