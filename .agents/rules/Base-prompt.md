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

### SSH 接続
SSH 接続時には `~/.ssh/config` を参照し適切な方法で接続すること。

よく使うホスト:
- `k3s-worker`: オンプレ k3s バックエンド（kubectl は `sudo kubectl`）
- `gcloud compute ssh mc-proxy-1 --zone=asia-northeast1-b --tunnel-through-iap`: GCE VM（IAP 経由）
