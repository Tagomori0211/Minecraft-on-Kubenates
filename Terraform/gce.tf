# ============================================================
# GCE Minecraft Proxy VM (GKE 代替)
# ============================================================
# 移行目的:
#   GKE Standard を GCE 単一 VM に置換し、月額 ¥19,700 → ¥3,680 へ削減（81%減）
#   ホームIP遮蔽の役割は VM が引き継ぎ、Velocity と nginx-stream を Docker Compose で運用
#
# 構成:
#   - e2-medium / asia-northeast1-b
#   - Ubuntu 24.04 LTS / pd-balanced 20GB
#   - 静的IP 35.200.78.252（tagomori-minecraft-ip）を access_config にアタッチ
#   - cloud-init で Docker / Tailscale / mc-proxy.service をプロビジョニング
#   - Service Account `mc-proxy-sa` に Secret Manager 読取権限のみ付与
#
# 既存リソースの再利用:
#   - VPC: google_compute_network.tak_vpc
#   - Subnet: google_compute_subnetwork.tak_subnet
#   - Firewall: tailscale_udp / minecraft_tcp（target_tags で適用）
#   - 静的IP: google_compute_address.minecraft_ip
# ============================================================

# ============================================================
# Service Account（最小権限）
# ============================================================
resource "google_service_account" "mc_proxy_sa" {
  account_id   = "mc-proxy-sa"
  display_name = "GCE Minecraft Proxy Service Account"
  description  = "Used by mc-proxy-1 VM. Allows reading Secret Manager values only."
}

resource "google_project_iam_member" "mc_proxy_secret_access" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.mc_proxy_sa.email}"
}

# ============================================================
# GCE VM: mc-proxy-1
# ============================================================
resource "google_compute_instance" "mc_proxy" {
  name         = "mc-proxy-1"
  machine_type = "e2-medium"
  zone         = var.zone
  tags         = ["minecraft", "tailscale"]

  # 起動時 cloud-init の完了を待ちたいため停止可
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2404-lts"
      size  = 20
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.tak_subnet.name

    # Phase 2 ではエフェメラル IP で動作確認
    # Phase 3 で nat_ip = google_compute_address.minecraft_ip.address に切替
    access_config {}
  }

  service_account {
    email  = google_service_account.mc_proxy_sa.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    user-data = file("${path.module}/../gce/cloud-init.yaml")
  }

  shielded_instance_config {
    enable_secure_boot          = false
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  labels = local.common_labels

  # IP 切替時は VM 再作成を避けたい
  lifecycle {
    ignore_changes = [
      metadata["ssh-keys"],
    ]
  }

  depends_on = [
    google_project_iam_member.mc_proxy_secret_access,
  ]
}

# ============================================================
# Outputs
# ============================================================
output "mc_proxy_external_ip" {
  description = "GCE Minecraft Proxy VM external IP (ephemeral until Phase 3)"
  value       = google_compute_instance.mc_proxy.network_interface[0].access_config[0].nat_ip
}

output "mc_proxy_internal_ip" {
  description = "GCE Minecraft Proxy VM internal IP"
  value       = google_compute_instance.mc_proxy.network_interface[0].network_ip
}
