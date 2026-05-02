# ============================================================
# Outputs
# ============================================================

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
    cluster_type   = "n/a (GKE 廃止済み)"
    proxy_node     = "e2-medium (GCE / Docker Compose)"
    nat_enabled    = false
    static_ip      = true
    estimated_note = "GKE → GCE 移行完了（2026-05-03）。月額 ¥19,700 → ¥3,680 に削減（81%減）。"
  }
}
