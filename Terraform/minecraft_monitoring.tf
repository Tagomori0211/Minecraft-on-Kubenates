# ============================================================
# Minecraft Monitoring - BigQuery Dataset / Table
# ============================================================
# フロー:
#   vmalert (15m recording rules) → GCE bq-metrics.timer
#   → bq insert (ADC via GCEインスタンスメタデータ、SA key 不要)
#   → BigQuery → Looker Studio (task4) で gcp_billing_export と JOIN
#
# 認証方式:
#   SA key 作成は org policy (constraints/iam.disableServiceAccountKeyCreation)
#   で禁止されているため、GCE VM の mc-proxy-sa を使用する。
#   GCE インスタンスメタデータ経由で ADC が自動提供されるため key 不要。
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

  # 日次パーティション: クエリコスト削減
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }

  # クラスタリング: server/metric_name フィルタを高速化
  clustering = ["server", "metric_name"]

  labels = merge(local.common_labels, {
    purpose = "minecraft-monitoring"
  })
}

# ============================================================
# BQ 権限: 既存の mc-proxy-sa に dataEditor を付与
# ============================================================
# SA key 不要。GCE VM の cloud-platform スコープで ADC が自動提供される。
# dataset レベルのみ（project-wide 権限を避ける）。

resource "google_bigquery_dataset_iam_member" "mc_proxy_bq_editor" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.minecraft_monitoring.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.mc_proxy_sa.email}"
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

output "mc_monitoring_setup_note" {
  description = "GCE VM への bq-metrics timer デプロイ手順"
  value       = <<-EOT
    GCE VM に bq-metrics timer をデプロイ（既存 VM への手動適用）:
      gcloud compute ssh mc-proxy-1 --zone=asia-northeast1-b --tunnel-through-iap -- '
        sudo git -C /opt/mc-proxy pull
        sudo install -m 0644 /opt/mc-proxy/systemd/bq-metrics.service /etc/systemd/system/
        sudo install -m 0644 /opt/mc-proxy/systemd/bq-metrics.timer /etc/systemd/system/
        sudo systemctl daemon-reload
        sudo systemctl enable --now bq-metrics.timer
        sudo systemctl list-timers bq-metrics.timer
      '
  EOT
}
