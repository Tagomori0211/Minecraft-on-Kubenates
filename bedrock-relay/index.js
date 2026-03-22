const { Relay } = require('bedrock-protocol');

const HOST = process.env.LISTEN_HOST || '0.0.0.0';
const PORT = parseInt(process.env.LISTEN_PORT || "19132");
const DEST_HOST = process.env.DEST_HOST || '10.43.91.112'; // Default to k3s Bedrock ClusterIP 
const DEST_PORT = parseInt(process.env.DEST_PORT || "19132");

console.log(`Starting Bedrock Relay: listening on ${HOST}:${PORT}, forwarding to ${DEST_HOST}:${DEST_PORT}...`);

const relay = new Relay({
    host: HOST,
    port: PORT,
    destination: {
        host: DEST_HOST,
        port: DEST_PORT
    },
    // クライアントのXbox Live認証情報をBDSに透過させてXUID消失を防ぐ
    offline: false,
});

relay.listen();

relay.on('connect', player => {
    const xuid = player.profile?.xuid || 'Unknown';
    const name = player.profile?.name || 'Unknown';
    console.log(`[+] Player connected: ${name} (XUID: ${xuid})`);

    // エラーハンドリングなどを追加
    player.on('error', err => {
        console.error(`[!] Error from player ${name}:`, err);
    });

    player.on('close', () => {
        console.log(`[-] Player disconnected: ${name}`);
    });
});

relay.on('error', err => {
    console.error('[!] Relay Error:', err);
});
