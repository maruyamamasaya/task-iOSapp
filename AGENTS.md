# CalendarTaskApp 開発契約

このファイルを最初に読み、設計の詳細が必要なときだけ `docs/architecture.md` と対象 Feature を確認すること。README より実コードを正とする。

## プロジェクトと現在地

CalendarTaskApp は、予定・タスク・日ごとのメモを一つの手帳として扱う iOS 17+ SwiftUI アプリ。現在は主要画面、編集、QuickAdd、通知、SwiftData 永続化、バックアップ、Widget / App Intent まで実装済みの基盤拡張フェーズであり、単なる InMemory プロトタイプではない。

## アーキテクチャ

基本の依存方向は `View → ViewModel → Store → Repository protocol → Data実装`。構築は `App/AppDependencies.swift` に集約する。

- `App`: エントリポイント、ルート Tab / Navigation、Composition Root。
- `Core`: 共有ドメインモデル、Repository protocol、Store、サービス、拡張、バックアップ。UI や具体的保存方式に依存させない。
- `Data`: SwiftData Entity / container、Repository の具体実装、テスト・Preview 用 InMemory 実装と SampleData。`Local` / `Remote` はデータソース境界。
- `Features`: Home / Calendar / Tasks / Settings と横断 UI フローの QuickAdd / Editing。画面固有の View・ViewModel・表示用型を置く。
- `DesignSystem`: 複数 Feature で再利用する見た目・スタイルのみ。
- `Utilities`: UI・ドメイン・保存方式のいずれにも属さない小さな汎用処理のみ。
- `Resources`: Asset Catalog、将来のローカライズ等。
- `CalendarTaskWidget`: WidgetKit UI、SwiftData 読み出し、タスク完了 App Intent。
- `CalendarTaskAppTests`: Repository、Store / Service、設定、QuickAdd、日付・繰り返し、バックアップ、Widget action の unit test。

主要モデルは `TaskItem`、`CalendarEvent`、`DailyNote`、`TaskCompletion`、`Project`。モデルを変更すると SwiftData Entity、変換、バックアップ、Widget、テストへの影響があるため、依頼なしに変更しない。

## 責務とデータフロー

- **View**: 状態の描画、入力、ナビゲーション、ユーザー操作の転送。Repository / ModelContext を生成・直接操作しない。
- **ViewModel** (`@MainActor`): 画面状態、フィルタ・並べ替え、画面操作の調停。永続化は Store に委譲する。
- **Store** (`@MainActor`, `ObservableObject`): Feature 間で共有するドメイン状態と更新操作。Repository を呼び、必要な通知同期・Widget refresh を調停する。
- **Repository protocol**: Core に置く保存契約。ドメイン値だけを受け渡し、SwiftData / CloudKit / EventKit の型を漏らさない。
- **Data実装**: Entity 変換、クエリ、保存など具体技術を閉じ込める。

本番は `AppDependencies.live()` が SwiftData Repository、通知、Widget refresh を注入する。テストでは同じ initializer に InMemory / spy / noop を渡す。View、ViewModel、Store 内で concrete dependency を勝手に生成しない。詳細は `docs/architecture.md` を参照。

## 追加・変更ルール

1. まず対象 Feature と隣接する Store / protocol だけを読む。
2. 画面固有コードは `Features/<Name>`、共有ドメイン契約は `Core`、具体的 I/O は `Data` に置く。二つ以上の Feature で実際に共有されるまで Core / DesignSystem に昇格させない。
3. 新しい外部依存は protocol を Core 側に置き、adapter を Data（または適切な target 境界）に置き、`AppDependencies` で注入する。
4. Home / Calendar からの作成・編集は既存の `Editing/UnifiedEditorFlow`、短文入力は `QuickAdd` を再利用し、類似フォームを増やさない。
5. async な保存後の再読込、通知の同期・削除、Widget timeline 更新という既存 Store の副作用を維持する。
6. 既存 public/internal API、モデル、保存 schema、画面遷移、文言・UI を依頼なしに変更しない。不要なファイル移動、全体整形、命名統一、レイヤー再編などの大規模リファクタリングは禁止。問題を発見してもスコープ外なら報告だけにする。
7. Widget とアプリが共有する Swift ファイルの target membership、および App Group / store URL を変更する場合は両 target を検証する。

## テストと完了条件

- ロジック変更には同じレイヤーの unit test を追加する。Repository は CRUD と変換、Store は状態と副作用、parser / date / recurrence は境界値をテストする。
- DI 可能性を保ち、テストで本番 SwiftData singleton、通知権限、WidgetCenter に依存させない。
- 実装後は最低限 `xcodebuild -project CalendarTaskApp.xcodeproj -scheme CalendarTaskApp -sdk iphonesimulator build` と `xcodebuild -project CalendarTaskApp.xcodeproj -scheme CalendarTaskApp -sdk iphonesimulator test` を実行する。変更対象が Widget なら Widget target も build する。
- UI変更時は Home / Calendar / Tasks / Settings、作成・編集・削除、QuickAdd、空状態とエラー状態を該当範囲で目視確認する。永続化変更時は再起動後の読込、移行、バックアップ、Widget共有を確認する。
- `git diff` でスコープ外変更がないことも確認する。

README は利用者が認識すべき機能・セットアップ・前提が変わる場合に更新する。`docs/architecture.md` は依存方向、レイヤー責務、DI、永続化や target 間共有の設計判断が変わる場合に更新する。実装詳細だけの変更でドキュメントを水増ししない。
