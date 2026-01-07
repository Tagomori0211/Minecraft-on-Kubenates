resource "proxmox_vm_qemu" "server_vms" {
  for_each = var.vms

  # 基本設定
  name        = each.key
  target_node = var.common_config.target_node
  vmid        = each.value.vmid
  description = each.value.desc


  # テンプレート設定
  clone      = "ubuntu-2404-cloud-init"
  full_clone = true

  # リソース設定
  cores   = each.value.cores
  sockets = 1
  memory  = each.value.memory

  # ★ SCSIコントローラ（重要）
  scsihw = "virtio-scsi-pci"

  # ★ ディスク設定
  disk {
    slot    = "scsi0"
    size    = each.value.disk_size  # 例: "32G"
    storage = "local-lvm"
    type    = "disk"
  }

  # ★ Cloud-Initドライブ
  disk {
    slot    = "ide2"
    type    = "cloudinit"
    storage = "local-lvm"
  }

  # ネットワーク設定
  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }
 #  シリアルコンソール設定
  serial {
    id   = 0
    type = "socket"
  }

  #  VGA設定（シリアルコンソール使用）
  vga {
    type = "serial0"
  }

  # Cloud-Init設定
  os_type   = "cloud-init"
  ipconfig0 = "ip=${each.value.ip}/24,gw=${var.common_config.gateway}"
  ciuser    = "shinari"
  sshkeys    = var.ssh_public_key

  # ★ qemu-guest-agent有効化
  agent = 1

  # 起動待機（Cloud-Init完了まで）
  lifecycle {
    ignore_changes = [
      disk,  # ディスクリサイズ後の差分を無視
    ]
  }
}