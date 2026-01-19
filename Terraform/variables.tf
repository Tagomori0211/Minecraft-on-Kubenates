# ============================================================
# Variables
# ============================================================

variable "project_id" {
  description = "GCP Project ID"
  type        = string
  # 実際のプロジェクトIDに置き換える
  # default = "tak-pipeline-prod"
}

variable "region" {
  description = "GCP Region for GKE cluster"
  type        = string
  default     = "asia-northeast1" # 東京リージョン
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
  description = "GKE Autopilot cluster name"
  type        = string
  default     = "tak-entrance"
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
variable "enable_spot_only" {
  description = "Force all workloads to use Spot Pods"
  type        = bool
  default     = true
}
