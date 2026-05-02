# ============================================================
# GKE Standard Cluster (ゾーナル / プロキシ専用)
# ============================================================
# 移行目的:
#   Autopilot → Standard に変更してコストを削減
#   プロキシ層（Velocity / nginx-gw / socat）のみ GKE に残す
#   Lobby はオンプレに移行済み
#
# Node Pool 構成:
#   proxy-pool: e2-medium × 1（Regular）
#     - Velocity, nginx-gw, socat を配置
#     - Spot 非対応（Velocity 停止 = 全サーバーダウンのため）
#
# コストメモ:
#   コントロールプレーン: Zonal = $74.4 クレジットで実質無料
#   proxy-pool e2-medium:  ~$13/月
#   GCE Tailscale Router: ~$5/月（変更なし）
#   合計: ~$18/月
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

  # GKE 用のセカンダリレンジ
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

# Tailscale UDP 通信用
resource "google_compute_firewall" "tailscale_udp" {
  name    = "${var.vpc_name}-allow-tailscale"
  network = google_compute_network.tak_vpc.name

  allow {
    protocol = "udp"
    ports    = [tostring(local.tailscale_port)]
  }

  # Tailscale は基本的にどこからでも接続可能にする
  # (実際の認証は Tailscale 側で行われる)
  source_ranges = ["0.0.0.0/0"]

  target_tags = ["tailscale"]

  description = "Allow Tailscale UDP traffic for VPN"
}

# Minecraft 用（LoadBalancer 経由だが念のため）
resource "google_compute_firewall" "minecraft_tcp" {
  name    = "${var.vpc_name}-allow-minecraft"
  network = google_compute_network.tak_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["25565"]
  }

  allow {
    protocol = "udp"
    ports    = ["19132"]
  }

  source_ranges = ["0.0.0.0/0"]

  target_tags = ["minecraft"]

  description = "Allow Minecraft TCP/UDP traffic"
}

# 内部通信用（GKE 内部）
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
# GKE Standard Cluster（2026-05-03 GCE 移行により削除）
# ============================================================
# 削除理由: GCE e2-medium + Docker Compose に移行（月額 81% 削減）
# 参照: Terraform/gce.tf, gce/README.md

# ============================================================
# Cloud NAT (廃止済み)
# ============================================================
# ADR-001: enable_private_nodes = false によりノードが外部IPを持つため
# Cloud NAT は不要になった。tak-vpc-router / tak-vpc-nat は terraform apply で削除される。
# 削除日: 2026-05-02

# ============================================================
# Static IP for LoadBalancer
# ============================================================
# DNS 設定用の固定 IP（Nginx GW の LB に使用）

resource "google_compute_address" "minecraft_ip" {
  name        = "tagomori-minecraft-ip"
  region      = var.region
  description = "Static IP for Minecraft Velocity Proxy"
}
