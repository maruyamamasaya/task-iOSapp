# Mac 検証メモ

記録日: 2026-09-14

今回追加したカレンダーの日表示とタグ管理機能は、Windows環境で実装したため、Xcodeでのビルド・テスト・Simulator目視確認が未実施。Mac上で後ほど確認する。

## ビルド

```sh
xcodebuild -project CalendarTaskApp.xcodeproj -scheme CalendarTaskApp -sdk iphonesimulator build
```

Widgetと共有するSwiftData schemaを変更しているため、Widget targetもビルドする。

## テスト

テスト前に `~/Library/Developer/XCTestDevices` の既存UUIDフォルダ一覧と容量を記録する。既存Simulatorを1台だけ使い、新規端末やランタイムは作成しない。

```sh
xcodebuild -project CalendarTaskApp.xcodeproj -scheme CalendarTaskApp -sdk iphonesimulator \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 test
```

テスト後、この実行で新規作成された `XCTestDevices` のUUIDフォルダだけを、Xcode・Simulator・テスト処理が終了していることを確認して削除する。以前から存在するデータやDerivedDataは削除しない。作成・削除したテスト端末数と、残っている容量を記録する。

## 日表示の目視確認

- カレンダーの切替が「月／週／日」になっている。
- 日表示の前後ボタンで1日ずつ移動し、「今日に戻る」が動作する。
- 終日予定、終日タスク、時間付き予定・タスク、時刻未設定タスクが正しく表示される。
- 今日では現在時刻表示が出て、別の日には出ない。
- 日別メモの表示・作成・編集・削除ができる。
- 日表示から予定・タスクの作成、編集、完了、日付変更、複製、削除、QuickAddが動作する。
- 空状態と保存エラー時の表示を確認する。
- 設定の初期表示を「日」にして再起動したとき、日表示で開く。

## タグ管理と永続化の確認

- 設定 → タグで作成、名前変更、削除ができる。
- タスク編集で複数タグを選択・解除できる。
- 保存後とアプリ再起動後にタグ割り当てが保持される。
- タグ名変更が割り当て済みタスクにも反映される。
- タグ削除時、既存タスクから該当タグだけが外れ、タスク自体は残る。
- 既存ストアを保持した状態で起動し、SwiftData schema移行が成功する。
- バックアップの書き出し・置換復元後に、タグ一覧とタスクのタグ割り当てが復元される。
- アプリとWidgetが同じApp Group storeを問題なく開ける。

検証後、このメモの結果を更新し、問題がなければ削除または完了記録へ移す。
