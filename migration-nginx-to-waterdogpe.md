# 移行指示書: Nginx UDP Proxy → WaterdogPE

**プロジェクト**: sushiski Minecraft Infrastructure  
**対象**: GKE Autopilot 上の Bedrock Edition 接続経路  
**作成日**: 2026-03-10  
**移行理由**: Nginx Stream の UDP プロキシは RakNet のステートフルなハンドシェイク（MTU ディスカバリ・セッション管理）を理解できず、Bedrock クライアントが接続不能。RakNet ネイティブ実装の WaterdogPE に置換する。

---

## 前提条件

- GKE Autopilot クラスタ（asia-northeast1）が稼働中
- `namespace: minecraft` が作成済み
- Nginx Stream Gateway が TCP 25565 + UDP 19132 で稼働中
- Tailscale VPN メッシュが GKE ↔ オンプレ間で確立済み
- オンプレ Bedrock Server が k3s-worker 上で稼働中（19132/UDP）
- `kubectl` が GKE クラスタに接続済み

---

## 移行概要

```
【Before】
Player (UDP 19132) → GKE LB → Nginx Stream → Tailscale → Bedrock Server
                                ↑ RakNet 非対応のため接続不可

【After】
Player (UDP 19132) → GKE LB → WaterdogPE Pod → Tailscale → Bedrock Server
                                ↑ RakNet ネイティブ実装、接続可能

Player (TCP 25565) → GKE LB → Nginx Stream → Velocity → Java Servers
                                ↑ TCP のみに簡素化、変更なし
```

---

## Step 1: オンプレ Bedrock Server の設定変更

WaterdogPE が認証を一元管理するため、ダウンストリーム側の Xbox 認証を無効化する。

### 1-1. server.properties の編集

```bash
kubectl exec -it <bedrock-pod-name> -n minecraft -- sh
```

```properties
# server.properties
xbox-auth=off
```

> **注意**: `xbox-auth=off` にしても WaterdogPE 側で `online_mode: true` を設定するため、未認証プレイヤーはプロキシ段階で弾かれる。ダウンストリームへの直接接続は Tailscale VPN 内部に限定されるため、セキュリティリスクなし。

### 1-2. Bedrock Server を再起動

```bash
kubectl rollout restart deployment bedrock-server -n minecraft
```

### 1-3. 動作確認

```bash
kubectl logs deployment/bedrock-server -n minecraft | grep -i "xbox"
```

`xbox-auth` が無効になっていることを確認。

---

## Step 2: WaterdogPE の ConfigMap 作成

### 2-1. config.yml

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: waterdogpe-config
  namespace: minecraft
data:
  config.yml: |
    # WaterdogPE Configuration for sushiski
    listener:
      motd: "§bsushiski §3Bedrock"
      host: 0.0.0.0:19132
      max_players: 20

    servers:
      bedrock-survival:
        address: "<ONPREM_TAILSCALE_IP>:19132"
        public_address: "<ONPREM_TAILSCALE_IP>:19132"
        server_type: bedrock

    priorities:
      - bedrock-survival

    # Xbox Live 認証を WaterdogPE で一元管理
    online_mode: true

    # パフォーマンス最適化
    # プロキシが処理不要なパケットをデコードせず生データ転送
    use_fast_codec: true

    # クライアント情報をダウンストリームに伝達（XUID, IP等）
    use_login_extras: true

    # TransferServer パケットによる高速転送
    prefer_fast_transfer: true

    # 圧縮設定
    # Tailscale 経由（低レイテンシ）なのでアップストリーム圧縮は軽め
    upstream_compression_level: 2
    # クライアント向けは帯域節約のため中程度
    downstream_compression_level: 6

    # IPv6 無効（GKE Autopilot 環境）
    enable_ipv6: false

    # サーバーリストの ping 応答を有効化
    enable_query: true

    # スレッドプール（-1 で CPU コア数自動検出）
    default_idle_threads: -1
```

> **`<ONPREM_TAILSCALE_IP>`** をオンプレ k3s-worker の Tailscale IP（100.x.x.x）に置換すること。

### 2-2. ConfigMap をデプロイ

```bash
kubectl apply -f waterdogpe-configmap.yaml
```

---

## Step 3: WaterdogPE Deployment 作成

### 3-1. Deployment マニフェスト

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: waterdogpe
  namespace: minecraft
  labels:
    app: waterdogpe
spec:
  replicas: 1
  selector:
    matchLabels:
      app: waterdogpe
  template:
    metadata:
      labels:
        app: waterdogpe
    spec:
      # 通常 Pod（Spot 不可: Bedrock UX 保護）
      # GKE Autopilot では nodeSelector 不要、Spot toleration を付けないことで通常ノードに配置
      containers:
        # --- WaterdogPE コンテナ ---
        - name: waterdogpe
          image: ghcr.io/waterdogpe/waterdogpe:latest
          # ※ 公式イメージが存在しない場合は自前ビルドが必要（Step 3-2 参照）
          ports:
            - containerPort: 19132
              protocol: UDP
          resources:
            requests:
              cpu: "250m"
              memory: "512Mi"
            limits:
              cpu: "500m"
              memory: "512Mi"
          volumeMounts:
            - name: config
              mountPath: /opt/waterdogpe/config.yml
              subPath: config.yml
          readinessProbe:
            exec:
              command:
                - sh
                - -c
                - "pgrep -f waterdogpe || pgrep -f java"
            initialDelaySeconds: 15
            periodSeconds: 10
          livenessProbe:
            exec:
              command:
                - sh
                - -c
                - "pgrep -f waterdogpe || pgrep -f java"
            initialDelaySeconds: 30
            periodSeconds: 15

        # --- Tailscale Sidecar ---
        - name: tailscale
          image: ghcr.io/tailscale/tailscale:latest
          env:
            - name: TS_AUTHKEY
              valueFrom:
                secretKeyRef:
                  name: tailscale-auth
                  key: TS_AUTHKEY
            - name: TS_KUBE_SECRET
              value: ""
            - name: TS_USERSPACE
              value: "true"
            - name: TS_STATE_DIR
              value: "/var/lib/tailscale"
            - name: TS_HOSTNAME
              value: "waterdogpe-gke"
          resources:
            requests:
              cpu: "50m"
              memory: "128Mi"
            limits:
              cpu: "100m"
              memory: "256Mi"
          securityContext:
            runAsUser: 1000
            runAsGroup: 1000

      volumes:
        - name: config
          configMap:
            name: waterdogpe-config
```

### 3-2. WaterdogPE コンテナイメージについて

WaterdogPE は公式 Docker イメージが提供されていない可能性がある。その場合は以下の Dockerfile で自前ビルドする。

```dockerfile
FROM eclipse-temurin:21-jre-alpine

WORKDIR /opt/waterdogpe

# WaterdogPE の最新リリース JAR をダウンロード
# https://github.com/WaterdogPE/WaterdogPE/releases から URL を取得
ADD https://github.com/WaterdogPE/WaterdogPE/releases/download/<VERSION>/WaterdogPE.jar /opt/waterdogpe/WaterdogPE.jar

EXPOSE 19132/udp

ENTRYPOINT ["java", "-Xms256M", "-Xmx512M", "-jar", "WaterdogPE.jar"]
```

```bash
# ビルド & プッシュ（Artifact Registry 使用）
docker build -t asia-northeast1-docker.pkg.dev/<PROJECT_ID>/minecraft/waterdogpe:<VERSION> .
docker push asia-northeast1-docker.pkg.dev/<PROJECT_ID>/minecraft/waterdogpe:<VERSION>
```

> Deployment マニフェストの `image` を Artifact Registry の URL に置換すること。

### 3-3. デプロイ

```bash
kubectl apply -f waterdogpe-deployment.yaml
```

### 3-4. Pod 起動確認

```bash
kubectl get pods -n minecraft -l app=waterdogpe
kubectl logs deployment/waterdogpe -n minecraft -c waterdogpe
kubectl logs deployment/waterdogpe -n minecraft -c tailscale
```

確認項目:
- WaterdogPE が `Listening on 0.0.0.0:19132` を出力していること
- Tailscale sidecar が VPN に参加し、IP が割り当てられていること

---

## Step 4: WaterdogPE 用 Service 作成（UDP LB）

### 4-1. 新規 Service マニフェスト

```yaml
apiVersion: v1
kind: Service
metadata:
  name: waterdogpe-udp
  namespace: minecraft
spec:
  type: LoadBalancer
  selector:
    app: waterdogpe
  ports:
    - name: bedrock
      protocol: UDP
      port: 19132
      targetPort: 19132
```

### 4-2. デプロイ

```bash
kubectl apply -f waterdogpe-service.yaml
```

### 4-3. External IP 取得

```bash
kubectl get svc waterdogpe-udp -n minecraft -w
```

`EXTERNAL-IP` が割り当てられるまで待機（GKE Autopilot では数分かかる場合あり）。

> この IP が Bedrock プレイヤーの新しい接続先になる。

---

## Step 5: Nginx Gateway から UDP 設定を削除

### 5-1. ConfigMap の更新

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-stream-config
  namespace: minecraft
data:
  nginx.conf: |
    stream {
        # Java Edition → Velocity (GKE 内部通信)
        upstream velocity {
            server velocity-svc.minecraft.svc.cluster.local:25565;
        }
        server {
            listen 25565;
            proxy_pass velocity;
            proxy_connect_timeout 5s;
        }

        # UDP 19132 セクション削除済み
        # Bedrock は WaterdogPE Pod が担当
    }
```

### 5-2. 適用 & リロード

```bash
kubectl apply -f nginx-configmap.yaml
kubectl rollout restart deployment nginx-gateway -n minecraft
```

### 5-3. 旧 UDP Service の削除

```bash
kubectl delete svc gateway-udp -n minecraft
```

> **Java 側の gateway-tcp Service は削除しないこと。**

### 5-4. Nginx Gateway の containerPort から UDP 19132 を削除

Deployment マニフェストの `ports` セクションから UDP 19132 を削除し、再適用。

```bash
kubectl apply -f nginx-gateway-deployment.yaml
```

---

## Step 6: 接続テスト

### 6-1. Bedrock Edition クライアントから接続

1. Minecraft Bedrock Edition を起動
2. サーバー追加画面で以下を入力:
   - **サーバーアドレス**: `<waterdogpe-udp の EXTERNAL-IP>`
   - **ポート**: `19132`
3. 接続を試行

### 6-2. 確認項目チェックリスト

| # | 確認項目 | コマンド / 方法 | 期待結果 |
|---|---------|----------------|---------|
| 1 | WaterdogPE ログにハンドシェイク成功 | `kubectl logs deploy/waterdogpe -c waterdogpe` | `Connected <player>` のようなログ |
| 2 | Bedrock Server ログにプレイヤー参加 | `kubectl logs deploy/bedrock-server -n minecraft` | プレイヤー参加ログ |
| 3 | ワールドが正常にロード | クライアント画面で確認 | 既存ワールドが表示される |
| 4 | Java 側が影響を受けていない | Java クライアントから 25565/TCP で接続 | 正常に接続可能 |
| 5 | Prometheus が WaterdogPE を監視 | Grafana ダッシュボードで確認 | メトリクスが取得できている |

### 6-3. レイテンシ確認

```bash
# GKE Pod から オンプレ Tailscale IP への RTT
kubectl exec deploy/waterdogpe -c tailscale -- ping -c 10 <ONPREM_TAILSCALE_IP>
```

東京 ↔ 北九州で 10-20ms 程度が目安。

---

## Step 7: クリーンアップ

全ての接続テストが成功した後に実施。

```bash
# 旧 Nginx の UDP 関連リソースが残っていないか確認
kubectl get svc -n minecraft
# gateway-udp が存在しないことを確認

# WaterdogPE が正常稼働していることを最終確認
kubectl get pods -n minecraft -l app=waterdogpe -o wide
```

---

## ロールバック手順

WaterdogPE に問題が発生した場合の切り戻し手順。

### 即時ロールバック

```bash
# 1. オンプレ Bedrock Server の xbox-auth を元に戻す
#    server.properties: xbox-auth=on
kubectl rollout restart deployment bedrock-server -n minecraft

# 2. Nginx ConfigMap を UDP 込みの旧設定に戻す
kubectl apply -f nginx-configmap-backup.yaml
kubectl rollout restart deployment nginx-gateway -n minecraft

# 3. 旧 gateway-udp Service を再作成
kubectl apply -f gateway-udp-service-backup.yaml

# 4. WaterdogPE を停止
kubectl scale deployment waterdogpe --replicas=0 -n minecraft
```

> **重要**: ロールバック用に、移行前の以下のマニフェストを必ずバックアップしておくこと。
> - `nginx-configmap-backup.yaml`（UDP 込みの旧 nginx.conf）
> - `gateway-udp-service-backup.yaml`（旧 UDP Service）
> - `nginx-gateway-deployment-backup.yaml`（UDP containerPort 込みの旧 Deployment）

---

## 最終構成サマリ

| コンポーネント | 状態 | 役割 |
|--------------|------|------|
| Nginx Gateway | **変更** | TCP 25565 のみ（UDP 削除）|
| WaterdogPE | **新規** | UDP 19132、RakNet ネイティブ Bedrock プロキシ |
| gateway-tcp Service | 維持 | Java LB |
| gateway-udp Service | **削除** | — |
| waterdogpe-udp Service | **新規** | Bedrock LB |
| Velocity | 維持 | Java プロキシ |
| Bedrock Server (オンプレ) | **変更** | xbox-auth=off |

---

## 注意事項

- WaterdogPE は JVM ベースのため、GKE Autopilot での起動に 15-30 秒かかる。Pod の readinessProbe の `initialDelaySeconds` を適切に設定すること
- WaterdogPE のバージョンアップ時は Bedrock クライアントのバージョンとの互換性を必ず確認すること。プロトコルバージョン不一致で接続不可になる
- Tailscale sidecar の auth key は reusable + ephemeral を使用し、Pod 再作成時の自動認証を確保すること
- 移行作業はプレイヤーが少ない時間帯（深夜帯推奨）に実施すること
