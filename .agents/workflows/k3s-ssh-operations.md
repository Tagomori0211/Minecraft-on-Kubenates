---
description: k3s クラスター操作スキル（SSH経由）
---

# k3s SSH 操作スキル

## ⚠️ 重要制約（必ず守ること）

**Claude Code クライアントマシンでは以下を直接実行できない:**
- `kubectl` — k3s-worker / k3s-monitoring に SSH してから実行すること
- `helm` — k3s-worker に SSH してから実行すること
- `gcloud` — **k3s-worker にのみインストール済み**（クライアント・k3s-monitoring には未インストール）

**すべての k3s 操作は SSH 経由で行う。**

---

## 接続先ホスト一覧

| ホスト名 | 役割 | Tailscale IP | kubectl | gcloud |
|---------|------|-------------|---------|--------|
| `k3s-worker` | ゲームサーバー (minecraft ns) | 100.107.122.45 | `sudo kubectl` ✅ | ✅ |
| `k3s-monitoring` | Prometheus / Grafana | 100.105.190.5 | `sudo kubectl` ✅ | ❌ |

SSH ホスト名は `~/.ssh/config` で解決済み。

---

## 基本パターン

### 単発コマンド

```bash
ssh k3s-worker 'sudo kubectl get pods -n minecraft'
```

```bash
ssh k3s-monitoring 'sudo kubectl get pods -n monitoring-prometheus'
```

### 複数コマンドの連結（SSH内では && / ; 可）

CLAUDE.md の `&&` 禁止はクライアント側ローカルシェルへの制約。
SSH の引数文字列内部では可読性・実用性のために `&&` を使ってよい。

```bash
ssh k3s-worker 'sudo kubectl get pods -n minecraft && sudo kubectl get pvc -n minecraft'
```

### 変数展開が必要な場合（クライアント側で展開 → ダブルクォート）

```bash
POD="deploy-bedrock-xxxxx"
ssh k3s-worker "sudo kubectl exec -n minecraft $POD -c bedrock -- send-command 'say hello'"
```

### 変数展開を SSH 先で行う場合（シングルクォートで保護）

```bash
ssh k3s-worker 'POD=$(sudo kubectl get pod -n minecraft -l app=mc-bedrock -o jsonpath="{.items[0].metadata.name}") && echo $POD'
```

---

## よく使う操作集

### Pod 一覧確認

```bash
ssh k3s-worker 'sudo kubectl get pods -n minecraft -o wide'
```

```bash
ssh k3s-monitoring 'sudo kubectl get pods -n monitoring-prometheus'
```

### ログ確認

```bash
ssh k3s-worker 'sudo kubectl logs deploy/deploy-bedrock -c bedrock -n minecraft --tail=30'
```

```bash
ssh k3s-worker 'sudo kubectl logs deploy/mc-survival -n minecraft --tail=20'
```

### ⚠️ 全サーバー共通: Pod 再起動は必ず replicas 0 → 1（rollout restart 絶対禁止）

`minecraft` namespace の **すべての Deployment**（lobby / survival / mod / bedrock）に適用。

**理由:** `rollout restart` や rolling update は旧Pod・新Podが瞬間的に並走し、合計メモリ要求が物理メモリを超えて OOMキラー発動。特に mod(30Gi)・survival(16Gi) で顕著。

```bash
# ❌ 禁止
ssh k3s-worker 'sudo kubectl rollout restart deployment/deploy-survival -n minecraft'

# ✅ 正しい手順（survival の例、deploy-lobby / deploy-mod / deploy-bedrock も同様）
ssh k3s-worker 'sudo kubectl scale deployment deploy-survival -n minecraft --replicas=0'
# 旧Podの完全終了を確認してから
ssh k3s-worker 'sudo kubectl scale deployment deploy-survival -n minecraft --replicas=1'
```

helm upgrade を伴う場合:
```bash
# 1. 先に停止
ssh k3s-worker 'sudo kubectl scale deployment deploy-mod -n minecraft --replicas=0'
# 2. 旧Pod完全終了を確認
ssh k3s-worker 'sudo kubectl get pods -n minecraft'
# 3. helm upgrade（template の replicas=1 が再適用されて新Pod起動）
ssh k3s-worker 'cd ~/Minecraft_java_k3s/k8s/onprem/helm && sudo helm upgrade industry ./minecraft-server -f values-industry.yaml -n minecraft'
```

### BDS への say コマンド送信

```bash
ssh k3s-worker 'POD=$(sudo kubectl get pod -n minecraft -l app=mc-bedrock --no-headers -o custom-columns=":metadata.name") && sudo kubectl exec -n minecraft $POD -c bedrock -- send-command "say メッセージ"'
```

### Helm リリース一覧

```bash
ssh k3s-worker 'sudo helm list -n minecraft'
```

### gcloud（k3s-worker 経由）

```bash
ssh k3s-worker 'gcloud compute instances list'
```

```bash
ssh k3s-worker 'gcloud compute ssh mc-proxy-1 --zone=asia-northeast1-b --tunnel-through-iap --command="docker compose -f /opt/mc-proxy/compose.yaml ps"'
```

### Prometheus / Grafana 確認（k3s-monitoring）

```bash
ssh k3s-monitoring 'sudo kubectl get pods -n monitoring-prometheus'
```

```bash
ssh k3s-monitoring 'sudo kubectl logs deploy/prometheus -n monitoring-prometheus --tail=20'
```

---

## PVC / ファイル操作

PVC 内のファイル操作には helper Pod を立てる（MCBDS_restore.md 参照）。
ファイル転送は `kubectl cp` を SSH 経由で実行する。

```bash
# ローカルファイルを k3s-worker に転送してから kubectl cp
scp ./localfile k3s-worker:/tmp/localfile
ssh k3s-worker 'sudo kubectl cp /tmp/localfile minecraft/<pod-name>:/data/localfile'
```

---

## トラブルシューティング

### Pod が起動しない

```bash
ssh k3s-worker 'sudo kubectl describe pod -n minecraft -l app=mc-bedrock'
```

### ノード状態確認

```bash
ssh k3s-worker 'sudo kubectl get nodes -o wide'
```

### k3s サービス状態

```bash
ssh k3s-worker 'sudo systemctl status k3s'
```

```bash
ssh k3s-monitoring 'sudo systemctl status k3s-agent'
```
