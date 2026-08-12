# CalendarTaskApp

## アプリ概要

カレンダーとタスク管理を統合した iOS アプリです。現在は、今後の機能追加を安全に行うためのベースプロジェクトです。

## 現在のフェーズ

基盤構築段階です。SwiftUI、MVVM、`NavigationStack`、`TabView`、Swift Concurrency を使い、外部 SDK や永続化には依存していません。

## アーキテクチャ

```text
View
  ↓ user action / observed state
ViewModel
  ↓ shared application state
Store
  ↓ persistence abstraction
Repository
  ↓
Data Source (currently in-memory SampleData)
```

依存関係は `AppDependencies` で組み立てます。View と ViewModel は具体的な保存実装を生成しません。

## フォルダ構成

- `CalendarTaskApp/App`: アプリのエントリポイント、ルート Tab、依存性注入。
- `CalendarTaskApp/Core`: Feature 間で共有するモデル、Repository protocol、Store、日付 Service。
- `CalendarTaskApp/Features`: Home / Calendar / Tasks / Settings ごとの View と ViewModel。
- `CalendarTaskApp/Data`: Repository の具体実装、分離可能なサンプルデータ。`Local` と `Remote` は将来実装の境界。
- `CalendarTaskApp/DesignSystem`: 複数 Feature で本当に共有する UI の配置先。
- `CalendarTaskApp/Utilities`: UI・ドメインに属さない小さな共通処理の配置先。
- `CalendarTaskApp/Resources`: Asset Catalog とローカライズリソース。
- `CalendarTaskAppTests`: Repository、ViewModel、日付処理の Unit Test。

## データフロー

起動時に `AppDependencies` が InMemory Repository を Store に注入します。各 ViewModel は Store を受け取り、非同期でロードや絞り込みを行います。View は公開された画面状態だけを描画します。

## 拡張ガイド

- **SwiftData**: `Data/Local/SwiftData` にモデル変換と Data Source、`Data/Repositories` に protocol 実装を追加し、`AppDependencies` の生成先だけを差し替えます。
- **CloudKit / Firebase**: `Data/Remote` に SDK 境界と Repository 実装を追加し、DI を差し替えます。View は変更しません。
- **EventKit**: `Core/Services` に抽象 protocol、`Data` に EventKit adapter を追加します。外部イベントは `externalEventID` で対応付けます。
- **UserNotifications**: Service protocol と実装を追加し、必要な Store / ViewModel に注入します。
- **WidgetKit / App Intents**: Core の値型と Repository 境界を共有し、独立した Target から利用します。
- **新しい Feature**: `Features/<Name>/Views` と `ViewModels` を作り、Feature 固有型はその配下に置きます。複数 Feature で必要になった概念だけ Core / DesignSystem に昇格させます。

## 今回含めないもの

Firebase、CloudKit、EventKit、UserNotifications、WidgetKit、App Intents、外部 API、本格的な永続化は意図的に未実装です。
