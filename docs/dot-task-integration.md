# Dot連携の現在仕様と確認範囲

更新: 2026-10-22。実装を正とし、現在の運用・入力契約・検証範囲の入口をこの文書へ集約する。個人のタスク内容、端末識別子、操作ID、復元資料は公開リポジトリへ含めない。詳細な実機検証記録はローカルで保持する。

## 保存と同期

- 正本はMacの `~/Library/Application Support/CalendarTaskApp/DotLocalRelay/state/tasks.json`。操作は正規CLI `Integrations/DotLocalBridge/canonical_tasks.py` から行う。SQLiteは配信用投影と永続受信箱で、JSON/DB直接編集やWeb/D1からの上書きはしない。
- 端末の完了変更はatomic outbox保存後に自動送信。Mac受信箱commit→revision一致時の正本更新→読戻し→applied応答→outbox解消。競合は上書きせず保持し、保存失敗は同じoperation IDで再試行する。明示applyと手動送受信は復旧用に残す。
- 未送信が確実な新操作だけは取消で取下げ可能。送信開始前に不確実性を保存し、それ以降は元ID/payloadを維持して最新希望を別保存、ack後に新IDで後続変更を送る。古いキャッシュの送信不明状態は取下げない。
- 起動・前景復帰・前景中の再試行で通信回復に対応する。バックグラウンド・終了中・Macスリープ中の常時同期は保証しない。Mac受信/正本適用とWeb・Dot会話への反映を区別する。
- 接続は既存LAN、TLS証明書ピニング、端末別認証。承認済みLaunchAgentの設定・停止手順は[常駐運用](../Integrations/DotLocalBridge/SERVICE-PROPOSAL.md)。Supabase・新規クラウド・VPN・外部公開を導入しない。

## タスクデータ作成・更新の共通手順

1. 現行CLIスキーマと[入力仕様](../Integrations/DotLocalBridge/DOT-TASK-FORMAT.md)を確認する。更新可能項目は `title/date/dateLabel/status/details/aiContext/category/subcategory/parentId/completed/project/tags/reminderAt/startTime/endTime/timeZone/deadlineDate/deadlineTime`。id/revisionは変更JSONに入れず安定slugとexpected revisionを使う。
2. 操作直前に `pending` と `read` で最新revision・受信保留・重複・既存分類を確認する。`read` は中断した受信操作の回復とDB投影を伴うため、厳密な読取り限定では正本を変更しない隔離コピー等を使う。端末の未送信操作がある同じタスクを黙って更新しない。
3. project/tagsは正本内の実在するUUID/name参照を再利用する。サンプルUUIDを使わず、同じIDの名前不一致や重複を拒否する。新規分類は本人の依頼範囲内だけで生成し、Gitリポジトリ対応を推測しない。parentIdはproject UUIDとは別の従来参照である。
4. 変更前の正本・受信箱の整合した復元用コピーと差分JSONを所有者専用で保持する。正式CLIのcreate/updateだけで一件ずつ保存する。省略した属性は保持する。競合・未反映操作は強制上書きしない。
5. 保存後readで対象全指定属性・件数・他タスク不変・保護する日程/期限/通知/完了/分類を照合する。Mac保存とiPhone受信・実表示・通知予約を区別し、未観測の反映を成功と報告しない。正本削除・一括置換・統合元の復活は行わない。

## 表示・日程・分類の契約

- タイトルは短い体言止め、20文字程度を目安とし意味を優先する。detailsは人向けの行動・次の一歩・完了目安。aiContextは元の詳細・出典・履歴・関連・注意を保持し通常UI/Widgetへ渡さない。端末とLAN転送には含まれるため秘密領域ではない。
- dateはYYYY-MM-DD/nullの作業日・希望日。startTime/endTimeは同日のHH:mm/null。時刻指定時は実在するIANA timeZoneが必要。秒、24:00、開始なし終了、開始以前の終了、存在しないDST現地時刻を拒否する。日跨ぎ枠は未対応。「朝ごろ」から正確な時刻・所要時間を捏造しない。
- 固定期限はdeadlineDate/deadlineTimeへ分離し、本人の作業日や案件全体期限の意味を取り違えない。通知reminderAtは別のoffset付きISO秒精度で、日程整理から通知を自動新設しない。
- projectはnullまたはUUID/name、tagsはその配列。categoryはwork/private/otherを大分類表示へ使う。statusとcompletedは別で、工程・保留・検討状態から完了を推測しない。
- 日付のみは終日、時刻付きは指定zoneの開始日時を既存TaskItemへ投影。終了と固定期限は人向け詳細にも明示する。native SwiftData schemaを増やさず、Dotの名前・日程・本文整理はMac正本側、iPhone更新は完了操作のみ。
- タスクタブの初期表示は今日から7暦日の「今週」。大分類切替、プロジェクト集約、次の一歩、仮枠/希望日と固定期限の別表示。保留・検討中・統合済み・完了は週から除外する。従来の全件・日付別・タグ絞込みは残す。
- 完了/取消のUUIDを保持し、古い保存結果・古い表示ボタンで別の対象を取消さない。端末保存通知からStoreとWidget共有投影を更新する。Widget実描画の時刻はOS管理。

## 現在地・未確認

| 範囲 | 確認状態 |
| --- | --- |
| 正本/永続outbox/自動適用/同一ID再送/競合/取消 | 隔離テスト、実機のオンライン往復・即取消・オフライン即取消を確認 |
| 詳細分離・分単位日程・分類・週間UI | 合成テスト、署名済み上書き更新、データ保持、本人の表示確認済み |
| Widget共有 | 保存・読戻し一致と本人の表示報告あり。描画時間・常時更新は保証しない |
| 後続のカレンダー/タグ/日別生成文変更 | リポジトリの最終統合検証対象。先行する端末更新とは分ける |
| Dotのひとこと | 本人がチャットで依頼した場合のみ生成する[手順](../Integrations/DotLocalBridge/DAILY-BRIEF.md)。本番中継・実機の更新、受信材料、生成CLI保存と実表示は個別確認が必要 |

### 今週画面の実機確認（2026-10-22・本人報告）

- 「仕事／私用／その他」の切替が問題なく動作した。
- プロジェクト別の表示が問題なく確認できた。
- 仮予定と固定期限を区別して読めた。
- 確認中にタスクは変更していないとの報告。表示確認として記録し、今回あらためて正本・UUID・履歴・outboxを照合したとは扱わない。

この確認は更新後の今週画面が対象であり、後続のUI変更や同期・復旧の未確認項目を確認済みへ変更するものではない。

残る具体的検証は、取消しないオフライン完了の再接続後往復、実機での複数行取消、実際の日跨ぎ・ログイン・長期稼働・スリープ復帰、端末交換/outbox復元。既知の初回対象外操作は入力経路の記録不足で原因未特定。独立して再現した取消競合は修正済みだが、初回事象との因果は断定しない。実タスクを無断で反転して試験しない。

既存Web完了overlay由来の初期状態、Dot会話自身のCLI実運用採用、全画面の実機回帰も未確認。新規機能や監視を無制限に始めず、本人依頼の範囲で進める。

## 資料の入口

- [README](../README.md): 利用者向け機能・セットアップ。
- [構成](architecture.md): 保存境界・DI・target共有。
- [正本CLI](../Integrations/DotLocalBridge/CANONICAL-SOURCE.md): revision更新・競合・復旧。
- [バックアップ](dot-backup-recovery.md): 正本と受信箱の一貫コピー・隔離検証。
- [検証・公開の記録](validation-status.md): 最終コードのテスト/ビルド、未導入範囲と公開除外。

古い実機記録や個人の予定一覧は現行仕様ではなく、ローカル保存の検証資料として分離する。公開版へ個人タスクJSON・認証情報・端末識別子を含めない。
