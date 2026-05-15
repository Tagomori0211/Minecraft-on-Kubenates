package dev.tak.velocityportals;

import io.netty.buffer.Unpooled;
import net.minecraft.network.FriendlyByteBuf;
import net.minecraft.network.protocol.common.ClientboundCustomPayloadPacket;
import net.minecraft.network.protocol.common.custom.CustomPacketPayload;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.server.level.ServerPlayer;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

/**
 * BungeeCord/Velocity プラグインチャンネル経由でプレイヤーを別サーバーへ転送する。
 *
 * Velocity は "bungeecord:main" チャンネルのカスタムパケットを監視しており、
 * "Connect" サブチャンネルを受け取ると指定サーバーへ転送する。
 *
 * パケット構造:
 *   channel:  bungeecord:main  (ResourceLocation として packet が自動付与)
 *   payload:  [utf "Connect"] [utf targetServer]
 */
public class BungeeCordMessenger {

    private static final Logger LOGGER = LogManager.getLogger("VelocityPortals");

    /** BungeeCord プラグインチャンネル Type (static 定数として1度だけ生成) */
    private static final CustomPacketPayload.Type<ConnectPayload> BUNGEE_TYPE =
        new CustomPacketPayload.Type<>(
            ResourceLocation.fromNamespaceAndPath("bungeecord", "main")
        );

    /**
     * bungeecord:main チャンネルに "Connect" メッセージを送るペイロード実装。
     * write() でサブチャンネル名とサーバー名を UTF-8 文字列として書き込む。
     */
    private record ConnectPayload(String targetServer) implements CustomPacketPayload {

        @Override
        public void write(FriendlyByteBuf buf) {
            buf.writeUtf("Connect");
            buf.writeUtf(targetServer);
        }

        @Override
        public Type<? extends CustomPacketPayload> type() {
            return BUNGEE_TYPE;
        }
    }

    /**
     * 指定プレイヤーを targetServer へ転送するパケットを送信する。
     * Velocity が bungeecord:main の "Connect" メッセージを横取りして転送する。
     */
    public static void connectToServer(ServerPlayer player, String targetServer) {
        try {
            ConnectPayload payload = new ConnectPayload(targetServer);
            ClientboundCustomPayloadPacket packet = new ClientboundCustomPayloadPacket(payload);
            player.connection.send(packet);

            LOGGER.info("[VelocityPortals] {} → {} へ転送パケットを送信しました",
                player.getName().getString(), targetServer);

        } catch (Exception e) {
            LOGGER.error("[VelocityPortals] 転送パケット送信エラー ({}): {}",
                player.getName().getString(), e.getMessage());
        }
    }
}
