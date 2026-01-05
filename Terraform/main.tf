resource "proxmox_vm_qemu" "server_vms" {
  # 【重要】for_eachを使って、tfvarsの "vms" リスト分だけ繰り返します
  for_each = var.vms

  # 基本設定
  name        = each.key                 # mapのキー名 (例: devops-server) がVM名になります
  target_node = var.common_config.target_node
  vmid        = each.value.vmid          # tfvarsの vmid (103, 104)
  desc        = each.value.desc          # 説明文

  # テンプレート設定
  clone       = "ubuntu-template"        # ※Proxmox上のテンプレート名に合わせてください
  # id指定でクローンする場合は full_clone = true などが必要になる場合がありますが
  # 通常はテンプレート名を指定してクローンします。
  # もしID指定が必要なプロバイダ設定の場合は適宜修正してください。

  # リソース設定
  cores       = each.value.cores
  sockets     = 1                        # ソケットは1、コア数で調整
  memory      = each.value.memory
  

  # ネットワーク設定
  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

  # Cloud-Init設定 (IP固定化)
  os_type = "cloud-init"
  
  # IPアドレスの設定
  # each.value.ip で各VMのIPを取得、common_configからGWを取得
  ipconfig0 = "ip=${each.value.ip}/24,gw=${var.common_config.gateway}"
  
  # ユーザー設定（必要に応じて）
  # ciuser = "shinari"
  # sshkeys = "..."
}