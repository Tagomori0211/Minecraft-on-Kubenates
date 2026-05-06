---
description: Restore Bedrock World from mcworld backup
---

このワークフローは、Bedrock Dedicated Server (BDS) のワールドデータを `.mcworld` バックアップからリストアします。

**前提:**
- `k8s/onprem/onprem_kubeconfig.yaml` が存在すること
- リストアする `.mcworld` ファイルがカレントディレクトリにあること
- BDS Deployment: `deploy-bedrock` / Namespace: `minecraft` / PVC: `pvc-bedrock`

---

## 1. BDS 停止

```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml \
  scale deploy/deploy-bedrock -n minecraft --replicas=0
```

Pod が完全に停止するまで待ちます。

```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml \
  get pods -n minecraft -l app=mc-bedrock
```

---

## 2. 作業用 Pod (Helper) の起動

```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml \
  run restore-helper --image=alpine:latest --restart=Never \
  --overrides='{"spec": {"containers": [{"name": "restore-helper", "image": "alpine:latest", "command": ["sleep", "3600"], "volumeMounts": [{"name": "data", "mountPath": "/data"}]}], "volumes": [{"name": "data", "persistentVolumeClaim": {"claimName": "pvc-bedrock"}}]}}' \
  -n minecraft
```

Pod が Ready になるまで待機します。

```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml \
  wait pod/restore-helper -n minecraft --for=condition=Ready --timeout=60s
```

---

## 3. ツールインストールと既存データの退避

```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml \
  exec restore-helper -n minecraft -- sh -c \
  'apk add --no-cache unzip && cd /data/worlds && if [ -d "Bedrock level" ]; then mv "Bedrock level" "Bedrock level.$(date +%Y%m%d_%H%M%S).bak" && echo "Existing world backed up"; fi'
```

---

## 4. バックアップファイルのコピー

リストアする `.mcworld` ファイル（例: `sushi.ski-server.mcworld`）を Pod にコピーします。

```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml \
  cp sushi.ski-server.mcworld minecraft/restore-helper:/data/sushi.ski-server.mcworld
```

---

## 5. ワールドの展開とリストア

```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml \
  exec restore-helper -n minecraft -- sh -c \
  'mkdir -p "/data/worlds/Bedrock level" && cd "/data/worlds/Bedrock level" && unzip -o /data/sushi.ski-server.mcworld && [ -f "world_behavior_packs.json" ] || echo "[]" > "world_behavior_packs.json" && [ -f "world_resource_packs.json" ] || echo "[]" > "world_resource_packs.json" && chown -R 1000:1000 /data && echo "Done"'
```

**注意:** `world_resource_packs.json` は VV（Vibrant Visuals）との互換性のため `[]` を維持すること。リソースパックはクライアント側グローバルリソースパックとして適用すること。

---

## 6. クリーンアップと Pod 削除

```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml \
  exec restore-helper -n minecraft -- rm -f /data/sushi.ski-server.mcworld
```

```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml \
  delete pod restore-helper -n minecraft --force
```

---

## 7. BDS 起動と確認

BDS 再起動は rollout restart 禁止。replicas=0 → 1 の順で行います。

```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml \
  scale deploy/deploy-bedrock -n minecraft --replicas=1
```

```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml \
  rollout status deploy/deploy-bedrock -n minecraft
```

---

## 8. 起動ログの確認

```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml \
  logs deploy/deploy-bedrock -c bedrock -n minecraft --tail=30
```

確認項目:
- `Level Name: Bedrock level` が表示されること
- `Server started.` が表示されること
- エラーやクラッシュがないこと

---

## ロールバック手順（リストアに失敗した場合）

```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml \
  scale deploy/deploy-bedrock -n minecraft --replicas=0
```

```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml \
  run restore-helper --image=alpine:latest --restart=Never \
  --overrides='{"spec": {"containers": [{"name": "restore-helper", "image": "alpine:latest", "command": ["sleep", "3600"], "volumeMounts": [{"name": "data", "mountPath": "/data"}]}], "volumes": [{"name": "data", "persistentVolumeClaim": {"claimName": "pvc-bedrock"}}]}}' \
  -n minecraft
```

```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml \
  wait pod/restore-helper -n minecraft --for=condition=Ready --timeout=60s
```

```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml \
  exec restore-helper -n minecraft -- sh -c \
  'cd /data/worlds && rm -rf "Bedrock level" && mv "Bedrock level.*.bak" "Bedrock level" && echo "Rollback done"'
```

```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml \
  delete pod restore-helper -n minecraft --force
```

```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml \
  scale deploy/deploy-bedrock -n minecraft --replicas=1
```

---

## 注意事項

- `VERSION=LATEST` のままで起動すること（クライアントバージョンと一致させる）
- `LEVEL_NAME` が変わっていたら `Bedrock level` に戻すこと（`server.properties` を確認）
- 破損バックアップ（`.bak`）はストレージに余裕があれば残しておく（原因分析用）
