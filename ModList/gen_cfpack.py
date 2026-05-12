#!/usr/bin/env python3
"""
modlist.html（CurseForge URLリスト）から CurseForge modpack（.zip）を生成する。
- CFWidget API（認証不要）で projectID・fileID を取得
- NeoForge 21.1.228 / Mekanism 10.7.19.85 / mekanism_extras 1.4.0 / mekmm 1.3.3 対応
- manifest.json を生成して zip に梱包
"""

import json
import re
import sys
import time
import zipfile
from html.parser import HTMLParser
from pathlib import Path
import urllib.request

CFWIDGET_API = "https://api.cfwidget.com/minecraft/mc-mods"
USER_AGENT   = "sushi-java-cfpack-gen/1.0 (github.com/Tagomori0211)"
GAME_VERSION = "1.21.1"
NEOFORGE_VER = "21.1.228"

# CFWidget がスラグで 404 になるMODの CF project ID フォールバック
# （スラグが CFWidget 未登録のため数値IDエンドポイントを使用）
CF_PROJECT_ID_FALLBACK: dict[str, int] = {
    "balm":                                      531761,
    "ferritecore":                               429235,
    "chipped":                                   456956,
    "architectury-api":                          419699,
    "supermartijn642s-core-lib":                 454372,
    "supermartijn642s-config-lib":               438332,
    "applied-energistics-2-wireless-terminals":  459929,
    "sophisticated-core":                        618298,
    "forge-config-api-port":                     547434,
}

# ファイル名サブストリングで強制バージョン指定（先頭マッチ優先）
FORCE_FILE_NAME: dict[str, str] = {
    "mekanism":            "Mekanism-1.21.1-10.7.19.85.jar",
    "mekanism-additions":  "MekanismAdditions-1.21.1-10.7.19.85.jar",
    "mekanism-generators": "MekanismGenerators-1.21.1-10.7.19.85.jar",
    "mekanism-tools":      "MekanismTools-1.21.1-10.7.19.85.jar",
    "mekanism-extras":     "mekanism_extras-1.21.1-1.4.0.jar",
    "mekanism-more-machine": "mekmm-1.21.1-1.3.3.jar",
}


def api_get(slug: str) -> dict | None:
    """CFWidget からプロジェクト情報を取得する。スラグで失敗した場合は数値IDでリトライ。"""
    for url in _build_urls(slug):
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            if e.code in (404, 400):
                continue  # 次のURLを試す
            print(f"  [WARN] HTTP {e.code} {url}", file=sys.stderr)
            return None
        except Exception as e:
            print(f"  [WARN] {e} {url}", file=sys.stderr)
            return None
    return None


def _build_urls(slug: str) -> list[str]:
    """スラグ用URLと、フォールバック用の数値ID URLのリストを返す。"""
    urls = [f"{CFWIDGET_API}/{slug}"]
    pid = CF_PROJECT_ID_FALLBACK.get(slug)
    if pid:
        urls.append(f"https://api.cfwidget.com/{pid}")
    return urls


class CFUrlParser(HTMLParser):
    """modlist.htmlからCurseForge slugとMOD名称を抽出する。"""
    def __init__(self):
        super().__init__()
        self.entries: list[tuple[str, str]] = []
        self._cur_slug: str | None = None

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            href = dict(attrs).get("href", "")
            m = re.search(r"curseforge\.com/minecraft/mc-mods/([^/\"]+)", href)
            if m:
                self._cur_slug = m.group(1).rstrip("/")

    def handle_data(self, data):
        if self._cur_slug:
            self.entries.append((self._cur_slug, data.strip()))
            self._cur_slug = None


def pick_file(cf_slug: str, files: list[dict]) -> dict | None:
    """強制指定ファイル名一致 → NeoForge+1.21.1 の最新リリースの順で選択する。"""
    # 強制バージョン指定
    forced_name = FORCE_FILE_NAME.get(cf_slug)
    if forced_name:
        for f in files:
            if f.get("name") == forced_name:
                return f
        # 見つからない場合はフォールバック
        print(f"  [WARN] forced file '{forced_name}' not found, falling back", file=sys.stderr)

    # NeoForge + 1.21.1 対応のリリース版を優先
    candidates = [
        f for f in files
        if GAME_VERSION in f.get("versions", [])
        and ("NeoForge" in f.get("versions", []) or "neoforge" in f.get("versions", []))
    ]
    releases = [f for f in candidates if f.get("type") == "release"]
    if releases:
        return releases[0]
    if candidates:
        return candidates[0]

    # フォールバック: 1.21.1のみ
    fallback = [f for f in files if GAME_VERSION in f.get("versions", [])]
    if fallback:
        return fallback[0]

    return None


def main():
    here = Path(__file__).parent
    modlist_path = here / "modlist.html"
    out_dir = here / "cfpack"
    out_dir.mkdir(exist_ok=True)

    parser = CFUrlParser()
    parser.feed(modlist_path.read_text(encoding="utf-8-sig"))
    entries = parser.entries
    print(f"[INFO] {len(entries)} MODs found in modlist.html\n")

    files_section = []
    missing = []

    for cf_slug, display_name in entries:
        print(f"  [FETCH] {display_name} → {cf_slug}", end="", flush=True)
        time.sleep(0.6)  # CFWidget レート制限対策

        data = api_get(cf_slug)
        if not data:
            missing.append(f"{display_name} ({cf_slug})")
            print(" → NOT FOUND")
            continue

        project_id = data["id"]
        chosen_file = pick_file(cf_slug, data.get("files", []))

        if not chosen_file:
            missing.append(f"{display_name} ({cf_slug})")
            print(f" → NO MATCHING FILE (projectID={project_id})")
            continue

        files_section.append({
            "projectID": project_id,
            "fileID": chosen_file["id"],
            "required": True,
            "_name": chosen_file["name"],  # デバッグ用（manifest.jsonには含めない）
        })
        print(f" → {chosen_file['name']} (pid={project_id}, fid={chosen_file['id']}) ✓")

    # manifest.json 生成（_name フィールドを除外）
    manifest_files = [
        {"projectID": f["projectID"], "fileID": f["fileID"], "required": f["required"]}
        for f in files_section
    ]
    manifest = {
        "minecraft": {
            "version": GAME_VERSION,
            "modLoaders": [
                {"id": f"neoforge-{NEOFORGE_VER}", "primary": True}
            ],
        },
        "manifestType": "minecraftModpack",
        "manifestVersion": 1,
        "name": "すしJava",
        "version": "1.0.0",
        "author": "Tagomori0211",
        "files": manifest_files,
        "overrides": "overrides",
    }

    manifest_path = out_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

    cfpack_path = out_dir / "sushiJava-1.0.0-cf.zip"
    with zipfile.ZipFile(cfpack_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(manifest_path, "manifest.json")
        # overrides/ ディレクトリエントリ（Python 3.10 対応: writestr で空エントリ作成）
        zf.writestr("overrides/", "")

    print(f"\n[DONE] {len(files_section)} entries → {cfpack_path}")

    if missing:
        miss_path = out_dir / "missing_mods.txt"
        miss_path.write_text("\n".join(missing), encoding="utf-8")
        print(f"\n[MISSING] {len(missing)} MODs:")
        for m in missing:
            print(f"  - {m}")
        print(f"  (saved to {miss_path})")


if __name__ == "__main__":
    main()
