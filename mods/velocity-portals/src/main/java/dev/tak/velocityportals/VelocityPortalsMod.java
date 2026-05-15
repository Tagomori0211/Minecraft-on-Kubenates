package dev.tak.velocityportals;

import net.neoforged.bus.api.IEventBus;
import net.neoforged.fml.ModContainer;
import net.neoforged.fml.common.Mod;
import net.neoforged.fml.event.lifecycle.FMLCommonSetupEvent;
import net.neoforged.neoforge.common.NeoForge;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

@Mod("velocityportals")
public class VelocityPortalsMod {

    public static final Logger LOGGER = LogManager.getLogger("VelocityPortals");

    public VelocityPortalsMod(IEventBus modEventBus, ModContainer container) {
        modEventBus.addListener(this::onCommonSetup);
    }

    private void onCommonSetup(FMLCommonSetupEvent event) {
        // サーバーサイドのイベントハンドラを登録
        // PortalConfig.init() は PortalEventHandler コンストラクタ内で呼ばれる
        NeoForge.EVENT_BUS.register(new PortalEventHandler());
        LOGGER.info("[VelocityPortals] ポータルイベントハンドラを登録しました");
        LOGGER.info("[VelocityPortals] 設定ファイル: config/velocityportals.toml");
    }
}
