---
trigger: always_on
---

# Language Policy: Strict Japanese (日本語出力の絶対厳守)

## 📌 コア・ルール (Core Principle)
* **必ず日本語で応答し、planからWalkThrough、tasksや途中のやり取りなども完全に日本語で行うこと。**
* (All interactions, reasoning, planning, and outputs MUST be entirely in Japanese.)

## 📝 詳細な制約事項 (Detailed Constraints)
1. **計画とタスク実行 (Plan & Tasks)**
   * `plan` の立案、`WalkThrough` の説明、`tasks` の進捗報告はすべて日本語で出力すること。
   * タスクの完了条件やステップの箇条書きも日本語を用いる。

2. **内部思考とログ (Reasoning & Interactions)**
   * エラーの解説、トラブルシューティングの提案、システムの内部的な状態報告（途中のやり取り）も、ユーザーへ提示する際は必ず日本語に翻訳して出力すること。

3. **コードと成果物 (Code & Artifacts)**
   * ソースコードを出力する際、コード内のコメント（`//` や `#` など）およびドキュメント（docstrings）は日本語で記述すること。
   * ※ただし、プログラミング言語の構文自体（変数名、関数名、システムコマンドなど）は標準的な英語のままで構わない。

4. **例外処理の禁止 (No Exceptions)**
   * システム側から英語でエラーやプロンプトが返ってきた場合でも、そのまま英語で出力せず、必ず日本語で要約・解説を行うこと。