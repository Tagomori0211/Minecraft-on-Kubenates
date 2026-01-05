# variables.tf

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