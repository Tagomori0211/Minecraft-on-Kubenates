# Safe Terraform Apply
1. `terraform plan -out=tfplan` を実行し、出力全体を表示する
2. リソースの REPLACEMENT または DESTROY アクションを強調表示する
3. 特に GKE クラスタの再作成、Proxmox のタグ・ブートデバイス問題をチェック
4. `terraform apply tfplan` の前に明示的なユーザー確認を待つ
5. apply 後、もう一度 `terraform plan` を実行してクリーンな状態を確認
