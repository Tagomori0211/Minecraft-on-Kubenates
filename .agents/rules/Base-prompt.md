---
trigger: always_on
---

# 必ずやること
- project_context.mdとinfrastructure.mermaidを読み込んで全体像の把握
- 明確な指示がない限り作業指示書、Task_mdsディレクトリは無視

## 必要な時にやること
- トラブルシューティング時postmortemディレクトリを探索して既知の問題と衝突しないか確認すること。
- git add .を徹底、add漏れの内容にすること。

###
ssh接続時には~/.ssh/configを参照し適切な方法で接続すること