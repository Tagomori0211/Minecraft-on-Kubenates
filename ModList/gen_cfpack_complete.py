#!/usr/bin/env python3
"""
完結版 CurseForge modpack zip を生成する。
全 MOD JAR を overrides/mods/ に梱包し、CF App のダウンロード不要で動作する。

- Modrinth CDN (62 MOD): mrpack/modrinth.index.json の downloads URL を使用
- CF専用 (2 MOD, Athena・TwilightForest): CFWidget API でファイル名取得後
  edge.forgecdn.net からダウンロード

再実行時はキャッシュ (cfpack_cache/) を使用してスキップ。
"""

import hashlib
import json
import sys
import time
import urllib.request
import zipfile
from pathlib import Path

GAME_VERSION = "1.21.1"
NEOFORGE_VER = "21.1.228"
USER_AGENT = "sushi-java-cfpack-gen/1.0 (github.com/Tagomori0211)"
CFWIDGET_API = "https://api.cfwidget.com"

# Modrinthにないため CurseForge から直接取得する MOD
# project_id: CFWidget がスラグで 404 の場合に数値IDエンドポイントを使用
CF_ONLY_MODS = [
    {"slug": "athena",            "project_id": 841890, "file_id": 8061947},
    {"slug": "the-twilight-forest", "project_id": 227639, "file_id": 7797302},
]


def sha1_of(path: Path) -> str:
    return hashlib.sha1(path.read_bytes()).hexdigest()


def download_file(url: str, dest: Path, expected_sha1: str | None = None) -> bool:
    """URLからファイルをダウンロードする。キャッシュ済みかつSHA1一致の場合はスキップ。"""
    if dest.exists():
        if expected_sha1:
            if sha1_of(dest) == expected_sha1:
                print(f"  [CACHE] {dest.name}")
                return True
            print(f"  [STALE] {dest.name} (SHA1不一致、再ダウンロード)")
        else:
            print(f"  [CACHE] {dest.name}")
            return True

    print(f"  [DL]    {dest.name} ...", end="", flush=True)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            data = r.read()
    except Exception as e:
        print(f" ERROR: {e}")
        return False

    if expected_sha1:
        actual = hashlib.sha1(data).hexdigest()
        if actual != expected_sha1:
            print(f" SHA1不一致 expected={expected_sha1} actual={actual}")
            return False

    dest.write_bytes(data)
    print(f" OK ({len(data) / 1024:.0f} KB)")
    return True


def fetch_cf_filename(slug: str, project_id: int, file_id: int) -> str | None:
    """CFWidget API でスラグ→数値IDの順で問い合わせ、file_id に対応するファイル名を返す。"""
    urls = [
        f"{CFWIDGET_API}/minecraft/mc-mods/{slug}",
        f"{CFWIDGET_API}/{project_id}",  # スラグが未登録の場合の数値IDフォールバック
    ]
    for url in urls:
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                data = json.loads(r.read())
            for f in data.get("files", []):
                if f.get("id") == file_id:
                    return f["name"]
        except Exception:
            pass
        time.sleep(0.6)
    return None


def main() -> None:
    here = Path(__file__).parent
    cache_dir = here / "cfpack_cache"
    cache_dir.mkdir(exist_ok=True)
    out_dir = here / "cfpack"
    out_dir.mkdir(exist_ok=True)

    mrpack_index_path = here / "mrpack" / "modrinth.index.json"
    index = json.loads(mrpack_index_path.read_text(encoding="utf-8"))

    jar_paths: list[Path] = []
    failed: list[str] = []

    # ── Step 1: Modrinth CDN から全 MOD をダウンロード ──────────────────────
    entries = index["files"]
    print(f"\n[STEP 1] Modrinth CDN から {len(entries)} MOD をダウンロード")
    for entry in entries:
        filename = Path(entry["path"]).name
        dest = cache_dir / filename
        url = entry["downloads"][0]
        sha1 = entry["hashes"].get("sha1")
        if download_file(url, dest, sha1):
            jar_paths.append(dest)
        else:
            failed.append(filename)

    # ── Step 2: CF専用 MOD をダウンロード ────────────────────────────────────
    print(f"\n[STEP 2] CF専用 MOD ({len(CF_ONLY_MODS)} 件) をダウンロード")
    for mod in CF_ONLY_MODS:
        slug = mod["slug"]
        file_id = mod["file_id"]
        print(f"  [CFWidget] {slug} のファイル名取得中...", end="", flush=True)
        filename = fetch_cf_filename(slug, mod["project_id"], file_id)
        if not filename:
            print(" 取得失敗")
            failed.append(slug)
            continue
        print(f" → {filename}")

        # CF CDN URL: files/{fileID/1000}/{fileID%1000}/{filename}
        part1 = file_id // 1000
        part2 = file_id % 1000
        url = f"https://edge.forgecdn.net/files/{part1}/{part2}/{filename}"
        dest = cache_dir / filename
        if download_file(url, dest):
            jar_paths.append(dest)
        else:
            failed.append(filename)
        time.sleep(0.6)

    if not jar_paths:
        print("\n[ERROR] ダウンロードできた MOD が 0 件です。中止します。")
        sys.exit(1)

    # ── Step 3: ZIP 作成 ────────────────────────────────────────────────────
    print(f"\n[STEP 3] ZIP 作成 ({len(jar_paths)} MOD 梱包)")
    manifest = {
        "minecraft": {
            "version": GAME_VERSION,
            "modLoaders": [{"id": f"neoforge-{NEOFORGE_VER}", "primary": True}],
        },
        "manifestType": "minecraftModpack",
        "manifestVersion": 1,
        "name": "すしJava",
        "version": "1.0.0",
        "author": "Tagomori0211",
        # 全 MOD は overrides/mods/ に梱包するため files は空
        "files": [],
        "overrides": "overrides",
    }

    zip_path = out_dir / "sushiJava-1.0.0-cf.zip"
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
        for jar in sorted(jar_paths, key=lambda p: p.name):
            arc_name = f"overrides/mods/{jar.name}"
            zf.write(jar, arc_name)
            print(f"  + {arc_name}")

    total_mb = zip_path.stat().st_size / 1024 / 1024
    print(f"\n[DONE] {zip_path}")
    print(f"       サイズ: {total_mb:.1f} MB")
    print(f"       MOD数: {len(jar_paths)} 件")

    if failed:
        print(f"\n[MISSING] 失敗した MOD ({len(failed)} 件):")
        for name in failed:
            print(f"  - {name}")
        sys.exit(1)


if __name__ == "__main__":
    main()
