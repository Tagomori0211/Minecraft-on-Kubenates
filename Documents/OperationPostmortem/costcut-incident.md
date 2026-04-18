# 📝 インシデント・ポストモーテム: GKE コスト最適化移行に伴う接続障害

> **概要**
> GKE Autopilot から Standard (Zonal) へのコスト最適化移行において、リソース不足、RBAC権限不足、およびオンプレミス側デバイスのオフラインが重なり、長時間のサービス停止が発生した。

---

## 📅 基本情報

| 項目 | 内容 |
|------|------|
| 発生日時 | 2026-04-14 20:00 (JST) |
| 解消日時 | 2026-04-14 22:45 (JST) (所要時間: 165分) |
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
  - `22:30`: GKE 疎通後もオンプレミス不通が継続。調査の結果、Auth Key 切れによる VPN 切断を特定。
  - `22:33`: ユーザーによる VPN 手動承認完了。新 IP `100.107.122.45` 割り当て。
  - `22:45`: 全構成ファイルの IP 追従修正・適用完了。全ポート開通。

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
  - **リソース見積もりミス**: e2-small の 2GB は、GKE システムコンポーネントによる占有で不足。
  - **構成変更漏れ**: Standard 移行時の RBAC 定義漏れ。
  - **認証情報劣化**: 古い TS_AUTHKEY の無効化による VPN 自動復帰の失敗。
  - **IP 不一致**: VPN 再認証によるオンプレミス側 IP の変動 (`100.100.135.81` -> `100.107.122.45`)。

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

---

# 🚀 追記: 第2フェーズ (2026-04-15 〜 2026-04-18) アーキテクチャの完全修復と最適化

> **追記概要**
> 当初 e2-medium への緊急増強で凌いでいた状態から、抜本的なアーキテクチャの改革を実施。
> Tailscale の接続基盤を各Podのサイドカーから**GKEノード自体のHostNetwork (DaemonSet)**へと集約することでメモリ問題を解消し、無事に目標であった **e2-small (2GB)** でのフル稼働を達成した。

## 📅 第2フェーズ タイムライン

- `2026-04-16 〜 2026-04-17`:
  - Tailscaleサイドカーによる OOMKilled 多発に直面し、アーキテクチャの見直しを開始。
  - Terraform 管理下の GCP VPC Subnet Router (`tailscale-router.tf`) を撤去。クラウド上のルーティングを排除し、完全な K8s ネイティブ通信へ移行。
- `2026-04-18 09:00`: GKE 側で `tailscale-node` DaemonSet (HostNetwork) を採用。Secret による認証でループ障害が発生したため、ノードの `/var/lib/tailscale` への `hostPath` 永続化に切り替え解決。
- `2026-04-18 10:00`: オンプレ側 `k3s-monitoring` が Terraform の SCSI コントローラバグによりディスクマウントに失敗していた問題を発見し、コード修正で修復。
- `2026-04-18 10:45`: GKE Pod からオンプレへの通信が「片道切符」になっていた問題に対し、GKE ノード上に iptables **MASQUERADE (SNAT) サイドカー** を注入することで解決。Velocity -> オンプレミスの透過ルーティングが完成。
- `2026-04-18 10:52`: K3s 再構築で消失していた Bedrock ワールドデータを `MCBDS_restore.md` ワークフローに沿って復旧。
- `2026-04-18 11:00`: Bedrock UDP 19132ポートの Firewall 欠落も修正し、全アーキテクチャが e2-small 上で完全に安定稼働 (<-- 現在地)

## 💡 第2フェーズ 学び・改善点

- **ルーティングの実装**: GCP VPCに依存した subnet routing から、GKEノードを直接 Tailscale に参加させる（HostNetwork + SNAT）手法へ進化。これにより Sidecar によるメモリ浪費がなくなり、リソース効率が劇的に向上した。
- **恒久化設定の重要性**: 一時的な Secret マウントによる Auth Key 管理ではなく、ディスク (`hostPath`) を持たせることで、DaemonSet がクラッシュしても二度と再認証を求められない安定環境を実現した。

*Updated by: Antigravity (JST: 2026-04-18 11:13)*
*承認 Tagomori0211*
