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
    { name = "timestamp", type = "TIMESTAMP", mode = "REQUIRED",
    description = "メトリクス収集時刻 (UTC)" },
    { name = "player_hash", type = "STRING", mode = "NULLABLE",
    description = "SHA256(XUID + salt) — 将来のプレイヤー粒度メトリクス用。現在は NULL。" },
    { name = "server", type = "STRING", mode = "REQUIRED",
    description = "サーバー識別子 (lobby / survival / mod / bedrock)" },
    { name = "metric_name", type = "STRING", mode = "REQUIRED",
    description = "recording rule 名 (例: mc:players_online:avg15m)" },
    { name = "value", type = "FLOAT64", mode = "REQUIRED",
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
# BigQuery VIEW: コスト分析（Billing Export × Server Metrics）
# ============================================================
# gcp_billing_export × minecraft_monitoring.server_metrics を日次で JOIN し
# サーバー別コスト按分・プレイヤーあたりコストを算出する。
#
# NOTE: server_metrics は VictoriaMetrics → bq-metrics timer が稼働して
#       初めてデータが入る。billing_export 側は 2026-03-01〜 のデータあり。
#       双方にデータが揃った日付から JOIN 結果が出る。

resource "google_bigquery_table" "cost_analysis_view" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.minecraft_monitoring.dataset_id
  table_id            = "cost_analysis_view"
  deletion_protection = false

  view {
    use_legacy_sql = false
    query          = <<-SQL
      WITH

      -- 日次 GCP 総コスト（全サービス合計）
      daily_billing AS (
        SELECT
          DATE(usage_start_time)   AS usage_date,
          service.description      AS service_name,
          SUM(cost)                AS cost_usd
        FROM `${var.project_id}.gcp_billing_export.gcp_billing_export_v1_01D081_BB268A_137D65`
        WHERE cost > 0
        GROUP BY 1, 2
      ),

      daily_total_cost AS (
        SELECT
          usage_date,
          SUM(cost_usd) AS total_cost_usd
        FROM daily_billing
        GROUP BY 1
      ),

      -- 15分メトリクスを日次集計（server 別）
      daily_players AS (
        SELECT
          DATE(timestamp)                                                          AS usage_date,
          server,
          AVG(CASE WHEN metric_name = 'mc:players_online:avg15m' THEN value END)  AS avg_players,
          MAX(CASE WHEN metric_name = 'mc:players_online:max15m' THEN value END)  AS peak_players,
          AVG(CASE WHEN metric_name = 'mc:tps:avg15m'             THEN value END) AS avg_tps,
          MIN(CASE WHEN metric_name = 'mc:tps:min15m'             THEN value END) AS min_tps,
          AVG(CASE WHEN metric_name = 'mc:jvm_memory_used_bytes:avg15m' THEN value END)
            / (1024 * 1024 * 1024)                                                AS avg_memory_gib
        FROM `${var.project_id}.minecraft_monitoring.server_metrics`
        GROUP BY 1, 2
      ),

      -- 全サーバー合計プレイヤー数（コスト按分の分母）
      daily_total_players AS (
        SELECT
          usage_date,
          SUM(avg_players) AS total_avg_players
        FROM daily_players
        GROUP BY 1
      )

      SELECT
        dp.usage_date,
        dp.server,
        ROUND(dp.avg_players,  2)    AS avg_players_daily,
        ROUND(dp.peak_players, 0)    AS peak_players_daily,
        ROUND(dp.avg_tps,      2)    AS avg_tps_daily,
        ROUND(dp.min_tps,      2)    AS min_tps_daily,
        ROUND(dp.avg_memory_gib, 3)  AS avg_memory_gib_daily,
        ROUND(dtc.total_cost_usd, 4) AS daily_gcp_cost_usd,
        -- プレイヤー比率でサーバー別にコストを按分
        ROUND(
          SAFE_DIVIDE(dp.avg_players, dtp.total_avg_players) * dtc.total_cost_usd,
          6
        )                            AS server_attributed_cost_usd,
        -- 平均接続プレイヤー1人あたりのコスト（$）
        ROUND(
          SAFE_DIVIDE(dtc.total_cost_usd, dtp.total_avg_players),
          6
        )                            AS cost_per_avg_player_usd
      FROM daily_players dp
      LEFT JOIN daily_total_cost dtc    ON dp.usage_date = dtc.usage_date
      LEFT JOIN daily_total_players dtp ON dp.usage_date = dtp.usage_date
      ORDER BY dp.usage_date DESC, dp.server
    SQL
  }

  labels = merge(local.common_labels, {
    purpose = "minecraft-monitoring"
  })

  depends_on = [google_bigquery_table.server_metrics]
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

output "looker_studio_cost_analysis_url" {
  description = "Looker Studio コスト分析ダッシュボード用データソース接続 URL"
  value       = "https://lookerstudio.google.com/datasources/create?connectorId=bigQuery&projectId=${var.project_id}&datasetId=minecraft_monitoring&tableId=cost_analysis_view"
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
