# Local data sources

SwiftData など、端末内の永続化実装をここに追加します。Core の Repository protocol に準拠させます。

## Project / Tag

Project は TaskItem / CalendarEvent が `projectID` を0または1件保持し、系列元だけに保存します。繰り返しOccurrenceは元項目のProjectを参照し、複製しません。

将来のTagは Project と分離し、`Tag(id, name, colorIdentifier)` と Task/CalendarEvent の中間エンティティによる多対多（0...n）として追加します。Quick Addは名前解決用の抽象層を介し、ParserをSwiftDataモデルへ直接依存させません。
