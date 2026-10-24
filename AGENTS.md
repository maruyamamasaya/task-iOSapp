# CalendarTaskApp 開発契約

このファイルを最初に読み、設計の詳細が必要なときだけ `docs/architecture.md` と対象 Feature を確認すること。README より実コードを正とする。

## プロジェクトと現在地

CalendarTaskApp は、予定・タスク・日ごとのメモを一つの手帳として扱う iOS 17+ SwiftUI アプリ。現在は主要画面、編集、QuickAdd、通知、SwiftData 永続化、バックアップ、Widget / App Intent まで実装済みの基盤拡張フェーズであり、単なる InMemory プロトタイプではない。

## 外部サービスの利用方針

このプロジェクトでは現在の実装・今後の設計の双方で Supabase を使用せず、新規導入・外部連携・データ移行の候補からも除外する。端末内保存や JSON を優先する。既存依存を発見した場合は、対象と依存内容を報告し、ユーザーが指示した範囲で置き換える。既存の外部リソース・データは、削除・変更の明示的な指示なしに操作しない。

## Dotタスクの正本（2026-10-21）

Dotタスクを作成・更新する前に、必ず [docs/dot-task-integration.md](docs/dot-task-integration.md) の「タスクデータ作成・更新の共通手順」を読むこと。詳細ルールは同文書に集約する。

ユーザー指示により、Dotタスクの正本は Mac の `~/Library/Application Support/CalendarTaskApp/DotLocalRelay/state/tasks.json` とする。Dotからの参照・作成・更新は `Integrations/DotLocalBridge/canonical_tasks.py` を使用し、操作前に最新revisionを読む。SQLiteは配信用投影と受信箱であり、Web/D1や古いJSONから正本を上書きしない。直接JSON/DB編集は禁止。iPhone受信は適用と区別し、認証済み本人の完了操作はrevision一致時に受信箱へ永続保存した後、正本更新・読戻し・確認応答まで自動実行する。競合は上書きせず、保存失敗は受信箱に保持して同じoperation IDで再試行する。明示applyは復旧用に残す。現在地・優先課題は `docs/dot-task-integration.md`、操作手順は `Integrations/DotLocalBridge/CANONICAL-SOURCE.md` を参照。Dotチャットの実際の採用は別途確認する。

## タスク管理の責務

本人は追加依頼を中心に行い、追加後の分類・関連/重複候補整理・優先順位・無理のない仮配分・進捗/見通し管理はdotが担う。アプリは手帳として予定確認と完了が中心。追加保存だけで終了せず、[共通手順](docs/dot-task-integration.md)の管理・照合まで実施する。固定期限・明示予定・完了/ID/履歴を守り、本文の購入/予約/送信は管理依頼から実行しない。

## Dotのひとこと

本人がDotチャットで見通し・振り返りの生成を頼んだ場合は、[Integrations/DotLocalBridge/DAILY-BRIEF.md](Integrations/DotLocalBridge/DAILY-BRIEF.md) の手順でアプリ受信材料を読み、生成文を正規CLIで保存・読戻しする。未受信・古い材料や未導入を生成/実機反映済みと扱わない。タスク正本と既存メモは変更しない。 会話らしい音声原稿の責務は同手順の「会話らしい音声原稿の責務」を正とし、dotが意味と原稿、NarrationStudioが対応済みの声の表現、アプリが保存・通知・再生を担当する。

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
- 実装後は最低限 `xcodebuild -project CalendarTaskApp.xcodeproj -scheme CalendarTaskApp -sdk iphonesimulator -destination 'platform=iOS Simulator,id=EB3A49ED-6553-4D7E-B933-387951643EAB' build` を実行する。変更内容の確認にビルドだけで十分なら `xcodebuild test` は実行しない。変更対象が Widget なら Widget target も同じ destination で build する。
- UI変更時は Home / Calendar / Tasks / Settings、作成・編集・削除、QuickAdd、空状態とエラー状態を該当範囲で目視確認する。永続化変更時は再起動後の読込、移行、バックアップ、Widget共有を確認する。
- `git diff` でスコープ外変更がないことも確認する。

実機オフライン操作は毎回の更新条件にしない。同期/outbox/再送/競合の実質変更や関連不具合時の回帰範囲は `docs/dot-task-integration.md` の現行運用に従う。

### このMacでの開発端末の固定（2026-10-23）

- iOSアプリのシミュレータービルド・起動・テストは、既存の **iPhone 17e / iOS 26.5 / UDID `EB3A49ED-6553-4D7E-B933-387951643EAB`** に統一する。
- `xcodebuild` では常に `-destination 'platform=iOS Simulator,id=EB3A49ED-6553-4D7E-B933-387951643EAB'` を指定する。`simctl` による起動・インストール・実行でもこのUDIDを明示し、`booted` や端末名だけによる暗黙の選択は避ける。
- 実行前に既存端末とランタイムの利用可否を確認する。指定端末が見つからない、利用できない、またはXcode・プロジェクトとの互換性に問題がある場合は、代替端末を作成・選択せず、理由と必要な対応を報告する。
- 別のシミュレーター端末の作成・複製、およびOSランタイムの追加・更新を自動で行わない。並列テストによる端末の複製も避ける。
- 実機確認が必要な場合は、接続されている **iPhone 12 mini・iPhone 13・iPhone 17e** を利用する。実際の接続先を確認して指定し、利用できない場合は報告する。
- 既存シミュレーター内のアプリやテストデータは、明示的な依頼なく初期化・削除しない。端末のerase・削除やアプリのアンインストールを、検証や不具合回避のために自動実行しない。

### Xcode のストレージ管理

- テストが必要な場合は、上記UDIDの既存Simulatorを1台だけ使用する。新しいSimulator、テスト端末、ランタイムを自動で作成・ダウンロードしない。
- テストでは並列実行を無効にし、`-parallel-testing-enabled NO` と `-maximum-parallel-testing-workers 1` を指定する。同じテストを理由なく繰り返さない。
- テスト開始前に `~/Library/Developer/XCTestDevices` の既存フォルダ一覧と容量を記録する。
- テスト完了後、そのタスクによって新規作成された `XCTestDevices` 内の UUID フォルダだけを削除する。以前から存在するデータは削除しない。
- Xcode、Simulator、またはテスト処理が実行中の場合は削除せず、状況を報告する。
- DerivedData など、ほかの Xcode データを削除する場合は事前にユーザーへ確認を求める。
- 最後に、作成・削除したテスト端末の数と、`XCTestDevices` に残っている容量を報告する。

README は利用者が認識すべき機能・セットアップ・前提が変わる場合に更新する。`docs/architecture.md` は依存方向、レイヤー責務、DI、永続化や target 間共有の設計判断が変わる場合に更新する。実装詳細だけの変更でドキュメントを水増ししない。
