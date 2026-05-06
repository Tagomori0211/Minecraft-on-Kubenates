---
trigger: always_on
---

# 必ずやること
- `.agents/workflows/project_context.md` と `Documents/architecture/infrastructure.mermaid` を読み込んで全体像を把握する
- `gce/README.md` を確認してGCE側の構成を把握する
- 明確な指示がない限り作業指示書、Task_mds ディレクトリは無視する

## 必要な時にやること
- トラブルシューティング時は `Documents/OperationPostmortem/` を探索して既知の問題と衝突しないか確認する
- `git add .` を徹底し、add 漏れがないようにする

### SSH / k3s 操作
k3s クラスターへの操作が必要な場合は `.agents/workflows/k3s-ssh-operations.md` を参照すること。

**絶対に守ること:**
- `kubectl` / `helm` / `gcloud` はクライアントマシンから直接実行できない — SSH 経由のみ
- `gcloud` は k3s-worker にのみインストール済み（k3s-monitoring には未インストール）
- SSH ホスト名は `~/.ssh/config` で解決済み: `k3s-worker` / `k3s-monitoring`
- GCE VM へは IAP SSH: `gcloud compute ssh mc-proxy-1 --zone=asia-northeast1-b --tunnel-through-iap`
  （ただし gcloud 自体は k3s-worker から実行）
