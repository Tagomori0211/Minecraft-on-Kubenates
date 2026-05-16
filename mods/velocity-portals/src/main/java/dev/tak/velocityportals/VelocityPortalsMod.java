package dev.tak.velocityportals;

import net.neoforged.bus.api.IEventBus;
import net.neoforged.fml.ModContainer;
import net.neoforged.fml.common.Mod;
import net.neoforged.fml.event.lifecycle.FMLCommonSetupEvent;
import net.neoforged.neoforge.common.NeoForge;
import net.neoforged.neoforge.network.event.RegisterPayloadHandlersEvent;
import net.neoforged.neoforge.network.registration.PayloadRegistrar;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

@Mod("velocityportals")
public class VelocityPortalsMod {

    public static final Logger LOGGER = LogManager.getLogger("VelocityPortals");

    public VelocityPortalsMod(IEventBus modEventBus, ModContainer container) {
        modEventBus.addListener(this::onCommonSetup);
        modEventBus.addListener(this::onRegisterPayloads);
    }

    private void onCommonSetup(FMLCommonSetupEvent event) {
        NeoForge.EVENT_BUS.register(new PortalEventHandler());
        LOGGER.info("[VelocityPortals] ポータルイベントハンドラを登録しました");
    }

    private void onRegisterPayloads(RegisterPayloadHandlersEvent event) {
        PayloadRegistrar registrar = event.registrar("velocityportals");
        // optional(): クライアントがこのチャンネルを知らなくてもよい（Velocityが横取りする）
        registrar.optional().commonToClient(
            BungeeCordMessenger.ConnectPayload.TYPE,
            BungeeCordMessenger.ConnectPayload.STREAM_CODEC,
            (payload, ctx) -> {}  // クライアント側ハンドラ（到達しないため空）
        );
        LOGGER.info("[VelocityPortals] BungeeCord:Connect ペイロードを登録しました");
    }
}
