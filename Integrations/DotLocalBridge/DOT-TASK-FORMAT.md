# Dotへのタスク作成・更新指示

2026-10-22。Macの正本を使うDot向け。既存のペアリング・認証・revision保護を維持する。

## Dotへ渡す指示（そのまま貼付け可）

タスクの参照・作成・更新は、次のディレクトリで `canonical_tasks.py` を使ってください。

`<TaskApp checkout>/Integrations/DotLocalBridge`

- 回答・変更する直前に `python3 canonical_tasks.py read` で最新一覧・revisionを読み、`pending` で受信保留を確認する。チャットの記憶を正本にしない。
- プロジェクトは1件または未所属、タグは複数。既存一覧の `project` / `tags` に同じ分類があれば、そのUUIDと名前を再利用する。見つからない場合にだけ新しいUUIDを作る。同名の別IDが複数ある場合は対象を確認し、推測して統合しない。
- 新規作成の変更JSONは以下の形式。タスクのslugは新しい安定IDをCLIへ渡す。JSONに `id` / `revision` は書かず、CLIに管理させる。
- `date` は予定日・期限の日付。`reminderAt` は通知の絶対日時で、必ず秒とタイムゾーンを含める。日本時間の例は `2026-10-23T09:00:00+09:00`。日時が曖昧なら確認し、日付だけから通知時刻を勝手に決めない。
- 未所属は `project: null`、タグなしは `tags: []`、通知なしは `reminderAt: null`。更新で省略した項目は既存値を維持する。
- `status` は工程、`completed` は完了のboolean。工程名から完了を推測しない。
- 変更JSONを権限600の一時ファイルへ保存し、create/updateを実行後にreadで結果を照合する。JSON・SQLiteを直接編集しない。競合は上書きせず最新内容を比較する。
- 「Mac正本への保存」と「iPhone取得・通知予約・通知表示」を区別する。CLI成功だけで「iPhoneの通知設定完了」と報告しない。

```json
{
  "title": "請求書を送る",
  "date": "2026-10-23",
  "dateLabel": "10月23日",
  "status": "未着手",
  "details": "送付前に金額を確認する",
  "category": "work",
  "completed": false,
  "project": {
    "id": "11111111-1111-4111-8111-111111111111",
    "name": "経理"
  },
  "tags": [
    {
      "id": "22222222-2222-4222-8222-222222222222",
      "name": "請求"
    }
  ],
  "reminderAt": "2026-10-23T09:00:00+09:00"
}
```

例のUUIDは説明用。実際は既存のUUIDを再利用するか、新規UUIDを生成する。

```sh
python3 canonical_tasks.py read
python3 canonical_tasks.py pending
# 自分が作成した変更ファイルに対してのみ実行
chmod 600 /private/tmp/dot-new-task.json
python3 canonical_tasks.py create --task-id invoice-20261023 --expected-revision 0 --changes-file /private/tmp/dot-new-task.json
python3 canonical_tasks.py read
```

更新例（revisionは直前に読んだ値に置換）:

```sh
python3 canonical_tasks.py update --task-id invoice-20261023 --expected-revision 1 --changes-file /private/tmp/dot-task-changes.json
```

リマインダーのみ解除する変更ファイル:

```json
{"reminderAt": null}
```

## 保存とiPhone通知の仕様

分類のUUID・名前は各タスクの正本レコードに保持し、同じUUIDの異なる名前は拒否する。プロジェクト名・タグ名の一括変更や、未使用の分類だけを登録する独立マスター操作は今回の範囲外。プロジェクト色・アイコンはiPhone投影で青・briefcaseを使う。既存タスクに項目追加を強制せず、未設定として読み込む。

iPhoneの保存済み中継データから `TaskItem.projectID` / `tags` / `reminderDate` へ投影する。分類一覧もメモリに投影し、SwiftDataへ複製しない。Dot所有の分類の編集・削除はMac側で行い、iPhone側の管理操作は拒否する。既存の端末内分類とUUIDが衝突した場合は混同せずエラーにする。Dot分類の端末内タスクへの割当ても拒否し、通常のSwiftDataバックアップへDotデータを混ぜない。

受信・再起動時のキャッシュ読込・完了・取消後に、既存NotificationServiceで予約を同期する。通知日時変更・解除・完了では既存予約を取り消し、未完了かつ未来日時で権限がある場合に予約する。通知は標準音。複数回通知、通知音の個別指定、繰り返しリマインダーは今回未対応。

Mac更新はiPhoneが前景で同期した後に反映する。アプリ終了中・バックグラウンド・通信断では新しい設定の取得を保証しない。取得済みで予約できた通知はiOSが管理する。通知権限・集中モード等は端末側の設定に従う。通知予約成功をMacへ返すreceiptは今回追加していない。実機で通知が表示されたことは別途確認する。

## 検証・導入の現在地

現在の公開可能な検証結果・未確認・未導入範囲は [検証記録](../../docs/validation-status.md) へ集約する。個人タスク・実端末・実操作の記録はローカルに保持し、公開Gitへ転記しない。

## 任意の種別

`taskKind`は`event`（予定）/`task`（具体的タスク）/`idea`（やりたいこと）/`errand`（細々した用事）またはnull。省略は未設定。category/project/tags/status/completedとは独立し、既存の未設定行を日程から推測しない。CLI updateの省略項目は保持する。対応済み中継でのみ追加し、既存ID/revisionを維持する。
