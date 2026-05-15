package dev.tak.velocityportals;

import com.electronwill.nightconfig.core.UnmodifiableConfig;
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
        } catch (Exception e) {
            LOGGER.warn("[VelocityPortals] FileWatcher の登録に失敗しました: {}", e.getMessage());
        }
    }

    /**
     * 設定ファイルを読み込んで zones を更新する。
     * nightconfig の [[portals]] エントリは UnmodifiableConfig として返される。
     */
    public static synchronized void loadConfig() {
        if (configPath == null || !Files.exists(configPath)) return;

        List<PortalZone> loaded = new ArrayList<>();
        try (CommentedFileConfig cfg = CommentedFileConfig.builder(configPath).build()) {
            cfg.load();

            // [[portals]] の各エントリは UnmodifiableConfig (StampedConfig) で返される
            List<UnmodifiableConfig> portals = cfg.getOrElse("portals", List.of());
            for (UnmodifiableConfig p : portals) {
                String name   = p.getOrElse("name", "unnamed");
                String target = p.getOrElse("target_server", "survival");
                int    dim    = toInt(p.getOrElse("dimension", 0));
                double minX   = toDouble(p.getOrElse("min_x", 0.0));
                double minY   = toDouble(p.getOrElse("min_y", 60.0));
                double minZ   = toDouble(p.getOrElse("min_z", 0.0));
                double maxX   = toDouble(p.getOrElse("max_x", 3.0));
                double maxY   = toDouble(p.getOrElse("max_y", 64.0));
                double maxZ   = toDouble(p.getOrElse("max_z", 3.0));

                loaded.add(new PortalZone(name, target, dim, minX, minY, minZ, maxX, maxY, maxZ));
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

    // ---- ヘルパー: nightconfig は TOML 整数を Long、小数を Double で返す ----

    private static int toInt(Object v) {
        if (v instanceof Number n) return n.intValue();
        return 0;
    }

    private static double toDouble(Object v) {
        if (v instanceof Number n) return n.doubleValue();
        return 0.0;
    }

    /** デフォルト設定ファイルをコメント付きで生成する。 */
    private static void writeDefaultConfig() {
        String content =
            "# VelocityPortals 設定ファイル\n" +
            "# ポータルゾーンを [[portals]] ブロックで複数定義できます。\n" +
            "# ゾーン内に入ったプレイヤーは target_server へ転送されます。\n" +
            "# dimension: 0=overworld, -1=nether, 1=end\n" +
            "# target_server は Velocity の velocity.toml [servers] セクションのキー名\n" +
            "\n" +
            "# 例: survival ポータル (座標 100,60,100 ～ 103,64,103)\n" +
            "[[portals]]\n" +
            "  name          = \"survival-portal\"\n" +
            "  target_server = \"survival\"\n" +
            "  dimension     = 0\n" +
            "  min_x         = 100.0\n" +
            "  min_y         = 60.0\n" +
            "  min_z         = 100.0\n" +
            "  max_x         = 103.0\n" +
            "  max_y         = 64.0\n" +
            "  max_z         = 103.0\n" +
            "\n" +
            "# 例: industry ポータル\n" +
            "#[[portals]]\n" +
            "#  name          = \"industry-portal\"\n" +
            "#  target_server = \"mod\"\n" +
            "#  dimension     = 0\n" +
            "#  min_x         = 200.0\n" +
            "#  min_y         = 60.0\n" +
            "#  min_z         = 200.0\n" +
            "#  max_x         = 203.0\n" +
            "#  max_y         = 64.0\n" +
            "#  max_z         = 203.0\n";

        try {
            Files.writeString(configPath, content);
            LOGGER.info("[VelocityPortals] デフォルト設定ファイルを生成しました: {}", configPath);
        } catch (IOException e) {
            LOGGER.error("[VelocityPortals] 設定ファイルの生成に失敗しました: {}", e.getMessage());
        }
    }
}
