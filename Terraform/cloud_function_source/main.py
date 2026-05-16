"""
Minecraft ログイベント加工 Cloud Function (Gen2).

mc-raw-logs から Pub/Sub プッシュ通知を受け取り:
  1. Minecraft ログ行をパース
  2. UUID 行から playername → XUID マッピングをキャッシュ
  3. ログイン/ログアウト行を検出 → XUID + salt を SHA256 ハッシュ
  4. クリーンイベントを mc-clean-events に publish

依存: stdlib のみ（billing_notifier と同じパターン）。
"""

import base64
import hashlib
import json
import os
import re
import urllib.error
import urllib.request
from datetime import datetime, timezone, timedelta

# ---------------------------------------------------------------------------
# 正規表現パターン
# ---------------------------------------------------------------------------

# Java Edition: コンテナ内 /data/logs/latest.log の生フォーマット
# 例: [16May2026 15:28:45.076] [Server thread/INFO] [net.minecraft.server.MinecraftServer/]: shinari20b joined the game
LOGIN_PATTERN = re.compile(
    r"\[\d{1,2}\w{3}\d{4} \d{2}:\d{2}:\d{2}\.\d{3}\] \[[^\]]*\]: (\w+) joined the game"
)
LOGOUT_PATTERN = re.compile(
    r"\[\d{1,2}\w{3}\d{4} \d{2}:\d{2}:\d{2}\.\d{3}\] \[[^\]]*\]: (\w+) left the game"
)
UUID_PATTERN = re.compile(
    r"\[\d{1,2}\w{3}\d{4} \d{2}:\d{2}:\d{2}\.\d{3}\] \[[^\]]*\]: UUID of player (\w+) is ([0-9a-f\-]+)"
)

# ---------------------------------------------------------------------------
# グローバルキャッシュ（ウォームインスタンスで再利用）
# ---------------------------------------------------------------------------

_player_xuid_map: dict[str, str] = {}  # playername → XUID (ハイフン除去)
_salt: str | None = None  # Secret Manager から取得したハッシュ salt


# ---------------------------------------------------------------------------
# GCP ヘルパー（stdlib + metadata server パターン）
# ---------------------------------------------------------------------------


def _get_access_token() -> str:
    """GCE/Cloud Functions メタデータサーバーからアクセストークン取得。"""
    req = urllib.request.Request(
        "http://metadata.google.internal/computeMetadata/v1/"
        "instance/service-accounts/default/token",
        headers={"Metadata-Flavor": "Google"},
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        body = json.loads(resp.read().decode())
    return body["access_token"]


def _get_salt(project_id: str, secret_name: str) -> str:
    """Secret Manager から mc-player-hash-salt を取得（グローバルキャッシュ）。"""
    global _salt
    if _salt is not None:
        return _salt

    token = _get_access_token()
    url = (
        f"https://secretmanager.googleapis.com/v1/projects/{project_id}"
        f"/secrets/{secret_name}/versions/latest:access"
    )
    req = urllib.request.Request(
        url, headers={"Authorization": f"Bearer {token}"}
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = json.loads(resp.read().decode())
        _salt = body["payload"]["data"]
        # base64 decode
        _salt = base64.b64decode(_salt).decode()
    except urllib.error.HTTPError as e:
        error_body = e.read().decode() if e.fp else "(no body)"
        print(f"ERROR: Secret Manager アクセス失敗: {e.code} {error_body}")
        raise
    return _salt


def _publish_clean_event(
    project_id: str,
    topic_name: str,
    event: dict,
    token: str,
) -> None:
    """mc-clean-events トピックに整形済みイベントを publish。"""
    url = (
        f"https://pubsub.googleapis.com/v1/projects/{project_id}"
        f"/topics/{topic_name}:publish"
    )
    payload = json.dumps({
        "messages": [{
            "data": base64.b64encode(
                json.dumps(event).encode()
            ).decode(),
        }]
    })
    req = urllib.request.Request(
        url,
        data=payload.encode(),
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = json.loads(resp.read().decode())
        print(f"INFO: クリーンイベント publish 成功: {body.get('messageIds', [])}")
    except urllib.error.HTTPError as e:
        error_body = e.read().decode() if e.fp else "(no body)"
        print(f"ERROR: Pub/Sub publish 失敗: {e.code} {error_body}")
        raise


# ---------------------------------------------------------------------------
# エントリーポイント
# ---------------------------------------------------------------------------


def process_log_event(event: dict, context=None) -> tuple[str, int]:
    """Pub/Sub トリガーで呼び出されるメイン関数（Gen2 background function シグネチャ）。

    event["data"] に base64 エンコードされたログイベント JSON が格納されている。
    context は Eventarc から渡されるメタデータ（使用しない）。
    """
    project_id = os.environ.get("PROJECT_ID", "")
    salt_secret_name = os.environ.get("HASH_SALT_SECRET_NAME", "")

    JST = timezone(timedelta(hours=9))  # 日本標準時

    # 1. Pub/Sub メッセージをデコード
    raw_data = event.get("data", "")
    if not raw_data:
        print("WARNING: 空メッセージ、スキップ")
        return ("OK", 200)

    try:
        payload = json.loads(base64.b64decode(raw_data).decode())
    except Exception as e:
        print(f"ERROR: メッセージデコード失敗: {e}")
        return ("ERROR", 400)

    message = payload.get("message", "")
    server = payload.get("server", "unknown")
    event_timestamp = payload.get("event_timestamp", datetime.now(JST).isoformat())
    direct_xuid = payload.get("xuid", "")  # Bedrock はログシッパーが直接 XUID を添付

    if not message:
        print("WARNING: message フィールドなし、スキップ")
        return ("OK", 200)

    print(f"DEBUG: ログ行 [{server}] {message.strip()}")

    # ── Bedrock モード: xuid が直接指定されている ──
    if direct_xuid:
        # 注意: "disconnected" は "connected" を含むため先に判定
        if "disconnected" in message.lower() or "left" in message.lower():
            event_type = "logout"
        elif "connected" in message.lower() or "joined" in message.lower():
            event_type = "login"
        else:
            print(f"DEBUG: Bedrock イベントタイプ不明、スキップ")
            return ("OK", 200)

        player_name = "bedrock_player"  # Bedrock はプレイヤー名を使わず XUID でハッシュ
        xuid = direct_xuid
        print(f"INFO: Bedrock XUID 直接使用: {xuid}")
    else:
        # ── Java モード: メッセージをパースして UUID→XUID を解決 ──
        uuid_match = UUID_PATTERN.search(message)
        if uuid_match:
            player_name = uuid_match.group(1)
            xuid_with_hyphens = uuid_match.group(2)
            xuid = xuid_with_hyphens.replace("-", "")
            _player_xuid_map[player_name] = xuid
            print(f"INFO: XUID マッピング登録: {player_name} → xuid({len(xuid)}桁)")
            return ("OK", 200)

        login_match = LOGIN_PATTERN.search(message)
        if login_match:
            player_name = login_match.group(1)
            event_type = "login"
        else:
            logout_match = LOGOUT_PATTERN.search(message)
            if logout_match:
                player_name = logout_match.group(1)
                event_type = "logout"
            else:
                print(f"DEBUG: ログインパターンにもログアウトパターンにも一致せずスキップ")
                return ("OK", 200)

        # Java: プレイヤー名から XUID を解決
        xuid = _player_xuid_map.get(player_name)
        if xuid:
            print(f"INFO: XUID ベースハッシュ: {player_name}")
        else:
            # XUID 未取得の場合はプレイヤー名でフォールバック
            xuid = player_name
            print(f"WARNING: XUID 未取得のため playername でハッシュ: {player_name}")

    # 3. player_hash 計算
    raw_input = xuid + _get_salt(project_id, salt_secret_name)

    player_hash = hashlib.sha256(raw_input.encode()).hexdigest()

    # 4. クリーンイベントを publish
    clean_event = {
        "player_hash": player_hash,
        "event_type": event_type,
        "event_timestamp": event_timestamp,
        "server": server,
    }
    token = _get_access_token()
    _publish_clean_event(project_id, "mc-clean-events", clean_event, token)

    print(f"INFO: 処理完了: {event_type} {player_name} → {player_hash[:16]}...")
    return ("OK", 200)

# v2.2: Bedrock "spawned" 誤検出修正（死亡リスポン時にloginと誤認する問題を修正）
