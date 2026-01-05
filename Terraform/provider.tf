terraform {
  required_providers {
    proxmox = {
      # Proxmoxを操作するための公式ライクなプラグインを指定
      source  = "telmate/proxmox"
      # バージョンを指定（動作が安定しているバージョンを選定）
      version = "2.9.14"
    }
  }
}

provider "proxmox" {
  # Proxmoxの管理画面(API)のURL
  # 変数 var.proxmox_api_url から読み込みます
  pm_api_url = var.proxmox_api_url

  # ログインユーザー名 (例: root@pam)
  pm_user = var.proxmox_user

  # ログインパスワード
  # 重要：これはコードに書かず、後述する別ファイルで管理します
  pm_password = var.proxmox_password

  # 証明書エラーを無視するかどうか
  # 自宅サーバー(オレオレ証明書)の場合は true にしないとエラーになります
  pm_tls_insecure = true
}