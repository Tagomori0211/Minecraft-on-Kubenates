# ============================================================
# TAK Pipeline - GKE Autopilot Hybrid Infrastructure
# ============================================================
# Purpose: GKE Autopilotクラスターをエントランスとして構築
# Cost Strategy: Spot Pod優先でコスト最適化
# ============================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }

  # State管理（本番運用時はGCSバックエンドを推奨）
  # backend "gcs" {
  #   bucket = "tak-pipeline-tfstate"
  #   prefix = "hybrid/gke"
  # }
}

# ============================================================
# Provider Configuration
# ============================================================
provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# ============================================================
# Data Sources
# ============================================================
data "google_project" "current" {
  project_id = var.project_id
}

# ============================================================
# Local Values
# ============================================================
locals {
  # 共通ラベル
  common_labels = {
    "app.kubernetes.io/part-of" = "tak-pipeline"
    "environment"               = var.environment
    "managed-by"                = "terraform"
  }

  # Tailscale UDP port
  tailscale_port = 41641
}
