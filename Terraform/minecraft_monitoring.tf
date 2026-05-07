# ============================================================
# Minecraft Monitoring - BigQuery Dataset / Table / SA
# ============================================================
# フロー:
#   vmalert (15m recording rules) → k3s CronJob → BQ INSERT
#   → Looker Studio (task4) で gcp_billing_export と JOIN して
#     プレイヤー当たりコストを可視化する
#
# デプロイ後の手動手順（SA key → k8s Secret 作成）:
#   terraform output -raw mc_monitoring_writer_key \
#     | base64 -d > /tmp/mc-monitoring-sa.json
#   kubectl create secret generic bq-writer-sa-key \
#     -n monitoring-prometheus \
#     --from-file=key.json=/tmp/mc-monitoring-sa.json
#   rm /tmp/mc-monitoring-sa.json
# ============================================================

# ============================================================
# BigQuery Dataset
# ============================================================

resource "google_bigquery_dataset" "minecraft_monitoring" {
  project       = var.project_id
  dataset_id    = "minecraft_monitoring"
  friendly_name = "Minecraft Monitoring Metrics"
  description   = "Minecraft サーバーメトリクス（vmalert 15分集計値）。gcp_billing_export との JOIN でプレイヤー当たりコスト計算に利用。"
  location      = "US"

  labels = merge(local.common_labels, {
    purpose = "minecraft-monitoring"
  })

  depends_on = [google_project_service.bigquery]
}

# ============================================================
# BigQuery Table
# ============================================================

resource "google_bigquery_table" "server_metrics" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.minecraft_monitoring.dataset_id
  table_id   = "server_metrics"

  schema = jsonencode([
    { name = "timestamp",   type = "TIMESTAMP", mode = "REQUIRED",
      description = "メトリクス収集時刻 (UTC)" },
    { name = "player_hash", type = "STRING",    mode = "NULLABLE",
      description = "SHA256(XUID + salt) — 将来のプレイヤー粒度メトリクス用。現在は NULL。" },
    { name = "server",      type = "STRING",    mode = "REQUIRED",
      description = "サーバー識別子 (lobby / survival / mod / bedrock)" },
    { name = "metric_name", type = "STRING",    mode = "REQUIRED",
      description = "recording rule 名 (例: mc:players_online:avg15m)" },
    { name = "value",       type = "FLOAT64",   mode = "REQUIRED",
      description = "集計値" },
  ])

  # 日次パーティション: クエリコスト削減とデータ管理に必須
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }

  # クラスタリング: server/metric_name でフィルタするクエリを高速化
  clustering = ["server", "metric_name"]

  labels = merge(local.common_labels, {
    purpose = "minecraft-monitoring"
  })
}

# ============================================================
# Service Account（BQ 書き込み専用）
# ============================================================

resource "google_service_account" "mc_monitoring_writer" {
  project      = var.project_id
  account_id   = "mc-monitoring-writer"
  display_name = "Minecraft Monitoring BQ Writer"
  description  = "k3s CronJob から minecraft_monitoring dataset へのストリーミングINSERT専用。最小権限。"
}

# dataset レベルで dataEditor 権限のみ付与（project-wide権限を避ける）
resource "google_bigquery_dataset_iam_member" "mc_monitoring_bq_editor" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.minecraft_monitoring.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.mc_monitoring_writer.email}"
}

# SA key（k8s Secret に格納するための JSON キー）
resource "google_service_account_key" "mc_monitoring_writer_key" {
  service_account_id = google_service_account.mc_monitoring_writer.name
}

# ============================================================
# Outputs
# ============================================================

output "mc_monitoring_dataset_id" {
  description = "Minecraft メトリクス BigQuery データセット ID"
  value       = google_bigquery_dataset.minecraft_monitoring.dataset_id
}

output "mc_monitoring_table_id" {
  description = "Minecraft メトリクス BigQuery テーブル ID"
  value       = google_bigquery_table.server_metrics.table_id
}

output "mc_monitoring_writer_key" {
  description = <<-EOT
    k8s Secret 作成コマンド（SA key JSON）:
      terraform output -raw mc_monitoring_writer_key \
        | base64 -d > /tmp/mc-monitoring-sa.json
      kubectl create secret generic bq-writer-sa-key \
        -n monitoring-prometheus \
        --from-file=key.json=/tmp/mc-monitoring-sa.json
      rm /tmp/mc-monitoring-sa.json
  EOT
  value     = google_service_account_key.mc_monitoring_writer_key.private_key
  sensitive = true
}
