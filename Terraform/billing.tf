# ============================================================
# Billing Export → BigQuery 監視基盤
# ============================================================
# フロー:
#   Cloud Console（手動） → Billing Export → BigQuery Dataset
#   → Looker Studio ダッシュボード（Linking API URL 経由）
#
# 注意: Billing Export の有効化は CLI/API 非対応のため手動が必須
#   Cloud Console → 課金 → 請求データのエクスポート → BigQuery へのエクスポート
#   データセット ID: gcp_billing_export を選択して保存
# ============================================================

# ============================================================
# 必要な API 有効化
# ============================================================

resource "google_project_service" "bigquery" {
  project            = var.project_id
  service            = "bigquery.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudbilling" {
  project            = var.project_id
  service            = "cloudbilling.googleapis.com"
  disable_on_destroy = false
}

# ============================================================
# BigQuery データセット（Billing Export 受け取り先）
# ============================================================

resource "google_bigquery_dataset" "billing_export" {
  project       = var.project_id
  dataset_id    = "gcp_billing_export"
  friendly_name = "GCP Billing Export"
  description   = "Cloud Billing Export データセット。Cloud Console から Billing Export 設定後に自動でテーブルが作成される。"

  # Billing Export は US / EU マルチリージョンを推奨
  # asia-northeast1 も可能だが、エクスポート後の変更は不可
  location = "US"

  labels = merge(local.common_labels, {
    purpose = "billing-monitoring"
  })

  depends_on = [google_project_service.bigquery]
}

# ============================================================
# Outputs
# ============================================================

output "billing_dataset_id" {
  description = "Billing Export 先 BigQuery データセット ID"
  value       = google_bigquery_dataset.billing_export.dataset_id
}

output "billing_dataset_location" {
  description = "BigQuery データセットのロケーション（Billing Export 設定時に一致させること）"
  value       = google_bigquery_dataset.billing_export.location
}

output "looker_studio_url" {
  description = <<-EOT
    Looker Studio ダッシュボード作成 URL。
    Billing Export でデータが流入してから（最大 24h）アクセスすること。
    BigQuery コネクタからデータセット "gcp_billing_export" を選択すれば接続できる。
    公式テンプレートを使う場合: Looker Studio ギャラリーで "Cloud Billing" を検索してコピー。
  EOT
  value       = "https://lookerstudio.google.com/datasources/create?connectorId=bigQuery&projectId=${var.project_id}&datasetId=${google_bigquery_dataset.billing_export.dataset_id}"
}

output "billing_setup_instructions" {
  description = "Billing Export 手動設定手順"
  value       = <<-EOT
    【手動設定が必要】Billing Export の有効化:
    1. Cloud Console → 課金 → 請求データのエクスポート → BigQuery へのエクスポート
    2. プロジェクト: ${var.project_id}
    3. データセット: gcp_billing_export（ロケーション: US）
    4. 「標準使用コスト」を有効化して保存
    5. 数時間〜翌日にデータが流入開始する
  EOT
}
