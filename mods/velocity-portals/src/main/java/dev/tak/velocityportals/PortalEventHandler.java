package dev.tak.velocityportals;

import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.phys.Vec3;
import net.neoforged.bus.api.SubscribeEvent;
import net.neoforged.neoforge.event.entity.player.PlayerEvent;
import net.neoforged.neoforge.event.tick.PlayerTickEvent;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * PlayerTickEvent を監視してポータルゾーンに入ったプレイヤーを転送する。
 * 設定はゲーム起動時 + ファイル変更時に PortalConfig から動的にリロードされる。
 */
public class PortalEventHandler {

    private static final Logger LOGGER = LogManager.getLogger("VelocityPortals");

    /** 転送クールダウン: UUID → 次に転送可能なシステム時刻(ms) */
    private final Map<UUID, Long> cooldowns = new HashMap<>();

    /** 転送後のクールダウン時間(ms): 5秒 */
    private static final long COOLDOWN_MS = 5_000L;

    /** ティックカウンタ(毎ティック呼ばれるため、チェックを間引く用) */
    private int tickCounter = 0;

    /** 初回起動時に設定を読み込む */
    public PortalEventHandler() {
        PortalConfig.init();
        LOGGER.info("[VelocityPortals] PortalEventHandler が初期化されました");
    }

    /**
     * プレイヤーがサーバーに参加したときにクールダウンを設定する。
     * Velocity 経由で別サーバーから戻ってきた際、ログイン座標がポータルゾーン内でも
     * 即座に再転送されるループを防ぐ。
     */
    @SubscribeEvent
    public void onPlayerJoin(PlayerEvent.PlayerLoggedInEvent event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) return;
        cooldowns.put(player.getUUID(), System.currentTimeMillis() + COOLDOWN_MS);
        LOGGER.debug("[VelocityPortals] {} の参加クールダウンを設定しました", player.getName().getString());
    }

    /**
     * サーバーサイドの PlayerTickEvent.Post を受信する。
     * 20ティックに1回(約1秒)チェックして負荷を抑える。
     */
    @SubscribeEvent
    public void onPlayerTick(PlayerTickEvent.Post event) {
        if (!(event.getEntity() instanceof ServerPlayer player)) return;

        // 20tick に1回だけチェック（各プレイヤー個別にカウントするため tickCounter はグローバル）
        tickCounter++;
        if (tickCounter % 20 != 0) return;

        // クールダウン中はスキップ
        UUID uuid = player.getUUID();
        long now = System.currentTimeMillis();
        Long cooldownUntil = cooldowns.get(uuid);
        if (cooldownUntil != null && now < cooldownUntil) return;

        // プレイヤーの現在座標とディメンション
        Vec3 pos = player.position();
        ServerLevel level = (ServerLevel) player.level();
        int dimId = getDimensionId(level);

        List<PortalZone> zones = PortalConfig.getZones();
        for (PortalZone zone : zones) {
            if (zone.dimension != dimId) continue;
            if (!zone.contains(pos.x, pos.y, pos.z)) continue;

            // ゾーン内に入っている → 転送
            LOGGER.info("[VelocityPortals] {} がポータル '{}' に入りました → {}",
                player.getName().getString(), zone.name, zone.targetServer);

            cooldowns.put(uuid, now + COOLDOWN_MS);
            BungeeCordMessenger.connectToServer(player, zone.targetServer);
            return; // 複数ゾーンが重なっていても最初のものだけ適用
        }
    }

    /** ディメンション → 数値IDを返す（overworld=0, nether=-1, end=1）。 */
    private static int getDimensionId(ServerLevel level) {
        String dim = level.dimension().location().toString();
        return switch (dim) {
            case "minecraft:the_nether" -> -1;
            case "minecraft:the_end"    -> 1;
            default                     -> 0;
        };
    }
}
