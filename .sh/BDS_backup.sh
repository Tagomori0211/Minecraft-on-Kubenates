#!/bin/bash

# ==============================================================================
# Script: BDS_backup.sh
# Description:
# 1. BDSのPodを特定
# 2. 30秒前にアナウンス「30秒後にサーバーは再起動します。」
# 3. 30秒待機
# 4. stopコマンドでグレースフルシャットダウン
# 5. worlds, permissions.json, server.properties, allowlist.json をtar圧縮
# 6. BDS起動
# 7. MinIOへアップロードし、成功後にローカルファイルを削除
# ==============================================================================

export LANG=C.UTF-8

# スクリプトのディレクトリを取得して.envやBDS_say.shのパスを決定
DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DIR="$(dirname "$DIR")"

# .env をパースして環境変数を取得
if [ -f "${ROOT_DIR}/.env" ]; then
  # 余分なスペースなどを xargs で除去
  BUCKETNAME=$(awk -F'=' '/^BUCKETNAME/ {print $2}' "${ROOT_DIR}/.env" | xargs)
  ACCESS_IP=$(awk -F'=' '/^ACCESS_IP/ {print $2}' "${ROOT_DIR}/.env" | xargs)
  ACCESSKEY=$(awk -F'=' '/^ACCESSKEY/ {print $2}' "${ROOT_DIR}/.env" | xargs)
  SECRETKEY=$(awk -F'=' '/^(SERCETKEY|SECRETKEY)/ {print $2}' "${ROOT_DIR}/.env" | xargs)
else
  echo "❌ エラー: .env ファイルが見つかりません。(${ROOT_DIR}/.env)"
  exit 1
fi

if [ -z "$ACCESS_IP" ] || [ -z "$ACCESSKEY" ] || [ -z "$SECRETKEY" ] || [ -z "$BUCKETNAME" ]; then
  echo "❌ エラー: .env ファイルに MinIO の認証情報が不足しています。"
  exit 1
fi

# MinIOポート (デフォルト9000を使用)
MINIO_PORT=${MINIO_PORT:-9000}
MINIO_URL="http://${ACCESS_IP}:${MINIO_PORT}"

# 1. BDS Podの特定
NAMESPACE="minecraft"
echo "🔎 Bedrock Podを検索中..."
POD_NAME=$(ssh k3s-worker "sudo kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/component=bedrock -o jsonpath='{.items[0].metadata.name}'" 2>/dev/null)

if [ -z "$POD_NAME" ] || [ "$POD_NAME" == "null" ]; then
  echo "❌ エラー: BedrockのPodが見つかりませんでした。"
  exit 1
fi
echo "✅ Bedrock Podを特定しました: ${POD_NAME}"

# 2. アナウンス
echo "📢 30秒前の再起動アナウンスを送信..."
"${DIR}/BDS_say.sh" "30秒後にサーバーは再起動します。"

# 3. 30秒待機
echo "⏳ 30秒待機中..."
sleep 30

# 4. サーバーのグレースフルシャットダウン
echo "🛑 サーバーをシャットダウンしています..."
# stopコマンドを送信してグレースフルにデータを保存・終了
ssh k3s-worker "sudo kubectl exec -n ${NAMESPACE} ${POD_NAME} -c bedrock -- send-command stop" 2>/dev/null
echo "⏳ データの保存を待機中 (10秒)..."
sleep 10
# Deploymentのスケールダウンを行い、再起動を防ぐ
ssh k3s-worker "sudo kubectl scale deployment deploy-bedrock -n ${NAMESPACE} --replicas=0" >/dev/null 2>&1
# 完全終了を待つ
ssh k3s-worker "sudo kubectl wait --for=delete pod/${POD_NAME} -n ${NAMESPACE} --timeout=120s" 2>/dev/null || sleep 5

# 5. バックアップ作成
DATE_STR=$(date +%Y-%m-%d)
TAR_FILE="${DIR}/${DATE_STR}.tar.gz"
echo "📦 テンポラリPodを起動してデータを圧縮中: ${TAR_FILE}"

# テンポラリPodを立ち上げ、PVCマウント下でtarを実行
ssh k3s-worker "sudo kubectl run bds-backup-temp --image=alpine --restart=Never -n ${NAMESPACE} --overrides='{\"spec\": {\"volumes\": [{\"name\": \"data\", \"persistentVolumeClaim\": {\"claimName\": \"pvc-bedrock\"}}], \"containers\": [{\"name\": \"bds-backup-temp\", \"image\": \"alpine\", \"command\": [\"sleep\", \"3600\"], \"volumeMounts\": [{\"name\": \"data\", \"mountPath\": \"/data\"}]}]}}'" >/dev/null 2>&1

ssh k3s-worker "sudo kubectl wait --for=condition=Ready pod/bds-backup-temp -n ${NAMESPACE} --timeout=60s" >/dev/null 2>&1

# tar 実行しローカルにファイルを作成 (指示の permission.json は実際のディレクトリの permissions.json を指すため合わせる)
ssh k3s-worker "sudo kubectl exec bds-backup-temp -n ${NAMESPACE} -- sh -c 'tar -czf - -C /data worlds permissions.json server.properties allowlist.json 2>/dev/null'" > "${TAR_FILE}"

echo "🧹 テンポラリPodを削除中..."
ssh k3s-worker "sudo kubectl delete pod bds-backup-temp -n ${NAMESPACE}" >/dev/null 2>&1

if [ ! -s "${TAR_FILE}" ]; then
  echo "⚠️ 警告: バックアップファイルの作成に失敗したか、ファイルが空です。"
else
  echo "✅ バックアップ作成完了: $(ls -lh "${TAR_FILE}" | awk '{print $5}')"
fi

# 6. サーバー起動
echo "🚀 サーバーを再起動しています..."
ssh k3s-worker "sudo kubectl scale deployment deploy-bedrock -n ${NAMESPACE} --replicas=1" >/dev/null 2>&1

# 7. MinIOへアップロード
if [ -s "${TAR_FILE}" ]; then
  echo "☁️ MinIO (${MINIO_URL}) へのアップロードを開始..."
  
  # mc (MinIO Client) の準備
  if ! command -v mc &> /dev/null && [ ! -x "${DIR}/mc" ]; then
    echo "⬇️ mc クライアントをダウンロード中..."
    wget -qO "${DIR}/mc" https://dl.min.io/client/mc/release/linux-amd64/mc
    chmod +x "${DIR}/mc"
  fi
  
  MC_BIN="mc"
  [ -x "${DIR}/mc" ] && MC_BIN="${DIR}/mc"

  # MinIO エイリアスの設定とアップロード
  ${MC_BIN} alias set myminio "${MINIO_URL}" "${ACCESSKEY}" "${SECRETKEY}" >/dev/null 2>&1
  
  # ファイル名(yyyy-mm-dd.tar.gz)のみ抽出
  TAR_FILENAME=$(basename "${TAR_FILE}")

  if ${MC_BIN} cp "${TAR_FILE}" "myminio/${BUCKETNAME}/${TAR_FILENAME}"; then
    echo "✅ アップロード成功！"
    echo "🗑️ ローカルのバックアップファイル (${TAR_FILE}) を削除します。"
    rm -f "${TAR_FILE}"
  else
    echo "❌ エラー: アップロードに失敗しました。"
    echo "💡 ネットワークやポート(9000)、認証情報を確認してください。"
    echo "💡 ローカルファイルは保持されます: ${TAR_FILE}"
  fi
fi

echo "🎉 バックアッププロセスが完了しました。"
