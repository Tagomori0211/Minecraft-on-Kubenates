#!/usr/bin/env python3
"""
VictoriaMetrics の recording rule 結果を BigQuery にストリーミング INSERT する。

実行環境: GCE VM 上の Docker コンテナ (google/cloud-sdk:slim)
認証: GCE インスタンスメタデータ経由の ADC (SA key 不要)
"""
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


# k3s VictoriaMetrics NodePort (Tailscale 経由)
VM_URL = os.environ.get("VM_URL", "http://100.107.122.45:30428")
BQ_PROJECT = _load_project_id()
BQ_TABLE = "minecraft_monitoring.server_metrics"

# vmalert が生成する 15 分集計 recording rules
METRICS = [
    "mc:players_online:avg15m",
    "mc:players_online:max15m",
    "mc:tps:avg15m",
    "mc:tps:min15m",
    "mc:jvm_memory_used_bytes:avg15m",
]


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

    for metric in METRICS:
        for r in query_vm(metric):
            server = r["metric"].get("component", "unknown")
            raw = r.get("value", [None, None])[1]
            # NoData（サーバー停止中・Bedrock の mc_tps 未対応等）はスキップ
            if raw is None or raw == "NaN":
                continue
            rows.append({
                "timestamp": ts,
                "player_hash": None,    # 将来のプレイヤー粒度メトリクス用（現在 NULL）
                "server": server,
                "metric_name": metric,
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
