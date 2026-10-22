# Mac正本の操作・復旧

仕様と作業前チェックは [共通手順](../../docs/dot-task-integration.md#タスクデータ作成更新の共通手順)。正本JSON・DBの直接編集は禁止する。

## 通常操作

リポジトリの `Integrations/DotLocalBridge` から、既存の専用領域とbridge IDを使用する。

```sh
python3 canonical_tasks.py pending
python3 canonical_tasks.py read
python3 canonical_tasks.py update --task-id sample-task --expected-revision 1 --changes-file /path/to/private-changes.json
python3 canonical_tasks.py read
```

sample-taskは合成例。実際の安定slugと直前に読んだrevisionへ置き換える。変更JSONは所有者専用で保持し、Gitへ含めない。createは未登録slugとexpected-revision 0を使用する。id/revisionを変更JSONへ入れない。

readはJSONを読むだけでなく、中断した受信済み操作の回復とSQLite投影を行う。厳密な読取り限定の確認には、整合した隔離コピーを使用する。古い会話やSQLiteの内容でJSONを上書きしない。

## 完了・確認応答

認証済みiPhoneの完了変更は、受信箱commit後にrevision一致を条件として自動適用する。正本保存・読戻し後に同じoperation IDへのapplied応答を返す。Mac受信だけでは適用完了としない。通常の手動applyは不要。

保存失敗はreceivedを保持する。次回取得・同じoperation IDの再送で回復する。正本commit後・DB確認応答前の中断も正本の適用記録から回復する。operation IDとpayloadを変えて同じ操作を作り直さない。

## 競合・復旧

- 競合は現行revisionと端末希望値を比較し、黙って上書き・rebaseしない。
- pendingがある同じタスクの編集を強行しない。受信・正本適用・確認応答・端末outboxを別々に確認する。
- 明示applyは復旧用。対象IDと保存状態を確認した上で、既存CLIのapplyを使用する。未確認の一括適用は行わない。
- 正本破損時にDBから正本を復元しない。[バックアップ手順](../../docs/dot-backup-recovery.md)に従って隔離検証する。
- 欠落行は削除指示ではない。削除連携・正本置換・端末初期化は通常操作に含めない。

端末への受信、通知予約、画面やWidgetの実描画はMacの保存成功だけでは証明できない。検証済み範囲は[現在地](../../docs/dot-task-integration.md#現在地未確認)を参照する。
