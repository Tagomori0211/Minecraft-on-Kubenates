# ============================================================
# GCP設定
# ============================================================
# GCPプロジェクトID（gcloud projects list で確認）
project_id = "project-61cf5742-d0ea-45ed-ac0"

# ============================================================
# オンプレ設定（Proxmox）
# ============================================================
# 共通設定
common_config = {
  gateway     = "192.168.0.1"
  template_id = 9000        # 用意済みのテンプレートID
  target_node = "mc-server" # ※環境に合わせて変更してください（例: pve1, proxmoxなど）
}

# VMリスト
vms = {
  # シングルノード: オンプレ：k3s-worker (Java/Bedrock マイクラゲームサーバー用 + Status Platform)
  "k3s-worker" = {
    vmid      = 105
    desc      = "Single K3s Node for all services (Minecraft + Infrastructure)"
    cores     = 16              # 16コア
    memory    = 59392           # 58GiB (58 * 1024 = 59392MB)
    ip        = "192.168.0.151" # 既存のMinecraftServerのIPを引き継ぐ
    disk_size = "200G"          # 十分なディスクサイズ
  }
}

