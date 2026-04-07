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
  k3s-worker = {
    vmid        = 105
    desc        = "Single K3s Node for all services (Minecraft + Infrastructure)"
    cores       = 16
    memory      = 59392
    ip          = "192.168.0.151"
    disk_size   = "200G"
    target_node = "mc-server"
    template_id = "ubuntu-2404-cloud-init"
  }

  # 監視専用ノード: s3ホスト上に配置
  k3s-monitoring = {
    vmid        = 100
    desc        = "Dedicated Monitoring Node (Prometheus/Grafana)"
    cores       = 4
    memory      = 8192 # 8GiB
    ip          = "192.168.0.101"
    disk_size   = "50G"
    target_node = "s3"
    template_id = "ubuntu-2404-cloud-init-s3"
  }
}
