---
description: Install Bedrock Addon (.mcpack / .mcaddon) to k3s Bedrock Server
---

このワークフローは、`.mcpack` または `.mcaddon` 形式の Bedrock 専用アドオンをオンプレミスの k3s Bedrock サーバーに導入する手順をまとめます。

## 事前準備
導入したいアドオンファイル（`.mcpack` や `.mcaddon`）をカレントディレクトリ（例: `MC_addon-raw/` 等）に配置し、中身の `manifest.json` を事前に確認して UUID と Version を特定してください。

1. **アドオンの解凍と構造確認**
アドオンは ZIP 形式のため、一旦手元で解凍します。
```bash
mkdir -p tmp_addon
unzip -o MC_addon-raw/YOUR_ADDON.mcpack -d tmp_addon/
cat tmp_addon/manifest.json
```
`manifest.json` 内の `header.uuid` と `header.version` の値、また `modules` が `resources`（リソースパック）か `data`（ビヘイビアーパック）かを確認します。

2. **クラスタ上のBedrock Podへ転送**
解凍したフォルダを k3s ワーカーノードに SCP し、そこから対象の Pod に配置します。
// turbo
```bash
POD=$(kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml get pod -n minecraft -l app=mc-bedrock -o jsonpath='{.items[0].metadata.name}')
scp -r tmp_addon k3s-worker:/tmp/addon_extracted
```
リソースパックの場合は `resource_packs`、ビヘイビアーパックの場合は `behavior_packs` フォルダの下に配置します（以下はリソースパックの例）。
// turbo
```bash
ssh k3s-worker "sudo k3s kubectl exec -n minecraft $POD -c bedrock -- mkdir -p '/data/worlds/Bedrock level/resource_packs/addon_folder'"
ssh k3s-worker "sudo k3s kubectl cp -n minecraft /tmp/addon_extracted $POD:'/data/worlds/Bedrock level/resource_packs/addon_folder' -c bedrock"
```

3. **JSONファイルへの登録**
ワールドにパックを適用するため、`/data/worlds/Bedrock level/world_resource_packs.json`（または `world_behavior_packs.json`）を編集し、先ほど確認した UUID と Version を追加します。

手元で JSON を作成し、転送するのが安全です。
```bash
echo '[{"pack_id": "YOUR-UUID-HERE", "version": [1, 0, 0]}]' > tmp_packs.json
scp tmp_packs.json k3s-worker:/tmp/packs.json
ssh k3s-worker "sudo k3s kubectl cp -n minecraft /tmp/packs.json $POD:'/data/worlds/Bedrock level/world_resource_packs.json' -c bedrock"
```

4. **パーミッションの修正**
コンテナ内で権限エラーが起きないよう、オーナーを `1000:1000` に修正します。
// turbo
```bash
ssh k3s-worker "sudo k3s kubectl exec -n minecraft $POD -c bedrock -- chown -R 1000:1000 '/data/worlds/Bedrock level'"
```

5. **サーバーの再起動**
Podを再起動してアドオンを読み込ませます。
// turbo
```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml delete pod -n minecraft -l app=mc-bedrock
```

6. **一時ファイルの削除**
```bash
rm -rf tmp_addon tmp_packs.json
ssh k3s-worker "rm -rf /tmp/addon_extracted /tmp/packs.json"
```
