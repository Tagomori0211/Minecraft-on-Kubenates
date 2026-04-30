---
description: Restore Bedrock World from mcworld backup
---

このワークフローは、Bedrock Dedicated Server (BDS) のワールドデータを `.mcworld` バックアップからリストアします。
※実行前に `k8s/onprem/onprem_kubeconfig.yaml` が存在し、バックアップファイルがカレントディレクトリにあることを確認してください。

1. **BDS 停止と確認**
// turbo
```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml scale deploy/deploy-bedrock -n minecraft --replicas=0
```
Podが完全に停止するまで待ちます。
```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml get pods -n minecraft -l app=mc-bedrock
```

2. **作業用 Pod (Helper) の起動**
// turbo
```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml run restore-helper --image=alpine:latest --restart=Never --overrides='{"spec": {"containers": [{"name": "restore-helper", "image": "alpine:latest", "command": ["sleep", "3600"], "volumeMounts": [{"name": "data", "mountPath": "/data"}]}], "volumes": [{"name": "data", "persistentVolumeClaim": {"claimName": "pvc-bedrock"}}]}}' -n minecraft
```
PodがReadyになるまで待機（約10〜30秒）。
```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml wait pod/restore-helper -n minecraft --for=condition=Ready --timeout=60s
```

3. **ツールのインストールと既存データの退避**
// turbo
```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml exec restore-helper -n minecraft -- sh -c 'apk add --no-cache unzip && cd /data/worlds && if [ -d "Bedrock level" ]; then mv "Bedrock level" "Bedrock level.$(date +%Y%m%d_%H%M%S).bak" && echo "Existing world backed up"; fi'
```

4. **バックアップファイルのコピー**
リストアする `.mcworld` ファイル（例: `sushi.ski-server.mcworld`）を Pod にコピーします。
// turbo
```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml cp sushi.ski-server.mcworld minecraft/restore-helper:/data/sushi.ski-server.mcworld
```

5. **ワールドの展開とリストア**
// turbo
```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml exec restore-helper -n minecraft -- sh -c 'mkdir -p "/data/worlds/Bedrock level" && cd "/data/worlds/Bedrock level" && unzip -o /data/sushi.ski-server.mcworld && [ -f "world_behavior_packs.json" ] || echo "[]" > "world_behavior_packs.json" && [ -f "world_resource_packs.json" ] || echo "[]" > "world_resource_packs.json" && chown -R 1000:1000 /data'
```

6. **クリーンアップと Pod の削除**
// turbo
```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml delete pod restore-helper -n minecraft --force
```

7. **BDS 起動とログ確認**
// turbo
```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml scale deploy/deploy-bedrock -n minecraft --replicas=1 && kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml rollout status deploy/deploy-bedrock -n minecraft
```
起動ログを確認して `Server started.` が表示されれば成功です。
```bash
kubectl --kubeconfig=k8s/onprem/onprem_kubeconfig.yaml logs deploy/deploy-bedrock -c bedrock -n minecraft --tail=20
```

8. **後処理**
誤ってバイナリをプッシュしないよう、カレントディレクトリの `.mcworld` を削除することを推奨します。
```bash
rm sushi.ski-server.mcworld
```
