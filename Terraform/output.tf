# ============================================================
# Outputs
# ============================================================

output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.tak_entrance.name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.tak_entrance.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = google_container_cluster.tak_entrance.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_location" {
  description = "GKE cluster location"
  value       = google_container_cluster.tak_entrance.location
}

# kubectl接続用コマンド
output "kubectl_command" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.tak_entrance.name} --zone ${google_container_cluster.tak_entrance.location} --project ${var.project_id}"
}

# ネットワーク情報
output "vpc_name" {
  description = "VPC network name"
  value       = google_compute_network.tak_vpc.name
}

output "subnet_name" {
  description = "Subnet name"
  value       = google_compute_subnetwork.tak_subnet.name
}

# 静的IP
output "minecraft_static_ip" {
  description = "Static IP for Minecraft LoadBalancer"
  value       = google_compute_address.minecraft_ip.address
}

# Tailscale設定用情報
output "tailscale_firewall_rule" {
  description = "Tailscale firewall rule name"
  value       = google_compute_firewall.tailscale_udp.name
}

# コスト見積もり用情報
output "cost_estimation_info" {
  description = "Information for cost estimation"
  value = {
    region         = var.region
    cluster_type   = "Standard (Zonal)"
    proxy_node     = "e2-small (Regular)"
    nat_enabled    = false
    static_ip      = true
    estimated_note = "Zonalコントロールプレーンは無料、$74.4クレジットで相殺。e2-smallノード費用のみ発生。"
  }
}
