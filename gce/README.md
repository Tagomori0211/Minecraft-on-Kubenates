# GCE Minecraft Proxy（GKE 代替）

GKE Standard を GCE 単一 VM + Docker Compose に置換したプロキシ構成。月額 ¥19,700 → ¥3,680（81% 減）。

## アーキテクチャ

```
[Player Java]    → 35.200.78.252:25565/TCP ┐
                                           │  GCE VM (e2-medium, asia-northeast1-b)
[Player Bedrock] → 35.200.78.252:19132/UDP │  ├─ nginx-stream (host net)
                                           │  │   ├─ TCP 25565 → 127.0.0.1:25577 (velocity)
                                           │  │   └─ UDP 19132 → 100.107.122.45:19132
                                           │  ├─ velocity (host net, 25577)
                                           │  └─ tailscaled (host systemd, kernel mode)
                                           │       │
                                           └──────┼─→ Tailscale → 100.107.122.45 (k3s-worker)
                                                  │      ├─ Survival  :30065
                                                  │      ├─ MOD       :30066
                                                  │      ├─ Lobby     :30067
                                                  │      └─ Bedrock   :19132
```

## ファイル構成

```
gce/
├── README.md                       # このファイル
├── compose.yaml                    # velocity + nginx-stream
├── nginx/nginx.conf                # TCP 25565 + UDP 19132 stream proxy
├── velocity/
│   ├── velocity.toml               # Velocity 設定（Tailscale IP 直書き）
│   └── forwarding.secret.example   # 平文は Secret Manager から取得
├── systemd/
│   ├── mc-proxy.service            # Compose 起動 systemd unit
│   └── fetch-secrets.sh            # Secret Manager から forwarding.secret 取得
└── cloud-init.yaml                 # VM 初期セットアップ（Docker / Tailscale / mc-proxy）
```

## Phase 0: Secret Manager 準備（VM 作成前に実施）

### 0-1. GKE 既存 Secret から値を取り出し

```bash
# Tailscale auth key
TS_KEY=$(kubectl --context=gke-tak get secret -n minecraft tailscale-auth \
    -o jsonpath='{.data.TS_AUTHKEY}' | base64 -d)

# Velocity forwarding secret
VEL_SECRET=$(kubectl --context=gke-tak get secret -n minecraft velocity-secret \
    -o jsonpath='{.data.velocity-forwarding-secret}' | base64 -d)
```

### 0-2. Secret Manager に登録

```bash
PROJECT=project-61cf5742-d0ea-45ed-ac0

# Secret Manager API 有効化（初回のみ）
gcloud services enable secretmanager.googleapis.com --project=$PROJECT

# tailscale-auth-key
printf '%s' "$TS_KEY" | gcloud secrets create tailscale-auth-key \
    --data-file=- \
    --replication-policy=automatic \
    --project=$PROJECT

# velocity-forwarding-secret
printf '%s' "$VEL_SECRET" | gcloud secrets create velocity-forwarding-secret \
    --data-file=- \
    --replication-policy=automatic \
    --project=$PROJECT

# 確認
gcloud secrets list --project=$PROJECT
```

### 0-3. 注意事項

- Tailscale auth key は **再利用可能（reusable）** でない場合、Secret 登録時点で消費される。
  `tailnet 管理画面 → Settings → Keys` で reusable / pre-approved な auth key を生成すること。
- `velocity-forwarding-secret` の値は **オンプレ Paper サーバーの `paper-global.yml` の secret と一致する必要あり**。値を変更する場合は両側を同時更新する。

## Phase 1〜2: VM 作成（Terraform）

```bash
cd /home/shinari/Minecraft_java_k3s/Terraform

# プラン確認（追加のみ・GKE 無傷を確認）
terraform plan -var-file=secret.tfvars

# Apply（VM はエフェメラル IP で起動）
terraform apply -var-file=secret.tfvars

# 出力で VM の external IP を確認
terraform output mc_proxy_external_ip
```

VM 起動後、cloud-init が Docker / Tailscale / mc-proxy.service をプロビジョニング。3〜5 分で完了。

### 動作確認

```bash
# SSH（IAP 経由）
gcloud compute ssh mc-proxy-1 --zone=asia-northeast1-b --tunnel-through-iap

# VM 内
sudo systemctl status mc-proxy.service     # active (exited)
docker compose -f /opt/mc-proxy/compose.yaml ps    # Up
tailscale status                            # 100.107.122.45 reachable
tailscale ping --until-direct 100.107.122.45

# 外部から
EPHEMERAL_IP=$(terraform output -raw mc_proxy_external_ip)
nc -zv $EPHEMERAL_IP 25565       # Java TCP
nc -zuv $EPHEMERAL_IP 19132      # Bedrock UDP
```

## Phase 3: 静的IP カットオーバー（ダウンタイム発生）

```bash
# 1. GKE LB 削除（35.200.78.252 をデタッチ）
kubectl --context=gke-tak delete svc nginx-gw-java -n minecraft
kubectl --context=gke-tak delete svc bedrock-direct-lb -n minecraft

# 2. GCE VM に静的IP 35.200.78.252 を付け替え
gcloud compute instances delete-access-config mc-proxy-1 \
    --zone=asia-northeast1-b
gcloud compute instances add-access-config mc-proxy-1 \
    --address=35.200.78.252 \
    --zone=asia-northeast1-b

# 3. 疎通確認
nc -zv 35.200.78.252 25565
nc -zuv 35.200.78.252 19132
```

その後、`gce.tf` の `access_config {}` を `access_config { nat_ip = google_compute_address.minecraft_ip.address }` に書き換えて `terraform apply` で state を整合させる。

## Phase 4: GKE 削除 + クリーンアップ

```bash
# 1. GKE クラスター削除（gke.tf から google_container_* リソース削除後）
terraform apply -var-file=secret.tfvars

# 2. 廃 IP 解放
gcloud compute addresses delete minecraft-unified-ip --region=asia-northeast1

# 3. k8s/gke/ 削除
rm -rf /home/shinari/Minecraft_java_k3s/k8s/gke
```

## ロールバック

| Phase | 戻し方 |
|-------|-------|
| Phase 2 失敗 | `terraform destroy -target=google_compute_instance.mc_proxy` |
| Phase 3 失敗 | `gcloud compute instances delete-access-config mc-proxy-1 ...` で IP デタッチ → `kubectl apply -f k8s/gke/20-nginx-gw.yaml -f k8s/gke/20-bedrock-direct.yaml` で LB 復旧 |
| Phase 4 後 | クラスター削除後の戻しは困難。Phase 3 完了から 24h 安定稼働を確認してから着手 |

## 運用

### Velocity Forwarding Secret ローテーション

```bash
# 1. 新値を Secret Manager に登録（new version）
printf '%s' "$NEW_SECRET" | gcloud secrets versions add velocity-forwarding-secret \
    --data-file=- --project=$PROJECT

# 2. オンプレ Paper サーバーの paper-global.yml も同時更新
# 3. mc-proxy.service 再起動で新 secret を適用
gcloud compute ssh mc-proxy-1 --zone=asia-northeast1-b --tunnel-through-iap \
    --command="sudo systemctl restart mc-proxy.service"
```

### ログ確認

```bash
# cloud-init のブートストラップログ
sudo cat /var/log/cloud-init-output.log

# Compose サービスログ
docker compose -f /opt/mc-proxy/compose.yaml logs -f velocity
docker compose -f /opt/mc-proxy/compose.yaml logs -f nginx-stream

# Tailscale 状態
journalctl -u tailscaled -f
```

### コスト

| 項目 | 月額 |
|------|------|
| e2-medium (asia-northeast1) | ¥3,500 |
| pd-balanced 20GB | ¥120 |
| 静的IP × 1（VM アタッチ中は無料） | ¥0 |
| Egress | ~¥50 |
| Secret Manager | ¥0〜10 |
| **合計** | **約 ¥3,680/month** |
