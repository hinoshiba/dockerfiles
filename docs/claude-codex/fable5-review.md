# Fable 5 資料からの skills 整備（#306）

第三者の prompt 資料を分類して検討し、成果物の確認に使える部分を
[`verify-deliverables`](../../dockerfiles/claude-codex/skills/verify-deliverables/SKILL.md)
として独自に整理しました。外部資料に依存する実装、複数ファイルの変更、生成ファイルの納品に使います。
モデルの自己説明や、元環境のツール・API・パス・権限設定は導入しません。

取得版、真正性の扱い、領域ごとの採用・除外理由は
[検討記録](../../dockerfiles/claude-codex/skills/verify-deliverables/references/source-review.md) を参照してください。
既存の `COPY ./skills /opt/coding-skills` により、claude-codex イメージにも同梱されます。
利用・追加方法は [coding skills](coding-skills.md) を参照してください。
