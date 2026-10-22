# 組込み状況

現行仕様・検証済み範囲・未確認事項は [Dot連携の現在地](../../docs/dot-task-integration.md) を正本とする。実タスク件数や過去の端末操作記録を固定仕様として扱わない。

- AppはローカルSwift Packageを利用し、既存ペアリングのKeychain認証/TLSピニングで接続する。
- Mac正本とSQLite受信箱は分離。永続outbox・同一ID再送・競合保持・自動正本適用・確認応答を使用する。
- Home/Calendar/Tasksは共通planner投影。WidgetはApp Groupの表示専用snapshotを使用し、native SwiftDataへDotタスクをコピーしない。
- 週間一覧、分類/タグ、AI補足分離、分単位の日程は組込み済み。実装時点の検証と後続変更の導入状態を区別する。
- 日別生成文の受信経路はコードに含まれるが、本番中継/実機更新と本人依頼による生成・実表示は[専用手順](DAILY-BRIEF.md)で確認する。

最終リポジトリ検証は [検証記録](../../docs/validation-status.md)。認証情報・実タスク・端末固有の検証証跡は公開せずローカルに保持する。
