#!/usr/bin/env python3
"""
VictoriaMetrics の recording rule 結果を BigQuery にストリーミング INSERT する。

実行環境: GCE VM 上の Docker コンテナ (google/cloud-sdk:slim)
認証: GCE インスタンスメタデータ経由の ADC (SA key 不要)
"""
import base64
import hashlib
import json
import os
import subprocess
import tempfile
import urllib.parse
import urllib.request
from datetime import datetime, timezone


def _load_project_id() -> str:
    """プロジェクト ID を環境変数 → GCE メタデータの順で取得する。"""
    bq_project = os.environ.get("BQ_PROJECT", "")
    if bq_project:
        return bq_project
    try:
        req = urllib.request.Request(
            "http://metadata.google.internal/computeMetadata/v1/project/project-id",
            headers={"Metadata-Flavor": "Google"},
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.read().decode()
    except Exception as e:
        raise RuntimeError(f"GCE メタデータからプロジェクト ID を取得できませんでした: {e}") from e


# GCE mc-monitoring-1 VictoriaMetrics (Tailscale 経由)
VM_URL = os.environ.get("VM_URL", "http://100.121.113.37:8428")
BQ_PROJECT = _load_project_id()
BQ_TABLE = "minecraft_monitoring.server_metrics"

# minecraft_status_* から 15 分平均/最大/最小を PromQL で集計する
# (vmalert recording rules は未使用のため直接クエリ)
METRICS = [
    "avg_over_time(minecraft_status_players_online_count{server_edition='java'}[15m])",
    "max_over_time(minecraft_status_players_online_count{server_edition='java'}[15m])",
    "avg_over_time(minecraft_status_response_time_seconds{server_edition='java'}[15m])",
    "min_over_time(minecraft_status_healthy{server_edition='java'}[15m])",
]

# BQ に保存する metric_name（METRICS リストと 1:1 対応）
METRIC_NAMES = [
    "mc:players_online:avg15m",
    "mc:players_online:max15m",
    "mc:response_time_seconds:avg15m",
    "mc:healthy:min15m",
]


def _get_gce_access_token() -> str:
    """GCE インスタンスメタデータからアクセストークンを取得する。"""
    req = urllib.request.Request(
        "http://metadata.google.internal/computeMetadata/v1/"
        "instance/service-accounts/default/token",
        headers={"Metadata-Flavor": "Google"},
    )
    with urllib.request.urlopen(req, timeout=5) as resp:
        return json.loads(resp.read())["access_token"]


def get_player_hash_salt() -> str:
    """Secret Manager から XUID ハッシュ化用 salt を取得する。"""
    token = _get_gce_access_token()
    url = (
        f"https://secretmanager.googleapis.com/v1/projects/{BQ_PROJECT}"
        "/secrets/mc-player-hash-salt/versions/latest:access"
    )
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        payload_b64 = json.loads(resp.read())["payload"]["data"]
    return base64.b64decode(payload_b64).decode()


def hash_xuid(xuid: str, salt: str) -> str:
    """SHA256(XUID + salt) を返す。Looker Studio 公開時に生 XUID を隠蔽する。"""
    return hashlib.sha256((xuid + salt).encode()).hexdigest()


def query_vm(metric: str) -> list:
    """VictoriaMetrics HTTP API から instant query を実行して結果を返す。"""
    url = f"{VM_URL}/api/v1/query?query={urllib.parse.quote(metric)}"
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            return json.loads(resp.read()).get("data", {}).get("result", [])
    except Exception as e:
        print(f"[WARN] VM query failed for {metric}: {e}", flush=True)
        return []


def main() -> None:
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    rows = []

    for expr, metric_name in zip(METRICS, METRIC_NAMES):
        for r in query_vm(expr):
            server = r["metric"].get("component", "unknown")
            raw = r.get("value", [None, None])[1]
            # NoData（サーバー停止中等）はスキップ
            if raw is None or raw == "NaN":
                continue
            rows.append({
                "timestamp": ts,
                "player_hash": None,    # 将来のプレイヤー粒度メトリクス用（現在 NULL）
                "server": server,
                "metric_name": metric_name,
                "value": float(raw),
            })

    print(f"[{ts}] {len(rows)} rows collected from VictoriaMetrics", flush=True)
    if not rows:
        return

    with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
        for row in rows:
            f.write(json.dumps(row) + "\n")
        tmpfile = f.name

    try:
        proc = subprocess.run(
            ["bq", "insert", f"--project_id={BQ_PROJECT}", BQ_TABLE, tmpfile],
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            print(f"[ERROR] bq insert failed: {proc.stderr}", flush=True)
            raise SystemExit(1)
        print(
            f"[{ts}] Inserted {len(rows)} rows → {BQ_PROJECT}:{BQ_TABLE}",
            flush=True,
        )
    finally:
        os.unlink(tmpfile)


if __name__ == "__main__":
    main()
