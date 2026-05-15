package dev.tak.velocityportals;

/** ポータルゾーンの定義（設定ファイルから読み込まれる）。 */
public class PortalZone {

    public final String name;
    public final String targetServer;
    public final int dimension;  // 0=overworld, -1=nether, 1=end
    public final double minX, minY, minZ;
    public final double maxX, maxY, maxZ;

    public PortalZone(
            String name,
            String targetServer,
            int dimension,
            double minX, double minY, double minZ,
            double maxX, double maxY, double maxZ) {
        this.name = name;
        this.targetServer = targetServer;
        this.dimension = dimension;
        this.minX = minX;
        this.minY = minY;
        this.minZ = minZ;
        this.maxX = maxX;
        this.maxY = maxY;
        this.maxZ = maxZ;
    }

    /** プレイヤー座標がこのゾーン内かを判定する。 */
    public boolean contains(double x, double y, double z) {
        return x >= minX && x <= maxX
            && y >= minY && y <= maxY
            && z >= minZ && z <= maxZ;
    }

    @Override
    public String toString() {
        return String.format("[%s] dim=%d (%.1f,%.1f,%.1f)→(%.1f,%.1f,%.1f) → %s",
            name, dimension, minX, minY, minZ, maxX, maxY, maxZ, targetServer);
    }
}
