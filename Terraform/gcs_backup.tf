# ============================================================
# GCS Coldline バックアップバケット
# ============================================================
# 対象: Minecraft ワールドデータ（Bedrock / Java）
# スケジュール: 毎月1日 03:00 JST（k3s CronJob から gsutil でアップロード）
# 認証: k3s ノードから user ADC を k8s Secret として使用
#
# ライフサイクル:
#   作成 → 30日後 ARCHIVE → 365日後（1年）削除
# ============================================================

resource "google_storage_bucket" "mc_backups" {
  project                     = var.project_id
  name                        = "sushiski-mc-backups"
  location                    = "ASIA-NORTHEAST1"
  storage_class               = "COLDLINE"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  # 30日後 COLDLINE → ARCHIVE へ降格
  # 注: COLDLINE の最低保存期間は 90 日のため、30 日での降格には
  #     残り 60 日分の早期削除料金が発生する（数百MB規模では誤差）
  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
  }

  # 1年（365日）後に削除
  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type = "Delete"
    }
  }

  labels = merge(local.common_labels, {
    purpose = "minecraft-backup"
  })
}

# mc-proxy-sa に objectAdmin を付与（将来の GCE 経由バックアップ用）
resource "google_storage_bucket_iam_member" "mc_proxy_backup_admin" {
  bucket = google_storage_bucket.mc_backups.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.mc_proxy_sa.email}"
}

# ============================================================
# Outputs
# ============================================================

output "mc_backups_bucket_name" {
  description = "Minecraft バックアップ GCS バケット名"
  value       = google_storage_bucket.mc_backups.name
}

output "mc_backups_setup_note" {
  description = "k3s CronJob 用 GCS 認証情報 Secret 作成手順"
  value       = <<-EOT
    1. ユーザー ADC で認証:
         gcloud auth application-default login

    2. ADC ファイルを k8s Secret として登録:
         kubectl create secret generic gcs-backup-credentials \
           -n minecraft \
           --from-file=key.json=$HOME/.config/gcloud/application_default_credentials.json

    3. CronJob をデプロイ:
         kubectl apply -f k8s/onprem/35-gcs-backup-cronjob.yaml

    4. 動作確認（手動トリガー）:
         kubectl create job -n minecraft gcs-backup-manual \
           --from=cronjob/gcs-backup-cronjob
         kubectl logs -n minecraft -l job-name=gcs-backup-manual -f
  EOT
}
