# minecraft Pod 安全再起動（OOM回避）

`minecraft` namespace の重量級 deployment（`deploy-mod` / `deploy-survival` / `deploy-lobby`）を再起動する手順。

**⚠️ `kubectl rollout restart` 禁止**。旧pod・新podが一瞬同時稼働する瞬間に合計メモリ要求が物理メモリを超え、OOMキラーで落ちる（mod serverは30Gi割当）。必ず `replicas=0` → `1` を踏むこと。

## 対象 release / deployment / label / values 対応表

| Release | Deployment | label `app=` | values |
|---|---|---|---|
| industry (MOD) | deploy-mod | mc-mod | values-industry.yaml |
| survival | deploy-survival | mc-survival | values-survival.yaml |
| lobby | deploy-lobby | mc-lobby | values-lobby.yaml |

## 手順

1. **対象deployment停止**
   ```bash
   ssh k3s-worker "sudo kubectl scale deployment/<deploy-name> -n minecraft --replicas=0"
   ```

2. **pod完全終了を待機**
   ```bash
   ssh k3s-worker "sudo kubectl wait --for=delete pod -l app=<label> -n minecraft --timeout=180s"
   ```

3. **（values変更ありの場合）chart 同期 → helm upgrade**
   ```bash
   rsync -avz --delete /home/shinari/Minecraft_java_k3s/k8s/onprem/helm/ k3s-worker:~/k8s_manifests/helm/
   ssh k3s-worker "helm upgrade <release> ~/k8s_manifests/helm/minecraft-server -f ~/k8s_manifests/helm/values-<release>.yaml -n minecraft"
   ```
   helm upgrade で `deployment.spec.replicas=1` が再適用され、新pod が起動する。

4. **（values変更なしの場合）replicas=1 復元**
   ```bash
   ssh k3s-worker "sudo kubectl scale deployment/<deploy-name> -n minecraft --replicas=1"
   ```

5. **起動確認**
   ```bash
   ssh k3s-worker "sudo kubectl get pods -n minecraft -l app=<label>"
   ssh k3s-worker "sudo kubectl logs -n minecraft -l app=<label> -c minecraft --tail=120 -f"
   ```
   readiness が `2/2` になればOK。`mc-monitor` サイドカーも含めて両方Ready。

## トラブルシュート
- pod が `ImagePullBackOff` / `Error` の場合は `kubectl describe pod` を確認
- MOD ダウンロード失敗時は `Modrinth` / `CurseForge` API のレート制限疑い、5分待ってから再起動
