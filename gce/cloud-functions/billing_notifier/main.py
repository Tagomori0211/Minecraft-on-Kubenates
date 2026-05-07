"""
GCP Billing Budget アラート → Discord 通知 Cloud Function (Gen1)

トリガー: Pub/Sub topic `billing-alerts`
認証: Cloud Function SA (billing-notifier-sa) の ADC で Secret Manager から webhook URL 取得
"""
import base64
import json
import os
import urllib.request
from urllib.error import URLError


def handle_billing_alert(event, context):
    """Pub/Sub トリガーエントリーポイント。Budget アラートを Discord に転送する。"""
    raw = base64.b64decode(event["data"]).decode("utf-8")
    data = json.loads(raw)

    threshold = float(data.get("alertThresholdExceeded", 0))
    cost = float(data.get("costAmount", 0))
    budget = float(data.get("budgetAmount", 0))
    budget_name = data.get("budgetDisplayName", "Minecraft Infrastructure")
    currency = data.get("currencyCode", "USD")
    project_id = data.get("projectId", os.environ.get("PROJECT_ID", "-"))

    pct = int(round(threshold * 100))
    is_over = threshold >= 1.0
    color = 0xE74C3C if is_over else 0xFF9F43  # 赤(100%) / オレンジ(90%)
    icon = "🚨" if is_over else "⚠️"

    ratio_str = f"{cost / budget * 100:.1f}%" if budget > 0 else "N/A"
    embed = {
        "title": f"{icon} GCP 課金アラート {pct}%",
        "description": (
            f"予算 **{budget_name}** の **{pct}%** しきい値を超過しました。\n"
            f"現在の支出: **{currency} {cost:.2f}** / 予算: {currency} {budget:.2f}"
        ),
        "color": color,
        "fields": [
            {"name": "支出率", "value": ratio_str, "inline": True},
            {"name": "プロジェクト", "value": project_id, "inline": True},
        ],
    }

    webhook_url = _get_webhook_url()
    print(f"[DEBUG] webhook_url prefix: {webhook_url[:50]!r}", flush=True)
    payload = json.dumps({"embeds": [embed]}).encode()
    req = urllib.request.Request(
        webhook_url,
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    try:
        urllib.request.urlopen(req, timeout=10)
        print(f"Discord 通知送信完了: {pct}% アラート", flush=True)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")[:500]
        print(f"Discord HTTP エラー {e.code}: {body}", flush=True)
        raise
    except URLError as e:
        print(f"Discord 通知失敗: {e}", flush=True)
        raise


def _get_gce_access_token() -> str:
    """Cloud Function 実行環境のメタデータサーバーからアクセストークンを取得する。"""
    req = urllib.request.Request(
        "http://metadata.google.internal/computeMetadata/v1/"
        "instance/service-accounts/default/token",
        headers={"Metadata-Flavor": "Google"},
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read())["access_token"]


def _get_webhook_url() -> str:
    """Secret Manager から Discord webhook URL を取得する。"""
    secret_name = os.environ["SECRET_NAME"]
    project_id = os.environ["PROJECT_ID"]
    token = _get_gce_access_token()

    url = (
        f"https://secretmanager.googleapis.com/v1/projects/{project_id}"
        f"/secrets/{secret_name}/versions/latest:access"
    )
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        payload_b64 = json.loads(resp.read())["payload"]["data"]
    return base64.b64decode(payload_b64).decode().strip()
