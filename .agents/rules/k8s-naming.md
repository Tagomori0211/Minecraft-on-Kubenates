---
trigger: glob
globs: **/*.yaml,**/*.yml,k8s/**/*
---

---
description: Kubernetes / k3s マニフェスト作成・編集時のネーミング規約
activation: glob
glob: "**/*.yaml,**/*.yml,k8s/**/*,manifests/**/*"
---

# k8s Naming Convention — sushiski cluster

## Namespace
- 環境別プレフィックスを必ず付ける: `prod-`, `dev-`, `monitoring-`
- 例: `prod-minecraft`, `dev-velocity`, `monitoring-prometheus`

## リソース名
- 全て kebab-case（アンダースコア禁止）
- `<service>-<role>` の形式を基本とする
- 例: `minecraft-java`, `velocity-proxy`, `waterdogpe-bedrock`

## Label 必須セット
全リソースに以下を必ず付けること:
```yaml
labels:
  app.kubernetes.io/name: "<service-name>"
  app.kubernetes.io/component: "<role>"   # proxy / backend / monitoring
  app.kubernetes.io/managed-by: "terraform" # or "helm" / "kubectl"
  env: "prod"                              # prod / dev / staging
```

## PVC命名
- `<service>-<用途>-pvc` の形式
- 例: `minecraft-java-data-pvc`, `prometheus-storage-pvc`

## ConfigMap / Secret
- `<service>-<内容>-cm` / `<service>-<内容>-secret`
- 例: `minecraft-java-config-cm`, `velocity-forwarding-secret`

## ❌ やってはいけないこと
- `test`, `temp`, `new` などの曖昧な名前
- Namespace なしのデプロイ（`default` namespace への直デプロイ禁止）
- label なしリソースの作成（Prometheus のサービスディスカバリが死ぬ）