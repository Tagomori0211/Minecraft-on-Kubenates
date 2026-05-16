package dev.tak.velocityportals;

import net.minecraft.network.FriendlyByteBuf;
import net.minecraft.network.codec.StreamCodec;
import net.minecraft.network.protocol.common.ClientboundCustomPayloadPacket;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerPlayer;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

/**
 * BungeeCord/Velocity プラグインチャンネル経由でプレイヤーを別サーバーへ転送する。
 *
 * Velocity は "bungeecord:main" チャンネルを監視し、
 * "Connect" サブチャンネルを受け取ると指定サーバーへ転送する。
 *
 * パケット構造:
 *   channel: bungeecord:main
 *   payload: writeUtf("Connect") + writeUtf(targetServer)
 */
public class BungeeCordMessenger {

    private static final Logger LOGGER = LogManager.getLogger("VelocityPortals");

    /**
     * "bungeecord:main" チャンネル用のカスタムペイロード。
     * MC 1.21.1 では CustomPacketPayload に write() がないため、
     * エンコードは STREAM_CODEC 経由で行う。
     */
    public record ConnectPayload(String targetServer) implements CustomPacketPayload {

        public static final Type<ConnectPayload> TYPE =
            new Type<>(ResourceLocation.fromNamespaceAndPath("bungeecord", "main"));

        // Velocity がパケットを横取りするため、decode側はダミーで問題ない
        public static final StreamCodec<FriendlyByteBuf, ConnectPayload> STREAM_CODEC =
            StreamCodec.of(
                (buf, payload) -> {
                    buf.writeUtf("Connect");
                    buf.writeUtf(payload.targetServer());
                },
                buf -> {
                    buf.readUtf();  // "Connect" を読み捨て
                    return new ConnectPayload(buf.readUtf());
                }
            );

        @Override
        public Type<ConnectPayload> type() {
            return TYPE;
        }
    }

    /**
     * 指定プレイヤーを targetServer へ転送する。
     * Velocity が bungeecord:main の Connect メッセージを横取りしてサーバー転送を実行する。
     */
    public static void connectToServer(ServerPlayer player, String targetServer) {
        try {
            player.connection.send(new ClientboundCustomPayloadPacket(new ConnectPayload(targetServer)));
            LOGGER.info("[VelocityPortals] {} → {} へ転送パケットを送信しました",
                player.getName().getString(), targetServer);
        } catch (Exception e) {
            LOGGER.error("[VelocityPortals] 転送パケット送信エラー ({}): {}",
                player.getName().getString(), e.getMessage());
        }
    }
}
