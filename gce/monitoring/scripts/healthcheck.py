"""
オンプレ沈黙検知 HealthCheck スクリプト

mc-monitoring-1 上の Docker Compose サービス healthcheck から 5 分ごとに実行される。
ローカル VictoriaMetrics に「オンプレ vmagent が生きていれば必ず存在するメトリクス」を
クエリし、データが途絶（= オンプレ k3s 沈黙）していれば Pub/Sub topic billing-alerts に
{"type":"onprem_silence", ...} を publish する。discord-notifier がそれを pull して
「オンプレ沈黙アラート」を Discord に送る（mermaid: HealthCheck → PubSub → Alert_Job → Discord）。

認証: GCE VM (mc-monitoring-1) の mc-monitoring-sa ADC（メタデータ経由）
      → Pub/Sub publisher 権限が必要（Terraform/notifications.tf）
"""
import base64
import json
import os
import sys
import time
import urllib.parse
import urllib.request


PROJECT_ID = "project-61cf5742-d0ea-45ed-ac0"
TOPIC      = f"projects/{PROJECT_ID}/topics/billing-alerts"
# ローカル（同一 VM 内）の VictoriaMetrics
VM_URL     = os.environ.get("VM_URL", "http://victoria-metrics:8428")
# オンプレ生存の指標: vmagent が remote_write していれば最近のサンプルが存在する。
# 5 分以内にサンプルが無ければ沈黙とみなす。
PROBE_QUERY = os.environ.get(
    "PROBE_QUERY",
    "count(up{location='onprem'} == 1)",
)
LOOP_INTERVAL = 300


def _get_access_token() -> str:
    req = urllib.request.Request(
        "http://metadata.google.internal/computeMetadata/v1/"
        "instance/service-accounts/default/token",
        headers={"Metadata-Flavor": "Google"},
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read())["access_token"]


def _publish_silence(token: str, detail: str) -> None:
    url = f"https://pubsub.googleapis.com/v1/{TOPIC}:publish"
    data = base64.b64encode(
        json.dumps({"type": "onprem_silence", "detail": detail}).encode()
    ).decode()
    body = json.dumps({"messages": [{"data": data}]}).encode()
    req = urllib.request.Request(
        url, data=body,
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        resp.read()
    print(f"オンプレ沈黙を publish: {detail}", flush=True)


def _is_onprem_alive() -> bool:
    """VictoriaMetrics にオンプレ生存メトリクスが存在するか判定する。"""
    url = f"{VM_URL}/api/v1/query?query={urllib.parse.quote(PROBE_QUERY)}"
    with urllib.request.urlopen(url, timeout=10) as resp:
        result = json.loads(resp.read()).get("data", {}).get("result", [])
    if not result:
        return False
    value = result[0].get("value", [None, "0"])[1]
    return float(value) > 0


def check_once() -> None:
    try:
        alive = _is_onprem_alive()
    except Exception as e:
        # VM 自体に到達できない場合も沈黙として扱う
        token = _get_access_token()
        _publish_silence(token, f"VictoriaMetrics クエリ失敗: {e}")
        return
    if alive:
        print("オンプレ生存確認 OK", flush=True)
        return
    token = _get_access_token()
    _publish_silence(token, f"オンプレ生存メトリクスが 0 件（{PROBE_QUERY}）")


def main() -> None:
    print(f"healthcheck loop start (interval={LOOP_INTERVAL}s, VM={VM_URL})", flush=True)
    while True:
        try:
            check_once()
        except Exception as e:
            print(f"スクリプトエラー（継続）: {e}", flush=True, file=sys.stderr)
        time.sleep(LOOP_INTERVAL)


if __name__ == "__main__":
    main()
