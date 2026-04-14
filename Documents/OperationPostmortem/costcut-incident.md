# 📝 インシデント・ポストモーテム: GKE コスト最適化移行に伴う接続障害

> **概要**
> GKE Autopilot から Standard (Zonal) へのコスト最適化移行において、リソース不足、RBAC権限不足、およびオンプレミス側デバイスのオフラインが重なり、長時間のサービス停止が発生した。

---

## 📅 基本情報

| 項目 | 内容 |
|------|------|
| 発生日時 | 2026-04-14 20:00 (JST) |
| 解消日時 | 2026-04-14 22:15 (JST) (所要時間: 135分) |
| 影響範囲 | Minecraft (Java/Bedrock) 全サーバーへの外部接続不可 |
| 対応者 | Antigravity |

---

## 🔍 1. 何が起きたか（状況）

事象のサマリーと、時系列での推移。

- **事象概要**:
  - GKE Standard 移行後、e2-small 1ノード構成ではシステムポッドのオーバーヘッドにより Minecraft プロキシ層が起動不全に陥った。
  - 手動注入した Tailscale サイドカーに RBAC 権限が不足していたため、VPN 接続が確立できなかった。
  - 作業期間中にオンプレミス側の物理ホストおよび VM がオフラインとなり、ハイブリッド連携が完全に切断された。

- **タイムライン**:
  - `20:00`: Terraform による GKE Autopilot 削除・Standard 構築開始。
  - `20:44`: Standard クラスター構築完了。マニフェスト適用開始。
  - `21:00`: ポッドが `Insufficient memory` で Pending 状態になる。
  - `21:05`: 外部 IP 変動を確認。Java 版 IP 固定。
  - `21:08`: Tailscale サイドカー注入後、RBAC エラーで CrashLoopBackOff 発生。
  - `21:18`: e2-small (2GB) では収容不可と判断し、e2-medium (4GB) への増強を決定。
  - `21:47`: ノードアップグレード完了。メモリ不足解消。
  - `21:51`: RBAC (Role/RoleBinding) 適用。サイドカー起動成功。
  - `22:15`: オンプレ物理ホストの Tailscale 再起動および VM 起動を確認。疎通回復。

---

## 🔬 2. 調査プロセス

### 実行コマンド
```bash
# ポッドのリソース不足確認
kubectl describe pod <pod_name> -n minecraft | grep -A 5 "Events"

# サイドカーのエラーログ確認
kubectl logs <pod_name> -c tailscale

# オンプレミス VM 状態確認
ssh proxmox-mc-server "qm list"
```

- **確認したログの内容**:
  - `Insufficient memory. 0/1 nodes are available.` (e2-small の限界)
  - `missing get permission on secret "velocity-tailscale-state"` (RBAC不足)
  - `mc-server offline, last seen 2h ago` (Tailscale status)

- **特定された原因**:
  - **リソース見積もりミス**: e2-small の 2GB は、GKE システムコンポーネント (Fluentbit等) で半分以上占有されるため、サイドカー付き Pod 2つを動かすには不十分だった。
  - **構成変更漏れ**: Autopilot から Standard への移行時、自動付与されていた RBAC 権限を明示的に定義していなかった。

---

## 🛠️ 3. 対応内容

### 暫定対応（ワークアラウンド）
- [x] ノードタイプを `e2-small` から `e2-medium` (4GB) へ緊急アップグレード。
- [x] Tailscale 用 RBAC マニフェスト (`25-tailscale-rbac.yaml`) の作成と適用。

### 恒久対応（根本修正）
- [ ] GKE Standard 構成時のベースライン要求リソース（システム分＋ワークロード分）の標準化。
- [ ] マルチコンテナ Pod 構築時の RBAC テンプレートの共通化。
- [ ] オンプレミス VM の死活監視と自動起動設定の再点検。

---

## 💡 4. 学び・改善点

- [ ] **リソース設計**: 1ノード構成にする場合は、OS/Kubernetes システム側の専有領域を考慮したサイジングを必須とする。
- [ ] **移行チェックリスト**: Autopilot (Managed) から Standard (Self-managed) への移行時は、RBAC、サイドカー、Firewall の定義が全て含まれているか確認する。
- [ ] **IP 固定**: 外部 IP は可能な限り予約 IP を使用し、サービス再作成時の変動リスクを抑える。

---

*Created by: Antigravity (JST: 2026-04-14 22:24)*
