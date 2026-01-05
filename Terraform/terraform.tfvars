# terraform.tfvars

# 共通設定
common_config = {
  gateway     = "192.168.0.1"
  template_id = 9000   # 用意済みのテンプレートID
  target_node = "pve1" # ※環境に合わせて変更してください（例: pve1, proxmoxなど）
}

# VMリスト
# ここに行を追加すれば、3台目、4台目も自動で作られます
vms = {
  # 1台目: DevOps機 (監視スタック用)
  "devops-server" = {
    vmid   = 103
    desc   = "Prometheus, Grafana Monitoring Stack"
    cores  = 4
    memory = 4096          # 4GB = 4096MB
    ip     = "192.168.0.200"
  },

  # 2台目: App機 (Javaマイクラ k3sクラスタ用)
  "app-minecraft" = {
    vmid   = 104
    desc   = "K3s Node for Minecraft Java Server"
    cores  = 16            # 16コア！強力ですね
    memory = 16384         # 16GB = 16384MB
    ip     = "192.168.0.201"
  }
}