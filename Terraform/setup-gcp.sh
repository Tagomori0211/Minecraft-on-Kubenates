#!/usr/bin/env bash
# ============================================================
# GKE プロビジョニング セットアップスクリプト
# ============================================================
# 実行方法:
#   chmod +x setup-gcp.sh
#   ./setup-gcp.sh
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC} $*" >&2; }
success() { echo -e "${GREEN}[OK]${NC}   $*" >&2; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ============================================================
# Step 1: gcloud CLI インストール
# ============================================================
install_gcloud() {
  info "gcloud CLI のインストール状況を確認..."

  if command -v gcloud &>/dev/null; then
    success "gcloud CLI は既にインストール済みです ($(gcloud version --format='value(Google Cloud SDK)'))"
    return
  fi

  info "gcloud CLI をインストールします..."

  # GPGキーと apt リポジトリの設定
  sudo apt-get install -y apt-transport-https ca-certificates gnupg curl

  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg

  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list > /dev/null

  sudo apt-get update -q
  sudo apt-get install -y google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin

  success "gcloud CLI のインストール完了"
}

# ============================================================
# Step 2: GCP 認証
# ============================================================
authenticate_gcp() {
  info "GCP 認証状態を確認..."

  # ユーザー認証
  if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
    info "ブラウザでGoogleアカウントにログインします..."
    gcloud auth login
  else
    success "ユーザー認証済み: $(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -1)"
  fi

  # Application Default Credentials（Terraform用）
  if [ ! -f "$HOME/.config/gcloud/application_default_credentials.json" ]; then
    info "Terraform用のApplication Default Credentials (ADC) を設定します..."
    gcloud auth application-default login
  else
    success "ADC は設定済みです"
  fi
}

# ============================================================
# Step 3: GCPプロジェクトの設定
# ============================================================
set_project() {
  info "GCPプロジェクトを設定..."

  # terraform.tfvars から project_id を読み取る
  TFVARS_FILE="$(dirname "$0")/terraform.tfvars"
  PROJECT_ID=$(grep '^project_id' "$TFVARS_FILE" 2>/dev/null | sed 's/.*=\s*"\(.*\)"/\1/' | tr -d ' ')

  if [ "$PROJECT_ID" = "YOUR-GCP-PROJECT-ID" ] || [ -z "$PROJECT_ID" ]; then
    echo ""
    warn "terraform.tfvars の project_id が未設定です"
    echo "利用可能なプロジェクト一覧:"
    gcloud projects list --format="table(projectId,name)"
    echo ""
    read -r -p "使用するGCPプロジェクトIDを入力してください: " PROJECT_ID

    # terraform.tfvars を更新
    sed -i "s/project_id = \"YOUR-GCP-PROJECT-ID\"/project_id = \"${PROJECT_ID}\"/" "$TFVARS_FILE"
    success "terraform.tfvars に project_id = \"${PROJECT_ID}\" を設定しました"
  fi

  gcloud config set project "$PROJECT_ID"
  success "プロジェクト設定完了: $PROJECT_ID"

  echo "$PROJECT_ID"
}

# ============================================================
# Step 4: 必要なGCP APIの有効化
# ============================================================
enable_apis() {
  local project_id="$1"
  info "GKEに必要なAPIを有効化します..."

  APIS=(
    "container.googleapis.com"          # GKE
    "compute.googleapis.com"            # VPC/Firewall/NAT
    "cloudresourcemanager.googleapis.com" # プロジェクト管理
    "iam.googleapis.com"                # IAM (Workload Identity)
    "logging.googleapis.com"            # Cloud Logging
    "monitoring.googleapis.com"         # Cloud Monitoring
  )

  for api in "${APIS[@]}"; do
    gcloud services enable "$api" --project="$project_id" --quiet
    success "有効化: $api"
  done
}

# ============================================================
# Step 5: kubectl 用 gke-gcloud-auth-plugin の確認
# ============================================================
check_kubectl_plugin() {
  info "gke-gcloud-auth-plugin を確認..."

  if ! command -v gke-gcloud-auth-plugin &>/dev/null; then
    info "gke-gcloud-auth-plugin をインストール..."
    sudo apt-get install -y google-cloud-cli-gke-gcloud-auth-plugin
  fi

  success "gke-gcloud-auth-plugin 確認完了"

  # 環境変数の設定案内
  if ! grep -q "USE_GKE_GCLOUD_AUTH_PLUGIN" "$HOME/.bashrc" 2>/dev/null; then
    echo 'export USE_GKE_GCLOUD_AUTH_PLUGIN=True' >> "$HOME/.bashrc"
    info "~/.bashrc に USE_GKE_GCLOUD_AUTH_PLUGIN=True を追加しました"
    info "反映するには: source ~/.bashrc"
  fi
}

# ============================================================
# Step 6: Terraform 初期化・プラン
# ============================================================
run_terraform() {
  SCRIPT_DIR="$(dirname "$0")"
  info "Terraform を初期化します..."

  cd "$SCRIPT_DIR"

  # secret.tfvars の存在確認
  if [ ! -f "secret.tfvars" ]; then
    warn "secret.tfvars が見つかりません"
    warn "secret.tfvars.template をコピーして認証情報を入力してください:"
    echo "  cp secret.tfvars.template secret.tfvars"
    echo "  vi secret.tfvars"
    error "secret.tfvars を作成してから再実行してください"
  fi

  terraform init

  info "Terraform プランを実行します (GKEリソースのみ確認)..."
  echo ""
  terraform plan \
    -var-file="secret.tfvars" \
    -target=google_compute_network.tak_vpc \
    -target=google_compute_subnetwork.tak_subnet \
    -target=google_compute_firewall.tailscale_udp \
    -target=google_compute_firewall.minecraft_tcp \
    -target=google_compute_firewall.internal \
    -target=google_container_cluster.tak_entrance \
    -target=google_compute_router.tak_router \
    -target=google_compute_router_nat.tak_nat \
    -target=google_compute_global_address.minecraft_ip
}

# ============================================================
# メイン処理
# ============================================================
main() {
  echo ""
  echo "=================================================="
  echo "  GKE Autopilot セットアップスクリプト"
  echo "  Minecraft ハイブリッドインフラ"
  echo "=================================================="
  echo ""

  install_gcloud
  authenticate_gcp
  PROJECT_ID=$(set_project)
  enable_apis "$PROJECT_ID"
  check_kubectl_plugin

  echo ""
  echo "=================================================="
  success "GCP認証・設定完了！"
  echo "=================================================="
  echo ""
  info "次のステップ:"
  echo "  1. secret.tfvars の Proxmox認証情報を確認"
  echo "  2. terraform plan を確認後、apply でGKEをプロビジョニング:"
  echo "     terraform apply -var-file=secret.tfvars"
  echo ""
  echo "  GKEクラスター作成後、kubectlを接続する場合:"
  echo "     gcloud container clusters get-credentials tak-entrance \\"
  echo "       --region asia-northeast1 --project ${PROJECT_ID}"
  echo ""

  read -r -p "続けて terraform plan を実行しますか？ [y/N]: " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    run_terraform
  fi
}

main "$@"
