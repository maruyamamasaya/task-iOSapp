# CalendarTaskApp

カレンダー、タスク、日ごとのメモを一つの手帳として扱う iOS 17+ アプリです。SwiftUI で構築され、データは SwiftData に保存されます。

## 実装済みの主な機能

- **今日**: 選択日の予定・タスクをまとめたタイムライン、日別メモ、完了操作。
- **カレンダー**: 月・週・日表示、日付選択、予定・タスク・メモの確認と編集。
- **タスク**: セクション、検索、並べ替え、完了状態、繰り返し、優先度、プロジェクト分類。
- **統一編集フロー**: タスク・予定・メモの作成、編集、削除、未保存変更の確認。
- **QuickAdd**: 「明日 18:00 病院」「予定: 8/20 打ち合わせ」のような入力を解析し、プレビュー、即時保存、詳細編集へ接続。
- **設定**: 初期画面、カレンダー・タスク表示、作成時の既定値、QuickAdd、通知、外観、触覚フィードバック、プロジェクト、バックアップ。
- **通知と繰り返し**: UserNotifications によるリマインダーと occurrence 単位の繰り返しタスク完了管理。
- **Widget**: small / medium の「今日の手帳」で当日の予定・タスクを表示し、App Intent でタスクの完了を切り替え。

## 技術構成

```text
View → ViewModel → Store → Repository → SwiftData
```

依存関係は `AppDependencies` で組み立てます。本番は SwiftData、設定値は UserDefaults を利用し、テスト用に InMemory Repository と差し替え可能です。アプリと Widget は、両 target の署名設定を行ったうえで App Group の SwiftData store を共有する設計です。

主要ディレクトリは次のとおりです。

- `CalendarTaskApp/App`: 起動と依存性注入、ルート UI。
- `CalendarTaskApp/Core`: モデル、Repository 契約、Store、Service、バックアップ。
- `CalendarTaskApp/Data`: SwiftData と Repository 実装、InMemory 実装、SampleData。
- `CalendarTaskApp/Features`: Home / Calendar / Tasks / Settings / QuickAdd / Editing。
- `CalendarTaskApp/DesignSystem`, `Utilities`, `Resources`: 共有スタイル、汎用処理、Asset。
- `CalendarTaskWidget`: Widget と App Intent。
- `CalendarTaskAppTests`: unit test。

## 開発者向け情報

Xcode で `CalendarTaskApp.xcodeproj` を開き、`CalendarTaskApp` scheme を実行してください。Widget を端末で利用する場合は、アプリと Widget の両 target で同じ App Group を有効にし、署名設定に合う `APP_GROUP_IDENTIFIER` を指定する必要があります。詳細は `CalendarTaskWidget/README.md` を参照してください。

設計規約と変更手順は最初に [`AGENTS.md`](AGENTS.md) を読み、詳しい依存関係は [`docs/architecture.md`](docs/architecture.md) を参照してください。
