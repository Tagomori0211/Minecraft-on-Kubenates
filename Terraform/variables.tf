# ============================================================
# Variables
# ============================================================

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region for GKE cluster"
  type        = string
  default     = "asia-northeast1" # 東京リージョン
}

variable "zone" {
  description = "GCP Zone for GKE cluster（ゾーナル = コントロールプレーン実質無料）"
  type        = string
  default     = "asia-northeast1-b"
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
  default     = "prod"
}

# ============================================================
# Network Variables
# ============================================================
variable "vpc_name" {
  description = "VPC network name"
  type        = string
  default     = "tak-vpc"
}

variable "subnet_cidr" {
  description = "Subnet CIDR for GKE nodes"
  type        = string
  default     = "10.100.0.0/20" # 4096 IPs
}

variable "pod_cidr" {
  description = "Secondary CIDR for Pods"
  type        = string
  default     = "10.101.0.0/16" # 65536 Pod IPs
}

variable "service_cidr" {
  description = "Secondary CIDR for Services"
  type        = string
  default     = "10.102.0.0/20" # 4096 Service IPs
}

# ============================================================
# GKE Cluster Variables
# ============================================================
variable "cluster_name" {
  description = "GKE Standard cluster name"
  type        = string
  default     = "tagomori-minecraft"
}

variable "release_channel" {
  description = "GKE release channel (RAPID/REGULAR/STABLE)"
  type        = string
  default     = "REGULAR"
}

# ============================================================
# Tailscale Variables
# ============================================================
variable "tailscale_auth_key" {
  description = "Tailscale Auth Key (reusable, ephemeral recommended)"
  type        = string
  sensitive   = true
  default     = "" # CI/CD or terraform.tfvars で設定
}

variable "onprem_tailscale_subnet" {
  description = "On-premises subnet advertised via Tailscale"
  type        = string
  default     = "10.43.0.0/16" # k3s Service CIDR (要確認)
}

# ============================================================
# Cost Optimization
# ============================================================
# NOTE: Spot 制御は Node Pool 単位で行うため、この変数は廃止
# proxy-pool: Regular（Velocity 終窯 = 全サーバーダウンのため Spot 不可）

# ============================================================
# Proxmox Variables（オンプレ VM管理）
# ============================================================
variable "proxmox_api_url" {
  description = "Proxmox API URL (例: https://192.168.0.xxx:8006/api2/json)"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "Proxmox API Token ID (書式: user@pam!tokenid)"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API Token Secret"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "VM接続用SSHパブリックキー"
  type        = string
}

variable "vms" {
  description = "Proxmox VM構成マップ"
  type = map(object({
    vmid        = number
    desc        = string
    cores       = number
    memory      = number
    ip          = string
    disk_size   = string
    target_node = string
    template_id = string
  }))
  default = {}
}

variable "common_config" {
  description = "VM共通設定"
  type = object({
    gateway     = string
    template_id = number
    target_node = string
  })
}
