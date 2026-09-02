# CalendarTaskApp アーキテクチャ

## 1. 設計の目的

予定、タスク、日別メモというドメインを UI や保存技術から分離し、永続化・同期・OS framework・Widget を追加または交換しても Feature 層の変更を小さくする。README は利用者向け概要、ルートの `AGENTS.md` は日常の変更規約、本書は依存関係と現状実装の記録を担う。

## 2. レイヤーと依存方向

```text
View
  ↓ user action / observed screen state
ViewModel
  ↓ use-case operation / shared state
Store
  ↓ domain persistence contract
Repository protocol (Core)
  ↓ implemented by
Repository / Data Source (Data)
```

逆方向の依存は作らない。具体的には、Core は Features / Data / SwiftUI / SwiftData に依存せず、Feature は SwiftData Entity や `ModelContext` を知らない。Data は Core の protocol と domain model を実装・変換する。

### View

SwiftUI による描画、入力、sheet / navigation、操作の ViewModel への転送を担当する。Home と Calendar は `EditorRoute` / `EditorHostView` でタスク・予定・メモのフォームを統一し、`QuickAddView` から直接保存または編集 draft に遷移する。Tasks はタスク一覧とタスク編集、Settings は設定およびプロジェクト・バックアップ管理を提供する。

### ViewModel

`@MainActor` の画面状態を持ち、Store の共有状態を画面用に絞り込み・並べ替える。Home は選択日のタイムラインとメモ、Calendar は月・週・日表示、Tasks はセクション・検索・ソートを調停する。ViewModel は具体 Repository を知らず、保存結果や haptic など画面ユースケースをまとめる。

### Store

Repository をラップする共有 application state。ロードと CRUD 後の状態再取得に加え、Task / Calendar / TaskCompletion の更新時には通知と Widget refresh を調停する。`SettingsStore` は例外的に `UserDefaults` を直接境界として設定値を保持する。Store に画面レイアウトや特定画面だけの選択状態を入れない。

### Repository と Data Source

`Core/Repositories` の protocol は domain model の非同期 CRUD 契約である。`Data/Repositories/SwiftDataRepositories.swift` は domain と SwiftData Entity を変換し、`Data/Local/SwiftDataPersistence.swift` が schema と container / store URL を管理する。InMemory Repository は隔離された unit test や fixture 用であり、本番 DI では使われていない。

## 3. 現在の構成

`AppDependencies.live()` が次を一度だけ組み立て、`AppRootView` が各 ViewModel に必要な Store / Service を渡す。

- SwiftData: Task、CalendarEvent、DailyNote、TaskCompletion、Project の各 Repository。
- Store: Task、Calendar、DailyNote、TaskCompletion、Project、Settings。
- Service: system date、UserNotifications、haptic、Widget refresh、backup。
- Root UI: Today (Home)、Calendar、Tasks、Settings の四つの Tab と各 `NavigationStack`。

主要な書き込みは `View → ViewModel → Store → Repository` と進み、Repository が SwiftData を保存する。Store は成功後に通知を同期し、該当する操作では `WidgetCenter` の timeline reload を要求してから状態を再取得する。

## 4. モデルと永続化

- `TaskItem`: 日付、完了、優先度、通知、繰り返し、Project、category / tags を持つタスク。
- `CalendarEvent`: 開始・終了、終日、通知、繰り返し、Project、category、外部 event ID を持つ予定。
- `DailyNote`: 一日単位の本文。
- `TaskCompletion`: 繰り返しタスクの occurrence 単位の完了記録。
- `Project`: 色・icon と archive 状態を持つ分類。

現在の本番永続化は SwiftData。Settings は UserDefaults、バックアップは SwiftData domain data の JSON export / import を扱う。SwiftData Entity には現時点で Task の category / tags、CalendarEvent の category / externalEventID が保存されず、domain への復元時に空値になる。これらを永続化する変更は schema・移行・バックアップ・テストを伴う独立タスクとして扱う。

## 5. Widget / App Intent の共有

アプリと Widget は同じ `APP_GROUP_IDENTIFIER` を Info.plist から `SwiftDataPersistence` に渡し、利用可能なら App Group container 内の `CalendarTaskApp.store` を開く設計である。既存の標準 store がある場合は初回に関連ファイルを共有先へコピーする。なお、現在チェックインされているアプリ側 entitlement の App Group 配列は空で、Widget 側だけが build setting を参照している。実機で共有を成立させるには README の手順どおり両 target の capability / provisioning を揃える必要があり、この設定差はコード変更とは分けて確認する。

Widget の `WidgetDataProvider` は同じ Entity を読み、当日の予定と未完了タスクを生成する。対話的ボタンは `ToggleTaskCompletionIntent` から `WidgetTaskActionService` を呼び、通常タスクの完了状態または繰り返し occurrence の `TaskCompletion` を更新する。アプリ側 Store の書き込みは `WidgetRefreshService` を経由して timeline を更新する。共有 schema、App Group entitlement、target membership は一体として扱う。

## 6. 将来の adapter

- **CloudKit 等の同期**: Repository の裏側に remote/local coordination を実装する。競合解決や同期状態は Data に閉じ、必要な表示状態だけ Store 経由で公開する。
- **EventKit**: Core に用途を絞った service / repository protocol、Data に EventKit adapter と domain 変換を置く。Feature に `EKEvent` を渡さず、`externalEventID` を対応付けに使う。
- **UserNotifications**: 現在と同様に `NotificationService` 経由とし、Store が domain 更新との同期点を担う。
- **Widget / App Intents**: domain / persistence 契約を共有しつつ独立 target を保つ。AppIntent から Feature ViewModel を呼ばず、用途を限定した service を使う。
- **SwiftData schema 拡張**: domain model、Entity、mapping、migration、backup、Widget をまとめて設計し、Repository protocol が不要に保存技術へ寄らないようにする。

この境界を守れば、Composition Root と Data 実装を中心に変更し、Feature の表示・操作ロジックを維持できる。
