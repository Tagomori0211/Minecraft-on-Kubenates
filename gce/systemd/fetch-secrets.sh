#!/bin/bash
# ============================================================
# Secret Manager から forwarding.secret を取得して配置
# ============================================================
# systemd unit `mc-proxy.service` の ExecStartPre で実行
# /opt/mc-proxy/velocity/forwarding.secret に平文で書き出し
# パーミッション 600（root のみ読み取り可）
# ============================================================

set -euo pipefail

readonly SECRET_NAME="velocity-forwarding-secret"
readonly TARGET_FILE="/opt/mc-proxy/velocity/forwarding.secret"

mkdir -p "$(dirname "${TARGET_FILE}")"

# Secret Manager から最新版を取得（gcloud は cloud-init でインストール済み前提）
gcloud secrets versions access latest \
  --secret="${SECRET_NAME}" \
  > "${TARGET_FILE}"

chmod 600 "${TARGET_FILE}"
chown root:root "${TARGET_FILE}"

echo "[fetch-secrets] forwarding.secret を ${TARGET_FILE} に配置しました"
