provider "proxmox" {
  pm_api_url = var.proxmox_api_url

  # APIログイン
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret

  pm_tls_insecure = true
}

# s3 用のプロバイダー定義
provider "proxmox" {
  alias      = "s3"
  pm_api_url = "https://192.168.0.100:8006/api2/json"

  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret

  pm_tls_insecure = true
}