# 共通で使用する設定値
variable "common_config" {
  description = "全VMで共通の設定 (ゲートウェイ、テンプレートIDなど)"
  type = object({
    gateway     = string
    template_id = number
    target_node = string
  })
}

# 各VMごとの設定値（Map形式）
# キー（名前）に対して、スペックのセットを定義します
variable "vms" {
  description = "作成するVMのスペックリスト"
  type = map(object({
    vmid   = number # Proxmox上のID (103, 104)
    desc   = string # VMの説明メモ
    cores  = number # CPUコア数
    memory = number # メモリ容量(MB)
    ip     = string # 固定IPアドレス
  }))
}


variable "proxmox_api_url" {
  description = "Proxmox APIのURL (例: https://192.168.0.30:8006/api2/json)"
  type        = string
}

variable "proxmox_user" {
  description = "Proxmoxのユーザー名 (root@pam)"
  type        = string
  default     = "root@pam" 
}

variable "proxmox_api_token_id" {
  description = "API Token ID (例: root@pam!terraform)"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "API Token Secret (UUIDのような文字列)"
  type        = string
  sensitive   = true
}