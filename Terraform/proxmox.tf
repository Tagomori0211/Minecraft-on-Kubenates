# mc-server (192.168.0.30) 上のVM
resource "proxmox_vm_qemu" "mc_server_vms" {
  for_each = { for k, v in var.vms : k => v if v.target_node == "mc-server" }

  # 基本設定
  name        = each.key
  target_node = each.value.target_node
  vmid        = each.value.vmid
  description = each.value.desc

  # テンプレート設定
  clone      = each.value.template_id
  full_clone = true

  # リソース設定
  cores   = each.value.cores
  sockets = 1
  memory  = each.value.memory

  # ★ SCSIコントローラ
  scsihw = "virtio-scsi-pci"

  # ★ ディスク設定
  disk {
    slot    = "scsi0"
    size    = each.value.disk_size
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

  # シリアルコンソール
  serial {
    id   = 0
    type = "socket"
  }

  # VGA設定
  vga {
    type = "serial0"
  }

  # Cloud-Init設定
  os_type   = "cloud-init"
  ipconfig0 = "ip=${each.value.ip}/24,gw=${var.common_config.gateway}"
  ciuser    = "shinari"
  sshkeys   = var.ssh_public_key

  # ★ qemu-guest-agent有効化
  agent = 1

  lifecycle {
    ignore_changes = [disk]
  }
}

# s3 (192.168.0.100) 上のVM
resource "proxmox_vm_qemu" "s3_vms" {
  provider = proxmox.s3
  for_each = { for k, v in var.vms : k => v if v.target_node == "s3" }

  # 基本設定
  name        = each.key
  target_node = each.value.target_node
  vmid        = each.value.vmid
  description = each.value.desc

  # テンプレート設定
  clone      = each.value.template_id
  full_clone = true

  # リソース設定
  cores   = each.value.cores
  sockets = 1
  memory  = each.value.memory

  scsihw = "virtio-scsi-pci"

  disk {
    slot    = "scsi0"
    size    = each.value.disk_size
    storage = "local-lvm"
    type    = "disk"
  }

  disk {
    slot    = "ide2"
    type    = "cloudinit"
    storage = "local-lvm"
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

  serial {
    id   = 0
    type = "socket"
  }

  vga {
    type = "serial0"
  }

  os_type   = "cloud-init"
  ipconfig0 = "ip=${each.value.ip}/24,gw=${var.common_config.gateway}"
  ciuser    = "shinari"
  sshkeys   = var.ssh_public_key

  agent = 1

  lifecycle {
    ignore_changes = [disk]
  }
}