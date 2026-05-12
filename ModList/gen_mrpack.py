#!/usr/bin/env python3
"""
modlist.html（CurseForge URLリスト）から Modrinth パッケージ（.mrpack）を生成する。
- CurseForge slug → Modrinth slug マッピング
- Modrinth API でバージョン情報を取得して modrinth.index.json を生成
- NeoForge 21.1.228 / Mekanism 10.7.19.85 / mekanism_extras 1.4.0 対応
"""

import json
import re
import sys
import time
import zipfile
from html.parser import HTMLParser
from pathlib import Path
import urllib.request

MODRINTH_API  = "https://api.modrinth.com/v2"
USER_AGENT    = "sushi-java-mrpack-gen/1.0 (github.com/Tagomori0211)"
GAME_VERSION  = "1.21.1"
NEOFORGE_VER  = "21.1.228"

# CurseForge slug → Modrinth slug
# 同名の場合は省略可能だが、念のため全部明示
CF_TO_MODRINTH: dict[str, str | None] = {
    "applied-energistics-2":        "ae2",
    "applied-energistics-2-wireless-terminals": "applied-energistics-2-wireless-terminals",
    "applied-mekanistics":          "applied-mekanistics",
    "aquaculture":                  "aquaculture",
    "aquaculture-delight":          "aquaculture-delight",
    "balm":                         "balm",
    "bookshelf":                    "bookshelf-lib",
    "botany-pots":                  "botany-pots",
    "botany-trees":                 "botany-trees",
    "brewin-and-chewin":            "brewin-and-chewin",
    "carry-on":                     "carry-on",
    "chipped":                      "chipped",
    "connected-glass":              "connected-glass",
    "cosmetic-armor-reworked-forked":"cosmetic-armor-reworked-forked",
    "crabbers-delight":             "crabbers-delight",
    "cultural-delights":            "cultural-delights",
    "embeddium":                    "embeddium",
    "emi":                          "emi",
    "ends-delight":                 "ends-delight",
    "evolved-mekanism":             "evolved-mekanism",
    "expanded-delight":             "expanded-delight",
    "farmers-delight":              "farmers-delight",
    "ferritecore":                  "ferrite-core",
    "forge-config-api-port":        "forge-config-api-port",
    "fusion-connected-textures":    "fusion-connected-textures",
    "geckolib":                     "geckolib",
    "gravestone-mod":               "gravestone-mod",   # CF slug は gravestone-mod
    "guideme":                      "guideme",
    "handcrafted":                  "handcrafted",
    "iglee-library":                "iglee-library",    # CF slug は iglee-library
    "jade":                         "jade",
    "journeymap":                   "journeymap",
    "kuma-api":                     "kuma-api",
    "liteminer":                    "liteminer",
    "mekanism":                     "mekanism",
    "mekanism-additions":           "mekanism-additions",
    "mekanism-extras":              "mekanism_extra",       # Modrinth slug は mekanism_extra
    "mekanism-generators":          "mekanism-generators",
    "mekanism-lasers":              "mekanism-lasers",
    "mekanism-more-machine":        "mekanismmoremachine",
    "mekanism-tools":               "mekanism-tools",
    "modernfix":                    "modernfix",
    "more-delight-forge":           "more-delight",
    "my-nethers-delight":           "my-nethers-delight",
    "neat":                         "neat",
    "prickle":                      "prickle",
    "resourceful-lib":              "resourceful-lib",
    "rustic-delight":               "rustic-delight",
    "sophisticated-backpacks":      "sophisticated-backpacks",
    "sophisticated-core":           "sophisticated-core",
    "supermartijn642s-config-lib":  "supermartijn642s-config-lib",
    "supermartijn642s-core-lib":    "supermartijn642s-core-lib",
    "terrablender-neoforge":        "terrablender",
    "torchmaster":                  "torchmaster",
    "trail-tales-delight":          "trailtales-delight",
    "trash-cans":                   "trash-cans",
    "trashslot":                    "trashslot",
    "the-twilight-forest":          None,               # Modrinthに公式版なし（CurseForge専用）
    "waystones":                    "waystones",
    "yungs-api":                    "yungs-api",
    "yungs-better-caves":           "yungs-better-caves",
    "yungs-cave-biomes":            "yungs-cave-biomes",
    "appleskin":                    "appleskin",
    "amber-lib":                    "amber",            # CF slug は amber-lib
    # UNMAPPED追加分
    "architectury-api":             "architectury-api",
    "yungs-api-neoforge":           "yungs-api",
    "athena":                       None,   # terrariumearth製ライブラリ、Modrinthにneoforge版なし
    # クライアントのみMOD（サーバー不要 = server: unsupported にする）
    "journeymap-api":               None,   # 本体に同梱
}

# env設定（クライアントのみMOD）
CLIENT_ONLY_SLUGS = {
    "journeymap", "embeddium", "modernfix", "ferrite-core", "appleskin",
    "emi", "jade", "neat", "amber", "liteminer", "carry-on",
    "connected-glass", "fusion-connected-textures", "trashslot",
    "cosmetic-armor-reworked-forked", "forge-config-api-port",
    "kuma-api",
}

# 強制 version_id（確認済み）
FORCE_VERSION: dict[str, str] = {
    "mekanism":            "5KzzycBT",   # 10.7.19.85
    "mekanism-additions":  "6mkdykZa",   # 10.7.19.85
    "mekanism-generators": "a6gl7srE",   # 10.7.19.85
    "mekanism-tools":      "v5zlSE9s",   # 10.7.19.85
    "mekanism_extra":      "DsGsees0",   # 1.4.0
    "mekanismmoremachine": "3EMTKSFL",   # 1.3.3
}


def api_get(path: str):
    url = f"{MODRINTH_API}{path}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        print(f"  [WARN] HTTP {e.code} {url}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"  [WARN] {e} {url}", file=sys.stderr)
        return None


class CFUrlParser(HTMLParser):
    """modlist.htmlからCurseForge slugとMOD名称を抽出する。"""
    def __init__(self):
        super().__init__()
        self.entries: list[tuple[str, str]] = []  # (cf_slug, display_name)
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


def fetch_version(modrinth_slug: str) -> dict | None:
    """Modrinth slugからNeoForge 1.21.1対応バージョンを取得。"""
    # 強制バージョン優先
    force_id = FORCE_VERSION.get(modrinth_slug)
    if force_id:
        v = api_get(f"/version/{force_id}")
        if v:
            return v
        time.sleep(0.3)

    # 最新NeoForge/1.21.1対応版を取得
    encoded = f"?game_versions=%5B%221.21.1%22%5D&loaders=%5B%22neoforge%22%5D"
    versions = api_get(f"/project/{modrinth_slug}/version{encoded}")
    if not versions:
        return None
    # releaseを優先
    for v in versions:
        if v["version_type"] == "release":
            return v
    return versions[0]


def main():
    here = Path(__file__).parent
    modlist_path = here / "modlist.html"
    out_dir = here / "mrpack"
    out_dir.mkdir(exist_ok=True)

    parser = CFUrlParser()
    parser.feed(modlist_path.read_text(encoding="utf-8-sig"))
    entries = parser.entries
    print(f"[INFO] {len(entries)} MODs found in modlist.html\n")

    files_section = []
    missing = []

    for cf_slug, display_name in entries:
        modrinth_slug = CF_TO_MODRINTH.get(cf_slug)
        if modrinth_slug is None:
            # マッピング定義なし or スキップ指定
            if cf_slug in CF_TO_MODRINTH:
                print(f"  [SKIP] {display_name} ({cf_slug})")
            else:
                missing.append(f"{display_name} ({cf_slug})")
                print(f"  [UNMAPPED] {display_name} ({cf_slug})")
            continue

        print(f"  [FETCH] {display_name} → {modrinth_slug}", end="", flush=True)
        time.sleep(0.4)

        version = fetch_version(modrinth_slug)
        if not version or not version.get("files"):
            missing.append(f"{display_name} ({cf_slug})")
            print(" → NOT FOUND")
            continue

        pf = next((f for f in version["files"] if f.get("primary")), version["files"][0])

        env = {"client": "required", "server": "required"}
        if modrinth_slug in CLIENT_ONLY_SLUGS:
            env = {"client": "required", "server": "unsupported"}

        files_section.append({
            "path": f"mods/{pf['filename']}",
            "hashes": pf["hashes"],
            "env": env,
            "downloads": [pf["url"]],
            "fileSize": pf["size"],
        })
        print(f" → {version['version_number']} ✓")

    # modrinth.index.json 生成
    index = {
        "formatVersion": 1,
        "game": "minecraft",
        "versionId": "1.0.0",
        "name": "すしJava",
        "summary": f"NeoForge {NEOFORGE_VER} / Mekanism 10.7.19.85 対応",
        "files": files_section,
        "dependencies": {
            "minecraft": GAME_VERSION,
            "neoforge": NEOFORGE_VER,
        },
    }

    index_path = out_dir / "modrinth.index.json"
    index_path.write_text(json.dumps(index, ensure_ascii=False, indent=2), encoding="utf-8")

    mrpack_path = out_dir / "sushiJava-1.0.0.mrpack"
    with zipfile.ZipFile(mrpack_path, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.write(index_path, "modrinth.index.json")

    print(f"\n[DONE] {len(files_section)} entries → {mrpack_path}")

    if missing:
        miss_path = out_dir / "missing_mods.txt"
        miss_path.write_text("\n".join(missing), encoding="utf-8")
        print(f"\n[MISSING] {len(missing)} MODs not found on Modrinth:")
        for m in missing:
            print(f"  - {m}")
        print(f"  (saved to {miss_path})")


if __name__ == "__main__":
    main()
