# ============================================================
# GKE Autopilot Cluster
# ============================================================
# Autopilot特性:
#   - ノード管理不要（Googleが自動管理）
#   - Pod単位課金（リソース効率が良い）
#   - Spot Podで最大91%コスト削減
# ============================================================

# ============================================================
# VPC Network
# ============================================================
resource "google_compute_network" "tak_vpc" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
  project                 = var.project_id
}

resource "google_compute_subnetwork" "tak_subnet" {
  name          = "${var.vpc_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.tak_vpc.id

  # GKE用のセカンダリレンジ
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pod_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.service_cidr
  }

  private_ip_google_access = true
}

# ============================================================
# Firewall Rules
# ============================================================

# Tailscale UDP通信用
resource "google_compute_firewall" "tailscale_udp" {
  name    = "${var.vpc_name}-allow-tailscale"
  network = google_compute_network.tak_vpc.name

  allow {
    protocol = "udp"
    ports    = [tostring(local.tailscale_port)]
  }

  # Tailscaleは基本的にどこからでも接続可能にする
  # (実際の認証はTailscale側で行われる)
  source_ranges = ["0.0.0.0/0"]

  target_tags = ["tailscale"]

  description = "Allow Tailscale UDP traffic for VPN"
}

# Minecraft用（LoadBalancer経由だが念のため）
resource "google_compute_firewall" "minecraft_tcp" {
  name    = "${var.vpc_name}-allow-minecraft"
  network = google_compute_network.tak_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["25565"]
  }

  source_ranges = ["0.0.0.0/0"]

  target_tags = ["minecraft"]

  description = "Allow Minecraft TCP traffic"
}

# 内部通信用（GKE内部）
resource "google_compute_firewall" "internal" {
  name    = "${var.vpc_name}-allow-internal"
  network = google_compute_network.tak_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [
    var.subnet_cidr,
    var.pod_cidr,
    var.service_cidr,
  ]

  description = "Allow internal communication within VPC"
}

# ============================================================
# GKE Autopilot Cluster
# ============================================================
resource "google_container_cluster" "tak_entrance" {
  provider = google-beta

  name     = var.cluster_name
  location = var.region

  # Autopilotモード有効化
  enable_autopilot = true

  network    = google_compute_network.tak_vpc.name
  subnetwork = google_compute_subnetwork.tak_subnet.name

  # IPアロケーションポリシー
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # リリースチャネル
  release_channel {
    channel = var.release_channel
  }

  # プライベートクラスター設定
  # NOTE: Autopilotではprivate_cluster_configの一部オプションが制限される
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false # kubectl接続用にpublic endpointを維持

    master_ipv4_cidr_block = "172.16.0.0/28"
  }

  # マスター認可ネットワーク（セキュリティ強化）
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0" # 本番では自宅IPに制限推奨
      display_name = "All (restrict in production)"
    }
  }

  # Workload Identity（サービスアカウント連携）
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # メンテナンスウィンドウ（日本時間 平日深夜）
  maintenance_policy {
    recurring_window {
      start_time = "2024-01-01T17:00:00Z" # JST 02:00
      end_time   = "2024-01-01T21:00:00Z" # JST 06:00
      recurrence = "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
    }
  }

  # ロギング・モニタリング
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]

    managed_prometheus {
      enabled = true
    }
  }

  # リソースラベル
  resource_labels = local.common_labels

  # 削除保護（本番環境では有効化推奨）
  deletion_protection = false

  # 依存関係
  depends_on = [
    google_compute_subnetwork.tak_subnet
  ]
}

# ============================================================
# Cloud NAT (Egress用)
# ============================================================
# Autopilotのプライベートノードが外部通信するために必要

resource "google_compute_router" "tak_router" {
  name    = "${var.vpc_name}-router"
  region  = var.region
  network = google_compute_network.tak_vpc.id
}

resource "google_compute_router_nat" "tak_nat" {
  name   = "${var.vpc_name}-nat"
  router = google_compute_router.tak_router.name
  region = var.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ============================================================
# Static IP for LoadBalancer (optional)
# ============================================================
# 固定IPが必要な場合に使用（DNS設定用）

resource "google_compute_global_address" "minecraft_ip" {
  name         = "tak-minecraft-ip"
  address_type = "EXTERNAL"
  description  = "Static IP for Minecraft Velocity Proxy"
}
