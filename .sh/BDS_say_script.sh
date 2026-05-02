#!/bin/bash

# ==============================================================================
# Script: BDS_say_script.sh
# Description: Sends a 'say' command to the Bedrock Dedicated Server (BDS) console
# Usage: ./BDS_say_script.sh "<message>"
# Example: ./BDS_say_script.sh "日本語も対応させること"
# ==============================================================================

# 引数チェック
if [ -z "$1" ]; then
  echo "Usage: $0 <message>"
  echo "Example: $0 \"日本語も対応させること\""
  exit 1
fi

MESSAGE="$1"

# BDSのPodが配置されているNamespace（実稼働環境に合わせて指定）
# ※指示には「bedrock」とありましたが、現在のクラスタでは「minecraft」にあるため対応しています。
NAMESPACE="minecraft"

echo "🔎 Bedrock Podを検索中..."

# Label `app.kubernetes.io/component=bedrock` を用いてPodを特定
POD_NAME=$(ssh k3s-worker "sudo kubectl get pods -n ${NAMESPACE} -l app.kubernetes.io/component=bedrock -o jsonpath='{.items[0].metadata.name}'" 2>/dev/null)

# もし指定Namespaceで見つからない場合は全Namespaceからフォールバック検索
if [ -z "$POD_NAME" ] || [ "$POD_NAME" == "null" ]; then
  POD_NAME=$(ssh k3s-worker "sudo kubectl get pods -A -l app.kubernetes.io/component=bedrock -o jsonpath='{.items[0].metadata.name}'" 2>/dev/null)
  if [ -n "$POD_NAME" ] && [ "$POD_NAME" != "null" ]; then
    NAMESPACE=$(ssh k3s-worker "sudo kubectl get pods -A -l app.kubernetes.io/component=bedrock -o jsonpath='{.items[0].metadata.namespace}'" 2>/dev/null)
  fi
fi

if [ -z "$POD_NAME" ] || [ "$POD_NAME" == "null" ]; then
  echo "❌ エラー: BedrockのPodが見つかりませんでした。"
  exit 1
fi

echo "✅ Bedrock Podを特定しました: ${POD_NAME} (Namespace: ${NAMESPACE})"
echo "💬 メッセージを送信中: ${MESSAGE}"

# send-command を使用してBDSコンソールに "say" コマンドを打つ
# ※ $MESSAGE 内のダブルクォートなどはよしなにエスケープして送信
ssh k3s-worker "sudo kubectl exec -n ${NAMESPACE} ${POD_NAME} -c bedrock -- send-command \"say ${MESSAGE}\""

if [ $? -eq 0 ]; then
  echo "🚀 送信完了!"
else
  echo "⚠️ 送信に失敗しました。"
  exit 1
fi
