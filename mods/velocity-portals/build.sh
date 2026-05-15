#!/usr/bin/env bash
# velocity-portals mod ビルドスクリプト (Docker使用、Java/Gradle不要)
# 使い方: ./build.sh
# 成果物: build/libs/velocityportals-1.21.1-1.0.0.jar

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_TAG="vp-builder-$(date +%s)"
OUTPUT_DIR="${SCRIPT_DIR}/build/libs"

echo "=== VelocityPortals mod ビルド開始 ==="
echo "作業ディレクトリ: ${SCRIPT_DIR}"

# Docker イメージをビルド
echo "--- Docker イメージをビルド中 (初回は NeoForge のダウンロードで 5〜10 分かかります) ---"
docker build \
  -f "${SCRIPT_DIR}/Dockerfile.build" \
  -t "${IMAGE_TAG}" \
  "${SCRIPT_DIR}"

# コンテナを作成して /output から JAR を取り出す
echo "--- JAR ファイルを取り出し中 ---"
mkdir -p "${OUTPUT_DIR}"
CONTAINER_ID=$(docker create "${IMAGE_TAG}")
docker cp "${CONTAINER_ID}:/output/." "${OUTPUT_DIR}/"
docker rm "${CONTAINER_ID}"

# ビルド用イメージを削除
docker rmi "${IMAGE_TAG}"

echo ""
echo "=== ビルド完了 ==="
ls -lh "${OUTPUT_DIR}"/*.jar 2>/dev/null || echo "[ERROR] JAR が見つかりません。Dockerfile.build のログを確認してください"
