package dev.tak.velocityportals;

import com.electronwill.nightconfig.core.file.CommentedFileConfig;
import com.electronwill.nightconfig.core.file.FileWatcher;
import net.neoforged.fml.loading.FMLPaths;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * velocityportals.toml を読み込み、PortalZone リストを管理する。
 *
 * 設定例:
 * [[portals]]
 *   name = "survival-portal"
 *   target_server = "survival"
 *   dimension = 0
 *   min_x = 100.0
 *   min_y = 60.0
 *   min_z = 100.0
 *   max_x = 103.0
 *   max_y = 64.0
 *   max_z = 103.0
 */
public class PortalConfig {

    private static final Logger LOGGER = LogManager.getLogger("VelocityPortals");
    private static final String CONFIG_FILE = "velocityportals.toml";

    private static volatile List<PortalZone> zones = new ArrayList<>();
    private static Path configPath;

    /** 初回読み込みと FileWatcher による自動リロードを開始する。 */
    public static void init() {
        configPath = FMLPaths.CONFIGDIR.get().resolve(CONFIG_FILE);

        if (!Files.exists(configPath)) {
            writeDefaultConfig();
        }

        loadConfig();

        // 設定ファイル変更時に自動リロード
        try {
            FileWatcher.defaultInstance().addWatch(configPath, PortalConfig::loadConfig);
            LOGGER.info("[VelocityPortals] 設定ファイルの自動リロードを有効化しました");
        } catch (IOException e) {
            LOGGER.warn("[VelocityPortals] FileWatcher の登録に失敗しました: {}", e.getMessage());
        }
    }

    /** 設定ファイルを読み込んで zones を更新する。 */
    @SuppressWarnings("unchecked")
    public static synchronized void loadConfig() {
        if (configPath == null || !Files.exists(configPath)) return;

        List<PortalZone> loaded = new ArrayList<>();
        try (CommentedFileConfig cfg = CommentedFileConfig.builder(configPath).build()) {
            cfg.load();

            List<Map<String, Object>> portals = cfg.getOrElse("portals", List.of());
            for (Map<String, Object> p : portals) {
                String name        = getString(p, "name", "unnamed");
                String target      = getString(p, "target_server", "survival");
                int    dimension   = getInt(p, "dimension", 0);
                double minX        = getDouble(p, "min_x", 0.0);
                double minY        = getDouble(p, "min_y", 60.0);
                double minZ        = getDouble(p, "min_z", 0.0);
                double maxX        = getDouble(p, "max_x", 3.0);
                double maxY        = getDouble(p, "max_y", 64.0);
                double maxZ        = getDouble(p, "max_z", 3.0);

                loaded.add(new PortalZone(name, target, dimension, minX, minY, minZ, maxX, maxY, maxZ));
                LOGGER.info("[VelocityPortals] ポータル読み込み: {}", loaded.get(loaded.size() - 1));
            }
        } catch (Exception e) {
            LOGGER.error("[VelocityPortals] 設定ファイルの読み込みに失敗しました: {}", e.getMessage());
        }

        zones = loaded;
        LOGGER.info("[VelocityPortals] {}個のポータルゾーンを読み込みました", zones.size());
    }

    public static List<PortalZone> getZones() {
        return zones;
    }

    // ---- ヘルパー ----

    private static String getString(Map<String, Object> map, String key, String def) {
        Object v = map.get(key);
        return v != null ? v.toString() : def;
    }

    private static int getInt(Map<String, Object> map, String key, int def) {
        Object v = map.get(key);
        if (v instanceof Number n) return n.intValue();
        return def;
    }

    private static double getDouble(Map<String, Object> map, String key, double def) {
        Object v = map.get(key);
        if (v instanceof Number n) return n.doubleValue();
        return def;
    }

    /** デフォルト設定ファイルをコメント付きで生成する。 */
    private static void writeDefaultConfig() {
        String content =
            "# VelocityPortals 設定ファイル\n" +
            "# ポータルゾーンを [[portals]] ブロックで複数定義できます。\n" +
            "# ゾーン内に入ったプレイヤーは target_server へ転送されます。\n" +
            "# dimension: 0=overworld, -1=nether, 1=end\n" +
            "\n" +
            "# 例: survival ポータル (座標 100,60,100 ～ 103,64,103)\n" +
            "[[portals]]\n" +
            "  name         = \"survival-portal\"\n" +
            "  target_server = \"survival\"\n" +
            "  dimension    = 0\n" +
            "  min_x        = 100.0\n" +
            "  min_y        = 60.0\n" +
            "  min_z        = 100.0\n" +
            "  max_x        = 103.0\n" +
            "  max_y        = 64.0\n" +
            "  max_z        = 103.0\n" +
            "\n" +
            "# 例: industry ポータル\n" +
            "#[[portals]]\n" +
            "#  name         = \"industry-portal\"\n" +
            "#  target_server = \"mod\"\n" +
            "#  dimension    = 0\n" +
            "#  min_x        = 200.0\n" +
            "#  min_y        = 60.0\n" +
            "#  min_z        = 200.0\n" +
            "#  max_x        = 203.0\n" +
            "#  max_y        = 64.0\n" +
            "#  max_z        = 203.0\n";

        try {
            Files.writeString(configPath, content);
            LOGGER.info("[VelocityPortals] デフォルト設定ファイルを生成しました: {}", configPath);
        } catch (IOException e) {
            LOGGER.error("[VelocityPortals] 設定ファイルの生成に失敗しました: {}", e.getMessage());
        }
    }
}
