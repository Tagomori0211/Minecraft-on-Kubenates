"""
GCP Billing Budget アラート → Discord 通知スクリプト

GCE VM 上で systemd timer (5分ごと) から実行される。
Pub/Sub Pull サブスクリプション billing-alerts-gce-pull をポーリングし、
メッセージがあれば Discord に embed 通知を送信して ACK する。

認証: GCE VM の mc-proxy-sa ADC（メタデータサーバー経由）
"""
import base64
import json
import sys
import urllib.request
from urllib.error import URLError


SUBSCRIPTION = "projects/project-61cf5742-d0ea-45ed-ac0/subscriptions/billing-alerts-gce-pull"
SECRET_NAME  = "mc-discord-webhook-url"
PROJECT_ID   = "project-61cf5742-d0ea-45ed-ac0"


def _get_access_token() -> str:
    """GCE メタデータサーバーからアクセストークンを取得する。"""
    req = urllib.request.Request(
        "http://metadata.google.internal/computeMetadata/v1/"
        "instance/service-accounts/default/token",
        headers={"Metadata-Flavor": "Google"},
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read())["access_token"]


def _get_webhook_url(token: str) -> str:
    """Secret Manager から Discord webhook URL を取得する。"""
    url = (
        f"https://secretmanager.googleapis.com/v1/projects/{PROJECT_ID}"
        f"/secrets/{SECRET_NAME}/versions/latest:access"
    )
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        payload_b64 = json.loads(resp.read())["payload"]["data"]
    return base64.b64decode(payload_b64).decode().strip()


def _pull_messages(token: str) -> list:
    """Pub/Sub から最大 10 件のメッセージを Pull する。"""
    url = f"https://pubsub.googleapis.com/v1/{SUBSCRIPTION}:pull"
    body = json.dumps({"maxMessages": 10}).encode()
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read()).get("receivedMessages", [])


def _ack_messages(token: str, ack_ids: list) -> None:
    """処理済みメッセージを ACK する。"""
    url = f"https://pubsub.googleapis.com/v1/{SUBSCRIPTION}:acknowledge"
    body = json.dumps({"ackIds": ack_ids}).encode()
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        resp.read()


def _send_discord(webhook_url: str, data: dict) -> None:
    """Budget アラートデータから Discord embed を構築して送信する。"""
    threshold = float(data.get("alertThresholdExceeded", 0))
    cost      = float(data.get("costAmount", 0))
    budget    = float(data.get("budgetAmount", 0))
    name      = data.get("budgetDisplayName", "Minecraft Infrastructure")
    currency  = data.get("currencyCode", "USD")
    project   = data.get("projectId", PROJECT_ID)

    pct     = int(round(threshold * 100))
    is_over = threshold >= 1.0
    color   = 0xE74C3C if is_over else 0xFF9F43  # 赤(100%) / オレンジ(90%)
    icon    = "🚨" if is_over else "⚠️"

    ratio_str = f"{cost / budget * 100:.1f}%" if budget > 0 else "N/A"
    # JPY は小数点なし、その他は 2 桁
    fmt = "{:,.0f}" if currency == "JPY" else "{:,.2f}"
    cost_str   = f"¥{fmt.format(cost)}"   if currency == "JPY" else f"{currency} {fmt.format(cost)}"
    budget_str = f"¥{fmt.format(budget)}" if currency == "JPY" else f"{currency} {fmt.format(budget)}"
    embed = {
        "title": f"{icon} GCP 課金アラート {pct}%",
        "description": (
            f"予算 **{name}** の **{pct}%** しきい値を超過しました。\n"
            f"現在の支出: **{cost_str}** / 予算上限: {budget_str}"
        ),
        "color": color,
        "fields": [
            {"name": "支出率",    "value": ratio_str, "inline": True},
            {"name": "プロジェクト", "value": project,   "inline": True},
        ],
    }

    payload = json.dumps({"embeds": [embed]}).encode()
    req = urllib.request.Request(
        webhook_url,
        data=payload,
        headers={
            "Content-Type": "application/json",
            # Cloudflare は Python-urllib を ASN レベルでブロックするため偽装が必要
            "User-Agent": "DiscordBot (https://github.com, 1.0)",
        },
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        resp.read()
    print(f"Discord 通知送信完了: {pct}% アラート", flush=True)


def main() -> None:
    token = _get_access_token()
    messages = _pull_messages(token)

    if not messages:
        print("メッセージなし", flush=True)
        return

    webhook_url = _get_webhook_url(token)
    ack_ids = []

    for msg in messages:
        ack_ids.append(msg["ackId"])
        try:
            raw  = base64.b64decode(msg["message"]["data"]).decode("utf-8")
            data = json.loads(raw)
            _send_discord(webhook_url, data)
        except Exception as e:
            print(f"通知失敗（ACK はスキップ）: {e}", flush=True)
            ack_ids.pop()  # 失敗したメッセージは ACK しない（リトライさせる）

    if ack_ids:
        _ack_messages(token, ack_ids)
        print(f"{len(ack_ids)} 件を ACK", flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"スクリプトエラー: {e}", flush=True, file=sys.stderr)
        sys.exit(1)
