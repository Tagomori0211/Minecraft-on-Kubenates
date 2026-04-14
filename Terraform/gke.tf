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

  source_ranges = ["0.0.0.0/0"]

  target_tags = ["minecraft"]

  description = "Allow Minecraft TCP traffic"
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
# GKE Standard Cluster（ゾーナル）
# ============================================================
resource "google_container_cluster" "tak_entrance" {
  provider = google-beta

  name     = var.cluster_name
  # ゾーナルにすることでコントロールプレーンが実質無料（$74.4/月クレジット相殺）
  location = var.zone

  # Standard モード（Autopilot 無効 = node_pool 自分で管理）
  # enable_autopilot は指定しない（デフォルトで Standard）

  network    = google_compute_network.tak_vpc.name
  subnetwork = google_compute_subnetwork.tak_subnet.name

  # デフォルト node pool は削除して custom pool のみ使用
  remove_default_node_pool = true
  initial_node_count       = 1

  # IP アロケーションポリシー
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # リリースチャネル
  release_channel {
    channel = var.release_channel
  }

  # プライベートクラスター設定
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false # kubectl 接続用に public endpoint を維持

    master_ipv4_cidr_block = "172.16.0.0/28"
  }

  # マスター認可ネットワーク
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0" # 本番では自宅 IP に制限推奨
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
  # NOTE: managed_prometheus は無効（監視はオンプレ Prometheus に移行済み）
  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]

    managed_prometheus {
      enabled = false
    }
  }

  # リソースラベル
  resource_labels = local.common_labels

  # 削除保護（destroy を許可するため無効）
  deletion_protection = false

  # 依存関係
  depends_on = [
    google_compute_subnetwork.tak_subnet
  ]
}

# ============================================================
# Node Pool: proxy-pool（プロキシ専用 Regular ノード）
# ============================================================
# Velocity / nginx-gw / socat を収容する Regular（非 Spot）ノード
# Velocity が落ちると全サーバーダウンするため Spot は採用しない
resource "google_container_node_pool" "proxy_pool" {
  name     = "proxy-pool"
  cluster  = google_container_cluster.tak_entrance.name
  location = var.zone
  project  = var.project_id

  # 固定 1 台（オートスケール不要 / プロキシのリソース要件は小さい）
  node_count = 1

  node_config {
    machine_type = "e2-medium" # 2vCPU / 2GB — Velocity+nginx+socat で十分

    # Spot を使わない（Regular）
    spot = false

    disk_size_gb = 20
    disk_type    = "pd-standard"

    # ノード識別ラベル（Pod 側 nodeSelector で参照）
    labels = {
      pool             = "proxy"
      "app-part-of"    = "tak-pipeline"
      env              = "prod"
    }

    tags = ["minecraft", "tailscale"]

    # OAuth スコープ
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    # Workload Identity 有効化
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_integrity_monitoring = true
      enable_secure_boot          = false
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }
}

# ============================================================
# Cloud NAT (Egress 用)
# ============================================================
# プライベートノードが外部通信するために必要

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
# Static IP for LoadBalancer
# ============================================================
# DNS 設定用の固定 IP（Nginx GW の LB に使用）

resource "google_compute_address" "minecraft_ip" {
  name        = "tagomori-minecraft-ip"
  region      = var.region
  description = "Static IP for Minecraft Velocity Proxy"
}
