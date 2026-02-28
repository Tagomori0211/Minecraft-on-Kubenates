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
  template_id = 9000   # 用意済みのテンプレートID
  target_node = "mc-server" # ※環境に合わせて変更してください（例: pve1, proxmoxなど）
}

# VMリスト
vms = {
  # 1台目: オンプレ：AppServer (k3sノード / 将来拡張および監視・ルーターノード)
  "AppServer" = {
    vmid   = 103
    desc   = "K3s Node for Main Services (Infrastructure/Router)"
    cores  = 4
    memory = 8192          # 8GB = 8192MB
    ip     = "192.168.0.150"
    disk_size = "100G"
  },

  # 2台目: オンプレ：MinecraftServer (k3sノード / Java/Bedrock マイクラゲームサーバー用)
  "MinecraftServer" = {
    vmid   = 104
    desc   = "K3s Node for Minecraft Game Servers (Survival, Mod, Bedrock)"
    cores  = 16            # 16コア
    memory = 24576         # 24GiB
    ip     = "192.168.0.151"
    disk_size = "200G"
  }
}

