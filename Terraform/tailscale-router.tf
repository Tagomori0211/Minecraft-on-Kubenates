# ============================================================
# Tailscale Subnet Router (GCE VM)
# ============================================================
# GKE Autopilot からオンプレミス環境へ透過的に UDP/TCP 通信を行うためのルーター

# ------------------------------------------------------------
# IAM Service Account for the Router
# ------------------------------------------------------------
resource "google_service_account" "tailscale_router_sa" {
  account_id   = "tailscale-router-sa"
  display_name = "Tailscale Subnet Router Service Account"
  project      = var.project_id
}

# ------------------------------------------------------------
# Compute Engine Instance (e2-micro)
# ------------------------------------------------------------
resource "google_compute_instance" "tailscale_subnet_router" {
  name         = "tailscale-subnet-router"
  machine_type = "e2-micro"
  zone         = "asia-northeast1-b"
  project      = var.project_id

  tags = ["tailscale-router"]

  # IP Forwarding is REQUIRED for a subnet router
  can_ip_forward = true

  boot_disk {
    auto_delete = true
    device_name = "tailscale-subnet-router"
    initialize_params {
      image = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2404-lts-amd64"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.tak_vpc.self_link
    subnetwork = google_compute_subnetwork.tak_subnet.self_link
    # 外部通信 (Tailscale Control Plane への接続など) のために外部IPを付与
    access_config {
      network_tier = "PREMIUM"
    }
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    provisioning_model  = "STANDARD"
  }

  shielded_instance_config {
    enable_integrity_monitoring = true
    enable_secure_boot          = false
    enable_vtpm                 = true
  }

  service_account {
    email  = google_service_account.tailscale_router_sa.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  allow_stopping_for_update = true
}

# ------------------------------------------------------------
# VPC Route
# ------------------------------------------------------------
# GKE Pod から Tailscale IP (100.64.0.0/10) 宛のトラフィックを VM に向ける
resource "google_compute_route" "tailscale_route" {
  name        = "tailscale-route"
  project     = var.project_id
  network     = google_compute_network.tak_vpc.name
  description = "Route Tailscale CGNAT to Subnet Router"

  # Tailscale Network CIDR
  dest_range = "100.64.0.0/10"

  priority = 100

  next_hop_instance      = google_compute_instance.tailscale_subnet_router.self_link
  next_hop_instance_zone = google_compute_instance.tailscale_subnet_router.zone
}

# ------------------------------------------------------------
# Firewall Rules
# ------------------------------------------------------------
# GKE Pods -> Tailscale Router への全トラフィックを許可
resource "google_compute_firewall" "allow_gke_to_tailscale_router" {
  name        = "${var.vpc_name}-allow-gke-to-tailscale-router"
  network     = google_compute_network.tak_vpc.name
  project     = var.project_id
  description = "Allow GKE Pods to reach Tailscale Subnet Router"

  direction = "INGRESS"

  allow {
    protocol = "all"
  }

  # GKE Pod CIDR & Node CIDR (in case of SNAT)
  source_ranges = [var.pod_cidr, var.subnet_cidr]

  # tailscale_subnet_router のタグ
  target_tags = ["tailscale-router"]
}

# 管理者(Ansible) -> Tailscale Router への SSH 許可
resource "google_compute_firewall" "allow_ssh_to_tailscale_router" {
  name        = "allow-ssh-to-tailscale-router"
  network     = google_compute_network.tak_vpc.name
  project     = var.project_id
  description = "Allow SSH to Tailscale Subnet Router"

  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["tailscale-router"]
}

