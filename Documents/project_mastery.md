# Project Mastery: Minecraft Hybrid Cloud Infrastructure

## 1. トラフィックフローの完全把握

### Java版 Minecraft
1. **入口**: GKE上の `nginx-gw` (TCP 25565)
2. **L7プロキシ**: GKE上の `Velocity` (TCP 25577)
3. **VPN通過**: Tailscale経由でオンプレミスへ
4. **ロビー**: オンプレk3s上の `Lobby` (Paper)
5. **各サーバー**: `Survival` または `Industry` (MOD) へ転送

### Bedrock版 Minecraft
1. **入口**: GKE上の `socat` (UDP 19132 透過転送)
2. **VPN通過**: Tailscale経由でオンプレミスへ
3. **バックエンド**: オンプレk3s上の `Bedrock (BDS)` (hostPort 19132)

## 2. インフラ・ネットワーク構成の詳細

### Tailscale 接続トポロジ
- **GKE側**: `tailscale-node` DaemonSet により、GKEノード自体がTailscaleネットワークに参加。
- **オンプレ側**: `tailscale-subnet-router` がk3sサービスCIDR (`10.43.0.X/16`) を広告。
- **名前解決**: TailscaleのマジックDNSまたはIP直接指定で相互通信。

### リソース割り当て (オンプレ Ryzen 5700G)
- **Lobby**: 8Gi RAM
- **Survival**: 16Gi RAM
- **Industry**: 30Gi RAM
- **Bedrock**: 8Gi RAM
- **合計予約**: 約 62Gi / 64Gi (限界に近い)


## 4. 運用・保守の指針
- **デプロイ**: マニフェストは `k8s/` 以下で管理。命名規則（kebab-case, namespace prefix）を厳守。
- **同期**: 作業後は必ず `git commit` + `git push` を行う。
- **トラブル対応**: `Documents/OperationPostmortem/` に記録を残す（現在はディレクトリのみ存在確認）。
